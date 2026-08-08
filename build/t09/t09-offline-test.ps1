#requires -Version 5.1
<#
.SYNOPSIS
    T-09 · 離線 mock 測試（沙盒／CI 皆可跑，不連網）。

.DESCRIPTION
    只測 render-board.ps1 的**純函式**部分（Build-StationBoardReport 及其下游 Build-*／ConvertTo-*
    輔助函式）。手造符合 SNAPSHOT SCHEMA 的 mock 物件直接餵給 Build-StationBoardReport，斷言輸出的
    Html／TextSummary／ErrorStates。全程不呼叫 Get-StationBoardSnapshot、不打任何網路請求。

    覆蓋範圍：
      群組 A：§4.4 四種錯誤狀態（含「零筆＋無基線 ⇒ 兩訊息並列」的並列規則）
      群組 B：§4.1 字卡逐欄位（work 名＋ID、repo 清單、五段 stepper、逐 repo 進度、executor、
              狀態燈與理由、在跑／停滯數、legacy badge）
      群組 C：§4.6／T-23 併入的待寫佇列揭露（不存在／讀取失敗／N 筆／寫入斷點不可信註記）
      群組 D：§4.5 刷新時機（-NoReconcile 模式的「本次未對帳，沿用 <時間> 結果」文案）
      群組 E：PS 5.1／StrictMode 陷阱回歸測試（本檔開發過程中實際踩到並修正過的臭蟲，鎖住不回歸）
      群組 F：Save-StationBoardArtifact／Read-CacheBaselineFromExistingArtifact 的邊界情況

.NOTES
    執行：/opt/pwsh/pwsh -NoProfile -File t09-offline-test.ps1
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

. "$PSScriptRoot/render-board.ps1" -FunctionsOnly

# ============================================================================
# 極簡斷言框架
# ============================================================================
$Script:PassCount = 0
$Script:FailCount = 0
$Script:Results = @()

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
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][array]$Haystack, [Parameter(Mandatory)][string]$Needle)
    $found = @($Haystack | Where-Object { $_ -eq $Needle })
    Assert-True -Name $Name -Condition ($found.Count -gt 0) -Detail "需要含 [$Needle]，實際=[$($Haystack -join ',')]"
}

function Assert-NotContains {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][array]$Haystack, [Parameter(Mandatory)][string]$Needle)
    $found = @($Haystack | Where-Object { $_ -eq $Needle })
    Assert-True -Name $Name -Condition ($found.Count -eq 0) -Detail "不應含 [$Needle]，實際=[$($Haystack -join ',')]"
}

# ============================================================================
# Mock 資料建構工具（皆遵守 render-board.ps1 檔頭的 SNAPSHOT SCHEMA）
# ============================================================================

$TplPath = Join-Path $PSScriptRoot 'board-template.html'
if (-not (Test-Path -LiteralPath $TplPath)) { throw "找不到樣板：$TplPath" }
$TemplateContent = Get-Content -LiteralPath $TplPath -Raw -Encoding UTF8

function New-MockIssue {
    param(
        [int]$Number = 1, [string]$Repo = 'acme/plugin', [string]$Title = 'demo',
        [string]$Body = '', [string[]]$Labels = @(), [string]$State = 'open',
        [datetime]$UpdatedAtUtc = (Get-Date).ToUniversalTime(), [bool]$HasAssignee = $false
    )
    return [pscustomobject]@{
        Number = $Number; Repo = $Repo; Title = $Title; Body = $Body; Labels = $Labels
        State = $State; UpdatedAtUtc = $UpdatedAtUtc; HasAssignee = $HasAssignee; HtmlUrl = "https://x/$Number"
    }
}

