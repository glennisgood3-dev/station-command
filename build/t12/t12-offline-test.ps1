#requires -Version 5.1
<#
.SYNOPSIS
    T-12：離線 mock 測試——沙盒可跑，不連 GitHub。比照 T-08／T-10 offline test 手法：覆蓋
    Invoke-RestMethod 為假函式（含**有狀態**的 issue mock，支援 GET 讀現況／PATCH 寫入並反映在
    後續 GET，用來讓「回滾後 assignee 必為空」這條斷言是對著真的會變化的模擬狀態斷言，不是只斷言
    「佇列裡有沒有那筆項目」）。

.DESCRIPTION
    群組 A：Get-ExecutorBasisDeclaration／Get-DependsOnList／Get-IrreversibleDeclaration（純 regex 解析）
    群組 B：Test-CandidateBlocked／Test-CandidateRunning（含跨站繼承）
    群組 C：Test-DependsOnSatisfied（未解／未關閉／已滿足／空清單）
    群組 D：Get-RunRoutingDefault（四站映射＋站5拒絕）
    群組 E：Select-NextActionableItem 整合——① 站1-3 work 級選件；② 站4 造四張票（blocked／
            depends_on 未滿足／已在跑／合格）驗證三判準過濾，只有第四張進 frontier
    群組 F：【紅燈①】Test-RunProducerAllowed／Add-RunQueueItemGuarded——-SkipEnqueueGuard 開啟時
            斷言「run 不得產生 label 類佇列項」真的失敗（佇列裡真的出現了 set-labels）；關閉後同一
            斷言通過
    群組 G：Invoke-RunDispatch——needsBodyWrite／2nd-layer override／[INVALID]／不可逆動作停手
    群組 H：【紅燈②】Invoke-DispatchFailureRollback——人造中間態 fixture（assignee 已指派於 mock
            GitHub 現況）＋ dispatch 回傳失敗，-SkipRollback 開啟時斷言「回滾後 assignee 必為空」
            （對著有狀態 mock 的現況直接斷言，非僅佇列存在性）真的失敗；關閉後同一斷言通過
    群組 I：run-apply.ps1 的 schema／冪等輔助函式（Test-SetAssigneeSatisfied／
            Test-SetTicketFieldsSatisfied 對有狀態 mock 的正確性）

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t12-offline-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# ⚠️ 用 $T12TestDir 而非常見的 $ScriptDir——理由：下面 dot-source run-dispatch.ps1 會 cascade
# 進 ../t10/gate-check.ps1，該檔宣告未加 Script: 範圍的 $ScriptDir 並指向 t10 目錄，dot-source
# 全程共用同一層作用域，會覆蓋本檔同名變數（實跑抓到的真實 bug：報告一度誤寫進 build/t10/）。
$T12TestDir = $PSScriptRoot

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
# 有狀態 Mock 基礎設施：GET 讀現況／PATCH 寫入並反映在後續 GET（比 t08/t10 的單純固定回應更進一步，
# 專為驗證「套用後現況真的改變」而設計，非僅測「佇列裡有沒有那筆項目」）
# ============================================================
$script:MockIssueState = @{}      # key = "owner/repo#issue" -> pscustomobject（可變）
$script:MockResponses = @{}       # 非 issue 端點的固定回應（如 /user）
$script:MockCallLog = New-Object System.Collections.ArrayList

function New-MockIssue {
    param(
        [string]$Owner, [string]$Repo, [int]$Number, [string]$Title = 'demo',
        [string]$Body = '', [string]$State = 'open',
        [string[]]$Labels = @(), [string[]]$AssigneeLogins = @(), [string]$MilestoneTitle = $null
    )
    $key = "$Owner/$Repo#$Number"
    $issue = [pscustomobject]@{
        number     = $Number
        title      = $Title
        body       = $Body
        state      = $State
        labels     = @($Labels | ForEach-Object { [pscustomobject]@{ name = $_ } })
        assignees  = @($AssigneeLogins | ForEach-Object { [pscustomobject]@{ login = $_ } })
        milestone  = if ($MilestoneTitle) { [pscustomobject]@{ title = $MilestoneTitle } } else { $null }
    }
    $script:MockIssueState[$key] = $issue
    return $issue
}

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

    if ($Uri -match '/repos/([^/]+)/([^/]+)/issues/(\d+)$') {
        $key = "$($Matches[1])/$($Matches[2])#$($Matches[3])"
        if ($Method -eq 'Get') {
            if ($script:MockIssueState.ContainsKey($key)) { return $script:MockIssueState[$key] }
            return $null
        }
        if ($Method -eq 'Patch') {
            if (-not $script:MockIssueState.ContainsKey($key)) {
                throw "MOCK-MISS：PATCH 目標不存在於 mock 現況：$key（測試 fixture 未先造出該 issue）"
            }
            $bodyObj = $Body | ConvertFrom-Json
            $issue = $script:MockIssueState[$key]
            if ($bodyObj.PSObject.Properties.Name -contains 'assignees') {
                $issue.assignees = @($bodyObj.assignees | ForEach-Object { [pscustomobject]@{ login = $_ } })
            }
            if ($bodyObj.PSObject.Properties.Name -contains 'body') {
                $issue.body = $bodyObj.body
            }
            $script:MockIssueState[$key] = $issue
            return $issue
        }
    }

    if ($script:MockResponses.ContainsKey($Uri)) { return $script:MockResponses[$Uri] }

    # 未知端點（例如 issues 列表查詢，未在測試中特別 mock）⇒ 回空陣列，避免整支測試因未預期查詢而炸開
    if ($Uri -match '/issues\?' -or $Uri -match '/milestones\?') { return @() }

    throw "MOCK-MISS：t12-offline-test.ps1 未替這個 URL 設定假回應，無法繼續（也證明沒有真的連網）：$Method $Uri"
}

