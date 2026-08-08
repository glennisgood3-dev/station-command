#requires -Version 5.1
<#
.SYNOPSIS
    T-15a：離線測試——沙盒可跑，不連 GitHub、不執行任何被測系統（判讀對象全為靜態結構化 JSON
    與程式內組出的 prompt 文字）。

.DESCRIPTION
    群組 A：Test-AxisInputSeparation（軸A/軸B 合格輸入、spec 洩漏、smell 洩漏、未知 kind）
    群組 B：Test-AxisAStandardsNamed（檔案+版本、無落檔規範聲明、兩者皆缺）
    群組 C：Test-ReportsNotMerged（無禁止欄位、出現 mergedFindings）
    群組 D：Test-FindingsRemediated（hard 有/無證據、judgement 有/無裁決、非法 severity）
    群組 E：Test-Station5VerifierIndependent（不同/相同/Commander/空值）
    群組 F：Test-RemediationVerified ＋【紅燈】RED-PROOF：-SkipRemediationCheck 讓「未經復驗即
            結案必須被拒絕」這條斷言對著 fixtures/not-reverified.json 真的失敗一次，再關閉取得綠
    群組 G：Test-IsolationDisclaimer（已落檔解除／未落檔有字串／未落檔缺字串）
    群組 H：Test-ClosingSummary（3/1 通過、跨軸贏家、缺 worst、筆數不符）
    群組 I：Read-Station5Submission（十四份 fixture 皆可讀取；缺欄位擲例外）
    群組 J：Invoke-Station5Check 整合——十四份 fixture 逐一對應驗收，含變因隔離驗證
    群組 K：New-CloseTicketQueueItem／Add-QueueItemIfAbsent（schema 正確、冪等去重）
    群組 L：Test-TicketClosed／Find-LastCloseEvent／Test-CloseActorLegit（驗收④後段，
            deferred-to-CI 結構驗證，比照 T-10/T-14 既有先例）
    群組 M：PS 5.1 / StrictMode 陣列陷阱（0/1/N 筆 findings、單元素陣列回傳）
    群組 N：station5-dispatch-prep——New-AxisAPrompt／New-AxisBPrompt 結構性簽章保證（無法傳入
            禁止參數）＋ Test-PromptTextMarkers 對真實 fowler-smells.md／Spec 原文組出的真實
            prompt 跑第二道防線，並留存為可核對的證據檔（驗收①③的具體證據位置）

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t15a-offline-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# ⚠️ 用 $T15aTestDir 而非 $ScriptDir／$T15aCheckDir／$T15aPrepDir——理由見 station5-check.ps1／
# station5-dispatch-prep.ps1 檔頭註解：dot-source 會 cascade 進 ../t10/gate-check.ps1（宣告
# 未加 Script: 範圍的 $ScriptDir），全程共用同一層作用域會覆蓋本檔同名變數（T-12/T-14 皆記載
# 過的實跑 bug：報告誤寫進錯誤目錄）。
$T15aTestDir = $PSScriptRoot
$FixturesDir = Join-Path $T15aTestDir 'fixtures'

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
# Mock 基礎設施：本檔絕大多數函式不連網；若任何函式意外呼叫 Invoke-RestMethod，覆蓋版本會立刻
# 噴錯而非悄悄連真網（比照 T-14 既有先例）。
# ============================================================
function Invoke-RestMethod {
    [CmdletBinding()]
    param([Parameter()] [string]$Uri, [Parameter()] $Headers, [Parameter()] [string]$Method = 'Get', [Parameter()] $Body, [Parameter()] [string]$ContentType)
    throw "MOCK-MISS：t15a-offline-test.ps1 不應觸發任何真實 GitHub 呼叫（本票判讀對象為靜態結構化 JSON 與 prompt 文字），但收到請求：$Method $Uri"
}

. (Join-Path $T15aTestDir 'station5-check.ps1') -SubmissionPath 'unused' -Repo 'unused' -Issue 1 -FunctionsOnly
Set-StrictMode -Version Latest

# ============================================================
Write-Host '===================================================================='
Write-Host '群組 A：Test-AxisInputSeparation'
Write-Host '===================================================================='

$validA = @(
    [pscustomobject]@{ kind = 'diff'; value = 'diff --git a/x b/x' }
    [pscustomobject]@{ kind = 'standards'; value = 'docs/STANDARDS.md' }
    [pscustomobject]@{ kind = 'smell-baseline'; value = '12 條基線全文' }
)
$rA1 = Test-AxisInputSeparation -Axis 'AxisA' -InputList $validA
Assert-True -Name 'A1 軸A合格輸入（diff+standards+smell-baseline）⇒ Satisfied=true' -Condition $rA1.Satisfied -Detail $rA1.Detail

$validB = @(
    [pscustomobject]@{ kind = 'diff'; value = 'diff --git a/x b/x' }
    [pscustomobject]@{ kind = 'spec'; value = 'Spec §5.2 逐項對照' }
)
$rA2 = Test-AxisInputSeparation -Axis 'AxisB' -InputList $validB
Assert-True -Name 'A2 軸B合格輸入（diff+spec）⇒ Satisfied=true' -Condition $rA2.Satisfied -Detail $rA2.Detail

