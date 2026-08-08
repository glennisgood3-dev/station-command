#requires -Version 5.1
<#
.SYNOPSIS
    T-18：離線 mock 測試——沙盒可跑，不連 GitHub。比照 T-08/T-10/T-13 offline test 手法：覆蓋
    Invoke-RestMethod 為查表假函式（0 筆回 $null／1 筆回裸物件／多筆回陣列，忠實重現 PS 5.1 真實
    解卷行為），dot-source legacy-intake.ps1 與 gate-legacy-advance.ps1（各自 -FunctionsOnly）
    直接呼叫內部函式做函式級別驗證，另含一段真正跑過 Invoke-LegacyIntakeFlow／
    Invoke-LegacyGateAdvanceProduce 整合流程的「CLI smoke test」。

.DESCRIPTION
    群組 SETUP：dot-source 兩檔＋cascade 陷阱哨兵（證明 $T18*／$T18Adv* 命名隔離有效，非 no-op）
    群組 A：fixture 載入與 Test-AuditorFindingsWellFormed（品質守門）
    群組 B：Get-AuditorCandidateStation（§6 同一份 checklist，站1-3 逐條核對）
    群組 C：🔴【紅燈】Test-LegacyStationCap——定站不得高於站3，-BypassCapForRedTest 讓斷言真的失敗一次
    群組 D：Test-LegacyRemediationComplete（§7.3 路徑①／②，含 setup-check 避免自證）
    群組 E：badge 生命週期三階段（掛上／存續中／摘除）
    群組 F：🔴 不改寫舊票——程式碼層守門（非文件宣告）
    群組 G：auditor 報告格式化與證據非空泛交叉核對（對照真實 fixture 檔名）
    群組 H：PS 5.1／StrictMode 既知陷阱哨兵
    群組 I：CLI smoke test（Invoke-LegacyIntakeFlow／Invoke-LegacyGateAdvanceProduce 整合跑一次，
            比照 t08-offline-test.ps1 群組 G 的 URL 查表 mock 手法，多階段 Stage A→B→C 全跑）

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t18-offline-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# ⚠️ 命名為 $T18TestDir，不用 $T18Dir／$T18AdvDir（那兩個名字分別已被本檔稍後 dot-source 的
# legacy-intake.ps1／gate-legacy-advance.ps1 各自佔用，同層作用域下重名會互相覆蓋，見 t13 README
# 記載的同型事故先例）。
$T18TestDir = $PSScriptRoot
$T18FixturesDir = Join-Path $T18TestDir 'fixtures'

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
# Mock 基礎設施：覆蓋 Invoke-RestMethod，依 URL 查表回傳假資料，不連網
# ============================================================
$script:MockResponses = @{}
$script:MockCallLog = New-Object System.Collections.ArrayList

function Invoke-RestMethod {
    [CmdletBinding()]
    param([Parameter()] [string]$Uri, [Parameter()] $Headers, [Parameter()] [string]$Method = 'Get', [Parameter()] $Body, [Parameter()] [string]$ContentType)
    [void]$script:MockCallLog.Add([pscustomobject]@{ Uri = $Uri; Method = $Method })
    if ($script:MockResponses.ContainsKey($Uri)) { return $script:MockResponses[$Uri] }
    throw "MOCK-MISS：t18-offline-test.ps1 未替這個 URL 設定假回應，無法繼續（也證明沒有真的連網）：$Method $Uri"
}
function Start-Sleep { param([Parameter(Position = 0)]$Seconds) }

# ============================================================
# 準備整合測試用的臨時 PAT 檔與佇列檔路徑
# ============================================================
$T18TmpPatPath = Join-Path $T18TestDir 't18-offline-test-fake-pat.txt'
[System.IO.File]::WriteAllText($T18TmpPatPath, 'FAKE-TOKEN-NOT-REAL', (New-Object System.Text.UTF8Encoding($false)))
$T18TmpQueuePath = Join-Path $T18TestDir 't18-offline-test-tmp-queue.json'
if (Test-Path -LiteralPath $T18TmpQueuePath) { Remove-Item -LiteralPath $T18TmpQueuePath -Force }
$T18TmpQueuePath2 = Join-Path $T18TestDir 't18-offline-test-tmp-queue-adv.json'
if (Test-Path -LiteralPath $T18TmpQueuePath2) { Remove-Item -LiteralPath $T18TmpQueuePath2 -Force }

$T18AuditorFindingsB = Join-Path $T18FixturesDir 'auditor-findings-legacy-project-b.json'
$T18DecisionsB = Join-Path $T18FixturesDir 'legacy-project-b\DECISIONS.md'
$T18ProtectedTicketsPath = Join-Path $T18FixturesDir 'protected-legacy-tickets.json'

# ============================================================
# dot-source（① legacy-intake.ps1 -FunctionsOnly，用「有意義的真實值」而非隨便佔位字串，
# 供本檔稍後直接驗證 cascade 隔離是否真的有效）
# ============================================================
. (Join-Path $T18TestDir 'legacy-intake.ps1') `
    -WorkId 'W-legacy-demo' -PrimaryRepo 'acme/legacy-repo' -ParticipatingRepos 'acme/legacy-repo' `
    -AuditorFindingsPath $T18AuditorFindingsB -DecisionsMdPath $T18DecisionsB `
    -ProtectedLegacyTicketsPath $T18ProtectedTicketsPath `
    -PatPath $T18TmpPatPath -QueuePath $T18TmpQueuePath -FunctionsOnly

