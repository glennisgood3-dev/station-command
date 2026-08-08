#requires -Version 5.1
<#
.SYNOPSIS
    T-13：離線 mock 測試——沙盒可跑，不連 GitHub。比照 T-10／T-12 offline test 手法：覆蓋
    Invoke-RestMethod 為丟錯的假函式（證明沒有真的連網），dot-source gate-station3.ps1
    -FunctionsOnly 直接呼叫內部函式做函式級別驗證。

.DESCRIPTION
    群組 A：Get-FieldBlock 欄位邊界抽取（含邊界情境：欄位在最後一個、body 為空字串）
    群組 B：Test-Station3FieldsDeep 單票深度檢查（逐欄機制，含 INVALID vs FAIL 分類判準）
    群組 C：Test-Station3TicketSetDeep（票集）——【驗收①】五票情境：缺 basis／缺 depends_on／
            缺測試先行／缺不可逆動作／完整，具名前四張缺項；補齊後重跑 pass
    群組 D：Test-Station3TicketSetDeep（票集）——【驗收⑤】兩票情境：有測試先行文字但未具名 seam／
            未具名獨立預期值來源，各自 fail 並具名缺項
    群組 E：Invoke-Station3ExitChecklistDeep——【驗收⑥】3.seam-confirmed 出口條件項：未提供裁定
            fail-closed；quiz 明確裁定「未確認」仍 fail；三項皆通過才 AllSatisfied=true
    群組 F：【紅燈】-SkipDeepContentCheck 開啟時，兩類斷言真的失敗一次（非檔案缺失型紅燈）：
            F-RED-1：ticket A 的 Classification 不再是 INVALID（退化判準抓不到 executor/basis
            優先分類）；F-RED-2：ticket F／G 不再被抓進 BadTickets（退化判準只認關鍵字存在，
            抓不到 seam／獨立預期值來源具名缺失）。關閉旗標後同一組資料回到綠燈（即群組 C／D）。
    群組 G：gate 佇列項產生（Get-FullLabelSetWithGateFail／New-GateFailQueueItem／
            Add-Station3QueueItemIfAbsent）——本檔扮演 gate 角色，唯一得產生 set-labels 者
    群組 H：run 在站 3 dispatch 拆票 executor——驗證該能力已由 T-12 Get-RunRoutingDefault／
            Select-NextActionableItem 完整覆蓋（重用驗證，非本票重新實作，見 README）
    群組 I：PS 5.1／StrictMode 既知陷阱哨兵（單票 .Count、空陣列、@(函式呼叫) 陷阱）

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t13-offline-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# ⚠️ 命名為 $T13TestDir 而非常見的 $ScriptDir——理由同 gate-station3.ps1／../t12/run-select.ps1
# 的既有註解（實跑抓到的真實 bug 先例）：本檔稍後 dot-source 的 gate-station3.ps1 會 cascade
# dot-source ../t10/gate-check.ps1，該檔內部宣告未加範圍前綴的 $ScriptDir 並指向 t10 自己的目錄；
# dot-source 全程共用同一層作用域，後執行的賦值會覆蓋前面的同名變數——若沿用 $ScriptDir，本檔稍後
# 用它組報告／佇列檔路徑就會誤寫到 build/t10/（本檔開發過程中實跑抓到的真實 bug，非假設）。
$T13TestDir = $PSScriptRoot

$script:TestResults = New-Object System.Collections.ArrayList
$script:FailCount = 0

function Assert-True {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-Host "[PASS] $Name $Detail"
        [void]$script:TestResults.Add("[PASS] $Name $Detail")
    } else {
        Write-Host "[FAIL] $Name $Detail"
        [void]$script:TestResults.Add("[FAIL] $Name $Detail")
        $script:FailCount++
    }
}

# ============================================================
# Mock 基礎設施：覆蓋 Invoke-RestMethod，任何呼叫皆丟錯——證明本檔測試全程未連網
# （本測試只對函式級別直接呼叫，不經 CLI 主流程，故理論上不會觸發任何 HTTP 呼叫；
#  保留此覆蓋是為了「若真的不小心觸發，會立刻炸而非靜默連真網」的防呆）
# ============================================================
function Invoke-RestMethod {
    [CmdletBinding()]
    param([Parameter()] [string]$Uri, [Parameter()] $Headers, [Parameter()] [string]$Method = 'Get', [Parameter()] $Body, [Parameter()] [string]$ContentType)
    throw "MOCK-MISS：t13-offline-test.ps1 只做函式級別測試，不預期任何 HTTP 呼叫，也證明沒有真的連網：$Method $Uri"
}
function Start-Sleep { param([Parameter(Position=0)]$Seconds) }

