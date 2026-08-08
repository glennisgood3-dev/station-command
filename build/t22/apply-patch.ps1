#requires -Version 5.1
<#
.SYNOPSIS
    T-22：程式碼 patch 落地套用腳本。手動階段站 4 程式產出的唯一落地路徑。

.DESCRIPTION
    讀佇列檔（與 T-21 apply-queue.ps1 共用同一份 queue.json，格式見 build/t21/queue-format.md），
    只處理 action == "apply-patch" 的項目，其餘項目原樣保留、原樣寫回（留給 T-21 apply-queue.ps1
    處理）。詳細設計理由與流程見同目錄 patch-format.md。

    每筆流程（patch-format.md §4）：
      ① schema 驗證 → ② sha256 完整性核對 → ③ worktree 合法性檢查 →
      ④ 反向乾跑（冪等判準）：已達成 ⇒ SKIPPED-ALREADY-APPLIED，出列 →
      ⑤ 正向乾跑：失敗 ⇒ FAILED-CONFLICT，留佇列具名回報（含行尾差異診斷提示）→
      ⑥ 真套用（無 --reject/--3way/--index，git 內建 all-or-nothing）→
      ⑦ 回驗（再跑一次反向乾跑）：成功 ⇒ APPLIED-VERIFIED，出列＋寫 applied-patches.log；
        不成功 ⇒ FAILED-VERIFY，留佇列具名回報，🚫 不得標記已套用。

    本型套用全程**不連 GitHub**、**不覆寫 core.autocrlf**（理由見 patch-format.md §8）、
    **不自動 commit／push**（不可逆動作聲明：無）。

.PARAMETER QueuePath
    佇列檔路徑。預設與本腳本同目錄的 queue.json（與 T-21 共用同一份檔案）。

.PARAMETER AppliedLogPath
    落地紀錄檔路徑，供交付判定使用（patch-format.md §6）。預設與本腳本同目錄的 applied-patches.log。

.PARAMETER SkipDryRunCheck
    ⚠️ 紅燈驗證專用實驗開關（比照 T-21 -SkipIdempotencyCheck 先例）。開啟後跳過套用前正向乾跑，
    改用 `git apply --reject` 直接嘗試套用——對必然衝突的 patch 會產生「部分檔案真的被改掉、
    衝突檔案留下 .rej」的半套殘局。**僅供 t22-test.ps1 紅燈驗證使用，正式流程與一般手動套用
    絕對不得開啟**。詳見 patch-format.md §9。

.EXAMPLE
    .\apply-patch.ps1
.EXAMPLE
    .\apply-patch.ps1 -QueuePath 'G:\default mount\station-command-queue.json'
.EXAMPLE
    .\apply-patch.ps1 -SkipDryRunCheck   # 僅供紅燈驗證，勿在正式流程使用
#>

[CmdletBinding()]
param(
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [string]$AppliedLogPath = (Join-Path $PSScriptRoot 'applied-patches.log'),
    [switch]$SkipDryRunCheck
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'patch-common.ps1')
Set-ConsoleUtf8

if (-not (Test-GitAvailable)) {
    throw "找不到 git 執行檔（不在 PATH 內）。apply-patch.ps1 全程依賴本機 git 指令，請先安裝 git 並確認 'git' 可在此 shell 直接執行。"
}

if ($SkipDryRunCheck) {
    Write-Warning "⚠️⚠️⚠️ -SkipDryRunCheck 已開啟：本次執行跳過套用前正向乾跑，改用 --reject 直接嘗試套用。"
    Write-Warning "         必然衝突的 patch 在此模式下會產生半套殘局（部分檔案被改、衝突檔案留 .rej）。"
    Write-Warning "         此為 T-22 紅燈驗證專用開關，正式流程與一般手動套用絕對不得使用。"
}

$QueueDir = Split-Path -Path $QueuePath -Parent
if ([string]::IsNullOrEmpty($QueueDir)) { $QueueDir = '.' }

$reportLines = @("apply-patch 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "佇列檔：$QueuePath", "")

$Items = Read-QueueFile -QueuePath $QueuePath

if ($null -eq $Items) {
    $msg = "待寫佇列不存在，本批程式碼落地動作將重新產生（佇列檔路徑：$QueuePath）。目標工作區既有內容不受影響。"
    Write-Host $msg
    $reportLines += $msg
    Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'apply-patch-report.txt') -Content ($reportLines -join [Environment]::NewLine)
    exit 0
}

$Items = @($Items)

if ($Items.Count -eq 0) {
    $msg = "佇列檔存在但無任何待寫項目（空陣列），無事可做。"
    Write-Host $msg
    $reportLines += $msg
    Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'apply-patch-report.txt') -Content ($reportLines -join [Environment]::NewLine)
    exit 0
}

$outputItems = New-Object System.Collections.ArrayList
$statusRows = @()
$hadFailure = $false
$mineCount = 0