# ② gate-legacy-advance.ps1 -FunctionsOnly（無 Mandatory 參數，用空字串／0 皆可繫結）
. (Join-Path $T18TestDir 'gate-legacy-advance.ps1') -PatPath $T18TmpPatPath -QueuePath $T18TmpQueuePath2 -FunctionsOnly

Set-StrictMode -Version Latest

Write-Host "===================================================================="
Write-Host ('群組 SETUP：cascade 陷阱哨兵（$T18* / $T18Adv* 命名隔離是否真的有效）')
Write-Host "===================================================================="
Assert-True -Name "SETUP1 dot-source legacy-intake.ps1 後 `$T18WorkId 仍為 'W-legacy-demo'（未被 t08 內部佔位值 'W-t18-dotsource-placeholder' 覆蓋）" -Condition ($T18WorkId -eq 'W-legacy-demo') -Detail "實際='$T18WorkId'"
Assert-True -Name "SETUP2 `$T18PrimaryRepo 仍為 'acme/legacy-repo'（未被 t08 佔位值 'placeholder/placeholder' 覆蓋）" -Condition ($T18PrimaryRepo -eq 'acme/legacy-repo') -Detail "實際='$T18PrimaryRepo'"
Assert-True -Name "SETUP3 `$T18Dir 指向本檔（t18）自己的目錄，非 t08／t13 的目錄" -Condition ($T18Dir -eq $T18TestDir) -Detail "T18Dir='$T18Dir' TestDir='$T18TestDir'"
Assert-True -Name "SETUP4 dot-source gate-legacy-advance.ps1 後 `$T18AdvDir 亦指向本檔目錄（與 `$T18Dir 不同變數名，互不覆蓋）" -Condition ($T18AdvDir -eq $T18TestDir) -Detail "T18AdvDir='$T18AdvDir'"
Assert-True -Name "SETUP5 兩檔各自的 `$T18Dir 與 `$T18AdvDir 皆未殘留 t08／t10/t13 的路徑" -Condition (($T18Dir -notmatch 't08') -and ($T18Dir -notmatch 't13') -and ($T18AdvDir -notmatch 't10'))

Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 A：fixture 載入與 Test-AuditorFindingsWellFormed（品質守門）"
Write-Host "===================================================================="

$findingsA = Get-AuditorFindingsFromFile -Path (Join-Path $T18FixturesDir 'auditor-findings-legacy-project-a.json')
$findingsB = Get-AuditorFindingsFromFile -Path (Join-Path $T18FixturesDir 'auditor-findings-legacy-project-b.json')
$findingsOpt = Get-AuditorFindingsFromFile -Path (Join-Path $T18FixturesDir 'auditor-findings-legacy-project-b-optimistic.json')

Assert-True -Name "A1 legacy-project-a findings 載入成功，8 筆" -Condition ((@($findingsA.Findings)).Count -eq 8)
Assert-True -Name "A2 legacy-project-b findings 載入成功，8 筆" -Condition ((@($findingsB.Findings)).Count -eq 8)
Assert-True -Name "A3 legacy-project-a findings 通過品質守門（皆有 Mark，✗項皆有證據與合法缺件分類）" -Condition (Test-AuditorFindingsWellFormed -AuditorFindings $findingsA.Findings).WellFormed
Assert-True -Name "A4 legacy-project-b findings 通過品質守門" -Condition (Test-AuditorFindingsWellFormed -AuditorFindings $findingsB.Findings).WellFormed
Assert-True -Name "A5 optimistic findings 結構仍合格（結構守門管不到『內容誠實與否』，那是 cap 這道防呆的職責，見群組C）" -Condition (Test-AuditorFindingsWellFormed -AuditorFindings $findingsOpt.Findings).WellFormed

# 品質守門的反例：手工構造一筆缺證據的 fail 項
$malformed = @([pscustomobject]@{ Station = 'sc:station-1'; Id = '1.glossary'; Mark = 'fail'; Evidence = ''; MissingClass = 'minor' })
$wfMalformed = Test-AuditorFindingsWellFormed -AuditorFindings $malformed
Assert-True -Name "A6 手工構造『✗項缺證據』⇒ WellFormed=false" -Condition (-not $wfMalformed.WellFormed) -Detail ($wfMalformed.Problems -join '；')

Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 B：Get-AuditorCandidateStation（§6 同一份 checklist，重用 t10 定義，站1-3逐條核對）"
Write-Host "===================================================================="

$candA = Get-AuditorCandidateStation -AuditorFindings $findingsA.Findings
Assert-True -Name "B1 legacy-project-a 候選站別＝1（1.glossary 為第一個未滿足項）" -Condition ($candA.CandidateStation -eq 1) -Detail $candA.Detail
Assert-True -Name "B1b legacy-project-a UnmetItems 恰含站1三項（1.glossary/1.adr/1.confirm 皆 fail）" -Condition ((@($candA.UnmetItems)).Count -eq 3)

$candB = Get-AuditorCandidateStation -AuditorFindings $findingsB.Findings
Assert-True -Name "B2 legacy-project-b 候選站別＝3（站1/2全過，3.fields 未過）" -Condition ($candB.CandidateStation -eq 3) -Detail $candB.Detail
Assert-True -Name "B2b legacy-project-b UnmetItems 恰 1 項（僅 3.fields；3.vertical=na 不計入）" -Condition ((@($candB.UnmetItems)).Count -eq 1 -and $candB.UnmetItems[0].Id -eq '3.fields')