# 依序 dot-source run-dispatch.ps1（-FunctionsOnly 且不觸發 CLI 主流程），其內部會 cascade
# dot-source run-select.ps1 → run-common.ps1 → ../t10/gate-check.ps1 → ../t21/queue-common.ps1，
# 一次載齊全部函式（比照 T-08／T-10 的 cascade 慣例）。
. (Join-Path $T12TestDir 'run-dispatch.ps1') -WorkId 'W-off' -PrimaryRepo 'o/r' -AnchorIssue 1 -FunctionsOnly
Set-StrictMode -Version Latest

$FakeHeaders = @{ 'Authorization' = 'Bearer FAKE-TOKEN-NOT-REAL'; 'Accept' = 'application/vnd.github+json' }

function New-TempQueuePath {
    param([string]$Prefix)
    return (Join-Path ([System.IO.Path]::GetTempPath()) "t12-$Prefix-$([Guid]::NewGuid().ToString('N').Substring(0,8)).json")
}

# ============================================================
Write-Host '===================================================================='
Write-Host '群組 A：Get-ExecutorBasisDeclaration／Get-DependsOnList／Get-IrreversibleDeclaration'
Write-Host '===================================================================='

$bodyFull = "REQ-ID: X`nexecutor: fullstack-developer`nbasis: 理由 A`ndepends_on: [T-10, T-11]`n不可逆動作：無（純編排，可回復）"
$rA1 = Get-ExecutorBasisDeclaration -Body $bodyFull
Assert-True -Name 'A1 Get-ExecutorBasisDeclaration(全齊) Executor/Basis 皆讀到' -Condition (($rA1.ExecutorPresent) -and ($rA1.Executor -eq 'fullstack-developer') -and ($rA1.BasisPresent) -and ($rA1.Basis -eq '理由 A'))

$bodyExecOnly = "executor: fullstack-developer`n沒有 basis 這行"
$rA2 = Get-ExecutorBasisDeclaration -Body $bodyExecOnly
Assert-True -Name 'A2 Get-ExecutorBasisDeclaration(僅 executor，缺 basis) BasisPresent=false' -Condition (($rA2.ExecutorPresent) -and (-not $rA2.BasisPresent))

$bodyNone = "REQ-ID: X`n沒有 executor 也沒有 basis"
$rA3 = Get-ExecutorBasisDeclaration -Body $bodyNone
Assert-True -Name 'A3 Get-ExecutorBasisDeclaration(皆無) ExecutorPresent=false' -Condition (-not $rA3.ExecutorPresent)

$rA4 = Get-DependsOnList -Body $bodyFull
$rA4 = @($rA4)
Assert-True -Name 'A4 Get-DependsOnList([T-10, T-11]) 解析出 2 項' -Condition (($rA4.Count -eq 2) -and ($rA4[0] -eq 'T-10') -and ($rA4[1] -eq 'T-11')) -Detail "[$($rA4 -join ', ')]"

$rA5 = Get-DependsOnList -Body 'depends_on: []'
$rA5 = @($rA5)
Assert-True -Name 'A5 Get-DependsOnList(空清單) Count=0' -Condition ($rA5.Count -eq 0)

$rA6 = Get-DependsOnList -Body '無此欄位'
$rA6 = @($rA6)
Assert-True -Name 'A6 Get-DependsOnList(無此欄位) Count=0（不拋錯）' -Condition ($rA6.Count -eq 0)

$rA7 = Get-IrreversibleDeclaration -Body $bodyFull
Assert-True -Name 'A7 Get-IrreversibleDeclaration(宣告無) Present=true Value=無' -Condition (($rA7.Present) -and ($rA7.Value -eq '無'))

$rA8 = Get-IrreversibleDeclaration -Body "不可逆動作：有（將對外寄送）"
Assert-True -Name 'A8 Get-IrreversibleDeclaration(宣告有) Present=true Value=有' -Condition (($rA8.Present) -and ($rA8.Value -eq '有'))

$rA9 = Get-IrreversibleDeclaration -Body '（work 級項目，無此欄）'
Assert-True -Name 'A9 Get-IrreversibleDeclaration(無此欄位) Present=false（不拋錯）' -Condition (-not $rA9.Present)

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 B：Test-CandidateBlocked／Test-CandidateRunning'
Write-Host '===================================================================='

$issueClean = [pscustomobject]@{ labels = @(); assignees = @() }
$rB1 = Test-CandidateBlocked -CandidateIssue $issueClean -AnchorIssue $null -IsTicketLevel $false
Assert-True -Name 'B1 Test-CandidateBlocked(無 label) Blocked=false' -Condition (-not $rB1.Blocked)