. (Join-Path $T13TestDir 'gate-station3.ps1') -FunctionsOnly
Set-StrictMode -Version Latest

# ============================================================
# 測試票 body 固件（人造，缺項配置由本檔自行指定——即§3.5 註C要求的「獨立預期值來源」：
# 本測試的預期值＝ Spec §3.5 欄位清單與本檔人為指定的缺項配置，不取自被測 gate-station3.ps1
# 自身的輸出）
# ============================================================
function New-CompleteTicketBody {
    param([string]$Suffix = '')
    return @(
        "REQ-ID: REQ-T13-$Suffix"
        "驗收條件: 可執行——跑 gate-station3.ps1 對此票集，看輸出 PASS 即算過"
        "depends_on: [T-12]"
        "executor: fullstack-developer"
        "basis: 需要真的跑測試的執行體"
        "scope: 站3拆票與票集檢查"
        "測試先行: 先寫斷言取紅燈；seam: gate-station3.ps1 的 Test-Station3FieldsDeep；獨立預期值來源: Spec §3.5 欄位清單與人造票缺項配置"
        "不可逆動作: 無 —— 純檢查與寫 label，可回退"
    ) -join "`n"
}

$bodyE = New-CompleteTicketBody -Suffix 'E'

# A：缺 basis（executor 仍在，觸發 [INVALID]）
$bodyA = (New-CompleteTicketBody -Suffix 'A') -replace "(?m)^basis:.*(`n?)", ''
# B：缺 depends_on 整欄
$bodyB = (New-CompleteTicketBody -Suffix 'B') -replace "(?m)^depends_on:.*(`n?)", ''
# C：缺測試先行整欄
$bodyC = (New-CompleteTicketBody -Suffix 'C') -replace "(?m)^測試先行:.*(`n?)", ''
# D：缺第八欄「不可逆動作」
$bodyD = (New-CompleteTicketBody -Suffix 'D') -replace "(?m)^不可逆動作:.*(`n?)", ''
# F：有測試先行文字但未具名 seam（保留獨立預期值來源）
$bodyF = (New-CompleteTicketBody -Suffix 'F') -replace '測試先行:.*', '測試先行: 先寫斷言取紅燈；獨立預期值來源: Spec §3.5 欄位清單與人造票缺項配置'
# G：有測試先行文字但未具名獨立預期值來源（保留 seam）
$bodyG = (New-CompleteTicketBody -Suffix 'G') -replace '測試先行:.*', '測試先行: 先寫斷言取紅燈；seam: gate-station3.ps1 的 Test-Station3FieldsDeep'

# 補齊版（用於「補齊後重跑 pass」情境）
$bodyAf = New-CompleteTicketBody -Suffix 'Af'
$bodyBf = New-CompleteTicketBody -Suffix 'Bf'
$bodyCf = New-CompleteTicketBody -Suffix 'Cf'
$bodyDf = New-CompleteTicketBody -Suffix 'Df'

# 防呆：確認上面的 -replace 真的移除了目標行（若正規式沒命中，測試資料本身就是假的）
Assert-True -Name "設定檢查：bodyA 不含 'basis:' 行" -Condition ($bodyA -notmatch '(?m)^basis:')
Assert-True -Name "設定檢查：bodyB 不含 'depends_on:' 行" -Condition ($bodyB -notmatch '(?m)^depends_on:')
Assert-True -Name "設定檢查：bodyC 不含 '測試先行:' 行" -Condition ($bodyC -notmatch '(?m)^測試先行:')
Assert-True -Name "設定檢查：bodyD 不含 '不可逆動作:' 行" -Condition ($bodyD -notmatch '(?m)^不可逆動作:')
Assert-True -Name "設定檢查：bodyF 含測試先行但不含 'seam:'" -Condition (($bodyF -match '測試先行') -and ($bodyF -notmatch '(?i)seam[:：]'))
Assert-True -Name "設定檢查：bodyG 含測試先行但不含 '獨立預期值來源:'" -Condition (($bodyG -match '測試先行') -and ($bodyG -notmatch '獨立預期值來源[:：]'))

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 A：Get-FieldBlock 欄位邊界抽取"
Write-Host "===================================================================="