function New-MockSnapshot {
    param(
        [string]$WorkId = 'W-demo', [string]$PrimaryRepo = 'acme/plugin',
        [string[]]$ParticipatingReposDeclared = @('acme/plugin'),
        [datetime]$NowUtc = (Get-Date).ToUniversalTime(),
        $AnchorQuery = $null, $TicketsQuery = $null, [array]$MilestoneProgress = @(), $Queue = $null
    )
    if ($null -eq $AnchorQuery) {
        $AnchorQuery = [pscustomobject]@{ Ok = $true; Found = $false; FailureDetail = $null; Issue = $null }
    }
    if ($null -eq $TicketsQuery) {
        $TicketsQuery = [pscustomobject]@{ Ok = $true; FailedRepos = @(); Tickets = @(); ResultCountThisRun = 0; TotalCountReported = 0; HitPageCap = $false }
    }
    if ($null -eq $Queue) {
        $Queue = [pscustomobject]@{ Exists = $false; Count = $null; Path = './queue.json'; ParseError = $null }
    }
    return [pscustomobject]@{
        WorkId = $WorkId; PrimaryRepo = $PrimaryRepo; ParticipatingReposDeclared = $ParticipatingReposDeclared
        NowUtc = $NowUtc; AnchorQuery = $AnchorQuery; TicketsQuery = $TicketsQuery
        MilestoneProgress = $MilestoneProgress; Queue = $Queue
    }
}

function Invoke-Build {
    param($Snapshot, $CacheBaseline = $null, [switch]$NoReconcile, [switch]$SkipErrorStateHandling)
    return Build-StationBoardReport -Snapshot $Snapshot -TemplateContent $TemplateContent -CacheBaseline $CacheBaseline `
        -NowLocal (Get-Date) -TimeZoneLabel 'UTC+8' -NoReconcile:$NoReconcile -SkipErrorStateHandling:$SkipErrorStateHandling
}

Write-Host "==================== T-09 離線 mock 測試開始 ====================" -ForegroundColor Cyan

# ============================================================================
# 群組 A：§4.4 四種錯誤狀態
# ============================================================================
Write-Host "`n--- 群組 A：§4.4 四種錯誤狀態 ---" -ForegroundColor Yellow

# A1：查詢失敗（anchor 查詢丟例外，模擬「查詢清單混入不存在的 repo 名」）
$sA1 = New-MockSnapshot -AnchorQuery ([pscustomobject]@{ Ok = $false; Found = $false; FailureDetail = 'acme/no-such-repo: 404 Not Found'; Issue = $null })
$rA1 = Invoke-Build -Snapshot $sA1
Assert-Contains -Name 'A1 查詢失敗 ⇒ ErrorStates 含 query-failed' -Haystack $rA1.ErrorStates -Needle 'query-failed'
Assert-Match -Name 'A1 banner 具名失敗對象' -Text $rA1.Html -Pattern 'acme/no-such-repo: 404 Not Found'
Assert-Match -Name 'A1 banner 標題為「數據過期」' -Text $rA1.Html -Pattern '數據過期'
Assert-NotMatch -Name 'A1 不得把失敗顯示為「無工作」' -Text $rA1.Html -Pattern '目前無 active work'
Assert-Match -Name 'A1 受影響字卡打灰標「未更新」' -Text $rA1.Html -Pattern 'badge--stale.*未更新|未更新.*badge'
Assert-Match -Name 'A1 卡片套用 card--stale 灰化樣式' -Text $rA1.Html -Pattern 'class="card card--stale"'

# A2：不完整（觸頂）
$anchorOkIssue = New-MockIssue -Labels @('sc:work', 'sc:station-4')
$sA2 = New-MockSnapshot -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorOkIssue }) `
    -TicketsQuery ([pscustomobject]@{ Ok = $true; FailedRepos = @(); Tickets = @(); ResultCountThisRun = 100; TotalCountReported = 137; HitPageCap = $true })
$rA2 = Invoke-Build -Snapshot $sA2
Assert-Contains -Name 'A2 觸頂 ⇒ ErrorStates 含 incomplete' -Haystack $rA2.ErrorStates -Needle 'incomplete'
Assert-Match -Name 'A2 banner 標題為「資料可能不完整」' -Text $rA2.Html -Pattern '資料可能不完整'
Assert-Match -Name 'A2 具名徵狀含總筆數與已取得筆數' -Text $rA2.Html -Pattern '總筆數 137.*100 筆|137.*100'

# A3：面板寫入失敗（獨立函式，指向不存在的目錄）
$rA3save = Save-StationBoardArtifact -Html '<html>x</html>' -OutputPath '/no/such/dir/out.html'
Assert-True -Name 'A3 面板寫入失敗 ⇒ Save 回傳 Ok=false' -Condition (-not $rA3save.Ok)
Assert-True -Name 'A3 面板寫入失敗具名原因' -Condition (-not [string]::IsNullOrWhiteSpace($rA3save.Detail))
# 寫入失敗時的「文字輸出完整字卡摘要」由 Invoke-StationBoardRender 承接（見群組 F 的整合測試）

# A4：空狀態（查詢成功、零筆、且有基線 ⇒ 不觸發「無基線」橫幅）
$cacheWithBaseline = [pscustomobject]@{ workId = 'W-demo'; lastFullSyncTimeUtc = (Get-Date).ToUniversalTime().AddHours(-1).ToString('o'); lastReconcileTimeUtc = $null; lastTicketCount = 3; anchorFound = $true }
$sA4 = New-MockSnapshot
$rA4 = Invoke-Build -Snapshot $sA4 -CacheBaseline $cacheWithBaseline
Assert-Contains -Name 'A4 空狀態 ⇒ ErrorStates 含 empty' -Haystack $rA4.ErrorStates -Needle 'empty'
Assert-Match -Name 'A4 顯示「目前無 active work」明示卡' -Text $rA4.Html -Pattern '目前無 active work'
Assert-Match -Name 'A4 附查詢條件' -Text $rA4.Html -Pattern '查詢條件：work-id=W-demo'
Assert-NotContains -Name 'A4 有基線時不觸發 no-baseline' -Haystack $rA4.ErrorStates -Needle 'no-baseline'
Assert-NotMatch -Name 'A4 有基線時 html 不含消失偵測不可用橫幅' -Text $rA4.Html -Pattern '消失偵測不可用'

# A5：零筆＋無基線 ⇒ 兩訊息並列（🚫 不得只顯示其中一個）
$sA5 = New-MockSnapshot
$rA5 = Invoke-Build -Snapshot $sA5 -CacheBaseline $null
Assert-Contains -Name 'A5 零筆+無基線 ⇒ ErrorStates 含 empty' -Haystack $rA5.ErrorStates -Needle 'empty'
Assert-Contains -Name 'A5 零筆+無基線 ⇒ ErrorStates 含 no-baseline' -Haystack $rA5.ErrorStates -Needle 'no-baseline'
Assert-Match -Name 'A5 html 同時含「目前無 active work」' -Text $rA5.Html -Pattern '目前無 active work'
Assert-Match -Name 'A5 html 同時含「消失偵測不可用（無基線）」' -Text $rA5.Html -Pattern '消失偵測不可用（無基線）'

Write-Host "`n--- 群組 A 完成 ---"

