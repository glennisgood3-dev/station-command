#requires -Version 5.1
<#
.SYNOPSIS
    T-13：站 3 拆票與八欄位 gate——對票集做 §3.5 八欄位「深度內容檢查」（非僅關鍵字存在），
    含缺 executor／basis 判 [INVALID]、第七欄「測試先行」內容須具名①seam②獨立預期值來源
    （§3.5 註 B／註 C），以及站 3 出口條件新增項「seam 已於拆票 quiz 中經使用者確認」。

.DESCRIPTION
    地基重用（依票面「gate 檢查與 run dispatch 同層且共用票結構」basis，直接重用勿重寫）：
      dot-source ../t12/run-common.ps1——該檔會 cascade dot-source ../t10/gate-check.ps1
      -FunctionsOnly，後者再 cascade dot-source ../t21/queue-common.ps1，一次載齊：
        - t21：Read-PatToken／Get-GithubHeaders／Read-QueueFile／Write-QueueFile／
          Split-RepoString／Get-CurrentIssue／ConvertTo-SafeArray／Set-ConsoleUtf8／
          Write-Utf8BomFile 等純工具與 GitHub 讀取函式。
        - t10：Get-CurrentStation（站別讀取，§3.4 結構性檢查，本檔重用不重寫）。
        - t12：Get-TicketsForWorkWithRepo（帶 RepoString 的票集查詢）、Get-RunRoutingDefault
          （驗證「run 在站 3 dispatch 拆票 executor」——該能力已由 T-12 完整實作，本檔不重複
          實作 dispatch 邏輯，只在 CLI 報告與離線測試中引用驗證，見 README「dispatch 部分」節）。
      本檔**不修改** t10／t12／t21 任何檔案（file ownership 邊界）。

    **本檔淨新增的邏輯**（T-13 的實際交付內容）：
      ① Get-FieldBlock：從票 body 抽出單一欄位的完整區塊文字（欄位邊界以 §3.5 八個 label 的
         下一個 label 或文件結尾為界），供深度內容檢查使用（非 t10 Test-TicketFieldsPresence
         的「關鍵字是否出現在文字任何位置」淺層判法）。
      ② Test-Station3FieldsDeep：逐欄深度檢查，回傳 Classification（PASS／FAIL／INVALID）—
         executor 或 basis 缺漏／空值 ⇒ 一律 INVALID（§3.5：「缺 executor／basis 判 [INVALID]」，
         優先於其餘欄位的一般 FAIL）；depends_on 僅檢查欄位是否存在（§3.5：可為空但欄位必須在）；
         測試先行欄位另分兩個子檢查——seam 具名（註 B）、獨立預期值來源具名（註 C）；
         不可逆動作欄位要求「有／無」值後接非空說明。
      ③ Invoke-Station3ExitChecklistDeep：站 3 出口 checklist，三項——3.fields（本檔深度機械
         檢查）、3.vertical（沿用 t10 既有 RequiresInput override 介面，未新增）、
         **3.seam-confirmed**（新項，RequiresInput：「每張票的測試 seam 已寫下且已於拆票 quiz
         中經使用者確認」——⚠️ 本項只讀取 Commander 已完成的拆票 quiz 裁定結果，不新增任何
         獨立審查步驟或第二個人類 gate，見 station-gate-supplement.md）。
      ④ CLI：讀票集 → 深度檢查 → 全過 ⇒ 具名 PASS 報告 ＋ 產生可餵給 ../t10/gate-advance.ps1
         的 -ChecklistOverridesPath 橋接檔（3.fields／3.vertical／3.seam-confirmed 三鍵，站別
         推進本身仍由 t10 gate-advance.ps1 完成，不重複實作 §3.4 原子性推進邏輯，DRY）；
         未過 ⇒ 具名列出前 N 張問題票與各自缺項，產生 sc:gate-fail 的 set-labels 佇列項
         （anchor 一筆 ＋ 每張問題票各一筆，§3.3「sc:gate-fail 合法載體＝anchor或票」）——
         **只產生佇列項，不直接呼叫 GitHub 寫入 API**（§4.6；本檔扮演 gate 角色，是唯一被允許
         產生 set-labels／close-issue 型佇列項的角色）。

