#requires -Version 5.1
<#
.SYNOPSIS
    T-17 · 離線 mock 測試（沙盒／CI 皆可跑，不連網，不呼叫真實 GitHub API，不寫 plans/ 以外的任何檔案）。

.DESCRIPTION
    只測 reconcile-board.ps1 的**純函式／可離線注入的函式**：
      Compare-PlanVsGithubTickets       （pure —— 驗收②「漂移筆數＝差異集筆數」直接打這裡）
      Get-ReconcileStateForWork         （pure —— 驗收①④＋兩條紅燈正向斷言的核心 seam）
      Get-PlanWorkRecord                （真讀本機臨時 fixture 目錄／-PlanReader 注入，決定性重現三種
                                          plans/ 情境）
      New-ReconciledFleetWorkCardModel  （呼叫 t16 New-FleetWorkCardModel＋覆寫既有欄位，不新增欄位）
      Build-ReconciledFleetBoardReport  （pure —— 驗收①②③④的整合 seam；透過 Build-WorkCardHtml
                                          產生真實可讀的 HTML，斷言在 HTML 字面內容上做，不是只在
                                          model 物件層面斷言）
      Get-PlansTreeDigest／Get-SnapshotDigest（守恆檢查工具）
    全程不呼叫 Get-FleetSnapshot（唯一打真實 GitHub API 的函式，本票不新增任何 GitHub 呼叫，繼承 T-16
    既有的「未在本沙盒實跑」誠實聲明，見 T-16 README）。

    **獨立預期值來源**（Spec §3.5 註 C）：本檔頂部 `$Script:FixtureDriftSet`（人造差異集：手寫的
    plan 側票清單與 GitHub 側票清單，逐筆列出應落在哪一類漂移、應有幾筆）與各 plans/ fixture 檔案內容
    （手寫 JSON 字面值）皆為測試作者固定字面值，🚫 從未由 Compare-PlanVsGithubTickets／
    Get-ReconcileStateForWork／Build-ReconciledFleetBoardReport 自身算過再回填——比對時一律拿這些
    固定值當 `-Expected`，被測函式輸出只出現在 `-Actual` 那一側。

    **紅燈設計**（Spec §6 註 A：紅是斷言失敗的紅，非載入／collection 失敗；T-17 票面原文：
    「先對人造差異集跑『漂移筆數＝差異集筆數』與『範圍外標示存在且非綠燈』兩條正向斷言 ⇒ 必紅」）：
      群組 G 用 `-BugDisableReconcile` 讓這兩條斷言各自真的失敗一次（存證＋meta-assertion 確認其
      真的失敗），再關閉旗標重跑同一組輸入 ⇒ 轉綠。旗標標註「⚠️ 僅供紅燈驗證，正式流程禁用」，
      reconcile-board.ps1 的 `Invoke-ReconciledBoardRender` 預設路徑（`if (-not $T17FunctionsOnly)`）
      從不帶入此旗標。

    覆蓋範圍：
      群組 A：Compare-PlanVsGithubTickets 漂移三類（各自獨立＋組合＋零漂移＋「預期缺席不算漂移」規則）
      群組 B：Get-PlanWorkRecord 三種 plans/ 情境（根目錄不存在／work 查無／work 讀取失敗），真讀臨時檔案
      群組 C：Get-ReconcileStateForWork 四態決定（not-executed／out-of-scope／in-scope-clean／in-scope-drift）
      群組 D：New-ReconciledFleetWorkCardModel＋Build-WorkCardHtml 整合，HTML 字面斷言（驗收①②）
      群組 E：NoReconcile 模式不受干擾（驗收③，確認 t16 既有「本次未對帳」文案原樣通過）
      群組 F：Build-ReconciledFleetBoardReport 端到端，plans/ 不可用 ⇒ 全部字卡「對帳未執行」（驗收④）
      群組 G：紅燈存證（兩條正向斷言真的失敗一次）
      群組 H：PS 5.1／StrictMode 陷阱回歸測試
      群組 I：只報不修守門（grep 靜態檢查＋守恆檢查：plans/ 樹狀內容雜湊、Snapshot 物件雜湊，前後不變）
      群組 J：三態不塌成兩態（範圍外／未對帳／漂移／對帳未執行 四態互斥且各自可獨立觸發，交叉驗證）

.NOTES
    執行：/opt/pwsh/pwsh -NoProfile -File t17-offline-test.ps1
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

# ⚠️ 命名紀律：本檔頂層一律用 T17Test 前綴，🚫 不與 dot-source 進來的 reconcile-board.ps1／
# aggregate-board.ps1／render-board.ps1 頂層參數（$T17Repos／$T16Repos／$WorkId／$OutputPath…）同名，
# 避免 cascade 覆蓋（T-12/T-13/T-15a 教訓，T-16 檔頭已具名同一風險）。
$T17TestDir = $PSScriptRoot
. "$T17TestDir/reconcile-board.ps1" -T17FunctionsOnly

# ============================================================================
# 極簡斷言框架（比照 t09/t16-offline-test.ps1 風格）
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
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowEmptyCollection()][array]$Haystack, [Parameter(Mandatory)][string]$Needle)
    $found = @($Haystack | Where-Object { $_ -eq $Needle })
    Assert-True -Name $Name -Condition ($found.Count -gt 0) -Detail "需要含 [$Needle]，實際=[$($Haystack -join ',')]"
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

$T17TplPath = Join-Path $T17TestDir '..\t16\fleet-board-template.html'
if (-not (Test-Path -LiteralPath $T17TplPath)) { throw "找不到樣板（T-16 所有，本檔僅讀取）：$T17TplPath" }
$T17TemplateContent = Get-Content -LiteralPath $T17TplPath -Raw -Encoding UTF8

