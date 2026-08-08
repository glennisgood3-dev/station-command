#requires -Version 5.1
<#
.SYNOPSIS
    T-25：替 T-24 loop 加上單一收尾批次摘要與具名停因推播。

.DESCRIPTION
    本檔直接 dot-source ../t24/run-loop.ps1 -FunctionsOnly，複用其 loop 主體、六條停因判定與
    RoundSummaries；不重寫選件、派工、gate 或停手邏輯。

    正式流程只有一條底層推播入口 Send-StationUserPush。停因策略由 Send-StationStopNotification
    決定後呼叫該入口；T-29 的 50%／80% 成本告警也應直接沿用 Send-StationUserPush 與同一個
    NotificationSink，不得另立第二套通知機制。

.PARAMETER SkipRequiredNotifications
    ⚠️ 僅供紅燈驗證。刻意漏掉原本必須發送的停因②③④⑥推播；正式流程禁用。

.PARAMETER SkipSilentNotificationGuard
    ⚠️ 僅供紅燈驗證。刻意對安靜停因①⑤也推播；正式流程禁用。

.PARAMETER SkipBatchAggregation
    ⚠️ 僅供紅燈驗證。刻意改成逐輪留言並另留停因留言，以重現洗版；正式流程禁用。

.PARAMETER FunctionsOnly
    只載入函式，不執行 CLI。
#>

[CmdletBinding()]
param(
    [switch]$DemoMode,
    [switch]$SkipRequiredNotifications,
    [switch]$SkipSilentNotificationGuard,
    [switch]$SkipBatchAggregation,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：dot-source 鏈中的腳本有同名 param；必須先保存，避免 cascade 覆蓋後
# 讓 CLI 變成 exit 0、零輸出的靜默 no-op。所有保存名均使用 T25 獨有前綴。
$T25Dir = $PSScriptRoot
$T25DemoModeRequested = [bool]$DemoMode
$T25SkipRequiredNotificationsRequested = [bool]$SkipRequiredNotifications
$T25SkipSilentNotificationGuardRequested = [bool]$SkipSilentNotificationGuard
$T25SkipBatchAggregationRequested = [bool]$SkipBatchAggregation
$T25FunctionsOnlyRequested = [bool]$FunctionsOnly

$T25RunLoopPath = Join-Path $T25Dir '..\t24\run-loop.ps1'
if (-not (Test-Path -LiteralPath $T25RunLoopPath)) {
    throw "找不到 T-24 地基：$T25RunLoopPath"
}
. $T25RunLoopPath -FunctionsOnly
Set-StrictMode -Version Latest

function ConvertTo-T25SingleLine {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    return (($Text -replace "`r`n", ' ' -replace "`r", ' ' -replace "`n", ' ') -replace '\s{2,}', ' ').Trim()
}

function New-LoopBatchSummaryText {
    param(
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)]$LoopResult
    )
    if (-not ($LoopResult.PSObject.Properties.Name -contains 'StopReason') -or
        [string]::IsNullOrWhiteSpace([string]$LoopResult.StopReason)) {
        throw 'loop 尚未具名停止，不得產生收尾摘要（§5.3a：只有停止必須具名停因）'
    }

    $reason = [string]$LoopResult.StopReason
    $reasonText = Get-StopReasonText -Reason $reason
    $roundsRaw = if ($LoopResult.PSObject.Properties.Name -contains 'RoundSummaries') { $LoopResult.RoundSummaries } else { $null }
    if ($null -eq $roundsRaw) { $rounds = @() } else { $rounds = @($roundsRaw) }
    $roundParts = @($rounds | ForEach-Object { ConvertTo-T25SingleLine -Text ([string]$_) })
    $roundText = if ($roundParts.Count -eq 0) { '本批未派票，無 gate 判定' } else { $roundParts -join '；' }
    $detail = if ($LoopResult.PSObject.Properties.Name -contains 'StopDetail') {
        ConvertTo-T25SingleLine -Text ([string]$LoopResult.StopDetail)
    } else { '' }
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $reasonText }

    return "loop 批次摘要｜work=$WorkId｜輪次結果：$roundText｜停因$reason：$reasonText｜停因細節：$detail"
}

function New-LoopCommentQueueItem {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$Source
    )
    # 佇列格式正典：恰好 action／target／payload／source 四欄；comment payload 只有完整 body。
    return [pscustomobject][ordered]@{
        action  = 'comment'
        target  = [pscustomobject][ordered]@{ repo = $Repo; issue = $IssueNumber }
        payload = [pscustomobject][ordered]@{ body = $Body }
        source  = $Source
    }
}