$issueSelfBlocked = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:blocked' }); assignees = @() }
$rB2 = Test-CandidateBlocked -CandidateIssue $issueSelfBlocked -AnchorIssue $null -IsTicketLevel $false
Assert-True -Name 'B2 Test-CandidateBlocked(自身有 sc:blocked) Blocked=true' -Condition $rB2.Blocked -Detail $rB2.Detail

$anchorBlocked = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:blocked' }) }
$rB3 = Test-CandidateBlocked -CandidateIssue $issueClean -AnchorIssue $anchorBlocked -IsTicketLevel $true
Assert-True -Name 'B3 Test-CandidateBlocked(票級，anchor 有 sc:blocked，跨站繼承) Blocked=true' -Condition $rB3.Blocked -Detail $rB3.Detail

$rB4 = Test-CandidateBlocked -CandidateIssue $issueClean -AnchorIssue $anchorBlocked -IsTicketLevel $false
Assert-True -Name 'B4 Test-CandidateBlocked(work 級不繼承 anchor 自身) Blocked=false（work 級的 candidate 本身就是 anchor，不套用「繼承」邏輯避免自我矛盾）' -Condition (-not $rB4.Blocked)

$issueRunning = [pscustomobject]@{ labels = @(); assignees = @([pscustomobject]@{ login = 'someone' }) }
$rB5 = Test-CandidateRunning -CandidateIssue $issueRunning
Assert-True -Name 'B5 Test-CandidateRunning(有 assignee) Running=true' -Condition $rB5.Running -Detail $rB5.Detail

$rB6 = Test-CandidateRunning -CandidateIssue $issueClean
Assert-True -Name 'B6 Test-CandidateRunning(無 assignee) Running=false' -Condition (-not $rB6.Running)

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 C：Test-DependsOnSatisfied'
Write-Host '===================================================================='

$ticketClosed = [pscustomobject]@{ number = 10; title = 'T-10 · 出口條件檢查器'; body = 'REQ-ID: T-10'; state = 'closed' }
$ticketOpenDep = [pscustomobject]@{ number = 11; title = 'T-11 · 路由表 asset'; body = 'REQ-ID: T-11'; state = 'open' }

$rC1 = Test-DependsOnSatisfied -DependsOn @() -AllTicketsInWork @($ticketClosed, $ticketOpenDep)
Assert-True -Name 'C1 Test-DependsOnSatisfied(空清單) Satisfied=true' -Condition $rC1.Satisfied

$rC2 = Test-DependsOnSatisfied -DependsOn @('T-10') -AllTicketsInWork @($ticketClosed, $ticketOpenDep)
Assert-True -Name 'C2 Test-DependsOnSatisfied(依賴票已關閉) Satisfied=true' -Condition $rC2.Satisfied -Detail $rC2.Detail

$rC3 = Test-DependsOnSatisfied -DependsOn @('T-11') -AllTicketsInWork @($ticketClosed, $ticketOpenDep)
Assert-True -Name 'C3 Test-DependsOnSatisfied(依賴票仍 open) Satisfied=false' -Condition (-not $rC3.Satisfied) -Detail $rC3.Detail

$rC4 = Test-DependsOnSatisfied -DependsOn @('T-99') -AllTicketsInWork @($ticketClosed, $ticketOpenDep)
Assert-True -Name 'C4 Test-DependsOnSatisfied(查無對應票，fail-closed) Satisfied=false 且具名 Unresolved' -Condition ((-not $rC4.Satisfied) -and (@($rC4.Unresolved) -contains 'T-99')) -Detail $rC4.Detail

$rC5 = Test-DependsOnSatisfied -DependsOn @('T-10', 'T-11') -AllTicketsInWork @($ticketClosed, $ticketOpenDep)
Assert-True -Name 'C5 Test-DependsOnSatisfied(一好一壞) Satisfied=false' -Condition (-not $rC5.Satisfied) -Detail $rC5.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 D：Get-RunRoutingDefault'
Write-Host '===================================================================='

Assert-True -Name "D1 站1 Executor 含 brainstormer" -Condition ((Get-RunRoutingDefault -Station 'sc:station-1').Executor -like '*brainstormer*')
Assert-True -Name "D2 站2 Executor 含 planner" -Condition ((Get-RunRoutingDefault -Station 'sc:station-2').Executor -like '*planner*')
Assert-True -Name "D3 站3 Executor 含 kongming 複核" -Condition ((Get-RunRoutingDefault -Station 'sc:station-3').Executor -like '*kongming*')
Assert-True -Name "D4 站4 Executor 含 fullstack-developer" -Condition ((Get-RunRoutingDefault -Station 'sc:station-4').Executor -like '*fullstack-developer*')

$d5Threw = $false
try { Get-RunRoutingDefault -Station 'sc:station-5' | Out-Null } catch { $d5Threw = $true }
Assert-True -Name 'D5 站5 拒絕（雙審 dispatch 屬 gate 職責，run 不派工站5） 拋出例外' -Condition $d5Threw

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 E：Select-NextActionableItem 整合'
Write-Host '===================================================================='

