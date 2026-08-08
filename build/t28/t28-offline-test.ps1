#requires -Version 5.1
<#
.SYNOPSIS
    T-28 完整離線測試；不連網、不碰真 key。

.PARAMETER SkipKeyRedaction
    僅供紅燈驗證：故意讓四個測試表面含測試 key，使 key 不外洩斷言失敗。正式流程禁用。

.PARAMETER SkipRetry
    僅供紅燈驗證：故意停用逾時／5xx 重試，使「重試次數恰為 1」斷言失敗。正式流程禁用。
#>

[CmdletBinding()]
param(
    [switch]$SkipKeyRedaction,
    [switch]$SkipRetry
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：dot-source 前先存入 T28 獨有變數，避免下游 param() cascade 覆寫。
$T28TestSkipKeyRedaction = [bool]$SkipKeyRedaction
$T28TestSkipRetry = [bool]$SkipRetry
$T28TestDir = $PSScriptRoot
. (Join-Path $T28TestDir 'vendor-adapter.ps1')
. (Join-Path $T28TestDir 'key-leak-scan.ps1')
. (Join-Path $T28TestDir 'reachability-policy.ps1')

$script:T28Pass = 0
$script:T28Fail = 0

function Assert-T28 {
    param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    if ($Condition) {
        $script:T28Pass++
        Write-Host "[PASS] $Message"
    }
    else {
        $script:T28Fail++
        Write-Host "[ASSERTION FAILED] $Message"
    }
}

function Resolve-T28FixturePath {
    param([Parameter(Mandatory = $true)]$Root, [Parameter(Mandatory = $true)][string]$Path)
    $current = $Root
    foreach ($segment in ($Path -split '\.')) {
        if ($segment -match '^\d+$') {
            $items = @($current)
            $index = [int]$segment
            if ($index -ge $items.Count) { return [pscustomobject]@{ Exists = $false; Value = $null } }
            $current = $items[$index]
        }
        else {
            if ($current -is [Collections.IDictionary]) {
                if (-not $current.Contains($segment)) { return [pscustomobject]@{ Exists = $false; Value = $null } }
                $current = $current[$segment]
            }
            else {
                $property = $current.PSObject.Properties[$segment]
                if ($null -eq $property) { return [pscustomobject]@{ Exists = $false; Value = $null } }
                $current = $property.Value
            }
        }
    }
    return [pscustomobject]@{ Exists = $true; Value = $current }
}

function Write-T28TestText {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($true)))
}

