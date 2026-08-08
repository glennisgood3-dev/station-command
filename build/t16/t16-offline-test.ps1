#requires -Version 5.1
<#
.SYNOPSIS
    T-16 · 離線 mock 測試（沙盒／CI 皆可跑，不連網，不呼叫真實 GitHub API）。

.DESCRIPTION
    只測 aggregate-board.ps1 的**純函式／可離線注入的函式**：
      Group-FleetIssuesByWorkId       （pure —— 驗收②「誤併」直接打這裡）
      Get-FleetMilestoneRowsForWork   （-MilestoneListFetcher 注入，離線覆蓋補查詢路徑）
      Build-FleetBoardReport          （pure —— 驗收①③④⑤⑥的整合 seam）
      Get-FleetWorkIdFromAnchorBody／Get-FleetWorkIdFromMilestoneDescription／ConvertTo-FleetIssue（字串工具）
      Read-FleetQueueInfoForWork      （真讀本機暫存檔，不連網）
    全程不呼叫 Get-FleetSnapshot（唯一打真實 GitHub API 的函式，未在本沙盒實跑，見 README「deferred」）。

    **獨立預期值來源**（Spec §3.5 註 C）：本檔頂部的 `$Script:FixtureWorkRepoMap`／各筆 mock
    milestone 的 open/closed 數字，皆為測試作者手寫的固定字面值，🚫 不曾由 Group-FleetIssuesByWorkId／
    Get-FleetMilestoneRowsForWork／Build-FleetBoardReport 自身算過再回填——比對時一律拿這些固定值當
    期望值，被測函式的輸出只出現在「實際值」那一側。

    **紅燈設計**（Spec §6 註 A：紅是斷言失敗的紅，非載入／collection 失敗）：
      群組 A 用 `-BugGroupByMilestoneTitle` 讓「不同 work-id 不得合併」斷言真的失敗一次（存證＋
      meta-assertion 確認其真的失敗），再關閉旗標重跑同一斷言轉綠。
      群組 D 用 `-SkipNoBaselineBanner` 讓「無基線 banner 必須存在」斷言真的失敗一次，同理轉綠。
      兩旗標皆標註「⚠️ 僅供紅燈驗證，正式流程禁用」，aggregate-board.ps1 的 `Invoke-FleetBoardRender`
      預設路徑（`if (-not $T16FunctionsOnly)`）從不帶入這兩個旗標。

    覆蓋範圍：
      群組 A：分組正確性（誤併紅燈＋fixture 期望值）
      群組 B：逐 repo milestone 進度（ticket 隨附路徑＋補查詢注入路徑，皆以 description 而非 title 比對）
      群組 C：多字卡 render、欄位總數不新增（§4.1 硬性約束）、同 work 跨 repo 分列不合成單一數字（驗收①）
      群組 D：anchor 消失偵測（驗收③）＋無基線紅燈（驗收④的前置條件）
      群組 E：零筆＋無基線並列（驗收⑤）
      群組 F：刪除面板快取後字卡內容不變（驗收④）
      群組 G：站別竄改 ⇒ 字卡紅燈標「站別來源不明」（驗收⑥）
      群組 H：PS 5.1／StrictMode 陷阱回歸測試
      群組 I：待寫佇列讀取（依 source 篩選 work-id）
      群組 J：ConvertTo-FleetIssue（milestone 欄位正規化）

.NOTES
    執行：/opt/pwsh/pwsh -NoProfile -File t16-offline-test.ps1
    （Windows PowerShell 5.1 亦可跑，語法無用到僅 PS7 才有的功能。）
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
try {
    [Console]::OutputEncoding = $Script:Utf8Bom
    $Global:OutputEncoding = $Script:Utf8Bom
} catch {
    Write-Warning "無法設定主控台輸出編碼，繼續執行：$($_.Exception.Message)"
}

# ⚠️ 命名紀律：本檔頂層一律用 T16Test 前綴，🚫 不與 dot-source 進來的 aggregate-board.ps1／
# render-board.ps1 頂層參數（$T16Repos／$WorkId／$OutputPath…）同名，避免 cascade 覆蓋（T-12/T-13 教訓）。
$T16TestDir = $PSScriptRoot
. "$T16TestDir/aggregate-board.ps1" -T16FunctionsOnly

# ============================================================================
# 極簡斷言框架（比照 t09-offline-test.ps1 風格）
# ============================================================================
$Script:PassCount = 0
$Script:FailCount = 0
$Script:Results = @()
$Script:RedLightLog = @()

function Assert-True {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $Script:PassCount++
        $Script:Results += "[PASS] $Name"
    } else {
        $Script:FailCount++
        $Script:Results += "[FAIL] $Name$(if ($Detail) { " — $Detail" })"
    }
}

function Assert-Equal {
    param([Parameter(Mandatory)][string]$Name, $Expected, $Actual)
    $ok = ($Expected -eq $Actual)
    Assert-True -Name $Name -Condition $ok -Detail "期望=[$Expected] 實際=[$Actual]"
}

function Assert-Match {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Pattern)
    Assert-True -Name $Name -Condition ($Text -match $Pattern) -Detail "pattern=[$Pattern] 未命中"
}

function Assert-NotMatch {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Pattern)
    Assert-True -Name $Name -Condition (-not ($Text -match $Pattern)) -Detail "pattern=[$Pattern] 不應命中但命中了"
}

function Assert-Contains {
    # ⚠️ 陷阱回歸：[Parameter(Mandatory)][array]$Haystack 在傳入**空陣列**時會被 PowerShell 參數繫結
    # 直接拒絕（"Cannot bind argument ... because it is an empty collection"，實測踩到，非假設）——
    # 這與 StrictMode 的三陷阱是同類但另一種形狀，用 [AllowEmptyCollection()] 解除。
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowEmptyCollection()][array]$Haystack, [Parameter(Mandatory)][string]$Needle)
    $found = @($Haystack | Where-Object { $_ -eq $Needle })
    Assert-True -Name $Name -Condition ($found.Count -gt 0) -Detail "需要含 [$Needle]，實際=[$($Haystack -join ',')]"
}