$rA1 = Get-FieldBlock -Body $bodyE -Label 'executor'
Assert-True -Name "A1 Get-FieldBlock('executor') 抽出正確內容且不含下一欄" -Condition ($rA1.Present -and $rA1.Text -eq 'fullstack-developer') -Detail "Text='$($rA1.Text)'"

$rA2 = Get-FieldBlock -Body $bodyE -Label '不可逆動作'
Assert-True -Name "A2 Get-FieldBlock('不可逆動作'，最後一欄，文件結尾為界) 抽出正確內容" -Condition ($rA2.Present -and $rA2.Text -like '無*') -Detail "Text='$($rA2.Text)'"

$rA3 = Get-FieldBlock -Body '' -Label 'executor'
Assert-True -Name "A3 Get-FieldBlock(空字串 body) Present=false" -Condition (-not $rA3.Present)

$rA4 = Get-FieldBlock -Body $bodyE -Label '測試先行'
Assert-True -Name "A4 Get-FieldBlock('測試先行') 含 seam 與獨立預期值來源全文" -Condition (($rA4.Text -match 'seam') -and ($rA4.Text -match '獨立預期值來源')) -Detail "Text='$($rA4.Text)'"

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 B：Test-Station3FieldsDeep 單票深度檢查"
Write-Host "===================================================================="

$rB1 = Test-Station3FieldsDeep -Body $bodyE
Assert-True -Name "B1 完整票 Classification=PASS" -Condition ($rB1.Classification -eq 'PASS') -Detail "Missing=[$(($rB1.Missing | ForEach-Object { $_.Field }) -join ', ')]"

$rB2 = Test-Station3FieldsDeep -Body $bodyA
Assert-True -Name "B2 缺 basis（executor 仍在）Classification=INVALID【核心：缺executor/basis判INVALID】" -Condition ($rB2.Classification -eq 'INVALID') -Detail "Classification=$($rB2.Classification)"
Assert-True -Name "B2b 缺項具名含 basis" -Condition (($rB2.Missing | ForEach-Object { $_.Field }) -contains 'basis')

$bodyNoExec = (New-CompleteTicketBody -Suffix 'NX') -replace "(?m)^executor:.*(`n?)", ''
$rB3 = Test-Station3FieldsDeep -Body $bodyNoExec
Assert-True -Name "B3 缺 executor（basis 仍在）Classification=INVALID" -Condition ($rB3.Classification -eq 'INVALID') -Detail "Classification=$($rB3.Classification)"

$rB4 = Test-Station3FieldsDeep -Body $bodyB
Assert-True -Name "B4 缺 depends_on 整欄 Classification=FAIL（非 INVALID，因 executor/basis 仍在）" -Condition ($rB4.Classification -eq 'FAIL') -Detail "Classification=$($rB4.Classification)"
Assert-True -Name "B4b 缺項具名含 depends_on" -Condition (($rB4.Missing | ForEach-Object { $_.Field }) -contains 'depends_on')

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 C：【驗收①】五票情境——缺 basis／缺 depends_on／缺測試先行／缺不可逆動作／完整"
Write-Host "===================================================================="

$ticketA = [pscustomobject]@{ number = 1; body = $bodyA; RepoString = 'o/r' }
$ticketB = [pscustomobject]@{ number = 2; body = $bodyB; RepoString = 'o/r' }
$ticketC = [pscustomobject]@{ number = 3; body = $bodyC; RepoString = 'o/r' }
$ticketD = [pscustomobject]@{ number = 4; body = $bodyD; RepoString = 'o/r' }
$ticketE = [pscustomobject]@{ number = 5; body = $bodyE; RepoString = 'o/r' }