.PARAMETER SkipDeepContentCheck
    ⚠️ 僅供紅燈驗證使用（t13-offline-test.ps1 的 RED 段落），正式流程與一般手動執行絕對不得
    開啟。開啟後 Test-Station3FieldsDeep 退化為「關鍵字是否出現在文字任何位置」的淺層判法
    （比照 t10 Test-TicketFieldsPresence），藉此讓「INVALID 分類」與「seam／獨立預期值來源
    具名」兩類斷言在開啟本旗標時真的失敗一次（見 README／t13-offline-test.ps1）。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程（供 t13-offline-test.ps1 dot-source 呼叫內部函式）。
#>

[CmdletBinding()]
param(
    [string]$WorkId,
    [string]$PrimaryRepo,
    [int]$AnchorIssue,
    [string[]]$ParticipatingRepos = @(),
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$ChecklistOverridesPath = '',
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [string]$BridgeOverridesOutPath = (Join-Path $PSScriptRoot 'station3-overrides-for-t10.json'),
    [switch]$SkipDeepContentCheck,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'

# ⚠️ 命名為 $T13Dir 而非常見的 $ScriptDir／$Script:ScriptDir——理由見 ../t12/run-select.ps1 同段
# 註解（實跑抓到的真實 bug 先例）：下面 dot-source 的 run-common.ps1 會 cascade dot-source
# ../t10/gate-check.ps1，該檔內部宣告未加範圍前綴的 $ScriptDir 並指向 t10 自己的目錄；dot-source
# 全程共用同一層作用域，後執行的賦值會覆蓋前面的同名變數。用一個下游任何被 dot-source 檔案都不會
# 用到的獨有變數名，才能保證整個流程結束後仍指向本檔（t13）自己的目錄。
$T13Dir = $PSScriptRoot
$RunCommonPath = Join-Path $T13Dir '..\t12\run-common.ps1'
if (-not (Test-Path -LiteralPath $RunCommonPath)) {
    throw ("找不到 T-12 地基：{0}。請確認 t13 與 t12 為同層兄弟目錄。" -f $RunCommonPath)
}
# ---------------------------------------------------------------------------
# CLI 參數作用域防火牆（同 T-12 rework 修法，2026-08-08；本檔實測亦為靜默 no-op）
#
# run-common.ps1（T-12）會 cascade dot-source ../t10/gate-check.ps1，該檔的 param() 宣告了
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

# ============================================================
# §3.5 八欄位正典順序（本檔的欄位邊界判定依此表；新增/刪改須同步 station-gate-supplement.md）
# ============================================================
$Script:Station3FieldLabels = @('REQ-ID', '驗收條件', 'depends_on', 'executor', 'basis', 'scope', '測試先行', '不可逆動作')

# ============================================================
# ① 欄位區塊抽取：從 label 開始，抓到「下一個已知 label」或文件結尾為止的完整文字
# PS 5.1／StrictMode 陷阱②③：本函式內部 $findings 一律先 @(...) 賦值再操作，不在賦值式前綴逗號。
# ============================================================
function Get-FieldBlock {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Body,
        [Parameter(Mandatory)][string]$Label
    )
    $escLabel = [regex]::Escape($Label)
    $otherLabels = @($Script:Station3FieldLabels | Where-Object { $_ -ne $Label })
    $otherPattern = ($otherLabels | ForEach-Object { [regex]::Escape($_) }) -join '|'
    # (?s) 讓 . 跨行（欄位內容可能多行）；(?m) 讓 ^ 逐行錨定；non-greedy 抓到下一個 label 起點或字串結尾。
    $pattern = "(?ism)^[ \t]*\**$escLabel\**[:：][ \t]*(.*?)(?=\r?\n[ \t]*\**($otherPattern)\**[:：]|\z)"
    $m = [regex]::Match($Body, $pattern)
    if (-not $m.Success) {
        return [pscustomobject]@{ Present = $false; Text = $null }
    }
    return [pscustomobject]@{ Present = $true; Text = $m.Groups[1].Value.Trim() }
}