# ============================================================================
# 群組 B：§4.1 字卡逐欄位
# ============================================================================
Write-Host "`n--- 群組 B：§4.1 字卡逐欄位 ---" -ForegroundColor Yellow

$ticket1 = New-MockIssue -Number 10 -Repo 'acme/plugin' -Title 'T-10' -Body "executor: fullstack-developer`nbasis: x" `
    -Labels @('sc:ticket') -State 'open' -UpdatedAtUtc (Get-Date).ToUniversalTime().AddHours(-1) -HasAssignee $true
$ticket2 = New-MockIssue -Number 11 -Repo 'acme/app' -Title 'T-11' -Body "**executor**：`"docs-manager`"" `
    -Labels @('sc:ticket', 'sc:red-proven') -State 'open' -UpdatedAtUtc (Get-Date).ToUniversalTime().AddHours(-30) -HasAssignee $true
$ticket3Closed = New-MockIssue -Number 12 -Repo 'acme/plugin' -Title 'T-12' -Body 'executor: tester' `
    -Labels @('sc:ticket') -State 'closed' -UpdatedAtUtc (Get-Date).ToUniversalTime().AddDays(-5) -HasAssignee $true

$anchorB = New-MockIssue -Number 1 -Repo 'acme/plugin' -Title 'W-full-demo · primary anchor' `
    -Body "work-id: W-full-demo`nprimary-repo: acme/plugin`nparticipating-repos:`n- acme/plugin`n- acme/app`n`n描述文字" `
    -Labels @('sc:work', 'sc:station-4') -State 'open'

$sB = New-MockSnapshot -WorkId 'W-full-demo' -ParticipatingReposDeclared @('acme/plugin', 'acme/app') `
    -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorB }) `
    -TicketsQuery ([pscustomobject]@{ Ok = $true; FailedRepos = @(); Tickets = @($ticket1, $ticket2, $ticket3Closed); ResultCountThisRun = 3; TotalCountReported = 3; HitPageCap = $false }) `
    -MilestoneProgress @(
        [pscustomobject]@{ Repo = 'acme/plugin'; QueryOk = $true; FailureDetail = $null; MilestoneFound = $true; Title = 'W-full-demo'; OpenIssues = 2; ClosedIssues = 8; PercentComplete = 80 }
        [pscustomobject]@{ Repo = 'acme/app'; QueryOk = $true; FailureDetail = $null; MilestoneFound = $true; Title = 'W-full-demo'; OpenIssues = 1; ClosedIssues = 1; PercentComplete = 50 }
    )
