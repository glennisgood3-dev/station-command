#requires -Version 5.1
<#
.SYNOPSIS
    T-25 完整離線驗收。預期值固定來自本檔的人造停因表與三輪票號表，不讀被測輸出反推。

.PARAMETER SkipRequiredNotifications
    ⚠️ 僅供紅燈驗證，正式流程禁用。預期使「該叫不叫」斷言真的失敗並令本腳本 exit 1。

.PARAMETER SkipSilentNotificationGuard
    ⚠️ 僅供紅燈驗證，正式流程禁用。預期使「不該叫狂叫」斷言真的失敗並令本腳本 exit 1。

.PARAMETER SkipBatchAggregation
    ⚠️ 僅供紅燈驗證，正式流程禁用。預期使「三輪恰一則摘要」斷言真的失敗並令本腳本 exit 1。
#>
[CmdletBinding()]
param(
    [switch]$SkipRequiredNotifications,
    [switch]$SkipSilentNotificationGuard,
    [switch]$SkipBatchAggregation,
    [string]$ReportPath = (Join-Path $PSScriptRoot 't25-offline-test-report.txt')
)

$ErrorActionPreference = 'Stop'
$T25TestDir = $PSScriptRoot
$T25TestSkipRequired = [bool]$SkipRequiredNotifications
$T25TestSkipSilentGuard = [bool]$SkipSilentNotificationGuard
$T25TestSkipAggregation = [bool]$SkipBatchAggregation
$T25TestReportPath = $ReportPath

$script:MockIssueState = @{}
$script:MockResponses = @{}

function Invoke-RestMethod {
    [CmdletBinding()]
    param([string]$Uri, $Headers, [string]$Method = 'Get', $Body, [string]$ContentType)
    if ($Method -ne 'Get') { throw "T-25 loop mock 只允許 GET，收到：$Method $Uri" }
    if ($Uri -match '/repos/([^/]+)/([^/]+)/issues/(\d+)$') {
        $key = "$($Matches[1])/$($Matches[2])#$($Matches[3])"
        if ($script:MockIssueState.ContainsKey($key)) { return $script:MockIssueState[$key] }
        return $null
    }
    if ($script:MockResponses.ContainsKey($Uri)) { return $script:MockResponses[$Uri] }
    if ($Uri -match '/issues\?') { return ,@() }
    throw "T-25 離線 mock 拒絕未列入白名單的讀取：$Method $Uri"
}

. (Join-Path $T25TestDir 'run-finalize.ps1') -FunctionsOnly
Set-StrictMode -Version Latest

$script:TestLines = New-Object System.Collections.ArrayList
$script:FailCount = 0

function Write-TestLine {
    param([Parameter(Mandatory)][string]$Line)
    Write-Host $Line
    [void]$script:TestLines.Add($Line)
}

function Assert-T25 {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-TestLine "[PASS] $Name $Detail"
    } else {
        Write-TestLine "[FAIL] $Name $Detail"
        $script:FailCount++
    }
}

function New-T25TempPath {
    param([Parameter(Mandatory)][string]$Name, [string]$Extension = 'json')
    return (Join-Path ([System.IO.Path]::GetTempPath()) "t25-$Name-$([Guid]::NewGuid().ToString('N').Substring(0,8)).$Extension")
}

function New-T25MockIssue {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$Number,
        [string]$Body = '',
        [string[]]$Labels = @(),
        [string]$State = 'open',
        [string]$Title = 'mock issue',
        [string]$Milestone = $null
    )
    $issue = [pscustomobject]@{
        number = $Number; title = $Title; body = $Body; state = $State
        labels = @($Labels | ForEach-Object { [pscustomobject]@{ name = $_ } })
        assignees = @()
        milestone = if ($Milestone) { [pscustomobject]@{ title = $Milestone } } else { $null }
        RepoString = $Repo
    }
    $script:MockIssueState["$Repo#$Number"] = $issue
    return $issue
}