# ============================================================
# ② 單票深度檢查——回傳 Classification（PASS／FAIL／INVALID）與逐欄 Findings
# ============================================================
function Test-Station3FieldsDeep {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Body,
        [switch]$SkipDeepContentCheck
    )

    if ($SkipDeepContentCheck) {
        Write-Warning "⚠️⚠️⚠️ -SkipDeepContentCheck 已開啟：退化為淺層關鍵字檢查，僅供紅燈驗證使用，正式流程絕對不得使用。"
        $findings = @()
        foreach ($l in $Script:Station3FieldLabels) {
            $present = [bool]($Body -match [regex]::Escape($l))
            $findings += [pscustomobject]@{ Field = $l; Satisfied = $present; Detail = if ($present) { "『$l』關鍵字存在於票 body 任意位置（淺層模式，僅供紅燈驗證，非正式判準）" } else { "『$l』關鍵字不存在於票 body" } }
        }
        $findings = @($findings)
        $missing = @($findings | Where-Object { -not $_.Satisfied })
        $classification = if ($missing.Count -eq 0) { 'PASS' } else { 'FAIL' }
        return [pscustomobject]@{ Classification = $classification; Findings = $findings; Missing = $missing; ExecutorMissing = $false; BasisMissing = $false }
    }

    $findings = @()

    $reqId = Get-FieldBlock -Body $Body -Label 'REQ-ID'
    $reqIdOk = ($reqId.Present -and -not [string]::IsNullOrWhiteSpace($reqId.Text))
    $findings += [pscustomobject]@{ Field = 'REQ-ID'; Satisfied = $reqIdOk; Detail = if ($reqIdOk) { '存在' } else { '欄位缺漏（label 未出現，或出現但無內容）' } }

    $accept = Get-FieldBlock -Body $Body -Label '驗收條件'
    $acceptOk = ($accept.Present -and -not [string]::IsNullOrWhiteSpace($accept.Text))
    $findings += [pscustomobject]@{ Field = '驗收條件'; Satisfied = $acceptOk; Detail = if ($acceptOk) { '存在' } else { '欄位缺漏（label 未出現，或出現但無內容）' } }

    $dependsOn = Get-FieldBlock -Body $Body -Label 'depends_on'
    $findings += [pscustomobject]@{ Field = 'depends_on'; Satisfied = $dependsOn.Present; Detail = if ($dependsOn.Present) { "欄位存在（§3.5：可為空但欄位必須在；內容='$($dependsOn.Text)'）" } else { '欄位缺漏（label 未出現——§3.5 要求「可為空但欄位必須在」，本票連欄位本身都沒有）' } }

    $executor = Get-FieldBlock -Body $Body -Label 'executor'
    $executorOk = ($executor.Present -and -not [string]::IsNullOrWhiteSpace($executor.Text))
    $findings += [pscustomobject]@{ Field = 'executor'; Satisfied = $executorOk; Detail = if ($executorOk) { "存在：'$($executor.Text)'" } else { '欄位缺漏或為空（§3.5：缺 executor 判 [INVALID]）' } }

    $basis = Get-FieldBlock -Body $Body -Label 'basis'
    $basisOk = ($basis.Present -and -not [string]::IsNullOrWhiteSpace($basis.Text))
    $findings += [pscustomobject]@{ Field = 'basis'; Satisfied = $basisOk; Detail = if ($basisOk) { "存在：'$($basis.Text)'" } else { '欄位缺漏或為空（§3.5：缺 basis 判 [INVALID]）' } }

    $scope = Get-FieldBlock -Body $Body -Label 'scope'
    $scopeOk = ($scope.Present -and -not [string]::IsNullOrWhiteSpace($scope.Text))
    $findings += [pscustomobject]@{ Field = 'scope'; Satisfied = $scopeOk; Detail = if ($scopeOk) { '存在' } else { '欄位缺漏（label 未出現，或出現但無內容）' } }

    $testFirst = Get-FieldBlock -Body $Body -Label '測試先行'
    $testFirstBaseOk = ($testFirst.Present -and -not [string]::IsNullOrWhiteSpace($testFirst.Text))
    $findings += [pscustomobject]@{ Field = '測試先行-存在'; Satisfied = $testFirstBaseOk; Detail = if ($testFirstBaseOk) { '存在' } else { '欄位缺漏或為空（label 未出現，或出現但無內容）' } }

    if ($testFirstBaseOk) {
        $seamOk = [bool]([regex]::IsMatch($testFirst.Text, '(?i)seam[:：]\s*\S'))
        $findings += [pscustomobject]@{ Field = '測試先行-seam具名'; Satisfied = $seamOk; Detail = if ($seamOk) { '已具名 seam（§3.5 註B）' } else { '未具名 seam（§3.5 註B：須寫下本票測試打在哪個 seam；格式：seam: <內容>）' } }

        $srcOk = [bool]([regex]::IsMatch($testFirst.Text, '獨立預期值來源[:：]\s*\S'))
        $findings += [pscustomobject]@{ Field = '測試先行-獨立預期值來源具名'; Satisfied = $srcOk; Detail = if ($srcOk) { '已具名獨立預期值來源（§3.5 註C）' } else { '未具名獨立預期值來源（§3.5 註C：須具名 known-good literal／worked example／spec 之一；格式：獨立預期值來源: <內容>）' } }
    } else {
        $findings += [pscustomobject]@{ Field = '測試先行-seam具名'; Satisfied = $false; Detail = '基礎欄位（測試先行）缺漏，無法檢查 seam 具名' }
        $findings += [pscustomobject]@{ Field = '測試先行-獨立預期值來源具名'; Satisfied = $false; Detail = '基礎欄位（測試先行）缺漏，無法檢查獨立預期值來源具名' }
    }

    $irr = Get-FieldBlock -Body $Body -Label '不可逆動作'
    if (-not $irr.Present -or [string]::IsNullOrWhiteSpace($irr.Text)) {
        $findings += [pscustomobject]@{ Field = '不可逆動作'; Satisfied = $false; Detail = '欄位缺漏（第八欄「不可逆動作：有／無＋說明」未出現；§3.5：八項任一缺漏即站3出口 gate fail）' }
    } else {
        $irrM = [regex]::Match($irr.Text, '(?s)^([有無])[\s—\-：:]*(.+)$')
        if (-not $irrM.Success -or [string]::IsNullOrWhiteSpace($irrM.Groups[2].Value)) {
            $findings += [pscustomobject]@{ Field = '不可逆動作'; Satisfied = $false; Detail = "欄位存在但格式不符或缺說明（§3.5：須為『有／無＋說明』；現有內容='$($irr.Text)'）" }
        } else {
            $findings += [pscustomobject]@{ Field = '不可逆動作'; Satisfied = $true; Detail = "存在：'$($irrM.Groups[1].Value)' —— $($irrM.Groups[2].Value.Trim())" }
        }
    }

    $findings = @($findings)
    $missing = @($findings | Where-Object { -not $_.Satisfied })

    $classification = if ((-not $executorOk) -or (-not $basisOk)) { 'INVALID' } elseif ($missing.Count -gt 0) { 'FAIL' } else { 'PASS' }

    return [pscustomobject]@{ Classification = $classification; Findings = $findings; Missing = $missing; ExecutorMissing = (-not $executorOk); BasisMissing = (-not $basisOk) }
}

