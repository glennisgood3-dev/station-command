#requires -Version 5.1
<#
.SYNOPSIS
    T-14：離線測試——沙盒可跑，不連 GitHub、不執行任何被測系統（判讀對象全為靜態文本）。

.DESCRIPTION
    群組 A：Test-RedLightIsAssertionFailure（斷言失敗／載入失敗／未知三類特徵）
    群組 B：Test-VerifierIndependent（不同／相同／空值）
    群組 C：Test-AssertionExpectedIndependent（結構性自證偵測、來源標記 fail-closed／關鍵詞、
            單行斷言退回標記檢查）＋【紅燈】RED-PROOF：-SkipProvenanceCheck 讓「自證式交件必須被
            拒絕」這條斷言對著 fixtures/self-referential-assertion.json 真的失敗一次，再關閉取得綠
    群組 D：Read-Station4Submission（四份 fixture 皆可讀取、缺欄位擲例外）
    群組 E：Invoke-Station4Check 整合——對四份 fixture 分別驗證，逐一對應驗收①②③④
    群組 F：New-RedProvenLabelSet／New-RedProvenQueueItem（加項不減項、冪等、schema 正確）
    群組 G：Add-QueueItemIfAbsent（去重）
    群組 H：Test-RedProvenLabelPresent／Find-LastRedProvenLabelEvent／Test-RedProvenActorLegit
            （驗收②後段 actor=bot，deferred-to-CI 結構驗證，比照 T-10 既有先例）
    群組 I：PS 5.1 / StrictMode 陣列陷阱（0/1/N 筆 assertions、New-RedProvenLabelSet 單元素回傳）

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t14-offline-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# ⚠️ 用 $T14TestDir 而非 $ScriptDir——理由同 station4-check.ps1 檔頭註解／T-12 README 記載的
# 實跑 bug：dot-source 會 cascade 進 ../t10/gate-check.ps1，該檔宣告未加 Script: 範圍的
# $ScriptDir 並指向 t10 自己的目錄，全程共用同一層作用域會覆蓋本檔同名變數。
$T14TestDir = $PSScriptRoot
$FixturesDir = Join-Path $T14TestDir 'fixtures'

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
# Mock 基礎設施：本檔絕大多數函式不連網；僅群組 F/G 會用到 Read/Write-QueueFile（純本機檔案 I/O，
# 非 GitHub），若任何函式意外呼叫 Invoke-RestMethod，覆蓋版本會立刻噴錯而非悄悄連真網。
# ============================================================
function Invoke-RestMethod {
    [CmdletBinding()]
    param([Parameter()] [string]$Uri, [Parameter()] $Headers, [Parameter()] [string]$Method = 'Get', [Parameter()] $Body, [Parameter()] [string]$ContentType)
    throw "MOCK-MISS：t14-offline-test.ps1 不應觸發任何真實 GitHub 呼叫（本票判讀對象為靜態文本），但收到請求：$Method $Uri"
}

. (Join-Path $T14TestDir 'station4-check.ps1') -SubmissionPath 'unused' -Repo 'unused' -Issue 1 -FunctionsOnly
Set-StrictMode -Version Latest

# ============================================================
Write-Host '===================================================================='
Write-Host '群組 A：Test-RedLightIsAssertionFailure'
Write-Host '===================================================================='

$rA1 = Test-RedLightIsAssertionFailure -RedOutputText "FAILED tests/test_x.py::test_add - AssertionError: assert 0 == 5"
Assert-True -Name 'A1 pytest AssertionError ⇒ Kind=assertion-failure, Satisfied=true' -Condition (($rA1.Satisfied) -and ($rA1.Kind -eq 'assertion-failure')) -Detail $rA1.Detail

$rA2 = Test-RedLightIsAssertionFailure -RedOutputText "ModuleNotFoundError: No module named 'calc_module'"
Assert-True -Name 'A2 ModuleNotFoundError ⇒ Kind=load-failure, Satisfied=false【核心：載入失敗須被擋】' -Condition ((-not $rA2.Satisfied) -and ($rA2.Kind -eq 'load-failure')) -Detail $rA2.Detail

