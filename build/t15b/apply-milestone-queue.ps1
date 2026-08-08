#requires -Version 5.1
<#
.SYNOPSIS
    T-15b：套用 close-milestone 佇列項；其餘型別原樣保留。

.DESCRIPTION
    本檔是 T-21 套用器的最小擴充，只消費 close-milestone。每筆先 GET 現況做冪等判定，
    未達成才 PATCH state=closed，之後再 GET 回驗；失敗或回驗不符皆留在原佇列。
    產生端仍是 /station-gate；本套用器不自行創造任何 GitHub 動作。
#>

[CmdletBinding()]
param(
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [string]$ReportPath = (Join-Path $PSScriptRoot 'apply-milestone-queue-report.txt'),
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# dot-source 前保存每一個 CLI 參數，避免 T-21 同名 param cascade 覆蓋。
$T15bApplyPatPath = $PatPath
$T15bApplyQueuePath = $QueuePath
$T15bApplyReportPath = $ReportPath
$T15bApplyFunctionsOnly = $FunctionsOnly.IsPresent
$T15bApplyRoot = $PSScriptRoot

$T15bApplyQueueCommonPath = Join-Path $T15bApplyRoot '..\t21\queue-common.ps1'
if (-not (Test-Path -LiteralPath $T15bApplyQueueCommonPath)) { throw "找不到 T-21 佇列地基：$T15bApplyQueueCommonPath" }
. $T15bApplyQueueCommonPath
Set-ConsoleUtf8

function Test-T15bCloseMilestoneItemSchema {
    param([Parameter(Mandatory)]$Item)
    $outer = @($Item.PSObject.Properties.Name)
    $required = @('action', 'target', 'payload', 'source')
    if ($outer.Count -ne 4 -or @(Compare-Object ($outer | Sort-Object) ($required | Sort-Object)).Count -ne 0) {
        return [pscustomobject]@{ Valid = $false; Detail = "外層不是恰四欄：[$($outer -join ', ')]" }
    }
    if ($Item.action -ne 'close-milestone') { return [pscustomobject]@{ Valid = $false; Detail = "action 不是 close-milestone：$($Item.action)" } }
    $targetNames = @($Item.target.PSObject.Properties.Name)
    $payloadNames = @($Item.payload.PSObject.Properties.Name)
    $valid = ($targetNames.Count -eq 2) -and ($targetNames -contains 'repo') -and ($targetNames -contains 'milestone') -and
        ($payloadNames.Count -eq 1) -and ($payloadNames -contains 'state') -and ($Item.payload.state -eq 'closed') -and
        (-not [string]::IsNullOrWhiteSpace([string]$Item.target.repo)) -and ([int]$Item.target.milestone -gt 0) -and
        (-not [string]::IsNullOrWhiteSpace([string]$Item.source))
    return [pscustomobject]@{ Valid = $valid; Detail = if ($valid) { 'close-milestone schema 合格' } else { 'close-milestone target/payload/source schema 不合格' } }
}

function Get-T15bCurrentMilestone {
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$MilestoneNumber,
        [Parameter(Mandatory)][hashtable]$Headers
    )
    $uri = "https://api.github.com/repos/$Owner/$Repo/milestones/$MilestoneNumber"
    try { return Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get }
    catch {
        $response = $_.Exception.Response
        if ($response -and $response.StatusCode.value__ -eq 404) { return $null }
        throw
    }
}

function Test-T15bCloseMilestoneSatisfied {
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)][hashtable]$Headers)
    $repo = Split-RepoString -RepoString $Item.target.repo
    $current = Get-T15bCurrentMilestone -Owner $repo.Owner -Repo $repo.Repo -MilestoneNumber ([int]$Item.target.milestone) -Headers $Headers
    if ($null -eq $current) { return [pscustomobject]@{ Satisfied = $false; Detail = '目標 milestone 不存在' } }
    $ok = ($current.state -eq 'closed')
    return [pscustomobject]@{ Satisfied = $ok; Detail = "milestone 現況 state='$($current.state)'，期望 'closed'" }
}

function Invoke-T15bCloseMilestoneWrite {
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)][hashtable]$Headers)
    $repo = Split-RepoString -RepoString $Item.target.repo
    $uri = "https://api.github.com/repos/$($repo.Owner)/$($repo.Repo)/milestones/$($Item.target.milestone)"
    $body = @{ state = 'closed' } | ConvertTo-Json -Compress
    [void](Invoke-RestMethod -Uri $uri -Headers $Headers -Method Patch -Body $body -ContentType 'application/json')
}

function Invoke-T15bApplyMilestoneQueueCli {
    $token = Read-PatToken -PatPath $T15bApplyPatPath
    $headers = Get-GithubHeaders -Token $token -UserAgent 'station-command-t15b-milestone-queue'
    $itemsRaw = Read-QueueFile -QueuePath $T15bApplyQueuePath
    $lines = @("apply-milestone-queue 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "佇列檔：$T15bApplyQueuePath", '')
    if ($null -eq $itemsRaw) {
        $lines += '待寫佇列不存在；合法降級，無事可做。'
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path $T15bApplyReportPath -Content ($lines -join [Environment]::NewLine)
        return
    }
    $items = @($itemsRaw)
    $remaining = New-Object System.Collections.ArrayList
    $handled = 0
    $failed = 0
    foreach ($item in $items) {
        if (-not ($item.PSObject.Properties.Name -contains 'action') -or $item.action -ne 'close-milestone') {
            [void]$remaining.Add($item)
            continue
        }
        $handled++
        $schema = Test-T15bCloseMilestoneItemSchema -Item $item
        if (-not $schema.Valid) {
            $lines += "[FAILED-SCHEMA] source=$($item.source) — $($schema.Detail)"
            [void]$remaining.Add($item)
            $failed++
            continue
        }
        try {
            $pre = Test-T15bCloseMilestoneSatisfied -Item $item -Headers $headers
            if ($pre.Satisfied) {
                $lines += "[SKIPPED-ALREADY-SATISFIED] $($item.target.repo) milestone#$($item.target.milestone)"
                continue
            }
            Invoke-T15bCloseMilestoneWrite -Item $item -Headers $headers
            $post = Test-T15bCloseMilestoneSatisfied -Item $item -Headers $headers
            if ($post.Satisfied) {
                $lines += "[APPLIED-VERIFIED] $($item.target.repo) milestone#$($item.target.milestone)"
            } else {
                $lines += "[FAILED-VERIFY] $($item.target.repo) milestone#$($item.target.milestone) — $($post.Detail)"
                [void]$remaining.Add($item)
                $failed++
            }
        } catch {
            $lines += "[FAILED-APPLY] $($item.target.repo) milestone#$($item.target.milestone) — $($_.Exception.Message)"
            [void]$remaining.Add($item)
            $failed++
        }
    }
    Write-QueueFile -QueuePath $T15bApplyQueuePath -Items @($remaining)
    $lines += "本輪辨識 close-milestone=$handled，失敗=$failed，佇列剩餘=$(@($remaining).Count)"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path $T15bApplyReportPath -Content ($lines -join [Environment]::NewLine)
    if ($failed -gt 0) { exit 1 }
}

if (-not $T15bApplyFunctionsOnly) { Invoke-T15bApplyMilestoneQueueCli }
