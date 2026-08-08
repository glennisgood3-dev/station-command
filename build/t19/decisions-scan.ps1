#requires -Version 5.1
<#
.SYNOPSIS
    T-19：豁免有牙與 DECISIONS.md 掃描 fail-closed —— gate 每次執行掃描全參與 repo 的 DECISIONS.md，
    判定過期豁免／讀取失敗／檔案不存在／解析失敗／條目格式不合五種情境，fail-closed 為核心紀律。

.DESCRIPTION
    依 Spec_station-command_v1.11.md §6（全站，每次 gate 均查：「全參與 repo 的 DECISIONS.md 皆無已
    過期豁免條目」）、§7.4（補件／豁免規則）、§8（DECISIONS.md 模板：追加式表格，只追加不改寫）實作。

    **失敗語意（逐字承接 §6 附註）**：
      讀取失敗（API 錯誤／權限不足）＝ gate fail（fail-closed）；
      檔案不存在＝視為該 repo 無豁免（不 fail）。
    本檔額外把「解析失敗」「豁免條目格式不合」兩種情境也判為 fail-closed——這兩者不在 §6 附註逐字
    範圍內，但屬本票精神的必要延伸（讀得到檔案、但內容看不懂／條目缺欄位，不能因為「有讀到東西」
    就放行；空白解讀成『沒有豁免』與『看不懂，先擋下』是完全不同的兩件事）。**唯一的「不 fail」情境
    只有『檔案確實不存在（404）』一種**——此點在 README「誠實聲明」一節有專門釐清（dispatch 訊息與
    ticket／spec 逐字文字之間的落差如何裁決）。

    **本票不撰寫、不修改、不移除任何豁免條目**（scope 已排除）——本檔全程對 DECISIONS.md 只做 GET
    讀取，不含任何寫入 DECISIONS.md 的程式路徑（無 PUT/PATCH/POST 對 contents API），程式碼層面即
    無法違反此條款，非僅文件宣告。

    **權限邊界**：讀 DECISIONS.md 唯讀（GitHub contents API，GET only）；判定 fail 時落 `sc:gate-fail`
    一律走 T-21 佇列項（`set-labels`），不直接呼叫 GitHub 寫入 API——重用 `../t21/queue-common.ps1`
    的 Read-QueueFile／Write-QueueFile（唯讀引用，不修改該檔案）。

    **地基重用**：本檔的佇列產生模式（Get-FullLabelSetWithGateFail／New-...QueueItem／
    Add-...QueueItemIfAbsent）比照 `../t10/gate-advance.ps1` 與 `../t13/gate-station3.ps1` 既有設計
    ——沿用同一套「完整 label 集合、冪等追加去重」慣例，但**各自保留本地一份**（不下放共用檔），
    理由與 T-10／T-13 README 相同：產生權自查邏輯屬各 skill 自己的產生階段責任，且 file ownership
    禁止本票修改 build/t10、build/t13、build/t21 內的檔案。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程（供離線測試 dot-source 呼叫內部函式）。
#>