$rA3 = Test-RedLightIsAssertionFailure -RedOutputText "SyntaxError: invalid syntax"
Assert-True -Name 'A3 SyntaxError ⇒ Kind=load-failure, Satisfied=false' -Condition ((-not $rA3.Satisfied) -and ($rA3.Kind -eq 'load-failure')) -Detail $rA3.Detail

$rA4 = Test-RedLightIsAssertionFailure -RedOutputText "Expecting value: line 1 column 1 (char 0)`nsome random unrelated log line"
Assert-True -Name 'A4 未命中任何特徵 ⇒ Kind=unknown, Satisfied=false（fail-closed）' -Condition ((-not $rA4.Satisfied) -and ($rA4.Kind -eq 'unknown')) -Detail $rA4.Detail

$rA5 = Test-RedLightIsAssertionFailure -RedOutputText "Describing Add`n  [-] adds correctly`n    Expected: 5`n    But was: 0"
Assert-True -Name 'A5 Jasmine 風格 Expected/But ⇒ Kind=assertion-failure' -Condition $rA5.Satisfied -Detail $rA5.Detail

$rA6 = Test-RedLightIsAssertionFailure -RedOutputText "CommandNotFoundException: The term 'Get-Sum' is not recognized as the name of a cmdlet"
Assert-True -Name 'A6 PowerShell 找不到指令 ⇒ Kind=load-failure（此為 Pester 場景下的載入失敗類比）' -Condition ((-not $rA6.Satisfied) -and ($rA6.Kind -eq 'load-failure')) -Detail $rA6.Detail

$rA7 = Test-RedLightIsAssertionFailure -RedOutputText "Interrupted: 1 error during collection"
Assert-True -Name 'A7 collection 中斷 ⇒ Kind=load-failure' -Condition ((-not $rA7.Satisfied) -and ($rA7.Kind -eq 'load-failure')) -Detail $rA7.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 B：Test-VerifierIndependent'
Write-Host '===================================================================='

$rB1 = Test-VerifierIndependent -Executor 'fullstack-developer' -Verifier 'tester'
Assert-True -Name 'B1 不同身分 ⇒ Satisfied=true' -Condition $rB1.Satisfied -Detail $rB1.Detail

$rB2 = Test-VerifierIndependent -Executor 'fullstack-developer' -Verifier 'fullstack-developer'
Assert-True -Name 'B2 相同身分（執行者自陳） ⇒ Satisfied=false【核心：驗收③】' -Condition (-not $rB2.Satisfied) -Detail $rB2.Detail

$rB3 = Test-VerifierIndependent -Executor 'fullstack-developer' -Verifier '  FullStack-Developer  '
Assert-True -Name 'B3 大小寫與前後空白正規化後視為相同 ⇒ Satisfied=false' -Condition (-not $rB3.Satisfied) -Detail $rB3.Detail

$rB4 = Test-VerifierIndependent -Executor 'fullstack-developer' -Verifier ''
Assert-True -Name 'B4 verifier 為空 ⇒ Satisfied=false（fail-closed）' -Condition (-not $rB4.Satisfied) -Detail $rB4.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 C：Test-AssertionExpectedIndependent（含【紅燈】RED-PROOF）'
Write-Host '===================================================================='

$rC1 = Test-AssertionExpectedIndependent -AssertionText "`$expected = Get-Sum 2 3`n`$actual = Get-Sum 2 3`nassert `$actual -eq `$expected" -Note ''
Assert-True -Name 'C1 結構性自證偵測：expected/actual 呼叫式完全相同 ⇒ Satisfied=false, Self=true【核心：驗收④拒絕】' -Condition ((-not $rC1.Satisfied) -and $rC1.Self) -Detail $rC1.Detail

