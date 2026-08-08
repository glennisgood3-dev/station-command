#requires -Version 5.1
<#
.SYNOPSIS
    依 DECISIONS.md 裁示建立站 5 三路 dispatch 計畫，並執行 A 軸外廠呼叫或具名降級。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Ticket,
    [Parameter(Mandatory = $true)][string]$DecisionsPath,
    [Parameter(Mandatory = $true)][string]$DiffPath,
    [Parameter(Mandatory = $true)][string]$SpecPath,
    [Parameter(Mandatory = $true)][string]$ConnectionFolder,
    [string[]]$StandardsRefs = @('該 repo 無落檔規範，本輪僅以基線審'),
    [string]$SmellBaselinePath = (Join-Path $PSScriptRoot '..\station-command\assets\fowler-smells.md'),
    [string]$RegistryPath = (Join-Path $PSScriptRoot '..\station-command\assets\vendor-registry.md'),
    [string]$OutputDir = (Join-Path $PSScriptRoot 'evidence'),
    [ValidateRange(1, 300)][int]$TimeoutSec = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：dot-source 前保存所有本入口參數，避免下游同名參數 cascade 覆寫。
$T30RunTicket = $Ticket
$T30RunDecisionsPath = $DecisionsPath
$T30RunDiffPath = $DiffPath
$T30RunSpecPath = $SpecPath
$T30RunConnectionFolder = $ConnectionFolder
$T30RunStandardsRefs = @($StandardsRefs)
$T30RunSmellBaselinePath = $SmellBaselinePath
$T30RunRegistryPath = $RegistryPath
$T30RunOutputDir = $OutputDir
$T30RunTimeoutSec = $TimeoutSec
$T30RunDir = $PSScriptRoot
. (Join-Path $T30RunDir 't30-core.ps1') -FunctionsOnly

foreach ($requiredPath in @($T30RunDiffPath, $T30RunSpecPath, $T30RunSmellBaselinePath, $T30RunRegistryPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "找不到必要輸入檔：$requiredPath" }
}
if (-not (Test-Path -LiteralPath $T30RunOutputDir -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $T30RunOutputDir -Force)
}

$decision = Read-T30UpgradeDecision -DecisionsPath $T30RunDecisionsPath -Ticket $T30RunTicket
$diffText = [IO.File]::ReadAllText($T30RunDiffPath)
$specText = [IO.File]::ReadAllText($T30RunSpecPath)
$smellText = [IO.File]::ReadAllText($T30RunSmellBaselinePath)
$plan = New-T30DispatchPlan -Ticket $T30RunTicket -Decision $decision -DiffText $diffText -StandardsRefs $T30RunStandardsRefs -SmellBaselineText $smellText -SpecText $specText

$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText((Join-Path $T30RunOutputDir 'axis-a-claude-prompt.txt'), $plan.axisA.claude.prompt, $utf8Bom)
[IO.File]::WriteAllText((Join-Path $T30RunOutputDir 'axis-a-external-prompt.txt'), $plan.axisA.external.prompt, $utf8Bom)
[IO.File]::WriteAllText((Join-Path $T30RunOutputDir 'axis-b-claude-prompt.txt'), $plan.axisB.prompt, $utf8Bom)
[IO.File]::WriteAllText((Join-Path $T30RunOutputDir 'axis-a-claude-input-list.json'), ($plan.axisA.claude.inputList | ConvertTo-Json -Depth 10), $utf8Bom)
[IO.File]::WriteAllText((Join-Path $T30RunOutputDir 'axis-a-external-input-list.json'), ($plan.axisA.external.inputList | ConvertTo-Json -Depth 10), $utf8Bom)

$dispatch = Invoke-T30ExternalAxisA -DispatchPlan $plan -ConnectionFolder $T30RunConnectionFolder -RegistryPath $T30RunRegistryPath -TimeoutSec $T30RunTimeoutSec
$dispatchJson = $dispatch | ConvertTo-Json -Depth 30
[IO.File]::WriteAllText((Join-Path $T30RunOutputDir 'dispatch-result.json'), $dispatchJson, $utf8Bom)

Write-Output "T-30 dispatch：ticket=$T30RunTicket；decision=$($decision.DecisionId)；A 軸=Claude+$($decision.Provider)；B 軸=Claude"
if ($dispatch.externalExecuted) {
    Write-Output "外廠 A 軸已執行：provider=$($decision.Provider)；model=$($decision.Model)"
}
else {
    Write-Output "外廠不可用，已降級：provider=$($dispatch.degradation.provider)；失敗原因=$($dispatch.degradation.'失敗原因')；承接者=$($dispatch.degradation.'承接者')；gate 不阻塞=$($dispatch.gateMayProceed)"
}