Write-Host '=== 0. 純函式庫直接執行提示 ==='
$currentPowerShell = (Get-Process -Id $PID).Path
$keyLeakScriptPath = Join-Path $T28TestDir 'key-leak-scan.ps1'
$keyLeakDirectOutput = @(& $currentPowerShell -NoLogo -NoProfile -File $keyLeakScriptPath 2>&1) | Out-String
Assert-T28 (-not [string]::IsNullOrWhiteSpace($keyLeakDirectOutput)) 'key-leak-scan.ps1 以子行程直接執行時輸出不得為空'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('station-t28-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempRoot)
try {
    # 測試 key 以片段於執行期組合，完整值不落入 repo 或證據。
    $fakeKeyParts = @('FAKE', '-KEY', '-DO', '-NOT', '-USE')
    $fakeKey = $fakeKeyParts -join ''
    $masked = '[已遮蔽]'

    Write-Host '=== A. T-27 登錄表與 12 家可達性 fixture ==='
    $registryPath = Join-Path $T28TestDir '../station-command/assets/vendor-registry.md'
    $reachabilityPath = Join-Path $T28TestDir 'fixtures/reachability-2026-08-08.json'
    $reachability = [IO.File]::ReadAllText($reachabilityPath) | ConvertFrom-Json
    $rawRegistry = Import-T28VendorRegistry -RegistryPath $registryPath
    $registry = @($rawRegistry)
    $expectedProviders = @($reachability.providers)
    Assert-T28 ($registry.Count -eq 12) '登錄表解析結果恰為 12 家'
    Assert-T28 ($expectedProviders.Count -eq 12) '可達性 fixture 恰為 12 家'
    $endpointMismatch = 0
    foreach ($expectedProvider in $expectedProviders) {
        $matches = @($registry | Where-Object { $_.Provider -eq $expectedProvider.provider -and $_.Endpoint -eq $expectedProvider.endpoint })
        if ($matches.Count -ne 1) { $endpointMismatch++ }
    }
    Assert-T28 ($endpointMismatch -eq 0) '12 家 provider 與端點逐列符合獨立 fixture'
    Assert-T28 ((@($reachability.probeQualityStatusCodes) -join ',') -eq '200,401,403,429') '探測品質 PASS 回應碼區間固定為 200／401／403／429'
    $nonGetProbes = @($expectedProviders | Where-Object { [string]$_.probeMethod -cne 'GET' })
    Assert-T28 ($nonGetProbes.Count -eq 0) '12 家可達性 probe 全部使用 GET'
    $nonModelProbes = @($expectedProviders | Where-Object { [string]$_.probeSuffix -cne 'models' })
    Assert-T28 ($nonModelProbes.Count -eq 0) '12 家可達性 probe 全部指向 models 清單端點'
    $missingProbeReasons = @($expectedProviders | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.probeReason) })
    Assert-T28 ($missingProbeReasons.Count -eq 0) '12 家 fixture 均逐列具名 GET probe 選擇理由'

    Write-Host '=== A2. 可達性與探測品質兩層判準的人造回應 ==='
    $syntheticCases = @(
        [pscustomobject]@{ Name = 'HTTP 200'; StatusCode = 200; NetworkFailure = $null; ExpectedReachable = $true },
        [pscustomobject]@{ Name = 'HTTP 401'; StatusCode = 401; NetworkFailure = $null; ExpectedReachable = $true },
        [pscustomobject]@{ Name = 'HTTP 403'; StatusCode = 403; NetworkFailure = $null; ExpectedReachable = $true },
        [pscustomobject]@{ Name = 'HTTP 429'; StatusCode = 429; NetworkFailure = $null; ExpectedReachable = $true },
        [pscustomobject]@{ Name = 'HTTP 400'; StatusCode = 400; NetworkFailure = $null; ExpectedReachable = $true },
        [pscustomobject]@{ Name = 'HTTP 404'; StatusCode = 404; NetworkFailure = $null; ExpectedReachable = $true },
        [pscustomobject]@{ Name = 'HTTP 405'; StatusCode = 405; NetworkFailure = $null; ExpectedReachable = $true },
        [pscustomobject]@{ Name = '模擬連線失敗'; StatusCode = $null; NetworkFailure = 'ConnectionFailure'; ExpectedReachable = $false }
    )
    $syntheticAssessments = @{}
    foreach ($syntheticCase in $syntheticCases) {
        $assessment = Get-T28ReachabilityAssessment -StatusCode $syntheticCase.StatusCode -NetworkFailure $syntheticCase.NetworkFailure
        $syntheticAssessments[[string]$syntheticCase.Name] = $assessment
        if ($syntheticCase.ExpectedReachable) {
            Assert-T28 $assessment.Reachable "新判準可達性：$($syntheticCase.Name) 有 HTTP 回應即判可達"
        }
        else {
            Assert-T28 (-not $assessment.Reachable) '新判準可達性：模擬連線失敗且無 HTTP 回應才判不可達'
        }
    }
    foreach ($warningCode in @(400, 404, 405)) {
        $warningAssessment = $syntheticAssessments["HTTP $warningCode"]
        Assert-T28 ($warningAssessment.Reachable -and $warningAssessment.ReachabilityLevel -eq 'PASS' -and $warningAssessment.ProbeQuality -eq 'WARN') "新判準探測品質：HTTP $warningCode 標為 WARN 而非可達性 FAIL"
    }
    $proxyAssessment = Get-T28ReachabilityAssessment -StatusCode 421 -NetworkFailure $null
    Assert-T28 ((-not $proxyAssessment.Reachable) -and $proxyAssessment.ProbeQuality -eq 'N/A') '新判準 proxy 特例：HTTP 421 攔截判不可達，探測品質為 N/A'

    Write-Host '=== B. 四家族官方 schema 必要子集與回應解碼 fixture ==='
    $schemaDoc = [IO.File]::ReadAllText((Join-Path $T28TestDir 'fixtures/official-request-schemas.json')) | ConvertFrom-Json
    $schemas = @($schemaDoc.families)
    $responseDoc = [IO.File]::ReadAllText((Join-Path $T28TestDir 'fixtures/family-responses.json')) | ConvertFrom-Json
    Assert-T28 ($schemas.Count -eq 4) '官方 schema fixture 恰含四個格式家族'
    foreach ($schema in $schemas) {
        $definition = [pscustomobject]@{ Provider = $schema.provider; Endpoint = $schema.endpoint; Family = $schema.family }
        $request = New-T28VendorRequest -ProviderDefinition $definition -Model $schema.model -Prompt '最小唯讀測試提示' -ApiKey $fakeKey -MaxTokens 64
        Assert-T28 ($request.Method -eq $schema.method) "$($schema.family)：HTTP method 符合官方 fixture"
        Assert-T28 ($request.Uri.EndsWith($schema.endpointSuffix, [StringComparison]::Ordinal)) "$($schema.family)：端點路徑符合官方 fixture"
        $requiredHeaders = @($schema.requiredHeaders)
        $headersOkay = $true
        foreach ($headerName in $requiredHeaders) {
            if (-not $request.Headers.ContainsKey([string]$headerName)) { $headersOkay = $false }
        }
        Assert-T28 $headersOkay "$($schema.family)：必要 header 名稱與認證位置符合官方 fixture"
        $expectedAuth = [string]$schema.authPrefix + $fakeKey
        Assert-T28 ($request.Headers[[string]$schema.authHeader] -ceq $expectedAuth) "$($schema.family)：key 僅位於指定認證 header"
        $bodyJson = $request.Body | ConvertTo-Json -Depth 20 -Compress
        Assert-T28 ((-not $bodyJson.Contains($fakeKey)) -and (-not $request.Uri.Contains($fakeKey))) "$($schema.family)：request body 與 URI 均不含 key"
        $bodyOkay = $true
        foreach ($bodyPath in @($schema.bodyPaths)) {
            $resolved = Resolve-T28FixturePath -Root $request.Body -Path ([string]$bodyPath)
            if (-not $resolved.Exists) { $bodyOkay = $false }
        }
        Assert-T28 $bodyOkay "$($schema.family)：body 欄位路徑符合官方 fixture"

        $responseFixture = $responseDoc.PSObject.Properties[[string]$schema.family].Value
        $decoded = ConvertFrom-T28VendorResponse -Family $schema.family -ResponseBody $responseFixture.body
        Assert-T28 ($decoded -ceq [string]$responseFixture.expectedText) "$($schema.family)：回應依獨立 fixture 解出"
    }

    $writeLikeRequest = [pscustomobject]@{ Family = 'Cohere'; Method = 'DELETE'; Uri = 'https://api.cohere.com/v1/chat'; Body = [ordered]@{ model = 'x'; message = 'x' } }
    $readOnlyRejected = $false
    try { Assert-T28ReadOnlyRequest -Request $writeLikeRequest } catch { $readOnlyRejected = $true }
    Assert-T28 $readOnlyRejected '寫入型 HTTP method 會被唯讀白名單拒絕'
    $webTimeout = New-Object Net.WebException('模擬 WebException 逾時', [Net.WebExceptionStatus]::Timeout)
    Assert-T28 (Test-T28TimeoutException -Exception $webTimeout) 'Windows PowerShell WebException Timeout 可被辨識為可重試逾時'

    Write-Host '=== C. key 路徑與四表面掃描 ==='
    $connectionFolder = Join-Path $tempRoot 'connections'
    [void](New-Item -ItemType Directory -Path $connectionFolder)
    $keyPath = Join-Path $connectionFolder 'mock-provider.key'
    Write-T28TestText -Path $keyPath -Content $fakeKey
    $loadedKey = Read-T28VendorKey -ConnectionFolder $connectionFolder -Provider 'Mock Provider'
    Assert-T28 ($loadedKey -ceq $fakeKey) 'key 從可設定連接資料夾的 provider key 檔讀得'
    Assert-T28 ($null -eq (Read-T28VendorKey -ConnectionFolder $connectionFolder -Provider 'Missing Provider')) '缺 key 回傳不可用訊號而非硬編碼 key'
    $repoConnectionRejected = $false
    try { [void](Read-T28VendorKey -ConnectionFolder $T28TestDir -Provider 'OpenAI') } catch { $repoConnectionRejected = $true }
    Assert-T28 $repoConnectionRejected '連接資料夾位於 repo 內時直接拒絕，避免 key 進 repo'

    $surfaceRoot = Join-Path $tempRoot 'surfaces'
    $conversationPath = Join-Path $surfaceRoot 'conversation.txt'
    $repoSurface = Join-Path $surfaceRoot 'repo'
    $repoArtifact = Join-Path $repoSurface 'artifact.txt'
    $logPath = Join-Path $surfaceRoot 'adapter.log'
    $queuePath = Join-Path $surfaceRoot 'pending-queue.json'
    $surfaceContent = $masked
    if ($T28TestSkipKeyRedaction) { $surfaceContent = $fakeKey }
    Write-T28TestText -Path $conversationPath -Content $surfaceContent
    Write-T28TestText -Path $repoArtifact -Content $surfaceContent
    Write-T28TestText -Path $logPath -Content $surfaceContent
    Write-T28TestText -Path $queuePath -Content $surfaceContent

    $leakScan = Test-T28KeyLeakAcrossSurfaces -Secret $fakeKey -ConversationPaths @($conversationPath) -RepoPath $repoSurface -LogPaths @($logPath) -QueuePaths @($queuePath)
    # 紅燈斷言③原文：key 不得出現在對話輸出、repo 內容、log、待寫佇列四處任一處。
    Assert-T28 $leakScan.Safe "紅燈斷言③：key 不得出現在對話輸出、repo 內容、log、待寫佇列四處任一處（命中數=$($leakScan.MatchCount)，不顯示 key）"

    $surfaceCases = @(
        [pscustomobject]@{ Name = '對話輸出'; Target = $conversationPath },
        [pscustomobject]@{ Name = 'repo 內容'; Target = $repoArtifact },
        [pscustomobject]@{ Name = 'log'; Target = $logPath },
        [pscustomobject]@{ Name = '待寫佇列'; Target = $queuePath }
    )
    foreach ($surfaceCase in $surfaceCases) {
        Write-T28TestText -Path $conversationPath -Content $masked
        Write-T28TestText -Path $repoArtifact -Content $masked
        Write-T28TestText -Path $logPath -Content $masked
        Write-T28TestText -Path $queuePath -Content $masked
        Write-T28TestText -Path $surfaceCase.Target -Content $fakeKey
        $detection = Test-T28KeyLeakAcrossSurfaces -Secret $fakeKey -ConversationPaths @($conversationPath) -RepoPath $repoSurface -LogPaths @($logPath) -QueuePaths @($queuePath)
        Assert-T28 ((-not $detection.Safe) -and $detection.MatchCount -eq 1 -and $detection.Matches[0].Surface -eq $surfaceCase.Name) "掃描器真的抓得到 $($surfaceCase.Name) 的單一測試 key，且不回印 key"
    }

    Write-Host '=== D. 逾時／5xx 恰一次重試與具名降級 ==='
    $mockDefinition = [pscustomobject]@{ Provider = 'Mock Provider'; Endpoint = 'mock.invalid/v1'; Family = 'OpenAI-compatible' }
    $timeoutState = [pscustomobject]@{ Count = 0 }
    $timeoutTransport = {
        param($Request, $TimeoutSec)
        $timeoutState.Count++
        throw [TimeoutException]::new('模擬逾時')
    }
    $timeoutResult = Invoke-T28VendorCall -ProviderDefinition $mockDefinition -Model 'fixture-model' -Prompt '唯讀測試' -ConnectionFolder $connectionFolder -FallbackProvider 'Claude' -Transport $timeoutTransport -SkipRetry:$T28TestSkipRetry -LogPath (Join-Path $tempRoot 'timeout.log')

    $serverState = [pscustomobject]@{ Count = 0 }
    $serverTransport = {
        param($Request, $TimeoutSec)
        $serverState.Count++
        return [pscustomobject]@{ StatusCode = 503; Body = [pscustomobject]@{} }
    }
    $serverResult = Invoke-T28VendorCall -ProviderDefinition $mockDefinition -Model 'fixture-model' -Prompt '唯讀測試' -ConnectionFolder $connectionFolder -FallbackProvider 'Claude' -Transport $serverTransport -SkipRetry:$T28TestSkipRetry -LogPath (Join-Path $tempRoot 'server.log')

    # 紅燈斷言④原文：模擬逾時與 5xx，各重試恰一次後判該 provider 不可用，不得無限重試。
    $retryExact = $timeoutResult.RetryCount -eq 1 -and $serverResult.RetryCount -eq 1 -and $timeoutState.Count -eq 2 -and $serverState.Count -eq 2
    Assert-T28 $retryExact "紅燈斷言④：逾時與 5xx 各重試恰一次（timeout retry=$($timeoutResult.RetryCount)，5xx retry=$($serverResult.RetryCount)）"
    Assert-T28 ((-not $timeoutResult.Available) -and (-not $serverResult.Available)) '兩次皆失敗後，逾時與 5xx provider 均判為不可用'
    Assert-T28 ($timeoutResult.Attempts -le 2 -and $serverResult.Attempts -le 2) '機械上限鎖定每次最多兩次 attempt，無限重試不可能'
    Assert-T28 ($timeoutResult.Degradation.provider -eq 'Mock Provider' -and $timeoutResult.Degradation.'失敗原因' -eq '逾時' -and $timeoutResult.Degradation.'承接者' -eq 'Claude' -and $timeoutResult.Degradation.'生產線繼續') '逾時失敗含 provider／失敗原因／承接者，且生產線繼續'
    Assert-T28 ($serverResult.Degradation.provider -eq 'Mock Provider' -and $serverResult.Degradation.'失敗原因' -eq 'HTTP 503' -and $serverResult.Degradation.'承接者' -eq 'Claude' -and $serverResult.Degradation.'生產線繼續') '5xx 失敗含 provider／失敗原因／承接者，且生產線繼續'

    $successTransport = {
        param($Request, $TimeoutSec)
        return [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ choices = @([pscustomobject]@{ message = [pscustomobject]@{ content = 'fixture-pipeline-content' } }) } }
    }
    $successResult = Invoke-T28VendorCall -ProviderDefinition $mockDefinition -Model 'fixture-model' -Prompt '唯讀測試' -ConnectionFolder $connectionFolder -FallbackProvider 'Claude' -Transport $successTransport
    Assert-T28 ($successResult.Success -and $successResult.Content -eq 'fixture-pipeline-content' -and $successResult.Attempts -eq 1 -and $successResult.RetryCount -eq 0) '成功路徑由 provider＋model 組請求並解出回應內容'

    $echoTransport = {
        param($Request, $TimeoutSec)
        return [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ choices = @([pscustomobject]@{ message = [pscustomobject]@{ content = $fakeKey } }) } }
    }
    $echoResult = Invoke-T28VendorCall -ProviderDefinition $mockDefinition -Model 'fixture-model' -Prompt '唯讀測試' -ConnectionFolder $connectionFolder -FallbackProvider 'Claude' -Transport $echoTransport
    Assert-T28 ((-not $echoResult.Success) -and $null -eq $echoResult.Content -and $echoResult.Degradation.'失敗原因' -eq '回應含認證資料，已攔截' -and $echoResult.Degradation.'生產線繼續') '回應若含 key 會攔截內容並具名降級，不進對話輸出'

    $missingDefinition = [pscustomobject]@{ Provider = 'Missing Provider'; Endpoint = 'mock.invalid/v1'; Family = 'OpenAI-compatible' }
    $missingResult = Invoke-T28VendorCall -ProviderDefinition $missingDefinition -Model 'fixture-model' -Prompt '唯讀測試' -ConnectionFolder $connectionFolder -FallbackProvider 'Claude' -Transport $serverTransport
    Assert-T28 ($missingResult.Attempts -eq 0 -and $missingResult.Degradation.provider -eq 'Missing Provider' -and $missingResult.Degradation.'失敗原因' -eq '缺少 key' -and $missingResult.Degradation.'承接者' -eq 'Claude' -and $missingResult.Degradation.'生產線繼續') '缺 key 不送請求，直接具名降級且生產線繼續'

    Write-Host '=== E. 正式 repo／執行 log／佇列／對話輸出全域 key 掃描 ==='
    Write-T28TestText -Path $conversationPath -Content '測試輸出只含結果，不含認證資料。'
    Write-T28TestText -Path $repoArtifact -Content '測試 artifact 已遮蔽。'
    Write-T28TestText -Path $logPath -Content '測試 log 已遮蔽。'
    Write-T28TestText -Path $queuePath -Content '{"status":"masked"}'
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $T28TestDir '../..'))
    $finalScan = Test-T28KeyLeakAcrossSurfaces -Secret $fakeKey -ConversationPaths @($conversationPath) -RepoPath $repoRoot -LogPaths @((Join-Path $tempRoot 'timeout.log'), (Join-Path $tempRoot 'server.log'), $logPath) -QueuePaths @($queuePath)
    Assert-T28 $finalScan.Safe "正式掃描四處皆不含測試 key（命中數=$($finalScan.MatchCount)，不顯示 key）"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Host "=== RESULT：PASS=$script:T28Pass FAIL=$script:T28Fail ==="
if ($script:T28Fail -gt 0) { exit 1 }
exit 0
