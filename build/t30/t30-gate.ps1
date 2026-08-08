#requires -Version 5.1
<#
.SYNOPSIS
    讀取兩份 A 軸廠別報告與 Claude B 軸報告，輸出並列結果及分歧裁示佇列項。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClaudeAxisAPath,
    [Parameter(Mandatory = $true)][string]$ExternalAxisAPath,
    [Parameter(Mandatory = $true)][string]$ClaudeAxisBPath,
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][int]$Issue,
    [Parameter(Mandatory = $true)][string]$Ticket,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'evidence\gate-result.json'),
    [string]$QueuePath = (Join-Path $PSScriptRoot 'evidence\dispute-queue-item.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：下游 dot-source 前使用 T30Gate 專屬名稱保存。
$T30GateClaudeAxisAPath = $ClaudeAxisAPath
$T30GateExternalAxisAPath = $ExternalAxisAPath
$T30GateClaudeAxisBPath = $ClaudeAxisBPath
$T30GateRepo = $Repo
$T30GateIssue = $Issue
$T30GateTicket = $Ticket
$T30GateOutputPath = $OutputPath
$T30GateQueuePath = $QueuePath
$T30GateDir = $PSScriptRoot
. (Join-Path $T30GateDir 't30-core.ps1') -FunctionsOnly

function Read-T30GateReportFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "找不到 review 報告：$Path" }
    $value = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    if (-not ($value.PSObject.Properties.Name -contains 'provider') -or -not ($value.PSObject.Properties.Name -contains 'findings')) {
        throw "review 報告缺 provider 或 findings：$Path"
    }
    return $value
}

$claudeA = Read-T30GateReportFile -Path $T30GateClaudeAxisAPath
$externalA = Read-T30GateReportFile -Path $T30GateExternalAxisAPath
$claudeB = Read-T30GateReportFile -Path $T30GateClaudeAxisBPath
$result = New-T30GateResult -ClaudeAxisAReport $claudeA -ExternalAxisAReport $externalA -ClaudeAxisBReport $claudeB
$queueItem = New-T30DisputeQueueItem -Repo $T30GateRepo -Issue $T30GateIssue -Ticket $T30GateTicket -GateResult $result

$utf8Bom = New-Object Text.UTF8Encoding($true)
foreach ($path in @($T30GateOutputPath, $T30GateQueuePath)) {
    $parent = Split-Path -Parent $path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
}
[IO.File]::WriteAllText($T30GateOutputPath, ($result | ConvertTo-Json -Depth 30), $utf8Bom)
$queueItemRaw = $queueItem
$queueItems = @($queueItemRaw)
# 複用 T-21 的 writer，確保佇列檔最外層永遠是陣列，且每項仍恰四欄。
Write-QueueFile -QueuePath $T30GateQueuePath -Items $queueItems
Write-Output $result.closingSummary
Write-Output "重疊=$(@($result.overlaps).Count)；分歧=$(@($result.disagreements).Count)；需使用者裁示=$($result.requiresUserDecision)；gate 可前進=$($result.gateMayProceed)"
