#requires -Version 5.1
<#
.SYNOPSIS
    T-28 異廠呼叫最小適配層。

.DESCRIPTION
    只依格式家族建立唯讀推論請求；provider 端點與家族來自 T-27 廠商登錄表。
    本檔不做成本記帳、不接站 5，也不判斷回應內容是否符合業務語意。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:T28RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)

function ConvertTo-T28ProviderSlug {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Provider)

    $slug = $Provider.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    return $slug.Trim('-')
}

function Import-T28VendorRegistry {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RegistryPath)

    if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
        throw "找不到廠商登錄表：$RegistryPath"
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in [IO.File]::ReadAllLines($RegistryPath)) {
        if ($line -notmatch '^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|$') {
            continue
        }
        $provider = $Matches[1].Trim()
        if ($provider -eq 'provider' -or $provider -match '^-+$') { continue }
        $rows.Add([pscustomobject]@{
            Provider = $provider
            Endpoint = $Matches[2].Trim()
            Authentication = $Matches[3].Trim()
            Family = $Matches[4].Trim()
            Status = $Matches[5].Trim()
        })
    }

    return $rows.ToArray()
}

function Get-T28VendorDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [Parameter(Mandatory = $true)][string]$Provider
    )

    $rawRows = Import-T28VendorRegistry -RegistryPath $RegistryPath
    $rows = @($rawRows)
    $matched = New-Object System.Collections.Generic.List[object]
    foreach ($row in $rows) {
        if ($row.Provider -ieq $Provider) { $matched.Add($row) }
    }
    if ($matched.Count -ne 1) {
        throw "provider 必須在登錄表中恰有一列：$Provider（實得 $($matched.Count) 列）"
    }
    return $matched[0]
}

function Read-T28VendorKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConnectionFolder,
        [Parameter(Mandatory = $true)][string]$Provider
    )

    if (-not (Test-Path -LiteralPath $ConnectionFolder -PathType Container)) { return $null }
    $resolvedConnection = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ConnectionFolder).Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $repoPrefix = $script:T28RepositoryRoot + [IO.Path]::DirectorySeparatorChar
    if ($resolvedConnection.Equals($script:T28RepositoryRoot, [StringComparison]::OrdinalIgnoreCase) -or $resolvedConnection.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw '連接資料夾不得位於 repo 內；拒絕讀取，避免 key 進 repo。'
    }
    $slug = ConvertTo-T28ProviderSlug -Provider $Provider
    $keyPath = Join-Path $ConnectionFolder ($slug + '.key')
    if (-not (Test-Path -LiteralPath $keyPath -PathType Leaf)) { return $null }
    $value = [IO.File]::ReadAllText($keyPath).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value
}

function Join-T28Endpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][string]$Suffix
    )

    $base = $Endpoint.Trim()
    if ($base -notmatch '^https://') { $base = 'https://' + $base }
    return $base.TrimEnd('/') + '/' + $Suffix.TrimStart('/')
}

function New-T28VendorRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ProviderDefinition,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [ValidateRange(1, 4096)][int]$MaxTokens = 256
    )

    if ([string]::IsNullOrWhiteSpace($Model)) { throw 'model 不得為空。' }
    if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'prompt 不得為空。' }
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw 'key 不得為空。' }

    $headers = @{}
    $headers['Content-Type'] = 'application/json; charset=utf-8'
    $uri = $null
    $body = $null

    switch ($ProviderDefinition.Family) {
        'OpenAI-compatible' {
            $headers['Authorization'] = 'Bearer ' + $ApiKey
            $uri = Join-T28Endpoint -Endpoint $ProviderDefinition.Endpoint -Suffix 'chat/completions'
            $body = [ordered]@{
                model = $Model
                messages = @([ordered]@{ role = 'user'; content = $Prompt })
            }
        }
        'Gemini' {
            $headers['x-goog-api-key'] = $ApiKey
            $encodedModel = [Uri]::EscapeDataString($Model)
            $uri = Join-T28Endpoint -Endpoint $ProviderDefinition.Endpoint -Suffix ("models/{0}:generateContent" -f $encodedModel)
            $body = [ordered]@{
                contents = @([ordered]@{
                    role = 'user'
                    parts = @([ordered]@{ text = $Prompt })
                })
            }
        }
        'Anthropic' {
            $headers['x-api-key'] = $ApiKey
            $headers['anthropic-version'] = '2023-06-01'
            $uri = Join-T28Endpoint -Endpoint $ProviderDefinition.Endpoint -Suffix 'v1/messages'
            $body = [ordered]@{
                model = $Model
                max_tokens = $MaxTokens
                messages = @([ordered]@{ role = 'user'; content = $Prompt })
            }
        }
        'Cohere' {
            $headers['Authorization'] = 'Bearer ' + $ApiKey
            $uri = Join-T28Endpoint -Endpoint $ProviderDefinition.Endpoint -Suffix 'chat'
            $body = [ordered]@{ model = $Model; message = $Prompt }
        }
        default { throw "不支援的格式家族：$($ProviderDefinition.Family)" }
    }

    $request = [pscustomobject]@{
        Provider = $ProviderDefinition.Provider
        Family = $ProviderDefinition.Family
        Method = 'POST'
        Uri = $uri
        Headers = $headers
        Body = $body
    }
    Assert-T28ReadOnlyRequest -Request $request
    return $request
}

