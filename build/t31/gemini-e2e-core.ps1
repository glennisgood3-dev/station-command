#requires -Version 5.1
<#
.SYNOPSIS
    T-31 Gemini 回應語意解析與落檔函式庫。

.DESCRIPTION
    seam：輸入 Gemini v1beta generateContent 原始回應物件與 HTTP 狀態，輸出逐條 finding、
    具名降級記錄或 usage 記帳物件。本檔不自行送網路請求。

.EXAMPLE
    . .\gemini-e2e-core.ps1
    ConvertFrom-T31GeminiResponse -HttpStatus 200 -ResponseBody $body -Provider Gemini -Model gemini-model -FallbackProvider Claude
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:T31CoreDir = $PSScriptRoot
$script:T31T28AdapterPath = [IO.Path]::GetFullPath((Join-Path $script:T31CoreDir '../t28/vendor-adapter.ps1'))
if (-not (Test-Path -LiteralPath $script:T31T28AdapterPath -PathType Leaf)) {
    throw "找不到 T-28 適配層：$script:T31T28AdapterPath"
}
. $script:T31T28AdapterPath

function Get-T31PropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($InputObject -is [Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-T31HasProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($InputObject -is [Collections.IDictionary]) { return $InputObject.Contains($Name) }
    return $null -ne $InputObject.PSObject.Properties[$Name]
}

function New-T31ParseFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][int]$HttpStatus,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][string]$FallbackProvider,
        [AllowNull()]$UsageRecord = $null
    )

    $degradation = New-T28DegradationRecord -Provider $Provider -Reason $Reason -FallbackProvider $FallbackProvider
    return [pscustomobject][ordered]@{
        Success = $false
        ParseFailed = $true
        Provider = $Provider
        Model = $Model
        HttpStatus = $HttpStatus
        Findings = @()
        Degradation = $degradation
        UsageRecord = $UsageRecord
    }
}

function New-T31UsageRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)]$UsageMetadata
    )

    foreach ($requiredName in @('promptTokenCount', 'candidatesTokenCount', 'totalTokenCount')) {
        if (-not (Test-T31HasProperty -InputObject $UsageMetadata -Name $requiredName)) {
            throw "usageMetadata 缺少必要欄位：$requiredName"
        }
    }

    return [pscustomobject][ordered]@{
        provider = $Provider
        model = $Model
        billingTier = 'free'
        currency = 'USD'
        estimatedCost = [decimal]0
        promptTokenCount = [int](Get-T31PropertyValue -InputObject $UsageMetadata -Name 'promptTokenCount')
        candidatesTokenCount = [int](Get-T31PropertyValue -InputObject $UsageMetadata -Name 'candidatesTokenCount')
        totalTokenCount = [int](Get-T31PropertyValue -InputObject $UsageMetadata -Name 'totalTokenCount')
        rawUsage = $UsageMetadata
    }
}

function New-T31GeminiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ProviderDefinition,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [ValidateRange(1, 8192)][int]$MaxOutputTokens = 1024
    )

    $request = New-T28VendorRequest -ProviderDefinition $ProviderDefinition -Model $Model -Prompt $Prompt -ApiKey $ApiKey
    if ($request.Family -cne 'Gemini') { throw 'T-31 請求包裝只接受 Gemini 格式家族。' }
    $request.Body['generationConfig'] = [ordered]@{
        maxOutputTokens = $MaxOutputTokens
        responseMimeType = 'application/json'
    }
    Assert-T28ReadOnlyRequest -Request $request
    return $request
}