$rC2 = Test-AssertionExpectedIndependent -AssertionText 'assert add(2, 3) == 5' -Note ''
Assert-True -Name 'C2 無 expected/actual 賦值樣式，且來源標記為空 ⇒ Satisfied=false, Self=false（退回標記檢查，fail-closed）' -Condition ((-not $rC2.Satisfied) -and (-not $rC2.Self)) -Detail $rC2.Detail

$rC3 = Test-AssertionExpectedIndependent -AssertionText 'assert add(2, 3) == 5' -Note '這是隨便寫的說明，沒有指明來源類型'
Assert-True -Name 'C3 來源標記存在但未提及三種獨立來源關鍵詞之一 ⇒ Satisfied=false' -Condition (-not $rC3.Satisfied) -Detail $rC3.Detail

$rC4 = Test-AssertionExpectedIndependent -AssertionText 'assert add(2, 3) == 5' -Note 'known-good literal 5，依 spec worked example'
Assert-True -Name 'C4 來源標記提及 known-good literal／spec／worked example ⇒ Satisfied=true【核心：驗收④通過】' -Condition $rC4.Satisfied -Detail $rC4.Detail

$rC5 = Test-AssertionExpectedIndependent -AssertionText "`$expected = 5`n`$actual = Get-Sum 2 3`nassert `$actual -eq `$expected" -Note 'known-good literal 5'
Assert-True -Name 'C5 expected 為字面值（非呼叫式）即使巧合與 actual 不同也不誤判 ⇒ Satisfied=true' -Condition $rC5.Satisfied -Detail $rC5.Detail

$rC6 = Test-AssertionExpectedIndependent -AssertionText "`$expected = Get-Sum 2 3`n`$actual = Get-Sum 2 3" -Note '' -SkipProvenanceCheck
Assert-True -Name 'C6 -SkipProvenanceCheck 開啟 ⇒ 一律 Satisfied=true（僅供紅燈驗證用途本身的正確性）' -Condition $rC6.Satisfied -Detail $rC6.Detail

Write-Host ''
Write-Host '--- 【紅燈】RED-PROOF：對 fixtures/self-referential-assertion.json 開啟 -SkipProvenanceCheck，讓「自證式交件必須被拒絕」這條斷言真的失敗一次 ---'
$subTautology = Read-Station4Submission -Path (Join-Path $FixturesDir 'self-referential-assertion.json')
$redResult = Invoke-Station4Check -Submission $subTautology -SkipProvenanceCheck
# 🔴 刻意不走 Assert-True／FailCount：這裡的斷言「自證式交件必須被拒絕（OverallPass=false）」在
# -SkipProvenanceCheck 開啟時**應該失敗**（那正是紅燈的定義：證明沒有④查核時，危險的自證式斷言
# 真的會被誤判為合格）。若真的失敗才符合預期，比照 T-21/T-12 對 RED 段落的既有處理方式。
if ($redResult.OverallPass) {
    Write-Host "[RED-CONFIRMED] 斷言「自證式交件必須被拒絕（OverallPass=false）」如預期失敗：-SkipProvenanceCheck 開啟後，OverallPass 真的變成 true（Detail：$($redResult.Detail)）。證明若無④查核，自證式斷言真的會被誤判為合格，不是紙上談兵——這正是 Spec §3.5 註 C／S3 防作弊要防的事。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] C-RED：-SkipProvenanceCheck 開啟後自證式交件被誤判為 PASS')
} else {
    Write-Host '[UNEXPECTED] RED-PROOF 段落未能重現誤判（斷言意外仍為 false）——需人工複查 -SkipProvenanceCheck 分支是否真的生效。'
    [void]$script:TestResults.Add('[FAIL] RED-PROOF 未如預期重現誤判')
    $script:FailCount++
}