[CmdletBinding()]
param(
    [string]$WorkId,
    [string]$PrimaryRepo,
    [int]$AnchorIssue,
    [string[]]$ParticipatingRepos = @(),
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [string]$AsOfDateString = '',
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
# ⚠️ 命名為 $T19ScriptDir 而非常見的 $ScriptDir——理由同 T-12／T-13 既有註解記載的實跑 bug 先例：
# 本檔 dot-source ../t21/queue-common.ps1，若沿用未加範圍前綴的 $ScriptDir，日後若本檔或其呼叫鏈
# cascade dot-source 到其他同樣用 $ScriptDir 的檔案（如 t10/gate-check.ps1），後執行者的賦值會覆蓋
# 前面的同名變數，導致本檔用它組報告／佇列檔路徑時誤寫到別的 build/tNN/ 目錄。獨有變數名徹底避開。
$T19ScriptDir = $PSScriptRoot
$T19QueueCommonPath = Join-Path $T19ScriptDir '..\t21\queue-common.ps1'
if (-not (Test-Path -LiteralPath $T19QueueCommonPath)) {
    throw ("找不到 T-21 共用函式庫：{0}。請確認 t19 與 t21 為同層兄弟目錄。" -f $T19QueueCommonPath)
}
. $T19QueueCommonPath
Set-ConsoleUtf8

# ============================================================================
# 第一層：DECISIONS.md markdown 表格解析（§8：日期｜ID｜類型｜裁示內容｜依據｜裁示人［｜狀態］）
# ============================================================================

# 依規則：一列以半形 | 分隔的儲存格陣列。表格分隔一律用半形 |；豁免子欄位序列化（見下）
# 刻意改用全形 ｜／： 以避免與半形表格分隔符衝突，故本函式不需處理跳脫字元。
function Split-MarkdownTableRow {
    param([Parameter(Mandatory)][string]$Line)
    $t = $Line.Trim()
    if ($t.StartsWith('|')) { $t = $t.Substring(1) }
    if ($t.EndsWith('|')) { $t = $t.Substring(0, $t.Length - 1) }
    $cells = $t -split '\|'
    $cells = @($cells | ForEach-Object { $_.Trim() })
    return ,$cells
}

function Test-IsSeparatorRow {
    param([string[]]$Cells)
    $Cells = @($Cells)
    if ($Cells.Count -eq 0) { return $false }
    foreach ($c in $Cells) {
        if ($c -notmatch '^:?-{1,}:?$') { return $false }
    }
    return $true
}

# 解析整份 DECISIONS.md 內容為結構化列陣列。**保守設計**：任何一列的欄位數與表頭不符，
# 整份判定解析失敗（fail-closed），不嘗試「盡量解析、跳過壞列」——因為壞列可能正是被截斷
# 或格式跑掉的豁免條目本身，跳過它等於漏檢，違反本票精神。
function ConvertFrom-DecisionsTable {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return [pscustomobject]@{ ParseOk = $false; Rows = @(); Detail = 'DECISIONS.md 內容為空白，找不到任何表格，解析失敗（fail-closed）' }
    }

    $lines = @($Content -split "`r`n|`n")
    $requiredCols = @('日期', 'ID', '類型', '裁示內容', '依據', '裁示人')

    $headerIdx = -1
    $headerCells = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line.Trim() -notlike '|*') { continue }
        # rework（實跑抓到的 bug，已用 pwsh 7 實測確認並修正）：🚫 不可直接 `@(Split-MarkdownTableRow ...)`
        # ——該函式內部用逗號運算子 `return ,$cells` 保護陣列型別跨函式邊界不被解卷；對「函式呼叫本身」
        # 再包一層 @() 會把「已保護好的陣列」錯誤地再包一層，變成「1 元素陣列，該元素是原陣列」
        # （同型陷阱見 ../t21/queue-common.ps1 既有註解）。正確作法：先賦值（PowerShell 對單一管線輸出物件
        # 的直接賦值語意會正確解卷回原陣列），再對已賦值變數包 @()（此時 @() 是安全的 idempotent 操作）。
        $cells = Split-MarkdownTableRow -Line $line
        $cells = @($cells)
        $hasAll = $true
        foreach ($rc in $requiredCols) {
            if ($cells -notcontains $rc) { $hasAll = $false; break }
        }
        if ($hasAll) { $headerIdx = $i; $headerCells = $cells; break }
    }

    if ($headerIdx -lt 0) {
        return [pscustomobject]@{ ParseOk = $false; Rows = @(); Detail = "DECISIONS.md 內容找不到符合 §8 格式的表格標頭（須含：$($requiredCols -join '、')），視為解析失敗（fail-closed）" }
    }
    if ($headerIdx + 1 -ge $lines.Count) {
        return [pscustomobject]@{ ParseOk = $false; Rows = @(); Detail = '表頭之後無分隔線與資料列，解析失敗（fail-closed）' }
    }

    # 同上一處 rework 註解：先賦值再 @() 包裝，不可直接 @(函式呼叫本身)。
    $sepCells = Split-MarkdownTableRow -Line $lines[$headerIdx + 1]
    $sepCells = @($sepCells)
    if (-not (Test-IsSeparatorRow -Cells $sepCells)) {
        return [pscustomobject]@{ ParseOk = $false; Rows = @(); Detail = "表頭下一行非 markdown 表格分隔線（實際內容：'$($lines[$headerIdx + 1])'），表格結構不符預期，解析失敗（fail-closed）" }
    }

    $colIndex = @{}
    for ($c = 0; $c -lt $headerCells.Count; $c++) { $colIndex[$headerCells[$c]] = $c }

    $rows = @()
    $rowLineNo = $headerIdx + 2
    $malformedRowDetail = $null
    while ($rowLineNo -lt $lines.Count) {
        $line = $lines[$rowLineNo]
        if ($line.Trim() -eq '' -or ($line.Trim() -notlike '|*')) { break }
        # 同上兩處 rework 註解：先賦值再 @() 包裝。
        $cells = Split-MarkdownTableRow -Line $line
        $cells = @($cells)
        if ($cells.Count -ne $headerCells.Count) {
            $malformedRowDetail = "第 $($rowLineNo + 1) 行欄位數（$($cells.Count)）與表頭欄位數（$($headerCells.Count)）不符，內容：'$line'"
            break
        }
        $row = [pscustomobject]@{
            Date     = $cells[$colIndex['日期']]
            Id       = $cells[$colIndex['ID']]
            Type     = $cells[$colIndex['類型']]
            Content  = $cells[$colIndex['裁示內容']]
            Basis    = $cells[$colIndex['依據']]
            Deciders = $cells[$colIndex['裁示人']]
            Status   = if ($colIndex.ContainsKey('狀態')) { $cells[$colIndex['狀態']] } else { $null }
        }
        $rows += $row
        $rowLineNo++
    }
    $rows = @($rows)

    if ($null -ne $malformedRowDetail) {
        return [pscustomobject]@{ ParseOk = $false; Rows = @(); Detail = "表格資料列格式不符（$malformedRowDetail），解析失敗（fail-closed，不嘗試部分解析）" }
    }

    return [pscustomobject]@{ ParseOk = $true; Rows = $rows; Detail = "解析成功，共 $($rows.Count) 筆條目" }
}

