#requires -Version 5.1
<#
.SYNOPSIS
    T-22：patch 落地共用函式庫。由 apply-patch.ps1 與測試腳本 dot-source 引用。

.DESCRIPTION
    單一來源的「讀現況比對」邏輯（patch-format.md §4：冪等靠 git apply --check --reverse 讀工作區
    現況，不設動作指紋）。本檔本身不對 GitHub 發任何請求（本型套用全程不連 GitHub），
    只呼叫本機 git 與檔案系統。

    刻意重複（非引用）T-21 queue-common.ps1 的四個純 I/O 工具函式
    （Set-ConsoleUtf8／Write-Utf8BomFile／Read-QueueFile／Write-QueueFile）——
    理由見 patch-format.md §1「與 T-21 佇列共存的實務安排」：
    build/t21 與 build/t22 可能被使用者複製到本機不同路徑，跨資料夾的相對路徑 dot-source
    會很脆弱；這四個函式是無狀態的純工具（不含任何 GitHub 或 issue-metadata 特定邏輯），
    複製四個小函式的維護成本遠低於強迫兩個票的交付物綁死同一個本機目錄結構。
    T-21 專屬邏輯（Test-ItemSatisfied／Get-DescriptionLengthViolations／Test-ItemSchema 等）
    完全不重複，因為 apply-patch 從不處理 metadata 型動作。
#>

Set-StrictMode -Version Latest

# --- UTF-8 BOM 輸出（比照 T-21 慣例） ---
$Script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Set-ConsoleUtf8 {
    try {
        [Console]::OutputEncoding = $Script:Utf8Bom
        $Global:OutputEncoding = $Script:Utf8Bom
    } catch {
        Write-Warning "無法設定主控台輸出編碼，繼續執行：$($_.Exception.Message)"
    }
}

function Write-Utf8BomFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Script:Utf8Bom)
}

# --- 佇列檔讀寫（與 T-21 queue-common.ps1 同邏輯，見檔頭「刻意重複」說明） ---
function Read-QueueFile {
    # 同 T-21 的陣列解卷防禦：一律用逗號運算子保住陣列型別，見 build/t21/queue-common.ps1 同名函式註解。
    param([Parameter(Mandatory)][string]$QueuePath)
    if (-not (Test-Path -LiteralPath $QueuePath)) {
        return $null
    }
    $raw = Get-Content -LiteralPath $QueuePath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return ,@()
    }
    $parsed = $raw | ConvertFrom-Json
    if ($null -eq $parsed) { return ,@() }
    return ,@($parsed)
}

function Write-QueueFile {
    param([Parameter(Mandatory)][string]$QueuePath, [Parameter(Mandatory)][AllowEmptyCollection()][array]$Items)
    $json = if ($Items.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject $Items -Depth 10 }
    Write-Utf8BomFile -Path $QueuePath -Content $json
}

# --- SHA-256 ---
function Get-FileSha256Hex {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "patch 檔不存在，無法計算雜湊：$Path"
    }
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    return $hash.Hash.ToLowerInvariant()
}

# --- git 呼叫包裝：統一 -C worktree、統一把 stdout/stderr 併成一段可讀字串、統一回傳陣列安全 ---
# 🚫 刻意不覆寫 core.autocrlf／core.eol——理由見 patch-format.md §8（實測：覆寫成 false 會讓
#     LF patch 對 CRLF 工作區檔案誤判衝突；讓 git 用該 repo既有設定套用才會正確重現「行尾一致」）。
function Invoke-GitCommand {
    param(
        [Parameter(Mandatory)][string]$Worktree,
        [Parameter(Mandatory)][string[]]$GitArgs
    )
    $fullArgs = @('-C', $Worktree) + $GitArgs
    $rawOutput = & git @fullArgs 2>&1
    $exitCode = $LASTEXITCODE
    # rework 型防禦（比照 T-21 陣列解卷教訓）：外部程式的 2>&1 合併輸出在 PS 5.1 對「僅 1 行」
    # 或「0 行」時同樣可能解卷成純量／$null；先賦值再 @() 包一層，且逐一轉字串
    # （stderr 行在 PS 5.1 可能是 ErrorRecord 物件，直接拼字串前需 .ToString()）。
    $rawOutput = @($rawOutput)
    $outputLines = @($rawOutput | ForEach-Object { $_.ToString() })
    $outputText = $outputLines -join [Environment]::NewLine
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $outputText }
}

