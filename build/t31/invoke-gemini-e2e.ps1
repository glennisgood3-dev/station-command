#requires -Version 5.1
<#
.SYNOPSIS
    T-31 Gemini 首發端到端腳本；真實呼叫僅由 Commander 在允許外網且持有 key 的環境執行。

.DESCRIPTION
    ErrorEnvelope 固定使用不存在的 model 名驗錯誤體；Success 使用指定 model 與實際 diff 驗正常路徑。
    提供 FixturePath 時只讀離線 fixture，不讀 key、也不送網路。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('ErrorEnvelope', 'Success')][string]$Scenario,
    [string]$ConnectionFolder,
    [string]$Model,
    [string]$DiffPath,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'commander-results'),
    [string]$FallbackProvider = 'Claude',
    [ValidateRange(1, 300)][int]$TimeoutSec = 30,
    [ValidateRange(1, 8192)][int]$MaxOutputTokens = 1024,
    [string]$RegistryPath = (Join-Path $PSScriptRoot '../station-command/assets/vendor-registry.md'),
    [string]$RequestTemplatePath = (Join-Path $PSScriptRoot 'request-template.json'),
    [string]$FixturePath,
    [int]$FixtureHttpStatus = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：dot-source T-31 核心前，先用本票獨有名稱保存所有已綁定參數。
$T31CliScenario = $Scenario
$T31CliConnectionFolder = $ConnectionFolder
$T31CliModel = $Model
$T31CliDiffPath = $DiffPath
$T31CliOutputDirectory = $OutputDirectory
$T31CliFallbackProvider = $FallbackProvider
$T31CliTimeoutSec = $TimeoutSec
$T31CliMaxOutputTokens = $MaxOutputTokens
$T31CliRegistryPath = $RegistryPath
$T31CliRequestTemplatePath = $RequestTemplatePath
$T31CliFixturePath = $FixturePath
$T31CliFixtureHttpStatus = $FixtureHttpStatus
$T31CliDir = $PSScriptRoot
. (Join-Path $T31CliDir 'gemini-e2e-core.ps1')

function Invoke-T31GeminiTransport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $requestJson = $Request.Body | ConvertTo-Json -Depth 30 -Compress
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Request.Uri -Method POST -Headers $Request.Headers -Body ([Text.Encoding]::UTF8.GetBytes($requestJson)) -TimeoutSec $TimeoutSeconds
        $body = $response.Content | ConvertFrom-Json
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $body }
    }
    catch {
        $webResponse = $_.Exception.Response
        if ($null -eq $webResponse -or $null -eq $webResponse.StatusCode) { throw }
        $stream = $null
        $reader = $null
        try {
            $stream = $webResponse.GetResponseStream()
            $reader = New-Object IO.StreamReader($stream)
            $errorJson = $reader.ReadToEnd()
        }
        finally {
            if ($null -ne $reader) { $reader.Dispose() }
            elseif ($null -ne $stream) { $stream.Dispose() }
        }
        $errorBody = $errorJson | ConvertFrom-Json
        return [pscustomobject]@{ StatusCode = [int]$webResponse.StatusCode; Body = $errorBody }
    }
}

if (-not (Test-Path -LiteralPath $T31CliRequestTemplatePath -PathType Leaf)) {
    throw "找不到請求模板：$T31CliRequestTemplatePath"
}
$requestTemplate = [IO.File]::ReadAllText($T31CliRequestTemplatePath) | ConvertFrom-Json
$definition = Get-T28VendorDefinition -RegistryPath $T31CliRegistryPath -Provider 'Gemini'

if ($T31CliScenario -eq 'ErrorEnvelope') {
    $effectiveModel = [string]$requestTemplate.errorEnvelope.model
    $prompt = [string]$requestTemplate.errorEnvelope.prompt
}
else {
    if ([string]::IsNullOrWhiteSpace($T31CliModel)) { throw 'Success 情境須提供 -Model。' }
    if ([string]::IsNullOrWhiteSpace($T31CliDiffPath) -or -not (Test-Path -LiteralPath $T31CliDiffPath -PathType Leaf)) {
        throw 'Success 情境須提供存在的 -DiffPath，內容必須是實際 diff。'
    }
    $effectiveModel = $T31CliModel
    $diffText = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $T31CliDiffPath).Path)
    if ([string]::IsNullOrWhiteSpace($diffText)) { throw '實際 diff 不得為空。' }
    $prompt = ([string]$requestTemplate.success.promptTemplate).Replace('{{DIFF}}', $diffText)
}

$transportResult = $null
if (-not [string]::IsNullOrWhiteSpace($T31CliFixturePath)) {
    if (-not (Test-Path -LiteralPath $T31CliFixturePath -PathType Leaf)) { throw "找不到 fixture：$T31CliFixturePath" }
    $fixtureStatus = $T31CliFixtureHttpStatus
    if ($fixtureStatus -eq 0) { $fixtureStatus = if ($T31CliScenario -eq 'ErrorEnvelope') { 404 } else { 200 } }
    $fixtureBody = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $T31CliFixturePath).Path) | ConvertFrom-Json
    $transportResult = [pscustomobject]@{ StatusCode = $fixtureStatus; Body = $fixtureBody }
    Write-Host "離線 fixture 模式：scenario=$T31CliScenario；未讀 key；未送網路"
}
else {
    if ([string]::IsNullOrWhiteSpace($T31CliConnectionFolder)) { throw '真實呼叫須提供 repo 外的 -ConnectionFolder。' }
    $apiKey = Read-T28VendorKey -ConnectionFolder $T31CliConnectionFolder -Provider 'Gemini'
    if ($null -eq $apiKey) { throw '找不到 Gemini key；未送出請求。' }
    $request = New-T31GeminiRequest -ProviderDefinition $definition -Model $effectiveModel -Prompt $prompt -ApiKey $apiKey -MaxOutputTokens $T31CliMaxOutputTokens
    $transportResult = Invoke-T31GeminiTransport -Request $request -TimeoutSeconds $T31CliTimeoutSec
}

$result = ConvertFrom-T31GeminiResponse -HttpStatus $transportResult.StatusCode -ResponseBody $transportResult.Body -Provider 'Gemini' -Model $effectiveModel -FallbackProvider $T31CliFallbackProvider
$scenarioOutput = Join-Path $T31CliOutputDirectory $T31CliScenario
$summary = Write-T31RunArtifacts -Result $result -RawResponseBody $transportResult.Body -OutputDirectory $scenarioOutput -Scenario $T31CliScenario

Write-Host "T-31 結果：scenario=$T31CliScenario；HTTP=$($summary.httpStatus)；success=$($summary.success)；parseFailed=$($summary.parseFailed)；findings=$($summary.findingCount)；usageWritten=$($summary.usageWritten)"
Write-Host "落檔目錄：$scenarioOutput"
if ($T31CliScenario -eq 'ErrorEnvelope') {
    if (-not $result.ParseFailed -or $null -eq $result.Degradation -or $summary.usageWritten) { exit 1 }
    Write-Host "具名降級：provider=$($result.Degradation.provider)；失敗原因=$($result.Degradation.'失敗原因')；承接者=$($result.Degradation.'承接者')"
    exit 0
}
if (-not $result.Success -or $summary.findingCount -lt 0 -or -not $summary.usageWritten) { exit 1 }
$outputFindingsRaw = $result.Findings
$outputFindings = @($outputFindingsRaw)
foreach ($finding in $outputFindings) {
    Write-Host "finding：id=$($finding.id)；severity=$($finding.severity)；summary=$($finding.summary)"
}
exit 0