function Get-ExemptionRows {
    param([array]$Rows = @())
    $Rows = @($Rows)
    return ,@($Rows | Where-Object { $_.Type -eq '豁免' })
}

# ============================================================================
# 第二層：豁免條目子欄位解析（§7.4：豁免 ID／項目／理由／範圍／期限或永久／批准人；必含
# 「本項【未】處理」）
#
# 【設計決策，具名聲明】Spec §7.4 只規定豁免須具備的六個「概念欄位」，未定義其在 DECISIONS.md
# 表格內的序列化格式。本票依下列理由做出實作選擇並在此具名（非 spec 逐字規定）：
#   ① 「豁免 ID」與「批准人」已由外層表格既有的 ID／裁示人兩欄承接，無需在裁示內容欄內重複——
#      減少雙寫漂移風險，符合 DRY。
#   ② 裁示內容欄內採用「項目：X｜理由：Y｜範圍：Z｜期限：W」＋ 必含「本項【未】處理」字樣的序列化，
#      分隔符刻意選用全形｜／：（非表格分隔用的半形 |），避免與 markdown 表格分隔符衝突，
#      不需跳脫機制。
#   ③ 期限值：或為 10 碼 ISO 日期字串 yyyy-MM-dd，或為字面「永久」（永久豁免，恆不過期）。
# 此為本票 scope 內合理且必要的實作選擇（豁免掃描邏輯必須有一套可解析的格式才跑得動 fail-closed
# 判定），非竄改 spec 條文本身——spec 六個概念欄位全數被涵蓋（ID／批准人在外層欄，其餘四項在此）。
# ============================================================================
function ConvertFrom-ExemptionContentCell {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    $hasMarker = [bool]($Content -match [regex]::Escape('本項【未】處理'))

    $keys = @('項目', '理由', '範圍', '期限')
    $values = @{}
    foreach ($k in $keys) {
        $m = [regex]::Match($Content, "$k：(.*?)(?=｜|$)")
        if ($m.Success) { $values[$k] = $m.Groups[1].Value.Trim() }
    }

    $missing = @($keys | Where-Object { -not $values.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($values[$_]) })

    $deadlineRaw = if ($values.ContainsKey('期限')) { $values['期限'] } else { '' }
    $deadlineKind = 'invalid'
    $deadlineDate = $null
    if (-not [string]::IsNullOrWhiteSpace($deadlineRaw)) {
        if ($deadlineRaw -eq '永久' -or $deadlineRaw -eq '永久豁免') {
            $deadlineKind = 'permanent'
        } else {
            $parsed = [datetime]::MinValue
            $ok = [datetime]::TryParseExact($deadlineRaw, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
            if ($ok) { $deadlineKind = 'date'; $deadlineDate = $parsed }
        }
    }

    $wellFormed = ($missing.Count -eq 0) -and $hasMarker -and ($deadlineKind -ne 'invalid')

    $detailParts = @()
    if ($missing.Count -gt 0) { $detailParts += "缺子欄位：$($missing -join '、')" }
    if (-not $hasMarker) { $detailParts += '缺「本項【未】處理」字樣（§7.4 硬性要求）' }
    if ($deadlineKind -eq 'invalid') { $detailParts += "期限值無法解析（原始值：'$deadlineRaw'，須為 yyyy-MM-dd 或『永久』）" }
    $detail = if ($wellFormed) { "格式合規：項目='$($values['項目'])'／期限=$deadlineRaw" } else { $detailParts -join '；' }

    return [pscustomobject]@{
        WellFormed   = $wellFormed
        Missing      = $missing
        HasMarker    = $hasMarker
        DeadlineKind = $deadlineKind
        DeadlineRaw  = $deadlineRaw
        DeadlineDate = $deadlineDate
        Detail       = $detail
    }
}

function Test-ExemptionEntryExpired {
    param([Parameter(Mandatory)]$ParsedContent, [Parameter(Mandatory)][datetime]$AsOfDate)
    if ($ParsedContent.DeadlineKind -eq 'permanent') {
        return [pscustomobject]@{ Expired = $false; Detail = '期限＝永久，不過期' }
    }
    if ($ParsedContent.DeadlineKind -eq 'date') {
        $expired = ($ParsedContent.DeadlineDate.Date -lt $AsOfDate.Date)
        $detail = if ($expired) {
            "期限 $($ParsedContent.DeadlineDate.ToString('yyyy-MM-dd')) 早於檢查基準日 $($AsOfDate.ToString('yyyy-MM-dd'))，已過期"
        } else {
            "期限 $($ParsedContent.DeadlineDate.ToString('yyyy-MM-dd')) 尚未到基準日 $($AsOfDate.ToString('yyyy-MM-dd'))，未過期"
        }
        return [pscustomobject]@{ Expired = $expired; Detail = $detail }
    }
    throw 'Test-ExemptionEntryExpired 不應對 DeadlineKind=invalid 呼叫（呼叫端應先過 WellFormed 檢查，格式不合走另一條 fail-closed 分支）'
}

# ============================================================================
# 第三層：單一 repo 的完整掃描結果（讀取失敗語意的唯一裁決點）
#
# -BypassFailClosedForRedTest：僅供紅燈驗證用的實驗開關（比照 T-13 -SkipDeepContentCheck、
# T-10 -BypassStationOrderCheck 先例）。開啟後，讀取失敗／解析失敗／格式不合／過期豁免四種
# 本應 fail 的情境，全部被錯誤地改判為「視為無豁免不 fail」——精確重現 §6 附註明文禁止的
# 「查不到就放行」反面教材，讓「這些情境必須 fail」的斷言在測試中真的失敗一次（見
# t19-offline-test.ps1 群組 F 與 README 紅燈章節）。🚫 正式流程與 CLI 主流程絕不開啟本旗標。
# ============================================================================
function Invoke-DecisionsFileExemptionScan {
    param(
        [Parameter(Mandatory)][string]$RepoLabel,
        [Parameter(Mandatory)]$FetchResult,
        [Parameter(Mandatory)][datetime]$AsOfDate,
        [switch]$BypassFailClosedForRedTest
    )

    if ($BypassFailClosedForRedTest) {
        Write-Warning "⚠️⚠️⚠️ [$RepoLabel] -BypassFailClosedForRedTest 已開啟：所有本應 fail-closed 的情境會被錯誤地改判為通過，僅供紅燈驗證使用，正式流程絕對不得使用。"
    }

    if ($FetchResult.ErrorKind -eq 'not-found') {
        # 唯一的「不 fail」失敗類情境：檔案確實不存在（404）——依 §6 附註逐字：
        # 「檔案不存在＝視為該 repo 無豁免（不 fail）」。此為受測情境之一，不是紅燈
        # （見 README「紅燈設計」一節的專門區分）。
        return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'pass-no-file'; Detail = 'DECISIONS.md 不存在，依 §6 全站條件與 §7.4，視為該 repo 無豁免（不 fail）'; ExpiredEntries = @(); MalformedEntries = @() }
    }

    if ($FetchResult.ErrorKind -eq 'read-error') {
        if ($BypassFailClosedForRedTest) {
            return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'pass-BYPASS'; Detail = "[BYPASS-RED-TEST] 讀取失敗本應 fail-closed，但旗標開啟後被錯誤地視為通過（模擬『查不到就放行』的反面教材，僅供紅燈驗證）：$($FetchResult.ErrorDetail)"; ExpiredEntries = @(); MalformedEntries = @() }
        }
        return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'fail-read-error'; Detail = "DECISIONS.md 讀取失敗（API 錯誤／權限不足），依 §6／§7.4 fail-closed：$($FetchResult.ErrorDetail)"; ExpiredEntries = @(); MalformedEntries = @() }
    }

    $parsed = ConvertFrom-DecisionsTable -Content $FetchResult.Content
    if (-not $parsed.ParseOk) {
        if ($BypassFailClosedForRedTest) {
            return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'pass-BYPASS'; Detail = "[BYPASS-RED-TEST] 解析失敗本應 fail-closed，旗標開啟後被錯誤地視為通過：$($parsed.Detail)"; ExpiredEntries = @(); MalformedEntries = @() }
        }
        return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'fail-parse-error'; Detail = "DECISIONS.md 解析失敗，fail-closed：$($parsed.Detail)"; ExpiredEntries = @(); MalformedEntries = @() }
    }

    # 同 ConvertFrom-DecisionsTable 內的 rework 註解：Get-ExemptionRows 內部也用 `return ,@(...)`
    # 保護陣列型別，先賦值再 @() 包裝，不可直接 @(函式呼叫本身)。
    $exemptionRows = Get-ExemptionRows -Rows $parsed.Rows
    $exemptionRows = @($exemptionRows)
    if ($exemptionRows.Count -eq 0) {
        return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'pass-no-exemptions'; Detail = 'DECISIONS.md 存在且可解析，但無任何類型＝豁免的條目'; ExpiredEntries = @(); MalformedEntries = @() }
    }

    $malformed = @()
    $expired = @()
    foreach ($row in $exemptionRows) {
        $pc = ConvertFrom-ExemptionContentCell -Content $row.Content
        if (-not $pc.WellFormed) {
            $malformed += [pscustomobject]@{ Id = $row.Id; Date = $row.Date; Detail = $pc.Detail }
            continue
        }
        $exp = Test-ExemptionEntryExpired -ParsedContent $pc -AsOfDate $AsOfDate
        if ($exp.Expired) {
            $expired += [pscustomobject]@{ Id = $row.Id; Date = $row.Date; Deadline = $pc.DeadlineRaw; Detail = $exp.Detail }
        }
    }
    $malformed = @($malformed)
    $expired = @($expired)

    if ($malformed.Count -gt 0) {
        if ($BypassFailClosedForRedTest) {
            return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'pass-BYPASS'; Detail = "[BYPASS-RED-TEST] 豁免條目格式不合本應 fail-closed，旗標開啟後被錯誤地視為通過：$($malformed.Count) 筆格式不合"; ExpiredEntries = $expired; MalformedEntries = $malformed }
        }
        return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'fail-malformed-exemption'; Detail = "$($malformed.Count) 筆豁免條目格式不合，fail-closed：" + (($malformed | ForEach-Object { "$($_.Id)：$($_.Detail)" }) -join '；'); ExpiredEntries = $expired; MalformedEntries = $malformed }
    }

    if ($expired.Count -gt 0) {
        if ($BypassFailClosedForRedTest) {
            return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'pass-BYPASS'; Detail = "[BYPASS-RED-TEST] 過期豁免本應 fail-closed，旗標開啟後被錯誤地視為通過：$($expired.Count) 筆已過期"; ExpiredEntries = $expired; MalformedEntries = $malformed }
        }
        return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'fail-expired-exemption'; Detail = "$($expired.Count) 筆豁免已過期，本次 gate fail 並落 sc:gate-fail：" + (($expired | ForEach-Object { "$($_.Id)（期限 $($_.Deadline)）" }) -join '、'); ExpiredEntries = $expired; MalformedEntries = $malformed }
    }

    return [pscustomobject]@{ Repo = $RepoLabel; Outcome = 'pass-all-valid'; Detail = "共 $($exemptionRows.Count) 筆豁免條目，格式皆合規且皆未過期"; ExpiredEntries = @(); MalformedEntries = @() }
}