$specLeakA = @(
    [pscustomobject]@{ kind = 'diff'; value = 'diff --git a/x b/x' }
    [pscustomobject]@{ kind = 'spec'; value = 'Spec §5.2 全文摘錄' }
)
$rA3 = Test-AxisInputSeparation -Axis 'AxisA' -InputList $specLeakA
Assert-True -Name 'A3【核心：驗收①】軸A出現 kind=spec ⇒ Satisfied=false（禁止 spec 原文洩漏）' -Condition (-not $rA3.Satisfied) -Detail $rA3.Detail

$smellLeakB = @(
    [pscustomobject]@{ kind = 'diff'; value = 'diff --git a/x b/x' }
    [pscustomobject]@{ kind = 'smell-baseline'; value = '12 條 Fowler smell 基線全文' }
)
$rA4 = Test-AxisInputSeparation -Axis 'AxisB' -InputList $smellLeakB
Assert-True -Name 'A4【核心：驗收①】軸B出現 kind=smell-baseline ⇒ Satisfied=false（禁止基線洩漏）' -Condition (-not $rA4.Satisfied) -Detail $rA4.Detail

$unknownKind = @([pscustomobject]@{ kind = 'notes'; value = '隨便寫的東西' })
$rA5 = Test-AxisInputSeparation -Axis 'AxisA' -InputList $unknownKind
Assert-True -Name 'A5 未知 kind ⇒ Satisfied=false（fail-closed，不在白名單內一律拒絕）' -Condition (-not $rA5.Satisfied) -Detail $rA5.Detail

$standardsLeakB = @(
    [pscustomobject]@{ kind = 'diff'; value = 'diff --git a/x b/x' }
    [pscustomobject]@{ kind = 'standards'; value = 'docs/STANDARDS.md' }
)
$rA6 = Test-AxisInputSeparation -Axis 'AxisB' -InputList $standardsLeakB
Assert-True -Name 'A6 軸B出現 kind=standards ⇒ Satisfied=false（軸B只准 diff/spec）' -Condition (-not $rA6.Satisfied) -Detail $rA6.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 B：Test-AxisAStandardsNamed'
Write-Host '===================================================================='

$axisAWithFile = [pscustomobject]@{ standardsFileUsed = 'docs/STANDARDS.md'; standardsVersion = 'v3' }
$rB1 = Test-AxisAStandardsNamed -AxisA $axisAWithFile
Assert-True -Name 'B1 具名檔案+版本 ⇒ Satisfied=true' -Condition $rB1.Satisfied -Detail $rB1.Detail

$axisANoStd = [pscustomobject]@{ noStandardsStatement = '該repo無落檔規範，本輪僅以基線審' }
$rB2 = Test-AxisAStandardsNamed -AxisA $axisANoStd
Assert-True -Name 'B2 明文「無落檔規範」聲明 ⇒ Satisfied=true' -Condition $rB2.Satisfied -Detail $rB2.Detail

$axisAEmpty = [pscustomobject]@{ standardsFileUsed = ''; standardsVersion = '' }
$rB3 = Test-AxisAStandardsNamed -AxisA $axisAEmpty
Assert-True -Name 'B3 兩者皆缺 ⇒ Satisfied=false（fail-closed）' -Condition (-not $rB3.Satisfied) -Detail $rB3.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 C：Test-ReportsNotMerged'
Write-Host '===================================================================='

$cleanSub = [pscustomobject]@{ ticket = 'X'; axisA = @{}; axisB = @{} }
$rC1 = Test-ReportsNotMerged -Submission $cleanSub
Assert-True -Name 'C1 無禁止欄位 ⇒ Satisfied=true' -Condition $rC1.Satisfied -Detail $rC1.Detail

$mergedSub = [pscustomobject]@{ ticket = 'X'; axisA = @{}; axisB = @{}; mergedFindings = @() }
$rC2 = Test-ReportsNotMerged -Submission $mergedSub
Assert-True -Name 'C2【核心】出現 mergedFindings ⇒ Satisfied=false（兩軸不得合併重排）' -Condition (-not $rC2.Satisfied) -Detail $rC2.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 D：Test-FindingsRemediated'
Write-Host '===================================================================='

$goodFindings = @(
    [pscustomobject]@{ id = 'F1'; severity = 'hard'; remediationEvidence = 'commit abc'; decision = '' }
    [pscustomobject]@{ id = 'F2'; severity = 'judgement'; remediationEvidence = ''; decision = '接受現狀' }
)
$rD1 = Test-FindingsRemediated -AxisLabel '軸X' -Findings $goodFindings
Assert-True -Name 'D1 hard有證據+judgement有裁決 ⇒ Satisfied=true' -Condition $rD1.Satisfied -Detail $rD1.Detail

$badHard = @([pscustomobject]@{ id = 'F3'; severity = 'hard'; remediationEvidence = ''; decision = '' })
$rD2 = Test-FindingsRemediated -AxisLabel '軸X' -Findings $badHard
Assert-True -Name 'D2 hard缺證據 ⇒ Satisfied=false' -Condition (-not $rD2.Satisfied) -Detail $rD2.Detail

$badJudgement = @([pscustomobject]@{ id = 'F4'; severity = 'judgement'; remediationEvidence = ''; decision = '' })
$rD3 = Test-FindingsRemediated -AxisLabel '軸X' -Findings $badJudgement
Assert-True -Name 'D3 judgement缺裁決 ⇒ Satisfied=false' -Condition (-not $rD3.Satisfied) -Detail $rD3.Detail