foreach ($item in $Items) {
    if (-not ($item.PSObject.Properties.Name -contains 'action') -or $item.action -ne 'apply-patch') {
        # 不是本腳本認得的動作型別：原樣保留、原樣通過，不觸碰、不重排（見 patch-format.md §1）
        [void]$outputItems.Add($item)
        continue
    }

    $mineCount++
    $srcLabel = if ($item.PSObject.Properties.Name -contains 'source') { $item.source } else { '(未知來源)' }

    # ① schema 驗證
    $schemaCheck = Test-ApplyPatchItemSchema -Item $item
    if (-not $schemaCheck.Valid) {
        $status = 'FAILED-SCHEMA'
        $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = $schemaCheck.Detail }
        Write-Host ("[{0,-24}] {1} — {2}" -f $status, $srcLabel, $schemaCheck.Detail)
        [void]$outputItems.Add($item)
        $hadFailure = $true
        continue
    }

    $worktree = $item.target.worktree
    $patchFileRel = $item.payload.patchFile
    $patchFileAbs = Join-Path $QueueDir $patchFileRel
    $targetLabel = "$($item.target.repo) @ $worktree"

    # ② patch 檔存在性 + sha256 完整性核對
    if (-not (Test-Path -LiteralPath $patchFileAbs -PathType Leaf)) {
        $status = 'FAILED-MISSING-PATCH-FILE'
        $detail = "patch 檔不存在：$patchFileAbs（payload.patchFile='$patchFileRel'，相對於佇列檔目錄 '$QueueDir'）"
        $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = $detail }
        Write-Host ("[{0,-24}] {1} | {2} — {3}" -f $status, $targetLabel, $srcLabel, $detail)
        [void]$outputItems.Add($item)
        $hadFailure = $true
        continue
    }

    $actualSha = Get-FileSha256Hex -Path $patchFileAbs
    if ($actualSha -ne $item.payload.sha256.ToLowerInvariant()) {
        $status = 'FAILED-INTEGRITY'
        $detail = "sha256 不符：期望 $($item.payload.sha256)，實際 $actualSha（patch 檔可能已被覆寫或傳輸不完整）"
        $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = $detail }
        Write-Host ("[{0,-24}] {1} | {2} — {3}" -f $status, $targetLabel, $srcLabel, $detail)
        [void]$outputItems.Add($item)
        $hadFailure = $true
        continue
    }

    # ③ worktree 合法性
    $worktreeCheck = Test-WorktreeValid -Worktree $worktree
    if (-not $worktreeCheck.Valid) {
        $status = 'FAILED-WORKTREE'
        $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = $worktreeCheck.Detail }
        Write-Host ("[{0,-24}] {1} | {2} — {3}" -f $status, $targetLabel, $srcLabel, $worktreeCheck.Detail)
        [void]$outputItems.Add($item)
        $hadFailure = $true
        continue
    }

    # best-effort repo 核對（不擋下，僅警示）
    $repoMatch = Test-WorktreeRepoMatches -Worktree $worktree -ExpectedRepo $item.target.repo
    if (-not $repoMatch.Matches) {
        Write-Warning $repoMatch.Detail
    }

    try {
        # ④ 反向乾跑（冪等判準）
        $already = Test-PatchAlreadyApplied -Worktree $worktree -PatchFile $patchFileAbs
        if ($already.AlreadyApplied) {
            $status = 'SKIPPED-ALREADY-APPLIED'
            $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = '工作區現況已符合 patch 宣告的目標內容（反向乾跑成功）' }
            Write-Host ("[{0,-24}] {1} | {2} — 工作區現況已符合 patch 宣告的目標內容" -f $status, $targetLabel, $srcLabel)
            Add-AppliedPatchLogEntry -LogPath $AppliedLogPath -Status $status -Source $srcLabel -Worktree $worktree -PatchFile $patchFileRel
            continue
        }

        if ($SkipDryRunCheck) {
            # ⚠️ 紅燈驗證專用路徑：跳過正向乾跑，直接魯莽套用（見 patch-format.md §9）
            $applyResult = Invoke-PatchApplyReckless -Worktree $worktree -PatchFile $patchFileAbs
            $rejCheck = Test-WorktreeHasRejectArtifacts -Worktree $worktree
            $filesList = if ($item.payload.PSObject.Properties.Name -contains 'files') { @($item.payload.files) } else { @() }
            $markerCheck = Test-WorktreeHasConflictMarkers -Worktree $worktree -Files $filesList
            if ($rejCheck.HasRejects -or $markerCheck.HasMarkers) {
                $status = 'FAILED-PARTIAL-APPLY'
                $rejNames = ($rejCheck.Files | ForEach-Object { $_.FullName }) -join '; '
                $detail = "⚠️ SkipDryRunCheck 模式偵測到半套殘留：.rej 檔=[$rejNames]；衝突標記檔=[$($markerCheck.Files -join ', ')]。工作區可能已部分被改動，本腳本不自動復原，請人工檢查 $worktree。"
                $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = $detail }
                Write-Host ("[{0,-24}] {1} | {2} — {3}" -f $status, $targetLabel, $srcLabel, $detail)
                [void]$outputItems.Add($item)
                $hadFailure = $true
                continue
            }
            # 理論上 --reject 模式若剛好完全乾淨套用（無衝突），視同正常套用成功，走下方共用回驗
        } else {
            # ⑤ 正向乾跑
            $applicable = Test-PatchAppliesCleanly -Worktree $worktree -PatchFile $patchFileAbs
            if (-not $applicable.Applicable) {
                $status = 'FAILED-CONFLICT'
                $hint = ''
                if (Test-ConflictLooksLikeLineEndingOnly -Worktree $worktree -PatchFile $patchFileAbs) {
                    $hint = " ⚠️ 可能為行尾（CRLF/LF）差異導致，而非實質內容衝突（診斷用 --ignore-whitespace 乾跑成功；本腳本不會自動採用該旗標套用，理由見 patch-format.md §8）。"
                }
                $detail = "套用前正向乾跑失敗，🚫 未寫入任何內容，留在佇列：$($applicable.Detail)$hint"
                $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = $detail }
                Write-Host ("[{0,-24}] {1} | {2} — {3}" -f $status, $targetLabel, $srcLabel, $detail)
                [void]$outputItems.Add($item)
                $hadFailure = $true
                continue
            }

            # ⑥ 真套用（安全預設，all-or-nothing）
            $applyResult = Invoke-PatchApply -Worktree $worktree -PatchFile $patchFileAbs
            if ($applyResult.ExitCode -ne 0) {
                $status = 'FAILED-APPLY'
                $detail = "乾跑通過但實際套用失敗（不應發生，具名回報供人工複查）：$($applyResult.Output)"
                $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = $detail }
                Write-Host ("[{0,-24}] {1} | {2} — {3}" -f $status, $targetLabel, $srcLabel, $detail)
                [void]$outputItems.Add($item)
                $hadFailure = $true
                continue
            }
        }

        # ⑦ 回驗（正常路徑與 SkipDryRunCheck 乾淨套用路徑共用）
        $verify = Test-PatchAlreadyApplied -Worktree $worktree -PatchFile $patchFileAbs
        if ($verify.AlreadyApplied) {
            $status = 'APPLIED-VERIFIED'
            $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = '套用後回驗：反向乾跑成功，工作區內容與 patch 宣告目標相符' }
            Write-Host ("[{0,-24}] {1} | {2} — 套用後回驗通過" -f $status, $targetLabel, $srcLabel)
            Add-AppliedPatchLogEntry -LogPath $AppliedLogPath -Status $status -Source $srcLabel -Worktree $worktree -PatchFile $patchFileRel
        } else {
            $status = 'FAILED-VERIFY'
            $detail = "套用後回驗不符，留在佇列，🚫 不得標記已套用：$($verify.Detail)"
            $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = $detail }
            Write-Host ("[{0,-24}] {1} | {2} — {3}" -f $status, $targetLabel, $srcLabel, $detail)
            [void]$outputItems.Add($item)
            $hadFailure = $true
        }
    }
    catch {
        $status = 'FAILED-APPLY'
        $detail = $_.Exception.Message
        $statusRows += [pscustomobject]@{ Status = $status; Source = $srcLabel; Detail = $detail }
        Write-Host ("[{0,-24}] {1} | {2} — {3}" -f $status, $targetLabel, $srcLabel, $detail)
        [void]$outputItems.Add($item)
        $hadFailure = $true
    }
}