Write-Host ''
Write-Host '--- 【綠燈】GREEN：正常模式（無 -SkipProvenanceCheck），同一份自證式交件 ---'
$greenResult = Invoke-Station4Check -Submission $subTautology
Assert-True -Name 'C-GREEN 斷言「自證式交件必須被拒絕」通過（正常模式，④查核生效）' -Condition (-not $greenResult.OverallPass) -Detail $greenResult.Detail
Assert-True -Name 'C-GREEN NamedGaps 具名指出斷言 A1 且提及自證/Tautological' -Condition ((($greenResult.NamedGaps -join '') -like '*A1*') -and (($greenResult.NamedGaps -join '') -match 'Tautological|自證')) -Detail ($greenResult.NamedGaps -join '｜')

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 D：Read-Station4Submission'
Write-Host '===================================================================='

$subLoadFail = Read-Station4Submission -Path (Join-Path $FixturesDir 'load-failure-red.json')
Assert-True -Name 'D1 load-failure-red.json 可讀取，ticket 欄位正確' -Condition ($subLoadFail.ticket -eq 'T-14-FIXTURE-LOADFAIL')

$subValid = Read-Station4Submission -Path (Join-Path $FixturesDir 'valid-submission.json')
Assert-True -Name 'D2 valid-submission.json 可讀取，assertions 恰 1 筆' -Condition (@($subValid.assertions).Count -eq 1)

$subSelfVerify = Read-Station4Submission -Path (Join-Path $FixturesDir 'executor-is-verifier.json')
Assert-True -Name 'D3 executor-is-verifier.json 可讀取，executor=verifier' -Condition ($subSelfVerify.executor -eq $subSelfVerify.verifier)

Assert-True -Name 'D4 self-referential-assertion.json 可讀取，assertions[0].id=A1' -Condition ($subTautology.assertions[0].id -eq 'A1')

$tmpMissingPath = Join-Path $T14TestDir 't14-tmp-missing-field.json'
'{"ticket":"X","executor":"a","verifier":"b"}' | Out-File -LiteralPath $tmpMissingPath -Encoding utf8
$d5Threw = $false
try { Read-Station4Submission -Path $tmpMissingPath | Out-Null } catch { $d5Threw = $true }
Assert-True -Name 'D5 缺 redOutput/greenOutput/assertions 欄位 ⇒ 擲例外（fail-closed）' -Condition $d5Threw
Remove-Item -LiteralPath $tmpMissingPath -Force -ErrorAction SilentlyContinue

$tmpEmptyAssertPath = Join-Path $T14TestDir 't14-tmp-empty-assertions.json'
'{"ticket":"X","executor":"a","verifier":"b","redOutput":"AssertionError","greenOutput":"passed","assertions":[]}' | Out-File -LiteralPath $tmpEmptyAssertPath -Encoding utf8
$d6Threw = $false
try { Read-Station4Submission -Path $tmpEmptyAssertPath | Out-Null } catch { $d6Threw = $true }
Assert-True -Name 'D6 assertions 為空陣列 ⇒ 擲例外（至少須有一條斷言可查）' -Condition $d6Threw
Remove-Item -LiteralPath $tmpEmptyAssertPath -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 E：Invoke-Station4Check 整合——四份 fixture 對應驗收①②③④'
Write-Host '===================================================================='

$rE1 = Invoke-Station4Check -Submission $subLoadFail
Assert-True -Name 'E1【驗收①】load-failure-red.json ⇒ OverallPass=false' -Condition (-not $rE1.OverallPass) -Detail $rE1.Detail
Assert-True -Name 'E1b 具名原因為紅燈型態（① 紅燈型態），非 verifier 或預期值出處問題' -Condition ((($rE1.NamedGaps -join '') -like '*① 紅燈型態*') -and (@($rE1.NamedGaps).Count -eq 1)) -Detail ($rE1.NamedGaps -join '｜')

$rE2 = Invoke-Station4Check -Submission $subValid
Assert-True -Name 'E2【驗收②＋④通過案例】valid-submission.json ⇒ OverallPass=true' -Condition $rE2.OverallPass -Detail $rE2.Detail
Assert-True -Name 'E2b NamedGaps 為空（全過）' -Condition (@($rE2.NamedGaps).Count -eq 0)

