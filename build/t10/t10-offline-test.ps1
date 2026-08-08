#requires -Version 5.1
<#
.SYNOPSIS
    T-10：離線 mock 測試——沙盒可跑，不連 GitHub。比照 T-08／T-21 offline test 手法：
    覆蓋 Invoke-RestMethod 為假函式，攔截 PowerShell 5.1 對「陣列被解卷成純量／$null」的同型風險。

.DESCRIPTION
    涵蓋 gate-check.ps1／gate-advance.ps1／gate-reset.ps1 三檔的核心函式：
      群組 A：Get-CurrentStation／Get-NextStation／Test-StationOrderValid（含站序不可跳三組）
      群組 B：Test-TicketFieldsPresence／Test-Station3FieldsChecklistItem（結構性欄位檢查）
      群組 C：Invoke-StationExitChecklist（RequiresInput fail-closed／override 通過）
      群組 D：Test-WorkStationConsistency／Get-CrossStationChecklist（手動／CI 兩模式）
      群組 E：Invoke-GateCheck 整合（跳站具名缺項、全過、dirty anchor、bypass 旗標）
      群組 F：New-StationAdvanceLabelSet／Test-AdvanceVerified／Invoke-VerifyAdvanceWithRetry（含重試）
      群組 G：Add-QueueItemIfAbsent（gate-advance／gate-reset 各自的本地版本）
      群組 H：Find-LastLegalStationEvent／Invoke-GateReset（兩分支）

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t10-offline-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

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
# Mock 基礎設施：覆蓋 Invoke-RestMethod，支援「單一固定值」與「依序消耗佇列」兩種掛法
# ============================================================
$script:MockResponses = @{}
$script:MockSequences = @{}
$script:MockCallLog = New-Object System.Collections.ArrayList

function Invoke-RestMethod {
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Uri,
        [Parameter()] $Headers,
        [Parameter()] [string]$Method = 'Get',
        [Parameter()] $Body,
        [Parameter()] [string]$ContentType
    )
    [void]$script:MockCallLog.Add([pscustomobject]@{ Uri = $Uri; Method = $Method })
    if ($script:MockSequences.ContainsKey($Uri)) {
        $q = @($script:MockSequences[$Uri])
        if ($q.Count -gt 0) {
            $next = $q[0]
            $script:MockSequences[$Uri] = @($q | Select-Object -Skip 1)
            return $next
        }
    }
    if ($script:MockResponses.ContainsKey($Uri)) { return $script:MockResponses[$Uri] }
    throw "MOCK-MISS：t10-offline-test.ps1 未替這個 URL 設定假回應，無法繼續（也證明沒有真的連網）：$Method $Uri"
}

function Start-Sleep { param([Parameter(Position=0)]$Seconds) } # 離線測試不真的睡；覆蓋內建避免拖慢測試

# 依序 dot-source gate-reset.ps1（-FunctionsOnly 且不觸發任何 CLI 主流程），
# 其內部會 cascade dot-source gate-check.ps1（同樣 -FunctionsOnly），gate-check.ps1 再 cascade
# dot-source ../t21/queue-common.ps1——一次載齊三個檔案的全部函式，比照 T-08 的 cascade 慣例。
# gate-advance.ps1 另外單獨 dot-source（它不被 gate-reset.ps1 cascade 到，函式互不重疊）。
. (Join-Path $ScriptDir 'gate-reset.ps1') -FunctionsOnly
. (Join-Path $ScriptDir 'gate-advance.ps1') -WorkId 'W-off' -PrimaryRepo 'o/r' -AnchorIssue 1 -TargetStation 'sc:station-2' -FunctionsOnly
Set-StrictMode -Version Latest

$FakeHeaders = @{ 'Authorization' = 'Bearer FAKE-TOKEN-NOT-REAL'; 'Accept' = 'application/vnd.github+json' }

# ============================================================
Write-Host "===================================================================="
Write-Host "群組 A：Get-CurrentStation／Get-NextStation／Test-StationOrderValid"
Write-Host "===================================================================="

$issueA0 = [pscustomobject]@{ labels = @() }
$rA0 = Get-CurrentStation -Issue $issueA0
Assert-True -Name "A0 Get-CurrentStation(0 個站別 label) Valid=false" -Condition (-not $rA0.Valid) -Detail $rA0.Detail

