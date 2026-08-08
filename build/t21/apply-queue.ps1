#requires -Version 5.1
<#
.SYNOPSIS
    T-21：待寫佇列套用腳本——手動階段的唯一寫入路徑。

.DESCRIPTION
    讀 PAT、讀佇列檔（queue-format.md 定義的四欄格式）。
    每筆套用前先讀 GitHub 現況比對（冪等，§4.6：不設動作指紋，只看目標現在的實際狀態）：
      - 已達成 payload 所述狀態 ⇒ 跳過並出列（SKIPPED-ALREADY-SATISFIED）
      - 未達成 ⇒ 套用 → 回驗（issues API 直讀，非 search）→ 相符才出列（APPLIED-VERIFIED），
        不符則留在佇列並具名回報（FAILED-VERIFY），🚫 不得標記為已套用
    送出前逐筆檢查 payload 內任何 description 欄位 ≤100 字元（今日實測 114 字元回 422），
    超過即擋下（FAILED-VALIDATION，不送出 API 呼叫）。
    佇列檔不存在 ⇒ 具名輸出「待寫佇列不存在，本批動作將重新產生」，正常結束（exit 0，非錯誤）。

.PARAMETER PatPath
    PAT 檔案路徑（純文字檔，內容即 token）。預設 G:\default mount\station_command-key。

.PARAMETER QueuePath
    佇列檔路徑。預設與本腳本同目錄的 queue.json。

.PARAMETER SkipIdempotencyCheck
    ⚠️ 紅燈驗證專用實驗開關（rework，站 4 verifier 回饋）。開啟後跳過「套用前讀現況比對」，
    每筆一律直接送出寫入 API，即使目標已達成 payload 所述狀態也會再寫一次。
    **僅供 T-21 驗收動態紅燈使用（t21-dynamic-test.ps1 的 RED 段落）；正式流程與一般手動套用
    絕對不得開啟**——開啟後 comment 型會真的重複貼留言，set-labels／close-issue 因寫入本身是
    冪等操作（PUT 整包覆蓋／PATCH 設定值）不會壞掉，但仍違反 §4.6「套用前先讀現況比對」硬規則。
    預設 $false。

.EXAMPLE
    .\apply-queue.ps1
.EXAMPLE
    .\apply-queue.ps1 -QueuePath 'G:\default mount\station-command-queue.json'
.EXAMPLE
    .\apply-queue.ps1 -SkipIdempotencyCheck   # 僅供紅燈驗證，勿在正式流程使用
#>

[CmdletBinding()]
param(
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [switch]$SkipIdempotencyCheck
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'queue-common.ps1')
Set-ConsoleUtf8

if ($SkipIdempotencyCheck) {
    Write-Warning "⚠️⚠️⚠️ -SkipIdempotencyCheck 已開啟：本次執行跳過套用前現況比對，每筆一律直接寫入。"
    Write-Warning "         此為 T-21 紅燈驗證專用開關，正式流程與一般手動套用絕對不得使用。"
}

# --- 讀 PAT（PAT 缺漏是真正的錯誤，非「佇列不存在」的合法降級，故照樣 throw） ---
$Token = Read-PatToken -PatPath $PatPath
$Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t21-apply-queue'

# --- 讀佇列檔 ---
$Items = Read-QueueFile -QueuePath $QueuePath

$reportLines = @("apply-queue 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "佇列檔：$QueuePath", "")

if ($null -eq $Items) {
    $msg = "待寫佇列不存在，本批動作將重新產生（佇列檔路徑：$QueuePath）。GitHub 既有狀態不受影響。"
    Write-Host $msg
    $reportLines += $msg
    Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'apply-queue-report.txt') -Content ($reportLines -join [Environment]::NewLine)
    exit 0
}

# rework：Read-QueueFile 內部已用逗號運算子保住陣列型別，這裡再 @() 包一層是防禦性
# 重複保險——即使佇列檔剛好只有 1 筆（ConvertFrom-Json 或函式邊界仍可能把陣列解卷成
# 純量），確保 $Items 在此之後一律是「保證可 .Count／可 foreach」的陣列。
$Items = @($Items)

if ($Items.Count -eq 0) {
    $msg = "佇列檔存在但無任何待寫項目（空陣列），無事可做。"
    Write-Host $msg
    $reportLines += $msg
    Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'apply-queue-report.txt') -Content ($reportLines -join [Environment]::NewLine)
    exit 0
}