$badSeverity = @([pscustomobject]@{ id = 'F5'; severity = 'minor'; remediationEvidence = ''; decision = '' })
$rD4 = Test-FindingsRemediated -AxisLabel '軸X' -Findings $badSeverity
Assert-True -Name 'D4 非法 severity 值 ⇒ Satisfied=false' -Condition (-not $rD4.Satisfied) -Detail $rD4.Detail

$rD5 = Test-FindingsRemediated -AxisLabel '軸X' -Findings @()
Assert-True -Name 'D5 空 findings 陣列（PS5.1陷阱：0筆） ⇒ Satisfied=true（無條目可違規）' -Condition $rD5.Satisfied -Detail $rD5.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 E：Test-Station5VerifierIndependent'
Write-Host '===================================================================='

$rE1 = Test-Station5VerifierIndependent -Executor 'fullstack-developer' -Verifier 'tester'
Assert-True -Name 'E1 不同身分 ⇒ Satisfied=true' -Condition $rE1.Satisfied -Detail $rE1.Detail

$rE2 = Test-Station5VerifierIndependent -Executor 'fullstack-developer' -Verifier 'fullstack-developer'
Assert-True -Name 'E2【核心：驗收③】相同身分 ⇒ Satisfied=false' -Condition (-not $rE2.Satisfied) -Detail $rE2.Detail

$rE3 = Test-Station5VerifierIndependent -Executor 'fullstack-developer' -Verifier 'Commander'
Assert-True -Name 'E3【核心：驗收③】verifier=Commander ⇒ Satisfied=false' -Condition (-not $rE3.Satisfied) -Detail $rE3.Detail

$rE4 = Test-Station5VerifierIndependent -Executor 'fullstack-developer' -Verifier '  主 session  '
Assert-True -Name 'E4 verifier=「主 session」（含空白正規化）⇒ Satisfied=false' -Condition (-not $rE4.Satisfied) -Detail $rE4.Detail

$rE5 = Test-Station5VerifierIndependent -Executor 'fullstack-developer' -Verifier ''
Assert-True -Name 'E5 verifier 為空 ⇒ Satisfied=false（fail-closed）' -Condition (-not $rE5.Satisfied) -Detail $rE5.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 F：Test-RemediationVerified（含【紅燈】RED-PROOF）'
Write-Host '===================================================================='

$remGood1 = [pscustomobject]@{ verified = $true; method = 'verifier-rerun'; evidence = 'verifier 重跑結果：全過' }
$rF1 = Test-RemediationVerified -Remediation $remGood1
Assert-True -Name 'F1 verifier-rerun 已復驗 ⇒ Satisfied=true' -Condition $rF1.Satisfied -Detail $rF1.Detail

$remGood2 = [pscustomobject]@{ verified = $true; method = 'two-axis-supplement'; evidence = '兩軸補審一輪：無新增 hard finding' }
$rF2 = Test-RemediationVerified -Remediation $remGood2
Assert-True -Name 'F2 two-axis-supplement 已復驗 ⇒ Satisfied=true' -Condition $rF2.Satisfied -Detail $rF2.Detail

$remBadNotVerified = [pscustomobject]@{ verified = $false; method = ''; evidence = '' }
$rF3 = Test-RemediationVerified -Remediation $remBadNotVerified
Assert-True -Name 'F3【核心：驗收②】verified=false ⇒ Satisfied=false（未經復驗即結案，拒絕）' -Condition (-not $rF3.Satisfied) -Detail $rF3.Detail

$remBadMethod = [pscustomobject]@{ verified = $true; method = 'eyeballed-it'; evidence = '看了一下覺得沒問題' }
$rF4 = Test-RemediationVerified -Remediation $remBadMethod
Assert-True -Name 'F4 method 不合法（非二擇一之一）⇒ Satisfied=false' -Condition (-not $rF4.Satisfied) -Detail $rF4.Detail

$remBadNoEvidence = [pscustomobject]@{ verified = $true; method = 'verifier-rerun'; evidence = '' }
$rF5 = Test-RemediationVerified -Remediation $remBadNoEvidence
Assert-True -Name 'F5 evidence 為空 ⇒ Satisfied=false（fail-closed）' -Condition (-not $rF5.Satisfied) -Detail $rF5.Detail

$rF6 = Test-RemediationVerified -Remediation $remBadNotVerified -SkipRemediationCheck
Assert-True -Name 'F6 -SkipRemediationCheck 開啟 ⇒ 一律 Satisfied=true（僅供紅燈驗證用途本身的正確性）' -Condition $rF6.Satisfied -Detail $rF6.Detail

