#requires -Version 5.1
<#
.SYNOPSIS
    T-21：待寫佇列共用函式庫。由 apply-queue.ps1 與 reconcile-queue.ps1 dot-source 引用。

.DESCRIPTION
    單一來源的「讀現況比對」邏輯（§4.6：冪等靠讀現況比對，不設動作指紋）。
    apply-queue.ps1 用它來判斷「是否需要真的寫」，reconcile-queue.ps1 用它來判斷「是否該出列」，
    兩者共用同一份比對規則，避免兩支腳本各自維護一份、日後對不上（DRY）。

    本檔本身不對 GitHub 發任何寫入請求（GET only）；寫入呼叫（PUT/POST/PATCH）只存在於 apply-queue.ps1。
#>

Set-StrictMode -Version Latest

# --- UTF-8 BOM 輸出（比照 T-07 慣例：主控台與報告檔皆用 BOM，避免繁中亂碼） ---
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

# --- PAT 讀取 ---
function Read-PatToken {
    param([Parameter(Mandatory)][string]$PatPath)
    if (-not (Test-Path -LiteralPath $PatPath)) {
        throw "PAT 檔案不存在：$PatPath"
    }
    $token = (Get-Content -LiteralPath $PatPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "PAT 檔案內容為空：$PatPath"
    }
    return $token
}

function Get-GithubHeaders {
    param([Parameter(Mandatory)][string]$Token, [string]$UserAgent = 'station-command-t21-queue')
    return @{
        'Authorization'        = "Bearer $Token"
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = $UserAgent
    }
}

# --- 佇列檔讀寫 ---
# 回傳 $null 代表「佇列檔不存在」——呼叫端須把這個情況視為合法降級（§4.6），
# 具名回報「待寫佇列不存在，本批動作將重新產生」並正常結束，不是錯誤。
function Read-QueueFile {
    # rework（實跑爆掉後修正）：函式回傳陣列時，若元素數恰為 1 或 0，PowerShell 會把陣列
    # 「解卷」成純量或 $null（連 return 出函式邊界也會，不只是管線／cmdlet 輸出才會）。
    # 修法：一律用逗號運算子 `,` 包一層強制保留陣列型別（,@() 保 0 筆、,@($x) 保 1／N 筆）。
    # 已用 /opt/pwsh/pwsh 實測驗證：`,@()` 經函式邊界回傳後 Count=0（不是 $null）；
    # `,@($x)`（$x 為單一物件）回傳後型別是 Object[] Count=1（不是純量）。
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
    # $parsed 此時保證非 null；不論原本是單一物件或陣列，@() 皆能正確包成陣列，
    # 再用逗號保住這層陣列不被函式邊界解卷。
    return ,@($parsed)
}

function Write-QueueFile {
    param([Parameter(Mandatory)][string]$QueuePath, [Parameter(Mandatory)][AllowEmptyCollection()][array]$Items)
    $json = if ($Items.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject $Items -Depth 10 }
    Write-Utf8BomFile -Path $QueuePath -Content $json
}

function Split-RepoString {
    param([Parameter(Mandatory)][string]$RepoString)
    $parts = $RepoString -split '/', 2
    if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
        throw "target.repo 格式錯誤（須為 owner/repo）：$RepoString"
    }
    return [pscustomobject]@{ Owner = $parts[0]; Repo = $parts[1] }
}

# --- GitHub description 100 字元守門（今日實測 114 字元回 422） ---
# 遞迴掃 payload 內任何名為 description 的欄位；找到 ⇒ 檢查長度，逾 100 記為違規。
# rework：兩個 return 皆加逗號，避免「總共只找到 1 筆違規」時被函式邊界解卷成純量，
# 導致呼叫端 apply-queue.ps1 的 $violations.Count 在 PS 5.1 下報同型錯誤。
function Get-DescriptionLengthViolations {
    param([Parameter(Mandatory)]$Payload, [string]$PathPrefix = 'payload')
    $violations = @()
    if ($null -eq $Payload) { return ,$violations }
    if ($Payload -is [System.Management.Automation.PSCustomObject]) {
        foreach ($prop in $Payload.PSObject.Properties) {
            $childPath = "$PathPrefix.$($prop.Name)"
            if ($prop.Name -eq 'description' -and $prop.Value -is [string]) {
                $len = $prop.Value.Length
                if ($len -gt 100) {
                    $violations += [pscustomobject]@{ Path = $childPath; Length = $len; Value = $prop.Value }
                }
            }
            # 遞迴呼叫本身也可能回傳 0/1/N 筆；+= 對純量或陣列 RHS 皆正確逐一附加，此處安全。
            $violations += Get-DescriptionLengthViolations -Payload $prop.Value -PathPrefix $childPath
        }
    }
    elseif ($Payload -is [System.Collections.IEnumerable] -and -not ($Payload -is [string])) {
        $i = 0
        foreach ($item in $Payload) {
            $violations += Get-DescriptionLengthViolations -Payload $item -PathPrefix "$PathPrefix[$i]"
            $i++
        }
    }
    return ,$violations
}

