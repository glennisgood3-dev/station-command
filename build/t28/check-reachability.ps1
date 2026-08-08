#requires -Version 5.1
<#
.SYNOPSIS
    驗證 12 家可達性 fixture，或由 Commander 在可連外環境逐家送一次無 key GET probe。

.DESCRIPTION
    本腳本不讀連接資料夾、不帶任何 key，也不做寫入、升級或付費呼叫。
    本交付環境禁止外網，所以 executor 只執行 -ValidateFixtureOnly；-RunNetworkCheck 留給 Commander。
#>

[CmdletBinding(DefaultParameterSetName = 'Validate')]
param(
    [Parameter(ParameterSetName = 'Validate')][switch]$ValidateFixtureOnly,
    [Parameter(ParameterSetName = 'Network', Mandatory = $true)][switch]$RunNetworkCheck,
    [string]$FixturePath = (Join-Path $PSScriptRoot 'fixtures/reachability-2026-08-08.json'),
    [string]$RegistryPath = (Join-Path $PSScriptRoot '../station-command/assets/vendor-registry.md'),
    [ValidateRange(1, 120)][int]$TimeoutSec = 20,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'reachability-policy.ps1')

function Write-T28ReachabilityReport {
    param([string]$Path, [string[]]$Lines)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($Path, ($Lines -join [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))
}

if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) { throw "找不到 fixture：$FixturePath" }
$fixture = [IO.File]::ReadAllText($FixturePath) | ConvertFrom-Json
$providers = @($fixture.providers)
$probeQualityCodes = @($fixture.probeQualityStatusCodes)
if ($providers.Count -ne 12) { throw "可達性 fixture 必須恰為 12 家，實得 $($providers.Count)。" }
if (($probeQualityCodes -join ',') -ne '200,401,403,429') { throw '探測品質回應碼區間必須逐字為 200／401／403／429。' }

$seen = @{}
foreach ($provider in $providers) {
    if ($seen.ContainsKey([string]$provider.provider)) { throw "fixture provider 重複：$($provider.provider)" }
    $seen[[string]$provider.provider] = $true
    if ([string]::IsNullOrWhiteSpace([string]$provider.endpoint) -or [string]::IsNullOrWhiteSpace([string]$provider.probeSuffix)) {
        throw "fixture 端點不完整：$($provider.provider)"
    }
    if ([string]$provider.probeMethod -cne 'GET') { throw "fixture probe method 必須為 GET：$($provider.provider)" }
    if ([string]$provider.probeSuffix -cne 'models') { throw "fixture probe 必須使用 GET 清單端點 models：$($provider.provider)" }
    if ([string]::IsNullOrWhiteSpace([string]$provider.probeReason)) { throw "fixture 必須逐列具名 probe 理由：$($provider.provider)" }
}

if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) { throw "找不到 T-27 廠商登錄表：$RegistryPath" }
$registryLines = [IO.File]::ReadAllLines($RegistryPath)
foreach ($provider in $providers) {
    $literalRowPrefix = '| ' + [string]$provider.provider + ' | ' + [string]$provider.endpoint + ' |'
    $rowMatches = @($registryLines | Where-Object { $_.StartsWith($literalRowPrefix, [StringComparison]::Ordinal) })
    if ($rowMatches.Count -ne 1) { throw "fixture 與 T-27 asset 的 provider／端點未逐列相符：$($provider.provider)" }
}

if (-not $RunNetworkCheck) {
    Write-Host '[PASS] fixture：12 家皆有唯一 provider、端點、GET models 清單 probe 與具名理由，且逐列符合 T-27 asset。'
    Write-Host '[POLICY] 可達性：取得任意 provider HTTP 回應即 PASS；無回應的網路錯誤或 proxy 421 才 FAIL。'
    Write-Host '[POLICY] 探測品質：200／401／403／429 為 PASS；其他 provider HTTP 狀態為 WARN，不影響可達性。'
    Write-Host '[OFFLINE] 未送出任何網路請求；請由 Commander 使用 -RunNetworkCheck。'
    exit 0
}

$report = New-Object System.Collections.Generic.List[string]
$unreachable = 0
$probePass = 0
$probeWarn = 0
$probeNotApplicable = 0
foreach ($provider in $providers) {
    $uri = 'https://' + ([string]$provider.endpoint).TrimEnd('/') + '/' + ([string]$provider.probeSuffix).TrimStart('/')
    $statusCode = $null
    $networkFailure = $null
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Get -TimeoutSec $TimeoutSec
        $statusCode = [int]$response.StatusCode
    }
    catch {
        if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        else {
            $networkFailure = $_.Exception.GetType().Name
            if ($_.Exception -is [Net.WebException]) { $networkFailure += ':' + [string]$_.Exception.Status }
        }
    }

    $assessment = Get-T28ReachabilityAssessment -StatusCode $statusCode -NetworkFailure $networkFailure -ProbeQualityStatusCodes $probeQualityCodes
    if ($assessment.Reachable) {
        $reachabilityLine = "[REACHABILITY PASS] provider=$($provider.provider) endpoint=$($provider.endpoint) probe=GET/$($provider.probeSuffix) status=$($assessment.StatusCode) reason=$($assessment.ReachabilityReason)"
    }
    else {
        $unreachable++
        $reachabilityLine = "[REACHABILITY FAIL] provider=$($provider.provider) endpoint=$($provider.endpoint) probe=GET/$($provider.probeSuffix) reason=$($assessment.ReachabilityReason)"
    }
    switch ([string]$assessment.ProbeQuality) {
        'PASS' {
            $probePass++
            $qualityLine = "[PROBE PASS] provider=$($provider.provider) status=$($assessment.StatusCode) reason=$($assessment.ProbeQualityReason)"
        }
        'WARN' {
            $probeWarn++
            $qualityLine = "[PROBE WARN] provider=$($provider.provider) status=$($assessment.StatusCode) reason=$($assessment.ProbeQualityReason)"
        }
        default {
            $probeNotApplicable++
            $qualityLine = "[PROBE N/A] provider=$($provider.provider) reason=$($assessment.ProbeQualityReason)"
        }
    }
    $report.Add($reachabilityLine)
    $report.Add($qualityLine)
    Write-Host $reachabilityLine
    Write-Host $qualityLine
}
$report.Add("REACHABILITY RESULT providers=12 reachable=$(12 - $unreachable) unreachable=$unreachable")
$report.Add("PROBE QUALITY RESULT pass=$probePass warn=$probeWarn notApplicable=$probeNotApplicable expected=200/401/403/429")
Write-T28ReachabilityReport -Path $OutputPath -Lines $report.ToArray()
if ($unreachable -gt 0) { exit 1 }
exit 0
