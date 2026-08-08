#requires -Version 5.1
<#
.SYNOPSIS
    T-10：推進器——全過時產生單一次「設定完整 label 集合」的佇列項；含寫後回驗設計（重試一次）。

.DESCRIPTION
    依 Spec §3.4「站別推進＝單一動作」與 §4.4「寫後回驗不經 search」實作。
    依 T-08 的既有設計選擇（同一理由）：本檔不直接寫 GitHub，只**產生** T-21 格式佇列項，
    真正落地仍由 ../t21/apply-queue.ps1 負責（DRY，不重寫寫入／冪等邏輯）。

    兩種模式：

    【模式一：產生（預設）】
      dot-source gate-check.ps1 → Invoke-GateCheck 全過 ⇒ 讀 anchor 現有完整 label 集合，
      移除所有 sc:station-* 後加入 TargetStation，組成**完整**集合，產生**單一筆** set-labels
      佇列項（🚫 不拆 remove+add 兩步）。未過 ⇒ 不產生任何佇列項，具名缺項（轉述 gate-check 結果）。

    【模式二：-VerifyAfterApply】
      使用者已跑過 apply-queue.ps1 落地後，Commander 用本模式確認「推進真的成功」：
      直接以 issues API 讀 anchor（不經 search）→ 比對是否恰為「單一個 TargetStation 站別 label」
      （§4.4：比對完整集合，不是單一 label 是否存在）→ 不符 ⇒ 等待後重試一次 → 仍不符 ⇒
      判寫入失敗、具名回報、🚫 不宣稱推進成功（不論 T-21 apply-queue-report.txt 怎麼寫，
      本檔自己的判定以本次直讀為準）。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程。
#>

[CmdletBinding(DefaultParameterSetName = 'Produce')]
param(
    [Parameter(ParameterSetName = 'Produce', Mandatory)]
    [Parameter(ParameterSetName = 'Verify', Mandatory)]
    [string]$WorkId,

    [Parameter(ParameterSetName = 'Produce', Mandatory)]
    [Parameter(ParameterSetName = 'Verify', Mandatory)]
    [string]$PrimaryRepo,

    [Parameter(ParameterSetName = 'Produce', Mandatory)]
    [Parameter(ParameterSetName = 'Verify', Mandatory)]
    [int]$AnchorIssue,

    [Parameter(ParameterSetName = 'Produce', Mandatory)]
    [Parameter(ParameterSetName = 'Verify', Mandatory)]
    [string]$TargetStation,

    [Parameter(ParameterSetName = 'Produce')]
    [string[]]$ParticipatingRepos = @(),

    [Parameter(ParameterSetName = 'Produce')]
    [string]$ChecklistOverridesPath = '',

    [Parameter(ParameterSetName = 'Produce')]
    [Parameter(ParameterSetName = 'Verify')]
    [string]$PatPath = 'G:\default mount\station_command-key',

    [Parameter(ParameterSetName = 'Produce')]
    [Parameter(ParameterSetName = 'Verify')]
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),

    [Parameter(ParameterSetName = 'Verify')]
    [switch]$VerifyAfterApply,

    [Parameter(ParameterSetName = 'Verify')]
    [int]$RetryDelaySeconds = 2,

    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$GateCheckPath = Join-Path $ScriptDir 'gate-check.ps1'
if (-not (Test-Path -LiteralPath $GateCheckPath)) { throw "找不到 gate-check.ps1：$GateCheckPath" }
. $GateCheckPath -FunctionsOnly
Set-ConsoleUtf8