$candOpt = Get-AuditorCandidateStation -AuditorFindings $findingsOpt.Findings
Assert-True -Name "B3 optimistic findings 候選站別＝4（站1-3全報pass，用於群組C紅燈情境）" -Condition ($candOpt.CandidateStation -eq 4) -Detail $candOpt.Detail

# fail-closed：auditor 完全沒回報 1.confirm 這一項
$findingsMissing = @($findingsB.Findings | Where-Object { $_.Id -ne '1.confirm' })
$candMissing = Get-AuditorCandidateStation -AuditorFindings $findingsMissing
Assert-True -Name "B4 auditor 漏回報 1.confirm ⇒ fail-closed 視為未滿足，候選站別＝1（非略過該項直接判過）" -Condition ($candMissing.CandidateStation -eq 1) -Detail $candMissing.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 C：🔴【紅燈】Test-LegacyStationCap——legacy 定站上限站 3（Spec §7.3，ticket 驗收條件①核心）"
Write-Host "===================================================================="

# --- C-RED：先寫「定站不得高於站3」斷言，用 -BypassCapForRedTest 讓它真的失敗一次 ---
$redCap = Test-LegacyStationCap -CandidateStation 4 -BypassCapForRedTest
$redCondition = ($redCap.DeterminedStation -le 3)
if (-not $redCondition) {
    Write-Host "[RED-CONFIRMED] 斷言『legacy 定站不得高於站3（DeterminedStation -le 3）』如預期失敗：-BypassCapForRedTest 開啟後，DeterminedStation=$($redCap.DeterminedStation)（>3）。證明若無 cap 邏輯，未實作時 auditor 過度樂觀的候選站別（見群組B3，optimistic findings 候選=4）會被直接當成定站結果，站別因此跳過站3直達站4——這正是 Spec §7.3『legacy 工作定站上限為站3』要防的事，不是紙上談兵。"
    [void]$script:TestResults.Add("[RED-CONFIRMED] Test-LegacyStationCap -BypassCapForRedTest 讓『定站不得高於站3』斷言真的失敗：DeterminedStation=$($redCap.DeterminedStation)")
} else {
    Assert-True -Name "C-RED（非預期）Bypass 開啟後仍未超過站3，紅燈未觸發，需檢查 Test-LegacyStationCap 實作" -Condition $false -Detail $redCap.Detail
}

# --- C-GREEN：關閉開關，同一份候選站別重新判定 ⇒ 正確封頂為站3 ---
$greenCap = Test-LegacyStationCap -CandidateStation 4
Assert-True -Name "C-GREEN 關閉 -BypassCapForRedTest 後，候選站別4（optimistic情境，未收編）⇒ DeterminedStation=3 CapApplied=true" -Condition (($greenCap.DeterminedStation -eq 3) -and $greenCap.CapApplied) -Detail $greenCap.Detail

# --- 一般情境（cap 不需要介入的典型案例，legacy-project-a／b 的真實候選站別皆 <=3） ---
$capA = Test-LegacyStationCap -CandidateStation $candA.CandidateStation
Assert-True -Name "C1 legacy-project-a（候選=1）⇒ DeterminedStation=1 CapApplied=false（cap 不過度介入）" -Condition (($capA.DeterminedStation -eq 1) -and (-not $capA.CapApplied)) -Detail $capA.Detail

$capB = Test-LegacyStationCap -CandidateStation $candB.CandidateStation
Assert-True -Name "C2 legacy-project-b（候選=3，legacy收編最典型情境）⇒ DeterminedStation=3 CapApplied=false（3=上限本身，非'超過'，cap不介入）" -Condition (($capB.DeterminedStation -eq 3) -and (-not $capB.CapApplied)) -Detail $capB.Detail

# --- 收編完成後 cap 解除（§7.3：直到補齊或具名不收編為止） ---
$capRemediated = Test-LegacyStationCap -CandidateStation 4 -TicketsRemediated
Assert-True -Name "C3 候選=4 且已收編完成（TicketsRemediated）⇒ DeterminedStation=4 CapApplied=false（cap解除）" -Condition (($capRemediated.DeterminedStation -eq 4) -and (-not $capRemediated.CapApplied)) -Detail $capRemediated.Detail

# --- 站5情境同樣受 cap 管束 ---
$cap5 = Test-LegacyStationCap -CandidateStation 5
Assert-True -Name "C4 候選=5（未收編）⇒ 同樣封頂為3" -Condition (($cap5.DeterminedStation -eq 3) -and $cap5.CapApplied) -Detail $cap5.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 D：Test-LegacyRemediationComplete（§7.3 兩條路徑，含 setup-check 避免自證）"
Write-Host "===================================================================="