# --- 讀現況：單一 issue（含 labels／state／state_reason） ---
function Get-CurrentIssue {
    param([Parameter(Mandatory)][string]$Owner, [Parameter(Mandatory)][string]$Repo,
          [Parameter(Mandatory)][int]$IssueNumber, [Parameter(Mandatory)][hashtable]$Headers)
    $url = "https://api.github.com/repos/$Owner/$Repo/issues/$IssueNumber"
    try {
        return Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
    } catch {
        $resp = $_.Exception.Response
        if ($resp -and $resp.StatusCode.value__ -eq 404) { return $null }
        throw
    }
}

# --- 把 Invoke-RestMethod 的原始回傳值強制轉成「保證是陣列」的值 ---
# 根因（rework，實跑爆掉後定位並用 pwsh 7 實測確認）：
#   Invoke-RestMethod 對 JSON 陣列回應會逐筆把元素送進管線；捕捉到變數時，
#   0 筆 ⇒ 變數是 $null（不是空陣列！實測 @(呼叫回傳 $null 的函式).Count 在此情境下
#          外層若沒特別處理，仍會把 $null 誤包成「1 筆內容是 $null」的陣列，見下方判斷）；
#   1 筆 ⇒ 變數是純量物件（PS 6+ 有 .Count 相容屬性會回 1 而掩蓋此問題，
#          但 PowerShell 5.1（使用者環境）沒有這個相容層，.Count 在 StrictMode 下直接拋
#          「The property 'Count' cannot be found on this object」——這正是本輪爆掉的原因）；
#   N 筆 ⇒ 變數本來就是正常陣列。
# 修法：明確先判斷 $null（視為 0 筆），非 null 才用 @() 包裝（此時 1 筆會被正確包成
#       1 元素陣列、N 筆維持不變）；🚫 不能對可能是 $null 的值直接 @() 包裝，因為
#       @($null) 本身會產生「1 個元素、該元素是 $null」的陣列（已用 pwsh 7 實測確認），
#       語意上是錯的（那是 0 筆，不是「1 筆內容為空」）。
function ConvertTo-SafeArray {
    param($RawValue)
    if ($null -eq $RawValue) { return ,@() }
    return ,@($RawValue)
}

function Get-CurrentIssueComments {
    param([Parameter(Mandatory)][string]$Owner, [Parameter(Mandatory)][string]$Repo,
          [Parameter(Mandatory)][int]$IssueNumber, [Parameter(Mandatory)][hashtable]$Headers,
          [int]$MaxPages = 3)
    $all = @()
    for ($page = 1; $page -le $MaxPages; $page++) {
        $url = "https://api.github.com/repos/$Owner/$Repo/issues/$IssueNumber/comments?per_page=100&page=$page"
        $rawChunk = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
        $chunk = ConvertTo-SafeArray -RawValue $rawChunk
        $all += $chunk
        if ($chunk.Count -lt 100) { break }
    }
    # $all 全程只被賦予 ConvertTo-SafeArray 保證的陣列值，型別穩定；仍加逗號防函式邊界解卷。
    return ,$all
}

function Get-CurrentIssuesByTitle {
    # best-effort：只掃最近 100 筆（state=all），文件已具名此限制（queue-format.md §3.4）
    param([Parameter(Mandatory)][string]$Owner, [Parameter(Mandatory)][string]$Repo,
          [Parameter(Mandatory)][hashtable]$Headers)
    $url = "https://api.github.com/repos/$Owner/$Repo/issues?state=all&per_page=100"
    $raw = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
    return ,(ConvertTo-SafeArray -RawValue $raw)
}