# --- 寫入端點 ---
function Invoke-SetLabelsWrite {
    param($Repo, $IssueNumber, $Labels, $Headers)
    $url = "https://api.github.com/repos/$($Repo.Owner)/$($Repo.Repo)/issues/$IssueNumber/labels"
    $body = @{ labels = $Labels } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $url -Headers $Headers -Method Put -Body $body -ContentType 'application/json; charset=utf-8' | Out-Null
}

function Invoke-CloseIssueWrite {
    param($Repo, $IssueNumber, $Payload, $Headers)
    $url = "https://api.github.com/repos/$($Repo.Owner)/$($Repo.Repo)/issues/$IssueNumber"
    $bodyObj = @{ state = $Payload.state }
    if ($Payload.PSObject.Properties.Name -contains 'state_reason' -and $Payload.state_reason) {
        $bodyObj['state_reason'] = $Payload.state_reason
    }
    $body = $bodyObj | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $url -Headers $Headers -Method Patch -Body $body -ContentType 'application/json; charset=utf-8' | Out-Null
}

function Invoke-CommentWrite {
    param($Repo, $IssueNumber, $Body, $Headers)
    $url = "https://api.github.com/repos/$($Repo.Owner)/$($Repo.Repo)/issues/$IssueNumber/comments"
    $bodyJson = @{ body = $Body } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $url -Headers $Headers -Method Post -Body $bodyJson -ContentType 'application/json; charset=utf-8' | Out-Null
}

function Invoke-CreateIssueWrite {
    param($Repo, $Payload, $Headers)
    $url = "https://api.github.com/repos/$($Repo.Owner)/$($Repo.Repo)/issues"
    $bodyObj = @{ title = $Payload.title; body = $Payload.body }
    if ($Payload.PSObject.Properties.Name -contains 'labels' -and $Payload.labels) { $bodyObj['labels'] = $Payload.labels }
    if ($Payload.PSObject.Properties.Name -contains 'milestone' -and $Payload.milestone) { $bodyObj['milestone'] = $Payload.milestone }
    $body = $bodyObj | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $url -Headers $Headers -Method Post -Body $body -ContentType 'application/json; charset=utf-8' | Out-Null
}

function Invoke-CreateMilestoneWrite {
    param($Repo, $Payload, $Headers)
    $url = "https://api.github.com/repos/$($Repo.Owner)/$($Repo.Repo)/milestones"
    $bodyObj = @{ title = $Payload.title }
    if ($Payload.PSObject.Properties.Name -contains 'description' -and $Payload.description) { $bodyObj['description'] = $Payload.description }
    $body = $bodyObj | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $url -Headers $Headers -Method Post -Body $body -ContentType 'application/json; charset=utf-8' | Out-Null
}

$remaining = New-Object System.Collections.ArrayList
$statusRows = @()
$hadFailure = $false