$issueA1 = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-2' }) }
$rA1 = Get-CurrentStation -Issue $issueA1
Assert-True -Name "A1 Get-CurrentStation(單一站別 label) Valid=true 且 Station 正確" -Condition ($rA1.Valid -and $rA1.Station -eq 'sc:station-2') -Detail $rA1.Detail

$issueA2 = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:station-2' }, [pscustomobject]@{ name = 'sc:station-3' }) }
$rA2 = Get-CurrentStation -Issue $issueA2
Assert-True -Name "A2 Get-CurrentStation(雙站別 label，髒資料) Valid=false" -Condition (-not $rA2.Valid) -Detail $rA2.Detail

Assert-True -Name "A3 Get-NextStation('sc:station-1')='sc:station-2'" -Condition ((Get-NextStation -Current 'sc:station-1') -eq 'sc:station-2')
Assert-True -Name "A4 Get-NextStation('sc:station-5')='sc:station-done'" -Condition ((Get-NextStation -Current 'sc:station-5') -eq 'sc:station-done')
Assert-True -Name "A5 Get-NextStation('sc:station-done')=`$null（終態無下一站）" -Condition ($null -eq (Get-NextStation -Current 'sc:station-done'))

Assert-True -Name "A6 Test-StationOrderValid(1→2，緊鄰) Valid=true" -Condition (Test-StationOrderValid -Current 'sc:station-1' -Target 'sc:station-2').Valid
Assert-True -Name "A7 Test-StationOrderValid(1→3，跳站) Valid=false【核心：站序不可跳①】" -Condition (-not (Test-StationOrderValid -Current 'sc:station-1' -Target 'sc:station-3').Valid)
Assert-True -Name "A8 Test-StationOrderValid(2→4，跳站) Valid=false【核心：站序不可跳②】" -Condition (-not (Test-StationOrderValid -Current 'sc:station-2' -Target 'sc:station-4').Valid)
Assert-True -Name "A9 Test-StationOrderValid(3→5，跳站) Valid=false【核心：站序不可跳③】" -Condition (-not (Test-StationOrderValid -Current 'sc:station-3' -Target 'sc:station-5').Valid)
Assert-True -Name "A10 Test-StationOrderValid(3→2，倒退) Valid=false" -Condition (-not (Test-StationOrderValid -Current 'sc:station-3' -Target 'sc:station-2').Valid)
Assert-True -Name "A11 Test-StationOrderValid(2→2，原地) Valid=false" -Condition (-not (Test-StationOrderValid -Current 'sc:station-2' -Target 'sc:station-2').Valid)
Assert-True -Name "A12 Test-StationOrderValid(5→done，緊鄰終態) Valid=true" -Condition (Test-StationOrderValid -Current 'sc:station-5' -Target 'sc:station-done').Valid

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 B：Test-TicketFieldsPresence／Test-Station3FieldsChecklistItem"
Write-Host "===================================================================="

$fullBody = "REQ-ID: X`n驗收條件：可執行`ndepends_on: []`nexecutor: fullstack-developer`nbasis: 理由`nscope: 範圍`n測試先行：先紅後綠`n不可逆動作：無"
$rB1 = Test-TicketFieldsPresence -TicketBody $fullBody
Assert-True -Name "B1 Test-TicketFieldsPresence(八項全齊) Satisfied=true" -Condition $rB1.Satisfied -Detail "Missing=[$($rB1.Missing -join ', ')]"

$badBody = "REQ-ID: X`n驗收條件：可執行`nexecutor: fullstack-developer"
$rB2 = Test-TicketFieldsPresence -TicketBody $badBody
Assert-True -Name "B2 Test-TicketFieldsPresence(缺多項) Satisfied=false" -Condition (-not $rB2.Satisfied) -Detail "Missing=[$($rB2.Missing -join ', ')]"
Assert-True -Name "B2b 缺項具名含 basis／scope／depends_on" -Condition (($rB2.Missing -contains 'basis') -and ($rB2.Missing -contains 'scope') -and ($rB2.Missing -contains 'depends_on'))

$rB3 = Test-Station3FieldsChecklistItem -Tickets @()
Assert-True -Name "B3 Test-Station3FieldsChecklistItem(零票) Satisfied=false" -Condition (-not $rB3.Satisfied) -Detail $rB3.Detail