Write-Host '--- E-1：站1-3 work 級選件（anchor 本身即候選） ---'
$anchorSt2 = [pscustomobject]@{ number = 100; title = 'W-e1 · primary anchor'; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-2' }); assignees = @(); body = 'spec 草案 body（無 executor 宣告）' }
$rE1 = Select-NextActionableItem -AnchorIssue $anchorSt2 -Station 'sc:station-2' -WorkId 'W-e1' -PrimaryRepo 'o/e1' -ParticipatingRepos @('o/e1') -Headers $FakeHeaders
Assert-True -Name 'E1 站2 anchor 選件成功，Kind=anchor' -Condition (($rE1.HasCandidate) -and ($rE1.Selected.Kind -eq 'anchor')) -Detail $rE1.Detail
Assert-True -Name 'E1b 站2 anchor 未宣告 executor ⇒ NeedsBodyWrite=true 且 EffectiveExecutor 為 planner 預設' -Condition (($rE1.Selected.NeedsBodyWrite) -and ($rE1.Selected.EffectiveExecutor -like '*planner*'))

Write-Host ''
Write-Host '--- E-2：站4 造四張票（有未解 blocker／depends_on 未完成／已有在跑 executor／三條皆滿足），只有第四張進 frontier ---'
$ticket4Blocked = [pscustomobject]@{ number = 201; title = 'T-A'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }, [pscustomobject]@{ name = 'sc:blocked' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-e2' }; RepoString = 'o/e2' }
$ticket4DepUnmet = [pscustomobject]@{ number = 202; title = 'T-B'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: [T-A]"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-e2' }; RepoString = 'o/e2' }
$ticket4Running = [pscustomobject]@{ number = 203; title = 'T-C'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @([pscustomobject]@{ login = 'already-working' }); milestone = [pscustomobject]@{ title = 'W-e2' }; RepoString = 'o/e2' }
$ticket4Eligible = [pscustomobject]@{ number = 204; title = 'T-D'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-e2' }; RepoString = 'o/e2' }

# T-A 本身要能被 depends_on 解析找到（供 ticket4DepUnmet 查照），故也放進 AllTicketsInWork（透過 mock 列表端點）
$script:MockResponses['https://api.github.com/repos/o/e2/issues?labels=sc:ticket&state=all&per_page=100'] = @($ticket4Blocked, $ticket4DepUnmet, $ticket4Running, $ticket4Eligible)

$anchorSt4 = [pscustomobject]@{ number = 100; title = 'W-e2 · primary anchor'; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-4' }); assignees = @() }
$rE2 = Select-NextActionableItem -AnchorIssue $anchorSt4 -Station 'sc:station-4' -WorkId 'W-e2' -PrimaryRepo 'o/e2' -ParticipatingRepos @('o/e2') -Headers $FakeHeaders

Assert-True -Name 'E2 四張票中恰 1 張進 frontier（合格）' -Condition (@($rE2.Eligible).Count -eq 1) -Detail "Eligible.Count=$(@($rE2.Eligible).Count)"
Assert-True -Name 'E2b 選中的是 #204（三條皆滿足）' -Condition (($rE2.HasCandidate) -and ($rE2.Selected.Number -eq 204))
Assert-True -Name 'E2c 3 張票被排除（共 3 項 Rejected）' -Condition (@($rE2.Rejected).Count -eq 3) -Detail "Rejected.Count=$(@($rE2.Rejected).Count)"

$rejectedByNumber = @{}
foreach ($rj in @($rE2.Rejected)) { $rejectedByNumber[$rj.Number] = $rj }
Assert-True -Name 'E2d #201（blocked）被排除且理由含 blocker' -Condition ($rejectedByNumber.ContainsKey(201) -and ($rejectedByNumber[201].RejectReasons -join '') -like '*blocker*')
Assert-True -Name 'E2e #202（depends_on 未滿足）被排除且理由含 depends_on' -Condition ($rejectedByNumber.ContainsKey(202) -and ($rejectedByNumber[202].RejectReasons -join '') -like '*depends_on*')
Assert-True -Name 'E2f #203（已在跑）被排除且理由含在跑 executor' -Condition ($rejectedByNumber.ContainsKey(203) -and ($rejectedByNumber[203].RejectReasons -join '') -like '*在跑*')

Write-Host ''
Write-Host '--- E-3：站5 票（open 且 sc:red-proven）不進候選清單（雙審屬 gate 職責） ---'
$ticket5RedProven = [pscustomobject]@{ number = 301; title = 'T-E'; body = ''; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }, [pscustomobject]@{ name = 'sc:red-proven' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-e3' }; RepoString = 'o/e3' }
$script:MockResponses['https://api.github.com/repos/o/e3/issues?labels=sc:ticket&state=all&per_page=100'] = @($ticket5RedProven)
$anchorSt5 = [pscustomobject]@{ number = 100; title = 'W-e3 · primary anchor'; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-5' }); assignees = @() }
$rE3 = Select-NextActionableItem -AnchorIssue $anchorSt5 -Station 'sc:station-5' -WorkId 'W-e3' -PrimaryRepo 'o/e3' -ParticipatingRepos @('o/e3') -Headers $FakeHeaders
Assert-True -Name 'E3 站5 red-proven 票不進候選 ⇒ frontier 空' -Condition (-not $rE3.HasCandidate) -Detail $rE3.Detail

Write-Host ''
Write-Host '--- E-4：sc:station-done ⇒ 無可動作項 ---'
$anchorDone = [pscustomobject]@{ number = 100; labels = @([pscustomobject]@{ name = 'sc:station-done' }) }
$rE4 = Select-NextActionableItem -AnchorIssue $anchorDone -Station 'sc:station-done' -WorkId 'W-e4' -PrimaryRepo 'o/e4' -ParticipatingRepos @('o/e4') -Headers $FakeHeaders
Assert-True -Name 'E4 sc:station-done ⇒ HasCandidate=false' -Condition (-not $rE4.HasCandidate)

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 F【紅燈①】：Test-RunProducerAllowed／Add-RunQueueItemGuarded — 產生權守門'
Write-Host '===================================================================='

$illegalLabelItem = [pscustomobject]@{
    action  = 'set-labels'
    target  = [pscustomobject]@{ repo = 'o/guard'; issue = 999 }
    payload = [pscustomobject]@{ labels = @('sc:station-5') }
    source  = 'W-guard-redtest'
}

Write-Host '--- F-RED：-SkipEnqueueGuard 開啟，強制產生 set-labels 佇列項 ---'
$queueRed = New-TempQueuePath -Prefix 'guard-red'
$addRed = Add-RunQueueItemGuarded -QueuePath $queueRed -Item $illegalLabelItem -SkipEnqueueGuard
$afterRed = ConvertTo-SafeArray -RawValue (Read-QueueFile -QueuePath $queueRed)
$afterRed = @($afterRed)
$setLabelsCountRed = @($afterRed | Where-Object { $_.action -eq 'set-labels' }).Count
# 🔴 刻意不走 Assert-True／FailCount：這裡的斷言「run 不得產生 label 類佇列項（佇列中須為 0 筆
# set-labels）」在 -SkipEnqueueGuard 開啟時**應該失敗**（那正是紅燈的定義：證明沒有這層擋，
# 危險的東西真的會進佇列）。若真的失敗才符合預期，比照 T-21/T-22 對 RED 段落的處理方式。
if ($setLabelsCountRed -gt 0) {
    Write-Host "[RED-CONFIRMED] 斷言「run 不得產生 label 類佇列項」如預期失敗：-SkipEnqueueGuard 開啟後，佇列中真的出現了 $setLabelsCountRed 筆 set-labels 項目（Added=$($addRed.Added)）。證明若無產生權守門，run 真的能把 label 類佇列項寫進去——這正是產生權不變式要防的事，不是紙上談兵。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] F-RED：-SkipEnqueueGuard 開啟後 set-labels 真的進了佇列')
} else {
    Write-Host '[UNEXPECTED] F-RED 段落未能重現越權寫入（斷言意外通過）——需人工複查 Add-RunQueueItemGuarded 的 -SkipEnqueueGuard 分支。'
    [void]$script:TestResults.Add('[FAIL] F-RED 未如預期重現越權寫入')
    $script:FailCount++
}
Remove-Item -LiteralPath $queueRed -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '--- F-GREEN：正常模式（無 -SkipEnqueueGuard），同一筆越權項目 ---'
$queueGreen = New-TempQueuePath -Prefix 'guard-green'
$addGreen = Add-RunQueueItemGuarded -QueuePath $queueGreen -Item $illegalLabelItem
$afterGreen = ConvertTo-SafeArray -RawValue (Read-QueueFile -QueuePath $queueGreen)
$afterGreen = @($afterGreen)
$setLabelsCountGreen = @($afterGreen | Where-Object { $_.action -eq 'set-labels' }).Count
Assert-True -Name 'F-GREEN 斷言「run 不得產生 label 類佇列項」通過（正常模式，守門生效）' -Condition ($setLabelsCountGreen -eq 0) -Detail "set-labels 筆數=$setLabelsCountGreen，Added=$($addGreen.Added)，Blocked=$($addGreen.Blocked)"
Assert-True -Name 'F-GREEN Add-RunQueueItemGuarded 回傳 Blocked=true 且具名理由含唯一產生者' -Condition (($addGreen.Blocked) -and ($addGreen.Detail -like '*gate*')) -Detail $addGreen.Detail
Remove-Item -LiteralPath $queueGreen -Force -ErrorAction SilentlyContinue

# 額外驗證：run 的三個合法動作型別皆放行
$queueLegal = New-TempQueuePath -Prefix 'guard-legal'
$legalAssignee = New-SetAssigneeItem -Repo 'o/g' -IssueNumber 1 -Assignees @('u') -Source 'W-g'
$addLegal1 = Add-RunQueueItemGuarded -QueuePath $queueLegal -Item $legalAssignee
Assert-True -Name 'F-extra set-assignee 屬合法動作，放行' -Condition ($addLegal1.Added -and (-not $addLegal1.Blocked))
$legalBody = New-SetTicketFieldsItem -Repo 'o/g' -IssueNumber 1 -Body 'x' -Source 'W-g2'
$addLegal2 = Add-RunQueueItemGuarded -QueuePath $queueLegal -Item $legalBody
Assert-True -Name 'F-extra set-ticket-fields 屬合法動作，放行' -Condition ($addLegal2.Added -and (-not $addLegal2.Blocked))
Remove-Item -LiteralPath $queueLegal -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 G：Invoke-RunDispatch'
Write-Host '===================================================================='

$queueG = New-TempQueuePath -Prefix 'dispatch'

Write-Host '--- G-1：needsBodyWrite=true（work 級 anchor，未宣告 executor）⇒ 產生 set-ticket-fields ＋ set-assignee ---'
$selG1 = $rE1.Selected
$rG1 = Invoke-RunDispatch -Selected $selG1 -QueuePath $queueG -AssigneeLogin 'glennisgood3-dev' -WorkId 'W-e1'
Assert-True -Name 'G1 Status=dispatch-ready' -Condition ($rG1.Status -eq 'dispatch-ready') -Detail ($rG1.Lines -join ' | ')
$queueAfterG1 = ConvertTo-SafeArray -RawValue (Read-QueueFile -QueuePath $queueG)
$queueAfterG1 = @($queueAfterG1)
Assert-True -Name 'G1b 佇列含 1 筆 set-ticket-fields ＋ 1 筆 set-assignee' -Condition ((@($queueAfterG1 | Where-Object { $_.action -eq 'set-ticket-fields' }).Count -eq 1) -and (@($queueAfterG1 | Where-Object { $_.action -eq 'set-assignee' }).Count -eq 1)) -Detail "共 $($queueAfterG1.Count) 筆"
Assert-True -Name 'G1c set-assignee payload.assignees=[glennisgood3-dev]' -Condition ((@($queueAfterG1 | Where-Object { $_.action -eq 'set-assignee' })[0]).payload.assignees -contains 'glennisgood3-dev')
Remove-Item -LiteralPath $queueG -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '--- G-2：票已宣告 executor+basis（2nd layer override）⇒ 不產生 set-ticket-fields，只產生 set-assignee ---'
$queueG2 = New-TempQueuePath -Prefix 'dispatch2'
$selG2 = $rE2.Selected   # #204，body 已含 executor/basis
Assert-True -Name 'G2-precheck 選中票 NeedsBodyWrite=false（body 已宣告）' -Condition (-not $selG2.NeedsBodyWrite)
$rG2 = Invoke-RunDispatch -Selected $selG2 -QueuePath $queueG2 -AssigneeLogin 'glennisgood3-dev' -WorkId 'W-e2'
Assert-True -Name 'G2 Status=dispatch-ready' -Condition ($rG2.Status -eq 'dispatch-ready')
$queueAfterG2 = ConvertTo-SafeArray -RawValue (Read-QueueFile -QueuePath $queueG2)
$queueAfterG2 = @($queueAfterG2)
Assert-True -Name 'G2b 佇列只含 1 筆（set-assignee，無 set-ticket-fields）' -Condition (($queueAfterG2.Count -eq 1) -and ($queueAfterG2[0].action -eq 'set-assignee'))
Remove-Item -LiteralPath $queueG2 -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '--- G-3：[INVALID]（executor 有宣告但缺 basis）⇒ 拒絕，不產生任何佇列項 ---'
$issueInvalid = [pscustomobject]@{ number = 401; title = 'T-INVALID'; body = "executor: fullstack-developer`n（無 basis 這行）"; assignees = @() }
$declInvalid = Get-ExecutorBasisDeclaration -Body $issueInvalid.body
$selInvalid = [pscustomobject]@{
    Kind = 'ticket'; RepoString = 'o/g3'; Number = 401; Title = 'T-INVALID'; Issue = $issueInvalid
    Invalid = $true; InvalidReason = '[INVALID] 票 body 已宣告 executor 但缺 basis'
    EffectiveExecutor = $null; EffectiveBasis = $null; NeedsBodyWrite = $false
}
$queueG3 = New-TempQueuePath -Prefix 'dispatch3'
$rG3 = Invoke-RunDispatch -Selected $selInvalid -QueuePath $queueG3 -AssigneeLogin 'glennisgood3-dev' -WorkId 'W-g3'
Assert-True -Name 'G3 Status=invalid' -Condition ($rG3.Status -eq 'invalid') -Detail ($rG3.Lines -join ' | ')
Assert-True -Name 'G3b 佇列檔未產生任何內容' -Condition (-not (Test-Path -LiteralPath $queueG3))

Write-Host ''
Write-Host '--- G-4：第八欄「不可逆動作：有」⇒ dispatch 前停手，不產生任何佇列項 ---'
$issueIrr = [pscustomobject]@{ number = 402; title = 'T-IRR'; body = "executor: fullstack-developer`nbasis: 理由`n不可逆動作：有（將對外寄送 email）"; assignees = @() }
$selIrr = [pscustomobject]@{
    Kind = 'ticket'; RepoString = 'o/g4'; Number = 402; Title = 'T-IRR'; Issue = $issueIrr
    Invalid = $false; InvalidReason = ''
    EffectiveExecutor = 'fullstack-developer'; EffectiveBasis = '理由'; NeedsBodyWrite = $false
}
$queueG4 = New-TempQueuePath -Prefix 'dispatch4'
$rG4 = Invoke-RunDispatch -Selected $selIrr -QueuePath $queueG4 -AssigneeLogin 'glennisgood3-dev' -WorkId 'W-g4'
Assert-True -Name 'G4 Status=irreversible-stop（§5.3a 停止條件①）' -Condition ($rG4.Status -eq 'irreversible-stop') -Detail ($rG4.Lines -join ' | ')
Assert-True -Name 'G4b 佇列檔未產生任何內容（dispatch 前擋下）' -Condition (-not (Test-Path -LiteralPath $queueG4))

Write-Host ''
Write-Host '--- G-5：第八欄「不可逆動作：無」⇒ 正常放行，不停手 ---'
$issueIrrNo = [pscustomobject]@{ number = 403; title = 'T-IRR-NO'; body = "executor: fullstack-developer`nbasis: 理由`n不可逆動作：無"; assignees = @() }
$selIrrNo = [pscustomobject]@{
    Kind = 'ticket'; RepoString = 'o/g5'; Number = 403; Title = 'T-IRR-NO'; Issue = $issueIrrNo
    Invalid = $false; InvalidReason = ''
    EffectiveExecutor = 'fullstack-developer'; EffectiveBasis = '理由'; NeedsBodyWrite = $false
}
$queueG5 = New-TempQueuePath -Prefix 'dispatch5'
$rG5 = Invoke-RunDispatch -Selected $selIrrNo -QueuePath $queueG5 -AssigneeLogin 'glennisgood3-dev' -WorkId 'W-g5'
Assert-True -Name 'G5 Status=dispatch-ready（不可逆動作：無，正常放行）' -Condition ($rG5.Status -eq 'dispatch-ready')
Remove-Item -LiteralPath $queueG5 -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 H【紅燈②】：Invoke-DispatchFailureRollback — 人造中間態 fixture'
Write-Host '===================================================================='

# 人造中間態：mock GitHub 現況為「assignee 已指派」（模擬 run 稍早已指派、dispatch 隨後失敗）
$rollbackOwner = 'o'; $rollbackRepo = 'hrb'; $rollbackIssueNum = 501
New-MockIssue -Owner $rollbackOwner -Repo $rollbackRepo -Number $rollbackIssueNum -AssigneeLogins @('glennisgood3-dev') | Out-Null

# 探測函式：對「assignees 應為空」的期望值直接查現況（不透過佇列，是否真的空）
function Test-MockAssigneeIsEmpty {
    param([string]$Repo, [int]$Issue, [hashtable]$Headers)
    $probeItem = New-SetAssigneeItem -Repo $Repo -IssueNumber $Issue -Assignees @() -Source 'probe'
    return Test-SetAssigneeSatisfied -Item $probeItem -Headers $Headers
}

$rollbackTargetRepo = "$rollbackOwner/$rollbackRepo"
$preCheck = Test-MockAssigneeIsEmpty -Repo $rollbackTargetRepo -Issue $rollbackIssueNum -Headers $FakeHeaders
Assert-True -Name 'H-precheck fixture 就緒：套用前 mock 現況 assignee 非空（模擬已指派）' -Condition (-not $preCheck.Satisfied) -Detail $preCheck.Detail

Write-Host ''
Write-Host '--- H-RED：-SkipRollback 開啟，dispatch 失敗但不產生回滾佇列項 ---'
$queueRb = New-TempQueuePath -Prefix 'rollback'
$rH_red = Invoke-DispatchFailureRollback -TargetRepo $rollbackTargetRepo -TargetIssue $rollbackIssueNum -Reason 'sub-agent 逾時無回應（紅燈驗證用理由）' -QueuePath $queueRb -Source 'W-hrb' -SkipRollback
Write-Host ($rH_red.Lines -join [Environment]::NewLine)
# 因為 -SkipRollback 沒有產生佇列項，模擬「使用者忘記真的落地」——即使真的跑了 run-apply.ps1，
# 也沒有東西可套用；直接對 mock 現況斷言「assignee 必為空」
$postRed = Test-MockAssigneeIsEmpty -Repo $rollbackTargetRepo -Issue $rollbackIssueNum -Headers $FakeHeaders
# 🔴 刻意不走 Assert-True／FailCount：斷言「回滾後 assignee 必為空」在 -SkipRollback 開啟時
# **應該失敗**（assignee 依然殘留＝現況仍是 Satisfied=false），若真的失敗才符合預期。
if (-not $postRed.Satisfied) {
    Write-Host "[RED-CONFIRMED] 斷言「回滾後 assignee 必為空」如預期失敗：-SkipRollback 開啟後未產生回滾佇列項（RollbackAdded=$($rH_red.RollbackAdded)），mock 現況 assignee 依然殘留（$($postRed.Detail)）。證明若無回滾邏輯，assignee 真的會卡在殘留狀態——這正是「立即移除該 assignee」條款要防的事。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] H-RED：-SkipRollback 開啟後 assignee 真的殘留')
} else {
    Write-Host '[UNEXPECTED] H-RED 段落未能重現殘留（斷言意外通過）——需人工複查 Invoke-DispatchFailureRollback 的 -SkipRollback 分支。'
    [void]$script:TestResults.Add('[FAIL] H-RED 未如預期重現殘留')
    $script:FailCount++
}
Remove-Item -LiteralPath $queueRb -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '--- H-GREEN：正常模式（無 -SkipRollback），同一份 fixture 重來一次，套用回滾項目後直接驗證 mock 現況 ---'
# 重置 fixture（回到「已指派」的中間態）
New-MockIssue -Owner $rollbackOwner -Repo $rollbackRepo -Number $rollbackIssueNum -AssigneeLogins @('glennisgood3-dev') | Out-Null
$preCheck2 = Test-MockAssigneeIsEmpty -Repo $rollbackTargetRepo -Issue $rollbackIssueNum -Headers $FakeHeaders
Assert-True -Name 'H-precheck2 重置後 fixture 仍為「已指派」' -Condition (-not $preCheck2.Satisfied)

$queueRb2 = New-TempQueuePath -Prefix 'rollback-green'
$rH_green = Invoke-DispatchFailureRollback -TargetRepo $rollbackTargetRepo -TargetIssue $rollbackIssueNum -Reason 'sub-agent 逾時無回應' -QueuePath $queueRb2 -Source 'W-hrb'
Assert-True -Name 'H-GREEN Status=rolled-back 且 RollbackAdded=true' -Condition (($rH_green.Status -eq 'rolled-back') -and $rH_green.RollbackAdded) -Detail ($rH_green.Lines -join ' | ')

# 模擬 run-apply.ps1 的套用步驟：讀佇列裡的 set-assignee 項目，直接呼叫 Invoke-SetAssigneeWrite 套用到 mock
$queueItemsRb2 = ConvertTo-SafeArray -RawValue (Read-QueueFile -QueuePath $queueRb2)
$queueItemsRb2 = @($queueItemsRb2)
Assert-True -Name 'H-GREEN 佇列含恰 1 筆 set-assignee(assignees=[])' -Condition (($queueItemsRb2.Count -eq 1) -and ($queueItemsRb2[0].action -eq 'set-assignee') -and (@($queueItemsRb2[0].payload.assignees).Count -eq 0))

$rbApplyItem = $queueItemsRb2[0]
$rbRepoObj = Split-RepoString -RepoString $rbApplyItem.target.repo
Invoke-SetAssigneeWrite -Repo $rbRepoObj -IssueNumber ([int]$rbApplyItem.target.issue) -Assignees $rbApplyItem.payload.assignees -Headers $FakeHeaders

$postGreen = Test-MockAssigneeIsEmpty -Repo $rollbackTargetRepo -Issue $rollbackIssueNum -Headers $FakeHeaders
Assert-True -Name 'H-GREEN 核心斷言：回滾佇列項套用後，mock GitHub 現況 assignee 必為空' -Condition $postGreen.Satisfied -Detail $postGreen.Detail
Remove-Item -LiteralPath $queueRb2 -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 I：run-apply.ps1 輔助函式（Test-SetAssigneeSatisfied／Test-SetTicketFieldsSatisfied 對有狀態 mock）'
Write-Host '===================================================================='

$applyOwner = 'o'; $applyRepo = 'iapply'; $applyIssueNum = 601
New-MockIssue -Owner $applyOwner -Repo $applyRepo -Number $applyIssueNum -Body 'original body' -AssigneeLogins @() | Out-Null
$applyTargetRepo = "$applyOwner/$applyRepo"

$itemAssign = New-SetAssigneeItem -Repo $applyTargetRepo -IssueNumber $applyIssueNum -Assignees @('new-worker') -Source 'W-i'
$rI1 = Test-SetAssigneeSatisfied -Item $itemAssign -Headers $FakeHeaders
Assert-True -Name 'I1 套用前 Test-SetAssigneeSatisfied=false（現況為空，期望非空）' -Condition (-not $rI1.Satisfied) -Detail $rI1.Detail

$repoObjI = Split-RepoString -RepoString $applyTargetRepo
Invoke-SetAssigneeWrite -Repo $repoObjI -IssueNumber $applyIssueNum -Assignees @('new-worker') -Headers $FakeHeaders
$rI2 = Test-SetAssigneeSatisfied -Item $itemAssign -Headers $FakeHeaders
Assert-True -Name 'I2 套用後 Test-SetAssigneeSatisfied=true（現況已符合）' -Condition $rI2.Satisfied -Detail $rI2.Detail

$itemBody = New-SetTicketFieldsItem -Repo $applyTargetRepo -IssueNumber $applyIssueNum -Body "original body`n`n---`nexecutor: x`nbasis: y`n" -Source 'W-i2'
$rI3 = Test-SetTicketFieldsSatisfied -Item $itemBody -Headers $FakeHeaders
Assert-True -Name 'I3 套用前 Test-SetTicketFieldsSatisfied=false（body 尚未更新）' -Condition (-not $rI3.Satisfied)

Invoke-SetTicketFieldsWrite -Repo $repoObjI -IssueNumber $applyIssueNum -Body $itemBody.payload.body -Headers $FakeHeaders
$rI4 = Test-SetTicketFieldsSatisfied -Item $itemBody -Headers $FakeHeaders
Assert-True -Name 'I4 套用後 Test-SetTicketFieldsSatisfied=true（body 已符合）' -Condition $rI4.Satisfied -Detail $rI4.Detail

# CRLF/LF 正規化容忍（沿用 t21 ConvertTo-NormalizedText）
$itemBodyCRLF = New-SetTicketFieldsItem -Repo $applyTargetRepo -IssueNumber $applyIssueNum -Body ($itemBody.payload.body -replace "`n", "`r`n") -Source 'W-i3'
$rI5 = Test-SetTicketFieldsSatisfied -Item $itemBodyCRLF -Headers $FakeHeaders
Assert-True -Name 'I5 換行正規化：CRLF 版本的期望值與現有 LF body 仍判定相符' -Condition $rI5.Satisfied -Detail $rI5.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Host '===================================================================='

$reportPath = Join-Path $T12TestDir 't12-offline-test-report.txt'
$reportLines = @("t12-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", '')
$reportLines += $script:TestResults
$reportLines += ''
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
