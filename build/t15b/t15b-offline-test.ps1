#requires -Version 5.1
<#
.SYNOPSIS
    T-15b 離線測試：完成、人手關票、零票、open 票、四欄佇列、milestone 擴充與 PS 5.1 陣列邊界。
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$T15bTestRoot = $PSScriptRoot
$T15bFixtures = Join-Path $T15bTestRoot 'fixtures'
$script:T15bPassCount = 0
$script:T15bFailCount = 0
$script:T15bRedCount = 0
$script:T15bResults = New-Object System.Collections.ArrayList

function Assert-T15b {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:T15bPassCount++
        [void]$script:T15bResults.Add("[PASS] $Name $Detail")
        Write-Host "[PASS] $Name $Detail"
    } else {
        $script:T15bFailCount++
        [void]$script:T15bResults.Add("[FAIL] $Name $Detail")
        Write-Host "[FAIL] $Name $Detail"
    }
}

function Assert-T15bExpectedRed {
    param([Parameter(Mandatory)][string]$AssertionText, [Parameter(Mandatory)][bool]$Condition)
    if (-not $Condition) { throw "ASSERTION FAILED: $AssertionText" }
}

function Test-T15bStringSetEqual {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Actual, [Parameter(Mandatory)][AllowEmptyCollection()][array]$Expected)
    $a = @($Actual | Sort-Object)
    $e = @($Expected | Sort-Object)
    return ($a.Count -eq $e.Count) -and (@(Compare-Object $a $e -SyncWindow 0).Count -eq 0)
}

function Get-T15bActionCount {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Items, [Parameter(Mandatory)][string]$Action)
    return @($Items | Where-Object { $_.action -eq $Action }).Count
}

# 網路護欄：離線測試若漏 mock 而嘗試連網，立即失敗。
function Invoke-RestMethod {
    [CmdletBinding()]
    param([string]$Uri, $Headers, [string]$Method = 'Get', $Body, [string]$ContentType)
    throw "MOCK-MISS：離線測試禁止連網，收到 $Method $Uri"
}

. (Join-Path $T15bTestRoot 'work-complete.ps1') -SnapshotPath 'unused' -QueuePath 'unused' -ReportPath 'unused' -FunctionsOnly
. (Join-Path $T15bTestRoot 'apply-milestone-queue.ps1') -PatPath 'unused' -QueuePath 'unused' -ReportPath 'unused' -FunctionsOnly
Set-StrictMode -Version Latest

$green = Read-T15bWorkSnapshot -Path (Join-Path $T15bFixtures 'all-gate-closed.json')
$human = Read-T15bWorkSnapshot -Path (Join-Path $T15bFixtures 'human-closed.json')
$empty = Read-T15bWorkSnapshot -Path (Join-Path $T15bFixtures 'no-tickets.json')
$open = Read-T15bWorkSnapshot -Path (Join-Path $T15bFixtures 'open-ticket.json')

Write-Host '=== A. 核心紅燈：人手關票不得判完成 ==='
$redDecision = Invoke-T15bCompletionDecision -Snapshot $human -SkipHumanClosureCheck
try {
    Assert-T15bExpectedRed -AssertionText '存在人手關閉的票 ⇒ Decision 不得為 complete' -Condition ($redDecision.Decision -ne 'complete')
    Assert-T15b -Name 'A1 紅燈斷言應真的失敗' -Condition $false -Detail "實得 Decision=$($redDecision.Decision)"
} catch {
    if ($_.Exception.Message -like 'ASSERTION FAILED:*') {
        $script:T15bRedCount++
        $evidence = "[RED-CONFIRMED] $_；-SkipHumanClosureCheck 開啟後實得 Decision='$($redDecision.Decision)'"
        [void]$script:T15bResults.Add($evidence)
        Write-Host $evidence
    } else { throw }
}
Assert-T15b -Name 'A2 紅燈開關確實讓人手關票案例誤判 complete' -Condition ($redDecision.Decision -eq 'complete') -Detail $redDecision.Detail