$rC1 = Test-Station3TicketSetDeep -Tickets @($ticketA, $ticketB, $ticketC, $ticketD, $ticketE)
Assert-True -Name "C1 五票情境 Satisfied=false" -Condition (-not $rC1.Satisfied) -Detail $rC1.Detail
$badNumbersC1 = @($rC1.BadTickets | ForEach-Object { $_.Number })
Assert-True -Name "C1b 具名前四張（#1#2#3#4）皆在 BadTickets，#5 不在" -Condition (($badNumbersC1 -contains 1) -and ($badNumbersC1 -contains 2) -and ($badNumbersC1 -contains 3) -and ($badNumbersC1 -contains 4) -and (-not ($badNumbersC1 -contains 5))) -Detail "Bad=[$($badNumbersC1 -join ', ')]"
Assert-True -Name "C1c 恰 4 張 bad（非誤判多或少）" -Condition (@($rC1.BadTickets).Count -eq 4)

$ticketAf = [pscustomobject]@{ number = 1; body = $bodyAf; RepoString = 'o/r' }
$ticketBf = [pscustomobject]@{ number = 2; body = $bodyBf; RepoString = 'o/r' }
$ticketCf = [pscustomobject]@{ number = 3; body = $bodyCf; RepoString = 'o/r' }
$ticketDf = [pscustomobject]@{ number = 4; body = $bodyDf; RepoString = 'o/r' }
$rC2 = Test-Station3TicketSetDeep -Tickets @($ticketAf, $ticketBf, $ticketCf, $ticketDf, $ticketE)
Assert-True -Name "C2 補齊後重跑 Satisfied=true" -Condition $rC2.Satisfied -Detail $rC2.Detail

$rC3 = Test-Station3TicketSetDeep -Tickets @()
Assert-True -Name "C3 零票 Satisfied=false" -Condition (-not $rC3.Satisfied) -Detail $rC3.Detail

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 D：【驗收⑤】兩票情境——未具名 seam／未具名獨立預期值來源"
Write-Host "===================================================================="

$ticketF = [pscustomobject]@{ number = 6; body = $bodyF; RepoString = 'o/r' }
$ticketG = [pscustomobject]@{ number = 7; body = $bodyG; RepoString = 'o/r' }

$rD1 = Test-Station3TicketSetDeep -Tickets @($ticketF, $ticketG)
Assert-True -Name "D1 兩票（F/G）Satisfied=false" -Condition (-not $rD1.Satisfied) -Detail $rD1.Detail
$badNumbersD1 = @($rD1.BadTickets | ForEach-Object { $_.Number })
Assert-True -Name "D1b F(#6)／G(#7) 皆在 BadTickets" -Condition (($badNumbersD1 -contains 6) -and ($badNumbersD1 -contains 7))

$ticketFResult = $rD1.PerTicket | Where-Object { $_.Number -eq 6 }
$ticketGResult = $rD1.PerTicket | Where-Object { $_.Number -eq 7 }
Assert-True -Name "D2 #6(F) 缺項具名『測試先行-seam具名』" -Condition (($ticketFResult.Missing | ForEach-Object { $_.Field }) -contains '測試先行-seam具名') -Detail "Missing=[$(($ticketFResult.Missing | ForEach-Object { $_.Field }) -join ', ')]"
Assert-True -Name "D2b #6(F) 不缺『測試先行-獨立預期值來源具名』（F 只缺 seam）" -Condition (-not (($ticketFResult.Missing | ForEach-Object { $_.Field }) -contains '測試先行-獨立預期值來源具名'))
Assert-True -Name "D3 #7(G) 缺項具名『測試先行-獨立預期值來源具名』" -Condition (($ticketGResult.Missing | ForEach-Object { $_.Field }) -contains '測試先行-獨立預期值來源具名') -Detail "Missing=[$(($ticketGResult.Missing | ForEach-Object { $_.Field }) -join ', ')]"
Assert-True -Name "D3b #7(G) 不缺『測試先行-seam具名』（G 只缺獨立預期值來源）" -Condition (-not (($ticketGResult.Missing | ForEach-Object { $_.Field }) -contains '測試先行-seam具名'))
Assert-True -Name "D4 F／G 兩張 Classification 皆為 FAIL（非 INVALID，executor/basis 皆在）" -Condition (($ticketFResult.Classification -eq 'FAIL') -and ($ticketGResult.Classification -eq 'FAIL'))

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 E：【驗收⑥】Invoke-Station3ExitChecklistDeep — 3.seam-confirmed 出口條件項"
Write-Host "===================================================================="