# ============================================================================
# 第四層：GitHub 讀取（唯讀，GET only）——以可注入的 -HttpGetFunc／-FetchFunction 支援離線測試，
# 不需 mock .NET 例外物件內部結構（比照的是「乾淨的相依注入」，非依賴 Invoke-RestMethod 例外殼層）。
# ============================================================================
function Invoke-GithubGetRaw {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][hashtable]$Headers)
    try {
        $resp = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get
        return [pscustomobject]@{ Success = $true; StatusCode = 200; Body = $resp; ErrorMessage = $null }
    } catch {
        $statusCode = $null
        try { if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode.value__ } } catch { }
        return [pscustomobject]@{ Success = $false; StatusCode = $statusCode; Body = $null; ErrorMessage = $_.Exception.Message }
    }
}

# 回傳 FetchResult：{ Exists; ErrorKind('none'|'not-found'|'read-error'); Content; ErrorDetail }
function Get-DecisionsFileFetchResult {
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][hashtable]$Headers,
        [scriptblock]$HttpGetFunc = $null
    )
    $uri = "https://api.github.com/repos/$Owner/$Repo/contents/DECISIONS.md"
    $raw = if ($HttpGetFunc) { & $HttpGetFunc $uri $Headers } else { Invoke-GithubGetRaw -Uri $uri -Headers $Headers }

    if ($raw.Success) {
        try {
            $b64 = ($raw.Body.content -replace "`n", '') -replace "`r", ''
            $bytes = [Convert]::FromBase64String($b64)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            return [pscustomobject]@{ Exists = $true; ErrorKind = 'none'; Content = $text; ErrorDetail = $null }
        } catch {
            return [pscustomobject]@{ Exists = $true; ErrorKind = 'read-error'; Content = $null; ErrorDetail = "base64 解碼失敗：$($_.Exception.Message)" }
        }
    }
    if ($raw.StatusCode -eq 404) {
        return [pscustomobject]@{ Exists = $false; ErrorKind = 'not-found'; Content = $null; ErrorDetail = $null }
    }
    return [pscustomobject]@{ Exists = $false; ErrorKind = 'read-error'; Content = $null; ErrorDetail = "讀取失敗，HTTP 狀態=$($raw.StatusCode)，訊息=$($raw.ErrorMessage)" }
}

