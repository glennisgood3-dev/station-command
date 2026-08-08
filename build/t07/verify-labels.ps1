#requires -Version 5.1
<#
.SYNOPSIS
    T-07：比對 repo 現有 sc: label 與 labels.json 是否完全一致（紅燈用）。

.DESCRIPTION
    列出 repo 現有全部 `sc:` 前綴 label，逐一與 labels.json 比對 name／color／description。
    全中（無缺漏、無多餘、無 color/description 不符）⇒ GREEN；否則 ⇒ RED，並列出差異清單。
    套用前（apply-labels.ps1 執行前）預期必為 RED；套用後預期轉 GREEN。

.PARAMETER Owner
    GitHub owner／org。預設 glennisgood3-dev。

.PARAMETER Repo
    GitHub repo 名稱。預設 station-command。

.PARAMETER PatPath
    PAT 檔案路徑（選填；私有 repo 或避免 rate limit 時建議提供）。預設 G:\default mount\station_command-key。

.PARAMETER LabelsJsonPath
    labels.json 路徑。預設與本腳本同目錄的 labels.json。

.OUTPUTS
    Exit code 0 = GREEN；Exit code 1 = RED。

.EXAMPLE
    .\verify-labels.ps1
#>

[CmdletBinding()]
param(
    [string]$Owner = 'glennisgood3-dev',
    [string]$Repo = 'station-command',
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$LabelsJsonPath = (Join-Path $PSScriptRoot 'labels.json')
)

$ErrorActionPreference = 'Stop'

# --- UTF-8 BOM 輸出 ---
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

# --- 讀 labels.json（必要） ---
if (-not (Test-Path -LiteralPath $LabelsJsonPath)) {
    throw "labels.json 不存在：$LabelsJsonPath"
}
$Expected = (Get-Content -LiteralPath $LabelsJsonPath -Raw | ConvertFrom-Json).labels
if (-not $Expected -or $Expected.Count -eq 0) {
    throw "labels.json 內無 labels 陣列或為空：$LabelsJsonPath"
}

# --- 讀 PAT（選填，讀不到就走未授權請求，僅適用於公開 repo） ---
$Headers = @{
    'Accept'               = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'station-command-t07-verify-labels'
}
if (Test-Path -LiteralPath $PatPath) {
    $Token = (Get-Content -LiteralPath $PatPath -Raw).Trim()
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $Headers['Authorization'] = "Bearer $Token"
    }
} else {
    Write-Warning "PAT 檔案不存在（$PatPath），改用未授權請求（僅適用公開 repo，且可能受 rate limit 限制）。"
}

# --- 撈 repo 現有全部 label（分頁） ---
$Actual = @()
$page = 1
do {
    $url = "https://api.github.com/repos/$Owner/$Repo/labels?per_page=100&page=$page"
    $chunk = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
    $Actual += $chunk
    $page++
} while ($chunk.Count -eq 100)

$ActualSc = $Actual | Where-Object { $_.name -like 'sc:*' }

$expectedByName = @{}
foreach ($e in $Expected) { $expectedByName[$e.name] = $e }
$actualByName = @{}
foreach ($a in $ActualSc) { $actualByName[$a.name] = $a }

$missing = @()      # 在 labels.json 但 repo 沒有
$extra = @()        # 在 repo（sc: 前綴）但 labels.json 沒有
$mismatched = @()   # 兩邊都有但 color/description 不符

foreach ($name in $expectedByName.Keys) {
    if (-not $actualByName.ContainsKey($name)) {
        $missing += $name
    } else {
        $exp = $expectedByName[$name]
        $act = $actualByName[$name]
        $colorDiff = ($act.color -replace '^#','').ToLowerInvariant() -ne $exp.color.ToLowerInvariant()
        $descDiff = ($act.description -as [string]) -ne ($exp.description -as [string])
        if ($colorDiff -or $descDiff) {
            $mismatched += [pscustomobject]@{
                Name = $name
                ExpectedColor = $exp.color
                ActualColor = $act.color
                ExpectedDescription = $exp.description
                ActualDescription = $act.description
            }
        }
    }
}
foreach ($name in $actualByName.Keys) {
    if (-not $expectedByName.ContainsKey($name)) {
        $extra += $name
    }
}

$isGreen = ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $mismatched.Count -eq 0)

$lines = @()
$lines += "verify-labels 比對報告 — $Owner/$Repo — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
$lines += "labels.json 定義數：$($Expected.Count)｜repo 現有 sc: label 數：$($ActualSc.Count)"
$lines += ""

if ($isGreen) {
    $lines += "GREEN：repo 現有 sc: label 與 labels.json 完全一致（無缺漏、無多餘、color/description 皆符）。"
} else {
    $lines += "RED：repo 現有 sc: label 與 labels.json 不一致。差異如下："
    if ($missing.Count -gt 0) {
        $lines += ""
        $lines += "缺漏（labels.json 有、repo 沒有，共 $($missing.Count) 個）："
        $lines += ($missing | Sort-Object | ForEach-Object { "  - $_" })
    }
    if ($extra.Count -gt 0) {
        $lines += ""
        $lines += "多餘（repo 有 sc: 前綴、labels.json 沒有，共 $($extra.Count) 個）："
        $lines += ($extra | Sort-Object | ForEach-Object { "  - $_" })
    }
    if ($mismatched.Count -gt 0) {
        $lines += ""
        $lines += "不符（color 或 description 與 labels.json 不同，共 $($mismatched.Count) 個）："
        foreach ($m in ($mismatched | Sort-Object Name)) {
            $lines += "  - $($m.Name)：color '$($m.ActualColor)' -> 應為 '$($m.ExpectedColor)'；description $(if ($m.ActualDescription -ne $m.ExpectedDescription) { '不符' } else { '相符' })"
        }
    }
}

$reportText = $lines -join [Environment]::NewLine
Write-Host $reportText

$reportPath = Join-Path $PSScriptRoot 'verify-labels-report.txt'
Write-Utf8BomFile -Path $reportPath -Content $reportText
Write-Host ""
Write-Host "報告已寫入：$reportPath"

if ($isGreen) { exit 0 } else { exit 1 }
