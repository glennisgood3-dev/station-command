#requires -Version 5.1

Set-StrictMode -Version Latest

function Get-T28ReachabilityAssessment {
    [CmdletBinding()]
    param(
        [AllowNull()][Nullable[int]]$StatusCode,
        [AllowNull()][string]$NetworkFailure,
        [int[]]$ProbeQualityStatusCodes = @(200, 401, 403, 429)
    )

    if ($null -eq $StatusCode) {
        $reason = '未取得 HTTP 回應'
        if (-not [string]::IsNullOrWhiteSpace($NetworkFailure)) { $reason = $NetworkFailure }
        return [pscustomobject]@{
            Reachable = $false
            ReachabilityLevel = 'FAIL'
            ReachabilityReason = $reason
            ProbeQuality = 'N/A'
            ProbeQualityReason = '未取得 provider HTTP 回應，無法評估 probe 端點形狀'
            StatusCode = $null
        }
    }

    $code = [int]$StatusCode
    if ($code -eq 421) {
        return [pscustomobject]@{
            Reachable = $false
            ReachabilityLevel = 'FAIL'
            ReachabilityReason = 'proxy 攔截（HTTP 421）'
            ProbeQuality = 'N/A'
            ProbeQualityReason = '回應來自 proxy 攔截，並非 provider 端點'
            StatusCode = $code
        }
    }

    $quality = 'WARN'
    $qualityReason = 'probe 路徑或方法可能不適用於該 provider'
    if ($ProbeQualityStatusCodes -contains $code) {
        $quality = 'PASS'
        $qualityReason = '狀態碼落在端點形狀正確區間 200／401／403／429'
    }

    return [pscustomobject]@{
        Reachable = $true
        ReachabilityLevel = 'PASS'
        ReachabilityReason = '已取得 HTTP 回應，網路層與伺服器可達'
        ProbeQuality = $quality
        ProbeQualityReason = $qualityReason
        StatusCode = $code
    }
}