# ============================================================
# 佇列項冪等追加（同 T-08 intake-native.ps1 的既有模式，本檔獨立一份，理由同 T-08 README：
# 產生權自查邏輯與去重邏輯屬各 skill 自己的產生階段責任，不下放共用檔改動既有 T-21/T-08 交付）
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
# 模式一：組出「完整 label 集合」的單一 set-labels 佇列項（§3.4 原子性核心）
# ============================================================
function New-StationAdvanceLabelSet {
    param([Parameter(Mandatory)]$AnchorIssue, [Parameter(Mandatory)][string]$TargetStation)
    $labelsRaw = ConvertTo-SafeArray -RawValue $AnchorIssue.labels
    $labelsRaw = @($labelsRaw)
    $existingNames = @($labelsRaw | ForEach-Object { $_.name })
    $nonStation = @($existingNames | Where-Object { $_ -notmatch '^sc:station-' })
    $desired = @($nonStation + @($TargetStation) | Select-Object -Unique)
    return ,$desired
}

function New-StationAdvanceQueueItem {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][int]$IssueNumber, [Parameter(Mandatory)][array]$DesiredLabels, [Parameter(Mandatory)][string]$Source)
    return [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $Repo; issue = $IssueNumber }
        payload = [pscustomobject]@{ labels = @($DesiredLabels) }
        source  = $Source
    }
}

# ============================================================
# 模式二：寫後回驗（issues API 直讀，不經 search；不符重試一次，仍不符判失敗）
# ============================================================
function Test-AdvanceVerified {
    param([Parameter(Mandatory)]$Issue, [Parameter(Mandatory)][string]$ExpectedStation)
    # rework（實跑抓到的 bug，已用 pwsh 7 實測確認並修正）：Get-StationLabelsOnIssue 內部用逗號運算子
    # `return ,$stationNames` 保護陣列型別跨函式邊界不被解卷；此處🚫不可直接 @(函式呼叫本身)——
    # 那樣會把「已保護好的陣列」再包一層，變成「1 元素陣列，該元素是原陣列」（雙站別情境下
    # Count 從 2 誤判成 1）。正確作法：先賦值（自動正確解卷），再對已賦值變數包 @()（同型註解
    # 見 ../t21/queue-common.ps1）。
    $stations = Get-StationLabelsOnIssue -Issue $Issue
    $stations = @($stations)
    $ok = ($stations.Count -eq 1) -and ($stations[0] -eq $ExpectedStation)
    $detail = if ($ok) {
        "anchor 現有站別 label 恰為 '$ExpectedStation'（無殘留舊站別、無雙站別中間態）"
    } else {
        "anchor 現有站別 label=[$($stations -join ', ')]（數量=$($stations.Count)），期望恰為單一 '$ExpectedStation'"
    }
    return [pscustomobject]@{ Satisfied = $ok; Detail = $detail }
}