# ============================================================================
# 第五層：涵蓋範圍檢查——「掃描涵蓋 anchor body 宣告的全部參與 repo，缺一未掃即算失敗」
# ============================================================================
function Test-RepoScanCoverage {
    param([string[]]$Expected = @(), [string[]]$Actual = @())
    $Expected = @($Expected)
    $Actual = @($Actual)
    $expectedNorm = @($Expected | ForEach-Object { $_.Trim().ToLowerInvariant() } | Select-Object -Unique)
    $actualNorm = @($Actual | ForEach-Object { $_.Trim().ToLowerInvariant() } | Select-Object -Unique)
    $missing = @($expectedNorm | Where-Object { $actualNorm -notcontains $_ })
    $complete = ($missing.Count -eq 0)
    $detail = if ($complete) {
        "涵蓋全部 $($expectedNorm.Count) 個參與 repo"
    } else {
        "缺漏未掃 repo：$($missing -join '、')（anchor body 宣告 $($expectedNorm.Count) 個，實際掃 $($actualNorm.Count) 個）"
    }
    return [pscustomobject]@{ Complete = $complete; Missing = $missing; Detail = $detail }
}

# ============================================================================
# 第六層：整合入口——對全部參與 repo 逐一掃描並彙總，唯一對外的頂層判定函式
# ============================================================================
function Invoke-DecisionsExemptionScan {
    param(
        [Parameter(Mandatory)][string[]]$ParticipatingRepos,
        [Parameter(Mandatory)][hashtable]$Headers,
        [datetime]$AsOfDate = (Get-Date),
        [scriptblock]$FetchFunction = $null,
        [switch]$BypassFailClosedForRedTest
    )
    $ParticipatingRepos = @($ParticipatingRepos)
    $perRepo = @()
    $scanned = @()
    foreach ($repoStr in $ParticipatingRepos) {
        $r = Split-RepoString -RepoString $repoStr
        $fr = if ($FetchFunction) {
            & $FetchFunction $r.Owner $r.Repo $Headers
        } else {
            Get-DecisionsFileFetchResult -Owner $r.Owner -Repo $r.Repo -Headers $Headers
        }
        $scanned += $repoStr
        $result = Invoke-DecisionsFileExemptionScan -RepoLabel $repoStr -FetchResult $fr -AsOfDate $AsOfDate -BypassFailClosedForRedTest:$BypassFailClosedForRedTest
        $perRepo += $result
    }
    $perRepo = @($perRepo)
    $scanned = @($scanned)

    $coverage = Test-RepoScanCoverage -Expected $ParticipatingRepos -Actual $scanned
    $failedRepos = @($perRepo | Where-Object { $_.Outcome -like 'fail-*' })

    $overallPass = $coverage.Complete -and (@($failedRepos).Count -eq 0)

    $gaps = @()
    if (-not $coverage.Complete) { $gaps += "[涵蓋範圍] $($coverage.Detail)" }
    foreach ($f in $failedRepos) { $gaps += "[$($f.Repo)] $($f.Outcome)：$($f.Detail)" }
    $gaps = @($gaps)

    return [pscustomobject]@{
        OverallPass = $overallPass
        PerRepo     = $perRepo
        Coverage    = $coverage
        NamedGaps   = $gaps
        Detail      = if ($overallPass) { "全參與 repo（$($ParticipatingRepos.Count) 個）皆掃描完成，無過期／格式不合／讀取失敗／解析失敗豁免問題" } else { $gaps -join '｜' }
    }
}