function Assert-NotContains {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowEmptyCollection()][array]$Haystack, [Parameter(Mandatory)][string]$Needle)
    $found = @($Haystack | Where-Object { $_ -eq $Needle })
    Assert-True -Name $Name -Condition ($found.Count -eq 0) -Detail "不應含 [$Needle]，實際=[$($Haystack -join ',')]"
}

# 紅燈存證：真的跑一次會失敗的斷言，記錄下來（不計入主線 PASS/FAIL，避免出貨版本恆紅）；
# 回傳布林值供呼叫端另外用 Assert-True 對「它是否真的失敗了」做 meta 判定（這條 meta 判定才計入主線）。
function Invoke-RedLightCheck {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Assertion)
    try {
        $result = & $Assertion
        if ($result) {
            $Script:RedLightLog += "[RED-EVIDENCE PASS] $Name"
            return $true
        } else {
            $Script:RedLightLog += "[RED-EVIDENCE FAIL（真的斷言失敗，存證）] $Name"
            return $false
        }
    } catch {
        $Script:RedLightLog += "[RED-EVIDENCE FAIL（例外，視同斷言失敗，存證）] $Name — $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# Mock 建構工具
# ============================================================================

$T16TplPath = Join-Path $T16TestDir 'fleet-board-template.html'
if (-not (Test-Path -LiteralPath $T16TplPath)) { throw "找不到樣板：$T16TplPath" }
$T16TemplateContent = Get-Content -LiteralPath $T16TplPath -Raw -Encoding UTF8

function New-FleetMockMilestone {
    <# 正規化後的 .Milestone 子物件（PascalCase），掛在 mock issue 上；與 ConvertTo-FleetIssue 輸出同形。 #>
    param([int]$Number = 1, [string]$Title = 'Sprint', [string]$Description = '', [int]$OpenIssues = 0, [int]$ClosedIssues = 0)
    return [pscustomobject]@{ Number = $Number; Title = $Title; Description = $Description; OpenIssues = $OpenIssues; ClosedIssues = $ClosedIssues }
}

function New-FleetMockRawMilestone {
    <# 模擬真實 REST 回傳形狀（snake_case），供 -MilestoneListFetcher 注入點使用（等同「補查詢」路徑的假回應）。 #>
    param([int]$number = 1, [string]$title = 'Sprint', [string]$description = '', [int]$open_issues = 0, [int]$closed_issues = 0)
    return [pscustomobject]@{ number = $number; title = $title; description = $description; open_issues = $open_issues; closed_issues = $closed_issues }
}

function New-FleetMockIssue {
    param(
        [int]$Number = 1, [string]$Repo = 'acme/plugin', [string]$Title = 'demo',
        [string]$Body = '', [string[]]$Labels = @(), [string]$State = 'open',
        [datetime]$UpdatedAtUtc = (Get-Date).ToUniversalTime(), [bool]$HasAssignee = $false,
        $Milestone = $null
    )
    $issue = [pscustomobject]@{
        Number = $Number; Repo = $Repo; Title = $Title; Body = $Body; Labels = $Labels
        State = $State; UpdatedAtUtc = $UpdatedAtUtc; HasAssignee = $HasAssignee; HtmlUrl = "https://x/$Repo/$Number"
    }
    Add-Member -InputObject $issue -NotePropertyName 'Milestone' -NotePropertyValue $Milestone -Force
    return $issue
}

function New-FleetMockWork {
    param(
        [string]$WorkId, $AnchorIssue = $null, [array]$ParticipatingRepos = @(),
        [array]$Tickets = @(), [array]$MilestoneRows = @(), $QueueInfo = $null
    )
    if ($null -eq $QueueInfo) { $QueueInfo = [pscustomobject]@{ Exists = $false; Count = $null; ParseError = $null } }
    return [pscustomobject]@{
        WorkId = $WorkId; AnchorIssue = $AnchorIssue; ParticipatingRepos = $ParticipatingRepos
        Tickets = $Tickets; MilestoneRows = $MilestoneRows; QueueInfo = $QueueInfo
    }
}

function New-FleetMockSnapshot {
    param(
        [array]$Works = @(), [bool]$Ok = $true, $FailureDetail = $null,
        $ResultCountThisRun = 0, $TotalCountReported = 0, [bool]$HitPageCap = $false,
        [string]$QueryDescription = 'test-query（fixture）', [datetime]$NowUtc = (Get-Date).ToUniversalTime()
    )
    return [pscustomobject]@{
        NowUtc = $NowUtc; Ok = $Ok; FailureDetail = $FailureDetail
        ResultCountThisRun = $ResultCountThisRun; TotalCountReported = $TotalCountReported; HitPageCap = $HitPageCap
        QueryDescription = $QueryDescription; Works = $Works
        UnresolvedTicketsCount = 0; DuplicateAnchorNotes = @()
    }
}

function Invoke-BuildFleet {
    param($Snapshot, $CacheBaseline = $null, [switch]$NoReconcile, [switch]$SkipNoBaselineBanner)
    return Build-FleetBoardReport -Snapshot $Snapshot -TemplateContent $T16TemplateContent -CacheBaseline $CacheBaseline `
        -NowLocal (Get-Date) -TimeZoneLabel 'UTC+8' -NoReconcile:$NoReconcile -SkipNoBaselineBanner:$SkipNoBaselineBanner
}

# ============================================================================
# 獨立預期值來源（Spec §3.5 註 C）：人造 work↔repo 對應表，手寫固定字面，非任何函式輸出回填
# ============================================================================
$Script:FixtureWorkRepoMap = @{
    'W-alpha' = @{ PrimaryRepo = 'acme/repo-a'; ParticipatingRepos = @('acme/repo-a', 'acme/repo-b'); TicketNumber = 101; TicketRepo = 'acme/repo-a' }
    'W-beta'  = @{ PrimaryRepo = 'acme/repo-c'; ParticipatingRepos = @('acme/repo-c');                 TicketNumber = 201; TicketRepo = 'acme/repo-c' }
}

$T16AlphaBody = @"
work-id: W-alpha
primary-repo: acme/repo-a
participating-repos:
- acme/repo-a
- acme/repo-b

demo work alpha
"@

$T16BetaBody = @"
work-id: W-beta
primary-repo: acme/repo-c
participating-repos:
- acme/repo-c

demo work beta
"@

$T16AnchorAlpha = New-FleetMockIssue -Number 1 -Repo 'acme/repo-a' -Title 'Alpha work · primary anchor' -Body $T16AlphaBody -Labels @('sc:work', 'sc:station-3')
$T16AnchorBeta  = New-FleetMockIssue -Number 9 -Repo 'acme/repo-c' -Title 'Beta work · primary anchor'  -Body $T16BetaBody  -Labels @('sc:work', 'sc:station-2')

# 兩張票的 milestone **標題刻意撞名（'Sprint-42'）**，description 內的 work-id 才是真正不同——這正是
# T-16 驗收②要防的情境：「milestone 同名但 work ID 不同 ⇒ 不得合併」。
$T16MsAlpha = New-FleetMockMilestone -Number 11 -Title 'Sprint-42' -Description 'work-id: W-alpha | primary-anchor: acme/repo-a#1' -OpenIssues 1 -ClosedIssues 3
$T16MsBeta  = New-FleetMockMilestone -Number 22 -Title 'Sprint-42' -Description 'work-id: W-beta | primary-anchor: acme/repo-c#9'  -OpenIssues 2 -ClosedIssues 0

$T16TicketAlpha = New-FleetMockIssue -Number 101 -Repo 'acme/repo-a' -Title 'alpha ticket' -Labels @('sc:ticket') -Milestone $T16MsAlpha
$T16TicketBeta  = New-FleetMockIssue -Number 201 -Repo 'acme/repo-c' -Title 'beta ticket'  -Labels @('sc:ticket') -Milestone $T16MsBeta

# ============================================================================
# 群組 A：分組正確性（誤併紅燈 + fixture 期望值）—— Group-FleetIssuesByWorkId
# ============================================================================
Write-Host "`n--- 群組 A：分組正確性（驗收②，誤併紅燈） ---" -ForegroundColor Yellow

$T16AnchorsFixture = @($T16AnchorAlpha, $T16AnchorBeta)
$T16TicketsFixture = @($T16TicketAlpha, $T16TicketBeta)

# --- 紅燈存證：開啟「以 milestone.Title 分組」旁路（複製 T-16 驗收②描述的錯誤行為） ---
$T16BugGrouped = Group-FleetIssuesByWorkId -AnchorIssues $T16AnchorsFixture -TicketIssues $T16TicketsFixture -BugGroupByMilestoneTitle
$T16BugAssertionPassed = Invoke-RedLightCheck -Name '誤併旁路開啟：「不同 work-id 不得合併」斷言（預期真的失敗）' -Assertion {
    $g = $T16BugGrouped.Groups
    $g.ContainsKey('W-alpha') -and $g.ContainsKey('W-beta') -and
    (@($g['W-alpha'].Tickets)).Count -eq 1 -and (@($g['W-beta'].Tickets)).Count -eq 1
}
Assert-True -Name '紅燈存證①：旁路開啟時「不同 work-id 不得合併」斷言確實失敗（誤併真的發生）' -Condition (-not $T16BugAssertionPassed) `
    -Detail '若此項也是 PASS，代表旁路沒有真的製造出誤併，紅燈示範失效——需檢查 BugGroupByMilestoneTitle 是否真的生效'
# 順便具體驗證誤併「長什麼樣」：兩張票被塞進同一個以 milestone 標題為鍵的錯誤群組
Assert-True -Name '紅燈存證①附證：誤併後兩張票被塞進同一個鍵為 Sprint-42（標題）的群組' `
    -Condition ($T16BugGrouped.Groups.ContainsKey('Sprint-42') -and (@($T16BugGrouped.Groups['Sprint-42'].Tickets)).Count -eq 2)

# --- 關閉旁路（正式行為）：重跑同一組輸入，斷言轉綠 ---
$T16FixedGrouped = Group-FleetIssuesByWorkId -AnchorIssues $T16AnchorsFixture -TicketIssues $T16TicketsFixture
Assert-True -Name 'A1 正式模式：W-alpha 與 W-beta 分屬兩個獨立群組' `
    -Condition ($T16FixedGrouped.Groups.ContainsKey('W-alpha') -and $T16FixedGrouped.Groups.ContainsKey('W-beta'))
Assert-Equal -Name 'A2 W-alpha 恰有 1 張票（fixture 期望值）' -Expected 1 -Actual (@($T16FixedGrouped.Groups['W-alpha'].Tickets)).Count
Assert-Equal -Name 'A3 W-beta 恰有 1 張票（fixture 期望值）' -Expected 1 -Actual (@($T16FixedGrouped.Groups['W-beta'].Tickets)).Count
Assert-Equal -Name 'A4 W-alpha 票號＝fixture 期望值 101' -Expected $Script:FixtureWorkRepoMap['W-alpha'].TicketNumber -Actual ($T16FixedGrouped.Groups['W-alpha'].Tickets[0].Number)
Assert-Equal -Name 'A5 W-beta 票號＝fixture 期望值 201' -Expected $Script:FixtureWorkRepoMap['W-beta'].TicketNumber -Actual ($T16FixedGrouped.Groups['W-beta'].Tickets[0].Number)
Assert-Equal -Name 'A6 W-alpha anchor 綁定正確（acme/repo-a#1）' -Expected 'acme/repo-a#1' -Actual "$($T16FixedGrouped.Groups['W-alpha'].AnchorIssue.Repo)#$($T16FixedGrouped.Groups['W-alpha'].AnchorIssue.Number)"
Assert-Equal -Name 'A7 W-alpha ParticipatingRepos＝fixture 期望值' -Expected ($Script:FixtureWorkRepoMap['W-alpha'].ParticipatingRepos -join ',') -Actual (($T16FixedGrouped.Groups['W-alpha'].ParticipatingRepos) -join ',')

# --- 無 milestone 的票（Milestone=$null）⇒ 歸入 UnresolvedTickets，不得被靜默丟進任何群組 ---
$T16OrphanTicket = New-FleetMockIssue -Number 301 -Repo 'acme/repo-z' -Title 'orphan' -Labels @('sc:ticket') -Milestone $null
$T16OrphanGrouped = Group-FleetIssuesByWorkId -AnchorIssues @() -TicketIssues @($T16OrphanTicket)
Assert-Equal -Name 'A8 無 milestone 的票歸入 UnresolvedTickets（不誤入任何 work 群組）' -Expected 1 -Actual (@($T16OrphanGrouped.UnresolvedTickets)).Count
Assert-Equal -Name 'A9 無 milestone 的票不產生任何群組' -Expected 0 -Actual (@($T16OrphanGrouped.Groups.Keys)).Count

Write-Host "`n--- 群組 A 完成 ---"

# ============================================================================
# 群組 B：逐 repo milestone 進度（ticket 隨附路徑 + 補查詢注入路徑，皆以 description 而非 title 比對）
# ============================================================================
Write-Host "`n--- 群組 B：逐 repo milestone 進度（description 比對，非 title） ---" -ForegroundColor Yellow

# repo-b 刻意提供兩個候選 milestone：一個標題也叫 Sprint-42 但 work-id 是別的 work（W-zzz，陷阱）、
# 一個才是真正屬於 W-alpha 的——驗證補查詢路徑不會被「標題撞名」誤導。
$T16FetcherB = {
    param($repo)
    if ($repo -eq 'acme/repo-b') {
        return @(
            (New-FleetMockRawMilestone -number 34 -title 'Sprint-42' -description 'work-id: W-zzz | primary-anchor: acme/repo-b#77' -open_issues 9 -closed_issues 1),
            (New-FleetMockRawMilestone -number 33 -title 'Sprint-42-b' -description 'work-id: W-alpha | primary-anchor: acme/repo-a#1' -open_issues 0 -closed_issues 5)
        )
    }
    if ($repo -eq 'acme/repo-nomatch') {
        return @( (New-FleetMockRawMilestone -number 55 -title 'Unrelated' -description 'work-id: W-other | primary-anchor: acme/repo-x#1' -open_issues 1 -closed_issues 1) )
    }
    return @()
}

$T16RowsAlpha = Get-FleetMilestoneRowsForWork -WorkId 'W-alpha' -ParticipatingRepos @('acme/repo-a', 'acme/repo-b', 'acme/repo-nomatch') `
    -TicketsForWork @($T16TicketAlpha) -MilestoneListFetcher $T16FetcherB

Assert-Equal -Name 'B1 三個參與 repo 都各自出現一列（不合併）' -Expected 3 -Actual (@($T16RowsAlpha)).Count
$T16RowA = $T16RowsAlpha | Where-Object { $_.Repo -eq 'acme/repo-a' } | Select-Object -First 1
$T16RowB = $T16RowsAlpha | Where-Object { $_.Repo -eq 'acme/repo-b' } | Select-Object -First 1
$T16RowNoMatch = $T16RowsAlpha | Where-Object { $_.Repo -eq 'acme/repo-nomatch' } | Select-Object -First 1
Assert-Equal -Name 'B2 repo-a（ticket 隨附路徑）open=1（fixture 期望值）' -Expected 1 -Actual $T16RowA.OpenIssues
Assert-Equal -Name 'B3 repo-a（ticket 隨附路徑）closed=3（fixture 期望值）' -Expected 3 -Actual $T16RowA.ClosedIssues
Assert-Equal -Name 'B4 repo-a 百分比＝75%（fixture 手算：3/(1+3)）' -Expected 75 -Actual $T16RowA.PercentComplete
Assert-Equal -Name 'B5 repo-b（補查詢路徑，以 description 比對）open=0（fixture 期望值，非撞名的 W-zzz 那筆）' -Expected 0 -Actual $T16RowB.OpenIssues
Assert-Equal -Name 'B6 repo-b（補查詢路徑）closed=5（fixture 期望值，非撞名的 W-zzz 那筆）' -Expected 5 -Actual $T16RowB.ClosedIssues
Assert-Equal -Name 'B7 repo-b 百分比＝100%（fixture 手算：5/(0+5)）' -Expected 100 -Actual $T16RowB.PercentComplete
Assert-True -Name 'B8 repo-nomatch 查無屬於本 work 的 milestone ⇒ MilestoneFound=false（不誤配到 W-other 那筆）' -Condition (-not $T16RowNoMatch.MilestoneFound)

Write-Host "`n--- 群組 B 完成 ---"

# ============================================================================
# 群組 C：多字卡 render、欄位不新增（§4.1 硬約束）、同 work 跨 repo 分列不合成單一數字（驗收①）
# ============================================================================
Write-Host "`n--- 群組 C：多字卡 render ---" -ForegroundColor Yellow

$T16QueueEmpty = [pscustomobject]@{ Exists = $false; Count = $null; ParseError = $null }
$T16WorkAlpha = New-FleetMockWork -WorkId 'W-alpha' -AnchorIssue $T16AnchorAlpha -ParticipatingRepos @('acme/repo-a', 'acme/repo-b') `
    -Tickets @($T16TicketAlpha) -MilestoneRows $T16RowsAlpha[0..1] -QueueInfo $T16QueueEmpty
$T16WorkBeta = New-FleetMockWork -WorkId 'W-beta' -AnchorIssue $T16AnchorBeta -ParticipatingRepos @('acme/repo-c') `
    -Tickets @($T16TicketBeta) -MilestoneRows (Get-FleetMilestoneRowsForWork -WorkId 'W-beta' -ParticipatingRepos @('acme/repo-c') -TicketsForWork @($T16TicketBeta)) -QueueInfo $T16QueueEmpty

$T16SnapC = New-FleetMockSnapshot -Works @($T16WorkAlpha, $T16WorkBeta)
$T16RC = Invoke-BuildFleet -Snapshot $T16SnapC -CacheBaseline ([pscustomobject]@{ lastFullSyncTimeUtc = (Get-Date).ToUniversalTime().ToString('o'); lastReconcileTimeUtc = $null; works = @() })

Assert-Match -Name 'C1 兩張字卡皆出現（work-id 文字兩者皆有）' -Text $T16RC.Html -Pattern 'W-alpha'
Assert-Match -Name 'C1b 兩張字卡皆出現（work-id 文字兩者皆有）' -Text $T16RC.Html -Pattern 'W-beta'
$T16DtCount = ([regex]::Matches($T16RC.Html, '<dt>')).Count
Assert-Equal -Name 'C2 兩張字卡的 <dt> 欄位總數＝16（8 欄 x 2 卡，不多不少 ⇒ 未新增欄位，§4.1 硬約束）' -Expected 16 -Actual $T16DtCount
Assert-Match -Name 'C3 同 work 跨 repo：repo-a 的 75% 有出現' -Text $T16RC.Html -Pattern '75%'
Assert-Match -Name 'C3b 同 work 跨 repo：repo-b 的 100% 有出現' -Text $T16RC.Html -Pattern '100%'
Assert-NotMatch -Name 'C4 不得出現任何看起來像合成單一數字的 "87.5%" 或 "88%"（75 與 100 的加權/平均皆不應出現）' -Text $T16RC.Html -Pattern '87\.5%|88%'
$T16RepoProgressLis = ([regex]::Matches($T16RC.Html, '<ul class="repo-progress">.*?</ul>', 'Singleline'))
Assert-True -Name 'C5 至少能定位到兩段 repo-progress 清單（W-alpha 一段、W-beta 一段）' -Condition ($T16RepoProgressLis.Count -ge 2)

Write-Host "`n--- 群組 C 完成 ---"

# ============================================================================
# 群組 D：anchor 消失偵測（驗收③）＋ 無基線紅燈（驗收④前置）
# ============================================================================
Write-Host "`n--- 群組 D：anchor 消失偵測 + 無基線紅燈 ---" -ForegroundColor Yellow

$T16BaselineWithOldAndDone = [pscustomobject]@{
    lastFullSyncTimeUtc = (Get-Date).AddHours(-1).ToUniversalTime().ToString('o')
    lastReconcileTimeUtc = $null
    works = @(
        @{ workId = 'W-old'; station = 'sc:station-3'; primaryRepo = 'acme/repo-old' },
        @{ workId = 'W-done'; station = 'sc:station-done'; primaryRepo = 'acme/repo-done' },
        @{ workId = 'W-alpha'; station = 'sc:station-3'; primaryRepo = 'acme/repo-a' }
    )
}
$T16SnapD = New-FleetMockSnapshot -Works @($T16WorkAlpha)  # 本輪只找到 W-alpha；W-old／W-done 皆不在
$T16RD = Invoke-BuildFleet -Snapshot $T16SnapD -CacheBaseline $T16BaselineWithOldAndDone

Assert-Contains -Name 'D1 驗收③：ErrorStates 含 disappeared' -Haystack $T16RD.ErrorStates -Needle 'disappeared'
Assert-Match -Name 'D2 驗收③：banner／摘要含「工作消失」＋ work ID（W-old）＋ 上次所見站別（sc:station-3）' -Text $T16RD.Html -Pattern '工作消失.*?W-old.*?sc:station-3'
Assert-NotMatch -Name 'D3 sc:station-done 的 W-done 不得被判定為消失（§4.4：站別非 done 才算異常）' -Text $T16RD.Html -Pattern 'W-done'

# --- 紅燈存證：無基線時，banner 若被旁路旗標關掉，「banner 必須存在」斷言必須真的失敗 ---
$T16RDSkip = Invoke-BuildFleet -Snapshot $T16SnapD -CacheBaseline $null -SkipNoBaselineBanner
$T16NoBaselineAssertionPassed = Invoke-RedLightCheck -Name '無基線旁路開啟：「消失偵測不可用（無基線）banner 必須存在」斷言（預期真的失敗）' -Assertion {
    $T16RDSkip.ErrorStates -contains 'no-baseline'
}
Assert-True -Name '紅燈存證②：旁路開啟時「無基線 banner 必須存在」斷言確實失敗' -Condition (-not $T16NoBaselineAssertionPassed) `
    -Detail '若此項也是 PASS，代表旁路沒有真的抑制 banner，紅燈示範失效'

# --- 關閉旁路：無基線時 banner 必須出現（正式行為，轉綠） ---
$T16RDNormal = Invoke-BuildFleet -Snapshot $T16SnapD -CacheBaseline $null
Assert-Contains -Name 'D4 正式模式：CacheBaseline=$null 時「消失偵測不可用（無基線）」banner 存在' -Haystack $T16RDNormal.ErrorStates -Needle 'no-baseline'
Assert-Match -Name 'D5 正式模式：banner 文案含「消失偵測不可用（無基線）」字樣' -Text $T16RDNormal.Html -Pattern '消失偵測不可用（無基線）'

Write-Host "`n--- 群組 D 完成 ---"

# ============================================================================
# 群組 E：零筆＋無基線並列（驗收⑤）
# ============================================================================
Write-Host "`n--- 群組 E：零筆＋無基線並列 ---" -ForegroundColor Yellow

$T16SnapEmpty = New-FleetMockSnapshot -Works @()
$T16RE = Invoke-BuildFleet -Snapshot $T16SnapEmpty -CacheBaseline $null
Assert-Match -Name 'E1 空狀態卡「目前無 active work」存在' -Text $T16RE.Html -Pattern '目前無 active work'
Assert-Contains -Name 'E2 無基線 banner 亦存在（兩者並列，🚫 不得只顯示其中一個）' -Haystack $T16RE.ErrorStates -Needle 'no-baseline'
Assert-Contains -Name 'E3 empty kind 亦記錄在 ErrorStates（供呼叫端內部判斷用）' -Haystack $T16RE.ErrorStates -Needle 'empty'

# 對照組：零筆＋有基線 ⇒ 只有空狀態卡，不應出現無基線 banner
$T16REWithBaseline = Invoke-BuildFleet -Snapshot $T16SnapEmpty -CacheBaseline ([pscustomobject]@{ lastFullSyncTimeUtc = (Get-Date).ToUniversalTime().ToString('o'); works = @() })
Assert-NotContains -Name 'E4 對照組：零筆＋有基線 ⇒ 不應出現無基線 banner' -Haystack $T16REWithBaseline.ErrorStates -Needle 'no-baseline'

Write-Host "`n--- 群組 E 完成 ---"

# ============================================================================
# 群組 F：刪除面板 artifact 後字卡內容不變（驗收④）
# ============================================================================
Write-Host "`n--- 群組 F：字卡內容於快取有無之間保持一致 ---" -ForegroundColor Yellow

$T16SnapF = New-FleetMockSnapshot -Works @($T16WorkAlpha, $T16WorkBeta)
$T16RFBefore = Invoke-BuildFleet -Snapshot $T16SnapF -CacheBaseline $T16BaselineWithOldAndDone
$T16RFAfterDeleted = Invoke-BuildFleet -Snapshot $T16SnapF -CacheBaseline $null   # 模擬 artifact 被刪除後首刷（無基線）

Assert-Equal -Name 'F1 驗收④：刪除快取前後，字卡本體（CardsHtml）逐字相同' -Expected $T16RFBefore.CardsHtml -Actual $T16RFAfterDeleted.CardsHtml
Assert-Contains -Name 'F2 驗收④：刪除快取後首刷出現「消失偵測不可用（無基線）」' -Haystack $T16RFAfterDeleted.ErrorStates -Needle 'no-baseline'
Assert-NotContains -Name 'F3 對照：刪除前（有基線）不應出現無基線 banner' -Haystack $T16RFBefore.ErrorStates -Needle 'no-baseline'

Write-Host "`n--- 群組 F 完成 ---"

# ============================================================================
# 群組 G：站別竄改 ⇒ 字卡紅燈標「站別來源不明」（驗收⑥）
# ============================================================================
Write-Host "`n--- 群組 G：站別竄改偵測 ---" -ForegroundColor Yellow

# G1：站別 label 被整個拔掉（竄改手法一：手動移除）
$T16AnchorNoStation = New-FleetMockIssue -Number 5 -Repo 'acme/repo-g' -Title 'tampered work · primary anchor' `
    -Body "work-id: W-tampered-1`nprimary-repo: acme/repo-g`nparticipating-repos:`n- acme/repo-g`n" -Labels @('sc:work')
$T16WorkG1 = New-FleetMockWork -WorkId 'W-tampered-1' -AnchorIssue $T16AnchorNoStation -ParticipatingRepos @('acme/repo-g') -Tickets @() -MilestoneRows @()
$T16RG1 = Invoke-BuildFleet -Snapshot (New-FleetMockSnapshot -Works @($T16WorkG1)) -CacheBaseline ([pscustomobject]@{ works = @() })
Assert-Match -Name 'G1 驗收⑥：站別 label 缺席（竄改手法一）⇒ 字卡含「站別來源不明」' -Text $T16RG1.Html -Pattern '站別來源不明'
Assert-Match -Name 'G1b 驗收⑥：狀態燈為紅' -Text $T16RG1.Html -Pattern 'dot dot--red'

# G2：站別 label 被改成兩個互斥值同時存在（竄改手法二：手動加了一個沒清掉舊的）
$T16AnchorDualStation = New-FleetMockIssue -Number 6 -Repo 'acme/repo-g' -Title 'tampered work 2 · primary anchor' `
    -Body "work-id: W-tampered-2`nprimary-repo: acme/repo-g`nparticipating-repos:`n- acme/repo-g`n" -Labels @('sc:work', 'sc:station-2', 'sc:station-4')
$T16WorkG2 = New-FleetMockWork -WorkId 'W-tampered-2' -AnchorIssue $T16AnchorDualStation -ParticipatingRepos @('acme/repo-g') -Tickets @() -MilestoneRows @()
$T16RG2 = Invoke-BuildFleet -Snapshot (New-FleetMockSnapshot -Works @($T16WorkG2)) -CacheBaseline ([pscustomobject]@{ works = @() })
Assert-Match -Name 'G2 驗收⑥：站別 label 雙重存在（竄改手法二）⇒ 字卡含「站別來源不明」（t09 原文未含此字樣，靠 t16 包裝補上）' -Text $T16RG2.Html -Pattern '站別來源不明'
Assert-Match -Name 'G2b 驗收⑥：狀態燈為紅' -Text $T16RG2.Html -Pattern 'dot dot--red'

# 對照組：正常單一站別 label ⇒ 不應出現「站別來源不明」
$T16RG3 = Invoke-BuildFleet -Snapshot (New-FleetMockSnapshot -Works @($T16WorkAlpha)) -CacheBaseline ([pscustomobject]@{ works = @() })
Assert-NotMatch -Name 'G3 對照組：正常單一站別 label ⇒ 不出現「站別來源不明」' -Text $T16RG3.Html -Pattern '站別來源不明'

Write-Host "`n--- 群組 G 完成 ---"

# ============================================================================
# 群組 H：PS 5.1／StrictMode 陷阱回歸測試
# ============================================================================
Write-Host "`n--- 群組 H：StrictMode 陷阱回歸 ---" -ForegroundColor Yellow

# H1：Group-FleetIssuesByWorkId 餵全空陣列不得拋例外，且回傳的 Groups 是可安全 .Count 的容器
$T16EmptyGrouped = Group-FleetIssuesByWorkId -AnchorIssues @() -TicketIssues @()
Assert-Equal -Name 'H1 全空輸入 ⇒ Groups.Count=0（不拋例外）' -Expected 0 -Actual (@($T16EmptyGrouped.Groups.Keys)).Count

# H2：Get-FleetMilestoneRowsForWork 餵零參與 repo，回傳空陣列而非 1 元素 $null 陣列（陷阱③回歸）
$T16ZeroRows = Get-FleetMilestoneRowsForWork -WorkId 'W-x' -ParticipatingRepos @() -TicketsForWork @()
$T16ZeroRowsSafe = ConvertTo-SafeArray -RawValue $T16ZeroRows
Assert-Equal -Name 'H2 零參與 repo ⇒ 逐 repo 進度陣列為 0 筆（非 1 筆內容 $null）' -Expected 0 -Actual $T16ZeroRowsSafe.Count

# H3：Build-FleetBoardReport 餵 Works=@()（單一空陣列賦值，非表達式管線）不得把 isEmpty 判斷判錯
$T16RH3 = Invoke-BuildFleet -Snapshot (New-FleetMockSnapshot -Works @()) -CacheBaseline ([pscustomobject]@{ works = @() })
Assert-Contains -Name 'H3 Works=@() ⇒ ErrorStates 含 empty（陷阱②回歸：陳述式賦值不被管線攤平成 $null）' -Haystack $T16RH3.ErrorStates -Needle 'empty'

# H4：CacheBaseline.works 只有 1 筆（PowerShell 對「1 元素陣列」在某些序列化路徑會攤平成純量，
# 這裡驗證 ConvertTo-SafeArray 包過的 baselineWorks 迭代不受影響）
$T16OneWorkBaseline = [pscustomobject]@{ works = @{ workId = 'W-solo'; station = 'sc:station-1'; primaryRepo = 'acme/solo' } }
$T16RH4 = Invoke-BuildFleet -Snapshot (New-FleetMockSnapshot -Works @()) -CacheBaseline $T16OneWorkBaseline
Assert-Match -Name 'H4 CacheBaseline.works 只有 1 筆（非陣列型態）仍被正確視為消失（陷阱①/③回歸）' -Text $T16RH4.Html -Pattern 'W-solo'

# H5：陷阱②回歸（實際踩過一次的真實 bug）——New-FleetWorkCardModel 的 OtherRepos 恰有 1 個元素時，
# 若曾誤用 if/elseif/else「表達式賦值」，該元素會被攤平成純量，下游 Build-WorkCardHtml 對
# .Count 取值會在 StrictMode 直接拋「屬性 Count 找不到」。此處鎖住修正後的正確行為。
$T16ModelH5 = New-FleetWorkCardModel -WorkId 'W-h5' -AnchorIssue $T16AnchorAlpha -ParticipatingRepos @('acme/repo-a', 'acme/repo-b') `
    -Tickets @() -MilestoneRows @() -QueueInfo $T16QueueEmpty -NowUtc (Get-Date).ToUniversalTime() -LastFullSyncText 'now'
Assert-Equal -Name 'H5 OtherRepos 恰有 1 個元素時型別仍是陣列（陷阱②真實回歸，非假設）' -Expected 'System.Object[]' -Actual $T16ModelH5.OtherRepos.GetType().FullName
Assert-Equal -Name 'H5b OtherRepos.Count=1（不拋例外）' -Expected 1 -Actual $T16ModelH5.OtherRepos.Count
$T16Html5 = Build-WorkCardHtml -Model $T16ModelH5
Assert-Match -Name 'H5c Build-WorkCardHtml 對此 Model 成功產生 HTML（不拋例外）' -Text $T16Html5 -Pattern 'acme/repo-b'

Write-Host "`n--- 群組 H 完成 ---"

# ============================================================================
# 群組 I：待寫佇列讀取（依 source 篩選 work-id）
# ============================================================================
Write-Host "`n--- 群組 I：待寫佇列（依 work-id 篩選） ---" -ForegroundColor Yellow

$T16QueueTestDir = Join-Path ([System.IO.Path]::GetTempPath()) ("t16-queue-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $T16QueueTestDir -Force | Out-Null
try {
    $T16QNotExist = Join-Path $T16QueueTestDir 'no-such-queue.json'
    $T16IQ1 = Read-FleetQueueInfoForWork -QueuePath $T16QNotExist -WorkId 'W-alpha'
    Assert-True -Name 'I1 佇列檔不存在 ⇒ Exists=false（合法狀態，非 0 筆）' -Condition (-not $T16IQ1.Exists)

    $T16QEmpty = Join-Path $T16QueueTestDir 'empty-queue.json'
    Write-Utf8BomFile -Path $T16QEmpty -Content ''
    $T16IQ2 = Read-FleetQueueInfoForWork -QueuePath $T16QEmpty -WorkId 'W-alpha'
    Assert-True -Name 'I2 空檔案 ⇒ Exists=true, Count=0' -Condition ($T16IQ2.Exists -and $T16IQ2.Count -eq 0)

    $T16QBad = Join-Path $T16QueueTestDir 'bad-queue.json'
    Write-Utf8BomFile -Path $T16QBad -Content '{not valid json,,,'
    $T16IQ3 = Read-FleetQueueInfoForWork -QueuePath $T16QBad -WorkId 'W-alpha'
    Assert-True -Name 'I3 JSON 壞掉 ⇒ ParseError 非空（🚫 不得靜默當 0 筆）' -Condition ($T16IQ3.Exists -and $null -ne $T16IQ3.ParseError)

    $T16QGood = Join-Path $T16QueueTestDir 'good-queue.json'
    $T16QueueJson = @"
[
  { "action": "set-assignee", "target": { "repo": "acme/repo-a", "issue": 101 }, "payload": {}, "source": "W-alpha" },
  { "action": "comment", "target": { "repo": "acme/repo-a", "issue": 101 }, "payload": {}, "source": "W-alpha" },
  { "action": "set-assignee", "target": { "repo": "acme/repo-c", "issue": 201 }, "payload": {}, "source": "W-beta" }
]
"@
    Write-Utf8BomFile -Path $T16QGood -Content $T16QueueJson
    $T16IQ4Alpha = Read-FleetQueueInfoForWork -QueuePath $T16QGood -WorkId 'W-alpha'
    $T16IQ4Beta = Read-FleetQueueInfoForWork -QueuePath $T16QGood -WorkId 'W-beta'
    Assert-Equal -Name 'I4 依 source 篩選：W-alpha 恰有 2 筆（fixture 期望值）' -Expected 2 -Actual $T16IQ4Alpha.Count
    Assert-Equal -Name 'I5 依 source 篩選：W-beta 恰有 1 筆（fixture 期望值）' -Expected 1 -Actual $T16IQ4Beta.Count
} finally {
    Remove-Item -LiteralPath $T16QueueTestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n--- 群組 I 完成 ---"

# ============================================================================
# 群組 J：ConvertTo-FleetIssue（milestone 欄位正規化）
# ============================================================================
Write-Host "`n--- 群組 J：ConvertTo-FleetIssue milestone 正規化 ---" -ForegroundColor Yellow

$T16RawIssueWithMilestone = [pscustomobject]@{
    number = 42; title = 'raw issue'; body = 'work-id: W-raw'; state = 'open'
    updated_at = (Get-Date).ToUniversalTime().ToString('o'); html_url = 'https://x/42'
    labels = @([pscustomobject]@{ name = 'sc:ticket' })
    assignees = @()
    repository_url = 'https://api.github.com/repos/acme/repo-raw'
    milestone = [pscustomobject]@{ number = 7; title = 'RawSprint'; description = "work-id: W-raw | primary-anchor: acme/repo-raw#1"; open_issues = 2; closed_issues = 6 }
}
$T16ConvertedWithMs = ConvertTo-FleetIssue -RawIssue $T16RawIssueWithMilestone
Assert-Equal -Name 'J1 Milestone.Title 正確帶出' -Expected 'RawSprint' -Actual $T16ConvertedWithMs.Milestone.Title
Assert-Equal -Name 'J2 Milestone.OpenIssues 正確帶出' -Expected 2 -Actual $T16ConvertedWithMs.Milestone.OpenIssues
Assert-Equal -Name 'J3 Milestone.ClosedIssues 正確帶出' -Expected 6 -Actual $T16ConvertedWithMs.Milestone.ClosedIssues
Assert-Equal -Name 'J4 Repo 由 repository_url 正確解出（複用 t09 ConvertTo-BoardIssue 邏輯）' -Expected 'acme/repo-raw' -Actual $T16ConvertedWithMs.Repo

$T16RawIssueNoMilestone = [pscustomobject]@{
    number = 43; title = 'no milestone'; body = ''; state = 'open'
    updated_at = (Get-Date).ToUniversalTime().ToString('o'); html_url = 'https://x/43'
    labels = @([pscustomobject]@{ name = 'sc:work' })
}
$T16ConvertedNoMs = ConvertTo-FleetIssue -RawIssue $T16RawIssueNoMilestone
Assert-True -Name 'J5 無 milestone 欄位 ⇒ .Milestone 為 $null（不得拋例外或誤造假物件）' -Condition ($null -eq $T16ConvertedNoMs.Milestone)

Write-Host "`n--- 群組 J 完成 ---"

# ============================================================================
# 總結
# ============================================================================
Write-Host "`n==================== 紅燈存證 log（不計入下方 PASS/FAIL 總計） ====================" -ForegroundColor Magenta
$Script:RedLightLog | ForEach-Object { Write-Host $_ -ForegroundColor Magenta }

Write-Host "`n==================== 總結 ====================" -ForegroundColor Cyan
$Script:Results | ForEach-Object {
    if ($_ -like '[PASS]*') { Write-Host $_ -ForegroundColor Green } else { Write-Host $_ -ForegroundColor Red }
}
Write-Host "`n通過：$Script:PassCount　失敗：$Script:FailCount　總計：$($Script:PassCount + $Script:FailCount)"

if ($Script:FailCount -gt 0) {
    Write-Host "`n離線測試：FAIL（有 $Script:FailCount 項斷言失敗）" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n離線測試：PASS（全數 $Script:PassCount 項斷言通過）" -ForegroundColor Green
    exit 0
}