Write-Host ''
Write-Host '--- 【紅燈】RED-PROOF：對 fixtures/not-reverified.json 開啟 -SkipRemediationCheck，讓「未經復驗即結案必須被拒絕」這條斷言真的失敗一次 ---'
$subNotReverified = Read-Station5Submission -Path (Join-Path $FixturesDir 'not-reverified.json')
$redResult = Invoke-Station5Check -Submission $subNotReverified -SkipRemediationCheck
# 🔴 刻意不走 Assert-True／FailCount：這裡的斷言「未經復驗即結案必須被拒絕（OverallPass=false）」
# 在 -SkipRemediationCheck 開啟時**應該失敗**（那正是紅燈的定義：證明沒有②查核時，未復驗的
# 結案報告真的會被誤判為合格）。若真的失敗才符合預期，比照 T-14/T-21 對 RED 段落的既有處理方式。
if ($redResult.OverallPass) {
    Write-Host "[RED-CONFIRMED] 斷言「未經復驗即結案必須被拒絕（OverallPass=false）」如預期失敗：-SkipRemediationCheck 開啟後，OverallPass 真的變成 true（Detail：$($redResult.Detail)）。證明若無②查核，未經復驗的結案真的會被誤判為合格，不是紙上談兵——這正是 Spec §5.2『修復必須復驗』要防的事。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] F-RED：-SkipRemediationCheck 開啟後未復驗交件被誤判為 PASS')
} else {
    Write-Host '[UNEXPECTED] RED-PROOF 段落未能重現誤判（斷言意外仍為 false）——需人工複查 -SkipRemediationCheck 分支是否真的生效。'
    [void]$script:TestResults.Add('[FAIL] RED-PROOF 未如預期重現誤判')
    $script:FailCount++
}

Write-Host ''
Write-Host '--- 【綠燈】GREEN：正常模式（無 -SkipRemediationCheck），同一份未復驗交件 ---'
$greenResult = Invoke-Station5Check -Submission $subNotReverified
Assert-True -Name 'F-GREEN 斷言「未經復驗即結案必須被拒絕」通過（正常模式，②查核生效）' -Condition (-not $greenResult.OverallPass) -Detail $greenResult.Detail
Assert-True -Name 'F-GREEN NamedGaps 具名指出②修復復驗，其餘（輸入分離/verifier/隔離/摘要）皆合格（變因隔離）' -Condition ((($greenResult.NamedGaps -join '') -like '*② 修復復驗*') -and (@($greenResult.NamedGaps).Count -eq 1)) -Detail ($greenResult.NamedGaps -join '｜')

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 G：Test-IsolationDisclaimer'
Write-Host '===================================================================='

$rG1 = Test-IsolationDisclaimer -IsolationDecisionRecorded $true -ClosingReportText '報告全文（不含固定字串）'
Assert-True -Name 'G1 已落檔（isolationDecisionRecorded=true）⇒ Satisfied=true（要求解除，不需固定字串）' -Condition $rG1.Satisfied -Detail $rG1.Detail

$rG2 = Test-IsolationDisclaimer -IsolationDecisionRecorded $false -ClosingReportText '站5結案報告：...context 隔離未實測，本結論僅由輸入分離支撐...'
Assert-True -Name 'G2 未落檔但含固定字串 ⇒ Satisfied=true' -Condition $rG2.Satisfied -Detail $rG2.Detail

$rG3 = Test-IsolationDisclaimer -IsolationDecisionRecorded $false -ClosingReportText '站5結案報告：軸A軸B皆完成（缺固定字串）'
Assert-True -Name 'G3【核心：驗收⑤】未落檔且缺固定字串 ⇒ Satisfied=false（預設狀態，不需 T-03 完成即可驗證）' -Condition (-not $rG3.Satisfied) -Detail $rG3.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 H：Test-ClosingSummary（比照驗收⑥「軸A 3條、軸B 1條」範例）'
Write-Host '===================================================================='

$sumGood = [pscustomobject]@{ axisACount = 3; axisBCount = 1; axisAWorst = 'A1'; axisBWorst = 'B1'; text = '軸 A：3 條，worst A1｜軸 B：1 條，worst B1' }
$rH1 = Test-ClosingSummary -ClosingSummary $sumGood -ActualAxisACount 3 -ActualAxisBCount 1
Assert-True -Name 'H1【核心：驗收⑥】3/1 配置，兩軸各自具名 worst，無跨軸贏家 ⇒ Satisfied=true' -Condition $rH1.Satisfied -Detail $rH1.Detail

$sumCrossWinner = [pscustomobject]@{ axisACount = 3; axisBCount = 1; axisAWorst = 'A1'; axisBWorst = 'B1'; text = '軸 A：3 條，worst A1｜軸 B：1 條，worst B1｜本票整體最嚴重問題是 A1' }
$rH2 = Test-ClosingSummary -ClosingSummary $sumCrossWinner -ActualAxisACount 3 -ActualAxisBCount 1
Assert-True -Name 'H2【核心：驗收⑥】同 3/1 配置但出現跨軸單一贏家樣式 ⇒ Satisfied=false' -Condition (-not $rH2.Satisfied) -Detail $rH2.Detail

$sumMissingWorst = [pscustomobject]@{ axisACount = 1; axisBCount = 0; axisAWorst = ''; axisBWorst = ''; text = '軸 A：1 條｜軸 B：0 條' }
$rH3 = Test-ClosingSummary -ClosingSummary $sumMissingWorst -ActualAxisACount 1 -ActualAxisBCount 0
Assert-True -Name 'H3 軸A有findings但缺worst ⇒ Satisfied=false；軸B無findings不強制worst' -Condition (-not $rH3.Satisfied) -Detail $rH3.Detail

$sumMismatch = [pscustomobject]@{ axisACount = 5; axisBCount = 1; axisAWorst = 'A1'; axisBWorst = 'B1'; text = '軸 A：3 條，worst A1｜軸 B：1 條，worst B1' }
$rH4 = Test-ClosingSummary -ClosingSummary $sumMismatch -ActualAxisACount 3 -ActualAxisBCount 1
Assert-True -Name 'H4 摘要宣稱筆數（5）與實際筆數（3）不符 ⇒ Satisfied=false（獨立預期值來源比對）' -Condition (-not $rH4.Satisfied) -Detail $rH4.Detail

