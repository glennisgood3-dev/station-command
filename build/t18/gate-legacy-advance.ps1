#requires -Version 5.1
<#
.SYNOPSIS
    T-18：badge 生命週期——`sc:legacy` 摘除邏輯。通過第一個 native gate（即本檔產生的推進成功）
    後由 gate 摘除（Spec §7.4）。本檔是 `../t10/gate-advance.ps1` 的 legacy 感知版本，🚫 不修改
    t10 任何檔案（file ownership）。

.DESCRIPTION
    為何不能直接沿用 `../t10/gate-advance.ps1` 完成這件事（誠實聲明，非重工）：
      該檔 `New-StationAdvanceLabelSet` 只移除 `^sc:station-` 開頭的 label，`sc:legacy` 不符合
      這個 pattern，會被原樣保留進「完整集合」——也就是說，若沿用 t10 既有的推進器，legacy 工作
      每次推進都會一直帶著 `sc:legacy`，永遠不會消失，直接違反 Spec §7.4「通過第一個 native gate
      後由 gate 摘除」。要修掉這件事，唯一合法選項是「另立一個會多摘 sc:legacy 的推進器」，而不是
      去改 t10 的 `New-StationAdvanceLabelSet`（那是 t10 file ownership，且會影響所有 native 工作
      ——native 工作本來就不該有 sc:legacy，改了也沒意義，純粹是本票範圍該加的邏輯放錯地方）。

    地基重用：dot-source ../t10/gate-check.ps1 -FunctionsOnly（無 Mandatory 參數，dot-source
    安全，不會覆蓋本檔參數）取得 Invoke-GateCheck（站序合法性＋§6 出口條件，與 native 推進共用
    同一份判定，不另立第二套）、Get-CurrentStation、$Script:StationOrder。

    「badge 生命週期」策略：**每次成功推進都嘗試摘除 sc:legacy**（若不存在則此步驟為 no-op）。
    這等價於「通過第一個 native gate 後摘除」——因為摘除後不會再被重新加回（native 推進器與本檔
    皆不會主動加 sc:legacy，只有 legacy-intake.ps1 Stage C 會加，且只在初始化當下加一次），故
    「每次都摘」與「只在第一次摘」對最終狀態完全等價，且更簡單、不需要額外記錄「是否已經是第一次」
    這種本應避免的自建簿記（§3.4「不建立任何自建簿記作為判準」）。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程。
#>