# ============================================================================
# 第七層：sc:gate-fail 佇列項產生（唯讀 GET 判定 → 只產生佇列項，不直接呼叫 GitHub 寫入 API）
# 本地一份，理由同 T-10 gate-advance.ps1／T-13 gate-station3.ps1 既有先例（file ownership 不得
# 修改 t10／t13／t21，產生權自查邏輯屬各自產生階段責任）。
# ============================================================================
function Get-FullLabelSetWithGateFail {
    param([Parameter(Mandatory)]$Issue)
    $labelsRaw = ConvertTo-SafeArray -RawValue $Issue.labels
    $labelsRaw = @($labelsRaw)
    $names = @($labelsRaw | ForEach-Object { $_.name })
    $desired = @($names + @('sc:gate-fail') | Select-Object -Unique)
    return ,$desired
}

function New-DecisionsGateFailQueueItem {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)]$Issue,
        [Parameter(Mandatory)][string]$Source,
        [string]$Detail = ''
    )
    $labels = Get-FullLabelSetWithGateFail -Issue $Issue
    return [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $Repo; issue = $IssueNumber }
        payload = [pscustomobject]@{ labels = @($labels) }
        source  = $Source
    }
}

function Add-T19QueueItemIfAbsent {
    param([Parameter(Mandatory)][string]$QueuePath, [Parameter(Mandatory)]$Item)
    $existing = Read-QueueFile -QueuePath $QueuePath
    if ($null -eq $existing) { $existing = @() }
    $existing = @($existing)
    $itemTargetJson = $Item.target | ConvertTo-Json -Compress
    $dupe = @($existing | Where-Object {
        $_.action -eq $Item.action -and $_.source -eq $Item.source -and
        (($_.target | ConvertTo-Json -Compress) -eq $itemTargetJson)
    })
    if ($dupe.Count -gt 0) {
        return [pscustomobject]@{ Added = $false; Detail = '佇列中已有相同動作待落地，未重複加入' }
    }
    $updated = @($existing) + @($Item)
    Write-QueueFile -QueuePath $QueuePath -Items $updated
    return [pscustomobject]@{ Added = $true; Detail = '已加入佇列' }
}