$sumZeroBoth = [pscustomobject]@{ axisACount = 0; axisBCount = 0; axisAWorst = ''; axisBWorst = ''; text = '軸 A：0 條｜軸 B：0 條' }
$rH5 = Test-ClosingSummary -ClosingSummary $sumZeroBoth -ActualAxisACount 0 -ActualAxisBCount 0
Assert-True -Name 'H5 兩軸皆 0 筆（PS5.1陷阱：0） ⇒ Satisfied=true（無 findings 則不強制 worst）' -Condition $rH5.Satisfied -Detail $rH5.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 I：Read-Station5Submission（十四份 fixture 皆可讀取）'
Write-Host '===================================================================='

$fixtureNames = @(
    'valid-submission', 'not-reverified', 'two-axis-supplement', 'executor-is-verifier', 'verifier-is-commander',
    'missing-isolation-disclaimer', 'isolation-decision-recorded', 'closing-summary-3-1-good',
    'closing-summary-3-1-cross-winner', 'closing-summary-missing-worst', 'spec-leak-axisA', 'smell-leak-axisB',
    'standards-not-named', 'merged-findings', 'hard-finding-no-evidence'
)
$loadedSubs = @{}
foreach ($fn in $fixtureNames) {
    $sub = Read-Station5Submission -Path (Join-Path $FixturesDir "$fn.json")
    $loadedSubs[$fn] = $sub
    Assert-True -Name "I-$fn 可讀取，ticket 欄位非空" -Condition (-not [string]::IsNullOrWhiteSpace($sub.ticket))
}

$tmpMissingPath = Join-Path $T15aTestDir 't15a-tmp-missing-field.json'
'{"ticket":"X","executor":"a","verifier":"b"}' | Out-File -LiteralPath $tmpMissingPath -Encoding utf8
$iThrew = $false
try { Read-Station5Submission -Path $tmpMissingPath | Out-Null } catch { $iThrew = $true }
Assert-True -Name 'I-missing 缺 axisA/axisB/remediation 等欄位 ⇒ 擲例外（fail-closed）' -Condition $iThrew
Remove-Item -LiteralPath $tmpMissingPath -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 J：Invoke-Station5Check 整合——十四份 fixture 對應驗收（變因隔離）'
Write-Host '===================================================================='

$rJ1 = Invoke-Station5Check -Submission $loadedSubs['valid-submission']
Assert-True -Name 'J1【基準】valid-submission ⇒ OverallPass=true，NamedGaps 為空' -Condition ($rJ1.OverallPass -and (@($rJ1.NamedGaps).Count -eq 0)) -Detail $rJ1.Detail

$rJ2 = Invoke-Station5Check -Submission $loadedSubs['two-axis-supplement']
Assert-True -Name 'J2 two-axis-supplement ⇒ OverallPass=true（②的另一合法路徑）' -Condition $rJ2.OverallPass -Detail $rJ2.Detail

$rJ3 = Invoke-Station5Check -Submission $loadedSubs['executor-is-verifier']
Assert-True -Name 'J3【驗收③】executor-is-verifier ⇒ OverallPass=false，唯一缺項為 verifier獨立' -Condition ((-not $rJ3.OverallPass) -and (($rJ3.NamedGaps -join '') -like '*③ verifier獨立*') -and (@($rJ3.NamedGaps).Count -eq 1)) -Detail ($rJ3.NamedGaps -join '｜')

$rJ4 = Invoke-Station5Check -Submission $loadedSubs['verifier-is-commander']
Assert-True -Name 'J4【驗收③】verifier-is-commander ⇒ OverallPass=false，唯一缺項為 verifier獨立' -Condition ((-not $rJ4.OverallPass) -and (($rJ4.NamedGaps -join '') -like '*③ verifier獨立*') -and (@($rJ4.NamedGaps).Count -eq 1)) -Detail ($rJ4.NamedGaps -join '｜')

$rJ5 = Invoke-Station5Check -Submission $loadedSubs['missing-isolation-disclaimer']
Assert-True -Name 'J5【驗收⑤】missing-isolation-disclaimer ⇒ OverallPass=false，唯一缺項為 SC#6隔離標註' -Condition ((-not $rJ5.OverallPass) -and (($rJ5.NamedGaps -join '') -like '*⑤ SC#6隔離標註*') -and (@($rJ5.NamedGaps).Count -eq 1)) -Detail ($rJ5.NamedGaps -join '｜')

$rJ6 = Invoke-Station5Check -Submission $loadedSubs['isolation-decision-recorded']
Assert-True -Name 'J6【驗收⑤解除】isolation-decision-recorded ⇒ OverallPass=true（標註要求已解除）' -Condition $rJ6.OverallPass -Detail $rJ6.Detail

$rJ7 = Invoke-Station5Check -Submission $loadedSubs['closing-summary-3-1-good']
Assert-True -Name 'J7【驗收⑥】closing-summary-3-1-good ⇒ OverallPass=true（軸A 3條/軸B 1條，逐字比照範例）' -Condition $rJ7.OverallPass -Detail $rJ7.Detail

