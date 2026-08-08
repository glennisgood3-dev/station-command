#requires -Version 5.1
<#
.SYNOPSIS
    T-31 完整離線 mock 測試；不連網、不讀任何 key。

.PARAMETER SkipErrorEnvelopeGuard
    僅供紅燈驗證：故意重現錯誤 JSON 被當成空 finding 的舊行為，使 (a)(b) 斷言真的失敗。
    正式流程禁用。
#>

[CmdletBinding()]
param(
    [switch]$SkipErrorEnvelopeGuard
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：dot-source 前先存成 T-31 獨有名稱。
$T31TestSkipErrorEnvelopeGuard = [bool]$SkipErrorEnvelopeGuard
$T31TestDir = $PSScriptRoot
. (Join-Path $T31TestDir 'gemini-e2e-core.ps1')

$script:T31Pass = 0
$script:T31Fail = 0

function Assert-T31 {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Condition) {
        $script:T31Pass++
        Write-Host "[PASS] $Message"
    }
    else {
        $script:T31Fail++
        Write-Host "[ASSERTION FAILED] $Message"
    }
}

$fixtureDir = Join-Path $T31TestDir 'fixtures'
$successBody = [IO.File]::ReadAllText((Join-Path $fixtureDir 'gemini-success.json')) | ConvertFrom-Json
$errorBody = [IO.File]::ReadAllText((Join-Path $fixtureDir 'gemini-error.json')) | ConvertFrom-Json
$maxTokensBody = [IO.File]::ReadAllText((Join-Path $fixtureDir 'gemini-max-tokens.json')) | ConvertFrom-Json
$expected = [IO.File]::ReadAllText((Join-Path $fixtureDir 'expected-outcomes.json')) | ConvertFrom-Json

Write-Host '=== A. 錯誤體 seam 與斷言失敗型紅燈 ==='
Assert-T31 (Test-T31HasProperty -InputObject $errorBody -Name 'error') '錯誤 fixture 採 error 外框'
Assert-T31 (-not (Test-T31HasProperty -InputObject $errorBody -Name 'candidates')) '錯誤 fixture 明確不是 candidates 結構'
Assert-T31 ($errorBody.error.code -eq 404 -and [string]$errorBody.error.status -ceq 'NOT_FOUND') '錯誤 fixture 含獨立字面值 error.code／error.status'
$errorResult = ConvertFrom-T31GeminiResponse -HttpStatus ([int]$expected.error.httpStatus) -ResponseBody $errorBody -Provider 'Gemini' -Model 't31-free-tier-model-does-not-exist' -FallbackProvider 'Claude' -SkipErrorEnvelopeGuard:$T31TestSkipErrorEnvelopeGuard

# 紅燈斷言 (a) 原文：適配層須判定解析失敗，不得把 Gemini error JSON 當成沒有 finding。
Assert-T31 $errorResult.ParseFailed '紅燈斷言 (a)：適配層須判定解析失敗，不得把 Gemini error JSON 當成沒有 finding。'

$hasNamedDegradation = $false
if ($null -ne $errorResult.Degradation) {
    $hasNamedDegradation = (Test-T31HasProperty -InputObject $errorResult.Degradation -Name 'provider') -and
        (Test-T31HasProperty -InputObject $errorResult.Degradation -Name '失敗原因') -and
        (Test-T31HasProperty -InputObject $errorResult.Degradation -Name '承接者')
}
# 紅燈斷言 (b) 原文：解析失敗須產生同時含 provider／失敗原因／承接者三項的具名降級記錄。
Assert-T31 $hasNamedDegradation '紅燈斷言 (b)：解析失敗須產生同時含 provider／失敗原因／承接者三項的具名降級記錄。'

# 紅燈斷言 (c) 原文：錯誤體該次不得產生 usage 記帳。
Assert-T31 ($null -eq $errorResult.UsageRecord) '紅燈斷言 (c)：錯誤體該次不得產生 usage 記帳。'

