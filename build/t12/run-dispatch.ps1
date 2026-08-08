#requires -Version 5.1
<#
.SYNOPSIS
    T-12：派工器——寫票（或 anchor）body 的 executor／basis 欄位（佇列項）→ 指派 assignee 作二元
    開工訊號（佇列項）→ 輸出可 dispatch 目標 → 若事後回報 dispatch 失敗，立即移除該 assignee 並
    具名回報。含第八欄「不可逆動作」檢查（dispatch 前讀取，宣告「有」即停手待裁示）。

.DESCRIPTION
    兩種模式（ParameterSetName）：

    【Dispatch（預設）】重跑 run-select 同一套選件邏輯（dot-source run-common.ps1，不重複維護
    第二份判準）→ 若選中項目 [INVALID]（缺 basis）⇒ 拒絕，不產生任何佇列項 → 若第八欄宣告
    「不可逆動作：有」⇒ dispatch 前停手待裁示（§5.3a 停止條件①），不產生任何佇列項 → 否則：
    需要時產生 set-ticket-fields 佇列項（寫入 executor／basis）、產生 set-assignee 佇列項
    （assignees=[執行身分帳號]）→ 輸出「佇列已就緒，請落地後由 Commander 實際 dispatch」報告。
    **本檔不代 Commander 呼叫 sub-agent**——實際 dispatch（Task 呼叫）是 Claude 主 session 的動作，
    不是 PowerShell 腳本能做的事；本檔只負責「選件、寫欄位、開工訊號」三段編排產出物與報告。

    【ReportFailure（-TargetRepo -TargetIssue -Reason）】供 Commander 在實際 dispatch 失敗後呼叫：
    立即產生「移除 assignee」的佇列項（assignees=[]）並具名回報失敗原因。

    產生權守門：本檔全程只透過 run-common.ps1 的 Add-RunQueueItemGuarded 產生佇列項，該函式會
    自查動作類型是否屬 run 產生權範圍（set-assignee／set-ticket-fields／comment），越權動作一律
    拒絕產生並具名（見 run-queue-ext.md／../t21/enqueue-guard.md）。

.PARAMETER SkipRollback
    ⚠️ 僅供紅燈驗證使用（t12-offline-test.ps1）。開啟後 ReportFailure 模式**不產生**移除 assignee
    的佇列項，用來證明「若無回滾邏輯，assignee 會殘留」。正式流程與一般手動執行絕對不得開啟。

.PARAMETER SkipEnqueueGuard
    ⚠️ 僅供紅燈驗證使用。開啟後略過產生權自查，任何動作類型的佇列項都會被寫入（比照 T-21
    -SkipIdempotencyCheck 命名警示風格）。正式流程與一般手動執行絕對不得開啟。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程。

.EXAMPLE
    .\run-dispatch.ps1 -WorkId W-demo -PrimaryRepo owner/repo -AnchorIssue 1 -AssigneeLogin glennisgood3-dev
.EXAMPLE
    .\run-dispatch.ps1 -TargetRepo owner/repo -TargetIssue 42 -Reason 'sub-agent 逾時無回應' -WorkId W-demo
#>

[CmdletBinding(DefaultParameterSetName = 'Dispatch')]
param(
    [Parameter(ParameterSetName = 'Dispatch', Mandatory)] [string]$WorkId,
    [Parameter(ParameterSetName = 'Dispatch', Mandatory)] [string]$PrimaryRepo,
    [Parameter(ParameterSetName = 'Dispatch', Mandatory)] [int]$AnchorIssue,
    [Parameter(ParameterSetName = 'Dispatch')] [string[]]$ParticipatingRepos = @(),
    [Parameter(ParameterSetName = 'Dispatch')] [string]$AssigneeLogin = '',

    [Parameter(ParameterSetName = 'ReportFailure', Mandatory)] [string]$TargetRepo,
    [Parameter(ParameterSetName = 'ReportFailure', Mandatory)] [int]$TargetIssue,
    [Parameter(ParameterSetName = 'ReportFailure', Mandatory)] [string]$Reason,
    [Parameter(ParameterSetName = 'ReportFailure')] [string]$FailureSource = '',
    [Parameter(ParameterSetName = 'ReportFailure')] [switch]$SkipRollback,

    [Parameter(ParameterSetName = 'Dispatch')]
    [Parameter(ParameterSetName = 'ReportFailure')]
    [switch]$SkipEnqueueGuard,

    [Parameter(ParameterSetName = 'Dispatch')]
    [Parameter(ParameterSetName = 'ReportFailure')]
    [string]$PatPath = 'G:\default mount\station_command-key',

    [Parameter(ParameterSetName = 'Dispatch')]
    [Parameter(ParameterSetName = 'ReportFailure')]
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),

    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