$ticketOk = [pscustomobject]@{ number = 1; body = $fullBody }
$ticketBad = [pscustomobject]@{ number = 2; body = $badBody }
$rB4 = Test-Station3FieldsChecklistItem -Tickets @($ticketOk)
Assert-True -Name "B4 Test-Station3FieldsChecklistItem(單票全齊) Satisfied=true" -Condition $rB4.Satisfied -Detail $rB4.Detail

$rB5 = Test-Station3FieldsChecklistItem -Tickets @($ticketOk, $ticketBad)
Assert-True -Name "B5 Test-Station3FieldsChecklistItem(一好一壞) Satisfied=false 且具名 #2" -Condition ((-not $rB5.Satisfied) -and ($rB5.Detail -like '*#2*')) -Detail $rB5.Detail

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 C：Invoke-StationExitChecklist"
Write-Host "===================================================================="

$rC1 = Invoke-StationExitChecklist -Station 'sc:station-1' -ChecklistOverrides @{}
Assert-True -Name "C1 Invoke-StationExitChecklist(站1，無 overrides) AllSatisfied=false（fail-closed）" -Condition (-not $rC1.AllSatisfied)
Assert-True -Name "C1b 三項皆具名『未提供裁定結果』" -Condition (@($rC1.Items | Where-Object { $_.Detail -like '*未提供裁定結果*' }).Count -eq 3)

$overridesC2 = @{
    '1.glossary' = [pscustomobject]@{ Satisfied = $true; Detail = '人工確認：名詞表完整' }
    '1.adr'      = [pscustomobject]@{ Satisfied = $true; Detail = '人工確認：ADR 已記錄' }
    '1.confirm'  = [pscustomobject]@{ Satisfied = $true; Detail = '人工確認：使用者已確認共識' }
}
$rC2 = Invoke-StationExitChecklist -Station 'sc:station-1' -ChecklistOverrides $overridesC2
Assert-True -Name "C2 Invoke-StationExitChecklist(站1，全 override 為 true) AllSatisfied=true" -Condition $rC2.AllSatisfied

$rC3 = Invoke-StationExitChecklist -Station 'sc:station-3' -Tickets @($ticketOk) -ChecklistOverrides @{ '3.vertical' = [pscustomobject]@{ Satisfied = $true; Detail = '人工確認垂直切片' } }
Assert-True -Name "C3 Invoke-StationExitChecklist(站3，機械項通過＋裁量項 override) AllSatisfied=true" -Condition $rC3.AllSatisfied

$rC4 = Invoke-StationExitChecklist -Station 'sc:station-4' -ChecklistOverrides @{}
Assert-True -Name "C4 Invoke-StationExitChecklist(站4，無 override) AllSatisfied=false 且具名『T-14 範圍』" -Condition ((-not $rC4.AllSatisfied) -and ($rC4.Items[0].Text -like '*T-14*'))

$rC5 = Invoke-StationExitChecklist -Station 'sc:station-5' -ChecklistOverrides @{}
Assert-True -Name "C5 Invoke-StationExitChecklist(站5，無 override) AllSatisfied=false 且具名『T-15a 範圍』" -Condition ((-not $rC5.AllSatisfied) -and ($rC5.Items[0].Text -like '*T-15a*'))

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 D：Test-WorkStationConsistency／Get-CrossStationChecklist"
Write-Host "===================================================================="

$rD1 = Test-WorkStationConsistency -CurrentStation 'sc:station-1' -OpenTickets @()
Assert-True -Name "D1 Test-WorkStationConsistency(零票) Applicable=false 且 Satisfied=true（N/A，不計入 AND）" -Condition ((-not $rD1.Applicable) -and $rD1.Satisfied) -Detail $rD1.Detail

$openT4 = [pscustomobject]@{ number = 10; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }) }
$openT5 = [pscustomobject]@{ number = 11; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }, [pscustomobject]@{ name = 'sc:red-proven' }) }
$rD2 = Test-WorkStationConsistency -CurrentStation 'sc:station-4' -OpenTickets @($openT4, $openT5)
Assert-True -Name "D2 Test-WorkStationConsistency(混合站4/5票，最小站=4，現站=4) Satisfied=true" -Condition $rD2.Satisfied -Detail $rD2.Detail