if (-not $T31TestSkipErrorEnvelopeGuard) {
    Assert-T31 (-not $errorResult.Success) '錯誤體不會回報成功'
    $errorFindingsRaw = $errorResult.Findings
    $errorFindings = @($errorFindingsRaw)
    Assert-T31 ($errorFindings.Count -eq 0) '錯誤體沒有 finding，但其語意是解析失敗而非成功空清單'
    Assert-T31 ($errorResult.HttpStatus -eq [int]$expected.error.httpStatus) '錯誤體保留獨立 fixture 指定的 HTTP 404'
    Assert-T31 ([string]$errorResult.Degradation.'失敗原因' -match 'code=404') '具名失敗原因保留 error.code'
    Assert-T31 ([string]$errorResult.Degradation.'失敗原因' -match 'status=NOT_FOUND') '具名失敗原因保留 error.status'
}

Write-Host '=== B. candidates[].content 正常路徑、逐條 finding 與記帳 ==='
Assert-T31 ((Test-T31HasProperty -InputObject $successBody -Name 'candidates') -and -not (Test-T31HasProperty -InputObject $successBody -Name 'error')) '成功 fixture 採 candidates[].content 且沒有 error 外框'
$successResult = ConvertFrom-T31GeminiResponse -HttpStatus ([int]$expected.success.httpStatus) -ResponseBody $successBody -Provider 'Gemini' -Model 'gemini-fixture-model' -FallbackProvider 'Claude'
$successFindingsRaw = $successResult.Findings
$successFindings = @($successFindingsRaw)
$expectedFindingIdsRaw = $expected.success.findingIds
$expectedFindingIds = @($expectedFindingIdsRaw)
Assert-T31 $successResult.Success '成功 fixture 判定成功'
Assert-T31 (-not $successResult.ParseFailed) '成功 fixture 不判解析失敗'
Assert-T31 ($successFindings.Count -eq [int]$expected.success.findingCount) 'finding 清單筆數符合獨立 expected fixture'
Assert-T31 ((($successFindings | ForEach-Object { $_.id }) -join ',') -ceq ($expectedFindingIds -join ',')) 'finding 可逐條列舉且 ID 順序符合獨立 expected fixture'
Assert-T31 ($successFindings[0] -isnot [string]) 'finding 是逐條物件，不是整包字串'
Assert-T31 ($null -eq $successResult.Degradation) '成功路徑沒有降級記錄'
Assert-T31 ($null -ne $successResult.UsageRecord) '成功路徑產生 usage 記帳物件'
Assert-T31 ($successResult.UsageRecord.promptTokenCount -eq [int]$expected.success.promptTokenCount) 'prompt token 符合獨立 expected fixture'
Assert-T31 ($successResult.UsageRecord.candidatesTokenCount -eq [int]$expected.success.candidatesTokenCount) 'candidate token 符合獨立 expected fixture'
Assert-T31 ($successResult.UsageRecord.totalTokenCount -eq [int]$expected.success.totalTokenCount) 'total token 符合獨立 expected fixture'
Assert-T31 ($successResult.UsageRecord.estimatedCost -eq [decimal]0) 'Gemini 免費層估算成本為 0，邊界是配額'
Assert-T31 ($successResult.UsageRecord.billingTier -ceq 'free') 'usage 記帳具名免費層'
$maxTokensResult = ConvertFrom-T31GeminiResponse -HttpStatus 200 -ResponseBody $maxTokensBody -Provider 'Gemini' -Model 'gemini-fixture-model' -FallbackProvider 'Claude'
Assert-T31 $maxTokensResult.ParseFailed 'MAX_TOKENS 回應判定失敗，不接受截斷審查'
Assert-T31 ([string]$maxTokensResult.Degradation.'失敗原因' -match 'token 上限') 'MAX_TOKENS 具名回報達上限並停手'
Assert-T31 ($maxTokensResult.UsageRecord.totalTokenCount -eq [int]$expected.maxTokens.totalTokenCount) 'MAX_TOKENS 失敗仍保存該次 usage 記帳'