function Invoke-VerifyAdvanceWithRetry {
    param(
        [Parameter(Mandatory)][string]$Owner, [Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$ExpectedStation, [Parameter(Mandatory)][hashtable]$Headers, [int]$RetryDelaySeconds = 2
    )
    $issue1 = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $IssueNumber -Headers $Headers
    if ($null -eq $issue1) {
        return [pscustomobject]@{ Satisfied = $false; Attempts = 1; Detail = "第一次直讀失敗：anchor 不存在（$Owner/$Repo#$IssueNumber）" }
    }
    $r1 = Test-AdvanceVerified -Issue $issue1 -ExpectedStation $ExpectedStation
    if ($r1.Satisfied) { return [pscustomobject]@{ Satisfied = $true; Attempts = 1; Detail = $r1.Detail } }

    Start-Sleep -Seconds $RetryDelaySeconds
    $issue2 = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $IssueNumber -Headers $Headers
    if ($null -eq $issue2) {
        return [pscustomobject]@{ Satisfied = $false; Attempts = 2; Detail = "重試後直讀失敗：anchor 不存在（$Owner/$Repo#$IssueNumber）。判寫入失敗，不宣稱推進成功。" }
    }
    $r2 = Test-AdvanceVerified -Issue $issue2 -ExpectedStation $ExpectedStation
    if ($r2.Satisfied) { return [pscustomobject]@{ Satisfied = $true; Attempts = 2; Detail = "首次不符，重試一次後相符：$($r2.Detail)" } }

    return [pscustomobject]@{ Satisfied = $false; Attempts = 2; Detail = "寫後回驗失敗（已重試一次仍不符）：$($r2.Detail)。判寫入失敗，具名回報，不宣稱推進成功。" }
}

# ============================================================
# CLI 主流程
# ============================================================
function Invoke-GateAdvanceProduce {
    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t10-gate-advance'

    $participating = if (@($ParticipatingRepos).Count -gt 0) { @($ParticipatingRepos) } else { @($PrimaryRepo) }
    $r = Split-RepoString -RepoString $PrimaryRepo
    $anchor = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $AnchorIssue -Headers $Headers
    if ($null -eq $anchor) { throw "找不到 anchor：$PrimaryRepo#$AnchorIssue" }

    $tickets = Get-TicketsForWork -WorkId $WorkId -ParticipatingRepos $participating -Headers $Headers

    $overrides = @{}
    if ($ChecklistOverridesPath -and (Test-Path -LiteralPath $ChecklistOverridesPath)) {
        $raw = Get-Content -LiteralPath $ChecklistOverridesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $raw.PSObject.Properties) { $overrides[$p.Name] = $p.Value }
    }

    $observedActor = $null
    try { $observedActor = (Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $Headers -Method Get).login } catch { }

    $gc = Invoke-GateCheck -AnchorIssue $anchor -TargetStation $TargetStation -Tickets $tickets -ChecklistOverrides $overrides -ObservedActorLogin $observedActor

    $lines = @("gate-advance（產生模式）執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "WorkId=$WorkId  Anchor=$PrimaryRepo#$AnchorIssue  Target=$TargetStation", "")
    $lines += "整體判定：$(if ($gc.OverallPass) { 'PASS' } else { 'FAIL' })（$($gc.Reason)）— $($gc.Detail)"

    if (-not $gc.OverallPass) {
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $ScriptDir 'gate-advance-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 1
    }

    $desired = New-StationAdvanceLabelSet -AnchorIssue $anchor -TargetStation $TargetStation
    $item = New-StationAdvanceQueueItem -Repo $PrimaryRepo -IssueNumber $AnchorIssue -DesiredLabels $desired -Source $WorkId
    $addResult = Add-QueueItemIfAbsent -QueuePath $QueuePath -Item $item

    $lines += "已產生單一次「設定完整 label 集合」佇列項（$($addResult.Detail)）：labels=[$($desired -join ', ')]"
    $lines += "=> 請執行 ..\t21\apply-queue.ps1 -QueuePath `"$QueuePath`" 落地；落地後可用 -VerifyAfterApply 模式確認寫後回驗。"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $ScriptDir 'gate-advance-report.txt') -Content ($lines -join [Environment]::NewLine)
    exit 0
}

function Invoke-GateAdvanceVerify {
    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t10-gate-advance-verify'
    $r = Split-RepoString -RepoString $PrimaryRepo
    $result = Invoke-VerifyAdvanceWithRetry -Owner $r.Owner -Repo $r.Repo -IssueNumber $AnchorIssue -ExpectedStation $TargetStation -Headers $Headers -RetryDelaySeconds $RetryDelaySeconds

    $lines = @("gate-advance（回驗模式）執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "WorkId=$WorkId  Anchor=$PrimaryRepo#$AnchorIssue  期望站別=$TargetStation  嘗試次數=$($result.Attempts)", "")
    $lines += "回驗判定：$(if ($result.Satisfied) { 'SATISFIED（推進成功）' } else { 'NOT-SATISFIED（推進失敗，不宣稱成功）' }) — $($result.Detail)"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $ScriptDir 'gate-advance-verify-report.txt') -Content ($lines -join [Environment]::NewLine)

    if ($result.Satisfied) { exit 0 } else { exit 1 }
}

if (-not $FunctionsOnly) {
    if ($PSCmdlet.ParameterSetName -eq 'Verify') { Invoke-GateAdvanceVerify } else { Invoke-GateAdvanceProduce }
}