$rJ8 = Invoke-Station5Check -Submission $loadedSubs['closing-summary-3-1-cross-winner']
Assert-True -Name 'J8【驗收⑥】closing-summary-3-1-cross-winner ⇒ OverallPass=false，唯一缺項為收尾摘要' -Condition ((-not $rJ8.OverallPass) -and (($rJ8.NamedGaps -join '') -like '*⑥ 收尾摘要*') -and (@($rJ8.NamedGaps).Count -eq 1)) -Detail ($rJ8.NamedGaps -join '｜')

$rJ9 = Invoke-Station5Check -Submission $loadedSubs['closing-summary-missing-worst']
Assert-True -Name 'J9【驗收⑥】closing-summary-missing-worst ⇒ OverallPass=false，唯一缺項為收尾摘要' -Condition ((-not $rJ9.OverallPass) -and (($rJ9.NamedGaps -join '') -like '*⑥ 收尾摘要*') -and (@($rJ9.NamedGaps).Count -eq 1)) -Detail ($rJ9.NamedGaps -join '｜')

$rJ10 = Invoke-Station5Check -Submission $loadedSubs['spec-leak-axisA']
Assert-True -Name 'J10【驗收①】spec-leak-axisA ⇒ OverallPass=false，唯一缺項為軸A輸入分離' -Condition ((-not $rJ10.OverallPass) -and (($rJ10.NamedGaps -join '') -like '*軸A輸入分離*') -and (@($rJ10.NamedGaps).Count -eq 1)) -Detail ($rJ10.NamedGaps -join '｜')

$rJ11 = Invoke-Station5Check -Submission $loadedSubs['smell-leak-axisB']
Assert-True -Name 'J11【驗收①】smell-leak-axisB ⇒ OverallPass=false，唯一缺項為軸B輸入分離' -Condition ((-not $rJ11.OverallPass) -and (($rJ11.NamedGaps -join '') -like '*軸B輸入分離*') -and (@($rJ11.NamedGaps).Count -eq 1)) -Detail ($rJ11.NamedGaps -join '｜')

$rJ12 = Invoke-Station5Check -Submission $loadedSubs['standards-not-named']
Assert-True -Name 'J12 standards-not-named ⇒ OverallPass=false，唯一缺項為規範版本具名' -Condition ((-not $rJ12.OverallPass) -and (($rJ12.NamedGaps -join '') -like '*①b 規範版本具名*') -and (@($rJ12.NamedGaps).Count -eq 1)) -Detail ($rJ12.NamedGaps -join '｜')

$rJ13 = Invoke-Station5Check -Submission $loadedSubs['merged-findings']
Assert-True -Name 'J13 merged-findings ⇒ OverallPass=false，唯一缺項為報告不合併' -Condition ((-not $rJ13.OverallPass) -and (($rJ13.NamedGaps -join '') -like '*報告不合併*') -and (@($rJ13.NamedGaps).Count -eq 1)) -Detail ($rJ13.NamedGaps -join '｜')

$rJ14 = Invoke-Station5Check -Submission $loadedSubs['hard-finding-no-evidence']
Assert-True -Name 'J14 hard-finding-no-evidence ⇒ OverallPass=false，唯一缺項為修法證據/裁決' -Condition ((-not $rJ14.OverallPass) -and (($rJ14.NamedGaps -join '') -like '*修法證據/裁決*') -and (@($rJ14.NamedGaps).Count -eq 1)) -Detail ($rJ14.NamedGaps -join '｜')

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 K：New-CloseTicketQueueItem／Add-QueueItemIfAbsent'
Write-Host '===================================================================='

$itemK1 = New-CloseTicketQueueItem -Repo 'o/r' -IssueNumber 42 -Source 'T-15a-demo'
Assert-True -Name 'K1 佇列項 schema：action=close-issue（重用 T-21 原五型，不新增動作型別）' -Condition ($itemK1.action -eq 'close-issue')
Assert-True -Name 'K1b target/payload/source 四欄正確' -Condition (($itemK1.target.repo -eq 'o/r') -and ($itemK1.target.issue -eq 42) -and ($itemK1.payload.state -eq 'closed') -and ($itemK1.payload.state_reason -eq 'completed') -and ($itemK1.source -eq 'T-15a-demo'))

$tmpQueuePath = Join-Path $T15aTestDir 't15a-offline-test-tmp-queue.json'
if (Test-Path -LiteralPath $tmpQueuePath) { Remove-Item -LiteralPath $tmpQueuePath -Force }

$addK2 = Add-QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemK1
Assert-True -Name 'K2 首次加入 ⇒ Added=true' -Condition $addK2.Added -Detail $addK2.Detail
$afterK2 = @(Read-QueueFile -QueuePath $tmpQueuePath)
Assert-True -Name 'K2b 加入後檔內恰 1 筆' -Condition ($afterK2.Count -eq 1)

$addK3 = Add-QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemK1
Assert-True -Name 'K3 重複加入（同 action+target+source） ⇒ Added=false（去重）' -Condition (-not $addK3.Added) -Detail $addK3.Detail
$afterK3 = @(Read-QueueFile -QueuePath $tmpQueuePath)
Assert-True -Name 'K3b 去重後仍恰 1 筆' -Condition ($afterK3.Count -eq 1)

Remove-Item -LiteralPath $tmpQueuePath -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 L：Test-TicketClosed／Find-LastCloseEvent／Test-CloseActorLegit'
Write-Host '===================================================================='

