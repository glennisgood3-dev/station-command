#requires -Version 5.1
<#
.SYNOPSIS
    T-15b：work 級完成態判定與待寫佇列產生器。

.DESCRIPTION
    讀取離線快照，判定全部票是否皆由站 5 gate 關閉。全數成立時產生 anchor 的
    sc:station-done、關閉 anchor、關閉全參與 repo milestone 的佇列項；若零張 open 票但
    任一關票事件不是 gate 身分所為，則只產生 sc:awaiting-user。所有 GitHub 寫入皆只形成
    四欄佇列項，本檔不呼叫任何 GitHub 寫入 API。

    -SkipHumanClosureCheck 是紅燈驗證專用開關：開啟後會把所有 closed 票誤當成 gate 關閉，
    僅供 t15b-offline-test.ps1 證明核心斷言真的失敗；正式流程絕對不得使用。
#>

[CmdletBinding()]
param(
    [string]$SnapshotPath,
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [string]$ReportPath = (Join-Path $PSScriptRoot 'work-complete-report.txt'),
    [switch]$SkipHumanClosureCheck,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# CLI 參數作用域防火牆：下方 dot-source 的 T-15a／T-10／T-21 皆有自己的 param 區塊，
# 其中 QueuePath、FunctionsOnly 等名稱會覆蓋呼叫端變數。任何 dot-source 前先全部另存成
# $T15b* 獨有名稱；後續主流程只讀這些快照，避免 exit 0 零輸出的靜默 no-op。
$T15bSnapshotPath = $SnapshotPath
$T15bQueuePath = $QueuePath
$T15bReportPath = $ReportPath
$T15bSkipHumanClosureCheck = $SkipHumanClosureCheck.IsPresent
$T15bFunctionsOnly = $FunctionsOnly.IsPresent
$T15bRoot = $PSScriptRoot

$T15bStation5Path = Join-Path $T15bRoot '..\t15a\station5-check.ps1'
if (-not (Test-Path -LiteralPath $T15bStation5Path)) {
    throw "找不到 T-15a 地基：$T15bStation5Path"
}
# 重用 T-15a 的 Find-LastCloseEvent，並由其 cascade 重用 T-10／T-21 的陣列、佇列與 UTF-8 函式。
. $T15bStation5Path -SubmissionPath 't15b-functions-only' -Repo 't15b/functions-only' -Issue 1 -FunctionsOnly
Set-ConsoleUtf8

function ConvertTo-T15bArray {
    param($Value)
    if ($null -eq $Value) { return ,@() }
    return ,@($Value)
}

function Get-T15bPropertyValue {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name, $DefaultValue = $null)
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $DefaultValue
}

function Read-T15bWorkSnapshot {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "work 快照不存在：$Path" }
    $snapshot = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $required = @('workId', 'primaryAnchor', 'participatingRepos', 'gateIdentityLogins', 'tickets')
    $missing = @($required | Where-Object { -not ($snapshot.PSObject.Properties.Name -contains $_) })
    if ($missing.Count -gt 0) { throw "work 快照缺必填欄位：$($missing -join '、')" }
    foreach ($anchorField in @('repo', 'issue', 'labels')) {
        if (-not ($snapshot.primaryAnchor.PSObject.Properties.Name -contains $anchorField)) {
            throw "primaryAnchor 缺欄位：$anchorField"
        }
    }
    return $snapshot
}

function Get-T15bLabelNames {
    param($Labels)
    $raw = ConvertTo-T15bArray -Value $Labels
    $raw = @($raw)
    $names = @()
    foreach ($label in $raw) {
        if ($label -is [string]) { $names += $label }
        elseif ($null -ne $label -and $label.PSObject.Properties.Name -contains 'name') { $names += [string]$label.name }
    }
    return ,@($names)
}