function Assert-T28ReadOnlyRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Request)

    if ($Request.Method -ne 'POST') { throw '適配層只允許 POST 唯讀推論請求。' }
    $allowed = $false
    switch ($Request.Family) {
        'OpenAI-compatible' { $allowed = $Request.Uri -match '/chat/completions$' }
        'Gemini' { $allowed = $Request.Uri -match '/models/[^/]+:generateContent$' }
        'Anthropic' { $allowed = $Request.Uri -match '/v1/messages$' }
        'Cohere' { $allowed = $Request.Uri -match '/chat$' }
    }
    if (-not $allowed) { throw "非白名單唯讀推論端點：$($Request.Uri)" }

    $serializedBody = $Request.Body | ConvertTo-Json -Depth 20 -Compress
    if ($serializedBody -match '(?i)\b(delete|deploy|upgrade|purchase|billing|payment|tool_choice|tools)\b') {
        throw '請求含寫入、部署、升級、付費或工具呼叫欄位，已拒絕。'
    }
}

function ConvertFrom-T28VendorResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('OpenAI-compatible', 'Gemini', 'Anthropic', 'Cohere')][string]$Family,
        [Parameter(Mandatory = $true)]$ResponseBody
    )

    switch ($Family) {
        'OpenAI-compatible' { return [string]$ResponseBody.choices[0].message.content }
        'Gemini' { return [string]$ResponseBody.candidates[0].content.parts[0].text }
        'Anthropic' { return [string]$ResponseBody.content[0].text }
        'Cohere' { return [string]$ResponseBody.text }
    }
}

function New-T28DegradationRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][string]$FallbackProvider
    )

    return [pscustomobject][ordered]@{
        provider = $Provider
        '失敗原因' = $Reason
        '承接者' = $FallbackProvider
        '生產線繼續' = $true
    }
}

function Write-T28SafeLog {
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$Event,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    if ([string]::IsNullOrWhiteSpace($LogPath)) { return }
    $parent = Split-Path -Parent $LogPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    $safeDetail = $Detail -replace '[\r\n]+', ' '
    $line = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK') provider=$Provider event=$Event detail=$safeDetail"
    if (Test-Path -LiteralPath $LogPath) {
        [IO.File]::AppendAllText($LogPath, [Environment]::NewLine + $line, (New-Object Text.UTF8Encoding($true)))
    }
    else {
        [IO.File]::WriteAllText($LogPath, $line, (New-Object Text.UTF8Encoding($true)))
    }
}

function Invoke-T28DefaultTransport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)][int]$TimeoutSec
    )

    $json = $Request.Body | ConvertTo-Json -Depth 20 -Compress
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Request.Uri -Method $Request.Method -Headers $Request.Headers -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec $TimeoutSec
    }
    catch {
        # Windows PowerShell 5.1 對 4xx／5xx 會先擲 WebException；保留 status code 交上層依規格判斷重試／降級。
        if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
            return [pscustomobject]@{ StatusCode = [int]$_.Exception.Response.StatusCode; Body = [pscustomobject]@{} }
        }
        throw
    }
    $parsed = $response.Content | ConvertFrom-Json
    return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $parsed }
}