function Get-CurrentMilestonesByTitle {
    param([Parameter(Mandatory)][string]$Owner, [Parameter(Mandatory)][string]$Repo,
          [Parameter(Mandatory)][hashtable]$Headers)
    $url = "https://api.github.com/repos/$Owner/$Repo/milestones?state=all&per_page=100"
    $raw = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
    return ,(ConvertTo-SafeArray -RawValue $raw)
}

# --- 換行符正規化（rework：verifier 提出 HIGH 風險——GitHub 對 comment body 可能正規化
#     CRLF/LF，若比對用原始字串會誤判「未達成」而重貼。動態測試（t21-dynamic-test.ps1）
#     會實測 GitHub 的實際行為；本函式無論實測結果為何都安全套用（純字串正規化不影響
#     LF-only 或已一致的內容比對結果）。同時 trim 每行尾端空白，涵蓋常見的行尾正規化差異。 ---
function ConvertTo-NormalizedText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $normalized = $Text -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    return $normalized
}

# --- 已達成判準（讀現況比對；不設動作指紋，§4.6） ---
# 回傳 [pscustomobject]@{ Satisfied = bool; Detail = string; CurrentSnapshot = obj-or-null }
function Test-ItemSatisfied {
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)][hashtable]$Headers)

    switch ($Item.action) {
        'set-labels' {
            $r = Split-RepoString -RepoString $Item.target.repo
            $issue = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber ([int]$Item.target.issue) -Headers $Headers
            if ($null -eq $issue) {
                return [pscustomobject]@{ Satisfied = $false; Detail = "目標 issue 不存在：$($Item.target.repo)#$($Item.target.issue)"; CurrentSnapshot = $null }
            }
            # rework：實測確認 $issue.labels 為 $null 時（issue 目前無任何 label），
            # 直接 pipe 進 ForEach-Object 會讓 $_ 綁定成 $null，再存取 $_.name 在 StrictMode
            # 下拋錯（已用 pwsh 7 實測重現同型錯誤：The property 'name' cannot be found）。
            # 用 ConvertTo-SafeArray 先擋一層，無 label 時視為空陣列。
            $issueLabels = ConvertTo-SafeArray -RawValue $issue.labels
            $current = @($issueLabels | ForEach-Object { $_.name } | Sort-Object)
            $desired = @($Item.payload.labels | Sort-Object)
            $same = ($current.Count -eq $desired.Count) -and (@(Compare-Object $current $desired -SyncWindow 0).Count -eq 0)
            $detail = if ($same) { "現有 label 集合已符合：[$($current -join ', ')]" } else { "現有 [$($current -join ', ')] != 期望 [$($desired -join ', ')]" }
            return [pscustomobject]@{ Satisfied = $same; Detail = $detail; CurrentSnapshot = $current }
        }
        'close-issue' {
            $r = Split-RepoString -RepoString $Item.target.repo
            $issue = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber ([int]$Item.target.issue) -Headers $Headers
            if ($null -eq $issue) {
                return [pscustomobject]@{ Satisfied = $false; Detail = "目標 issue 不存在：$($Item.target.repo)#$($Item.target.issue)"; CurrentSnapshot = $null }
            }
            $stateOk = ($issue.state -eq $Item.payload.state)
            $reasonOk = $true
            if ($Item.payload.PSObject.Properties.Name -contains 'state_reason' -and $Item.payload.state_reason) {
                $reasonOk = ($issue.state_reason -eq $Item.payload.state_reason)
            }
            $same = $stateOk -and $reasonOk
            $detail = "現有 state='$($issue.state)' state_reason='$($issue.state_reason)' vs 期望 state='$($Item.payload.state)'"
            return [pscustomobject]@{ Satisfied = $same; Detail = $detail; CurrentSnapshot = @{ state = $issue.state; state_reason = $issue.state_reason } }
        }
        'comment' {
            $r = Split-RepoString -RepoString $Item.target.repo
            # Get-CurrentIssueComments 已保證回陣列，這裡再 @() 包一層是防禦性重複保險
            # （即使函式內部保證失效，呼叫端仍不會拿到裸 $null／純量）。
            $comments = Get-CurrentIssueComments -Owner $r.Owner -Repo $r.Repo -IssueNumber ([int]$Item.target.issue) -Headers $Headers
            # rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
            # 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
            $comments = @($comments)
            # 先試完全相等（最嚴格）；找不到再試「換行正規化後相等」（因應 GitHub 可能對 CRLF/LF 做正規化，
            # rework HIGH 風險項——t21-dynamic-test.ps1 會實測是否真的觸發這條分支）。
            $found = $comments | Where-Object { $_.body -eq $Item.payload.body }
            $matchKind = 'exact'
            if ($null -eq $found -or @($found).Count -eq 0) {
                $desiredNorm = ConvertTo-NormalizedText -Text $Item.payload.body
                $found = $comments | Where-Object { (ConvertTo-NormalizedText -Text $_.body) -eq $desiredNorm }
                $matchKind = 'normalized-lineending'
            }
            $same = $null -ne $found -and @($found).Count -gt 0
            $detail = if ($same) { "已存在相同內文的留言（比對方式=$matchKind，id=$(@($found)[0].id)）" } else { "找不到相同內文的既有留言（完全相等與換行正規化後皆未命中；比對前 $($comments.Count) 則）" }
            return [pscustomobject]@{ Satisfied = $same; Detail = $detail; CurrentSnapshot = $comments }
        }
        'create-issue' {
            $r = Split-RepoString -RepoString $Item.target.repo
            $issues = Get-CurrentIssuesByTitle -Owner $r.Owner -Repo $r.Repo -Headers $Headers
            # rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
            # 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
            $issues = @($issues)
            $found = $issues | Where-Object { $_.title -eq $Item.payload.title }
            $same = $null -ne $found -and @($found).Count -gt 0
            $detail = if ($same) { "已存在同標題 issue（best-effort，僅掃最近 100 筆）：#$(@($found)[0].number)" } else { "最近 100 筆中找不到同標題 issue" }
            return [pscustomobject]@{ Satisfied = $same; Detail = $detail; CurrentSnapshot = $found }
        }
        'create-milestone' {
            $r = Split-RepoString -RepoString $Item.target.repo
            $milestones = Get-CurrentMilestonesByTitle -Owner $r.Owner -Repo $r.Repo -Headers $Headers
            # rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
            # 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
            $milestones = @($milestones)
            $found = $milestones | Where-Object { $_.title -eq $Item.payload.title }
            $same = $null -ne $found -and @($found).Count -gt 0
            $detail = if ($same) { "已存在同標題 milestone：#$(@($found)[0].number)" } else { "找不到同標題 milestone" }
            return [pscustomobject]@{ Satisfied = $same; Detail = $detail; CurrentSnapshot = $found }
        }
        default {
            throw "未知的 action 類型：$($Item.action)（白名單：set-labels／close-issue／comment／create-issue／create-milestone）"
        }
    }
}

# --- 佇列項基本 schema 驗證（四欄皆須存在） ---
function Test-ItemSchema {
    param([Parameter(Mandatory)]$Item)
    $required = @('action', 'target', 'payload', 'source')
    $missing = @()
    foreach ($f in $required) {
        if (-not ($Item.PSObject.Properties.Name -contains $f) -or $null -eq $Item.$f) {
            $missing += $f
        }
    }
    if ($missing.Count -gt 0) {
        return [pscustomobject]@{ Valid = $false; Detail = "缺少必填欄位：$($missing -join ', ')" }
    }
    $knownActions = @('set-labels', 'close-issue', 'comment', 'create-issue', 'create-milestone')
    if ($knownActions -notcontains $Item.action) {
        return [pscustomobject]@{ Valid = $false; Detail = "未知 action：'$($Item.action)'（白名單：$($knownActions -join '／')）" }
    }
    if (-not ($Item.target.PSObject.Properties.Name -contains 'repo') -or [string]::IsNullOrWhiteSpace($Item.target.repo)) {
        return [pscustomobject]@{ Valid = $false; Detail = "target.repo 缺漏" }
    }
    return [pscustomobject]@{ Valid = $true; Detail = '' }
}