Write-Host '=== C. 寫檔守門：錯誤不寫 usage，成功才寫 ==='
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('station-t31-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempRoot)
try {
    $errorOutput = Join-Path $tempRoot 'error'
    $errorSummary = Write-T31RunArtifacts -Result $errorResult -RawResponseBody $errorBody -OutputDirectory $errorOutput -Scenario ErrorEnvelope
    Assert-T31 (-not $errorSummary.usageWritten) '錯誤體摘要明示 usageWritten=False'
    Assert-T31 (-not (Test-Path -LiteralPath (Join-Path $errorOutput 'usage-record.json'))) '錯誤體目錄實際不存在 usage-record.json'
    if (-not $T31TestSkipErrorEnvelopeGuard) {
        $errorGate = [IO.File]::ReadAllText((Join-Path $errorOutput 'gate-record.json')) | ConvertFrom-Json
        Assert-T31 (-not (Test-T31HasProperty -InputObject $errorGate -Name 'usage')) '錯誤體 gate 紀錄沒有 usage 欄'
        Assert-T31 (Test-Path -LiteralPath (Join-Path $errorOutput 'degradation-record.json')) '錯誤體目錄存在具名降級記錄'
    }

    $successOutput = Join-Path $tempRoot 'success'
    $successSummary = Write-T31RunArtifacts -Result $successResult -RawResponseBody $successBody -OutputDirectory $successOutput -Scenario Success
    Assert-T31 $successSummary.usageWritten '成功摘要明示 usageWritten=True'
    Assert-T31 (Test-Path -LiteralPath (Join-Path $successOutput 'usage-record.json')) '成功目錄實際存在 usage-record.json'
    Assert-T31 (Test-Path -LiteralPath (Join-Path $successOutput 'findings.json')) '成功目錄實際存在 findings.json'
    $successGate = [IO.File]::ReadAllText((Join-Path $successOutput 'gate-record.json')) | ConvertFrom-Json
    Assert-T31 (Test-T31HasProperty -InputObject $successGate -Name 'usage') '成功 gate 紀錄含 usage 欄'
    Assert-T31 ($successGate.usage.totalTokenCount -eq 50 -and $successGate.usage.estimatedCost -eq 0) '成功 gate 紀錄含 token 與免費層成本'
    $savedFindingsRaw = [IO.File]::ReadAllText((Join-Path $successOutput 'findings.json')) | ConvertFrom-Json
    $savedFindings = @($savedFindingsRaw)
    Assert-T31 ($savedFindings.Count -eq 2) '落檔 finding 仍是可逐條列舉的二元素陣列'

    $maxTokensOutput = Join-Path $tempRoot 'max-tokens'
    $maxTokensSummary = Write-T31RunArtifacts -Result $maxTokensResult -RawResponseBody $maxTokensBody -OutputDirectory $maxTokensOutput -Scenario Success
    Assert-T31 ($maxTokensSummary.usageWritten -and -not $maxTokensSummary.success) 'MAX_TOKENS 摘要同時標示失敗與 usage 已記帳'
    Assert-T31 (Test-Path -LiteralPath (Join-Path $maxTokensOutput 'usage-record.json')) 'MAX_TOKENS 失敗實際寫入 usage-record.json'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Host '=== D. 請求、登錄、模板與四欄佇列契約 ==='
$requestTemplate = [IO.File]::ReadAllText((Join-Path $T31TestDir 'request-template.json')) | ConvertFrom-Json
Assert-T31 ([string]$requestTemplate.endpointShape -ceq 'POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent') '請求模板固定 Gemini v1beta generateContent 端點形狀'
Assert-T31 ([string]$requestTemplate.errorEnvelope.model -ceq 't31-free-tier-model-does-not-exist') '錯誤路徑固定使用指定不存在 model 名'
Assert-T31 ([string]$requestTemplate.success.promptTemplate -match '\{\{DIFF\}\}') '正常路徑模板要求嵌入實際 diff'
Assert-T31 ([string]$requestTemplate.success.promptTemplate -match 'findings') '正常路徑模板要求 findings JSON'
$requestFakeKeyParts = @('FAKE', '-KEY', '-DO', '-NOT', '-USE')
$requestFakeKey = $requestFakeKeyParts -join ''
$requestDefinition = [pscustomobject]@{ Provider = 'Gemini'; Endpoint = 'generativelanguage.googleapis.com/v1beta'; Family = 'Gemini' }
$boundedRequest = New-T31GeminiRequest -ProviderDefinition $requestDefinition -Model 'fixture-model' -Prompt 'fixture prompt' -ApiKey $requestFakeKey -MaxOutputTokens ([int]$requestTemplate.generationConfig.maxOutputTokens)
Assert-T31 ($boundedRequest.Body.generationConfig.maxOutputTokens -eq 1024) '真實請求形狀明確設定每票輸出 token 上限'
Assert-T31 ([string]$boundedRequest.Body.generationConfig.responseMimeType -ceq 'application/json') '真實請求要求 JSON MIME type'
Assert-T31 (-not (($boundedRequest.Body | ConvertTo-Json -Depth 20 -Compress).Contains($requestFakeKey))) '測試 key 不進 Gemini request body'

$registryPath = Join-Path $T31TestDir '../station-command/assets/vendor-registry.md'
$registryRowsRaw = Import-T28VendorRegistry -RegistryPath $registryPath
$registryRows = @($registryRowsRaw)
$geminiRows = @($registryRows | Where-Object { $_.Provider -ceq 'Gemini' })
Assert-T31 ($geminiRows.Count -eq 1) '登錄表 Gemini 恰一列'
Assert-T31 ([string]$geminiRows[0].Status -ceq 'available（首發；免費層，無需計費）') 'Gemini 狀態字串精確符合 Spec §5.1'
$forbiddenBillingPhrase = '待' + '儲值'
$t31Files = Get-ChildItem -LiteralPath $T31TestDir -Recurse -File
$forbiddenHits = 0
foreach ($t31File in $t31Files) {
    if ([IO.File]::ReadAllText($t31File.FullName).Contains($forbiddenBillingPhrase)) { $forbiddenHits++ }
}
Assert-T31 ($forbiddenHits -eq 0) 'T-31 全檔沒有已廢止的舊計費前提字串'

$queueRaw = [IO.File]::ReadAllText((Join-Path $T31TestDir 'queue-item-template.json')) | ConvertFrom-Json
$queueItems = @($queueRaw)
Assert-T31 ($queueItems.Count -eq 1) '佇列模板恰有一項'
$queueKeys = @($queueItems[0].PSObject.Properties.Name)
Assert-T31 ($queueKeys.Count -eq 4) '佇列項恰四欄'
Assert-T31 (($queueKeys -join '/') -ceq 'action/target/payload/source') '佇列四欄逐欄為 action／target／payload／source'
Assert-T31 ([string]$queueItems[0].action -ceq 'comment') '佇列 action 使用 T-21 白名單 comment'
Assert-T31 ([string]$queueItems[0].source -ceq 'T-31') '佇列 source 具名 T-31'

$conclusionText = [IO.File]::ReadAllText((Join-Path $T31TestDir 'conclusion-template.md'))
foreach ($requiredConclusionField in @('實際 HTTP 回應碼', 'usageMetadata', 'provider', '失敗原因', '承接者', 'DECISIONS.md')) {
    Assert-T31 $conclusionText.Contains($requiredConclusionField) "結論模板含必要欄位：$requiredConclusionField"
}

Write-Host "T31 OFFLINE RESULT：PASS=$script:T31Pass FAIL=$script:T31Fail"
if ($script:T31Fail -gt 0) { exit 1 }
exit 0