function Test-T15bTicketClosedByGate {
    param(
        [Parameter(Mandatory)]$Ticket,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$GateIdentityLogins,
        [switch]$SkipHumanClosureCheck
    )
    $repo = [string](Get-T15bPropertyValue -Object $Ticket -Name 'repo' -DefaultValue '(未知 repo)')
    $issue = Get-T15bPropertyValue -Object $Ticket -Name 'issue' -DefaultValue 0
    $state = [string](Get-T15bPropertyValue -Object $Ticket -Name 'state' -DefaultValue '')
    $target = "$repo#$issue"
    if ($state -ne 'closed') {
        return [pscustomobject]@{ Satisfied = $false; Target = $target; Actor = $null; Detail = "票仍為 '$state'，不是 closed" }
    }
    if ($SkipHumanClosureCheck) {
        return [pscustomobject]@{
            Satisfied = $true; Target = $target; Actor = '(略過)'
            Detail = '⚠️ -SkipHumanClosureCheck 已開啟：closed 票一律誤當成站 5 gate 關閉（僅供紅燈驗證，正式流程禁用）'
        }
    }
    $timelineRaw = Get-T15bPropertyValue -Object $Ticket -Name 'timeline' -DefaultValue $null
    $timeline = ConvertTo-T15bArray -Value $timelineRaw
    $timeline = @($timeline)
    $lastClose = Find-LastCloseEvent -TimelineEvents $timeline
    if (-not $lastClose.Found) {
        return [pscustomobject]@{ Satisfied = $false; Target = $target; Actor = $null; Detail = "$target 無 closed timeline 事件，不能證明經站 5 gate 關閉（fail-closed）" }
    }
    $identities = @($GateIdentityLogins)
    $legal = ($identities.Count -gt 0) -and ($identities -contains $lastClose.Actor)
    $detail = if ($legal) {
        "$target 最後一次 closed actor='$($lastClose.Actor)'，屬 gate 身分集合"
    } else {
        "$target 最後一次 closed actor='$($lastClose.Actor)'，不屬 gate 身分集合 [$($identities -join ', ')]，視為人手關閉／歸因未證"
    }
    return [pscustomobject]@{ Satisfied = $legal; Target = $target; Actor = $lastClose.Actor; Detail = $detail }
}

function Test-T15bMilestoneConventions {
    param([Parameter(Mandatory)]$Snapshot)
    $participantsRaw = Get-T15bPropertyValue -Object $Snapshot -Name 'participatingRepos' -DefaultValue $null
    $participants = ConvertTo-T15bArray -Value $participantsRaw
    $participants = @($participants)
    $gaps = @()
    if ($participants.Count -eq 0) { $gaps += 'participatingRepos 為空，無法關閉全參與 repo milestone' }
    $seen = @{}
    $anchorRef = "$($Snapshot.primaryAnchor.repo)#$($Snapshot.primaryAnchor.issue)"
    foreach ($participant in $participants) {
        $repo = [string](Get-T15bPropertyValue -Object $participant -Name 'repo' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($repo)) { $gaps += '參與 repo 項目缺 repo'; continue }
        if ($seen.ContainsKey($repo)) { $gaps += "參與 repo 重複：$repo" } else { $seen[$repo] = $true }
        $milestone = Get-T15bPropertyValue -Object $participant -Name 'milestone' -DefaultValue $null
        if ($null -eq $milestone) { $gaps += "$repo 缺 milestone"; continue }
        $number = Get-T15bPropertyValue -Object $milestone -Name 'number' -DefaultValue 0
        $title = [string](Get-T15bPropertyValue -Object $milestone -Name 'title' -DefaultValue '')
        $description = [string](Get-T15bPropertyValue -Object $milestone -Name 'description' -DefaultValue '')
        if ([int]$number -le 0) { $gaps += "$repo milestone.number 無效" }
        if ($title -ne $Snapshot.workId) { $gaps += "$repo milestone.title='$title'，應等於 work ID '$($Snapshot.workId)'" }
        $firstLine = ($description -split "`r?`n", 2)[0]
        if ($firstLine -notmatch [regex]::Escape("work-id: $($Snapshot.workId)")) { $gaps += "$repo milestone description 首行缺 work-id" }
        if ($firstLine -notmatch [regex]::Escape("primary-anchor: $anchorRef")) { $gaps += "$repo milestone description 首行缺 primary-anchor" }
    }
    if (-not $seen.ContainsKey([string]$Snapshot.primaryAnchor.repo)) { $gaps += 'primary repo 未列入 participatingRepos 全集' }
    $gaps = @($gaps)
    return [pscustomobject]@{
        Satisfied = ($gaps.Count -eq 0)
        Gaps = $gaps
        Detail = if ($gaps.Count -eq 0) { "共 $($participants.Count) 個參與 repo，milestone 慣例皆符合" } else { $gaps -join '｜' }
    }
}

