#requires -Version 5.1
<#
.SYNOPSIS
    T-12：選件器——驗站別歸因合法（結構性檢查）→ 套三判準（無 blocker／depends_on 已滿足／
    尚無在跑 executor）→ 依路由表定 executor＋basis → 輸出「下一個可動作項＋建議 executor＋basis」。

.DESCRIPTION
    **本檔只讀，不寫任何東西**（Spec §2 run 白名單：讀 GitHub；本檔完全落在這一項內，不觸碰
    assignee／票 body／留言／label 的任何寫入，那些是 run-dispatch.ps1 的職責）。

    站別歸因合法性：本檔重用 ../t10/gate-check.ps1 的 Get-CurrentStation 做結構性檢查（anchor
    是否恰有一個站別 label；髒資料——0 個或多個——⇒ 拒絕選件並具名，對應 Spec §3.4「不合法時...
    /station-run 拒絕選件」）。**時間軸 actor 歸因**（誰改的 label）依 ADR-NP-009 手動階段不生效，
    這部分留給 gate 的復位模式（T-10 範圍），本檔不重複實作。

    三判準與路由表定執行者的核心邏輯在 ./run-common.ps1 的 Select-NextActionableItem，本檔只是
    CLI 外殼（讀 PAT → 讀 GitHub → 呼叫 → 輸出報告）。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程（供 t12-offline-test.ps1／t12-test.ps1 dot-source 呼叫內部函式）。

.EXAMPLE
    .\run-select.ps1 -WorkId W-demo -PrimaryRepo owner/repo -AnchorIssue 1 -ParticipatingRepos owner/repo
#>

[CmdletBinding()]
param(
    [string]$WorkId,
    [string]$PrimaryRepo,
    [int]$AnchorIssue,
    [string[]]$ParticipatingRepos = @(),
    [string]$PatPath = 'G:\default mount\station_command-key',
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
# ⚠️ 命名為 $T12Dir 而非常見的 $ScriptDir——理由：下面 dot-source 的 run-common.ps1 會 cascade
# dot-source ../t10/gate-check.ps1，該檔內部也宣告一個「未加 Script: 範圍」的 $ScriptDir 並指向
# t10 自己的目錄；dot-source 全程共用同一層作用域，後執行的賦值會覆蓋前面的同名變數——若沿用
# $ScriptDir，本檔稍後用它組報告路徑就會誤寫到 build/t10/（實跑抓到的真實 bug，非假設）。
# 用不會被下游任何被 dot-source 檔案用到的獨有變數名，才能保證整個流程結束後仍指向本檔自己的目錄。
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

function Invoke-RunSelectCli {
    if (-not $WorkId -or -not $PrimaryRepo -or -not $AnchorIssue) {
        throw '直接執行模式須提供 -WorkId -PrimaryRepo -AnchorIssue（或改用 -FunctionsOnly 供測試 dot-source）'
    }

    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t12-run-select'

    $participating = if (@($ParticipatingRepos).Count -gt 0) { @($ParticipatingRepos) } else { @($PrimaryRepo) }
    $r = Split-RepoString -RepoString $PrimaryRepo
    $anchor = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $AnchorIssue -Headers $Headers
    if ($null -eq $anchor) { throw "找不到 anchor：$PrimaryRepo#$AnchorIssue" }

    $lines = @("run-select 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "WorkId=$WorkId  Anchor=$PrimaryRepo#$AnchorIssue", "")

    $cur = Get-CurrentStation -Issue $anchor
    if (-not $cur.Valid) {
        $lines += "拒絕選件（§3.4 站別歸因，結構性檢查）：$($cur.Detail)"
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T12Dir 'run-select-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 1
    }
    $lines += "現站：$($cur.Station)"

    $result = Select-NextActionableItem -AnchorIssue $anchor -Station $cur.Station -WorkId $WorkId -PrimaryRepo $PrimaryRepo -ParticipatingRepos $participating -Headers $Headers
    $lines += $result.Detail
    $lines += ''

    if ($result.HasCandidate) {
        $s = $result.Selected
        $lines += "已選出：$($s.Kind) $($s.RepoString)#$($s.Number)「$($s.Title)」"
        $lines += "建議 executor：$($s.EffectiveExecutor)"
        $lines += "basis：$($s.EffectiveBasis)"
        $lines += "需寫入 body：$($s.NeedsBodyWrite)　票已 [INVALID]：$($s.Invalid)$(if ($s.Invalid) { ' — ' + $s.InvalidReason } else { '' })"
    }

    $rejectedList = @($result.Rejected)
    if ($rejectedList.Count -gt 0) {
        $lines += ''
        $lines += "被排除項目（共 $($rejectedList.Count) 項）："
        foreach ($rj in $rejectedList) {
            $lines += "  - $($rj.Kind) $($rj.RepoString)#$($rj.Number)：$($rj.RejectReasons -join '；')"
        }
    }

    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T12Dir 'run-select-report.txt') -Content ($lines -join [Environment]::NewLine)

    if ($result.HasCandidate) { exit 0 } else { exit 2 }
}

if (-not $FunctionsOnly) { Invoke-RunSelectCli }