# --- 寫回佇列檔：非本型項目原樣保留＋本型未出列項目，順序不變 ---
Write-QueueFile -QueuePath $QueuePath -Items @($outputItems)

# --- 報告 ---
$reportLines += "本輪處理 apply-patch 型項目：$mineCount 筆（其餘型別項目原樣通過，交由 apply-queue.ps1 處理）"
$reportLines += ($statusRows | ForEach-Object { "[{0,-24}] {1} — {2}" -f $_.Status, $_.Source, $_.Detail })
$reportLines += ""
$remainingMine = @(@($outputItems) | Where-Object { $_.PSObject.Properties.Name -contains 'action' -and $_.action -eq 'apply-patch' })
$summary = "共處理 {0} 筆 apply-patch 項目：APPLIED-VERIFIED={1} SKIPPED-ALREADY-APPLIED={2} FAILED-CONFLICT={3} FAILED-VERIFY={4} FAILED-APPLY={5} FAILED-INTEGRITY={6} FAILED-WORKTREE={7} FAILED-MISSING-PATCH-FILE={8} FAILED-SCHEMA={9} FAILED-PARTIAL-APPLY={10}；剩餘於佇列：{11} 筆" -f `
    $mineCount, `
    (@($statusRows | Where-Object Status -eq 'APPLIED-VERIFIED')).Count, `
    (@($statusRows | Where-Object Status -eq 'SKIPPED-ALREADY-APPLIED')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-CONFLICT')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-VERIFY')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-APPLY')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-INTEGRITY')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-WORKTREE')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-MISSING-PATCH-FILE')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-SCHEMA')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-PARTIAL-APPLY')).Count, `
    $remainingMine.Count
$reportLines += $summary
Write-Host $summary

$reportPath = Join-Path $PSScriptRoot 'apply-patch-report.txt'
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($hadFailure) { exit 1 }
exit 0