# --- setup-check：獨立於被測函式，先確認 fixture 本身內容確實符合預期配置 ---
$ticket201Body = Get-Content -LiteralPath (Join-Path $T18FixturesDir 'legacy-project-b\remediated-native-tickets\ticket-201.md') -Raw -Encoding UTF8
$ticket202Body = Get-Content -LiteralPath (Join-Path $T18FixturesDir 'legacy-project-b\remediated-native-tickets\ticket-202.md') -Raw -Encoding UTF8
$eightFields = @('REQ-ID', '驗收條件', 'depends_on', 'executor', 'basis', 'scope', '測試先行', '不可逆動作')
$ticket201Missing = @($eightFields | Where-Object { $ticket201Body -notmatch [regex]::Escape("$_" + ':') })
$ticket202Missing = @($eightFields | Where-Object { $ticket202Body -notmatch [regex]::Escape("$_" + ':') })
$ticket201HasAll = ($ticket201Missing.Count -eq 0)
$ticket202HasAll = ($ticket202Missing.Count -eq 0)
Assert-True -Name "D-setup1 ticket-201.md 確實含全八項欄位標記（獨立於被測函式的人工核對）" -Condition $ticket201HasAll
Assert-True -Name "D-setup2 ticket-202.md 確實含全八項欄位標記" -Condition $ticket202HasAll
$decisionsOrigContent = Get-Content -LiteralPath $T18DecisionsB -Raw -Encoding UTF8
Assert-True -Name "D-setup3 原始 DECISIONS.md 確實不含『不收編、僅供查閱』字樣（避免誤判假陽性）" -Condition ($decisionsOrigContent -notmatch '不收編[、，,]\s*僅供查閱')
$decisionsPath2Content = Get-Content -LiteralPath (Join-Path $T18FixturesDir 'legacy-project-b\DECISIONS-path2-not-adopted.md') -Raw -Encoding UTF8
Assert-True -Name "D-setup4 DECISIONS-path2-not-adopted.md 確實含『不收編、僅供查閱』字樣" -Condition ($decisionsPath2Content -match '不收編[、，,]\s*僅供查閱')

# --- D1：路徑① ---
$remediatedTickets = Get-RemediatedTicketsFromDir -Dir (Join-Path $T18FixturesDir 'legacy-project-b\remediated-native-tickets') -RepoString 'acme/legacy-repo'
Assert-True -Name "D1a Get-RemediatedTicketsFromDir 讀到 2 張票" -Condition ((@($remediatedTickets)).Count -eq 2)
$remD1 = Test-LegacyRemediationComplete -NativeTickets $remediatedTickets -DecisionsMdContent $decisionsOrigContent
Assert-True -Name "D1 路徑①：8欄位齊全的native票集 ⇒ Remediated=true Path=path1-8fields" -Condition ($remD1.Remediated -and $remD1.Path -eq 'path1-8fields') -Detail $remD1.Detail

# --- D2：路徑② ---
$remD2 = Test-LegacyRemediationComplete -NativeTickets @() -DecisionsMdContent $decisionsPath2Content
Assert-True -Name "D2 路徑②：DECISIONS.md 具名『不收編、僅供查閱』 ⇒ Remediated=true Path=path2-not-adopted" -Condition ($remD2.Remediated -and $remD2.Path -eq 'path2-not-adopted') -Detail $remD2.Detail

# --- D3：兩條路徑皆未滿足 ---
$remD3 = Test-LegacyRemediationComplete -NativeTickets @() -DecisionsMdContent $decisionsOrigContent
Assert-True -Name "D3 無native票集、DECISIONS.md 亦無不收編記載 ⇒ Remediated=false" -Condition (-not $remD3.Remediated) -Detail $remD3.Detail

# --- D4：舊格式票（ticket-legacy-101/102）拿去跑深度檢查，應該不算路徑①滿足（反例，證明不是隨便給票就過） ---
$oldBody101 = Get-Content -LiteralPath (Join-Path $T18FixturesDir 'legacy-project-b\tickets\ticket-legacy-101.md') -Raw -Encoding UTF8
$oldBody102 = Get-Content -LiteralPath (Join-Path $T18FixturesDir 'legacy-project-b\tickets\ticket-legacy-102.md') -Raw -Encoding UTF8
$oldTickets = @(
    [pscustomobject]@{ number = 101; body = $oldBody101; RepoString = 'acme/legacy-repo' }
    [pscustomobject]@{ number = 102; body = $oldBody102; RepoString = 'acme/legacy-repo' }
)
$remD4 = Test-LegacyRemediationComplete -NativeTickets $oldTickets -DecisionsMdContent $decisionsOrigContent
Assert-True -Name "D4 舊格式票（無§3.5欄位）不滿足路徑① ⇒ Remediated=false（非只要有票就算數）" -Condition (-not $remD4.Remediated) -Detail $remD4.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 E：badge 生命週期三階段（掛上／存續中／通過首個native gate後摘除）"
Write-Host "===================================================================="

# --- 階段①：intake 定站時掛上 ---
$initialLabels = Get-LegacyInitialLabelSet -ExistingLabels @('sc:work') -DeterminedStation 3
Assert-True -Name "E1 階段①掛上：初始 label 集合含 sc:legacy 與 sc:station-3" -Condition (($initialLabels -contains 'sc:legacy') -and ($initialLabels -contains 'sc:station-3')) -Detail "[$($initialLabels -join ', ')]"
Assert-True -Name "E1b 初始 label 集合恰 3 項（sc:work／sc:station-3／sc:legacy，不多不少）" -Condition ((@($initialLabels)).Count -eq 3)

