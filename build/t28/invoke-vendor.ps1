#requires -Version 5.1
<# T-28 CLI：指定 provider＋model，從可設定連接資料夾讀 key 並呼叫；失敗具名降級。 #>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Provider,
    [Parameter(Mandatory = $true)][string]$Model,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$ConnectionFolder,
    [string]$FallbackProvider = 'Claude',
    [ValidateRange(1, 300)][int]$TimeoutSec = 30,
    [string]$RegistryPath = (Join-Path $PSScriptRoot '../station-command/assets/vendor-registry.md'),
    [string]$LogPath,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：所有參數先存為 T28 獨有名稱，再 dot-source。
$T28CliProvider = $Provider
$T28CliModel = $Model
$T28CliPrompt = $Prompt
$T28CliConnectionFolder = $ConnectionFolder
$T28CliFallbackProvider = $FallbackProvider
$T28CliTimeoutSec = $TimeoutSec
$T28CliRegistryPath = $RegistryPath
$T28CliLogPath = $LogPath
$T28CliDryRun = [bool]$DryRun
$T28CliDir = $PSScriptRoot
. (Join-Path $T28CliDir 'vendor-adapter.ps1')

$definition = Get-T28VendorDefinition -RegistryPath $T28CliRegistryPath -Provider $T28CliProvider
$apiKey = Read-T28VendorKey -ConnectionFolder $T28CliConnectionFolder -Provider $definition.Provider
if ($null -eq $apiKey) {
    $record = New-T28DegradationRecord -Provider $definition.Provider -Reason '缺少 key' -FallbackProvider $T28CliFallbackProvider
    Write-Host "降級：provider=$($record.provider)；失敗原因=$($record.'失敗原因')；承接者=$($record.'承接者')；生產線繼續=$($record.'生產線繼續')"
    exit 0
}

if ($T28CliDryRun) {
    $request = New-T28VendorRequest -ProviderDefinition $definition -Model $T28CliModel -Prompt $T28CliPrompt -ApiKey $apiKey
    Write-Host "DRY-RUN：provider=$($definition.Provider)；family=$($definition.Family)；method=$($request.Method)；host=$(([Uri]$request.Uri).Host)；認證 header 已設定=True；未送出網路請求"
    exit 0
}

$result = Invoke-T28VendorCall -ProviderDefinition $definition -Model $T28CliModel -Prompt $T28CliPrompt -ConnectionFolder $T28CliConnectionFolder -FallbackProvider $T28CliFallbackProvider -TimeoutSec $T28CliTimeoutSec -LogPath $T28CliLogPath
if ($result.Success) {
    Write-Output $result.Content
    exit 0
}
Write-Host "降級：provider=$($result.Degradation.provider)；失敗原因=$($result.Degradation.'失敗原因')；承接者=$($result.Degradation.'承接者')；生產線繼續=$($result.Degradation.'生產線繼續')"
exit 0