foreach ($item in $Items) {
    $srcLabel = if ($item.PSObject.Properties.Name -contains 'source') { $item.source } else { '(未知來源)' }
    $actionLabel = if ($item.PSObject.Properties.Name -contains 'action') { $item.action } else { '(未知動作)' }
    $targetLabel = try { "$($item.target.repo)#$($item.target.issue)" } catch { '(目標解析失敗)' }

    # ① schema 驗證
    $schemaCheck = Test-ItemSchema -Item $item
    if (-not $schemaCheck.Valid) {
        $status = 'FAILED-SCHEMA'
        $detail = $schemaCheck.Detail
        $statusRows += [pscustomobject]@{ Status = $status; Action = $actionLabel; Target = $targetLabel; Source = $srcLabel; Detail = $detail }
        Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $actionLabel, $targetLabel, $srcLabel, $detail)
        [void]$remaining.Add($item)
        $hadFailure = $true
        continue
    }

    # ② description ≤100 字元守門（今日實測 114 字元回 422）
    # rework：@() 防禦性包裝——恰好 1 筆違規時避免函式邊界解卷成純量導致 .Count 出錯。
    $violations = Get-DescriptionLengthViolations -Payload $item.payload
    # rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
    # 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
    $violations = @($violations)
    if ($violations.Count -gt 0) {
        $status = 'FAILED-VALIDATION'
        $detailParts = $violations | ForEach-Object { "$($_.Path) 長度 $($_.Length) 字元（上限 100）" }
        $detail = "description 逾長，已擋下不送出 API：" + ($detailParts -join '；')
        $statusRows += [pscustomobject]@{ Status = $status; Action = $actionLabel; Target = $targetLabel; Source = $srcLabel; Detail = $detail }
        Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $actionLabel, $targetLabel, $srcLabel, $detail)
        [void]$remaining.Add($item)
        $hadFailure = $true
        continue
    }

    try {
        # ③ 套用前讀現況比對（冪等）—— -SkipIdempotencyCheck 開啟時刻意跳過本段（紅燈驗證專用）
        if ($SkipIdempotencyCheck) {
            $pre = [pscustomobject]@{ Satisfied = $false; Detail = '⚠️ SkipIdempotencyCheck 開啟，已略過套用前現況比對（紅燈驗證專用，正式流程不得使用）' }
        } else {
            $pre = Test-ItemSatisfied -Item $item -Headers $Headers
        }
        if ($pre.Satisfied) {
            $status = 'SKIPPED-ALREADY-SATISFIED'
            $statusRows += [pscustomobject]@{ Status = $status; Action = $actionLabel; Target = $targetLabel; Source = $srcLabel; Detail = $pre.Detail }
            Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $actionLabel, $targetLabel, $srcLabel, $pre.Detail)
            # 已達成 ⇒ 出列（不加入 remaining）
            continue
        }

        # ④ 未達成 ⇒ 套用
        $repo = Split-RepoString -RepoString $item.target.repo
        switch ($item.action) {
            'set-labels'       { Invoke-SetLabelsWrite   -Repo $repo -IssueNumber ([int]$item.target.issue) -Labels $item.payload.labels -Headers $Headers }
            'close-issue'      { Invoke-CloseIssueWrite  -Repo $repo -IssueNumber ([int]$item.target.issue) -Payload $item.payload -Headers $Headers }
            'comment'          { Invoke-CommentWrite     -Repo $repo -IssueNumber ([int]$item.target.issue) -Body $item.payload.body -Headers $Headers }
            'create-issue'     { Invoke-CreateIssueWrite -Repo $repo -Payload $item.payload -Headers $Headers }
            'create-milestone' { Invoke-CreateMilestoneWrite -Repo $repo -Payload $item.payload -Headers $Headers }
        }

        # ⑤ 回驗（issues API 直讀，非 search）
        $post = Test-ItemSatisfied -Item $item -Headers $Headers
        if ($post.Satisfied) {
            $status = 'APPLIED-VERIFIED'
            $statusRows += [pscustomobject]@{ Status = $status; Action = $actionLabel; Target = $targetLabel; Source = $srcLabel; Detail = $post.Detail }
            Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $actionLabel, $targetLabel, $srcLabel, $post.Detail)
            # 相符 ⇒ 出列
        } else {
            $status = 'FAILED-VERIFY'
            $detail = "套用後回驗不符，留在佇列：$($post.Detail)"
            $statusRows += [pscustomobject]@{ Status = $status; Action = $actionLabel; Target = $targetLabel; Source = $srcLabel; Detail = $detail }
            Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $actionLabel, $targetLabel, $srcLabel, $detail)
            [void]$remaining.Add($item)
            $hadFailure = $true
        }
    }
    catch {
        $status = 'FAILED-APPLY'
        $detail = $_.Exception.Message
        $statusRows += [pscustomobject]@{ Status = $status; Action = $actionLabel; Target = $targetLabel; Source = $srcLabel; Detail = $detail }
        Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $actionLabel, $targetLabel, $srcLabel, $detail)
        [void]$remaining.Add($item)
        $hadFailure = $true
    }
}

# --- 寫回佇列檔（只留未出列項目，順序不變） ---
Write-QueueFile -QueuePath $QueuePath -Items @($remaining)

# --- 報告 ---
$reportLines += ($statusRows | ForEach-Object { "[{0,-24}] {1} | {2} | {3} — {4}" -f $_.Status, $_.Action, $_.Target, $_.Source, $_.Detail })
$reportLines += ""
$summary = "共 {0} 筆：APPLIED-VERIFIED={1} SKIPPED-ALREADY-SATISFIED={2} FAILED-VERIFY={3} FAILED-APPLY={4} FAILED-VALIDATION={5} FAILED-SCHEMA={6}；剩餘於佇列：{7} 筆" -f `
    $statusRows.Count, `
    (@($statusRows | Where-Object Status -eq 'APPLIED-VERIFIED')).Count, `
    (@($statusRows | Where-Object Status -eq 'SKIPPED-ALREADY-SATISFIED')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-VERIFY')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-APPLY')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-VALIDATION')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-SCHEMA')).Count, `
    $remaining.Count
$reportLines += $summary
Write-Host $summary

$reportPath = Join-Path $PSScriptRoot 'apply-queue-report.txt'
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($hadFailure) { exit 1 }
exit 0