# ============================================================
# 票集層級：對整個 work 的票集跑深度檢查，彙整具名缺項
# ============================================================
function Test-Station3TicketSetDeep {
    param(
        [array]$Tickets = @(),
        [switch]$SkipDeepContentCheck
    )
    $Tickets = @($Tickets)
    if ($Tickets.Count -eq 0) {
        return [pscustomobject]@{ Satisfied = $false; Detail = '該 work 尚無任何 sc:ticket，站 3 出口條件不成立（無票可判）'; PerTicket = @(); BadTickets = @() }
    }
    $per = @()
    foreach ($t in $Tickets) {
        $body = if ($t.PSObject.Properties.Name -contains 'body' -and $null -ne $t.body) { $t.body } else { '' }
        $r = Test-Station3FieldsDeep -Body $body -SkipDeepContentCheck:$SkipDeepContentCheck
        $repoStr = if ($t.PSObject.Properties.Name -contains 'RepoString' -and $t.RepoString) { $t.RepoString } else { $null }
        $per += [pscustomobject]@{ Number = $t.number; RepoString = $repoStr; Classification = $r.Classification; Missing = $r.Missing; Findings = $r.Findings }
    }
    $per = @($per)
    $bad = @($per | Where-Object { $_.Classification -ne 'PASS' })
    $satisfied = ($bad.Count -eq 0)
    $detail = if ($satisfied) {
        "共 $($Tickets.Count) 張票，§3.5 八欄位深度檢查（含註B seam／註C獨立預期值來源具名、缺 executor／basis 判 INVALID）全數通過"
    } else {
        $names = @($bad | ForEach-Object {
            $mtext = ($_.Missing | ForEach-Object { "$($_.Field)（$($_.Detail)）" }) -join '、'
            "#$($_.Number)[$($_.Classification)]：$mtext"
        })
        "$($bad.Count)／$($Tickets.Count) 張票未過：" + ($names -join '；')
    }
    return [pscustomobject]@{ Satisfied = $satisfied; Detail = $detail; PerTicket = $per; BadTickets = $bad }
}

