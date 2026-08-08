#requires -Version 5.1
<#
.SYNOPSIS
    T-10：gate 復位模式（Spec §3.4）——兩分支：回退至最後合法事件站別／無合法事件則落 sc:awaiting-user。

.DESCRIPTION
    🔴 deferred-to-CI（依 ADR-NP-009／驗收 #7）：本檔的「合法性」判準依賴 gate 執行身分
    ≠ 使用者互動帳號（-GateIdentityLogins，例如 CI 階段的 github-actions[bot]）。手動階段這個
    前提不成立（actor 恆等於使用者本人，見 SC-DEC-BOT-001），機器層無法區分「人手改」與「gate 改」，
    §3.4 本節在手動階段整段不生效。**本檔仍完整實作程式路徑並以離線 mock 測試涵蓋兩分支**——
    差別只在「動態驗收延後至 CI 階段」，不是「未實作」。詳見 gate-reset.md。

    設計沿用 T-08／T-21 慣例：本檔只**產生**單一 set-labels 佇列項，不直接寫 GitHub；
    落地仍交給 ../t21/apply-queue.ps1（DRY）。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程。
#>

[CmdletBinding()]
param(
    [string]$WorkId,
    [string]$PrimaryRepo,
    [int]$AnchorIssue,
    [string[]]$GateIdentityLogins = @(),
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$GateCheckPath = Join-Path $ScriptDir 'gate-check.ps1'
if (-not (Test-Path -LiteralPath $GateCheckPath)) { throw "找不到 gate-check.ps1：$GateCheckPath" }
. $GateCheckPath -FunctionsOnly
Set-ConsoleUtf8

# ============================================================
# 讀 primary anchor 的 issue timeline（原生記錄，§3.4「不採信當前 label 值，只讀 timeline」）
# ============================================================
function Get-IssueTimelineEvents {
    param([Parameter(Mandatory)][string]$Owner, [Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][int]$IssueNumber,
          [Parameter(Mandatory)][hashtable]$Headers, [int]$MaxPages = 5)
    $all = @()
    for ($page = 1; $page -le $MaxPages; $page++) {
        $url = "https://api.github.com/repos/$Owner/$Repo/issues/$IssueNumber/timeline?per_page=100&page=$page"
        $raw = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
        $chunk = ConvertTo-SafeArray -RawValue $raw
        $chunk = @($chunk)
        $all += $chunk
        if ($chunk.Count -lt 100) { break }
    }
    return ,@($all)
}

# ============================================================
# 在 timeline 中找「最後一次合法」的站別 labeled 事件（actor ∈ GateIdentityLogins）
# timeline API 回傳本就依時間正序排列；由尾端往前找第一個符合者＝時間上最後一筆合法事件。
# ============================================================
function Find-LastLegalStationEvent {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$TimelineEvents, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$GateIdentityLogins)
    $events = @($TimelineEvents)
    $stationLabeled = @($events | Where-Object {
        $_.event -eq 'labeled' -and
        $_.PSObject.Properties.Name -contains 'label' -and $null -ne $_.label -and
        ($_.label.name -match '^sc:station-')
    })
    if ($stationLabeled.Count -eq 0) {
        return [pscustomobject]@{ Found = $false; Station = $null; Actor = $null; CreatedAt = $null; Detail = 'timeline 中無任何 sc:station-* 的 labeled 事件' }
    }
    for ($i = $stationLabeled.Count - 1; $i -ge 0; $i--) {
        $ev = $stationLabeled[$i]
        $actorLogin = if ($ev.PSObject.Properties.Name -contains 'actor' -and $null -ne $ev.actor) { $ev.actor.login } else { $null }
        if ($null -ne $actorLogin -and ($GateIdentityLogins -contains $actorLogin)) {
            return [pscustomobject]@{ Found = $true; Station = $ev.label.name; Actor = $actorLogin; CreatedAt = $ev.created_at; Detail = "命中合法事件：station='$($ev.label.name)'，actor='$actorLogin'，時間='$($ev.created_at)'" }
        }
    }
    $actorsSeen = @($stationLabeled | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'actor' -and $null -ne $_.actor) { $_.actor.login } else { '(無 actor)' } } | Select-Object -Unique)
    return [pscustomobject]@{ Found = $false; Station = $null; Actor = $null; CreatedAt = $null; Detail = "timeline 中有 $($stationLabeled.Count) 筆 sc:station-* labeled 事件，但無一筆 actor 屬於 gate 身分集合（實際 actor：$($actorsSeen -join '、')；gate 身分集合：$($GateIdentityLogins -join '、')）" }
}