# --- 階段②：存續中（尚未過任何 native gate，badge 仍在） ---
$midAnchor = [pscustomobject]@{ number = 900; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-3' }, [pscustomobject]@{ name = 'sc:legacy' }) }
$badgeMid = Get-LegacyBadgeStatus -AnchorIssue $midAnchor
Assert-True -Name "E2 階段②存續中：anchor 現有 sc:legacy ⇒ HasLegacyBadge=true" -Condition $badgeMid.HasLegacyBadge -Detail $badgeMid.Detail

# --- 階段③：通過第一個 native gate（推進動作）⇒ badge 消失 ---
$advResult = New-LegacyAdvanceLabelSet -AnchorIssue $midAnchor -TargetStation 'sc:station-4'
Assert-True -Name "E3 階段③摘除：推進後 label 集合不含 sc:legacy" -Condition (-not (@($advResult.Labels) -contains 'sc:legacy')) -Detail "[$($advResult.Labels -join ', ')]"
Assert-True -Name "E3b BadgeRemoved=true（本次推進確實摘除了 badge）" -Condition $advResult.BadgeRemoved
Assert-True -Name "E3c 推進後仍正確含新站別 sc:station-4、不含舊站別 sc:station-3、保留 sc:work" -Condition (($advResult.Labels -contains 'sc:station-4') -and (-not ($advResult.Labels -contains 'sc:station-3')) -and ($advResult.Labels -contains 'sc:work'))

# --- 冪等：badge 已消失後再次推進，不應誤報「又摘了一次」，也不應把它加回來 ---
$postStripAnchor = [pscustomobject]@{ number = 900; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-4' }) }
$advResult2 = New-LegacyAdvanceLabelSet -AnchorIssue $postStripAnchor -TargetStation 'sc:station-5'
Assert-True -Name "E4 badge 已消失後再推進：不含 sc:legacy（未被重新加回）" -Condition (-not (@($advResult2.Labels) -contains 'sc:legacy'))
Assert-True -Name "E4b BadgeRemoved=false（本次推進前本來就沒有 badge，如實回報非本次摘除）" -Condition (-not $advResult2.BadgeRemoved) -Detail $advResult2.Detail

# --- native work（非 legacy）不受影響：從未有 sc:legacy，推進後也不會平白冒出 ---
$nativeAnchor = [pscustomobject]@{ number = 901; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-1' }) }
$advNative = New-LegacyAdvanceLabelSet -AnchorIssue $nativeAnchor -TargetStation 'sc:station-2'
Assert-True -Name "E5 native work 推進：labels 中從未出現 sc:legacy" -Condition (-not (@($advNative.Labels) -contains 'sc:legacy'))

Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 F：🔴 不改寫舊票——程式碼層守門（非文件宣告，t18-offline-test.ps1 逐一操練）"
Write-Host "===================================================================="

$protectedTickets = Get-ProtectedLegacyTicketsFromFile -Path $T18ProtectedTicketsPath
$protectedTickets = @($protectedTickets)
Assert-True -Name "F-setup 保護清單載入 2 筆（#101／#102）" -Condition ((@($protectedTickets)).Count -eq 2)

# --- F1：直接呼叫守門函式，對受保護舊票的 set-labels 動作 ⇒ Blocked=true ---
$mutateItem = [pscustomobject]@{ action = 'set-labels'; target = [pscustomobject]@{ repo = 'acme/legacy-repo'; issue = 101 }; payload = [pscustomobject]@{ labels = @('sc:ticket', 'sc:blocked') }; source = 'W-legacy-demo' }
$guardF1 = Test-LegacyTicketProtectionGuard -Item $mutateItem -ProtectedLegacyTickets $protectedTickets
Assert-True -Name "F1 對受保護舊票 #101 的 set-labels ⇒ Blocked=true" -Condition $guardF1.Blocked -Detail $guardF1.Detail

# --- F2：透過真正的產生入口 Add-Station18QueueItemIfAbsent ⇒ Added=false 且佇列檔內容不變 ---
if (Test-Path -LiteralPath $T18TmpQueuePath) { Remove-Item -LiteralPath $T18TmpQueuePath -Force }
$beforeQueueContent = if (Test-Path -LiteralPath $T18TmpQueuePath) { Get-Content -LiteralPath $T18TmpQueuePath -Raw } else { '(檔案不存在)' }
$addF2 = Add-Station18QueueItemIfAbsent -QueuePath $T18TmpQueuePath -Item $mutateItem -ProtectedLegacyTickets $protectedTickets
Assert-True -Name "F2 Add-Station18QueueItemIfAbsent 對受保護舊票 ⇒ Added=false Blocked=true" -Condition ((-not $addF2.Added) -and $addF2.Blocked) -Detail $addF2.Detail
$afterQueueExists = Test-Path -LiteralPath $T18TmpQueuePath
Assert-True -Name "F2b 佇列檔仍不存在（真的沒有寫入，非寫入後又復原）" -Condition (-not $afterQueueExists)

# --- F3：close-issue 動作同樣被擋（涵蓋『刪除』語意，非只擋 set-labels） ---
$closeItem = [pscustomobject]@{ action = 'close-issue'; target = [pscustomobject]@{ repo = 'acme/legacy-repo'; issue = 102 }; payload = [pscustomobject]@{ state = 'closed'; state_reason = 'not_planned' }; source = 'W-legacy-demo' }
$guardF3 = Test-LegacyTicketProtectionGuard -Item $closeItem -ProtectedLegacyTickets $protectedTickets
Assert-True -Name "F3 對受保護舊票 #102 的 close-issue ⇒ Blocked=true（涵蓋刪除語意）" -Condition $guardF3.Blocked -Detail $guardF3.Detail

# --- F4：負面對照組——目標不是受保護舊票（例如新建 native 票 #201 或 anchor #555）⇒ 不誤擋 ---
$legitItem = [pscustomobject]@{ action = 'set-labels'; target = [pscustomobject]@{ repo = 'acme/legacy-repo'; issue = 201 }; payload = [pscustomobject]@{ labels = @('sc:ticket') }; source = 'W-legacy-demo' }
$guardF4 = Test-LegacyTicketProtectionGuard -Item $legitItem -ProtectedLegacyTickets $protectedTickets
Assert-True -Name "F4 對非保護清單內的 #201 ⇒ Blocked=false（守門不誤擋合法動作）" -Condition (-not $guardF4.Blocked) -Detail $guardF4.Detail
$addF4 = Add-Station18QueueItemIfAbsent -QueuePath $T18TmpQueuePath -Item $legitItem -ProtectedLegacyTickets $protectedTickets
Assert-True -Name "F4b 合法動作確實成功寫入佇列（Added=true）" -Condition $addF4.Added -Detail $addF4.Detail
if (Test-Path -LiteralPath $T18TmpQueuePath) { Remove-Item -LiteralPath $T18TmpQueuePath -Force }

# --- F5：create-issue（無 .issue 欄位）⇒ 守門不適用（不是要擋的類型），不誤擋 anchor/milestone 建立 ---
$createItem = [pscustomobject]@{ action = 'create-issue'; target = [pscustomobject]@{ repo = 'acme/legacy-repo' }; payload = [pscustomobject]@{ title = 'x' }; source = 'W-legacy-demo' }
$guardF5 = Test-LegacyTicketProtectionGuard -Item $createItem -ProtectedLegacyTickets $protectedTickets
Assert-True -Name "F5 create-issue（無 issue 欄位，尚未指向既有票）⇒ Blocked=false（不適用本守門）" -Condition (-not $guardF5.Blocked) -Detail $guardF5.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 G：auditor 報告格式化與證據非空泛交叉核對（對照真實 fixture 檔名，非只檢查非空字串）"
Write-Host "===================================================================="

$reportA = Format-AuditorReport -AuditorFindings $findingsA.Findings -AuditorSuggestedRetreatStation $findingsA.AuditorSuggestedRetreatStation
Assert-True -Name "G1 legacy-project-a 報告：1.glossary 的行含 ✗ 符號" -Condition ((@($reportA | Where-Object { $_ -like '*1.glossary*' }))[0] -like '*✗*')
Assert-True -Name "G1b legacy-project-a 報告：含缺件分類標註" -Condition ((@($reportA | Where-Object { $_ -like '*1.glossary*' }))[0] -like '*缺件分類*')

# 真實 fixture 檔名清單（獨立於 findings JSON 本身，直接對實體目錄 ls）
$realFileNames = @(Get-ChildItem -Path (Join-Path $T18FixturesDir 'legacy-project-a') -Recurse -File | ForEach-Object { $_.Name })
$realFileNamesB = @(Get-ChildItem -Path (Join-Path $T18FixturesDir 'legacy-project-b') -Recurse -File | ForEach-Object { $_.Name })
function Test-EvidencePointsToRealArtifact {
    param([Parameter(Mandatory)][string]$Evidence, [Parameter(Mandatory)][array]$KnownFileNames)
    $KnownFileNames = @($KnownFileNames)
    foreach ($fn in $KnownFileNames) {
        if ($Evidence -like "*$fn*") { return $true }
    }
    return $false
}
# ⚠️ 範圍限定為「實際驅動候選站別判定」的未滿足項（$candA.UnmetItems，即 1.glossary/1.adr/
# 1.confirm）——這三項的證據都指向確實存在的檔案（README.md／NOTES.md）。2.confirm／2.gapreview／
# 3.fields 這幾項的證據描述的是「目錄內根本沒有對應檔案」（因為站1已退回，這些項本來就是陪同
# 呈報、不影響判定的下游項）——「找不到檔案」本身也是一種具體證據（非空泛描述），但無法用「引用
# 真實檔名」這個判準去驗證「不存在」這件事，故本檢查聚焦在真正驅動判定、且理應可指向既存檔案的
# 未滿足項，避免把「合理描述缺席」誤判為「空泛」。
$g2AllPoint = $true
foreach ($item in $candA.UnmetItems) {
    $hit = Test-EvidencePointsToRealArtifact -Evidence $item.Evidence -KnownFileNames $realFileNames
    if (-not $hit) { $g2AllPoint = $false; Write-Host "  （未命中真實檔名：$($item.Id) — $($item.Evidence)）" }
}
Assert-True -Name "G2 legacy-project-a 驅動候選站別判定的未滿足項（1.glossary/1.adr/1.confirm）Evidence 皆確實指向真實 fixture 檔名" -Condition $g2AllPoint -Detail "核對項：$((@($candA.UnmetItems | ForEach-Object { $_.Id })) -join '、')"

# 反面驗證：2.confirm 等「檔案根本不存在」型證據，仍非空字串（非空泛，只是無法比對真實檔名）
$absenceFindings = @($findingsA.Findings | Where-Object { $_.Mark -eq 'fail' -and $_.Id -notin @('1.glossary', '1.adr', '1.confirm') })
$absenceFindingsBlank = @($absenceFindings | Where-Object { [string]::IsNullOrWhiteSpace($_.Evidence) })
$g2bAllNonEmpty = ($absenceFindings.Count -gt 0) -and ($absenceFindingsBlank.Count -eq 0)
Assert-True -Name "G2b 其餘（因目錄內檔案根本不存在而未過的）項目，證據仍非空字串（描述『找不到』本身，非空泛留白）" -Condition $g2bAllNonEmpty

$failFindingsB = @($findingsB.Findings | Where-Object { $_.Mark -eq 'fail' })
$g3AllPoint = $true
foreach ($f in $failFindingsB) {
    $hit = Test-EvidencePointsToRealArtifact -Evidence $f.Evidence -KnownFileNames $realFileNamesB
    if (-not $hit) { $g3AllPoint = $false; Write-Host "  （未命中真實檔名：$($f.Id) — $($f.Evidence)）" }
}
Assert-True -Name "G3 legacy-project-b 每個 ✗ 項的 Evidence 皆確實指向真實 fixture 檔名" -Condition $g3AllPoint

Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 H：PS 5.1／StrictMode 既知陷阱哨兵"
Write-Host "===================================================================="

$singleFindingArr = @([pscustomobject]@{ Station = 'sc:station-1'; Id = '1.glossary'; Mark = 'fail'; Evidence = 'x'; MissingClass = 'minor' })
Assert-True -Name "H1 單筆 findings 陣列 .Count=1（陷阱①：單一物件無 .Count，須先 @() 包裝）" -Condition ((@($singleFindingArr)).Count -eq 1)
$candSingle = Get-AuditorCandidateStation -AuditorFindings $singleFindingArr
Assert-True -Name "H2 傳入單筆陣列不拋錯，正常回傳候選站別" -Condition ($candSingle.CandidateStation -eq 1)

$emptyProtected = Test-LegacyTicketProtectionGuard -Item $legitItem -ProtectedLegacyTickets @()
Assert-True -Name "H3 保護清單為空陣列時 @(函式呼叫) 不誤包成 1 筆，Blocked=false" -Condition (-not $emptyProtected.Blocked)

$remEmptyTickets = Test-LegacyRemediationComplete -NativeTickets @() -DecisionsMdContent ''
Assert-True -Name "H4 NativeTickets 為空陣列時不拋錯（不誤觸發 Test-Station3TicketSetDeep 的 0 票分支）" -Condition (-not $remEmptyTickets.Remediated)

Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 I：CLI smoke test——Invoke-LegacyIntakeFlow 多階段整合（Stage A→B→C 全跑一次）"
Write-Host "===================================================================="

$anchorUrl = 'https://api.github.com/repos/acme/legacy-repo/issues?labels=sc:work&state=all&per_page=100'
$msUrl = 'https://api.github.com/repos/acme/legacy-repo/milestones?state=all&per_page=100'
$userUrl = 'https://api.github.com/user'

# --- Call 1：anchor 不存在 ⇒ Stage A-pending ---
$script:MockResponses[$anchorUrl] = $null
$script:MockResponses[$msUrl] = $null
$script:MockResponses[$userUrl] = [pscustomobject]@{ login = 'glennisgood3-dev' }

$call1 = Invoke-LegacyIntakeFlow
Assert-True -Name "I1 Call1：anchor 不存在 ⇒ Stage=A-pending" -Condition ($call1.Stage -eq 'A-pending') -Detail "Stage=$($call1.Stage)"
$queueAfter1 = Read-QueueFile -QueuePath $T18TmpQueuePath
$queueAfter1 = @($queueAfter1)
Assert-True -Name "I1b 佇列產生 1 筆 create-issue（產生權=intake，與 native 模式同形狀）" -Condition (($queueAfter1.Count -eq 1) -and ($queueAfter1[0].action -eq 'create-issue')) -Detail "action=$($queueAfter1[0].action)"
Assert-True -Name "I1c create-issue payload.labels 恰含 sc:work（不含任何站別或 sc:legacy——建立當下還不知道定站結果）" -Condition (($queueAfter1[0].payload.labels -join ',') -eq 'sc:work')

# --- 模擬 apply-queue.ps1 已落地：anchor 現在存在，milestone 仍缺 ---
Remove-Item -LiteralPath $T18TmpQueuePath -Force -ErrorAction SilentlyContinue
$fakeAnchor = [pscustomobject]@{
    number = 555
    labels = @([pscustomobject]@{ name = 'sc:work' })
    body   = "work-id: W-legacy-demo`nprimary-repo: acme/legacy-repo`nparticipating-repos:`n- acme/legacy-repo`n"
}
$script:MockResponses[$anchorUrl] = $fakeAnchor

# --- Call 2：anchor 存在，milestone 不存在 ⇒ Stage B-pending ---
$call2 = Invoke-LegacyIntakeFlow
Assert-True -Name "I2 Call2：milestone 不存在 ⇒ Stage=B-pending" -Condition ($call2.Stage -eq 'B-pending') -Detail "Stage=$($call2.Stage)"
$queueAfter2 = Read-QueueFile -QueuePath $T18TmpQueuePath
$queueAfter2 = @($queueAfter2)
Assert-True -Name "I2b 佇列產生 1 筆 create-milestone（產生權=intake）" -Condition (($queueAfter2.Count -eq 1) -and ($queueAfter2[0].action -eq 'create-milestone')) -Detail "action=$($queueAfter2[0].action)"

# --- 模擬落地：milestone 現在存在，另補 identity/uniqueness 所需 mock ---
Remove-Item -LiteralPath $T18TmpQueuePath -Force -ErrorAction SilentlyContinue
$script:MockResponses[$msUrl] = [pscustomobject]@{ number = 10; title = 'W-legacy-demo'; description = 'work-id: W-legacy-demo | primary-anchor: acme/legacy-repo#555' }

# --- Call 3：anchor＋milestone 皆齊 ⇒ Stage C（legacy 定站封頂）---
$call3 = Invoke-LegacyIntakeFlow
Assert-True -Name "I3 Call3：Stage=C-pass" -Condition ($call3.Stage -eq 'C-pass') -Detail "Stage=$($call3.Stage) OverallPass=$($call3.OverallPass)"
Assert-True -Name "I3b 定站結果＝3（legacy-project-b 典型情境，重用 t08 Test-GateInitCriteria 判準①②③④全過）" -Condition ($call3.DeterminedStation -eq 3) -Detail "DeterminedStation=$($call3.DeterminedStation) CapApplied=$($call3.CapApplied)"
Assert-True -Name "I3c CapApplied=false（候選=3 本身未超過上限，cap 未介入，符合群組C『典型情境不需cap出手』的設計預期）" -Condition (-not $call3.CapApplied)

$queueAfter3 = Read-QueueFile -QueuePath $T18TmpQueuePath
$queueAfter3 = @($queueAfter3)
Assert-True -Name "I3d 佇列產生 1 筆 set-labels（產生權=gate，與native共用同一份原子性不變式）" -Condition (($queueAfter3.Count -eq 1) -and ($queueAfter3[0].action -eq 'set-labels'))
$finalLabels = @($queueAfter3[0].payload.labels)
Assert-True -Name "I3e 最終 label 集合含 sc:work／sc:station-3／sc:legacy 三者（badge 隨定站同時掛上）" -Condition (($finalLabels -contains 'sc:work') -and ($finalLabels -contains 'sc:station-3') -and ($finalLabels -contains 'sc:legacy')) -Detail "[$($finalLabels -join ', ')]"
Assert-True -Name "I3f 最終 label 集合恰 3 項（不多不少）" -Condition ($finalLabels.Count -eq 3)

Write-Host ""
Write-Host "--- I4：Invoke-LegacyGateAdvanceProduce 整合——第一個 native gate 通過 ⇒ badge 消失 ---"
$midAnchorForAdv = [pscustomobject]@{ number = 555; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-1' }, [pscustomobject]@{ name = 'sc:legacy' }) }
$overridesStation1 = @{
    '1.glossary' = [pscustomobject]@{ Satisfied = $true; Detail = '人工確認：GLOSSARY.md 齊全' }
    '1.adr'      = [pscustomobject]@{ Satisfied = $true; Detail = '人工確認：DECISIONS.md 含被否決方案' }
    '1.confirm'  = [pscustomobject]@{ Satisfied = $true; Detail = '人工確認：使用者已確認共識' }
}
$advIntegration = Invoke-LegacyGateAdvanceProduce -AnchorIssue $midAnchorForAdv -TargetStation 'sc:station-2' -Tickets @() -ChecklistOverrides $overridesStation1 -Repo 'acme/legacy-repo' -Source 'W-legacy-demo' -QueuePath $T18TmpQueuePath2
Assert-True -Name "I4 Invoke-LegacyGateAdvanceProduce 整體判定 OverallPass=true（重用 T-10 Invoke-GateCheck）" -Condition $advIntegration.OverallPass -Detail $advIntegration.Detail
Assert-True -Name "I4b 推進前 badge 狀態確實為『有』（BadgeBefore.HasLegacyBadge=true）" -Condition $advIntegration.BadgeBefore.HasLegacyBadge
Assert-True -Name "I4c 推進後產生的佇列項 payload.labels 不含 sc:legacy（首個native gate通過後摘除）" -Condition (-not (@($advIntegration.LabelSet.Labels) -contains 'sc:legacy')) -Detail "[$($advIntegration.LabelSet.Labels -join ', ')]"

$queueAdvContent = Read-QueueFile -QueuePath $T18TmpQueuePath2
$queueAdvContent = @($queueAdvContent)
Assert-True -Name "I4d 佇列檔內容與函式回傳一致（真的寫入了，不是只有記憶體內物件）" -Condition (($queueAdvContent.Count -eq 1) -and (-not (@($queueAdvContent[0].payload.labels) -contains 'sc:legacy')))

# 清理臨時檔
Remove-Item -LiteralPath $T18TmpPatPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $T18TmpQueuePath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $T18TmpQueuePath2 -Force -ErrorAction SilentlyContinue

# ============================================================
# 總結
# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)（另有 1 項 RED-CONFIRMED 不計入 FailCount）"
Write-Host "===================================================================="

$reportPath = Join-Path $T18TestDir 't18-offline-test-report.txt'
$reportLines = @("t18-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", "")
$reportLines += $script:TestResults
$reportLines += ""
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($reportPath, ($reportLines -join [Environment]::NewLine), $Utf8Bom)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