function Test-GitAvailable {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

function Test-WorktreeValid {
    param([Parameter(Mandatory)][string]$Worktree)
    if (-not (Test-Path -LiteralPath $Worktree -PathType Container)) {
        return [pscustomobject]@{ Valid = $false; Detail = "worktree 路徑不存在或不是資料夾：$Worktree" }
    }
    $r = Invoke-GitCommand -Worktree $Worktree -GitArgs @('rev-parse', '--is-inside-work-tree')
    if ($r.ExitCode -ne 0 -or ($r.Output.Trim() -ne 'true')) {
        return [pscustomobject]@{ Valid = $false; Detail = "路徑存在但不是合法 git 工作區：$Worktree（$($r.Output)）" }
    }
    return [pscustomobject]@{ Valid = $true; Detail = '' }
}

# best-effort：target.repo 與 worktree 實際 remote 是否對得上，對不上只警示，不擋下（見 patch-format.md §4）
function Test-WorktreeRepoMatches {
    param([Parameter(Mandatory)][string]$Worktree, [Parameter(Mandatory)][string]$ExpectedRepo)
    $r = Invoke-GitCommand -Worktree $Worktree -GitArgs @('remote', 'get-url', 'origin')
    if ($r.ExitCode -ne 0) {
        return [pscustomobject]@{ Matches = $true; Detail = '(worktree 尚未設定 origin remote，略過核對——best-effort，不擋下)' }
    }
    $remoteUrl = $r.Output.Trim()
    # 簡單子字串核對（owner/repo 名稱是否出現在 remote URL 內），涵蓋 https 與 ssh 兩種常見形式
    $repoNamePart = ($ExpectedRepo -split '/', 2)[-1]
    if ($remoteUrl -match [regex]::Escape($repoNamePart)) {
        return [pscustomobject]@{ Matches = $true; Detail = "origin=$remoteUrl，含 repo 名稱 '$repoNamePart'" }
    }
    return [pscustomobject]@{ Matches = $false; Detail = "⚠️ origin=$remoteUrl 未含目標 repo 名稱 '$repoNamePart'，target.repo='$ExpectedRepo'，請確認 worktree 路徑是否指對倉庫" }
}

# --- 冪等判準：反向乾跑（patch-format.md §4） ---
function Test-PatchAlreadyApplied {
    param([Parameter(Mandatory)][string]$Worktree, [Parameter(Mandatory)][string]$PatchFile)
    $r = Invoke-GitCommand -Worktree $Worktree -GitArgs @('apply', '--check', '--reverse', '--binary', $PatchFile)
    return [pscustomobject]@{ AlreadyApplied = ($r.ExitCode -eq 0); Detail = $r.Output }
}

# --- 套用前乾跑（正向） ---
function Test-PatchAppliesCleanly {
    param([Parameter(Mandatory)][string]$Worktree, [Parameter(Mandatory)][string]$PatchFile)
    $r = Invoke-GitCommand -Worktree $Worktree -GitArgs @('apply', '--check', '--binary', $PatchFile)
    return [pscustomobject]@{ Applicable = ($r.ExitCode -eq 0); Detail = $r.Output }
}

# --- 唯讀診斷：這個衝突「看起來」像不像純行尾差異（不自動套用，只供訊息參考，見 patch-format.md §7/§8） ---
function Test-ConflictLooksLikeLineEndingOnly {
    param([Parameter(Mandatory)][string]$Worktree, [Parameter(Mandatory)][string]$PatchFile)
    $r = Invoke-GitCommand -Worktree $Worktree -GitArgs @('apply', '--check', '--ignore-whitespace', '--binary', $PatchFile)
    return ($r.ExitCode -eq 0)
}

# --- 真套用：安全預設（無 --reject／--3way／--index），git 內建 all-or-nothing ---
function Invoke-PatchApply {
    param([Parameter(Mandatory)][string]$Worktree, [Parameter(Mandatory)][string]$PatchFile)
    return Invoke-GitCommand -Worktree $Worktree -GitArgs @('apply', '--binary', $PatchFile)
}

# --- 魯莽套用：僅供 -SkipDryRunCheck 紅燈驗證路徑使用，🚫 正式流程禁用（見 patch-format.md §9） ---
function Invoke-PatchApplyReckless {
    param([Parameter(Mandatory)][string]$Worktree, [Parameter(Mandatory)][string]$PatchFile)
    return Invoke-GitCommand -Worktree $Worktree -GitArgs @('apply', '--binary', '--reject', $PatchFile)
}

# --- 半套殘留偵測：.rej 檔 ---
function Test-WorktreeHasRejectArtifacts {
    param([Parameter(Mandatory)][string]$Worktree)
    $found = Get-ChildItem -LiteralPath $Worktree -Recurse -Filter '*.rej' -File -ErrorAction SilentlyContinue
    $found = @($found)
    return [pscustomobject]@{ HasRejects = ($found.Count -gt 0); Files = $found }
}

# --- 半套殘留偵測：內文衝突標記（3-way 情境才會出現，本票預設路徑不用 --3way，此為防禦性檢查） ---
function Test-WorktreeHasConflictMarkers {
    param([Parameter(Mandatory)][string]$Worktree, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Files)
    $hits = @()
    foreach ($f in $Files) {
        $full = Join-Path $Worktree $f
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $content = Get-Content -LiteralPath $full -Raw -ErrorAction SilentlyContinue
            if ($null -ne $content -and ($content -match '(?m)^<{7} ' -or $content -match '(?m)^={7}$' -or $content -match '(?m)^>{7} ')) {
                $hits += $f
            }
        }
    }
    $hits = @($hits)
    return [pscustomobject]@{ HasMarkers = ($hits.Count -gt 0); Files = $hits }
}