$rB = Invoke-Build -Snapshot $sB -CacheBaseline $null

Assert-Match -Name 'B1 工作名＋work ID' -Text $rB.Html -Pattern 'W-full-demo</h2>[\s\S]*W-full-demo</span>|W-full-demo'
Assert-Match -Name 'B2 primary repo＋參與 repo' -Text $rB.Html -Pattern 'acme/plugin（primary）.*acme/app|acme/plugin.*acme/app'
Assert-Match -Name 'B3 五段 stepper：目前站 4' -Text $rB.Html -Pattern 'step--current" title="4 implement"'
Assert-Match -Name 'B3 stepper：站 1-3 已完成（step--done）' -Text $rB.Html -Pattern 'step step--done" title="1 grill"'
Assert-Match -Name 'B4 逐 repo 進度：acme/plugin 80%' -Text $rB.Html -Pattern 'acme/plugin.*80%'
Assert-Match -Name 'B4 逐 repo 進度：acme/app 50%（不合成單一數字，兩者分開列）' -Text $rB.Html -Pattern 'acme/app.*50%'
Assert-Match -Name 'B5 當前 executor 讀票 body（不讀 assignee），機讀鍵值行格式' -Text $rB.Html -Pattern 'fullstack-developer'
Assert-Match -Name 'B5 當前 executor 讀票 body，人讀慣例格式（**executor**：）' -Text $rB.Html -Pattern 'docs-manager'
Assert-NotMatch -Name 'B5 closed 票（T-12, tester）不算在跑，不出現在 executor 清單' -Text ($rB.Html -replace '(?s).*當前 executor.*?</dd>', '') -Pattern 'tester'
Assert-Match -Name 'B6 狀態燈：綠（無 blocked/gate-fail/awaiting-user/髒label）' -Text $rB.Html -Pattern 'dot dot--green'
Assert-Match -Name 'B7 在跑數量＝2（兩張 open+assignee 票，closed 那張不算）' -Text $rB.Html -Pattern '<dt>在跑數量</dt><dd>2'
Assert-Match -Name 'B8 停滯票數＝1（T-11 距今 30h > 24h）' -Text $rB.Html -Pattern '<dt>停滯票數（24h）</dt><dd>1'

# B9：legacy badge
$anchorLegacy = New-MockIssue -Number 2 -Repo 'acme/plugin' -Title 'W-legacy · primary anchor' -Labels @('sc:work', 'sc:station-3', 'sc:legacy')
$sB9 = New-MockSnapshot -WorkId 'W-legacy' -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorLegacy })
$rB9 = Invoke-Build -Snapshot $sB9
Assert-Match -Name 'B9 legacy badge 出現' -Text $rB9.Html -Pattern 'badge--legacy">legacy</span>'

# B10：狀態燈紅（sc:blocked）＋理由具名
$anchorBlocked = New-MockIssue -Number 3 -Repo 'acme/plugin' -Title 'W-blocked · primary anchor' -Labels @('sc:work', 'sc:station-2', 'sc:blocked')
$sB10 = New-MockSnapshot -WorkId 'W-blocked' -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorBlocked })
$rB10 = Invoke-Build -Snapshot $sB10
Assert-Match -Name 'B10 狀態燈紅（sc:blocked）' -Text $rB10.Html -Pattern 'dot dot--red'
Assert-Match -Name 'B10 燈號理由具名 anchor 帶 sc:blocked' -Text $rB10.Html -Pattern 'anchor 帶 sc:blocked'

# B11：狀態燈黃（sc:awaiting-user）
$anchorAwaiting = New-MockIssue -Number 4 -Repo 'acme/plugin' -Title 'W-await · primary anchor' -Labels @('sc:work', 'sc:station-2', 'sc:awaiting-user')
$sB11 = New-MockSnapshot -WorkId 'W-await' -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorAwaiting })
$rB11 = Invoke-Build -Snapshot $sB11
Assert-Match -Name 'B11 狀態燈黃（sc:awaiting-user）' -Text $rB11.Html -Pattern 'dot dot--yellow'