$rE3 = Invoke-Station4Check -Submission $subSelfVerify
Assert-True -Name 'E3【驗收③】executor-is-verifier.json ⇒ OverallPass=false' -Condition (-not $rE3.OverallPass) -Detail $rE3.Detail
Assert-True -Name 'E3b 具名原因僅為 verifier≠executor，紅燈型態與預期值出處皆合格（變因隔離）' -Condition ((($rE3.NamedGaps -join '') -like '*③ verifier≠executor*') -and (@($rE3.NamedGaps).Count -eq 1)) -Detail ($rE3.NamedGaps -join '｜')

$rE4 = Invoke-Station4Check -Submission $subTautology
Assert-True -Name 'E4【驗收④拒絕案例】self-referential-assertion.json ⇒ OverallPass=false' -Condition (-not $rE4.OverallPass) -Detail $rE4.Detail
Assert-True -Name 'E4b 具名原因僅為預期值出處（斷言 A1），紅燈型態與 verifier 皆合格（變因隔離）' -Condition ((($rE4.NamedGaps -join '') -like '*④ 預期值出處，斷言 A1*') -and (@($rE4.NamedGaps).Count -eq 1)) -Detail ($rE4.NamedGaps -join '｜')

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 F：New-RedProvenLabelSet／New-RedProvenQueueItem'
Write-Host '===================================================================='

$issueF1 = [pscustomobject]@{ number = 42; labels = @([pscustomobject]@{ name = 'sc:ticket' }) }
$rF1 = New-RedProvenLabelSet -Issue $issueF1
$rF1 = @($rF1)
Assert-True -Name 'F1 尚無 sc:red-proven ⇒ 加項後含 sc:ticket 與 sc:red-proven（保留既有 label）' -Condition (($rF1 -contains 'sc:ticket') -and ($rF1 -contains 'sc:red-proven')) -Detail "[$($rF1 -join ', ')]"
Assert-True -Name 'F1b 恰 2 筆（無重複）' -Condition ($rF1.Count -eq 2)

$issueF2 = [pscustomobject]@{ number = 43; labels = @([pscustomobject]@{ name = 'sc:ticket' }, [pscustomobject]@{ name = 'sc:red-proven' }) }
$rF2 = New-RedProvenLabelSet -Issue $issueF2
$rF2 = @($rF2)
Assert-True -Name 'F2 已有 sc:red-proven ⇒ 冪等，不重複加入' -Condition (($rF2 -contains 'sc:red-proven') -and ($rF2.Count -eq 2)) -Detail "[$($rF2 -join ', ')]"

$itemF3 = New-RedProvenQueueItem -Repo 'o/r' -IssueNumber 42 -DesiredLabels @('sc:ticket', 'sc:red-proven') -Source 'T-14-demo'
Assert-True -Name 'F3 佇列項 schema：action=set-labels（重用 T-21 原五型，不新增動作型別）' -Condition ($itemF3.action -eq 'set-labels')
Assert-True -Name 'F3b target/payload/source 四欄正確' -Condition (($itemF3.target.repo -eq 'o/r') -and ($itemF3.target.issue -eq 42) -and (@($itemF3.payload.labels) -contains 'sc:red-proven') -and ($itemF3.source -eq 'T-14-demo'))

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 G：Add-QueueItemIfAbsent（去重）'
Write-Host '===================================================================='

$tmpQueuePath = Join-Path $T14TestDir 't14-offline-test-tmp-queue.json'
if (Test-Path -LiteralPath $tmpQueuePath) { Remove-Item -LiteralPath $tmpQueuePath -Force }

$addG1 = Add-QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemF3
Assert-True -Name 'G1 首次加入 ⇒ Added=true' -Condition $addG1.Added -Detail $addG1.Detail
$afterG1 = @(Read-QueueFile -QueuePath $tmpQueuePath)
Assert-True -Name 'G1b 加入後檔內恰 1 筆' -Condition ($afterG1.Count -eq 1)