# ============================================================
# ③ 站 3 出口 checklist（三項：3.fields 深度機械檢查／3.vertical 沿用 t10 override 介面／
#    3.seam-confirmed 新項）——⚠️ 欄位總數仍為 8（§3.5），本 checklist 是「出口條件」清單，
#    不是「欄位」清單；3.seam-confirmed 是註 B 對第七欄內容的要求落成的出口條件項，非第九欄。
# ============================================================
function Get-Station3ChecklistDefinitionDeep {
    return @(
        [pscustomobject]@{ Id = '3.fields'; Text = '每張票具備 §3.5 全八項欄位（深度內容檢查：含註B seam／註C獨立預期值來源具名、缺executor/basis判INVALID）'; Type = 'Mechanical' }
        [pscustomobject]@{ Id = '3.vertical'; Text = '切片可獨立驗收（垂直非水平）'; Type = 'RequiresInput' }
        [pscustomobject]@{ Id = '3.seam-confirmed'; Text = '每張票的測試 seam 已寫下且已於拆票 quiz 中經使用者確認（§3.5 註B；併入既有 quiz，非獨立步驟，非第二個人類 gate）'; Type = 'RequiresInput' }
    )
}

function Invoke-Station3ExitChecklistDeep {
    param(
        [array]$Tickets = @(),
        [hashtable]$ChecklistOverrides = @{},
        [switch]$SkipDeepContentCheck
    )
    $Tickets = @($Tickets)
    $defs = @(Get-Station3ChecklistDefinitionDeep)
    $items = @()
    foreach ($d in $defs) {
        if ($d.Id -eq '3.fields') {
            $r = Test-Station3TicketSetDeep -Tickets $Tickets -SkipDeepContentCheck:$SkipDeepContentCheck
            $items += [pscustomobject]@{ Id = $d.Id; Text = $d.Text; Type = $d.Type; Satisfied = $r.Satisfied; Detail = $r.Detail; PerTicket = $r.PerTicket; BadTickets = $r.BadTickets }
        } else {
            if ($ChecklistOverrides.ContainsKey($d.Id)) {
                $ov = $ChecklistOverrides[$d.Id]
                $sat = [bool]$ov.Satisfied
                $detail = if ($ov.PSObject -and $ov.PSObject.Properties.Name -contains 'Detail') { $ov.Detail } elseif ($ov -is [hashtable] -and $ov.ContainsKey('Detail')) { $ov['Detail'] } else { '(無附加說明)' }
                $items += [pscustomobject]@{ Id = $d.Id; Text = $d.Text; Type = $d.Type; Satisfied = $sat; Detail = $detail; PerTicket = @(); BadTickets = @() }
            } else {
                $items += [pscustomobject]@{ Id = $d.Id; Text = $d.Text; Type = $d.Type; Satisfied = $false; Detail = '未提供裁定結果（本項需人工／拆票 quiz 裁定，caller 尚未提供 -ChecklistOverridesPath，fail-closed）'; PerTicket = @(); BadTickets = @() }
            }
        }
    }
    $items = @($items)
    $unmet = @($items | Where-Object { -not $_.Satisfied })
    return [pscustomobject]@{ Items = $items; AllSatisfied = ($unmet.Count -eq 0) }
}