function Send-StationUserPush {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Category = 'general',
        [AllowNull()][AllowEmptyString()][string]$StopReason = '',
        [scriptblock]$NotificationSink
    )
    $notification = [pscustomobject]@{
        Channel    = 'station-user-push'
        Category   = $Category
        StopReason = $StopReason
        Message    = $Message
    }
    if ($null -ne $NotificationSink) {
        & $NotificationSink $notification
    } else {
        Write-Host "[主動推播][station-user-push][$Category] $Message"
    }
    return [pscustomobject]@{ Sent = $true; StopReason = $StopReason; Message = $Message; Channel = 'station-user-push'; Category = $Category }
}

function Send-StationStopNotification {
    param(
        [Parameter(Mandatory)][string]$StopReason,
        [Parameter(Mandatory)][string]$Message,
        [scriptblock]$NotificationSink,
        [switch]$SkipRequiredNotifications,
        [switch]$SkipSilentNotificationGuard
    )
    $mustNotify = Test-StopReasonRequiresNotification -Reason $StopReason
    $shouldSend = $mustNotify

    if ($SkipRequiredNotifications -and $mustNotify) {
        Write-Warning '⚠️ -SkipRequiredNotifications 已開啟：刻意漏送必須推播的停因，僅供紅燈驗證，正式流程禁用。'
        $shouldSend = $false
    }
    if ($SkipSilentNotificationGuard -and (-not $mustNotify)) {
        Write-Warning '⚠️ -SkipSilentNotificationGuard 已開啟：刻意對安靜停因推播，僅供紅燈驗證，正式流程禁用。'
        $shouldSend = $true
    }

    if (-not $shouldSend) {
        return [pscustomobject]@{ Sent = $false; StopReason = $StopReason; Message = $Message; Channel = 'station-user-push'; Category = 'loop-stop' }
    }
    return Send-StationUserPush -Message $Message -Category 'loop-stop' -StopReason $StopReason -NotificationSink $NotificationSink
}

function Add-T25CommentGuarded {
    param(
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)]$Item
    )
    if ($Item.action -ne 'comment') {
        throw "T-25 只得產生 comment，收到：$($Item.action)"
    }
    return Add-RunQueueItemGuarded -QueuePath $QueuePath -Item $Item
}

function Add-T25PerRoundRedComments {
    param(
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][string]$AnchorRepo,
        [Parameter(Mandatory)][int]$AnchorIssueNumber,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$RoundSummaries,
        [Parameter(Mandatory)][string]$StopBody
    )
    Write-Warning '⚠️ -SkipBatchAggregation 已開啟：刻意逐輪留言，僅供紅燈驗證，正式流程禁用。'
    $added = New-Object System.Collections.ArrayList
    $index = 0
    foreach ($round in $RoundSummaries) {
        $index++
        $roundLine = ConvertTo-T25SingleLine -Text ([string]$round)
        $targetRepo = $AnchorRepo
        $targetIssue = $AnchorIssueNumber
        $match = [regex]::Match($roundLine, '(?<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#(?<issue>\d+)')
        if ($match.Success) {
            $targetRepo = $match.Groups['repo'].Value
            $targetIssue = [int]$match.Groups['issue'].Value
        }
        $item = New-LoopCommentQueueItem -Repo $targetRepo -IssueNumber $targetIssue -Body "loop 逐輪痕跡（紅燈模式）｜work=$WorkId｜$roundLine" -Source $WorkId
        $result = Add-T25CommentGuarded -QueuePath $QueuePath -Item $item
        if ($result.Added) { [void]$added.Add($item) }
    }
    $stopItem = New-LoopCommentQueueItem -Repo $AnchorRepo -IssueNumber $AnchorIssueNumber -Body $StopBody -Source $WorkId
    $stopResult = Add-T25CommentGuarded -QueuePath $QueuePath -Item $stopItem
    if ($stopResult.Added) { [void]$added.Add($stopItem) }
    return ,@($added)
}