$addG2 = Add-QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemF3
Assert-True -Name 'G2 重複加入（同 action+target+source） ⇒ Added=false（去重）' -Condition (-not $addG2.Added) -Detail $addG2.Detail
$afterG2 = @(Read-QueueFile -QueuePath $tmpQueuePath)
Assert-True -Name 'G2b 去重後仍恰 1 筆' -Condition ($afterG2.Count -eq 1)

Remove-Item -LiteralPath $tmpQueuePath -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 H：Test-RedProvenLabelPresent／Find-LastRedProvenLabelEvent／Test-RedProvenActorLegit'
Write-Host '===================================================================='

$issueH1 = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:ticket' }, [pscustomobject]@{ name = 'sc:red-proven' }) }
$rH1 = Test-RedProvenLabelPresent -Issue $issueH1
Assert-True -Name 'H1 票上已有 sc:red-proven ⇒ Satisfied=true' -Condition $rH1.Satisfied -Detail $rH1.Detail

$issueH2 = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:ticket' }) }
$rH2 = Test-RedProvenLabelPresent -Issue $issueH2
Assert-True -Name 'H2 票上尚無 sc:red-proven ⇒ Satisfied=false' -Condition (-not $rH2.Satisfied) -Detail $rH2.Detail

$rH3 = Find-LastRedProvenLabelEvent -TimelineEvents @()
Assert-True -Name 'H3 空 timeline ⇒ Found=false' -Condition (-not $rH3.Found) -Detail $rH3.Detail

$evBot = [pscustomobject]@{ event = 'labeled'; label = [pscustomobject]@{ name = 'sc:red-proven' }; actor = [pscustomobject]@{ login = 'github-actions[bot]' }; created_at = '2026-08-08T00:00:00Z' }
$evHuman = [pscustomobject]@{ event = 'labeled'; label = [pscustomobject]@{ name = 'sc:red-proven' }; actor = [pscustomobject]@{ login = 'glennisgood3-dev' }; created_at = '2026-08-08T01:00:00Z' }
$rH4 = Find-LastRedProvenLabelEvent -TimelineEvents @($evBot, $evHuman)
Assert-True -Name 'H4 多筆事件 ⇒ Found=true 且取最後一筆 actor（時間序取尾端）' -Condition (($rH4.Found) -and ($rH4.Actor -eq 'glennisgood3-dev')) -Detail $rH4.Detail

$rH5 = Test-RedProvenActorLegit -Event $rH4 -GateIdentityLogins @()
Assert-True -Name 'H5 手動階段（未提供 -GateIdentityLogins） ⇒ Blocking=false（deferred-to-CI，具名回報 actor）' -Condition ((-not $rH5.Blocking) -and ($rH5.Detail -like '*glennisgood3-dev*')) -Detail $rH5.Detail

$rH4bot = Find-LastRedProvenLabelEvent -TimelineEvents @($evHuman, $evBot)
$rH6 = Test-RedProvenActorLegit -Event $rH4bot -GateIdentityLogins @('github-actions[bot]')
Assert-True -Name 'H6 CI 階段，合法 bot actor ⇒ Blocking=true 且 Satisfied=true【驗收② actor=bot】' -Condition (($rH6.Blocking) -and ($rH6.Satisfied)) -Detail $rH6.Detail

$rH7 = Test-RedProvenActorLegit -Event $rH4 -GateIdentityLogins @('github-actions[bot]')
Assert-True -Name 'H7 CI 階段，人手 actor ⇒ Blocking=true 且 Satisfied=false' -Condition (($rH7.Blocking) -and (-not $rH7.Satisfied)) -Detail $rH7.Detail