Write-Host '=== B. 關閉紅燈開關後，同一斷言轉綠 ==='
$humanDecision = Invoke-T15bCompletionDecision -Snapshot $human
Assert-T15b -Name 'B1【驗收②】人手關票案例不判 complete' -Condition ($humanDecision.Decision -ne 'complete') -Detail $humanDecision.Detail
Assert-T15b -Name 'B2【驗收②】Decision 等於 fixture expected.awaiting-user' -Condition ($humanDecision.Decision -eq $human.expected.decision) -Detail "actual=$($humanDecision.Decision) expected=$($human.expected.decision)"
Assert-T15b -Name 'B3 零 open 票' -Condition ($humanDecision.OpenCount -eq [int]$human.expected.openCount)
Assert-T15b -Name 'B4 人手／未證關票筆數來自 fixture 預設值' -Condition (@($humanDecision.HumanOrUnprovenTickets).Count -eq [int]$human.expected.humanOrUnprovenCount)
Assert-T15b -Name 'B5 零 open 分支不套最小站公式' -Condition ($humanDecision.MinimumStationApplicable -eq [bool]$human.expected.minimumStationApplicable)
$humanItemsRaw = New-T15bCompletionQueueItems -Snapshot $human -Decision $humanDecision
$humanItems = @($humanItemsRaw)
Assert-T15b -Name 'B6 awaiting-user 只產 fixture 預期筆數' -Condition ($humanItems.Count -eq [int]$human.expected.queueCount)
Assert-T15b -Name 'B7 awaiting-user 不產 close-issue' -Condition ((Get-T15bActionCount -Items $humanItems -Action 'close-issue') -eq [int]$human.expected.actionCounts.'close-issue')
Assert-T15b -Name 'B8 awaiting-user 不產 close-milestone' -Condition ((Get-T15bActionCount -Items $humanItems -Action 'close-milestone') -eq [int]$human.expected.actionCounts.'close-milestone')
$humanLabels = @($humanItems[0].payload.labels)
Assert-T15b -Name 'B9 awaiting-user 完整 label 集合等於 fixture 預期' -Condition (Test-T15bStringSetEqual -Actual $humanLabels -Expected @($human.expected.anchorLabels)) -Detail "[$($humanLabels -join ', ')]"
Assert-T15b -Name 'B10 awaiting-user 完整 label 集合不殘留 station label' -Condition (@($humanLabels | Where-Object { $_ -match '^sc:station-' }).Count -eq 0)

Write-Host '=== C. 全票經站 5 gate 關閉 ⇒ 完成態批次收尾 ==='
$greenDecision = Invoke-T15bCompletionDecision -Snapshot $green
Assert-T15b -Name 'C1【驗收①】Decision 等於 fixture expected.complete' -Condition ($greenDecision.Decision -eq $green.expected.decision) -Detail $greenDecision.Detail
Assert-T15b -Name 'C2 票數等於 fixture 預設值' -Condition ($greenDecision.TicketCount -eq [int]$green.expected.ticketCount)
Assert-T15b -Name 'C3 open 數等於 fixture 預設值' -Condition ($greenDecision.OpenCount -eq [int]$green.expected.openCount)
Assert-T15b -Name 'C4 每張關票歸因皆合法' -Condition (@($greenDecision.ClosureChecks | Where-Object { -not $_.Satisfied }).Count -eq 0)
$milestoneConvention = Test-T15bMilestoneConventions -Snapshot $green
Assert-T15b -Name 'C5 全參與 repo milestone 慣例通過' -Condition $milestoneConvention.Satisfied -Detail $milestoneConvention.Detail
$greenItemsRaw = New-T15bCompletionQueueItems -Snapshot $green -Decision $greenDecision
$greenItems = @($greenItemsRaw)
Assert-T15b -Name 'C6 完成態佇列總筆數等於 fixture 預期' -Condition ($greenItems.Count -eq [int]$green.expected.queueCount)
foreach ($action in @('set-labels', 'close-issue', 'close-milestone')) {
    $actualCount = Get-T15bActionCount -Items $greenItems -Action $action
    $expectedCount = [int]$green.expected.actionCounts.$action
    Assert-T15b -Name "C action=$action 筆數來自 fixture 預期" -Condition ($actualCount -eq $expectedCount) -Detail "actual=$actualCount expected=$expectedCount"
}
$doneLabels = @($greenItems | Where-Object action -eq 'set-labels')[0].payload.labels
Assert-T15b -Name 'C10 sc:station-done 完整 label 集合等於 fixture 預期' -Condition (Test-T15bStringSetEqual -Actual @($doneLabels) -Expected @($green.expected.anchorLabels)) -Detail "[$($doneLabels -join ', ')]"
Assert-T15b -Name 'C11 anchor close 使用 canonical close-issue payload' -Condition ((@($greenItems | Where-Object action -eq 'close-issue')[0].payload.state -eq 'closed') -and (@($greenItems | Where-Object action -eq 'close-issue')[0].payload.state_reason -eq 'completed'))
$milestoneTargets = @($greenItems | Where-Object action -eq 'close-milestone' | ForEach-Object { "$($_.target.repo)#$($_.target.milestone)" })
Assert-T15b -Name 'C12 全參與 repo milestone 皆在批次目標內' -Condition (Test-T15bStringSetEqual -Actual $milestoneTargets -Expected @('acme/app#7', 'acme/lib#9')) -Detail "[$($milestoneTargets -join ', ')]"

