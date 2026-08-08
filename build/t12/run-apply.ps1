#requires -Version 5.1
<#
.SYNOPSIS
    T-12：`set-assignee`／`set-ticket-fields` 兩型佇列項的套用腳本——手動階段唯一寫入路徑的
    延伸（比照 T-22 `apply-patch.ps1` 對 T-21 `apply-queue.ps1` 的共存模式）。

.DESCRIPTION
    讀佇列檔（與 ../t21/apply-queue.ps1 共用同一份 queue.json，格式見 ../t21/queue-format.md 與
    本目錄 run-queue-ext.md），只處理 action ∈ {set-assignee, set-ticket-fields} 的項目，其餘項目
    原樣保留、原樣寫回（留給 ../t21/apply-queue.ps1 處理）。

    每筆流程：① schema 驗證（四欄皆須存在）→ ② 套用前讀現況比對（冪等，§4.6）：已達成 ⇒
    SKIPPED-ALREADY-SATISFIED，出列 → ③ 未達成 ⇒ PATCH .../issues/{n} → ④ 套用後回驗（issues API
    直讀，非 search）：相符 ⇒ APPLIED-VERIFIED，出列；不符 ⇒ FAILED-VERIFY，留佇列具名回報，
    🚫 不得標記為已套用。

.PARAMETER PatPath
    PAT 檔案路徑。預設 G:\default mount\station_command-key。

.PARAMETER QueuePath
    佇列檔路徑。預設與本腳本同目錄的 queue.json。

.EXAMPLE
    .\run-apply.ps1
.EXAMPLE
    .\run-apply.ps1 -QueuePath 'G:\default mount\station-command-queue.json'
#>

[CmdletBinding()]
param(
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json')
)

$ErrorActionPreference = 'Stop'
# ---------------------------------------------------------------------------
# CLI 參數作用域防火牆（T-12 rework，2026-08-08）
#
# run-common.ps1 會 cascade dot-source ../t10/gate-check.ps1，該檔的 param() 宣告了
# 與本檔同名的參數（$WorkId／$PrimaryRepo／$AnchorIssue／$ParticipatingRepos／
# $PatPath／$FunctionsOnly）。dot-source 共用呼叫端作用域，parameter binder 會把本檔
# 已綁定完成的參數值整組覆蓋成 gate-check.ps1 的預設值，且 $FunctionsOnly 被那次
# `-FunctionsOnly` 綁成 $true ⇒ 檔尾的 `if (-not $FunctionsOnly)` 恆假，CLI 變成
# 「exit 0、零輸出、報告檔不產生」的靜默 no-op。（獨立 verifier 實測確認，非假設。）
#
# 修法：不硬寫變數名，改由本檔自己的 param() AST 動態取出全部宣告參數做快照，
# dot-source 完在 finally 內無條件還原 ⇒ 日後新增第七、第八個參數自動受保護。
# ---------------------------------------------------------------------------
$__runCliScriptBlock = $MyInvocation.MyCommand.ScriptBlock
if ($null -eq $__runCliScriptBlock -or $null -eq $__runCliScriptBlock.Ast.ParamBlock) {
    throw '無法取得目前 CLI 的 param() AST，參數作用域防火牆無法建立。'
}
$__runCliParameterSnapshot = @{}
foreach ($__runCliParameterAst in $__runCliScriptBlock.Ast.ParamBlock.Parameters) {
    $__runCliParameterName = $__runCliParameterAst.Name.VariablePath.UserPath
    # 先取 PSVariable 物件再讀 .Value——不用 Get-Variable -ValueOnly，
    # 避免空陣列值經 pipeline 列舉後被誤判成 $null（PS 5.1 陷阱）。
    $__runCliParameterVariable = Get-Variable -Name $__runCliParameterName -Scope 0 -ErrorAction Stop
    $__runCliParameterSnapshot[$__runCliParameterName] = $__runCliParameterVariable.Value
}
try {
    . (Join-Path $PSScriptRoot 'run-common.ps1')
}
finally {
    foreach ($__runCliParameterName in $__runCliParameterSnapshot.Keys) {
        $__runCliParameterVariable = Get-Variable -Name $__runCliParameterName -Scope 0 -ErrorAction Stop
        $__runCliParameterVariable.Value = $__runCliParameterSnapshot[$__runCliParameterName]
    }
    # 清掉 bootstrap 暫存變數，避免污染 -FunctionsOnly 型的 dot-source 測試環境。
    Remove-Variable -Name '__runCliScriptBlock','__runCliParameterSnapshot','__runCliParameterAst','__runCliParameterName','__runCliParameterVariable' -Scope 0 -ErrorAction SilentlyContinue
}
Set-ConsoleUtf8

$Token = Read-PatToken -PatPath $PatPath
$Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t12-run-apply'

$reportLines = @("run-apply 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "佇列檔：$QueuePath", "")

$Items = Read-QueueFile -QueuePath $QueuePath

if ($null -eq $Items) {
    $msg = "待寫佇列不存在，本批派工動作將重新產生（佇列檔路徑：$QueuePath）。GitHub 既有狀態不受影響。"
    Write-Host $msg
    $reportLines += $msg
    Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'run-apply-report.txt') -Content ($reportLines -join [Environment]::NewLine)
    exit 0
}

$Items = @($Items)

if ($Items.Count -eq 0) {
    $msg = '佇列檔存在但無任何待寫項目（空陣列），無事可做。'
    Write-Host $msg
    $reportLines += $msg
    Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'run-apply-report.txt') -Content ($reportLines -join [Environment]::NewLine)
    exit 0
}

$MyActions = @('set-assignee', 'set-ticket-fields')
$outputItems = New-Object System.Collections.ArrayList
$statusRows = @()
$hadFailure = $false
$mineCount = 0