function ConvertFrom-T31GeminiResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$HttpStatus,
        [Parameter(Mandatory = $true)]$ResponseBody,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$FallbackProvider,
        [switch]$SkipErrorEnvelopeGuard
    )

    $hasError = Test-T31HasProperty -InputObject $ResponseBody -Name 'error'
    if ($hasError -and $SkipErrorEnvelopeGuard) {
        # 僅供紅燈驗證：重現 T-28 舊解析出口把缺少 candidates 的錯誤體視為空結果的假綠。
        Write-Warning '已略過 Gemini 錯誤體守門；僅供紅燈驗證，正式流程禁用。'
        return [pscustomobject][ordered]@{
            Success = $true
            ParseFailed = $false
            Provider = $Provider
            Model = $Model
            HttpStatus = $HttpStatus
            Findings = @()
            Degradation = $null
            UsageRecord = $null
        }
    }

    if ($hasError) {
        $errorBody = Get-T31PropertyValue -InputObject $ResponseBody -Name 'error'
        $code = Get-T31PropertyValue -InputObject $errorBody -Name 'code'
        $status = Get-T31PropertyValue -InputObject $errorBody -Name 'status'
        $message = Get-T31PropertyValue -InputObject $errorBody -Name 'message'
        $reason = "Gemini 錯誤體：code=$code；status=$status；message=$message"
        return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason $reason -FallbackProvider $FallbackProvider
    }

    if ($HttpStatus -lt 200 -or $HttpStatus -ge 300) {
        return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason "HTTP $HttpStatus 未附 Gemini error 結構" -FallbackProvider $FallbackProvider
    }

    if (-not (Test-T31HasProperty -InputObject $ResponseBody -Name 'candidates')) {
        return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason '成功碼回應缺少 candidates' -FallbackProvider $FallbackProvider
    }
    $rawCandidates = Get-T31PropertyValue -InputObject $ResponseBody -Name 'candidates'
    $candidates = @($rawCandidates)
    if ($candidates.Count -lt 1) {
        return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason '成功碼回應的 candidates 為空' -FallbackProvider $FallbackProvider
    }

    $firstCandidate = $candidates[0]
    if (Test-T31HasProperty -InputObject $firstCandidate -Name 'finishReason') {
        $finishReason = [string](Get-T31PropertyValue -InputObject $firstCandidate -Name 'finishReason')
        if ($finishReason -ceq 'MAX_TOKENS') {
            $limitUsageRecord = $null
            if (Test-T31HasProperty -InputObject $ResponseBody -Name 'usageMetadata') {
                $limitUsageMetadata = Get-T31PropertyValue -InputObject $ResponseBody -Name 'usageMetadata'
                try { $limitUsageRecord = New-T31UsageRecord -Provider $Provider -Model $Model -UsageMetadata $limitUsageMetadata } catch { $limitUsageRecord = $null }
            }
            return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason '達每票輸出 token 上限；拒絕接受遭截斷的審查並停止後續呼叫' -FallbackProvider $FallbackProvider -UsageRecord $limitUsageRecord
        }
    }
    $content = Get-T31PropertyValue -InputObject $firstCandidate -Name 'content'
    if ($null -eq $content -or -not (Test-T31HasProperty -InputObject $content -Name 'parts')) {
        return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason 'candidate 缺少 content.parts' -FallbackProvider $FallbackProvider
    }
    $rawParts = Get-T31PropertyValue -InputObject $content -Name 'parts'
    $parts = @($rawParts)
    $textParts = New-Object System.Collections.Generic.List[string]
    foreach ($part in $parts) {
        if (Test-T31HasProperty -InputObject $part -Name 'text') {
            $partText = [string](Get-T31PropertyValue -InputObject $part -Name 'text')
            if (-not [string]::IsNullOrWhiteSpace($partText)) { $textParts.Add($partText) }
        }
    }
    if ($textParts.Count -lt 1) {
        return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason 'candidate.content.parts 沒有可解析文字' -FallbackProvider $FallbackProvider
    }

    $findingDocument = $null
    try {
        $findingDocument = ($textParts.ToArray() -join [Environment]::NewLine) | ConvertFrom-Json
    }
    catch {
        return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason 'candidate 文字不是規定的 finding JSON' -FallbackProvider $FallbackProvider
    }
    if (-not (Test-T31HasProperty -InputObject $findingDocument -Name 'findings')) {
        return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason 'candidate JSON 缺少 findings 陣列' -FallbackProvider $FallbackProvider
    }
    $rawFindings = Get-T31PropertyValue -InputObject $findingDocument -Name 'findings'
    $findings = @($rawFindings)

    foreach ($finding in $findings) {
        foreach ($requiredFindingName in @('id', 'severity', 'summary', 'evidence', 'recommendation')) {
            if (-not (Test-T31HasProperty -InputObject $finding -Name $requiredFindingName)) {
                return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason "finding 缺少必要欄位：$requiredFindingName" -FallbackProvider $FallbackProvider
            }
        }
    }

    if (-not (Test-T31HasProperty -InputObject $ResponseBody -Name 'usageMetadata')) {
        return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason '成功回應缺少 usageMetadata，無法逐次記帳' -FallbackProvider $FallbackProvider
    }
    $usageMetadata = Get-T31PropertyValue -InputObject $ResponseBody -Name 'usageMetadata'
    try {
        $usageRecord = New-T31UsageRecord -Provider $Provider -Model $Model -UsageMetadata $usageMetadata
    }
    catch {
        return New-T31ParseFailure -Provider $Provider -Model $Model -HttpStatus $HttpStatus -Reason $_.Exception.Message -FallbackProvider $FallbackProvider
    }

    return [pscustomobject][ordered]@{
        Success = $true
        ParseFailed = $false
        Provider = $Provider
        Model = $Model
        HttpStatus = $HttpStatus
        Findings = $findings
        Degradation = $null
        UsageRecord = $usageRecord
    }
}