$issueL1 = [pscustomobject]@{ state = 'closed' }
$rL1 = Test-TicketClosed -Issue $issueL1
Assert-True -Name 'L1 票已關閉 ⇒ Satisfied=true' -Condition $rL1.Satisfied -Detail $rL1.Detail

$issueL2 = [pscustomobject]@{ state = 'open' }
$rL2 = Test-TicketClosed -Issue $issueL2
Assert-True -Name 'L2 票仍 open ⇒ Satisfied=false' -Condition (-not $rL2.Satisfied) -Detail $rL2.Detail

$rL3 = Find-LastCloseEvent -TimelineEvents @()
Assert-True -Name 'L3 空 timeline ⇒ Found=false' -Condition (-not $rL3.Found) -Detail $rL3.Detail

$evClosedBot = [pscustomobject]@{ event = 'closed'; actor = [pscustomobject]@{ login = 'github-actions[bot]' }; created_at = '2026-08-08T00:00:00Z' }
$evClosedHuman = [pscustomobject]@{ event = 'closed'; actor = [pscustomobject]@{ login = 'glennisgood3-dev' }; created_at = '2026-08-08T01:00:00Z' }
$rL4 = Find-LastCloseEvent -TimelineEvents @($evClosedBot, $evClosedHuman)
Assert-True -Name 'L4 多筆 closed 事件 ⇒ 取最後一筆 actor（時間序取尾端）' -Condition (($rL4.Found) -and ($rL4.Actor -eq 'glennisgood3-dev')) -Detail $rL4.Detail

$rL5 = Test-CloseActorLegit -Event $rL4 -GateIdentityLogins @()
Assert-True -Name 'L5 手動階段（未提供 -GateIdentityLogins）⇒ Blocking=false（deferred-to-CI，具名回報 actor）' -Condition ((-not $rL5.Blocking) -and ($rL5.Detail -like '*glennisgood3-dev*')) -Detail $rL5.Detail

$rL4bot = Find-LastCloseEvent -TimelineEvents @($evClosedHuman, $evClosedBot)
$rL6 = Test-CloseActorLegit -Event $rL4bot -GateIdentityLogins @('github-actions[bot]')
Assert-True -Name 'L6【驗收④】CI 階段，合法 bot actor ⇒ Blocking=true 且 Satisfied=true' -Condition (($rL6.Blocking) -and ($rL6.Satisfied)) -Detail $rL6.Detail

$rL7 = Test-CloseActorLegit -Event $rL4 -GateIdentityLogins @('github-actions[bot]')
Assert-True -Name 'L7 CI 階段，人手 actor ⇒ Blocking=true 且 Satisfied=false' -Condition (($rL7.Blocking) -and (-not $rL7.Satisfied)) -Detail $rL7.Detail

$rL8 = Test-CloseActorLegit -Event $rL3 -GateIdentityLogins @('github-actions[bot]')
Assert-True -Name 'L8 找不到任何 closed 事件 ⇒ Blocking=true 且 Satisfied=false（不得默認通過）' -Condition (($rL8.Blocking) -and (-not $rL8.Satisfied)) -Detail $rL8.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 M：PS 5.1 / StrictMode 陣列陷阱'
Write-Host '===================================================================='

$subSingleA = [pscustomobject]@{
    ticket = 'X'; executor = 'a'; verifier = 'b'
    axisA  = [pscustomobject]@{
        inputList = @([pscustomobject]@{ kind = 'diff'; value = 'd' })
        standardsFileUsed = 'f'; standardsVersion = 'v'
        findings = @([pscustomobject]@{ id = 'S1'; severity = 'hard'; remediationEvidence = 'ev'; decision = '' })
    }
    axisB  = [pscustomobject]@{
        inputList = @([pscustomobject]@{ kind = 'diff'; value = 'd' })
        findings  = @()
    }
    remediation = [pscustomobject]@{ verified = $true; method = 'verifier-rerun'; evidence = 'ev' }
    isolationDecisionRecorded = $false
    closingReportText = 'context 隔離未實測，本結論僅由輸入分離支撐'
    closingSummary = [pscustomobject]@{ axisACount = 1; axisBCount = 0; axisAWorst = 'S1'; axisBWorst = ''; text = '軸A 1條 worst S1｜軸B 0條' }
}
$rM1 = Invoke-Station5Check -Submission $subSingleA
Assert-True -Name 'M1 軸A恰1筆findings、軸B恰0筆（PS5.1陷阱①：單一物件無.Count） ⇒ 正確計數且 OverallPass=true' -Condition $rM1.OverallPass -Detail $rM1.Detail

$itemM2 = New-CloseTicketQueueItem -Repo 'o/r' -IssueNumber 99 -Source 'M2'
$queueM2 = @($itemM2)
Assert-True -Name 'M2 陷阱②③：單元素佇列陣列 Count=1（非被解卷成純量、亦非被誤包成巢狀陣列）' -Condition ($queueM2.Count -eq 1 -and $queueM2[0].action -eq 'close-issue') -Detail "Count=$($queueM2.Count)"

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 N：station5-dispatch-prep——結構性簽章保證 ＋ 真實內容的第二道防線 ＋ 證據檔'
Write-Host '===================================================================='

$cmdA = Get-Command New-AxisAPrompt
$paramNamesA = @($cmdA.Parameters.Keys)
Assert-True -Name 'N1【結構性保證】New-AxisAPrompt 簽章不含任何名稱含 Spec 的參數（物理上無法傳入 spec 原文專屬欄位）' -Condition (@($paramNamesA | Where-Object { $_ -match '(?i)spec' }).Count -eq 0) -Detail "參數清單=[$($paramNamesA -join ', ')]"