foreach ($item in $Items) {
    if (-not ($item.PSObject.Properties.Name -contains 'action') -or ($MyActions -notcontains $item.action)) {
        # 不是本腳本認得的動作型別：原樣保留、原樣通過，交由 ../t21/apply-queue.ps1 處理
        [void]$outputItems.Add($item)
        continue
    }

    $mineCount++
    $srcLabel = if ($item.PSObject.Properties.Name -contains 'source') { $item.source } else { '(未知來源)' }
    $targetLabel = try { "$($item.target.repo)#$($item.target.issue)" } catch { '(目標解析失敗)' }

    # ① schema 驗證（四欄皆須存在；本檔不共用 t21 Test-ItemSchema——其白名單不含本兩型）
    $missing = @()
    foreach ($f in @('action', 'target', 'payload', 'source')) {
        if (-not ($item.PSObject.Properties.Name -contains $f) -or $null -eq $item.$f) { $missing += $f }
    }
    $missing = @($missing)
    if ($missing.Count -gt 0) {
        $status = 'FAILED-SCHEMA'
        $detail = "缺少必填欄位：$($missing -join ', ')"
        $statusRows += [pscustomobject]@{ Status = $status; Action = $item.action; Target = $targetLabel; Source = $srcLabel; Detail = $detail }
        Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $item.action, $targetLabel, $srcLabel, $detail)
        [void]$outputItems.Add($item)
        $hadFailure = $true
        continue
    }

    try {
        # ② 套用前讀現況比對（冪等）
        $pre = if ($item.action -eq 'set-assignee') { Test-SetAssigneeSatisfied -Item $item -Headers $Headers } else { Test-SetTicketFieldsSatisfied -Item $item -Headers $Headers }
        if ($pre.Satisfied) {
            $status = 'SKIPPED-ALREADY-SATISFIED'
            $statusRows += [pscustomobject]@{ Status = $status; Action = $item.action; Target = $targetLabel; Source = $srcLabel; Detail = $pre.Detail }
            Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $item.action, $targetLabel, $srcLabel, $pre.Detail)
            continue
        }

        # ③ 未達成 ⇒ 套用
        $repo = Split-RepoString -RepoString $item.target.repo
        if ($item.action -eq 'set-assignee') {
            Invoke-SetAssigneeWrite -Repo $repo -IssueNumber ([int]$item.target.issue) -Assignees $item.payload.assignees -Headers $Headers
        } else {
            Invoke-SetTicketFieldsWrite -Repo $repo -IssueNumber ([int]$item.target.issue) -Body $item.payload.body -Headers $Headers
        }

        # ④ 回驗（issues API 直讀，非 search）
        $post = if ($item.action -eq 'set-assignee') { Test-SetAssigneeSatisfied -Item $item -Headers $Headers } else { Test-SetTicketFieldsSatisfied -Item $item -Headers $Headers }
        if ($post.Satisfied) {
            $status = 'APPLIED-VERIFIED'
            $statusRows += [pscustomobject]@{ Status = $status; Action = $item.action; Target = $targetLabel; Source = $srcLabel; Detail = $post.Detail }
            Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $item.action, $targetLabel, $srcLabel, $post.Detail)
        } else {
            $status = 'FAILED-VERIFY'
            $detail = "套用後回驗不符，留在佇列：$($post.Detail)"
            $statusRows += [pscustomobject]@{ Status = $status; Action = $item.action; Target = $targetLabel; Source = $srcLabel; Detail = $detail }
            Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $item.action, $targetLabel, $srcLabel, $detail)
            [void]$outputItems.Add($item)
            $hadFailure = $true
        }
    }
    catch {
        $status = 'FAILED-APPLY'
        $detail = $_.Exception.Message
        $statusRows += [pscustomobject]@{ Status = $status; Action = $item.action; Target = $targetLabel; Source = $srcLabel; Detail = $detail }
        Write-Host ("[{0,-24}] {1} | {2} | {3} — {4}" -f $status, $item.action, $targetLabel, $srcLabel, $detail)
        [void]$outputItems.Add($item)
        $hadFailure = $true
    }
}

# --- 寫回佇列檔：非本型項目原樣保留＋本型未出列項目，順序不變 ---
Write-QueueFile -QueuePath $QueuePath -Items @($outputItems)

$reportLines += "本輪處理 set-assignee／set-ticket-fields 型項目：$mineCount 筆（其餘型別原樣通過，交由 ../t21/apply-queue.ps1 處理）"
$reportLines += ($statusRows | ForEach-Object { "[{0,-24}] {1} | {2} | {3} — {4}" -f $_.Status, $_.Action, $_.Target, $_.Source, $_.Detail })
$reportLines += ''

$remainingMine = @(@($outputItems) | Where-Object { $_.PSObject.Properties.Name -contains 'action' -and $MyActions -contains $_.action })
$summary = "共處理 {0} 筆：APPLIED-VERIFIED={1} SKIPPED-ALREADY-SATISFIED={2} FAILED-VERIFY={3} FAILED-APPLY={4} FAILED-SCHEMA={5}；剩餘於佇列：{6} 筆" -f `
    $mineCount, `
    (@($statusRows | Where-Object Status -eq 'APPLIED-VERIFIED')).Count, `
    (@($statusRows | Where-Object Status -eq 'SKIPPED-ALREADY-SATISFIED')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-VERIFY')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-APPLY')).Count, `
    (@($statusRows | Where-Object Status -eq 'FAILED-SCHEMA')).Count, `
    $remainingMine.Count
$reportLines += $summary
Write-Host $summary

$reportPath = Join-Path $PSScriptRoot 'run-apply-report.txt'
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($hadFailure) { exit 1 }
exit 0