$rE1 = Invoke-Station3ExitChecklistDeep -Tickets @($ticketE) -ChecklistOverrides @{}
Assert-True -Name "E1 無任何 override（含 3.seam-confirmed 缺）AllSatisfied=false，fail-closed" -Condition (-not $rE1.AllSatisfied)
$seamItemE1 = $rE1.Items | Where-Object { $_.Id -eq '3.seam-confirmed' }
Assert-True -Name "E1b 3.seam-confirmed 項具名『未提供裁定結果』" -Condition ($seamItemE1.Detail -like '*未提供裁定結果*') -Detail $seamItemE1.Detail

$overridesE2 = @{
    '3.vertical'       = [pscustomobject]@{ Satisfied = $true; Detail = '人工確認：垂直切片' }
    '3.seam-confirmed' = [pscustomobject]@{ Satisfied = $false; Detail = '拆票 quiz 中使用者尚未確認 seam（quiz 逐字記錄核對）' }
}
$rE2 = Invoke-Station3ExitChecklistDeep -Tickets @($ticketE) -ChecklistOverrides $overridesE2
Assert-True -Name "E2 quiz 明確裁定「未確認」⇒ AllSatisfied=false，gate 拒絕推站【核心：⑥】" -Condition (-not $rE2.AllSatisfied)
$seamItemE2 = $rE2.Items | Where-Object { $_.Id -eq '3.seam-confirmed' }
Assert-True -Name "E2b 具名理由來自 quiz 裁定內容（非泛用『未提供』字串）" -Condition ($seamItemE2.Detail -like '*quiz*') -Detail $seamItemE2.Detail

$overridesE3 = @{
    '3.vertical'       = [pscustomobject]@{ Satisfied = $true; Detail = '人工確認：垂直切片' }
    '3.seam-confirmed' = [pscustomobject]@{ Satisfied = $true; Detail = '拆票 quiz 已確認全部票的 seam' }
}
$rE3 = Invoke-Station3ExitChecklistDeep -Tickets @($ticketE) -ChecklistOverrides $overridesE3
Assert-True -Name "E3 三項皆通過（含票集深度檢查）⇒ AllSatisfied=true" -Condition $rE3.AllSatisfied -Detail (($rE3.Items | ForEach-Object { "$($_.Id)=$($_.Satisfied)" }) -join '; ')

$rE4 = Invoke-Station3ExitChecklistDeep -Tickets @($ticketA, $ticketE) -ChecklistOverrides $overridesE3
Assert-True -Name "E4 3.vertical／3.seam-confirmed 皆過但 3.fields 未過（票集仍有壞票）⇒ AllSatisfied=false" -Condition (-not $rE4.AllSatisfied)

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 F：【紅燈】-SkipDeepContentCheck 開啟時，兩類斷言真的失敗一次"
Write-Host "===================================================================="

Write-Host '--- F-RED-1：ticket A（缺 basis）在淺層模式下不再被判 INVALID ---'
$rF_redA = Test-Station3FieldsDeep -Body $bodyA -SkipDeepContentCheck
# 🔴 刻意不走 Assert-True／FailCount：斷言「缺 basis 必須判 INVALID」在 -SkipDeepContentCheck
# 開啟時應該真的失敗（因為淺層模式沒有 INVALID 特化分類邏輯），比照 T-10/T-12 對 RED 段落的處理方式。
if ($rF_redA.Classification -ne 'INVALID') {
    Write-Host "[RED-CONFIRMED] 斷言『缺 basis 必須判 INVALID』如預期失敗：-SkipDeepContentCheck 開啟後，Classification='$($rF_redA.Classification)'（非 INVALID）。證明若無深度檢查的 INVALID 特化分類，缺 executor/basis 的票會被淺層判準誤歸為普通 FAIL（或甚至 PASS），這正是 §3.5『缺 executor／basis 判 [INVALID]』要防的事，不是紙上談兵。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] F-RED-1：SkipDeepContentCheck 開啟後 INVALID 分類真的消失')
} else {
    Write-Host '[UNEXPECTED] F-RED-1 未能重現分類消失（斷言意外通過）——需人工複查 Test-Station3FieldsDeep 的 -SkipDeepContentCheck 分支。'
    [void]$script:TestResults.Add('[FAIL] F-RED-1 未如預期重現')
    $script:FailCount++
}