$cmdB = Get-Command New-AxisBPrompt
$paramNamesB = @($cmdB.Parameters.Keys)
Assert-True -Name 'N2【結構性保證】New-AxisBPrompt 簽章不含 StandardsRefs／SmellBaselineText（物理上無法傳入規範清單或 smell 基線）' -Condition ((@($paramNamesB) -notcontains 'StandardsRefs') -and (@($paramNamesB) -notcontains 'SmellBaselineText')) -Detail "參數清單=[$($paramNamesB -join ', ')]"

# 真實內容：真實讀取 T-11 交付的 12 條 smell 基線 asset（唯讀，不修改），與真實 Spec 檔前段摘錄，
# 組出「真的能拿去 dispatch」的 prompt 文字，寫成證據檔（供報告③「輸入分離的具體證據位置」使用）。
$realSmellPath = Join-Path $T15aTestDir '..\station-command\assets\fowler-smells.md'
$realSmellText = if (Test-Path -LiteralPath $realSmellPath) { Get-Content -LiteralPath $realSmellPath -Raw -Encoding UTF8 } else { '(找不到 T-11 asset，以佔位文字代替)' }
$realSpecPath = Join-Path $T15aTestDir '..\..\Spec_station-command_v1.11.md'
$realSpecExcerpt = if (Test-Path -LiteralPath $realSpecPath) {
    # 只取 §5.2 段落附近作為「逐項 ✓/✗ 對照用」的 spec 摘錄，非整份灌入（貼近實際 dispatch 用法）
    $fullSpec = Get-Content -LiteralPath $realSpecPath -Raw -Encoding UTF8
    $idx = $fullSpec.IndexOf('### 5.2 站 5 雙審規則')
    if ($idx -ge 0) { $fullSpec.Substring($idx, [Math]::Min(3000, $fullSpec.Length - $idx)) } else { $fullSpec.Substring(0, [Math]::Min(3000, $fullSpec.Length)) }
} else { '(找不到 spec 檔，以佔位文字代替)' }

$realAxisAPrompt = New-AxisAPrompt -Ticket 'T-15a-evidence-demo' -DiffText 'diff --git a/build/example/foo.ps1 b/build/example/foo.ps1' -StandardsRefs @('該 repo 無落檔規範，本輪僅以基線審') -SmellBaselineText $realSmellText
$realAxisBPrompt = New-AxisBPrompt -Ticket 'T-15a-evidence-demo' -DiffText 'diff --git a/build/example/foo.ps1 b/build/example/foo.ps1' -SpecExcerptText $realSpecExcerpt

Write-Utf8BomFile -Path (Join-Path $T15aTestDir 'evidence-axisA-prompt.txt') -Content $realAxisAPrompt
Write-Utf8BomFile -Path (Join-Path $T15aTestDir 'evidence-axisB-prompt.txt') -Content $realAxisBPrompt

$rN3 = Test-PromptTextMarkers -Axis 'AxisA' -PromptText $realAxisAPrompt
Assert-True -Name 'N3【真實內容】用真實 12 條 smell 基線＋佔位 diff 組出的軸A prompt ⇒ 未命中任何 spec 原文標記' -Condition $rN3.Satisfied -Detail $rN3.Detail

$rN4 = Test-PromptTextMarkers -Axis 'AxisB' -PromptText $realAxisBPrompt
Assert-True -Name 'N4【真實內容】用真實 Spec §5.2 摘錄＋佔位 diff 組出的軸B prompt ⇒ 未命中任何 smell 基線標記' -Condition $rN4.Satisfied -Detail $rN4.Detail

# 正面偵測測試：證明 Test-PromptTextMarkers 真的抓得到污染，不是永遠回傳 true 的假警報器
$rN5 = Test-PromptTextMarkers -Axis 'AxisA' -PromptText '這段文字含 REQ-ID 與 Spec_station-command 字樣，應被判定為疑似 spec 洩漏'
Assert-True -Name 'N5【偵測力驗證】人為污染軸A文字（含 REQ-ID／Spec_station-command）⇒ Satisfied=false' -Condition (-not $rN5.Satisfied) -Detail $rN5.Detail

$rN6 = Test-PromptTextMarkers -Axis 'AxisB' -PromptText '這段文字提到 Fowler 與 Mysterious Name，應被判定為疑似 smell 基線洩漏'
Assert-True -Name 'N6【偵測力驗證】人為污染軸B文字（含 Fowler／Mysterious Name）⇒ Satisfied=false' -Condition (-not $rN6.Satisfied) -Detail $rN6.Detail

Assert-True -Name 'N7 證據檔已寫入（evidence-axisA-prompt.txt／evidence-axisB-prompt.txt，供報告③核對）' -Condition ((Test-Path -LiteralPath (Join-Path $T15aTestDir 'evidence-axisA-prompt.txt')) -and (Test-Path -LiteralPath (Join-Path $T15aTestDir 'evidence-axisB-prompt.txt')))

# ============================================================
# 總結
# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Host '===================================================================='

$reportPath = Join-Path $T15aTestDir 't15a-offline-test-report.txt'
$reportLines = @("t15a-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", "")
$reportLines += $script:TestResults
$reportLines += ""
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