$rD3 = Test-WorkStationConsistency -CurrentStation 'sc:station-5' -OpenTickets @($openT4, $openT5)
Assert-True -Name "D3 Test-WorkStationConsistency(不一致：現站=5 但最小站應為4) Satisfied=false" -Condition (-not $rD3.Satisfied) -Detail $rD3.Detail

$rD4 = Get-CrossStationChecklist -CurrentStation 'sc:station-2' -OpenTickets @() -GateIdentityLogins @() -ObservedActorLogin 'glennisgood3-dev'
$attrD4 = $rD4 | Where-Object { $_.Id -eq 'all.attribution' }
Assert-True -Name "D4 Get-CrossStationChecklist(手動階段) attribution.Blocking=false" -Condition (-not $attrD4.Blocking) -Detail $attrD4.Detail
Assert-True -Name "D4b 手動階段 identity 項具名回報 actor" -Condition (($rD4 | Where-Object { $_.Id -eq 'all.identity' }).Detail -like "*glennisgood3-dev*")

$rD5 = Get-CrossStationChecklist -CurrentStation 'sc:station-2' -OpenTickets @() -GateIdentityLogins @('github-actions[bot]') -ObservedActorLogin 'github-actions[bot]'
$attrD5 = $rD5 | Where-Object { $_.Id -eq 'all.attribution' }
Assert-True -Name "D5 Get-CrossStationChecklist(CI 階段，合法 actor) Blocking=true 且 Satisfied=true" -Condition ($attrD5.Blocking -and $attrD5.Satisfied) -Detail $attrD5.Detail

$rD6 = Get-CrossStationChecklist -CurrentStation 'sc:station-2' -OpenTickets @() -GateIdentityLogins @('github-actions[bot]') -ObservedActorLogin 'glennisgood3-dev'
$attrD6 = $rD6 | Where-Object { $_.Id -eq 'all.attribution' }
Assert-True -Name "D6 Get-CrossStationChecklist(CI 階段，人手改動) Blocking=true 且 Satisfied=false" -Condition ($attrD6.Blocking -and (-not $attrD6.Satisfied)) -Detail $attrD6.Detail

$rD7 = Get-CrossStationChecklist -CurrentStation 'sc:station-2' -OpenTickets @()
$decD7 = $rD7 | Where-Object { $_.Id -eq 'all.decisions-exemption' }
Assert-True -Name "D7 Get-CrossStationChecklist DECISIONS 豁免項 N/A（T-19 範圍） Blocking=false Satisfied=`$null" -Condition ((-not $decD7.Blocking) -and ($null -eq $decD7.Satisfied)) -Detail $decD7.Detail

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 E：Invoke-GateCheck 整合"
Write-Host "===================================================================="