function Write-T31Utf8BomText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($true)))
}

function Write-T31RunArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)]$RawResponseBody,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][ValidateSet('ErrorEnvelope', 'Success')][string]$Scenario
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
    }
    $resultFindingsRaw = $Result.Findings
    $resultFindings = @($resultFindingsRaw)
    $rawPath = Join-Path $OutputDirectory 'raw-response.json'
    $summaryPath = Join-Path $OutputDirectory 'result-summary.json'
    $gateRecordPath = Join-Path $OutputDirectory 'gate-record.json'
    Write-T31Utf8BomText -Path $rawPath -Content (ConvertTo-Json -InputObject $RawResponseBody -Depth 30)

    $usageWritten = $false
    if ($Result.Success) {
        $findingPath = Join-Path $OutputDirectory 'findings.json'
        Write-T31Utf8BomText -Path $findingPath -Content (ConvertTo-Json -InputObject $resultFindings -Depth 30)
        if ($null -ne $Result.UsageRecord) {
            $usagePath = Join-Path $OutputDirectory 'usage-record.json'
            Write-T31Utf8BomText -Path $usagePath -Content (ConvertTo-Json -InputObject $Result.UsageRecord -Depth 30)
            $usageWritten = $true
        }
        $gateRecord = [pscustomobject][ordered]@{
            scenario = $Scenario
            provider = $Result.Provider
            model = $Result.Model
            httpStatus = $Result.HttpStatus
            outcome = 'success'
            findings = $resultFindings
            usage = $Result.UsageRecord
        }
    }
    else {
        $degradationPath = Join-Path $OutputDirectory 'degradation-record.json'
        Write-T31Utf8BomText -Path $degradationPath -Content (ConvertTo-Json -InputObject $Result.Degradation -Depth 20)
        $gateRecordFields = [ordered]@{
            scenario = $Scenario
            provider = $Result.Provider
            model = $Result.Model
            httpStatus = $Result.HttpStatus
            outcome = 'degraded'
            parseFailed = $Result.ParseFailed
            degradation = $Result.Degradation
        }
        if ($null -ne $Result.UsageRecord) {
            # 截斷等「有 usage 的失敗」仍須逐次記帳；Gemini error 外框沒有 usage，故不會進此分支。
            $usagePath = Join-Path $OutputDirectory 'usage-record.json'
            Write-T31Utf8BomText -Path $usagePath -Content (ConvertTo-Json -InputObject $Result.UsageRecord -Depth 30)
            $usageWritten = $true
            $gateRecordFields['usage'] = $Result.UsageRecord
        }
        $gateRecord = [pscustomobject]$gateRecordFields
    }
    Write-T31Utf8BomText -Path $gateRecordPath -Content (ConvertTo-Json -InputObject $gateRecord -Depth 30)

    $summary = [pscustomobject][ordered]@{
        scenario = $Scenario
        provider = $Result.Provider
        model = $Result.Model
        httpStatus = $Result.HttpStatus
        success = $Result.Success
        parseFailed = $Result.ParseFailed
        findingCount = $resultFindings.Count
        usageWritten = $usageWritten
        conclusionTemplateField = if ($Result.Success) { '正常路徑實際回應碼與用量原文' } else { '錯誤體路徑實際回應碼與降級記錄' }
    }
    Write-T31Utf8BomText -Path $summaryPath -Content (ConvertTo-Json -InputObject $summary -Depth 10)
    return $summary
}

if ($MyInvocation.InvocationName -ne '.') {
    Write-Host 'T-31 Gemini 語意解析函式庫；本檔不自行送網路。'
    Write-Host '用法：dot-source .\gemini-e2e-core.ps1，再呼叫 ConvertFrom-T31GeminiResponse 或 Write-T31RunArtifacts。'
    Write-Host '端到端 CLI：.\invoke-gemini-e2e.ps1 -Scenario <ErrorEnvelope|Success> ...'
}