Write-Host '=== D. 零票與 1 張 open 票的 PS 5.1 / StrictMode 邊界 ==='
$emptyDecision = Invoke-T15bCompletionDecision -Snapshot $empty
Assert-T15b -Name 'D1【驗收③】真正空 tickets 無錯誤且 Decision 等於 fixture 預期' -Condition ($emptyDecision.Decision -eq $empty.expected.decision)
Assert-T15b -Name 'D2【驗收③】零票不套最小站公式' -Condition ($emptyDecision.MinimumStationApplicable -eq [bool]$empty.expected.minimumStationApplicable)
$emptyItemsRaw = New-T15bCompletionQueueItems -Snapshot $empty -Decision $emptyDecision
$emptyItems = @($emptyItemsRaw)
Assert-T15b -Name 'D3 真正空陣列不被誤包成含 1 個空陣列' -Condition ($emptyItems.Count -eq [int]$empty.expected.queueCount) -Detail "Count=$($emptyItems.Count)"
$openDecision = Invoke-T15bCompletionDecision -Snapshot $open
Assert-T15b -Name 'D4 單一 ticket 純量邊界不觸發 .Count 錯誤' -Condition (($openDecision.TicketCount -eq [int]$open.expected.ticketCount) -and ($openDecision.Decision -eq $open.expected.decision))
Assert-T15b -Name 'D5 open 票不進完成態' -Condition ($openDecision.OpenCount -eq [int]$open.expected.openCount)
$openItemsRaw = New-T15bCompletionQueueItems -Snapshot $open -Decision $openDecision
$openItems = @($openItemsRaw)
Assert-T15b -Name 'D6 open 票產生 0 筆收尾佇列' -Condition ($openItems.Count -eq [int]$open.expected.queueCount)

Write-Host '=== E. 佇列四欄正典與冪等 ==='
foreach ($item in $greenItems + $humanItems) {
    $schema = Test-T15bQueueItemSchema -Item $item
    Assert-T15b -Name "E 四欄 schema：$($item.action) $($item.target.repo)" -Condition $schema.Valid -Detail $schema.Detail
    Assert-T15b -Name "E 外層恰四欄：$($item.action)" -Condition (@($item.PSObject.Properties.Name).Count -eq 4) -Detail ($item.PSObject.Properties.Name -join ',')
}
$badItem = [pscustomobject]@{ action = 'set-labels'; target = [pscustomobject]@{ repo = 'x/y'; issue = 1 }; payload = [pscustomobject]@{ labels = @() }; source = 'W-x'; extra = '禁止' }
$badSchema = Test-T15bQueueItemSchema -Item $badItem
Assert-T15b -Name 'E11 多第五欄必須拒絕' -Condition (-not $badSchema.Valid) -Detail $badSchema.Detail

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("t15b-test-" + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempDir)
try {
    $queuePath = Join-Path $tempDir 'queue.json'
    $first = Add-T15bQueueItemsIfAbsent -Path $queuePath -Items $greenItems
    $second = Add-T15bQueueItemsIfAbsent -Path $queuePath -Items $greenItems
    $persistedRaw = Read-QueueFile -QueuePath $queuePath
    $persisted = @($persistedRaw)
    Assert-T15b -Name 'E12 首次批次加入全部項目' -Condition ($first.Added -eq $greenItems.Count)
    Assert-T15b -Name 'E13 同一批重跑新增 0 筆（冪等）' -Condition ($second.Added -eq 0)
    Assert-T15b -Name 'E14 重跑後佇列筆數不增' -Condition ($persisted.Count -eq $greenItems.Count)
    foreach ($item in $persisted) {
        Assert-T15b -Name "E persisted 恰四欄：$($item.action)" -Condition (@($item.PSObject.Properties.Name).Count -eq 4)
    }
} finally {
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}