# ============================================================
# ④ gate 專屬佇列項產生（本檔扮演 gate 角色：唯一被允許產生 set-labels 型佇列項）
# 只產生佇列項，不直接呼叫 GitHub 寫入 API（§4.6）。
# ============================================================
function Get-FullLabelSetWithGateFail {
    param([Parameter(Mandatory)]$Issue)
    $labelsRaw = ConvertTo-SafeArray -RawValue $Issue.labels
    $labelsRaw = @($labelsRaw)
    $names = @($labelsRaw | ForEach-Object { $_.name })
    if ($names -notcontains 'sc:gate-fail') { $names = @($names + @('sc:gate-fail')) }
    return ,@($names | Select-Object -Unique)
}

function New-GateFailQueueItem {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)]$Issue,
        [Parameter(Mandatory)][string]$Source
    )
    $labels = Get-FullLabelSetWithGateFail -Issue $Issue
    return [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $Repo; issue = $IssueNumber }
        payload = [pscustomobject]@{ labels = @($labels) }
        source  = $Source
    }
}

# 本檔的本地佇列追加函式（比照 T-08／T-10／T-12 各自本地一份的既有先例：產生權自查與去重邏輯
# 屬各 skill 自己的產生階段責任，不下放共用檔改動既有 T-21／T-10／T-12 交付）。
# 🚫 本函式不設任何動作類型白名單限制——理由：本檔本身即扮演 gate 角色（唯一得產生
# set-labels／close-issue 型佇列項者，§3.3／§4.6），與 T-12 run-common.ps1 的
# Add-RunQueueItemGuarded（限制 run 只能產生 set-assignee／set-ticket-fields／comment）
# 是兩種不同的權限主體，不應共用同一份白名單常數。
function Add-Station3QueueItemIfAbsent {
    param([Parameter(Mandatory)][string]$QueuePath, [Parameter(Mandatory)]$Item)
    $existing = Read-QueueFile -QueuePath $QueuePath
    if ($null -eq $existing) { $existing = @() }
    $existing = @($existing)
    $itemTargetJson = $Item.target | ConvertTo-Json -Compress
    $dupe = @($existing | Where-Object {
        $_.action -eq $Item.action -and $_.source -eq $Item.source -and
        (($_.target | ConvertTo-Json -Compress) -eq $itemTargetJson)
    })
    if ($dupe.Count -gt 0) {
        return [pscustomobject]@{ Added = $false; Detail = '佇列中已有相同動作待落地，未重複加入' }
    }
    $updated = @($existing) + @($Item)
    Write-QueueFile -QueuePath $QueuePath -Items $updated
    return [pscustomobject]@{ Added = $true; Detail = '已加入佇列' }
}