$rH8 = Test-RedProvenActorLegit -Event $rH3 -GateIdentityLogins @('github-actions[bot]')
Assert-True -Name 'H8 找不到任何 sc:red-proven labeled 事件 ⇒ Blocking=true 且 Satisfied=false（不得默認通過）' -Condition (($rH8.Blocking) -and (-not $rH8.Satisfied)) -Detail $rH8.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 I：PS 5.1 / StrictMode 陣列陷阱（0/1/N 筆 assertions、單元素陣列回傳）'
Write-Host '===================================================================='

$subSingle = [pscustomobject]@{
    ticket = 'X'; executor = 'a'; verifier = 'b'
    redOutput = 'AssertionError: assert 0 == 1'; greenOutput = 'passed'
    assertions = @([pscustomobject]@{ id = 'S1'; text = 'assert x == 1'; expectedSourceNote = 'known-good literal 1' })
}
$rI1 = Invoke-Station4Check -Submission $subSingle
Assert-True -Name 'I1 恰 1 筆 assertions（PS5.1 陷阱①：單一物件無 .Count） ⇒ ProvenanceItems.Count 可正確存取且=1' -Condition (@($rI1.ProvenanceItems).Count -eq 1) -Detail "Count=$(@($rI1.ProvenanceItems).Count)"

$subTriple = [pscustomobject]@{
    ticket = 'X'; executor = 'a'; verifier = 'b'
    redOutput = 'AssertionError: assert 0 == 1'; greenOutput = 'passed'
    assertions = @(
        [pscustomobject]@{ id = 'M1'; text = 'assert x == 1'; expectedSourceNote = 'known-good literal 1' }
        [pscustomobject]@{ id = 'M2'; text = 'assert y == 2'; expectedSourceNote = 'spec worked example' }
        [pscustomobject]@{ id = 'M3'; text = 'assert z == 3'; expectedSourceNote = '' }
    )
}
$rI2 = Invoke-Station4Check -Submission $subTriple
Assert-True -Name 'I2 3 筆 assertions，其中 1 筆缺來源標記 ⇒ ProvenanceItems.Count=3，僅 M3 落入 NamedGaps' -Condition ((@($rI2.ProvenanceItems).Count -eq 3) -and ((($rI2.NamedGaps -join '') -like '*M3*')) -and (-not (($rI2.NamedGaps -join '') -like '*M1*')) -and (-not (($rI2.NamedGaps -join '') -like '*M2*'))) -Detail ($rI2.NamedGaps -join '｜')

# 單一 label 集合（New-RedProvenLabelSet 對「只有 1 個既有 label 且該 label 就是 sc:red-proven」情境）
$issueI3 = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:red-proven' }) }
$rI3 = New-RedProvenLabelSet -Issue $issueI3
$rI3 = @($rI3)
Assert-True -Name 'I3 陷阱②③：單一既有 label 恰為 sc:red-proven ⇒ 回傳陣列 Count=1（非被解卷成純量、亦非被誤包成巢狀陣列）' -Condition ($rI3.Count -eq 1 -and $rI3[0] -eq 'sc:red-proven') -Detail "Count=$($rI3.Count) 內容=[$($rI3 -join ', ')]"

# 零 label（PS5.1 陷阱①②③ 組合：ConvertTo-SafeArray 對 $null labels 的處理）
$issueI4 = [pscustomobject]@{ labels = $null }
$rI4 = New-RedProvenLabelSet -Issue $issueI4
$rI4 = @($rI4)
Assert-True -Name 'I4 陷阱①：issue.labels 為 $null（無任何既有 label） ⇒ 不拋錯，回傳恰含 sc:red-proven 的單元素陣列' -Condition ($rI4.Count -eq 1 -and $rI4[0] -eq 'sc:red-proven') -Detail "Count=$($rI4.Count)"

# ============================================================
# 總結
# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Host '===================================================================='

$reportPath = Join-Path $T14TestDir 't14-offline-test-report.txt'
$reportLines = @("t14-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", "")
$reportLines += $script:TestResults
$reportLines += ""
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