function Invoke-T15bCompletionDecision {
    param([Parameter(Mandatory)]$Snapshot, [switch]$SkipHumanClosureCheck)
    $ticketsRaw = Get-T15bPropertyValue -Object $Snapshot -Name 'tickets' -DefaultValue $null
    $tickets = ConvertTo-T15bArray -Value $ticketsRaw
    $tickets = @($tickets)
    $openTickets = @($tickets | Where-Object { (Get-T15bPropertyValue -Object $_ -Name 'state' -DefaultValue '') -eq 'open' })

    # 零票是獨立安全分支：既不量測最小站，也不以空集合真值誤關整個 work。
    if ($tickets.Count -eq 0) {
        return [pscustomobject]@{
            Decision = 'no-tickets'; TicketCount = 0; OpenCount = 0; MinimumStationApplicable = $false
            ClosureChecks = @(); HumanOrUnprovenTickets = @(); Detail = 'work 目前零票；不套用未關閉票最小站公式，也不以空集合真值判完成'
        }
    }
    if ($openTickets.Count -gt 0) {
        return [pscustomobject]@{
            Decision = 'incomplete'; TicketCount = $tickets.Count; OpenCount = $openTickets.Count; MinimumStationApplicable = $true
            ClosureChecks = @(); HumanOrUnprovenTickets = @(); Detail = "仍有 $($openTickets.Count) 張 open 票，不進完成態收尾"
        }
    }

    $gateIdsRaw = Get-T15bPropertyValue -Object $Snapshot -Name 'gateIdentityLogins' -DefaultValue $null
    $gateIds = ConvertTo-T15bArray -Value $gateIdsRaw
    $gateIds = @($gateIds)
    $checks = @()
    foreach ($ticket in $tickets) {
        $checks += Test-T15bTicketClosedByGate -Ticket $ticket -GateIdentityLogins $gateIds -SkipHumanClosureCheck:$SkipHumanClosureCheck
    }
    $checks = @($checks)
    $unproven = @($checks | Where-Object { -not $_.Satisfied })
    if ($unproven.Count -gt 0) {
        return [pscustomobject]@{
            Decision = 'awaiting-user'; TicketCount = $tickets.Count; OpenCount = 0; MinimumStationApplicable = $false
            ClosureChecks = $checks; HumanOrUnprovenTickets = $unproven
            Detail = "零 open 票，但 $($unproven.Count) 張票非站 5 gate 關閉或歸因未證；不得判完成"
        }
    }
    return [pscustomobject]@{
        Decision = 'complete'; TicketCount = $tickets.Count; OpenCount = 0; MinimumStationApplicable = $false
        ClosureChecks = $checks; HumanOrUnprovenTickets = @(); Detail = "零 open 票，且 $($tickets.Count) 張票皆由站 5 gate 身分關閉"
    }
}

function New-T15bAnchorLabelSet {
    param([Parameter(Mandatory)]$Anchor, [Parameter(Mandatory)][ValidateSet('complete', 'awaiting-user')][string]$Mode)
    $names = Get-T15bLabelNames -Labels $Anchor.labels
    $names = @($names)
    $kept = @($names | Where-Object { $_ -notmatch '^sc:station-' -and $_ -ne 'sc:awaiting-user' })
    $wanted = if ($Mode -eq 'complete') { 'sc:station-done' } else { 'sc:awaiting-user' }
    return ,@($kept + @($wanted) | Select-Object -Unique)
}