# B12：髒 label（anchor 帶兩個互斥站別 label）⇒ 紅燈 + 站別不明
$anchorDirty = New-MockIssue -Number 5 -Repo 'acme/plugin' -Title 'W-dirty · primary anchor' -Labels @('sc:work', 'sc:station-2', 'sc:station-4')
$sB12 = New-MockSnapshot -WorkId 'W-dirty' -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorDirty })
$rB12 = Invoke-Build -Snapshot $sB12
Assert-Match -Name 'B12 髒 label（雙站別）⇒ 紅燈' -Text $rB12.Html -Pattern 'dot dot--red'
Assert-Match -Name 'B12 stepper 顯示「站別不明」' -Text $rB12.Html -Pattern '站別不明'

# B13：票帶站別 label（非法載體）⇒ 紅燈具名
$ticketDirty = New-MockIssue -Number 20 -Repo 'acme/plugin' -Title 'T-20' -Labels @('sc:ticket', 'sc:station-4') -State 'open'
$anchorForB13 = New-MockIssue -Number 6 -Repo 'acme/plugin' -Title 'W-b13 · primary anchor' -Labels @('sc:work', 'sc:station-4')
$sB13 = New-MockSnapshot -WorkId 'W-b13' -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorForB13 }) `
    -TicketsQuery ([pscustomobject]@{ Ok = $true; FailedRepos = @(); Tickets = @($ticketDirty); ResultCountThisRun = 1; TotalCountReported = 1; HitPageCap = $false })
$rB13 = Invoke-Build -Snapshot $sB13
Assert-Match -Name 'B13 票帶站別 label ⇒ 紅燈具名（不合法載體）' -Text $rB13.Html -Pattern '不合法載體'

Write-Host "`n--- 群組 B 完成 ---"

# ============================================================================
# 群組 C：§4.6／T-23 併入的待寫佇列揭露
# ============================================================================
Write-Host "`n--- 群組 C：待寫佇列揭露 ---" -ForegroundColor Yellow

$anchorC = New-MockIssue -Number 7 -Repo 'acme/plugin' -Title 'W-queue · primary anchor' -Labels @('sc:work', 'sc:station-4')

# C1：佇列檔不存在 ⇒ 顯示「待寫佇列不存在」，不是 0
$sC1 = New-MockSnapshot -WorkId 'W-queue' -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorC }) `
    -Queue ([pscustomobject]@{ Exists = $false; Count = $null; Path = './queue.json'; ParseError = $null })
$rC1 = Invoke-Build -Snapshot $sC1
Assert-Match -Name 'C1 佇列不存在 ⇒「待寫佇列不存在」' -Text $rC1.Html -Pattern '待寫佇列不存在'
Assert-NotMatch -Name 'C1 不得誤顯示為「待寫 0 筆」' -Text $rC1.Html -Pattern '待寫 0 筆'

# C2：佇列非空（3 筆）⇒「待寫 3 筆」＋在跑/停滯數加註「寫入斷點期間不可信」
$sC2 = New-MockSnapshot -WorkId 'W-queue' -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorC }) `
    -TicketsQuery ([pscustomobject]@{ Ok = $true; FailedRepos = @(); Tickets = @($ticket1); ResultCountThisRun = 1; TotalCountReported = 1; HitPageCap = $false }) `
    -Queue ([pscustomobject]@{ Exists = $true; Count = 3; Path = './queue.json'; ParseError = $null })
$rC2 = Invoke-Build -Snapshot $sC2
Assert-Match -Name 'C2「待寫 3 筆」' -Text $rC2.Html -Pattern '待寫 3 筆'
Assert-Match -Name 'C2 badge 亦顯示「待寫 3 筆」' -Text $rC2.Html -Pattern 'badge--queue">待寫 3 筆</span>'
Assert-Match -Name 'C2 在跑數量加註「寫入斷點期間不可信」' -Text $rC2.Html -Pattern '在跑數量</dt><dd>1（寫入斷點期間不可信）'
Assert-Match -Name 'C2 停滯票數加註「寫入斷點期間不可信」' -Text $rC2.Html -Pattern '停滯票數（24h）</dt><dd>\d+（寫入斷點期間不可信）'
Assert-Match -Name 'C2 卡片內出現顯著警語' -Text $rC2.Html -Pattern '寫入斷點期間不可信（在跑數量'

# C3：佇列檔存在但讀取失敗（壞 JSON）⇒ 具名回報，🚫 不得靜默當 0
$sC3 = New-MockSnapshot -WorkId 'W-queue' -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorC }) `
    -Queue ([pscustomobject]@{ Exists = $true; Count = $null; Path = './queue.json'; ParseError = 'Unexpected token' })