function Complete-StationRunLoop {
    param(
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][string]$AnchorRepo,
        [Parameter(Mandatory)][int]$AnchorIssueNumber,
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)]$LoopResult,
        [scriptblock]$NotificationSink,
        [switch]$SkipRequiredNotifications,
        [switch]$SkipSilentNotificationGuard,
        [switch]$SkipBatchAggregation
    )
    $body = New-LoopBatchSummaryText -WorkId $WorkId -LoopResult $LoopResult
    $roundsRaw = if ($LoopResult.PSObject.Properties.Name -contains 'RoundSummaries') { $LoopResult.RoundSummaries } else { $null }
    if ($null -eq $roundsRaw) { $rounds = @() } else { $rounds = @($roundsRaw) }

    if ($SkipBatchAggregation) {
        $itemsRaw = Add-T25PerRoundRedComments -QueuePath $QueuePath -WorkId $WorkId -AnchorRepo $AnchorRepo `
            -AnchorIssueNumber $AnchorIssueNumber -RoundSummaries $rounds -StopBody $body
        $commentItems = @($itemsRaw)
    } else {
        $summaryItem = New-LoopCommentQueueItem -Repo $AnchorRepo -IssueNumber $AnchorIssueNumber -Body $body -Source $WorkId
        $add = Add-T25CommentGuarded -QueuePath $QueuePath -Item $summaryItem
        $commentItems = if ($add.Added) { @($summaryItem) } else { @() }
    }

    $pushMessage = "loop 已停止｜work=$WorkId｜停因$($LoopResult.StopReason)：$(Get-StopReasonText -Reason ([string]$LoopResult.StopReason))｜$($LoopResult.StopDetail)"
    $push = Send-StationStopNotification -StopReason ([string]$LoopResult.StopReason) -Message $pushMessage `
        -NotificationSink $NotificationSink -SkipRequiredNotifications:$SkipRequiredNotifications `
        -SkipSilentNotificationGuard:$SkipSilentNotificationGuard

    return [pscustomobject]@{
        LoopResult       = $LoopResult
        SummaryBody      = $body
        CommentItems     = @($commentItems)
        Notification     = $push
    }
}

function Invoke-StationRunLoopWithFinalization {
    param(
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][string]$PrimaryRepo,
        [Parameter(Mandatory)][int]$AnchorIssueNumber,
        [Parameter(Mandatory)][string[]]$ParticipatingRepos,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)][string]$AssigneeLogin,
        [Parameter(Mandatory)][scriptblock]$GateResultProvider,
        [scriptblock]$NotificationSink,
        [string]$CostStatePath = '',
        [int]$MaxIterations = 50,
        [switch]$SkipRequiredNotifications,
        [switch]$SkipSilentNotificationGuard,
        [switch]$SkipBatchAggregation
    )
    $loopResult = Invoke-StationRunLoop -WorkId $WorkId -PrimaryRepo $PrimaryRepo -AnchorIssueNumber $AnchorIssueNumber `
        -ParticipatingRepos $ParticipatingRepos -Headers $Headers -QueuePath $QueuePath -AssigneeLogin $AssigneeLogin `
        -GateResultProvider $GateResultProvider -CostStatePath $CostStatePath -MaxIterations $MaxIterations
    return Complete-StationRunLoop -WorkId $WorkId -AnchorRepo $PrimaryRepo -AnchorIssueNumber $AnchorIssueNumber `
        -QueuePath $QueuePath -LoopResult $loopResult -NotificationSink $NotificationSink `
        -SkipRequiredNotifications:$SkipRequiredNotifications -SkipSilentNotificationGuard:$SkipSilentNotificationGuard `
        -SkipBatchAggregation:$SkipBatchAggregation
}

function Invoke-T25DemoCli {
    $demoQueue = Join-Path $T25Dir 't25-demo-queue.json'
    Remove-Item -LiteralPath $demoQueue -Force -ErrorAction SilentlyContinue
    $demoResult = [pscustomobject]@{
        StopReason = '④'
        StopDetail = 'demo：scope 需變更'
        RoundSummaries = @('第 1 輪：demo/repo#21 PASS', '第 2 輪：demo/repo#22 FAIL，安排 rework', '第 3 輪：demo/repo#22 PASS')
    }
    $sink = { param($n) Write-Host "[Demo 推播收到] channel=$($n.Channel) stop=$($n.StopReason)" }
    $done = Complete-StationRunLoop -WorkId 'W-t25-demo' -AnchorRepo 'demo/repo' -AnchorIssueNumber 1 `
        -QueuePath $demoQueue -LoopResult $demoResult -NotificationSink $sink `
        -SkipRequiredNotifications:$T25SkipRequiredNotificationsRequested `
        -SkipSilentNotificationGuard:$T25SkipSilentNotificationGuardRequested `
        -SkipBatchAggregation:$T25SkipBatchAggregationRequested
    $itemsRaw = Read-QueueFile -QueuePath $demoQueue
    if ($null -eq $itemsRaw) { $items = @() } else { $items = @($itemsRaw) }
    Write-Host 'T-25 CLI DemoMode 已實際執行（全程離線）'
    Write-Host "佇列總筆數=$($items.Count)；comment 筆數=$(@($items | Where-Object { $_.action -eq 'comment' }).Count)"
    Write-Host "推播已送=$($done.Notification.Sent)；停因=$($done.Notification.StopReason)"
    Write-Host "摘要=$($done.SummaryBody)"
    Remove-Item -LiteralPath $demoQueue -Force -ErrorAction SilentlyContinue
}

if (-not $T25FunctionsOnlyRequested) {
    if (-not $T25DemoModeRequested) {
        throw '直接執行請指定 -DemoMode；完整 loop 請 dot-source -FunctionsOnly 後呼叫 Invoke-StationRunLoopWithFinalization。'
    }
    Invoke-T25DemoCli
}