function New-T15bQueueItem {
    param([Parameter(Mandatory)][string]$Action, [Parameter(Mandatory)]$Target, [Parameter(Mandatory)]$Payload, [Parameter(Mandatory)][string]$Source)
    return [pscustomobject]@{ action = $Action; target = $Target; payload = $Payload; source = $Source }
}

function New-T15bCompletionQueueItems {
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)]$Decision)
    $items = @()
    if ($Decision.Decision -eq 'awaiting-user') {
        $labels = New-T15bAnchorLabelSet -Anchor $Snapshot.primaryAnchor -Mode 'awaiting-user'
        $items += New-T15bQueueItem -Action 'set-labels' `
            -Target ([pscustomobject]@{ repo = $Snapshot.primaryAnchor.repo; issue = [int]$Snapshot.primaryAnchor.issue }) `
            -Payload ([pscustomobject]@{ labels = @($labels) }) -Source $Snapshot.workId
        return ,@($items)
    }
    if ($Decision.Decision -ne 'complete') { return ,@() }

    $milestoneCheck = Test-T15bMilestoneConventions -Snapshot $Snapshot
    if (-not $milestoneCheck.Satisfied) { throw "milestone 慣例檢查失敗，拒絕批次收尾：$($milestoneCheck.Detail)" }

    $labels = New-T15bAnchorLabelSet -Anchor $Snapshot.primaryAnchor -Mode 'complete'
    $items += New-T15bQueueItem -Action 'set-labels' `
        -Target ([pscustomobject]@{ repo = $Snapshot.primaryAnchor.repo; issue = [int]$Snapshot.primaryAnchor.issue }) `
        -Payload ([pscustomobject]@{ labels = @($labels) }) -Source $Snapshot.workId
    $items += New-T15bQueueItem -Action 'close-issue' `
        -Target ([pscustomobject]@{ repo = $Snapshot.primaryAnchor.repo; issue = [int]$Snapshot.primaryAnchor.issue }) `
        -Payload ([pscustomobject]@{ state = 'closed'; state_reason = 'completed' }) -Source $Snapshot.workId

    $participantsRaw = Get-T15bPropertyValue -Object $Snapshot -Name 'participatingRepos' -DefaultValue $null
    $participants = ConvertTo-T15bArray -Value $participantsRaw
    $participants = @($participants)
    foreach ($participant in $participants) {
        # T-21 尚無關 milestone 型別；本票依 T-12/T-22 先例最小擴充 close-milestone，四欄骨架不變。
        $items += New-T15bQueueItem -Action 'close-milestone' `
            -Target ([pscustomobject]@{ repo = $participant.repo; milestone = [int]$participant.milestone.number }) `
            -Payload ([pscustomobject]@{ state = 'closed' }) -Source $Snapshot.workId
    }
    return ,@($items)
}

function Test-T15bQueueItemSchema {
    param([Parameter(Mandatory)]$Item)
    $actual = @($Item.PSObject.Properties.Name)
    $required = @('action', 'target', 'payload', 'source')
    $outerOk = ($actual.Count -eq 4) -and (@(Compare-Object ($actual | Sort-Object) ($required | Sort-Object)).Count -eq 0)
    if (-not $outerOk) { return [pscustomobject]@{ Valid = $false; Detail = "外層必須恰四欄 action/target/payload/source；實得 [$($actual -join ', ')]" } }
    switch ($Item.action) {
        'set-labels' {
            $valid = ($Item.target.PSObject.Properties.Name -contains 'repo') -and ($Item.target.PSObject.Properties.Name -contains 'issue') -and ($Item.payload.PSObject.Properties.Name -contains 'labels')
        }
        'close-issue' {
            $valid = ($Item.target.PSObject.Properties.Name -contains 'repo') -and ($Item.target.PSObject.Properties.Name -contains 'issue') -and ($Item.payload.state -in @('open', 'closed'))
        }
        'close-milestone' {
            $valid = ($Item.target.PSObject.Properties.Name -contains 'repo') -and ($Item.target.PSObject.Properties.Name -contains 'milestone') -and ($Item.payload.state -eq 'closed')
        }
        default { $valid = $false }
    }
    return [pscustomobject]@{ Valid = $valid; Detail = if ($valid) { "四欄 schema 合格：$($Item.action)" } else { "動作專屬 schema 不合格：$($Item.action)" } }
}