# ⚠️ 命名為 $T12Dir 而非常見的 $ScriptDir——理由見 run-select.ps1 同段註解：dot-source
# run-common.ps1 會 cascade 進 ../t10/gate-check.ps1，該檔也宣告未加 Script: 範圍的 $ScriptDir
# 並指向 t10 目錄，會覆蓋本檔的同名變數（實跑抓到的真實 bug：報告誤寫進 build/t10/）。
$T12Dir = $PSScriptRoot
$RunCommonPath = Join-Path $T12Dir 'run-common.ps1'
if (-not (Test-Path -LiteralPath $RunCommonPath)) { throw "找不到 run-common.ps1：$RunCommonPath" }
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
    . $RunCommonPath
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

function Invoke-RunDispatchCli {
    if ($PSCmdlet.ParameterSetName -eq 'ReportFailure') {
        $src = if ($FailureSource) { $FailureSource } else { "$TargetRepo#$TargetIssue" }
        $r = Invoke-DispatchFailureRollback -TargetRepo $TargetRepo -TargetIssue $TargetIssue -Reason $Reason `
            -QueuePath $QueuePath -Source $src -SkipRollback:$SkipRollback -SkipEnqueueGuard:$SkipEnqueueGuard
        $r.Lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T12Dir 'run-dispatch-report.txt') -Content ($r.Lines -join [Environment]::NewLine)
        switch ($r.Status) {
            'skip-rollback-demo' { exit 6 }
            default { exit 1 }
        }
    }

    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t12-run-dispatch'
    $participating = if (@($ParticipatingRepos).Count -gt 0) { @($ParticipatingRepos) } else { @($PrimaryRepo) }
    $r = Split-RepoString -RepoString $PrimaryRepo
    $anchor = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $AnchorIssue -Headers $Headers
    if ($null -eq $anchor) { throw "找不到 anchor：$PrimaryRepo#$AnchorIssue" }

    $lines = @("run-dispatch 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "WorkId=$WorkId  Anchor=$PrimaryRepo#$AnchorIssue", "")

    $cur = Get-CurrentStation -Issue $anchor
    if (-not $cur.Valid) {
        $lines += "拒絕派工（§3.4 站別歸因，結構性檢查）：$($cur.Detail)"
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T12Dir 'run-dispatch-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 3
    }

    $sel = Select-NextActionableItem -AnchorIssue $anchor -Station $cur.Station -WorkId $WorkId -PrimaryRepo $PrimaryRepo -ParticipatingRepos $participating -Headers $Headers
    if (-not $sel.HasCandidate) {
        $lines += $sel.Detail
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T12Dir 'run-dispatch-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 2
    }

    $effectiveAssignee = if ($AssigneeLogin) { $AssigneeLogin } else {
        try { (Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $Headers -Method Get).login } catch { $null }
    }
    if (-not $effectiveAssignee) {
        $lines += '無法決定 assignee 帳號（-AssigneeLogin 未提供且 /user 讀取失敗），拒絕派工。'
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T12Dir 'run-dispatch-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 3
    }

    $result = Invoke-RunDispatch -Selected $sel.Selected -QueuePath $QueuePath -AssigneeLogin $effectiveAssignee -WorkId $WorkId -SkipEnqueueGuard:$SkipEnqueueGuard
    $lines += $result.Lines
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T12Dir 'run-dispatch-report.txt') -Content ($lines -join [Environment]::NewLine)

    switch ($result.Status) {
        'dispatch-ready'   { exit 0 }
        'invalid'          { exit 4 }
        'irreversible-stop'{ exit 5 }
        'guard-blocked'    { exit 7 }
        default            { exit 1 }
    }
}

if (-not $FunctionsOnly) { Invoke-RunDispatchCli }