function Read-T25QueueSafe {
    param([Parameter(Mandatory)][string]$Path)
    $raw = Read-QueueFile -QueuePath $Path
    if ($null -eq $raw) { return ,@() }
    return ,@($raw)
}

Write-TestLine '群組 A：六條停因的推播矩陣（獨立人造預期值）'

# 獨立預期值來源：人手列出的 §5.3a 六停因配置；絕不呼叫被測函式計算 ExpectedPushCount。
$expectedPushCount = [ordered]@{ '①' = 0; '②' = 1; '③' = 1; '④' = 1; '⑤' = 0; '⑥' = 1 }
$actualPushCount = [ordered]@{}
$allCapturedPushes = New-Object System.Collections.ArrayList
foreach ($reason in @('①', '②', '③', '④', '⑤', '⑥')) {
    $queuePath = New-T25TempPath -Name "stop-$reason"
    $script:CapturedPushes = New-Object System.Collections.ArrayList
    $sink = { param($n) [void]$script:CapturedPushes.Add($n) }
    $fabricated = [pscustomobject]@{
        StopReason = $reason
        StopDetail = "人造停因配置：停因$reason"
        RoundSummaries = @()
    }
    Complete-StationRunLoop -WorkId "W-stop-$reason" -AnchorRepo 'mock/stop' -AnchorIssueNumber 77 `
        -QueuePath $queuePath -LoopResult $fabricated -NotificationSink $sink `
        -SkipRequiredNotifications:$T25TestSkipRequired -SkipSilentNotificationGuard:$T25TestSkipSilentGuard `
        -SkipBatchAggregation:$T25TestSkipAggregation | Out-Null
    $actualPushCount[$reason] = @($script:CapturedPushes).Count
    foreach ($captured in @($script:CapturedPushes)) { [void]$allCapturedPushes.Add($captured) }
    Remove-Item -LiteralPath $queuePath -Force -ErrorAction SilentlyContinue
}
$requiredActual = @('②', '③', '④', '⑥' | ForEach-Object { $actualPushCount[$_] })
$silentActual = @('①', '⑤' | ForEach-Object { $actualPushCount[$_] })
Assert-T25 -Name 'A1 斷言「停因②③④⑥必須各主動推播一次」（錯誤模式：該叫不叫）' `
    -Condition (($requiredActual -join ',') -eq '1,1,1,1') `
    -Detail "獨立預期=②:1,③:1,④:1,⑥:1；實際=②:$($actualPushCount['②']),③:$($actualPushCount['③']),④:$($actualPushCount['④']),⑥:$($actualPushCount['⑥'])"
Assert-T25 -Name 'A2 斷言「停因①⑤必須安靜、零推播」（錯誤模式：不該叫狂叫）' `
    -Condition (($silentActual -join ',') -eq '0,0') `
    -Detail "獨立預期=①:0,⑤:0；實際=①:$($actualPushCount['①']),⑤:$($actualPushCount['⑤'])"
$wrongChannels = @($allCapturedPushes | Where-Object { $_.Channel -ne 'station-user-push' -or $_.Category -ne 'loop-stop' })
Assert-T25 -Name 'A3 每次停因推播皆走唯一 station-user-push 管道（T-29 可沿用同一底層入口）' `
    -Condition ($wrongChannels.Count -eq 0) `
    -Detail "總推播數=$(@($allCapturedPushes).Count)，錯誤管道數=$($wrongChannels.Count)"
$script:CostChannelPushes = New-Object System.Collections.ArrayList
$costSink = { param($n) [void]$script:CostChannelPushes.Add($n) }
Send-StationUserPush -Message '人造 50% 成本告警（只驗管道，不做 T-29 記帳）' -Category 'cost-warning' -NotificationSink $costSink | Out-Null
Assert-T25 -Name 'A4 T-29 可直接沿用同一底層推播入口，不需第二套機制' `
    -Condition ((@($script:CostChannelPushes).Count -eq 1) -and ($script:CostChannelPushes[0].Channel -eq 'station-user-push') -and ($script:CostChannelPushes[0].Category -eq 'cost-warning'))

Write-TestLine '群組 B：實跑 T-24 三輪後收尾，只准一則批次摘要'

# 獨立輪次預期：三張人造票各 PASS 一輪；預期票號與摘要數均在呼叫被測 loop 前固定。
$expectedTicketNumbers = @(101, 102, 103)
$expectedSummaryCommentCount = 1
$ticketBody = "executor: fullstack-developer`nbasis: 人造測試`ndepends_on: []`n不可逆動作: 無"
$tickets = @()
foreach ($number in $expectedTicketNumbers) {
    $tickets += New-T25MockIssue -Repo 'mock/loop' -Number $number -Title "T-$number" -Body $ticketBody `
        -Labels @('sc:ticket') -Milestone 'W-three-rounds'
}
$script:MockResponses['https://api.github.com/repos/mock/loop/issues?labels=sc:ticket&state=all&per_page=100'] = @($tickets)
New-T25MockIssue -Repo 'mock/loop' -Number 77 -Title 'W-three-rounds anchor' -Labels @('sc:work', 'sc:station-4') | Out-Null
$queueB = New-T25TempPath -Name 'three-rounds'
$script:LoopPushes = New-Object System.Collections.ArrayList
$loopSink = { param($n) [void]$script:LoopPushes.Add($n) }
$passProvider = { param($selected, $iteration) [pscustomobject]@{ Pass = $true; ScopeChangeNeeded = $false; Detail = "人造第 $iteration 輪 PASS" } }
$wrapped = Invoke-StationRunLoopWithFinalization -WorkId 'W-three-rounds' -PrimaryRepo 'mock/loop' -AnchorIssueNumber 77 `
    -ParticipatingRepos @('mock/loop') -Headers @{ Authorization = 'FAKE' } -QueuePath $queueB `
    -AssigneeLogin 'offline-tester' -GateResultProvider $passProvider -NotificationSink $loopSink -MaxIterations 10 `
    -SkipRequiredNotifications:$T25TestSkipRequired -SkipSilentNotificationGuard:$T25TestSkipSilentGuard `
    -SkipBatchAggregation:$T25TestSkipAggregation
$queueItemsRaw = Read-T25QueueSafe -Path $queueB
$queueItems = @($queueItemsRaw)
$commentItems = @($queueItems | Where-Object { $_.action -eq 'comment' })
$assigneeItems = @($queueItems | Where-Object { $_.action -eq 'set-assignee' })
Assert-T25 -Name 'B1 斷言「loop 跑三輪只產生恰一則摘要留言，非逐輪洗版」' `
    -Condition ($commentItems.Count -eq $expectedSummaryCommentCount) `
    -Detail "獨立預期=$expectedSummaryCommentCount；實際 comment=$($commentItems.Count)；RoundSummaries=$(@($wrapped.LoopResult.RoundSummaries).Count)"
Assert-T25 -Name 'B2 loop 的確完成三個派票／gate 判定輪次後才以停因⑤收斂' `
    -Condition ((@($wrapped.LoopResult.RoundSummaries).Count -eq 3) -and ($wrapped.LoopResult.StopReason -eq '⑤') -and ($assigneeItems.Count -eq 3)) `
    -Detail "輪次=$(@($wrapped.LoopResult.RoundSummaries).Count)，停因=$($wrapped.LoopResult.StopReason)，派工項=$($assigneeItems.Count)"
$summaryBody = [string]$wrapped.SummaryBody
$containsAllRounds = $true
foreach ($number in $expectedTicketNumbers) {
    if ($summaryBody -notlike "*mock/loop#$number*PASS*") { $containsAllRounds = $false }
}
Assert-T25 -Name 'B3 單行摘要涵蓋三輪派票與三次 gate=PASS，並具名停因⑤' `
    -Condition ($containsAllRounds -and ($summaryBody -like '*停因⑤*') -and ($summaryBody -notmatch "`r|`n")) `
    -Detail $summaryBody
Assert-T25 -Name 'B4 續跑期間零逐輪 comment；唯一 comment 目標為 anchor' `
    -Condition (($commentItems.Count -eq 1) -and ($commentItems[0].target.repo -eq 'mock/loop') -and ([int]$commentItems[0].target.issue -eq 77)) `
    -Detail "comment 目標=$(if ($commentItems.Count -gt 0) { "$($commentItems[0].target.repo)#$($commentItems[0].target.issue)" } else { '(無)' })"

Write-TestLine '群組 C：佇列 schema 與 run 產生權邊界'
$schemaAllExact = $true
foreach ($item in $queueItems) {
    $names = @($item.PSObject.Properties.Name | Sort-Object)
    if (($names -join ',') -ne 'action,payload,source,target') { $schemaAllExact = $false }
}
$allowedActions = @('set-assignee', 'set-ticket-fields', 'comment')
$badActions = @($queueItems | Where-Object { $allowedActions -notcontains $_.action })
$forbiddenActions = @('set-labels', 'close-issue', 'create-issue', 'create-milestone')
$forbiddenHits = @($queueItems | Where-Object { $forbiddenActions -contains $_.action })
Assert-T25 -Name 'C1 全部佇列項恰四欄 action／target／payload／source' -Condition $schemaAllExact -Detail "檢查筆數=$($queueItems.Count)"
Assert-T25 -Name 'C2 run 只產生 set-assignee／set-ticket-fields／comment 三型' -Condition ($badActions.Count -eq 0) -Detail "違規=$($badActions.Count)"
Assert-T25 -Name 'C3 未產生 label／開關 issue／建票類 gate 或 intake 專屬型別' -Condition ($forbiddenHits.Count -eq 0) -Detail "違規=$($forbiddenHits.Count)"
if ($commentItems.Count -gt 0) {
    $commentProps = @($commentItems[0].payload.PSObject.Properties.Name)
    Assert-T25 -Name 'C4 摘要是正典 comment schema：payload 只有完整 body' -Condition (($commentProps.Count -eq 1) -and ($commentProps[0] -eq 'body'))
} else {
    Assert-T25 -Name 'C4 摘要是正典 comment schema：payload 只有完整 body' -Condition $false -Detail '沒有 comment 可驗'
}

Write-TestLine '群組 D：用 T-21 既有套用器的隔離副本套用後，可從 anchor 留言端點讀回'
$applyDir = Join-Path ([System.IO.Path]::GetTempPath()) "t25-apply-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
[void](New-Item -ItemType Directory -Path $applyDir)
Copy-Item -LiteralPath (Join-Path $T25TestDir '..\t21\apply-queue.ps1') -Destination (Join-Path $applyDir 'apply-queue.ps1')
Copy-Item -LiteralPath (Join-Path $T25TestDir '..\t21\queue-common.ps1') -Destination (Join-Path $applyDir 'queue-common.ps1')
$applyQueue = Join-Path $applyDir 'queue.json'
$commentStore = Join-Path $applyDir 'comments.json'
$patFile = Join-Path $applyDir 'fake-pat.txt'
[System.IO.File]::WriteAllText($patFile, 'FAKE-TOKEN-NOT-REAL', (New-Object System.Text.UTF8Encoding($true)))
$applyItem = New-LoopCommentQueueItem -Repo 'mock/apply' -IssueNumber 77 -Body $summaryBody -Source 'W-three-rounds'
Write-QueueFile -QueuePath $applyQueue -Items @($applyItem)
$applyOutputRaw = & /opt/pwsh/pwsh -NoProfile -File (Join-Path $T25TestDir 't25-apply-mock.ps1') `
    -ApplyScriptPath (Join-Path $applyDir 'apply-queue.ps1') -PatPath $patFile -QueuePath $applyQueue `
    -CommentStorePath $commentStore 2>&1
$applyExit = $LASTEXITCODE
$applyOutput = @($applyOutputRaw)
$storedRaw = if (Test-Path -LiteralPath $commentStore) { (Get-Content -LiteralPath $commentStore -Raw -Encoding UTF8 | ConvertFrom-Json) } else { $null }
if ($null -eq $storedRaw) { $storedComments = @() } else { $storedComments = @($storedRaw) }
Assert-T25 -Name 'D1 T-21 apply-queue.ps1 隔離副本離線套用成功且回驗成功' -Condition ($applyExit -eq 0) -Detail "exit=$applyExit；$($applyOutput -join ' | ')"
Assert-T25 -Name 'D2 套用後在對應 anchor mock/apply#77 讀到完全相同摘要' `
    -Condition (($storedComments.Count -eq 1) -and ($storedComments[0].body -eq $summaryBody)) `
    -Detail "留言數=$($storedComments.Count)"
$remainingRaw = Read-QueueFile -QueuePath $applyQueue
if ($null -eq $remainingRaw) { $remaining = @() } else { $remaining = @($remainingRaw) }
Assert-T25 -Name 'D3 套用後回驗相符，comment 佇列項已出列' -Condition ($remaining.Count -eq 0) -Detail "剩餘=$($remaining.Count)"

Write-TestLine '群組 E：移除摘要後重跑既有 gate，判定完全不變'
$gateAnchor = [pscustomobject]@{
    number = 88; title = 'gate anchor'; body = '固定 body'; state = 'open'
    labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-1' })
    assignees = @(); comments = @([pscustomobject]@{ id = 1; body = $summaryBody })
}
$overrides = @{
    '1.glossary' = [pscustomobject]@{ Satisfied = $true; Detail = '人造已滿足' }
    '1.adr'      = [pscustomobject]@{ Satisfied = $true; Detail = '人造已滿足' }
    '1.confirm'  = [pscustomobject]@{ Satisfied = $true; Detail = '人造已滿足' }
}
$gateWithSummary = Invoke-GateCheck -AnchorIssue $gateAnchor -TargetStation 'sc:station-2' -ChecklistOverrides $overrides
$gateAnchor.comments = @()
$gateWithoutSummary = Invoke-GateCheck -AnchorIssue $gateAnchor -TargetStation 'sc:station-2' -ChecklistOverrides $overrides
$withProjection = [pscustomobject]@{ Pass = $gateWithSummary.OverallPass; Reason = $gateWithSummary.Reason; Detail = $gateWithSummary.Detail }
$withoutProjection = [pscustomobject]@{ Pass = $gateWithoutSummary.OverallPass; Reason = $gateWithoutSummary.Reason; Detail = $gateWithoutSummary.Detail }
Assert-T25 -Name 'E1 摘要存在與移除後的 gate 結果相同（摘要不參與任何 gate 判定）' `
    -Condition (($withProjection | ConvertTo-Json -Compress) -eq ($withoutProjection | ConvertTo-Json -Compress)) `
    -Detail "有摘要=$($withProjection | ConvertTo-Json -Compress)；移除後=$($withoutProjection | ConvertTo-Json -Compress)"

Remove-Item -LiteralPath $queueB -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $applyDir -Recurse -Force -ErrorAction SilentlyContinue

Write-TestLine "總結：PASS=$(@($script:TestLines | Where-Object { $_ -like '[[]PASS[]]*' }).Count) FAIL=$($script:FailCount)"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($T25TestReportPath, ($script:TestLines -join [Environment]::NewLine), $utf8Bom)
Write-Host "報告已寫入：$T25TestReportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