function Add-T15bQueueItemsIfAbsent {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyCollection()][array]$Items)
    $newItems = @($Items)
    foreach ($item in $newItems) {
        $schema = Test-T15bQueueItemSchema -Item $item
        if (-not $schema.Valid) { throw $schema.Detail }
    }
    $existingRaw = Read-QueueFile -QueuePath $Path
    # 🚫 不可用 `$existing = if (...) { @() } else { ... }`：空陣列經 if 表達式的輸出
    # 管線會解卷成 $null，StrictMode 下讀 .Count 立即失敗。分支內直接賦值才保得住 0 筆陣列。
    if ($null -eq $existingRaw) { $existing = @() } else { $existing = @($existingRaw) }
    $output = @($existing)
    $added = 0
    foreach ($item in $newItems) {
        $targetJson = $item.target | ConvertTo-Json -Compress
        $payloadJson = $item.payload | ConvertTo-Json -Compress -Depth 10
        $dupes = @($output | Where-Object {
            $_.action -eq $item.action -and $_.source -eq $item.source -and
            (($_.target | ConvertTo-Json -Compress) -eq $targetJson) -and
            (($_.payload | ConvertTo-Json -Compress -Depth 10) -eq $payloadJson)
        })
        if ($dupes.Count -eq 0) { $output += $item; $added++ }
    }
    if ($newItems.Count -gt 0) { Write-QueueFile -QueuePath $Path -Items @($output) }
    return [pscustomobject]@{ Added = $added; Existing = $existing.Count; Total = $output.Count }
}

function Invoke-T15bCli {
    if ([string]::IsNullOrWhiteSpace($T15bSnapshotPath)) { throw '直接執行模式須提供 -SnapshotPath' }
    if ($T15bSkipHumanClosureCheck) {
        Write-Warning '⚠️⚠️⚠️ -SkipHumanClosureCheck 已開啟：僅供紅燈驗證，正式流程絕對禁用。'
    }
    $snapshot = Read-T15bWorkSnapshot -Path $T15bSnapshotPath
    $decision = Invoke-T15bCompletionDecision -Snapshot $snapshot -SkipHumanClosureCheck:$T15bSkipHumanClosureCheck
    $items = New-T15bCompletionQueueItems -Snapshot $snapshot -Decision $decision
    $items = @($items)
    $queueResult = Add-T15bQueueItemsIfAbsent -Path $T15bQueuePath -Items $items

    $lines = @(
        "work-complete 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
        "WorkId=$($snapshot.workId)  Anchor=$($snapshot.primaryAnchor.repo)#$($snapshot.primaryAnchor.issue)",
        "完成態判定：$($decision.Decision)",
        "票數=$($decision.TicketCount) open=$($decision.OpenCount) 最小站公式適用=$($decision.MinimumStationApplicable)",
        $decision.Detail,
        "本輪佇列項=$($items.Count) 新增=$($queueResult.Added) 佇列總數=$($queueResult.Total)"
    )
    foreach ($check in @($decision.ClosureChecks)) { $lines += "關票歸因：$($check.Detail)" }
    foreach ($item in $items) { $lines += "QUEUE $($item.action) $($item.target.repo) source=$($item.source)" }
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path $T15bReportPath -Content ($lines -join [Environment]::NewLine)
}

if (-not $T15bFunctionsOnly) { Invoke-T15bCli }