# ============================================================
# 復位模式主邏輯：兩分支，回傳單一 set-labels 佇列項（§3.4 原子性）
# ============================================================
function Invoke-GateReset {
    param(
        [Parameter(Mandatory)]$AnchorIssue,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$TimelineEvents,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$GateIdentityLogins,
        [Parameter(Mandatory)][string]$Repo
    )
    $legal = Find-LastLegalStationEvent -TimelineEvents $TimelineEvents -GateIdentityLogins $GateIdentityLogins

    $labelsRaw = ConvertTo-SafeArray -RawValue $AnchorIssue.labels
    $labelsRaw = @($labelsRaw)
    $existingNames = @($labelsRaw | ForEach-Object { $_.name })
    $nonStation = @($existingNames | Where-Object { $_ -notmatch '^sc:station-' })

    if ($legal.Found) {
        $desired = @($nonStation + @($legal.Station) | Select-Object -Unique)
        $reason = "① 沿 timeline 回溯，回退至最後一次合法事件所設站別：$($legal.Station)（事件時間：$($legal.CreatedAt)，actor='$($legal.Actor)'）"
        $item = [pscustomobject]@{
            action  = 'set-labels'
            target  = [pscustomobject]@{ repo = $Repo; issue = $AnchorIssue.number }
            payload = [pscustomobject]@{ labels = @($desired) }
            source  = "gate-reset"
        }
        return [pscustomobject]@{ Branch = 'legal-found'; TargetStation = $legal.Station; Reason = $reason; QueueItem = $item; Detail = $legal.Detail }
    } else {
        $desired = @($nonStation + @('sc:awaiting-user') | Select-Object -Unique)
        $reason = "② 整條 timeline 無任何合法事件 ⇒ 落 sc:awaiting-user、停止推進、交使用者裁示。$($legal.Detail)"
        $item = [pscustomobject]@{
            action  = 'set-labels'
            target  = [pscustomobject]@{ repo = $Repo; issue = $AnchorIssue.number }
            payload = [pscustomobject]@{ labels = @($desired) }
            source  = "gate-reset"
        }
        return [pscustomobject]@{ Branch = 'no-legal-event'; TargetStation = 'sc:awaiting-user'; Reason = $reason; QueueItem = $item; Detail = $legal.Detail }
    }
}

# ============================================================
# 佇列項冪等追加（同 gate-advance.ps1 模式）
# ============================================================
function Add-QueueItemIfAbsent {
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

# ============================================================
# CLI 主流程
# ============================================================
function Invoke-GateResetCli {
    if (@($GateIdentityLogins).Count -eq 0) {
        Write-Host "🔴 deferred-to-CI：未提供 -GateIdentityLogins，手動階段依 ADR-NP-009 無法成立機器歸因判準，本次不執行復位（程式路徑已就緒，待 CI 階段提供 github-actions[bot] 等身分後生效）。"
        exit 3
    }
    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t10-gate-reset'
    $r = Split-RepoString -RepoString $PrimaryRepo
    $anchor = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $AnchorIssue -Headers $Headers
    if ($null -eq $anchor) { throw "找不到 anchor：$PrimaryRepo#$AnchorIssue" }

    $timeline = Get-IssueTimelineEvents -Owner $r.Owner -Repo $r.Repo -IssueNumber $AnchorIssue -Headers $Headers
    $result = Invoke-GateReset -AnchorIssue $anchor -TimelineEvents $timeline -GateIdentityLogins $GateIdentityLogins -Repo $PrimaryRepo

    $lines = @("gate-reset 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "WorkId=$WorkId  Anchor=$PrimaryRepo#$AnchorIssue", "")
    $lines += "分支：$($result.Branch)"
    $lines += $result.Reason
    $addResult = Add-QueueItemIfAbsent -QueuePath $QueuePath -Item $result.QueueItem
    $lines += "已產生單一次 set-labels 佇列項（$($addResult.Detail)）：labels=[$($result.QueueItem.payload.labels -join ', ')]"
    $lines += "=> 請執行 ..\t21\apply-queue.ps1 -QueuePath `"$QueuePath`" 落地。"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $ScriptDir 'gate-reset-report.txt') -Content ($lines -join [Environment]::NewLine)
    exit 0
}

if (-not $FunctionsOnly) {
    Invoke-GateResetCli
}