$anchorE_st1 = [pscustomobject]@{ number = 100; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-1' }) }

$rE1 = Invoke-GateCheck -AnchorIssue $anchorE_st1 -TargetStation 'sc:station-3' -Tickets @()
Assert-True -Name "E1 Invoke-GateCheck(站1 anchor 請求跳到站3) OverallPass=false，Reason=station-order-violation【驗收①之一：1→3】" -Condition ((-not $rE1.OverallPass) -and $rE1.Reason -eq 'station-order-violation') -Detail $rE1.Detail
Assert-True -Name "E1b 具名列出被跳過站 2 的未滿足條件" -Condition ($rE1.Detail -like "*被跳過站 'sc:station-2'*")

$anchorE_st2 = [pscustomobject]@{ number = 101; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-2' }) }
$rE2 = Invoke-GateCheck -AnchorIssue $anchorE_st2 -TargetStation 'sc:station-4' -Tickets @()
Assert-True -Name "E2 Invoke-GateCheck(站2 anchor 請求跳到站4) OverallPass=false【驗收①之二：2→4】" -Condition (-not $rE2.OverallPass) -Detail $rE2.Detail

$anchorE_st3 = [pscustomobject]@{ number = 102; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-3' }) }
$rE3 = Invoke-GateCheck -AnchorIssue $anchorE_st3 -TargetStation 'sc:station-5' -Tickets @()
Assert-True -Name "E3 Invoke-GateCheck(站3 anchor 請求跳到站5) OverallPass=false【驗收①之三：3→5】" -Condition (-not $rE3.OverallPass) -Detail $rE3.Detail

$rE4 = Invoke-GateCheck -AnchorIssue $anchorE_st1 -TargetStation 'sc:station-2' -Tickets @() -ChecklistOverrides @{}
Assert-True -Name "E4 Invoke-GateCheck(站1→2，合法站序但無 override) OverallPass=false，Reason=checklist-unmet" -Condition ((-not $rE4.OverallPass) -and $rE4.Reason -eq 'checklist-unmet') -Detail $rE4.Detail

$overridesE5 = @{
    '1.glossary' = [pscustomobject]@{ Satisfied = $true; Detail = 'ok' }
    '1.adr'      = [pscustomobject]@{ Satisfied = $true; Detail = 'ok' }
    '1.confirm'  = [pscustomobject]@{ Satisfied = $true; Detail = 'ok' }
}
$rE5 = Invoke-GateCheck -AnchorIssue $anchorE_st1 -TargetStation 'sc:station-2' -Tickets @() -ChecklistOverrides $overridesE5
Assert-True -Name "E5 Invoke-GateCheck(站1→2，全 override 通過，零票 N/A) OverallPass=true" -Condition $rE5.OverallPass -Detail $rE5.Detail

$anchorE_dirty = [pscustomobject]@{ number = 103; labels = @() }
$rE6 = Invoke-GateCheck -AnchorIssue $anchorE_dirty -TargetStation 'sc:station-1'
Assert-True -Name "E6 Invoke-GateCheck(anchor 無站別 label，髒資料) OverallPass=false，Reason=dirty-anchor" -Condition ((-not $rE6.OverallPass) -and $rE6.Reason -eq 'dirty-anchor') -Detail $rE6.Detail

$rE7 = Invoke-GateCheck -AnchorIssue $anchorE_st1 -TargetStation 'sc:station-3' -Tickets @() -BypassStationOrderCheck
Assert-True -Name "E7 Invoke-GateCheck(BypassStationOrderCheck 開啟，1→3) 不再因站序被拒（轉而落到 checklist-unmet，因未提供 override）" -Condition ($rE7.Reason -ne 'station-order-violation') -Detail "Reason=$($rE7.Reason)"

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 F：New-StationAdvanceLabelSet／Test-AdvanceVerified／Invoke-VerifyAdvanceWithRetry"
Write-Host "===================================================================="

$anchorF1 = [pscustomobject]@{ number = 200; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-1' }) }
$rF1 = New-StationAdvanceLabelSet -AnchorIssue $anchorF1 -TargetStation 'sc:station-2'
Assert-True -Name "F1 New-StationAdvanceLabelSet 保留非站別 label 且恰含新站別（原子：無舊站別殘留）" -Condition (($rF1 -contains 'sc:work') -and ($rF1 -contains 'sc:station-2') -and (-not ($rF1 -contains 'sc:station-1'))) -Detail "[$($rF1 -join ', ')]"
Assert-True -Name "F1b 站別 label 恰一個" -Condition ((@($rF1 | Where-Object { $_ -match '^sc:station-' })).Count -eq 1)

$issueF2ok = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-2' }) }
$rF2 = Test-AdvanceVerified -Issue $issueF2ok -ExpectedStation 'sc:station-2'
Assert-True -Name "F2 Test-AdvanceVerified(恰為期望站別) Satisfied=true" -Condition $rF2.Satisfied -Detail $rF2.Detail

$issueF3bad = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:station-1' }, [pscustomobject]@{ name = 'sc:station-2' }) }
$rF3 = Test-AdvanceVerified -Issue $issueF3bad -ExpectedStation 'sc:station-2'
Assert-True -Name "F3 Test-AdvanceVerified(雙站別中間態) Satisfied=false" -Condition (-not $rF3.Satisfied) -Detail $rF3.Detail

# 首次即符合 ⇒ Attempts=1
$verifyUrlOk = 'https://api.github.com/repos/o/vf/issues/1'
$script:MockResponses[$verifyUrlOk] = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:station-2' }) }
$rF4 = Invoke-VerifyAdvanceWithRetry -Owner 'o' -Repo 'vf' -IssueNumber 1 -ExpectedStation 'sc:station-2' -Headers $FakeHeaders -RetryDelaySeconds 0
Assert-True -Name "F4 Invoke-VerifyAdvanceWithRetry(首次即符合) Satisfied=true Attempts=1" -Condition ($rF4.Satisfied -and $rF4.Attempts -eq 1) -Detail $rF4.Detail

# 首次不符、重試後符合 ⇒ Attempts=2, Satisfied=true（模擬最終一致性延遲）
$verifyUrlRetry = 'https://api.github.com/repos/o/vfr/issues/2'
$script:MockSequences[$verifyUrlRetry] = @(
    [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:station-1' }) },
    [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:station-2' }) }
)
$rF5 = Invoke-VerifyAdvanceWithRetry -Owner 'o' -Repo 'vfr' -IssueNumber 2 -ExpectedStation 'sc:station-2' -Headers $FakeHeaders -RetryDelaySeconds 0
Assert-True -Name "F5 Invoke-VerifyAdvanceWithRetry(首次不符，重試一次後符合) Satisfied=true Attempts=2【§4.4 重試一次設計】" -Condition ($rF5.Satisfied -and $rF5.Attempts -eq 2) -Detail $rF5.Detail

# 兩次皆不符 ⇒ 判寫入失敗，不宣稱成功
$verifyUrlFail = 'https://api.github.com/repos/o/vff/issues/3'
$script:MockSequences[$verifyUrlFail] = @(
    [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:station-1' }) },
    [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:station-1' }) }
)
$rF6 = Invoke-VerifyAdvanceWithRetry -Owner 'o' -Repo 'vff' -IssueNumber 3 -ExpectedStation 'sc:station-2' -Headers $FakeHeaders -RetryDelaySeconds 0
Assert-True -Name "F6 Invoke-VerifyAdvanceWithRetry(重試一次仍不符) Satisfied=false Attempts=2 且判寫入失敗【核心：不宣稱成功】" -Condition ((-not $rF6.Satisfied) -and $rF6.Attempts -eq 2 -and ($rF6.Detail -like '*不宣稱推進成功*')) -Detail $rF6.Detail

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 G：Add-QueueItemIfAbsent（gate-advance／gate-reset 各自本地版本）"
Write-Host "===================================================================="

$tmpQueuePath = Join-Path $ScriptDir 't10-offline-test-tmp-queue.json'
if (Test-Path -LiteralPath $tmpQueuePath) { Remove-Item -LiteralPath $tmpQueuePath -Force }

$itemG1 = [pscustomobject]@{ action = 'set-labels'; target = [pscustomobject]@{ repo = 'o/g'; issue = 1 }; payload = [pscustomobject]@{ labels = @('sc:station-2') }; source = 'W-g' }
$addG1 = Add-QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemG1
Assert-True -Name "G1 Add-QueueItemIfAbsent(首次加入) Added=true" -Condition $addG1.Added -Detail $addG1.Detail
$afterG1 = @(Read-QueueFile -QueuePath $tmpQueuePath)
Assert-True -Name "G1b 加入後檔內恰 1 筆" -Condition ($afterG1.Count -eq 1)

$addG2 = Add-QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemG1
Assert-True -Name "G2 Add-QueueItemIfAbsent(重複加入，同 action+target+source) Added=false（去重）" -Condition (-not $addG2.Added) -Detail $addG2.Detail
$afterG2 = @(Read-QueueFile -QueuePath $tmpQueuePath)
Assert-True -Name "G2b 去重後仍恰 1 筆" -Condition ($afterG2.Count -eq 1)

Remove-Item -LiteralPath $tmpQueuePath -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 H：Find-LastLegalStationEvent／Invoke-GateReset（deferred-to-CI，程式路徑與離線驗證）"
Write-Host "===================================================================="

$GateBots = @('github-actions[bot]')

# H1：無任何 labeled 事件
$rH1 = Find-LastLegalStationEvent -TimelineEvents @() -GateIdentityLogins $GateBots
Assert-True -Name "H1 Find-LastLegalStationEvent(空 timeline) Found=false" -Condition (-not $rH1.Found) -Detail $rH1.Detail

# H2：有站別事件但全為人手 actor（無合法事件）⇒ 復位分支②
$evHuman1 = [pscustomobject]@{ event = 'labeled'; label = [pscustomobject]@{ name = 'sc:station-1' }; actor = [pscustomobject]@{ login = 'glennisgood3-dev' }; created_at = '2026-08-01T00:00:00Z' }
$evHuman2 = [pscustomobject]@{ event = 'labeled'; label = [pscustomobject]@{ name = 'sc:station-2' }; actor = [pscustomobject]@{ login = 'glennisgood3-dev' }; created_at = '2026-08-02T00:00:00Z' }
$rH2 = Find-LastLegalStationEvent -TimelineEvents @($evHuman1, $evHuman2) -GateIdentityLogins $GateBots
Assert-True -Name "H2 Find-LastLegalStationEvent(全為人手 actor) Found=false" -Condition (-not $rH2.Found) -Detail $rH2.Detail

# H3：混合 actor，最後一筆合法事件在中間（時間序尾端往前找）⇒ 命中該筆而非最新的人手事件
$evBot = [pscustomobject]@{ event = 'labeled'; label = [pscustomobject]@{ name = 'sc:station-2' }; actor = [pscustomobject]@{ login = 'github-actions[bot]' }; created_at = '2026-08-02T00:00:00Z' }
$evHumanLater = [pscustomobject]@{ event = 'labeled'; label = [pscustomobject]@{ name = 'sc:station-3' }; actor = [pscustomobject]@{ login = 'glennisgood3-dev' }; created_at = '2026-08-03T00:00:00Z' }
$rH3 = Find-LastLegalStationEvent -TimelineEvents @($evHuman1, $evBot, $evHumanLater) -GateIdentityLogins $GateBots
Assert-True -Name "H3 Find-LastLegalStationEvent(混合 actor，最後合法事件在中間) Found=true 且 Station=sc:station-2（非最新的人手事件 station-3）" -Condition ($rH3.Found -and $rH3.Station -eq 'sc:station-2') -Detail $rH3.Detail

# H4：Invoke-GateReset 分支①（命中合法事件）
$anchorH4 = [pscustomobject]@{ number = 300; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-3' }) }
$rH4 = Invoke-GateReset -AnchorIssue $anchorH4 -TimelineEvents @($evHuman1, $evBot, $evHumanLater) -GateIdentityLogins $GateBots -Repo 'o/h4'
Assert-True -Name "H4 Invoke-GateReset(分支①命中) Branch=legal-found 且 TargetStation=sc:station-2【驗收③】" -Condition (($rH4.Branch -eq 'legal-found') -and ($rH4.TargetStation -eq 'sc:station-2')) -Detail $rH4.Reason
$h4Labels = @($rH4.QueueItem.payload.labels)
Assert-True -Name "H4b 佇列項為單一次完整集合：含 sc:work（保留）與 sc:station-2（回退），不含 sc:station-3（原髒站別已移除）" -Condition (($h4Labels -contains 'sc:work') -and ($h4Labels -contains 'sc:station-2') -and (-not ($h4Labels -contains 'sc:station-3'))) -Detail "[$($h4Labels -join ', ')]"
Assert-True -Name "H4c 站別 label 恰一個（原子性）" -Condition ((@($h4Labels | Where-Object { $_ -match '^sc:station-' })).Count -eq 1)

# H5：Invoke-GateReset 分支②（無合法事件）
$anchorH5 = [pscustomobject]@{ number = 301; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-2' }) }
$rH5 = Invoke-GateReset -AnchorIssue $anchorH5 -TimelineEvents @($evHuman1, $evHuman2) -GateIdentityLogins $GateBots -Repo 'o/h5'
Assert-True -Name "H5 Invoke-GateReset(分支②無合法事件) Branch=no-legal-event 且 TargetStation=sc:awaiting-user【驗收④】" -Condition (($rH5.Branch -eq 'no-legal-event') -and ($rH5.TargetStation -eq 'sc:awaiting-user')) -Detail $rH5.Reason
$h5Labels = @($rH5.QueueItem.payload.labels)
Assert-True -Name "H5b 佇列項含 sc:awaiting-user 且不含任何 sc:station-*（無合法站別可信，全數移除）" -Condition (($h5Labels -contains 'sc:awaiting-user') -and ((@($h5Labels | Where-Object { $_ -match '^sc:station-' })).Count -eq 0)) -Detail "[$($h5Labels -join ', ')]"

# ============================================================
# 總結
# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Host "===================================================================="

$reportPath = Join-Path $ScriptDir 't10-offline-test-report.txt'
$reportLines = @("t10-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", "")
$reportLines += $script:TestResults
$reportLines += ""
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