# ============================================================
# CLI 主流程
# ============================================================
function Invoke-GateStation3Cli {
    if (-not $WorkId -or -not $PrimaryRepo -or -not $AnchorIssue) {
        throw '直接執行模式須提供 -WorkId -PrimaryRepo -AnchorIssue（或改用 -FunctionsOnly 供測試 dot-source）'
    }
    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t13-gate-station3'

    $participating = if (@($ParticipatingRepos).Count -gt 0) { @($ParticipatingRepos) } else { @($PrimaryRepo) }
    $r = Split-RepoString -RepoString $PrimaryRepo
    $anchor = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $AnchorIssue -Headers $Headers
    if ($null -eq $anchor) { throw "找不到 anchor：$PrimaryRepo#$AnchorIssue" }

    $lines = @("gate-station3 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "WorkId=$WorkId  Anchor=$PrimaryRepo#$AnchorIssue", "")

    $cur = Get-CurrentStation -Issue $anchor
    if (-not $cur.Valid) {
        $lines += "拒絕檢查（§3.4 站別歸因，結構性檢查）：$($cur.Detail)"
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T13Dir 'gate-station3-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 3
    }
    if ($cur.Station -ne 'sc:station-3') {
        $lines += "本檔僅適用站 3 出口檢查（本檔為 ../t10/gate-check.ps1 的站3深度補件，非取代其通用站序判定）：現站='$($cur.Station)'，非 sc:station-3，拒絕檢查。"
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T13Dir 'gate-station3-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 3
    }

    $tickets = Get-TicketsForWorkWithRepo -WorkId $WorkId -ParticipatingRepos $participating -Headers $Headers

    $overrides = @{}
    if ($ChecklistOverridesPath -and (Test-Path -LiteralPath $ChecklistOverridesPath)) {
        $raw = Get-Content -LiteralPath $ChecklistOverridesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $raw.PSObject.Properties) { $overrides[$p.Name] = $p.Value }
    }

    $result = Invoke-Station3ExitChecklistDeep -Tickets $tickets -ChecklistOverrides $overrides -SkipDeepContentCheck:$SkipDeepContentCheck

    foreach ($it in $result.Items) {
        $lines += "[$($it.Type)] $($it.Id)：$(if ($it.Satisfied) { 'PASS' } else { 'FAIL' }) — $($it.Text)"
        if (-not $it.Satisfied) { $lines += "    detail: $($it.Detail)" }
    }
    $lines += ''
    $lines += "整體判定：$(if ($result.AllSatisfied) { 'PASS' } else { 'FAIL' })"

    if ($result.AllSatisfied) {
        $bridge = @{
            '3.fields'         = @{ Satisfied = $true; Detail = 'T-13 深度檢查已通過，橋接供 ../t10/gate-advance.ps1 使用' }
            '3.vertical'       = $overrides['3.vertical']
            '3.seam-confirmed' = $overrides['3.seam-confirmed']
        }
        ($bridge | ConvertTo-Json -Depth 6) | Out-File -LiteralPath $BridgeOverridesOutPath -Encoding utf8
        $lines += "已寫入橋接 overrides 檔供 ../t10/gate-advance.ps1 續行推進站 4：$BridgeOverridesOutPath"
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T13Dir 'gate-station3-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 0
    }

    $fieldsItem = $result.Items | Where-Object { $_.Id -eq '3.fields' }
    $badTickets = @($fieldsItem.BadTickets)
    if ($badTickets.Count -gt 0) {
        $anchorItem = New-GateFailQueueItem -Repo $PrimaryRepo -IssueNumber $AnchorIssue -Issue $anchor -Source $WorkId
        $addAnchor = Add-Station3QueueItemIfAbsent -QueuePath $QueuePath -Item $anchorItem
        $lines += "anchor 落 sc:gate-fail（$($addAnchor.Detail)）"
        foreach ($bt in $badTickets) {
            $btIssue = $tickets | Where-Object { $_.number -eq $bt.Number } | Select-Object -First 1
            if ($null -ne $btIssue -and $bt.RepoString) {
                $btItem = New-GateFailQueueItem -Repo $bt.RepoString -IssueNumber $bt.Number -Issue $btIssue -Source $WorkId
                $addBt = Add-Station3QueueItemIfAbsent -QueuePath $QueuePath -Item $btItem
                $lines += "票 #$($bt.Number) 落 sc:gate-fail（$($addBt.Detail)）"
            }
        }
        $lines += "=> 請執行 ..\t21\apply-queue.ps1 -QueuePath `"$QueuePath`" 落地。"
    }

    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T13Dir 'gate-station3-report.txt') -Content ($lines -join [Environment]::NewLine)
    exit 1
}

if (-not $FunctionsOnly) {
    Invoke-GateStation3Cli
}