# ============================================================================
# CLI 主流程
# ============================================================================
function Invoke-DecisionsScanCli {
    if (-not $PrimaryRepo -or -not $AnchorIssue) {
        throw '直接執行模式須提供 -PrimaryRepo -AnchorIssue（或改用 -FunctionsOnly 供測試 dot-source）'
    }
    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t19-decisions-scan'

    $participating = if (@($ParticipatingRepos).Count -gt 0) { @($ParticipatingRepos) } else { @($PrimaryRepo) }
    $asOf = if ($AsOfDateString) {
        [datetime]::ParseExact($AsOfDateString, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    } else {
        Get-Date
    }

    $result = Invoke-DecisionsExemptionScan -ParticipatingRepos $participating -Headers $Headers -AsOfDate $asOf

    $lines = @("decisions-scan 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PrimaryRepo=$PrimaryRepo  Anchor=#$AnchorIssue  參與repo=[$($participating -join ', ')]  基準日=$($asOf.ToString('yyyy-MM-dd'))", '')
    $lines += "整體判定：$(if ($result.OverallPass) { 'PASS' } else { 'FAIL' })"
    foreach ($pr in $result.PerRepo) { $lines += "  [$($pr.Repo)] $($pr.Outcome) — $($pr.Detail)" }
    $lines += "涵蓋範圍：$($result.Coverage.Detail)"
    if (-not $result.OverallPass) { $lines += ('缺項：' + ($result.NamedGaps -join '｜')) }
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T19ScriptDir 'decisions-scan-report.txt') -Content ($lines -join [Environment]::NewLine)

    if (-not $result.OverallPass) {
        $r = Split-RepoString -RepoString $PrimaryRepo
        $anchor = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $AnchorIssue -Headers $Headers
        if ($null -ne $anchor) {
            $item = New-DecisionsGateFailQueueItem -Repo $PrimaryRepo -IssueNumber $AnchorIssue -Issue $anchor -Source $WorkId -Detail ($result.NamedGaps -join '｜')
            $addResult = Add-T19QueueItemIfAbsent -QueuePath $QueuePath -Item $item
            Write-Host "已產生 sc:gate-fail 佇列項（$($addResult.Detail)）：labels=[$($item.payload.labels -join ', ')]"
            Write-Host "=> 請執行 ..\t21\apply-queue.ps1 -QueuePath `"$QueuePath`" 落地。"
        } else {
            Write-Warning "找不到 anchor（$PrimaryRepo#$AnchorIssue），無法產生 sc:gate-fail 佇列項；請人工確認 anchor 是否存在。"
        }
        exit 1
    }
    exit 0
}

if (-not $FunctionsOnly) {
    Invoke-DecisionsScanCli
}