Write-Host '=== F. milestone 擴充套用器的 schema、冪等與回驗 seam ==='
$milestoneItem = @($greenItems | Where-Object action -eq 'close-milestone')[0]
$applySchema = Test-T15bCloseMilestoneItemSchema -Item $milestoneItem
Assert-T15b -Name 'F1 close-milestone 擴充 schema 合格' -Condition $applySchema.Valid -Detail $applySchema.Detail
$script:T15bMockMilestoneState = 'open'
$script:T15bMockPatchCount = 0
function Get-T15bCurrentMilestone {
    param([string]$Owner, [string]$Repo, [int]$MilestoneNumber, [hashtable]$Headers)
    return [pscustomobject]@{ number = $MilestoneNumber; state = $script:T15bMockMilestoneState }
}
function Invoke-RestMethod {
    [CmdletBinding()]
    param([string]$Uri, $Headers, [string]$Method = 'Get', $Body, [string]$ContentType)
    if ($Method -eq 'Patch') {
        $script:T15bMockPatchCount++
        $script:T15bMockMilestoneState = 'closed'
        return [pscustomobject]@{ state = 'closed' }
    }
    throw "MOCK-MISS：未預期的 $Method $Uri"
}
$pre = Test-T15bCloseMilestoneSatisfied -Item $milestoneItem -Headers @{}
Assert-T15b -Name 'F2 open milestone 套用前尚未達成' -Condition (-not $pre.Satisfied) -Detail $pre.Detail
Invoke-T15bCloseMilestoneWrite -Item $milestoneItem -Headers @{}
$post = Test-T15bCloseMilestoneSatisfied -Item $milestoneItem -Headers @{}
Assert-T15b -Name 'F3 PATCH 後直讀回驗為 closed' -Condition $post.Satisfied -Detail $post.Detail
Assert-T15b -Name 'F4 mock 寫入恰呼叫一次' -Condition ($script:T15bMockPatchCount -eq 1)

Write-Host '=== G. fail-closed milestone 慣例與可逆性形狀 ==='
$badMilestone = Read-T15bWorkSnapshot -Path (Join-Path $T15bFixtures 'all-gate-closed.json')
$badMilestone.participatingRepos[1].milestone.title = '同名但錯 work-id'
$badConvention = Test-T15bMilestoneConventions -Snapshot $badMilestone
Assert-T15b -Name 'G1 milestone title 不等於 work ID ⇒ 批次收尾前拒絕' -Condition (-not $badConvention.Satisfied) -Detail $badConvention.Detail
$threw = $false
try { [void](New-T15bCompletionQueueItems -Snapshot $badMilestone -Decision $greenDecision) } catch { $threw = ($_.Exception.Message -like 'milestone 慣例檢查失敗*') }
Assert-T15b -Name 'G2 milestone 慣例失敗時不產生部分批次' -Condition $threw
Assert-T15b -Name 'G3 收尾只用 closed（無 delete-milestone 動作）' -Condition (@($greenItems | Where-Object { $_.action -match 'delete' }).Count -eq 0)
Assert-T15b -Name 'G4 close-milestone payload 是可 reopen 的 state=closed' -Condition (@($greenItems | Where-Object action -eq 'close-milestone' | Where-Object { $_.payload.state -ne 'closed' }).Count -eq 0)

$summary = "TOTAL=$($script:T15bPassCount + $script:T15bFailCount) PASS=$($script:T15bPassCount) FAIL=$($script:T15bFailCount) RED-CONFIRMED=$script:T15bRedCount"
Write-Host $summary
[void]$script:T15bResults.Add($summary)
Write-Utf8BomFile -Path (Join-Path $T15bTestRoot 't15b-offline-test-report.txt') -Content ($script:T15bResults -join [Environment]::NewLine)
if ($script:T15bFailCount -gt 0) { exit 1 }