Write-Host '--- F-RED-2：ticket F／G（缺 seam／缺獨立預期值來源具名）在淺層模式下不再被抓進 BadTickets ---'
$rF_redSet = Test-Station3TicketSetDeep -Tickets @($ticketF, $ticketG) -SkipDeepContentCheck
$badNumbersRed = @($rF_redSet.BadTickets | ForEach-Object { $_.Number })
if (-not (($badNumbersRed -contains 6) -and ($badNumbersRed -contains 7))) {
    Write-Host "[RED-CONFIRMED] 斷言『F(#6)／G(#7) 皆須在 BadTickets』如預期失敗：-SkipDeepContentCheck 開啟後，BadTickets=[$($badNumbersRed -join ', ')]（缺少 #6 與/或 #7）。證明若無 seam／獨立預期值來源的具名子檢查，只檢查『測試先行』關鍵字是否出現，F／G 兩票會被誤判為合格——這正是 §3.5 註B／註C 要防的自證式紅燈與未經確認 seam，不是紙上談兵。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] F-RED-2：SkipDeepContentCheck 開啟後 F/G 未被抓進 BadTickets')
} else {
    Write-Host '[UNEXPECTED] F-RED-2 未能重現漏抓（斷言意外通過）——需人工複查淺層模式的關鍵字判準範圍。'
    [void]$script:TestResults.Add('[FAIL] F-RED-2 未如預期重現')
    $script:FailCount++
}

Write-Host '--- F-GREEN：關閉旗標，同一組資料重來一次（等同群組 B／D，此處獨立再驗證一次做首尾呼應） ---'
$rF_greenA = Test-Station3FieldsDeep -Body $bodyA
Assert-True -Name "F-GREEN-1 關閉 -SkipDeepContentCheck 後，ticket A 恢復判 INVALID" -Condition ($rF_greenA.Classification -eq 'INVALID') -Detail "Classification=$($rF_greenA.Classification)"
$rF_greenSet = Test-Station3TicketSetDeep -Tickets @($ticketF, $ticketG)
$badNumbersGreen = @($rF_greenSet.BadTickets | ForEach-Object { $_.Number })
Assert-True -Name "F-GREEN-2 關閉 -SkipDeepContentCheck 後，F(#6)／G(#7) 恢復被抓進 BadTickets" -Condition (($badNumbersGreen -contains 6) -and ($badNumbersGreen -contains 7)) -Detail "Bad=[$($badNumbersGreen -join ', ')]"

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 G：gate 佇列項產生（唯一得產生 set-labels 者）"
Write-Host "===================================================================="

$issueG1 = [pscustomobject]@{ number = 42; labels = @([pscustomobject]@{ name = 'sc:ticket' }) }
$labelsG1 = Get-FullLabelSetWithGateFail -Issue $issueG1
Assert-True -Name "G1 Get-FullLabelSetWithGateFail 保留既有 label 且加入 sc:gate-fail" -Condition (($labelsG1 -contains 'sc:ticket') -and ($labelsG1 -contains 'sc:gate-fail')) -Detail "[$($labelsG1 -join ', ')]"

$issueG2 = [pscustomobject]@{ number = 43; labels = @([pscustomobject]@{ name = 'sc:ticket' }, [pscustomobject]@{ name = 'sc:gate-fail' }) }
$labelsG2 = Get-FullLabelSetWithGateFail -Issue $issueG2
Assert-True -Name "G2 已有 sc:gate-fail 時不重複加入（去重）" -Condition ((@($labelsG2 | Where-Object { $_ -eq 'sc:gate-fail' })).Count -eq 1) -Detail "[$($labelsG2 -join ', ')]"

$itemG3 = New-GateFailQueueItem -Repo 'o/r' -IssueNumber 42 -Issue $issueG1 -Source 'W-t13'
Assert-True -Name "G3 New-GateFailQueueItem action=set-labels 且 payload 為完整集合" -Condition (($itemG3.action -eq 'set-labels') -and ($itemG3.payload.labels -contains 'sc:gate-fail') -and ($itemG3.payload.labels -contains 'sc:ticket')) -Detail "action=$($itemG3.action)"