# --- 佇列項 schema 驗證（apply-patch 專屬，不共用 T-21 的 Test-ItemSchema——它的白名單不含本型） ---
function Test-ApplyPatchItemSchema {
    param([Parameter(Mandatory)]$Item)
    $required = @('action', 'target', 'payload', 'source')
    $missing = @()
    foreach ($f in $required) {
        if (-not ($Item.PSObject.Properties.Name -contains $f) -or $null -eq $Item.$f) { $missing += $f }
    }
    if ($missing.Count -gt 0) {
        return [pscustomobject]@{ Valid = $false; Detail = "缺少必填欄位：$($missing -join ', ')" }
    }
    if ($Item.action -ne 'apply-patch') {
        return [pscustomobject]@{ Valid = $false; Detail = "action 非 apply-patch，本腳本不處理：'$($Item.action)'" }
    }
    if (-not ($Item.target.PSObject.Properties.Name -contains 'worktree') -or [string]::IsNullOrWhiteSpace($Item.target.worktree)) {
        return [pscustomobject]@{ Valid = $false; Detail = 'target.worktree 缺漏' }
    }
    if (-not ($Item.target.PSObject.Properties.Name -contains 'repo') -or [string]::IsNullOrWhiteSpace($Item.target.repo)) {
        return [pscustomobject]@{ Valid = $false; Detail = 'target.repo 缺漏' }
    }
    if (-not ($Item.payload.PSObject.Properties.Name -contains 'patchFile') -or [string]::IsNullOrWhiteSpace($Item.payload.patchFile)) {
        return [pscustomobject]@{ Valid = $false; Detail = 'payload.patchFile 缺漏' }
    }
    if (-not ($Item.payload.PSObject.Properties.Name -contains 'sha256') -or [string]::IsNullOrWhiteSpace($Item.payload.sha256)) {
        return [pscustomobject]@{ Valid = $false; Detail = 'payload.sha256 缺漏' }
    }
    return [pscustomobject]@{ Valid = $true; Detail = '' }
}

# --- 落地紀錄（供交付判定使用，patch-format.md §6） ---
function Add-AppliedPatchLogEntry {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Worktree,
        [Parameter(Mandatory)][string]$PatchFile
    )
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K') | STATUS=$Status | source=$Source | worktree=$Worktree | patchFile=$PatchFile"
    $existing = if (Test-Path -LiteralPath $LogPath) { Get-Content -LiteralPath $LogPath -Raw -Encoding UTF8 } else { '' }
    $newContent = if ([string]::IsNullOrEmpty($existing)) { $line } else { $existing.TrimEnd([Environment]::NewLine.ToCharArray()) + [Environment]::NewLine + $line }
    Write-Utf8BomFile -Path $LogPath -Content $newContent
}

# --- 交付判定（驗收條件③：patch 仍在佇列時必須顯示未交付；patch-format.md §6） ---
function Test-PatchDelivered {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)][string]$AppliedLogPath
    )
    $items = Read-QueueFile -QueuePath $QueuePath
    if ($null -ne $items) {
        $items = @($items)
        $pending = @($items | Where-Object { $_.action -eq 'apply-patch' -and $_.source -eq $Source })
        if ($pending.Count -gt 0) {
            return [pscustomobject]@{ Delivered = $false; Reason = "仍有 $($pending.Count) 筆 apply-patch 型佇列項目未出列（source=$Source）——未套用前不得算交付" }
        }
    }
    if (-not (Test-Path -LiteralPath $AppliedLogPath)) {
        return [pscustomobject]@{ Delivered = $false; Reason = "佇列中查無該 source 的 apply-patch 項目，且落地紀錄檔不存在——安全預設為未交付（可能從未進佇列，非「已交付」的證據）" }
    }
    $logLines = @(Get-Content -LiteralPath $AppliedLogPath -Encoding UTF8 -ErrorAction SilentlyContinue)
    $hit = @($logLines | Where-Object {
        $_ -like "*source=$Source *" -and ($_ -like '*STATUS=APPLIED-VERIFIED*' -or $_ -like '*STATUS=SKIPPED-ALREADY-APPLIED*')
    })
    if ($hit.Count -gt 0) {
        return [pscustomobject]@{ Delivered = $true; Reason = "已於 applied-patches.log 找到 source=$Source 的落地紀錄，且佇列已無未出列項目" }
    }
    return [pscustomobject]@{ Delivered = $false; Reason = "佇列中查無該 source 的 apply-patch 項目，落地紀錄檔內也查無相符紀錄——安全預設為未交付" }
}
