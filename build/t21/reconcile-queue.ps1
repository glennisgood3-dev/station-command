#requires -Version 5.1
<#
.SYNOPSIS
    T-21：每輪 loop 開頭的對帳出列腳本——只讀 GitHub、不寫 GitHub。

.DESCRIPTION
    比對佇列檔與 GitHub 現況（沿用 apply-queue.ps1 同一套 Test-ItemSatisfied 冪等比對邏輯，
    確保「已達成」的判準只有一份，兩支腳本不會各自維護一份對不上的規則）。
    找出「已由他途落地、應出列」的項目（例如使用者手動在 GitHub 網頁上點掉、或已被別的批次套用過），
    把它們從佇列檔移除；未落地項目原樣保留，本腳本**不嘗試套用**它們（套用是 apply-queue.ps1 的職責）。

    對 GitHub 只發 GET 請求，不發任何 PUT/POST/PATCH——「只讀不寫」指的是對 GitHub；
    本機佇列檔本身會被改寫（移除已出列項），這是允許的（§4.6：「每輪 loop 開頭對帳...已落地項出列」）。

    佇列檔不存在 ⇒ 具名輸出「待寫佇列不存在，本批動作將重新產生」，正常結束（exit 0，非錯誤）。

.PARAMETER PatPath
    PAT 檔案路徑。預設 G:\default mount\station_command-key。

.PARAMETER QueuePath
    佇列檔路徑。預設與本腳本同目錄的 queue.json。

.EXAMPLE
    .\reconcile-queue.ps1
#>

[CmdletBinding()]
param(
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'queue-common.ps1')
Set-ConsoleUtf8

$Token = Read-PatToken -PatPath $PatPath
$Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t21-reconcile-queue'

$Items = Read-QueueFile -QueuePath $QueuePath

$reportLines = @("reconcile-queue 對帳報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "佇列檔：$QueuePath", "")

if ($null -eq $Items) {
    $msg = "待寫佇列不存在，本批動作將重新產生（佇列檔路徑：$QueuePath）。GitHub 既有狀態不受影響。"
    Write-Host $msg
    $reportLines += $msg
    Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'reconcile-queue-report.txt') -Content ($reportLines -join [Environment]::NewLine)
    exit 0
}

# rework：同型防禦性 @() 包裝，理由同 apply-queue.ps1（避免 1 筆佇列項被解卷成純量）。
$Items = @($Items)

if ($Items.Count -eq 0) {
    $msg = "佇列檔存在但無任何待寫項目（空陣列），無需對帳。"
    Write-Host $msg
    $reportLines += $msg
    Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'reconcile-queue-report.txt') -Content ($reportLines -join [Environment]::NewLine)
    exit 0
}

$remaining = New-Object System.Collections.ArrayList
$dequeued = @()
$statusRows = @()

foreach ($item in $Items) {
    $srcLabel = if ($item.PSObject.Properties.Name -contains 'source') { $item.source } else { '(未知來源)' }
    $actionLabel = if ($item.PSObject.Properties.Name -contains 'action') { $item.action } else { '(未知動作)' }
    $targetLabel = try { "$($item.target.repo)#$($item.target.issue)" } catch { '(目標解析失敗)' }

    $schemaCheck = Test-ItemSchema -Item $item
    if (-not $schemaCheck.Valid) {
        # schema 有問題的項目不判定「已落地」，保留讓 apply-queue.ps1 具名回報
        $statusRows += [pscustomobject]@{ Status = 'KEPT-INVALID-SCHEMA'; Action = $actionLabel; Target = $targetLabel; Source = $srcLabel; Detail = $schemaCheck.Detail }
        Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f 'KEPT-INVALID-SCHEMA', $actionLabel, $targetLabel, $srcLabel, $schemaCheck.Detail)
        [void]$remaining.Add($item)
        continue
    }

    try {
        $check = Test-ItemSatisfied -Item $item -Headers $Headers
        if ($check.Satisfied) {
            $status = 'DEQUEUED-ALREADY-LANDED'
            $statusRows += [pscustomobject]@{ Status = $status; Action = $actionLabel; Target = $targetLabel; Source = $srcLabel; Detail = $check.Detail }
            Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $actionLabel, $targetLabel, $srcLabel, $check.Detail)
            $dequeued += $item
            # 已由他途落地 ⇒ 不加入 remaining，出列
        } else {
            $status = 'KEPT-NOT-YET-LANDED'
            $statusRows += [pscustomobject]@{ Status = $status; Action = $actionLabel; Target = $targetLabel; Source = $srcLabel; Detail = $check.Detail }
            Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $actionLabel, $targetLabel, $srcLabel, $check.Detail)
            [void]$remaining.Add($item)
        }
    }
    catch {
        # 讀現況失敗（例如目標 repo/issue 打不到）⇒ 保守保留，不擅自出列，具名回報
        $status = 'KEPT-CHECK-FAILED'
        $detail = $_.Exception.Message
        $statusRows += [pscustomobject]@{ Status = $status; Action = $actionLabel; Target = $targetLabel; Source = $srcLabel; Detail = $detail }
        Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $actionLabel, $targetLabel, $srcLabel, $detail)
        [void]$remaining.Add($item)
    }
}

# --- 寫回佇列檔（只移除已落地項；本機檔案寫入，非 GitHub 寫入） ---
Write-QueueFile -QueuePath $QueuePath -Items @($remaining)

$reportLines += ($statusRows | ForEach-Object { "[{0,-24}] {1} | {2} | {3} — {4}" -f $_.Status, $_.Action, $_.Target, $_.Source, $_.Detail })
$reportLines += ""
$summary = "共 {0} 筆：DEQUEUED-ALREADY-LANDED={1} KEPT-NOT-YET-LANDED={2} KEPT-CHECK-FAILED={3} KEPT-INVALID-SCHEMA={4}；出列後剩餘於佇列：{5} 筆" -f `
    $statusRows.Count, `
    $dequeued.Count, `
    (@($statusRows | Where-Object Status -eq 'KEPT-NOT-YET-LANDED')).Count, `
    (@($statusRows | Where-Object Status -eq 'KEPT-CHECK-FAILED')).Count, `
    (@($statusRows | Where-Object Status -eq 'KEPT-INVALID-SCHEMA')).Count, `
    $remaining.Count
$reportLines += $summary
Write-Host $summary

$reportPath = Join-Path $PSScriptRoot 'reconcile-queue-report.txt'
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

exit 0