$rC3 = Invoke-Build -Snapshot $sC3
Assert-Match -Name 'C3 佇列讀取失敗具名' -Text $rC3.Html -Pattern '待寫佇列讀取失敗：Unexpected token'

Write-Host "`n--- 群組 C 完成 ---"

# ============================================================================
# 群組 D：§4.5 刷新時機（-NoReconcile）
# ============================================================================
Write-Host "`n--- 群組 D：刷新時機 ---" -ForegroundColor Yellow

$anchorD = New-MockIssue -Number 8 -Repo 'acme/plugin' -Title 'W-reconcile · primary anchor' -Labels @('sc:work', 'sc:station-4')
$sD = New-MockSnapshot -WorkId 'W-reconcile' -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorD })
$cacheD = [pscustomobject]@{ workId = 'W-reconcile'; lastFullSyncTimeUtc = (Get-Date).ToUniversalTime().ToString('o'); lastReconcileTimeUtc = (Get-Date).ToUniversalTime().AddDays(-1).ToString('o'); lastTicketCount = 0; anchorFound = $true }
$rD1 = Invoke-Build -Snapshot $sD -CacheBaseline $cacheD -NoReconcile
Assert-Match -Name 'D1 無對帳模式：「本次未對帳，沿用 <時間> 結果」' -Text $rD1.Html -Pattern '本次未對帳，沿用 .* 結果'

$rD2 = Invoke-Build -Snapshot $sD -CacheBaseline $cacheD
Assert-Match -Name 'D2 完整模式：對帳欄位保留位置（T-17 未實作，誠實聲明非偽造已對帳）' -Text $rD2.Html -Pattern '對帳：尚未實作（T-17 範圍）'
Assert-NotMatch -Name 'D2 完整模式不得偽稱已完成對帳' -Text $rD2.Html -Pattern '對帳：已完成'

Write-Host "`n--- 群組 D 完成 ---"

# ============================================================================
# 群組 E：PS 5.1／StrictMode 陷阱回歸測試
# ============================================================================
Write-Host "`n--- 群組 E：StrictMode 陷阱回歸測試 ---" -ForegroundColor Yellow

