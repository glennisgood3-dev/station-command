<#
.SYNOPSIS
    T-12 rework · CLI 參數作用域防火牆 smoke test（真實子行程，非 dot-source）

.DESCRIPTION
    鎖住獨立 verifier 實測到的兩個症狀：
      症狀 A：run-select.ps1／run-dispatch.ps1 帶齊真實參數執行 ⇒ exit 0、零輸出、報告檔不產生（靜默 no-op）
      症狀 B：run-apply.ps1 會跑，但使用者傳入的 -PatPath 被靜默換成 gate-check.ps1 的預設路徑

    ⚠️ 本檔刻意不以「報告檔是否產生」為 oracle——那會把 GitHub／fixture／檔案輸出邏輯一起拖進來。
    本票鎖的是「CLI 參數保存」與「主流程是否真的進入」兩件事。

    紅燈型態：本檔全部斷言皆為**斷言失敗型**（比對子行程的 exit code 與輸出字串），
    🚫 不是「檔案不存在」或「語法錯誤」這種載入失敗——載入失敗會在前置檢查以 SETUP ERROR 具名擋下。
#>
param(
    [string]$T12SmokeRoot = $PSScriptRoot,
    [string]$T12SmokePwsh = '/opt/pwsh/pwsh'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-T12Cli {
    param(
        [Parameter(Mandatory = $true)][string]$CliPath,
        [Parameter(Mandatory = $true)][string]$SentinelPatPath,
        [Parameter(Mandatory = $true)][string]$PwshPath,
        [switch]$ApplyStyle
    )
    $prev = $ErrorActionPreference
    $raw = $null
    $code = -1
    try {
        # 子行程本來就預期因故意不存在的 PatPath 而失敗；暫時 Continue，
        # 由下方斷言判定結果，避免 native stderr 先終止本測試。
        $ErrorActionPreference = 'Continue'
        if ($ApplyStyle) {
            $raw = & $PwshPath -NoProfile -NonInteractive -File $CliPath -PatPath $SentinelPatPath 2>&1
        } else {
            $raw = & $PwshPath -NoProfile -NonInteractive -File $CliPath -WorkId 'W-t12-scope-smoke' -PrimaryRepo 'acme/repo' -AnchorIssue 7 -PatPath $SentinelPatPath 2>&1
        }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    # 先賦值再 @() 正規化——🚫 不直接寫 @(函式呼叫)（PS 5.1 陷阱③）。
    $items = @($raw)
    $parts = $items | ForEach-Object { [string]$_ }
    $text = $parts -join [Environment]::NewLine
    return [pscustomobject]@{ ExitCode = [int]$code; OutputText = [string]$text }
}

$selectPath   = Join-Path $T12SmokeRoot 'run-select.ps1'
$dispatchPath = Join-Path $T12SmokeRoot 'run-dispatch.ps1'
$applyPath    = Join-Path $T12SmokeRoot 'run-apply.ps1'
foreach ($p in @($selectPath, $dispatchPath, $applyPath)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "SMOKE TEST SETUP ERROR：找不到 $p" }
}
if (-not (Test-Path -LiteralPath $T12SmokePwsh)) { throw "SMOKE TEST SETUP ERROR：找不到 pwsh：$T12SmokePwsh" }

# GUID 保證唯一，用來證明錯誤訊息回顯的是「使用者傳入值」而非 gate-check 預設值。
$sentinel = Join-Path ([System.IO.Path]::GetTempPath()) ('t12-scope-smoke-' + [Guid]::NewGuid().ToString('N') + '.txt')
if (Test-Path -LiteralPath $sentinel) { Remove-Item -LiteralPath $sentinel -Force }

$failures = New-Object 'System.Collections.Generic.List[string]'

# 斷言 1／2：run-select、run-dispatch 不得再是 exit 0 的靜默 no-op
foreach ($case in @(
    @{ Name = 'run-select.ps1';   Path = $selectPath },
    @{ Name = 'run-dispatch.ps1'; Path = $dispatchPath }
)) {
    $r = Invoke-T12Cli -CliPath $case.Path -SentinelPatPath $sentinel -PwshPath $T12SmokePwsh
    if ($r.ExitCode -eq 0) {
        $failures.Add(($case.Name + ' 斷言失敗：帶齊真實參數＋故意不存在的 PatPath，仍得到 exit code 0。表示主流程未執行（$FunctionsOnly 仍被下游 dot-source 污染成 $true）。')) | Out-Null
    }
    if ([string]::IsNullOrWhiteSpace($r.OutputText)) {
        $failures.Add(($case.Name + ' 斷言失敗：輸出為空。靜默 no-op 症狀仍在。')) | Out-Null
    }
}

# 斷言 3：run-apply 必須使用 caller 真正傳入的 PatPath
$ar = Invoke-T12Cli -CliPath $applyPath -SentinelPatPath $sentinel -PwshPath $T12SmokePwsh -ApplyStyle
if ($ar.OutputText.IndexOf($sentinel, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
    $failures.Add('run-apply.ps1 斷言失敗：錯誤輸出未包含 caller 傳入的 PatPath。預期：' + $sentinel + '｜實際輸出：' + $ar.OutputText) | Out-Null
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host '=== T-12 CLI 參數作用域 smoke test：FAILED ===' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host ('- ' + $f) }
    exit 1
}
Write-Host ''
Write-Host ('=== T-12 CLI 參數作用域 smoke test：PASSED（3 條斷言）===')
Write-Host ('    sentinel PatPath = ' + $sentinel)
exit 0
