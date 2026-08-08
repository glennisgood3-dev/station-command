#requires -Version 5.1
<#
.SYNOPSIS
    T-07：套用 sc: label scheme 到 GitHub repo（依 labels.json，Spec_station-command_v1.5.md §3.3）。

.DESCRIPTION
    讀取同目錄 labels.json，對每個 label：
      - repo 尚未存在該 label ⇒ POST 建立
      - repo 已存在該 label 但 color/description 不符 ⇒ PATCH 對齊
      - 已存在且一致 ⇒ 略過
    唯一寫入路徑：本機 PowerShell + fine-grained PAT（Cowork cloud 對 GitHub 寫入不通）。

.PARAMETER Owner
    GitHub owner／org。預設 glennisgood3-dev。

.PARAMETER Repo
    GitHub repo 名稱。預設 station-command。

.PARAMETER PatPath
    PAT 檔案路徑（純文字檔，內容即 token）。預設 G:\default mount\station_command-key。

.PARAMETER LabelsJsonPath
    labels.json 路徑。預設與本腳本同目錄的 labels.json。

.EXAMPLE
    .\apply-labels.ps1
    使用全部預設值套用到 glennisgood3-dev/station-command。

.EXAMPLE
    .\apply-labels.ps1 -Owner myorg -Repo myrepo
#>

[CmdletBinding()]
param(
    [string]$Owner = 'glennisgood3-dev',
    [string]$Repo = 'station-command',
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$LabelsJsonPath = (Join-Path $PSScriptRoot 'labels.json')
)

$ErrorActionPreference = 'Stop'

# --- UTF-8 BOM 輸出（避免 Windows PowerShell 主控台把繁中顯示成亂碼；報告檔一律以 UTF-8 BOM 寫出）---
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
try {
    [Console]::OutputEncoding = $Utf8Bom
    $OutputEncoding = $Utf8Bom
} catch {
    Write-Warning "無法設定主控台輸出編碼，繼續執行：$($_.Exception.Message)"
}

function Write-Utf8BomFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8Bom)
}

# --- 讀 PAT ---
if (-not (Test-Path -LiteralPath $PatPath)) {
    throw "PAT 檔案不存在：$PatPath"
}
$Token = (Get-Content -LiteralPath $PatPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "PAT 檔案內容為空：$PatPath"
}

# --- 讀 labels.json ---
if (-not (Test-Path -LiteralPath $LabelsJsonPath)) {
    throw "labels.json 不存在：$LabelsJsonPath"
}
$LabelsDef = (Get-Content -LiteralPath $LabelsJsonPath -Raw | ConvertFrom-Json).labels
if (-not $LabelsDef -or $LabelsDef.Count -eq 0) {
    throw "labels.json 內無 labels 陣列或為空：$LabelsJsonPath"
}

$Headers = @{
    'Authorization'        = "Bearer $Token"
    'Accept'               = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'station-command-t07-apply-labels'
}
$ApiBase = "https://api.github.com/repos/$Owner/$Repo/labels"

$results = @()
$hadFailure = $false

foreach ($label in $LabelsDef) {
    $encodedName = [uri]::EscapeDataString($label.name)
    $labelUrl = "$ApiBase/$encodedName"
    $action = 'unknown'
    $detail = ''

    try {
        $existing = $null
        try {
            $existing = Invoke-RestMethod -Uri $labelUrl -Headers $Headers -Method Get
        } catch {
            $resp = $_.Exception.Response
            if ($resp -and $resp.StatusCode.value__ -eq 404) {
                $existing = $null
            } else {
                throw
            }
        }

        if ($null -eq $existing) {
            $body = @{
                name        = $label.name
                color       = $label.color
                description = $label.description
            } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri $ApiBase -Headers $Headers -Method Post -Body $body -ContentType 'application/json; charset=utf-8' | Out-Null
            $action = 'CREATED'
        }
        elseif ($existing.color -ne $label.color -or $existing.description -ne $label.description) {
            $body = @{
                new_name    = $label.name
                color       = $label.color
                description = $label.description
            } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri $labelUrl -Headers $Headers -Method Patch -Body $body -ContentType 'application/json; charset=utf-8' | Out-Null
            $action = 'UPDATED'
            $detail = "color: '$($existing.color)' -> '$($label.color)'; description changed: $($existing.description -ne $label.description)"
        }
        else {
            $action = 'UNCHANGED'
        }
    }
    catch {
        $action = 'FAILED'
        $detail = $_.Exception.Message
        $hadFailure = $true
    }

    $results += [pscustomobject]@{
        Name   = $label.name
        Action = $action
        Detail = $detail
    }
    Write-Host ("[{0,-9}] {1}" -f $action, $label.name)
}

$reportLines = @("apply-labels 執行報告 — $Owner/$Repo — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')")
$reportLines += ($results | ForEach-Object { "[{0,-9}] {1}  {2}" -f $_.Action, $_.Name, $_.Detail })
$reportPath = Join-Path $PSScriptRoot 'apply-labels-report.txt'
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)

$summary = "共 {0} 個 label：CREATED={1} UPDATED={2} UNCHANGED={3} FAILED={4}" -f `
    $results.Count, `
    ($results | Where-Object Action -eq 'CREATED').Count, `
    ($results | Where-Object Action -eq 'UPDATED').Count, `
    ($results | Where-Object Action -eq 'UNCHANGED').Count, `
    ($results | Where-Object Action -eq 'FAILED').Count
Write-Host $summary
Write-Host "報告已寫入：$reportPath"

if ($hadFailure) {
    exit 1
}
exit 0