[CmdletBinding()]
param(
    [string]$WorkId,
    [string]$PrimaryRepo,
    [int]$AnchorIssue,
    [string]$TargetStation,
    [string[]]$ParticipatingRepos = @(),
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$ChecklistOverridesPath = '',
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'

# 獨有命名（本檔與 legacy-intake.ps1 可能在同一次離線測試 session 內先後被 dot-source，
# 兩檔各自的「自存參數」變數名須互不相同，否則會重演 t13 README 記載的同型 $ScriptDir 覆蓋事故）。
$T18AdvDir                  = $PSScriptRoot
$T18AdvWorkId                = $WorkId
$T18AdvPrimaryRepo           = $PrimaryRepo
$T18AdvAnchorIssue           = $AnchorIssue
$T18AdvTargetStation         = $TargetStation
$T18AdvParticipatingRepos    = @($ParticipatingRepos)
$T18AdvPatPath                = $PatPath
$T18AdvChecklistOverridesPath = $ChecklistOverridesPath
$T18AdvQueuePath              = $QueuePath
$T18AdvFunctionsOnlyFlag      = [bool]$FunctionsOnly

Write-Host "[T18-SMOKE] gate-legacy-advance 已收參數：WorkId='$T18AdvWorkId' Anchor='$T18AdvPrimaryRepo#$T18AdvAnchorIssue' Target='$T18AdvTargetStation'"

$T18AdvGateCheckPath = Join-Path $T18AdvDir '..\t10\gate-check.ps1'
if (-not (Test-Path -LiteralPath $T18AdvGateCheckPath)) {
    throw ("找不到 T-10 地基：{0}。請確認 t18 與 t10 為同層兄弟目錄。" -f $T18AdvGateCheckPath)
}
. $T18AdvGateCheckPath -FunctionsOnly
Set-ConsoleUtf8

Write-Host "[T18-SMOKE] dot-source 完成後 `$T18AdvWorkId 仍為 '$T18AdvWorkId'（t10/gate-check.ps1 無 Mandatory 參數，理論風險低，仍依票面規範保留 `$T18Adv* 隔離命名）"

# ============================================================
# badge 狀態查詢（供三階段測試與人讀報告使用）
# ============================================================
function Get-LegacyBadgeStatus {
    param([Parameter(Mandatory)]$AnchorIssue)
    # ⚠️ 陷阱③：不可直接 @(ConvertTo-SafeArray ...)——先賦值，再對已賦值變數包 @()。
    $labelsRaw = ConvertTo-SafeArray -RawValue $AnchorIssue.labels
    $labelsRaw = @($labelsRaw)
    $names = @($labelsRaw | ForEach-Object { $_.name })
    $has = ($names -contains 'sc:legacy')
    return [pscustomobject]@{
        HasLegacyBadge = $has
        Detail          = if ($has) { 'anchor 現有 sc:legacy（收編中，尚未通過第一個 native gate）' } else { 'anchor 無 sc:legacy（已通過第一個 native gate 摘除，或本非 legacy work）' }
    }
}

# ============================================================
# 🔴 badge 摘除核心：完整集合＝現有非站別非legacy的label ＋ 目標站別（單一次寫入，§3.4 原子性）
# ============================================================
function New-LegacyAdvanceLabelSet {
    param([Parameter(Mandatory)]$AnchorIssue, [Parameter(Mandatory)][string]$TargetStation)
    # ⚠️ 陷阱③：不可直接 @(ConvertTo-SafeArray ...)——先賦值，再對已賦值變數包 @()。
    $labelsRaw = ConvertTo-SafeArray -RawValue $AnchorIssue.labels
    $labelsRaw = @($labelsRaw)
    $existingNames = @($labelsRaw | ForEach-Object { $_.name })
    $hadLegacy = ($existingNames -contains 'sc:legacy')
    $kept = @($existingNames | Where-Object { ($_ -notmatch '^sc:station-') -and ($_ -ne 'sc:legacy') })
    $desired = @($kept + @($TargetStation) | Select-Object -Unique)
    $detail = if ($hadLegacy) {
        "sc:legacy 已摘除（本次推進即『通過第一個 native gate』，Spec §7.4）"
    } else {
        "本次推進前 anchor 無 sc:legacy，無需摘除（非 legacy work，或先前已摘除——摘除後不會被重新加回，見檔頭說明）"
    }
    return [pscustomobject]@{ Labels = @($desired); BadgeRemoved = $hadLegacy; Detail = $detail }
}

function Add-LegacyAdvanceQueueItemIfAbsent {
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
# 產生模式：站序＋§6 出口條件全過（重用 t10 Invoke-GateCheck）⇒ 產生單一 set-labels 佇列項
# （與 badge 摘除是同一次動作，非兩次寫入——符合 §3.4「一次寫完整集合」不變式）
# ============================================================
function Invoke-LegacyGateAdvanceProduce {
    param(
        [Parameter(Mandatory)]$AnchorIssue,
        [Parameter(Mandatory)][string]$TargetStation,
        [array]$Tickets = @(),
        [hashtable]$ChecklistOverrides = @{},
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$QueuePath
    )
    $gc = Invoke-GateCheck -AnchorIssue $AnchorIssue -TargetStation $TargetStation -Tickets $Tickets -ChecklistOverrides $ChecklistOverrides
    if (-not $gc.OverallPass) {
        return [pscustomobject]@{ OverallPass = $false; GateCheck = $gc; Detail = "站序或 §6 出口條件未過（重用 T-10 Invoke-GateCheck，與 native 推進共用同一份判定）：$($gc.Detail)" }
    }
    $badgeBefore = Get-LegacyBadgeStatus -AnchorIssue $AnchorIssue
    $labelSet = New-LegacyAdvanceLabelSet -AnchorIssue $AnchorIssue -TargetStation $TargetStation
    $item = [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $Repo; issue = [int]$AnchorIssue.number }
        payload = [pscustomobject]@{ labels = @($labelSet.Labels) }
        source  = $Source
    }
    $add = Add-LegacyAdvanceQueueItemIfAbsent -QueuePath $QueuePath -Item $item
    return [pscustomobject]@{
        OverallPass = $true; GateCheck = $gc; BadgeBefore = $badgeBefore; LabelSet = $labelSet; QueueAdd = $add
        Detail = "推進通過；$($labelSet.Detail)；$($add.Detail)"
    }
}

function Invoke-LegacyGateAdvanceCli {
    if (-not $T18AdvWorkId -or -not $T18AdvPrimaryRepo -or -not $T18AdvAnchorIssue -or -not $T18AdvTargetStation) {
        throw '直接執行模式須提供 -WorkId -PrimaryRepo -AnchorIssue -TargetStation（或改用 -FunctionsOnly 供測試 dot-source）'
    }
    $token = Read-PatToken -PatPath $T18AdvPatPath
    $headers = Get-GithubHeaders -Token $token -UserAgent 'station-command-t18-gate-legacy-advance'
    $r = Split-RepoString -RepoString $T18AdvPrimaryRepo
    $anchor = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $T18AdvAnchorIssue -Headers $headers
    if ($null -eq $anchor) { throw "找不到 anchor：$T18AdvPrimaryRepo#$T18AdvAnchorIssue" }

    $participating = if (@($T18AdvParticipatingRepos).Count -gt 0) { @($T18AdvParticipatingRepos) } else { @($T18AdvPrimaryRepo) }
    $tickets = Get-TicketsForWork -WorkId $T18AdvWorkId -ParticipatingRepos $participating -Headers $headers

    $overrides = @{}
    if ($T18AdvChecklistOverridesPath -and (Test-Path -LiteralPath $T18AdvChecklistOverridesPath)) {
        $raw = Get-Content -LiteralPath $T18AdvChecklistOverridesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $raw.PSObject.Properties) { $overrides[$p.Name] = $p.Value }
    }

    $result = Invoke-LegacyGateAdvanceProduce -AnchorIssue $anchor -TargetStation $T18AdvTargetStation -Tickets $tickets `
        -ChecklistOverrides $overrides -Repo $T18AdvPrimaryRepo -Source $T18AdvWorkId -QueuePath $T18AdvQueuePath

    $lines = @("gate-legacy-advance 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "WorkId=$T18AdvWorkId  Anchor=$T18AdvPrimaryRepo#$T18AdvAnchorIssue  Target=$T18AdvTargetStation", "")
    $lines += "整體判定：$(if ($result.OverallPass) { 'PASS' } else { 'FAIL' }) — $($result.Detail)"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T18AdvDir 'gate-legacy-advance-report.txt') -Content ($lines -join [Environment]::NewLine)

    if ($result.OverallPass) { exit 0 } else { exit 1 }
}

if (-not $T18AdvFunctionsOnlyFlag) {
    Invoke-LegacyGateAdvanceCli
}