# E1：0 筆 Tickets 陣列不得在 Build-RunningAndStaleCounts／ConvertTo-StatusLight／
#     Get-TicketDirtyStationLabels 任一處被錯誤解卷成 $null（開發過程中真實踩到的 bug：
#     `$tickets = if ($ticketsOk) { @(...) } else { @() }` 這種 if 表達式賦值形式，即使區塊內
#     已經 @() 包過，0 筆仍會被 if 整體表達式的管線收集攤平成 $null，導致下游 .Count 在
#     StrictMode 直接拋錯。已改為陳述式形式 if/else 賦值，此處鎖住不回歸）。
try {
    $sE1 = New-MockSnapshot -AnchorQuery ([pscustomobject]@{ Ok = $false; Found = $false; FailureDetail = 'x: timeout'; Issue = $null }) `
        -TicketsQuery ([pscustomobject]@{ Ok = $true; FailedRepos = @(); Tickets = @(); ResultCountThisRun = 0; TotalCountReported = 0; HitPageCap = $false })
    $rE1 = Invoke-Build -Snapshot $sE1
    Assert-True -Name 'E1 anchor 查詢失敗＋0 筆 tickets 不拋例外（陣列解卷回歸測試）' -Condition $true
} catch {
    Assert-True -Name 'E1 anchor 查詢失敗＋0 筆 tickets 不拋例外（陣列解卷回歸測試）' -Condition $false -Detail $_.Exception.Message
}

# E2：Mandatory 陣列參數收到空集合不得被 PowerShell 參數繫結器拒絕（開發過程中真實踩到：
#     `[Parameter(Mandatory)][array]$X` 收到 @() 時繫結器本身拋「Cannot bind argument … because
#     it is an empty collection」，與呼叫端邏輯無關、是宣告方式問題。已移除相關陣列參數的
#     Mandatory 標記，此處鎖住不回歸）。
try {
    $null = Build-RunningAndStaleCounts -Tickets @() -NowUtc (Get-Date).ToUniversalTime()
    Assert-True -Name 'E2 空陣列可繫結進陣列型別參數' -Condition $true
} catch {
    Assert-True -Name 'E2 空陣列可繫結進陣列型別參數' -Condition $false -Detail $_.Exception.Message
}

# E3：CacheBaseline 為 $null 時（無基線）不得對其取屬性拋例外
try {
    $sE3 = New-MockSnapshot
    $rE3 = Invoke-Build -Snapshot $sE3 -CacheBaseline $null
    Assert-True -Name 'E3 CacheBaseline=$null 不拋例外' -Condition $true
} catch {
    Assert-True -Name 'E3 CacheBaseline=$null 不拋例外' -Condition $false -Detail $_.Exception.Message
}

# E4：Read-BoardQueueInfo 對 0 筆／壞檔／不存在三種情況皆不得拋例外或誤判
$tmpQueueDir = Join-Path ([System.IO.Path]::GetTempPath()) "t09-queue-test-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmpQueueDir -Force | Out-Null
try {
    $emptyQueuePath = Join-Path $tmpQueueDir 'empty.json'
    Set-Content -LiteralPath $emptyQueuePath -Value '[]' -Encoding UTF8
    $qEmpty = Read-BoardQueueInfo -QueuePath $emptyQueuePath
    Assert-Equal -Name 'E4a 空陣列佇列檔 ⇒ Count=0（不是 $null 判定不存在）' -Expected 0 -Actual $qEmpty.Count
    Assert-True -Name 'E4a Exists=$true（檔案確實存在，只是 0 筆）' -Condition $qEmpty.Exists

    $badQueuePath = Join-Path $tmpQueueDir 'bad.json'
    Set-Content -LiteralPath $badQueuePath -Value '{not valid json' -Encoding UTF8
    $qBad = Read-BoardQueueInfo -QueuePath $badQueuePath
    Assert-True -Name 'E4b 壞 JSON ⇒ ParseError 非空（不得靜默當 0）' -Condition (-not [string]::IsNullOrWhiteSpace($qBad.ParseError))

    $missingQueuePath = Join-Path $tmpQueueDir 'missing.json'
    $qMissing = Read-BoardQueueInfo -QueuePath $missingQueuePath
    Assert-True -Name 'E4c 檔案不存在 ⇒ Exists=$false' -Condition (-not $qMissing.Exists)
    Assert-True -Name 'E4c 檔案不存在 ⇒ Count=$null（非 0）' -Condition ($null -eq $qMissing.Count)

    $singleQueuePath = Join-Path $tmpQueueDir 'single.json'
    Set-Content -LiteralPath $singleQueuePath -Value '[{"action":"set-labels","target":{"repo":"a/b","issue":1},"payload":{"labels":["x"]},"source":"T-01"}]' -Encoding UTF8
    $qSingle = Read-BoardQueueInfo -QueuePath $singleQueuePath
    Assert-Equal -Name 'E4d 單一元素佇列 ⇒ Count=1（不被解卷成純量）' -Expected 1 -Actual $qSingle.Count
} finally {
    Remove-Item -LiteralPath $tmpQueueDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n--- 群組 E 完成 ---"

# ============================================================================
# 群組 F：Save/Read 邊界情況與 Invoke-StationBoardRender 整合（仍全程不連網，用 -MockSnapshot）
# ============================================================================
Write-Host "`n--- 群組 F：Save／Read／整合 ---" -ForegroundColor Yellow

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "t09-render-test-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
try {
    $outPath = Join-Path $tmpDir 'board.html'

    # F1：首次 render（無既有 artifact）⇒ Read-CacheBaselineFromExistingArtifact 回 $null
    $cacheFirst = Read-CacheBaselineFromExistingArtifact -OutputPath $outPath
    Assert-True -Name 'F1 首次 render 無既有 artifact ⇒ 讀回 $null（合法降級，非錯誤）' -Condition ($null -eq $cacheFirst)

    # F2：整合呼叫 Invoke-StationBoardRender（用 -MockSnapshot 完全略過網路）；成功寫檔後
    #     快取應可被下一輪讀回且欄位正確 round-trip
    $anchorF = New-MockIssue -Number 9 -Repo 'acme/plugin' -Title 'W-integ · primary anchor' -Labels @('sc:work', 'sc:station-4')
    $sF = New-MockSnapshot -WorkId 'W-integ' -AnchorQuery ([pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchorF }) `
        -TicketsQuery ([pscustomobject]@{ Ok = $true; FailedRepos = @(); Tickets = @(); ResultCountThisRun = 0; TotalCountReported = 0; HitPageCap = $false })
    $resultF = Invoke-StationBoardRender -WorkId 'W-integ' -PrimaryRepo 'acme/plugin' -PatPath 'unused' -QueuePath (Join-Path $tmpDir 'queue.json') `
        -TemplatePath $TplPath -OutputPath $outPath -MockSnapshot $sF 6>$null
    Assert-True -Name 'F2 整合呼叫寫檔成功' -Condition $resultF.SaveResult.Ok
    Assert-True -Name 'F2 輸出檔確實存在' -Condition (Test-Path -LiteralPath $outPath)

    $cacheSecond = Read-CacheBaselineFromExistingArtifact -OutputPath $outPath
    Assert-True -Name 'F3 二輪讀回快取非 $null（第一輪已成功寫入基線）' -Condition ($null -ne $cacheSecond)
    Assert-Equal -Name 'F3 快取 workId round-trip 正確' -Expected 'W-integ' -Actual $cacheSecond.workId

    # F4：面板寫入失敗時，Invoke-StationBoardRender 仍必須把完整字卡摘要印到主控台（文字輸出）
    #     ＋ 過期告警，🚫 不得靜默——用 Write-Host 導向暫存檔驗證（用 *>&1 一併捕捉 host+warning 串流）
    $badOutPath = '/no/such/dir/board.html'
    $captured = & {
        Invoke-StationBoardRender -WorkId 'W-integ' -PrimaryRepo 'acme/plugin' -PatPath 'unused' -QueuePath (Join-Path $tmpDir 'queue.json') `
            -TemplatePath $TplPath -OutputPath $badOutPath -MockSnapshot $sF
    } 3>&1 6>&1 | Out-String
    Assert-Match -Name 'F4 寫入失敗仍輸出完整字卡摘要文字（工作：W-integ）' -Text $captured -Pattern '工作：W-integ'
    Assert-Match -Name 'F4 寫入失敗告警含「面板未更新」與「已過期」' -Text $captured -Pattern '面板未更新，畫面內容已過期'
} finally {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n--- 群組 F 完成 ---"

# ============================================================================
# 群組 G：SkipErrorStateHandling（供 t09-test.ps1 動態紅燈驗證用的旁路旗標）行為驗證
# ============================================================================
Write-Host "`n--- 群組 G：SkipErrorStateHandling 旁路旗標 ---" -ForegroundColor Yellow

$sG = New-MockSnapshot -AnchorQuery ([pscustomobject]@{ Ok = $false; Found = $false; FailureDetail = 'acme/no-such-repo: 404 Not Found'; Issue = $null })
$rGNormal = Invoke-Build -Snapshot $sG
$rGSkip = Invoke-Build -Snapshot $sG -SkipErrorStateHandling
Assert-Contains -Name 'G1 正常模式：查詢失敗正確顯示為 query-failed（不是 empty）' -Haystack $rGNormal.ErrorStates -Needle 'query-failed'
Assert-NotContains -Name 'G1 正常模式：查詢失敗不得被歸類為 empty' -Haystack $rGNormal.ErrorStates -Needle 'empty'
Assert-Contains -Name 'G2 旁路模式（僅供紅燈驗證）：查詢失敗被錯誤地當成 empty 顯示' -Haystack $rGSkip.ErrorStates -Needle 'empty'
Assert-Match -Name 'G2 旁路模式：html 錯誤地顯示「目前無 active work」（示範失敗顯示成空狀態的 bug）' -Text $rGSkip.Html -Pattern '目前無 active work'

Write-Host "`n--- 群組 G 完成 ---"

# ============================================================================
# 總結
# ============================================================================
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