function New-T17MockIssue {
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

function New-T17MockWork {
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

function New-T17MockSnapshot {
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

$T17AnchorBodyTpl = @"
work-id: {0}
primary-repo: {1}
participating-repos:
- {1}

demo work
"@

function New-T17MockAnchor {
    param([string]$WorkId, [string]$Repo = 'acme/repo-a', [int]$Number = 1, [string[]]$ExtraLabels = @())
    $body = ($T17AnchorBodyTpl -f $WorkId, $Repo)
    return New-T17MockIssue -Number $Number -Repo $Repo -Title "$WorkId · primary anchor" -Body $body -Labels (@('sc:work') + $ExtraLabels)
}

# ============================================================================
# 群組 A：Compare-PlanVsGithubTickets（**PURE**，驗收②的唯一測試 seam）
# ============================================================================
Write-Host "`n--- 群組 A：Compare-PlanVsGithubTickets 漂移三類 ---" -ForegroundColor Yellow

# --- 獨立預期值來源：人造差異集（Spec §3.5 註 C，手寫固定字面值） ---
$Script:FixtureDriftSet = @{
    PlanTickets = @(
        [pscustomobject]@{ TicketRef = 'acme/repo-a#101'; Status = 'open' }    # 兩側皆有、狀態一致 ⇒ 不算漂移
        [pscustomobject]@{ TicketRef = 'acme/repo-a#102'; Status = 'open' }    # plan 說 open，GitHub 側缺席 ⇒ plan-only
        [pscustomobject]@{ TicketRef = 'acme/repo-a#103'; Status = 'closed' } # plan 說 closed，GitHub 側缺席 ⇒ 預期缺席，不算漂移
        [pscustomobject]@{ TicketRef = 'acme/repo-a#104'; Status = 'closed' } # 兩側皆有但狀態不同 ⇒ status-mismatch
    )
    GithubTickets = @(
        [pscustomobject]@{ TicketRef = 'acme/repo-a#101'; Status = 'open' }
        [pscustomobject]@{ TicketRef = 'acme/repo-a#104'; Status = 'open' }
        [pscustomobject]@{ TicketRef = 'acme/repo-a#105'; Status = 'open' }    # GitHub 有、plan 完全沒有 ⇒ github-only
    )
    # 人工手算的期望漂移集（筆數與票號皆為實驗者預設值，非任何函式輸出）：
    ExpectedDriftRefs = @('acme/repo-a#102', 'acme/repo-a#104', 'acme/repo-a#105') | Sort-Object
    ExpectedDriftCount = 3
}

$T17DriftResult = Compare-PlanVsGithubTickets -PlanTickets $Script:FixtureDriftSet.PlanTickets -GithubTickets $Script:FixtureDriftSet.GithubTickets
Assert-Equal -Name 'A1 漂移筆數＝人造差異集期望筆數（3）' -Expected $Script:FixtureDriftSet.ExpectedDriftCount -Actual $T17DriftResult.Count
$T17DriftRefsActual = @($T17DriftResult | ForEach-Object { $_.TicketRef } | Sort-Object)
Assert-Equal -Name 'A2 漂移票號逐筆與差異集相符（排序後字串相等）' -Expected ($Script:FixtureDriftSet.ExpectedDriftRefs -join ',') -Actual ($T17DriftRefsActual -join ',')

$T17DriftByRef = @{}
foreach ($d in $T17DriftResult) { $T17DriftByRef[$d.TicketRef] = $d }
Assert-Equal -Name 'A3 #102 判為 plan-only' -Expected 'plan-only' -Actual $T17DriftByRef['acme/repo-a#102'].Kind
Assert-Equal -Name 'A4 #104 判為 status-mismatch' -Expected 'status-mismatch' -Actual $T17DriftByRef['acme/repo-a#104'].Kind
Assert-Equal -Name 'A5 #105 判為 github-only' -Expected 'github-only' -Actual $T17DriftByRef['acme/repo-a#105'].Kind
Assert-True -Name 'A6 #101（一致）不在漂移集內' -Condition (-not $T17DriftByRef.ContainsKey('acme/repo-a#101'))
Assert-True -Name 'A7 #103（plan 標 closed 且 GitHub 側缺席＝預期缺席）不在漂移集內（設計取捨，見檔頭說明）' -Condition (-not $T17DriftByRef.ContainsKey('acme/repo-a#103'))

# --- 零漂移獨立測試 ---
$T17CleanPlan = @([pscustomobject]@{ TicketRef = 'x/y#1'; Status = 'open' })
$T17CleanGithub = @([pscustomobject]@{ TicketRef = 'x/y#1'; Status = 'open' })
$T17CleanResult = Compare-PlanVsGithubTickets -PlanTickets $T17CleanPlan -GithubTickets $T17CleanGithub
Assert-Equal -Name 'A8 完全一致 ⇒ 零漂移' -Expected 0 -Actual $T17CleanResult.Count

# --- 空輸入（陷阱③回歸：函式須能吃空陣列不炸） ---
$T17EmptyResult = Compare-PlanVsGithubTickets -PlanTickets @() -GithubTickets @()
Assert-Equal -Name 'A9 兩側皆空 ⇒ 零漂移、不拋例外' -Expected 0 -Actual (ConvertTo-SafeArray -RawValue $T17EmptyResult).Count

Write-Host "--- 群組 A 完成 ---"

# ============================================================================
# 群組 B：Get-PlanWorkRecord（真讀本機臨時 fixture 目錄，三種情境）
# ============================================================================
Write-Host "`n--- 群組 B：Get-PlanWorkRecord plans/ 三種情境 ---" -ForegroundColor Yellow

$T17PlansFixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) "t17-plans-fixture-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $T17PlansFixtureDir -Force | Out-Null
try {
    # B1：plans 根目錄不存在
    $T17PlansMissingRoot = Join-Path $T17PlansFixtureDir 'does-not-exist'
    $T17B1 = Get-PlanWorkRecord -PlansRoot $T17PlansMissingRoot -WorkId 'W-any'
    Assert-True -Name 'B1 plans 根目錄不存在 ⇒ RootAvailable=false' -Condition (-not $T17B1.RootAvailable)

    # B2：plans 根目錄存在，但查無此 work（範圍外）
    $T17B2 = Get-PlanWorkRecord -PlansRoot $T17PlansFixtureDir -WorkId 'W-not-tracked'
    Assert-True -Name 'B2 根目錄可用但查無此 work ⇒ RootAvailable=true, Found=false' -Condition ($T17B2.RootAvailable -and ($T17B2.Found -eq $false))

    # B3：work 有紀錄，正確解析（獨立預期值：手寫 JSON 字面值）
    $T17WorkFile = Join-Path $T17PlansFixtureDir 'W-demo.json'
    $T17WorkJson = @'
{
  "workId": "W-demo",
  "tickets": [
    { "ticketRef": "acme/repo-a#1", "status": "open" },
    { "ticketRef": "acme/repo-a#2", "status": "closed" }
  ]
}
'@
    [System.IO.File]::WriteAllText($T17WorkFile, $T17WorkJson, $Script:Utf8Bom)
    $T17B3 = Get-PlanWorkRecord -PlansRoot $T17PlansFixtureDir -WorkId 'W-demo'
    Assert-True -Name 'B3 work 有紀錄 ⇒ Found=true' -Condition ($T17B3.RootAvailable -and ($T17B3.Found -eq $true))
    Assert-Equal -Name 'B3b 票數＝fixture 期望值 2' -Expected 2 -Actual (ConvertTo-SafeArray -RawValue $T17B3.Tickets).Count
    Assert-Equal -Name 'B3c 第一筆 TicketRef 正確解析' -Expected 'acme/repo-a#1' -Actual $T17B3.Tickets[0].TicketRef
    Assert-Equal -Name 'B3d 第一筆 Status 正確解析' -Expected 'open' -Actual $T17B3.Tickets[0].Status

    # B4：work 檔案存在但 JSON 壞掉 ⇒ 該 work 局部失敗（Found=$null），不牽連全域
    $T17BadFile = Join-Path $T17PlansFixtureDir 'W-bad.json'
    [System.IO.File]::WriteAllText($T17BadFile, '{not valid json,,,', $Script:Utf8Bom)
    $T17B4 = Get-PlanWorkRecord -PlansRoot $T17PlansFixtureDir -WorkId 'W-bad'
    Assert-True -Name 'B4 JSON 壞掉 ⇒ RootAvailable=true（不牽連全域）, Found=$null（局部失敗）' -Condition ($T17B4.RootAvailable -and ($null -eq $T17B4.Found))
    Assert-True -Name 'B4b FailureDetail 非空（不得靜默）' -Condition (-not [string]::IsNullOrWhiteSpace($T17B4.FailureDetail))

    # B5：-PlanReader 注入點（離線測試決定性重現，不碰檔案系統）
    $T17InjectedReader = { param($root, $wid) [pscustomobject]@{ RootAvailable = $false; Found = $false; Tickets = @(); FailureDetail = 'injected: 模擬權限錯誤' } }
    $T17B5 = Get-PlanWorkRecord -PlansRoot 'irrelevant-path-never-touched' -WorkId 'W-x' -PlanReader $T17InjectedReader
    Assert-True -Name 'B5 -PlanReader 注入生效，完全略過檔案系統' -Condition (-not $T17B5.RootAvailable)
} finally {
    Remove-Item -LiteralPath $T17PlansFixtureDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "--- 群組 B 完成 ---"

# ============================================================================
# 群組 C：Get-ReconcileStateForWork（四態決定，pure）
# ============================================================================
Write-Host "`n--- 群組 C：Get-ReconcileStateForWork 四態決定 ---" -ForegroundColor Yellow

$T17NowLocal = Get-Date

# C1：plans/ 不可用 ⇒ not-executed
$T17C1 = Get-ReconcileStateForWork -RootAvailable $false -PlanRecord ([pscustomobject]@{ Found = $false; Tickets = @(); FailureDetail = $null }) -GithubTickets @() -NowLocal $T17NowLocal
Assert-Equal -Name 'C1 plans 不可用 ⇒ Kind=not-executed' -Expected 'not-executed' -Actual $T17C1.Kind
Assert-Match -Name 'C1b 文案含「對帳未執行」' -Text $T17C1.ReconcileDataTimeText -Pattern '對帳未執行'
Assert-True -Name 'C1c 不強制非綠燈（not-executed 非驗收①的情境，維持中性）' -Condition (-not $T17C1.ForceNonGreen)

# C2：該 work 讀取失敗（Found=$null）⇒ not-executed（局部）
$T17C2 = Get-ReconcileStateForWork -RootAvailable $true -PlanRecord ([pscustomobject]@{ Found = $null; Tickets = @(); FailureDetail = '模擬解析錯誤' }) -GithubTickets @() -NowLocal $T17NowLocal
Assert-Equal -Name 'C2 該 work 讀取失敗 ⇒ Kind=not-executed' -Expected 'not-executed' -Actual $T17C2.Kind
Assert-Match -Name 'C2b 文案帶原始失敗原因' -Text $T17C2.ReconcileDataTimeText -Pattern '模擬解析錯誤'

# C3：plans/ 查無此 work ⇒ out-of-scope（驗收①核心）
$T17C3 = Get-ReconcileStateForWork -RootAvailable $true -PlanRecord ([pscustomobject]@{ Found = $false; Tickets = @(); FailureDetail = $null }) -GithubTickets @() -NowLocal $T17NowLocal
Assert-Equal -Name 'C3 查無此 work ⇒ Kind=out-of-scope' -Expected 'out-of-scope' -Actual $T17C3.Kind
Assert-Match -Name 'C3b 文案含「對帳範圍外」' -Text $T17C3.ReconcileDataTimeText -Pattern '對帳範圍外'
Assert-True -Name 'C3c ForceNonGreen=true（驗收①：該卡非綠燈）' -Condition $T17C3.ForceNonGreen
Assert-Contains -Name 'C3d ExtraStatusReasons 含「對帳範圍外」具名理由' -Haystack (ConvertTo-SafeArray -RawValue $T17C3.ExtraStatusReasons) -Needle '對帳範圍外：plans/ 查無此 work，非已對帳綠燈'

# C4：有紀錄、零漂移 ⇒ in-scope-clean
$T17PlanClean = [pscustomobject]@{ Found = $true; Tickets = @([pscustomobject]@{ TicketRef = 'a/b#1'; Status = 'open' }); FailureDetail = $null }
$T17GhClean = @([pscustomobject]@{ TicketRef = 'a/b#1'; Status = 'open' })
$T17C4 = Get-ReconcileStateForWork -RootAvailable $true -PlanRecord $T17PlanClean -GithubTickets $T17GhClean -NowLocal $T17NowLocal
Assert-Equal -Name 'C4 零漂移 ⇒ Kind=in-scope-clean' -Expected 'in-scope-clean' -Actual $T17C4.Kind
Assert-Equal -Name 'C4b DriftCount=0' -Expected 0 -Actual $T17C4.DriftCount
Assert-True -Name 'C4c 不強制非綠燈' -Condition (-not $T17C4.ForceNonGreen)

# C5：有紀錄、有漂移 ⇒ in-scope-drift（驗收②：DriftCount＝差異集筆數）
$T17PlanDrift = [pscustomobject]@{ Found = $true; Tickets = $Script:FixtureDriftSet.PlanTickets; FailureDetail = $null }
$T17C5 = Get-ReconcileStateForWork -RootAvailable $true -PlanRecord $T17PlanDrift -GithubTickets $Script:FixtureDriftSet.GithubTickets -NowLocal $T17NowLocal
Assert-Equal -Name 'C5 Kind=in-scope-drift' -Expected 'in-scope-drift' -Actual $T17C5.Kind
Assert-Equal -Name 'C5b DriftCount＝人造差異集期望筆數（3）' -Expected $Script:FixtureDriftSet.ExpectedDriftCount -Actual $T17C5.DriftCount
Assert-True -Name 'C5c ForceNonGreen=true（漂移屬對帳異常，§4.1 紅燈定義）' -Condition $T17C5.ForceNonGreen
Assert-Match -Name 'C5d 文案含漂移筆數 3' -Text $T17C5.ReconcileDataTimeText -Pattern '漂移 3 筆'

Write-Host "--- 群組 C 完成 ---"

# ============================================================================
# 群組 D：New-ReconciledFleetWorkCardModel + Build-WorkCardHtml（真實 HTML 字面斷言）
# ============================================================================
Write-Host "`n--- 群組 D：字卡 HTML 整合（驗收①②，真實 render） ---" -ForegroundColor Yellow

$T17AnchorD = New-T17MockAnchor -WorkId 'W-outscope' -Repo 'acme/repo-d' -Number 1 -ExtraLabels @('sc:station-3')
$T17QueueEmpty = [pscustomobject]@{ Exists = $false; Count = $null; ParseError = $null }

# D1：範圍外 ⇒ 字卡 HTML 含「對帳範圍外」且 dot class 非 green（驗收①，逐字對應票面用語）
$T17ModelOutScope = New-ReconciledFleetWorkCardModel -WorkId 'W-outscope' -AnchorIssue $T17AnchorD -ParticipatingRepos @('acme/repo-d') `
    -Tickets @() -MilestoneRows @() -QueueInfo $T17QueueEmpty -NowUtc (Get-Date).ToUniversalTime() `
    -CacheBaseline $null -LastFullSyncText '（測試）' -ReconcileState $T17C3
$T17HtmlOutScope = Build-WorkCardHtml -Model $T17ModelOutScope
Assert-Match -Name 'D1 HTML 含「對帳範圍外」字樣' -Text $T17HtmlOutScope -Pattern '對帳範圍外'
Assert-NotMatch -Name 'D1b HTML 的狀態燈 dot 不是 dot--green（驗收①：該卡非綠燈）' -Text $T17HtmlOutScope -Pattern 'dot dot--green'
Assert-Equal -Name 'D1c Model.StatusColor＝red（範圍外強制非綠燈的實際落點）' -Expected 'red' -Actual $T17ModelOutScope.StatusColor

# D2：有漂移 ⇒ 字卡 HTML 含漂移筆數與燈號理由（驗收②，字卡紅燈標筆數）
$T17AnchorE = New-T17MockAnchor -WorkId 'W-drift' -Repo 'acme/repo-e' -Number 2 -ExtraLabels @('sc:station-4')
$T17ModelDrift = New-ReconciledFleetWorkCardModel -WorkId 'W-drift' -AnchorIssue $T17AnchorE -ParticipatingRepos @('acme/repo-e') `
    -Tickets @() -MilestoneRows @() -QueueInfo $T17QueueEmpty -NowUtc (Get-Date).ToUniversalTime() `
    -CacheBaseline $null -LastFullSyncText '（測試）' -ReconcileState $T17C5
$T17HtmlDrift = Build-WorkCardHtml -Model $T17ModelDrift
Assert-Match -Name 'D2 HTML 含「漂移 3 筆」（驗收②：字卡紅燈標筆數，筆數＝差異集筆數）' -Text $T17HtmlDrift -Pattern '漂移 3 筆'
Assert-NotMatch -Name 'D2b HTML 的狀態燈 dot 不是 dot--green' -Text $T17HtmlDrift -Pattern 'dot dot--green'

# D3：無漂移 ⇒ 不出現「對帳範圍外」或「漂移」字樣、不因對帳被強制非綠燈（正向對照組，防止 D1/D2 誤判）
$T17AnchorF = New-T17MockAnchor -WorkId 'W-clean' -Repo 'acme/repo-f' -Number 3 -ExtraLabels @('sc:station-2')
$T17ModelClean = New-ReconciledFleetWorkCardModel -WorkId 'W-clean' -AnchorIssue $T17AnchorF -ParticipatingRepos @('acme/repo-f') `
    -Tickets @() -MilestoneRows @() -QueueInfo $T17QueueEmpty -NowUtc (Get-Date).ToUniversalTime() `
    -CacheBaseline $null -LastFullSyncText '（測試）' -ReconcileState $T17C4
$T17HtmlClean = Build-WorkCardHtml -Model $T17ModelClean
Assert-NotMatch -Name 'D3 對照組：無漂移時 HTML 不含「對帳範圍外」' -Text $T17HtmlClean -Pattern '對帳範圍外'
# ⚠️ 不得用裸字串 '漂移' 判斷「無漂移」——「無漂移」三字本身就包含子字串「漂移」，兩者不衝突，
# 這裡改用精確樣式「漂移 <數字> 筆」（真正代表「有漂移」的文案形狀）來確認正向計數字樣不存在。
Assert-NotMatch -Name 'D3b 對照組：無漂移時 HTML 不含「漂移 N 筆」計數字樣（僅含「無漂移」中性敘述）' -Text $T17HtmlClean -Pattern '漂移\s*\d+\s*筆'
Assert-Match -Name 'D3c 對照組：文案含「無漂移」（已對帳正常狀態）' -Text $T17HtmlClean -Pattern '已對帳.*無漂移'

Write-Host "--- 群組 D 完成 ---"

# ============================================================================
# 群組 E：NoReconcile 模式不受干擾（驗收③，t16/t09 既有行為原樣通過）
# ============================================================================
Write-Host "`n--- 群組 E：NoReconcile 模式（驗收③，本次未對帳） ---" -ForegroundColor Yellow

$T17CacheWithReconcile = [pscustomobject]@{ lastFullSyncTimeUtc = (Get-Date).ToUniversalTime().ToString('o'); lastReconcileTimeUtc = (Get-Date).ToUniversalTime().AddHours(-3).ToString('o'); works = @() }
$T17ModelNoReconcile = New-ReconciledFleetWorkCardModel -WorkId 'W-clean' -AnchorIssue $T17AnchorF -ParticipatingRepos @('acme/repo-f') `
    -Tickets @() -MilestoneRows @() -QueueInfo $T17QueueEmpty -NowUtc (Get-Date).ToUniversalTime() -NoReconcile `
    -CacheBaseline $T17CacheWithReconcile -LastFullSyncText '（測試）' -ReconcileState $null
Assert-Match -Name 'E1 NoReconcile 模式文案＝t16 既有「本次未對帳，沿用...結果」（T-17 不覆寫）' -Text $T17ModelNoReconcile.ReconcileDataTimeText -Pattern '本次未對帳，沿用'
Assert-Equal -Name 'E2 NoReconcile 模式 StatusColor 不受對帳強制（維持 t16 原判定）' -Expected 'green' -Actual $T17ModelNoReconcile.StatusColor

# 即使誤傳了一個 ReconcileState（呼叫端沒做到 -NoReconcile 才不傳的約定），NoReconcile 開關本身仍優先，不覆寫
$T17ModelNoReconcileGuard = New-ReconciledFleetWorkCardModel -WorkId 'W-clean' -AnchorIssue $T17AnchorF -ParticipatingRepos @('acme/repo-f') `
    -Tickets @() -MilestoneRows @() -QueueInfo $T17QueueEmpty -NowUtc (Get-Date).ToUniversalTime() -NoReconcile `
    -CacheBaseline $T17CacheWithReconcile -LastFullSyncText '（測試）' -ReconcileState $T17C3
Assert-Match -Name 'E3 NoReconcile 開關優先於 ReconcileState 是否為 $null（防呆）' -Text $T17ModelNoReconcileGuard.ReconcileDataTimeText -Pattern '本次未對帳，沿用'

Write-Host "--- 群組 E 完成 ---"

# ============================================================================
# 群組 F：Build-ReconciledFleetBoardReport 端到端（驗收④：plans/ 不可用 ⇒ 全部「對帳未執行」）
# ============================================================================
Write-Host "`n--- 群組 F：端到端 plans/ 不可用（驗收④） ---" -ForegroundColor Yellow

$T17SnapshotTwoWorks = New-T17MockSnapshot -Works @(
    (New-T17MockWork -WorkId 'W-fa' -AnchorIssue (New-T17MockAnchor -WorkId 'W-fa' -Repo 'acme/repo-fa' -Number 10) -ParticipatingRepos @('acme/repo-fa'))
    (New-T17MockWork -WorkId 'W-fb' -AnchorIssue (New-T17MockAnchor -WorkId 'W-fb' -Repo 'acme/repo-fb' -Number 20) -ParticipatingRepos @('acme/repo-fb'))
)
$T17PlansUnavailablePath = Join-Path ([System.IO.Path]::GetTempPath()) "t17-plans-absent-$([guid]::NewGuid().ToString('N'))"
# 刻意不建立 $T17PlansUnavailablePath ⇒ 模擬「plans/ 不可用」

$T17ReportPlansDown = Build-ReconciledFleetBoardReport -Snapshot $T17SnapshotTwoWorks -TemplateContent $T17TemplateContent `
    -CacheBaseline $null -NowLocal (Get-Date) -TimeZoneLabel 'UTC+8' -PlansRoot $T17PlansUnavailablePath -SkipNoBaselineBanner

Assert-Match -Name 'F1 W-fa 字卡含「對帳未執行」' -Text $T17ReportPlansDown.CardsHtml -Pattern 'W-fa[\s\S]*?對帳未執行'
Assert-Match -Name 'F2 W-fb 字卡含「對帳未執行」（驗收④：plans/ 不可用 ⇒ 全部標記，非只有其中一張）' -Text $T17ReportPlansDown.CardsHtml -Pattern 'W-fb[\s\S]*?對帳未執行'
Assert-Equal -Name 'F3 ReconcileSummary 兩筆皆為 not-executed' -Expected 2 -Actual (@($T17ReportPlansDown.ReconcileSummary | Where-Object { $_.Kind -eq 'not-executed' })).Count

Write-Host "--- 群組 F 完成 ---"

# ============================================================================
# 群組 G：紅燈存證（Spec §6 註 A：紅是斷言失敗的紅）
# ============================================================================
Write-Host "`n--- 群組 G：紅燈存證（兩條正向斷言真的失敗一次） ---" -ForegroundColor Yellow

# --- 紅燈①：漂移筆數＝差異集筆數（旁路開啟時應恆為 0，斷言真的失敗） ---
$T17BugState_Drift = Get-ReconcileStateForWork -RootAvailable $true -PlanRecord $T17PlanDrift -GithubTickets $Script:FixtureDriftSet.GithubTickets -NowLocal $T17NowLocal -BugDisableReconcile
$T17RedCheck1Passed = Invoke-RedLightCheck -Name '「漂移筆數＝人造差異集筆數（3）」斷言（旁路開啟，預期真的失敗）' -Assertion {
    $T17BugState_Drift.DriftCount -eq $Script:FixtureDriftSet.ExpectedDriftCount
}
Assert-True -Name '紅燈存證①：旁路開啟時「漂移筆數＝差異集筆數」斷言確實失敗（未實作時筆數恆為 0）' -Condition (-not $T17RedCheck1Passed) `
    -Detail "若此項也是 PASS，代表旁路沒有真的重現『未實作』行為——需檢查 BugDisableReconcile 是否生效；旁路開啟時實際 DriftCount=[$($T17BugState_Drift.DriftCount)]"
Assert-Equal -Name '紅燈存證①附證：旁路開啟時 DriftCount 確實恆為 0（複製未實作前的行為）' -Expected 0 -Actual $T17BugState_Drift.DriftCount

# --- 紅燈②：範圍外標示存在且非綠燈（旁路開啟時應無標示、不強制非綠燈，斷言真的失敗） ---
$T17BugState_OutScope = Get-ReconcileStateForWork -RootAvailable $true -PlanRecord ([pscustomobject]@{ Found = $false; Tickets = @(); FailureDetail = $null }) -GithubTickets @() -NowLocal $T17NowLocal -BugDisableReconcile
$T17RedCheck2Passed = Invoke-RedLightCheck -Name '「範圍外標示存在且非綠燈」斷言（旁路開啟，預期真的失敗）' -Assertion {
    ($T17BugState_OutScope.ReconcileDataTimeText -match '對帳範圍外') -and $T17BugState_OutScope.ForceNonGreen
}
Assert-True -Name '紅燈存證②：旁路開啟時「範圍外標示存在且非綠燈」斷言確實失敗（未實作時標示不存在、不強制非綠燈）' -Condition (-not $T17RedCheck2Passed) `
    -Detail "旁路開啟時實際文案=[$($T17BugState_OutScope.ReconcileDataTimeText)] ForceNonGreen=[$($T17BugState_OutScope.ForceNonGreen)]"
Assert-Match -Name '紅燈存證②附證：旁路開啟時文案退回原始佔位字串' -Text $T17BugState_OutScope.ReconcileDataTimeText -Pattern '尚未實作'

# --- 關閉旁路（正式行為）：重跑同一組輸入 ⇒ 兩條斷言轉綠（已在群組 C3／C5 驗證，此處再次以旁路關閉狀態確認） ---
Assert-True -Name 'G-關閉旁路：漂移筆數斷言轉綠' -Condition ($T17C5.DriftCount -eq $Script:FixtureDriftSet.ExpectedDriftCount)
Assert-True -Name 'G-關閉旁路：範圍外標示與非綠燈斷言轉綠' -Condition (($T17C3.ReconcileDataTimeText -match '對帳範圍外') -and $T17C3.ForceNonGreen)

Write-Host "--- 群組 G 完成 ---"

# ============================================================================
# 群組 H：PS 5.1 / StrictMode 陷阱回歸測試
# ============================================================================
Write-Host "`n--- 群組 H：StrictMode 陷阱回歸 ---" -ForegroundColor Yellow

# 陷阱①：單一物件無 .Count（Compare-PlanVsGithubTickets 對「恰 1 筆漂移」輸入需能安全取 .Count）
$T17SingleDriftPlan = @([pscustomobject]@{ TicketRef = 'z/z#1'; Status = 'open' })
$T17SingleDriftGh = @()
$T17SingleDriftResultRaw = Compare-PlanVsGithubTickets -PlanTickets $T17SingleDriftPlan -GithubTickets $T17SingleDriftGh
$T17SingleDriftResult = ConvertTo-SafeArray -RawValue $T17SingleDriftResultRaw
Assert-Equal -Name 'H1 陷阱①防護：恰 1 筆漂移時 .Count 安全可用' -Expected 1 -Actual $T17SingleDriftResult.Count

# 陷阱③：0 筆結果不得被 @(函式呼叫本身) 誤包成 1 筆
$T17ZeroDriftResultRaw = Compare-PlanVsGithubTickets -PlanTickets @() -GithubTickets @()
$T17ZeroDriftResult = ConvertTo-SafeArray -RawValue $T17ZeroDriftResultRaw
Assert-Equal -Name 'H2 陷阱③防護：0 筆漂移不被誤包成 1 筆' -Expected 0 -Actual $T17ZeroDriftResult.Count

# StatusReasons 疊加：確認「附加」邏輯在 t16 model 原本 StatusReasons 已有內容時仍正確串接（非覆蓋）
$T17AnchorBlocked = New-T17MockIssue -Number 5 -Repo 'acme/repo-g' -Title 'blocked work' -Body "work-id: W-blocked`nprimary-repo: acme/repo-g" -Labels @('sc:work', 'sc:station-3', 'sc:blocked')
$T17ModelBlockedDrift = New-ReconciledFleetWorkCardModel -WorkId 'W-blocked' -AnchorIssue $T17AnchorBlocked -ParticipatingRepos @('acme/repo-g') `
    -Tickets @() -MilestoneRows @() -QueueInfo $T17QueueEmpty -NowUtc (Get-Date).ToUniversalTime() `
    -CacheBaseline $null -LastFullSyncText '（測試）' -ReconcileState $T17C5
Assert-Contains -Name 'H3 StatusReasons 疊加：既有 sc:blocked 理由仍在' -Haystack (ConvertTo-SafeArray -RawValue $T17ModelBlockedDrift.StatusReasons) -Needle 'anchor 帶 sc:blocked'
$T17BlockedDriftReasonCount = (@($T17ModelBlockedDrift.StatusReasons | Where-Object { $_ -match '對帳異常' })).Count
Assert-True -Name 'H3b StatusReasons 疊加：對帳異常理由也在（兩者並存，非互相覆蓋）' -Condition ($T17BlockedDriftReasonCount -gt 0)

Write-Host "--- 群組 H 完成 ---"

# ============================================================================
# 群組 I：只報不修守門（grep 靜態檢查＋守恆檢查）
# ============================================================================
Write-Host "`n--- 群組 I：只報不修守門（grep＋守恆檢查） ---" -ForegroundColor Yellow

# ⚠️ 自檢對象是「實際會被執行的程式碼」，不是檔頭 docstring 裡「說明本檔不含什麼」的文字本身
# （那些說明文字必然逐字提到被禁止的 cmdlet／HTTP 動詞名稱，否則就寫不出「不含 X」這句話）——
# 先剝掉 `<# ... #>` 區塊與 `#` 開頭整行註解，只對剩餘的可執行程式碼做 grep，避免文件說明段落
# 把自己的靜態檢查斷言誤判為命中。
$T17SelfSourceRaw = Get-Content -LiteralPath (Join-Path $T17TestDir 'reconcile-board.ps1') -Raw -Encoding UTF8
$T17SelfSourceNoBlockComments = [regex]::Replace($T17SelfSourceRaw, '(?s)<#.*?#>', '')
$T17SelfSourceCodeLines = @($T17SelfSourceNoBlockComments -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' })
$T17SelfSourceCode = ($T17SelfSourceCodeLines -join "`n")

Assert-NotMatch -Name 'I1 reconcile-board.ps1 可執行程式碼不含任何 GitHub 寫入 HTTP 動詞（Put/Post/Patch/Delete）' `
    -Text $T17SelfSourceCode -Pattern '-Method\s+(Put|Post|Patch|Delete)'
Assert-NotMatch -Name 'I2 reconcile-board.ps1 可執行程式碼不含 plans/ 寫入 cmdlet（Set-Content/Out-File/New-Item/Remove-Item/Move-Item/Copy-Item/Add-Content）' `
    -Text $T17SelfSourceCode -Pattern '(Set-Content|Out-File|New-Item|Remove-Item|Move-Item|Copy-Item|Add-Content)'
Assert-NotMatch -Name 'I3 reconcile-board.ps1 可執行程式碼不產生 label/issue 開關類佇列項字面（set-labels/close-issue/create-issue）' `
    -Text $T17SelfSourceCode -Pattern '(set-labels|close-issue|create-issue)'

# --- 守恆檢查（票面原文：「對帳前後兩側內容摘要不變」，非紅燈，回歸檢查） ---
$T17ConservationDir = Join-Path ([System.IO.Path]::GetTempPath()) "t17-conservation-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $T17ConservationDir -Force | Out-Null
try {
    $T17ConservationWorkFile = Join-Path $T17ConservationDir 'W-cons.json'
    $T17ConservationJson = @'
{
  "workId": "W-cons",
  "tickets": [
    { "ticketRef": "acme/repo-cons#1", "status": "open" },
    { "ticketRef": "acme/repo-cons#2", "status": "closed" }
  ]
}
'@
    [System.IO.File]::WriteAllText($T17ConservationWorkFile, $T17ConservationJson, $Script:Utf8Bom)

    $T17ConsAnchor = New-T17MockAnchor -WorkId 'W-cons' -Repo 'acme/repo-cons' -Number 30
    $T17ConsTicket1 = New-T17MockIssue -Number 1 -Repo 'acme/repo-cons' -Title 't1' -Labels @('sc:ticket') -State 'open'
    $T17ConsSnapshot = New-T17MockSnapshot -Works @(
        (New-T17MockWork -WorkId 'W-cons' -AnchorIssue $T17ConsAnchor -ParticipatingRepos @('acme/repo-cons') -Tickets @($T17ConsTicket1))
    )

    $T17PlansDigestBefore = Get-PlansTreeDigest -PlansRoot $T17ConservationDir
    $T17SnapshotDigestBefore = Get-SnapshotDigest -Snapshot $T17ConsSnapshot

    # 跑一輪完整對帳（含漂移：W-cons#2 plan 標 closed 但 GitHub 側缺席 ⇒ 預期缺席不算漂移；純粹跑過一輪即可）
    $T17ConsReport = Build-ReconciledFleetBoardReport -Snapshot $T17ConsSnapshot -TemplateContent $T17TemplateContent `
        -CacheBaseline $null -NowLocal (Get-Date) -TimeZoneLabel 'UTC+8' -PlansRoot $T17ConservationDir -SkipNoBaselineBanner
    Assert-True -Name 'I4 守恆檢查前置：本輪對帳確實執行到底（有回傳 Html）' -Condition (-not [string]::IsNullOrWhiteSpace($T17ConsReport.Html))

    $T17PlansDigestAfter = Get-PlansTreeDigest -PlansRoot $T17ConservationDir
    $T17SnapshotDigestAfter = Get-SnapshotDigest -Snapshot $T17ConsSnapshot

    Assert-Equal -Name 'I5 守恆檢查：plans/ 樹狀內容雜湊對帳前後不變（未被寫入／刪除／修改）' -Expected $T17PlansDigestBefore -Actual $T17PlansDigestAfter
    Assert-Equal -Name 'I6 守恆檢查：GitHub 側 Snapshot 物件雜湊對帳前後不變（未被就地竄改）' -Expected $T17SnapshotDigestBefore -Actual $T17SnapshotDigestAfter

    # 額外直接比對檔案內容字面（雙重保險，不只靠 hash）
    $T17RawAfter = Get-Content -LiteralPath $T17ConservationWorkFile -Raw -Encoding UTF8
    Assert-Equal -Name 'I7 守恆檢查：plans/ 檔案內容逐字不變（雙重保險，非只靠 hash）' -Expected $T17ConservationJson -Actual $T17RawAfter
} finally {
    Remove-Item -LiteralPath $T17ConservationDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "--- 群組 I 完成 ---"

# ============================================================================
# 群組 J：三態（＋對帳未執行）不塌成兩態——四種情境互斥、各自可獨立觸發
# ============================================================================
Write-Host "`n--- 群組 J：四態互斥交叉驗證（不塌成兩態） ---" -ForegroundColor Yellow

# 同一組輸入資料下，四種情境必須各自產生**不同**的 Kind 與**不同**的文案關鍵字，
# 證明「查不到」（out-of-scope／not-executed）與「不一致」（in-scope-drift）不是同一件事被合併顯示。
$T17KindsSeen = @($T17C1.Kind, $T17C2.Kind, $T17C3.Kind, $T17C4.Kind, $T17C5.Kind)
Assert-Equal -Name 'J1 not-executed（全域）與 not-executed（局部）雖同 Kind 但文案不同（不同觸發原因仍可分辨）' `
    -Expected $false -Actual ($T17C1.ReconcileDataTimeText -eq $T17C2.ReconcileDataTimeText)
Assert-True -Name 'J2 out-of-scope 與 in-scope-drift 是不同 Kind（範圍外≠漂移，未塌成同一態）' -Condition ($T17C3.Kind -ne $T17C5.Kind)
Assert-True -Name 'J3 out-of-scope 與 not-executed 是不同 Kind（查無此 work≠plans 不可用，未塌成同一態）' -Condition ($T17C3.Kind -ne $T17C1.Kind)
Assert-True -Name 'J4 in-scope-clean 與 in-scope-drift 是不同 Kind（已對帳無異常≠有漂移，未塌成同一態）' -Condition ($T17C4.Kind -ne $T17C5.Kind)
Assert-Equal -Name 'J5 四態互不相同（Kind 去重後仍有 4 種：not-executed/out-of-scope/in-scope-clean/in-scope-drift）' `
    -Expected 4 -Actual (@($T17KindsSeen | Select-Object -Unique)).Count
# 「查不到」二態（not-executed／out-of-scope）都不應誤標成漂移；「不一致」態必須帶正的 DriftCount
Assert-Equal -Name 'J6 not-executed 的 DriftCount＝0（查不到≠有筆數可報）' -Expected 0 -Actual $T17C1.DriftCount
Assert-Equal -Name 'J7 out-of-scope 的 DriftCount＝0（查不到≠有筆數可報）' -Expected 0 -Actual $T17C3.DriftCount
Assert-True -Name 'J8 in-scope-drift 的 DriftCount＞0（不一致態才有正筆數）' -Condition ($T17C5.DriftCount -gt 0)

Write-Host "--- 群組 J 完成 ---"

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