function Test-T28TimeoutException {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][Exception]$Exception)

    if ($Exception -is [TimeoutException]) { return $true }
    if ($Exception -is [Net.WebException] -and $Exception.Status -eq [Net.WebExceptionStatus]::Timeout) { return $true }
    if ($null -ne $Exception.InnerException -and $Exception.InnerException -is [TimeoutException]) { return $true }
    return $Exception.Message -match '(?i)timeout|timed out|逾時'
}

function Invoke-T28VendorCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ProviderDefinition,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$ConnectionFolder,
        [Parameter(Mandatory = $true)][string]$FallbackProvider,
        [ValidateRange(1, 300)][int]$TimeoutSec = 30,
        [scriptblock]$Transport,
        [string]$LogPath,
        [switch]$SkipRetry
    )

    $apiKey = Read-T28VendorKey -ConnectionFolder $ConnectionFolder -Provider $ProviderDefinition.Provider
    if ($null -eq $apiKey) {
        $degradation = New-T28DegradationRecord -Provider $ProviderDefinition.Provider -Reason '缺少 key' -FallbackProvider $FallbackProvider
        Write-T28SafeLog -LogPath $LogPath -Provider $ProviderDefinition.Provider -Event 'degrade' -Detail '缺少 key'
        return [pscustomobject]@{ Success = $false; Available = $false; Attempts = 0; RetryCount = 0; Content = $null; Degradation = $degradation }
    }

    $request = New-T28VendorRequest -ProviderDefinition $ProviderDefinition -Model $Model -Prompt $Prompt -ApiKey $apiKey
    if ($null -eq $Transport) { $Transport = ${function:Invoke-T28DefaultTransport} }
    $attempts = 0
    $retryCount = 0
    $lastReason = '未知錯誤'

    while ($attempts -lt 2) {
        $attempts++
        try {
            $transportResult = & $Transport $request $TimeoutSec
            if ($null -eq $transportResult) { throw 'transport 未回傳結果。' }
            $statusCode = [int]$transportResult.StatusCode
            if ($statusCode -ge 200 -and $statusCode -lt 300) {
                $content = ConvertFrom-T28VendorResponse -Family $ProviderDefinition.Family -ResponseBody $transportResult.Body
                if ($content.Contains($apiKey)) {
                    $lastReason = '回應含認證資料，已攔截'
                    break
                }
                Write-T28SafeLog -LogPath $LogPath -Provider $ProviderDefinition.Provider -Event 'success' -Detail "HTTP $statusCode"
                return [pscustomobject]@{ Success = $true; Available = $true; Attempts = $attempts; RetryCount = $retryCount; Content = $content; Degradation = $null }
            }

            if ($statusCode -ge 500 -and $statusCode -le 599) {
                $lastReason = "HTTP $statusCode"
                if ($attempts -eq 1 -and -not $SkipRetry) {
                    $retryCount++
                    Write-T28SafeLog -LogPath $LogPath -Provider $ProviderDefinition.Provider -Event 'retry' -Detail $lastReason
                    continue
                }
            }
            elseif ($statusCode -eq 429) { $lastReason = '配額不足（HTTP 429）' }
            else { $lastReason = "API 錯誤（HTTP $statusCode）" }
            break
        }
        catch {
            $isTimeout = Test-T28TimeoutException -Exception $_.Exception
            if ($isTimeout) { $lastReason = '逾時' } else { $lastReason = 'API 錯誤（傳輸例外）' }
            if ($isTimeout -and $attempts -eq 1 -and -not $SkipRetry) {
                $retryCount++
                Write-T28SafeLog -LogPath $LogPath -Provider $ProviderDefinition.Provider -Event 'retry' -Detail $lastReason
                continue
            }
            break
        }
    }

    $degradation = New-T28DegradationRecord -Provider $ProviderDefinition.Provider -Reason $lastReason -FallbackProvider $FallbackProvider
    Write-T28SafeLog -LogPath $LogPath -Provider $ProviderDefinition.Provider -Event 'degrade' -Detail $lastReason
    return [pscustomobject]@{ Success = $false; Available = $false; Attempts = $attempts; RetryCount = $retryCount; Content = $null; Degradation = $degradation }
}
