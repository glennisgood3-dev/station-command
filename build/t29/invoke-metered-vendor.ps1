#requires -Version 5.1
<# T-29 CLI：以 T-28 適配層呼叫外廠，並套用每票成本／配額邊界。 #>

[CmdletBinding(DefaultParameterSetName = 'Real')]
param(
    [Parameter(ParameterSetName = 'Real', Mandatory = $true)][string]$WorkId,
    [Parameter(ParameterSetName = 'Real', Mandatory = $true)][string]$TicketId,
    [Parameter(ParameterSetName = 'Real', Mandatory = $true)][string]$Provider,
    [Parameter(ParameterSetName = 'Real', Mandatory = $true)][string]$Model,
    [Parameter(ParameterSetName = 'Real', Mandatory = $true)][string]$Prompt,
    [Parameter(ParameterSetName = 'Real', Mandatory = $true)][string]$ConnectionFolder,
    [Parameter(ParameterSetName = 'Real', Mandatory = $true)][string]$BudgetPath,
    [Parameter(ParameterSetName = 'Real', Mandatory = $true)][string]$LedgerPath,
    [Parameter(ParameterSetName = 'Real')][string]$CallId = ([Guid]::NewGuid().ToString('N')),
    [Parameter(ParameterSetName = 'Real')][string]$FallbackProvider = 'Claude',
    [Parameter(ParameterSetName = 'Real')][ValidateRange(1, 300)][int]$TimeoutSec = 30,
    [Parameter(ParameterSetName = 'Real')][string]$RegistryPath = (Join-Path $PSScriptRoot '../station-command/assets/vendor-registry.md'),
    [Parameter(ParameterSetName = 'Demo', Mandatory = $true)][switch]$DemoMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：dot-source 前保存所有參數，避免下游同名 param cascade 成靜默 no-op。
$T29CliDir = $PSScriptRoot
$T29CliParameterSet = $PSCmdlet.ParameterSetName
$T29CliWorkId = $WorkId
$T29CliTicketId = $TicketId
$T29CliProvider = $Provider
$T29CliModel = $Model
$T29CliPrompt = $Prompt
$T29CliConnectionFolder = $ConnectionFolder
$T29CliBudgetPath = $BudgetPath
$T29CliLedgerPath = $LedgerPath
$T29CliCallId = $CallId
$T29CliFallbackProvider = $FallbackProvider
$T29CliTimeoutSec = $TimeoutSec
$T29CliRegistryPath = $RegistryPath
$T29CliDemoRequested = [bool]$DemoMode
. (Join-Path $T29CliDir 'cost-boundary.ps1') -FunctionsOnly

function Invoke-T29DemoCli {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('t29-cli-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $tempRoot)
    try {
        $connection = Join-Path $tempRoot 'connections'
        [void](New-Item -ItemType Directory -Path $connection)
        $fakeKey = @('FAKE', '-KEY', '-DO', '-NOT', '-USE') -join ''
        [IO.File]::WriteAllText((Join-Path $connection 'fixture-vendor.key'), $fakeKey, (New-Object Text.UTF8Encoding($true)))
        $ledgerPath = Join-Path $tempRoot 'ledger.json'
        $definition = [pscustomobject]@{ Provider = 'Fixture Vendor'; Endpoint = 'https://fixture.invalid/v1'; Authentication = 'Bearer'; Family = 'OpenAI-compatible'; Status = 'fixture' }
        $budget = [pscustomobject]@{ tier = 'paid'; limitType = 'amount'; limitValue = 0.001; inputUsdPerMillion = 1; outputUsdPerMillion = 2 }
        $transport = {
            param($Request, $TransportTimeoutSec)
            [pscustomobject]@{
                StatusCode = 200
                Body = [pscustomobject]@{
                    choices = @([pscustomobject]@{ message = [pscustomobject]@{ content = 'CLI 離線完整回傳' } })
                    usage = [pscustomobject]@{ prompt_tokens = 10; completion_tokens = 5; total_tokens = 15 }
                }
            }
        }
        $result = Invoke-T29MeteredVendorCall -WorkId 'W-cli' -TicketId 'T-29-demo' -ProviderDefinition $definition `
            -Model 'fixture-model' -Prompt 'CLI 離線完整輸入' -ConnectionFolder $connection -FallbackProvider 'Claude' `
            -LedgerPath $ledgerPath -Budget $budget -CallId 'cli-demo-1' -Transport $transport
        Write-Host "CLI DEMO：Success=$($result.Success)；Blocked=$($result.Blocked)；輸入完整=$($result.SubmittedContent -ceq 'CLI 離線完整輸入')；輸出完整=$($result.Content -ceq 'CLI 離線完整回傳')"
        Write-Host "CLI DEMO：token=$($result.Usage.TotalTokens)；cost=$($result.LedgerEntry.estimatedCost)；percent=$($result.CostState.PercentUsed)；未送網路"
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($T29CliDemoRequested -or $T29CliParameterSet -eq 'Demo') {
    Invoke-T29DemoCli
    exit 0
}

if (-not (Test-Path -LiteralPath $T29CliBudgetPath -PathType Leaf)) { throw "找不到 budget：$T29CliBudgetPath" }
$budgetObject = [IO.File]::ReadAllText($T29CliBudgetPath) | ConvertFrom-Json
$providerDefinition = Get-T28VendorDefinition -RegistryPath $T29CliRegistryPath -Provider $T29CliProvider
$callResult = Invoke-T29MeteredVendorCall -WorkId $T29CliWorkId -TicketId $T29CliTicketId -ProviderDefinition $providerDefinition `
    -Model $T29CliModel -Prompt $T29CliPrompt -ConnectionFolder $T29CliConnectionFolder -FallbackProvider $T29CliFallbackProvider `
    -LedgerPath $T29CliLedgerPath -Budget $budgetObject -CallId $T29CliCallId -TimeoutSec $T29CliTimeoutSec
Write-Host $callResult.NamedReport
if ($callResult.Success) { Write-Output $callResult.Content; exit 0 }
if ($callResult.Blocked) { exit 2 }
Write-Host "降級：provider=$($callResult.Degradation.provider)；失敗原因=$($callResult.Degradation.'失敗原因')；承接者=$($callResult.Degradation.'承接者')"
exit 0