$tmpQueuePath = Join-Path $T13TestDir 't13-offline-test-tmp-queue.json'
if (Test-Path -LiteralPath $tmpQueuePath) { Remove-Item -LiteralPath $tmpQueuePath -Force }
$addG4 = Add-Station3QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemG3
Assert-True -Name "G4 首次加入佇列 Added=true" -Condition $addG4.Added -Detail $addG4.Detail
$addG5 = Add-Station3QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemG3
Assert-True -Name "G5 重複加入（同 action+target+source）Added=false（去重）" -Condition (-not $addG5.Added) -Detail $addG5.Detail
$afterG5 = @(Read-QueueFile -QueuePath $tmpQueuePath)
Assert-True -Name "G5b 去重後仍恰 1 筆" -Condition ($afterG5.Count -eq 1)
Assert-True -Name "G5c 佇列項的 action 恰為 set-labels（gate 專屬型別，未混入 run 的 set-assignee/set-ticket-fields）" -Condition ($afterG5[0].action -eq 'set-labels')
Remove-Item -LiteralPath $tmpQueuePath -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 H：run 在站 3 dispatch 拆票 executor（重用驗證，見 README）"
Write-Host "===================================================================="

$rH1 = Get-RunRoutingDefault -Station 'sc:station-3'
Assert-True -Name "H1 站3路由預設 executor 含 planner 與 kongming（拆票＋複核，§5.1）" -Condition (($rH1.Executor -match 'planner') -and ($rH1.Executor -match 'kongming')) -Detail "Executor='$($rH1.Executor)'"

$anchorH2 = [pscustomobject]@{ number = 900; title = 'W-t13-h2 anchor'; body = ''; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-3' }); assignees = @() }
$rH2 = Select-NextActionableItem -AnchorIssue $anchorH2 -Station 'sc:station-3' -WorkId 'W-t13-h2' -PrimaryRepo 'o/r' -ParticipatingRepos @('o/r') -Headers @{}
Assert-True -Name "H2 站3 anchor（尚無票）被選為可動作項，Kind=anchor" -Condition ($rH2.HasCandidate -and $rH2.Selected.Kind -eq 'anchor') -Detail $rH2.Detail
Assert-True -Name "H2b 建議 executor 等於路由表拆票 executor（含 planner／kongming）" -Condition (($rH2.Selected.EffectiveExecutor -match 'planner') -and ($rH2.Selected.EffectiveExecutor -match 'kongming')) -Detail "EffectiveExecutor='$($rH2.Selected.EffectiveExecutor)'"
Assert-True -Name "H2c anchor body 尚無 executor/basis 宣告 ⇒ NeedsBodyWrite=true（待 run-dispatch 寫入，重用 T-12 既有機制）" -Condition $rH2.Selected.NeedsBodyWrite

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 I：PS 5.1／StrictMode 既知陷阱哨兵"
Write-Host "===================================================================="

$singleTicket = @($ticketE)
Assert-True -Name "I1 單票陣列 .Count=1（陷阱①：單一物件無 .Count，須先 @() 包裝）" -Condition ($singleTicket.Count -eq 1)

$rI2 = Test-Station3TicketSetDeep -Tickets $ticketE
Assert-True -Name "I2 傳入單一物件（非陣列）給 Test-Station3TicketSetDeep 仍正確處理（函式內部 @() 防呆）" -Condition $rI2.Satisfied -Detail $rI2.Detail

$rI3 = @(Test-Station3TicketSetDeep -Tickets @() | Select-Object -ExpandProperty BadTickets)
Assert-True -Name "I3 零票時 BadTickets 為空陣列，@(...) 包裝後 .Count=0（陷阱③：@(函式呼叫) 不誤包成 1 筆）" -Condition ($rI3.Count -eq 0)

# ============================================================
# 總結
# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Host "===================================================================="

$reportPath = Join-Path $T13TestDir 't13-offline-test-report.txt'
$reportLines = @("t13-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", "")
$reportLines += $script:TestResults
$reportLines += ""
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
