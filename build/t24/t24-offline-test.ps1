#requires -Version 5.1
<#
.SYNOPSIS
    T-24：離線 mock 測試——沙盒可跑，不連 GitHub。比照 T-12/T-13/T-14 offline test 手法：覆蓋
    Invoke-RestMethod 為假函式（有狀態 issue mock，支援 GET 讀現況／PATCH 寫入並反映在後續 GET；
    另 mock 站 4 票集列表端點）。

.DESCRIPTION
    群組 A：Get-LoopStationKind（1/2/3→human-gate，4/5→autonomous，done→done，未知拋錯）
    群組 B：Test-CostLimitState（未提供檔案／50%／80%／100%／缺 percentUsed 拋錯）
    群組 C：Test-NoConfirmationPrompts（乾淨輸出 vs 命中違規樣式）
    群組 D：Test-ReworkStopCondition（0/1/2 次先前 rework 的判定）
    群組 E：Get-LoopCandidatePool（一般模式僅 Eligible／SkipFrontierFilter 模式含 Rejected／
            排除清單生效）
    群組 F【紅燈①＋綠燈①】：Invoke-StationRunLoop 三判準過濾——四張人造票（blocked／
            depends_on 未滿足／已在跑／合格），-SkipFrontierFilter 開啟時斷言「loop 只會派工
            frontier 內合格票」真的失敗（選中並派工了本應被拒的 #201）；關閉後同一斷言通過
            （只派工 #204，其餘三張從未進佇列）。
    群組 G【紅燈③＋綠燈③】：Invoke-StationRunLoop 不可逆前停手——單張票宣告「不可逆動作：有」，
            -SkipIrreversibleHalt 開啟時斷言「dispatch 前必先查第八欄」真的失敗（該票真的被
            派工，佇列出現 set-assignee，loop 也沒有以停因①停手）；關閉後同一斷言通過（佇列
            維持空，loop 以停因①停手）。
    群組 H：停因②（同一票 rework 2 次仍 fail）——連續三次 gate 判定皆 fail，驗證恰好安排兩次
            rework 後第三次觸發停手，且全程只選中同一張票。
    群組 I：停因③（work 位於站 1/2/3）——恰一輪、恰一次派工後停手。
    群組 J：停因⑤（frontier 空）——空候選集。
    群組 K：停因④（scope 需變更）——GateResultProvider 回報 ScopeChangeNeeded。
    群組 L：停因⑥（外廠成本達上限）——50%/80% 僅告警續跑、100% 停手；且停手前已產出的
            RoundSummaries 照常保留（不被清空）。
    群組 M：驗收⑥ 機械化檢查——多輪混合情境（pass/rework/stop）之後，對整段 Lines 掃描確認
            Clean=true；另以負向 fixture 證明掃描器真的會抓到違規（非恆真）。
    群組 N：run 產生權邊界——彙整前述所有情境產生的佇列項，逐筆斷言 action 僅出現於
            {set-assignee, set-ticket-fields}，從未出現 set-labels／close-issue／create-issue／
            create-milestone。
    群組 O：Get-StopReasonText／Test-StopReasonRequiresNotification（六條窮舉具名文字與通知範圍
            ②③④⑥＝true，①⑤＝false）。

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t24-offline-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# ⚠️ 用 $T24TestDir 而非常見的 $ScriptDir——理由同 run-loop.ps1／t12-offline-test.ps1：dot-source
# run-loop.ps1 會 cascade 進 ../t12/run-common.ps1 → ../t10/gate-check.ps1（該檔宣告未加 Script:
# 範圍的 $ScriptDir 並指向 t10 目錄），dot-source 全程共用同一層作用域，會覆蓋本檔同名變數。
$T24TestDir = $PSScriptRoot

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
# 有狀態 Mock 基礎設施（比照 t12-offline-test.ps1，另加站 4 票集列表端點的固定回應支援）
# ============================================================
$script:MockIssueState = @{}
$script:MockResponses = @{}

function New-MockIssue {
    param(
        [string]$Owner, [string]$Repo, [int]$Number, [string]$Title = 'demo',
        [string]$Body = '', [string]$State = 'open',
        [string[]]$Labels = @(), [string[]]$AssigneeLogins = @(), [string]$MilestoneTitle = $null
    )
    $key = "$Owner/$Repo#$Number"
    $issue = [pscustomobject]@{
        number    = $Number
        title     = $Title
        body      = $Body
        state     = $State
        labels    = @($Labels | ForEach-Object { [pscustomobject]@{ name = $_ } })
        assignees = @($AssigneeLogins | ForEach-Object { [pscustomobject]@{ login = $_ } })
        milestone = if ($MilestoneTitle) { [pscustomobject]@{ title = $MilestoneTitle } } else { $null }
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
    if ($Uri -match '/repos/([^/]+)/([^/]+)/issues/(\d+)$') {
        $key = "$($Matches[1])/$($Matches[2])#$($Matches[3])"
        if ($Method -eq 'Get') {
            if ($script:MockIssueState.ContainsKey($key)) { return $script:MockIssueState[$key] }
            return $null
        }
        if ($Method -eq 'Patch') {
            if (-not $script:MockIssueState.ContainsKey($key)) {
                throw "MOCK-MISS：PATCH 目標不存在於 mock 現況：$key"
            }
            $bodyObj = $Body | ConvertFrom-Json
            $issue = $script:MockIssueState[$key]
            if ($bodyObj.PSObject.Properties.Name -contains 'assignees') {
                $issue.assignees = @($bodyObj.assignees | ForEach-Object { [pscustomobject]@{ login = $_ } })
            }
            if ($bodyObj.PSObject.Properties.Name -contains 'body') { $issue.body = $bodyObj.body }
            $script:MockIssueState[$key] = $issue
            return $issue
        }
    }

    if ($script:MockResponses.ContainsKey($Uri)) { return $script:MockResponses[$Uri] }

    if ($Uri -match '/issues\?' -or $Uri -match '/milestones\?') { return @() }

    throw "MOCK-MISS：t24-offline-test.ps1 未替這個 URL 設定假回應，無法繼續（也證明沒有真的連網）：$Method $Uri"
}

. (Join-Path $T24TestDir 'run-loop.ps1') -FunctionsOnly
Set-StrictMode -Version Latest

$FakeHeaders = @{ 'Authorization' = 'Bearer FAKE-TOKEN-NOT-REAL'; 'Accept' = 'application/vnd.github+json' }

function New-TempQueuePath {
    param([string]$Prefix)
    return (Join-Path ([System.IO.Path]::GetTempPath()) "t24-$Prefix-$([Guid]::NewGuid().ToString('N').Substring(0,8)).json")
}

function New-TempCostFile {
    param([Parameter(Mandatory)][double]$PercentUsed, [string]$Provider = 'gemini', [string]$LimitType = 'quota')
    $path = Join-Path ([System.IO.Path]::GetTempPath()) "t24-cost-$([Guid]::NewGuid().ToString('N').Substring(0,8)).json"
    $obj = @{ workId = 'W-cost-demo'; percentUsed = $PercentUsed; provider = $Provider; limitType = $LimitType }
    ($obj | ConvertTo-Json -Compress) | Out-File -LiteralPath $path -Encoding utf8
    return $path
}

# 全域佇列項彙整（供群組 N「run 產生權邊界」跨情境彙整檢查）
$script:AllProducedQueueItems = New-Object System.Collections.ArrayList
function Collect-QueueItems {
    param([Parameter(Mandatory)][string]$QueuePath)
    if (-not (Test-Path -LiteralPath $QueuePath)) { return }
    # PS 5.1/StrictMode 陷阱③：ConvertTo-SafeArray／Read-QueueFile 內部皆用 `return ,@(...)`
    # 保護陣列型別，此處不可直接 `@(函式呼叫本身)`——先賦值再對已賦值變數包 @()（見 t12-offline-
    # test.ps1 同型先例）。
    $itemsRaw = ConvertTo-SafeArray -RawValue (Read-QueueFile -QueuePath $QueuePath)
    $items = @($itemsRaw)
    foreach ($it in $items) { [void]$script:AllProducedQueueItems.Add($it) }
}

# ============================================================
Write-Host '===================================================================='
Write-Host '群組 A：Get-LoopStationKind'
Write-Host '===================================================================='
Assert-True -Name 'A1 station-1 => human-gate' -Condition ((Get-LoopStationKind -Station 'sc:station-1') -eq 'human-gate')
Assert-True -Name 'A2 station-2 => human-gate' -Condition ((Get-LoopStationKind -Station 'sc:station-2') -eq 'human-gate')
Assert-True -Name 'A3 station-3 => human-gate' -Condition ((Get-LoopStationKind -Station 'sc:station-3') -eq 'human-gate')
Assert-True -Name 'A4 station-4 => autonomous' -Condition ((Get-LoopStationKind -Station 'sc:station-4') -eq 'autonomous')
Assert-True -Name 'A5 station-5 => autonomous' -Condition ((Get-LoopStationKind -Station 'sc:station-5') -eq 'autonomous')
Assert-True -Name 'A6 station-done => done' -Condition ((Get-LoopStationKind -Station 'sc:station-done') -eq 'done')
$a7Threw = $false
try { Get-LoopStationKind -Station 'sc:bogus' | Out-Null } catch { $a7Threw = $true }
Assert-True -Name 'A7 未知站別拋錯' -Condition $a7Threw

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 B：Test-CostLimitState'
Write-Host '===================================================================='
$b1 = Test-CostLimitState -CostStatePath ''
Assert-True -Name 'B1 未提供檔案 => 0% 不停不警' -Condition ((-not $b1.Reached100) -and (-not $b1.Warn50) -and (-not $b1.Warn80) -and ($b1.PercentUsed -eq 0)) -Detail $b1.Detail

$b2Path = New-TempCostFile -PercentUsed 50
$b2 = Test-CostLimitState -CostStatePath $b2Path
Assert-True -Name 'B2 50% => Warn50=true，Reached100=false' -Condition ($b2.Warn50 -and (-not $b2.Reached100) -and (-not $b2.Warn80)) -Detail $b2.Detail
Remove-Item -LiteralPath $b2Path -Force

$b3Path = New-TempCostFile -PercentUsed 85
$b3 = Test-CostLimitState -CostStatePath $b3Path
Assert-True -Name 'B3 85% => Warn80=true，Reached100=false' -Condition ($b3.Warn80 -and (-not $b3.Reached100)) -Detail $b3.Detail
Remove-Item -LiteralPath $b3Path -Force

$b4Path = New-TempCostFile -PercentUsed 100
$b4 = Test-CostLimitState -CostStatePath $b4Path
Assert-True -Name 'B4 100% => Reached100=true' -Condition ($b4.Reached100) -Detail $b4.Detail
Remove-Item -LiteralPath $b4Path -Force

$b5Path = Join-Path ([System.IO.Path]::GetTempPath()) "t24-cost-bad-$([Guid]::NewGuid().ToString('N').Substring(0,8)).json"
'{"workId":"W-x"}' | Out-File -LiteralPath $b5Path -Encoding utf8
$b5Threw = $false
try { Test-CostLimitState -CostStatePath $b5Path | Out-Null } catch { $b5Threw = $true }
Assert-True -Name 'B5 缺 percentUsed 欄位 => 拋錯（fail-closed，非默認 0%）' -Condition $b5Threw
Remove-Item -LiteralPath $b5Path -Force

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 C：Test-NoConfirmationPrompts'
Write-Host '===================================================================='
$c1 = Test-NoConfirmationPrompts -OutputLines @('派工完成，繼續下一輪', '票 o/r#1 gate 判定：PASS')
Assert-True -Name 'C1 乾淨輸出 => Clean=true' -Condition $c1.Clean -Detail $c1.Detail
$c2 = Test-NoConfirmationPrompts -OutputLines @('一切正常', '是否確認要繼續？')
Assert-True -Name 'C2 含確認提問樣式 => Clean=false（掃描器真的抓得到，非恆真）' -Condition (-not $c2.Clean) -Detail $c2.Detail
$c3 = Test-NoConfirmationPrompts -OutputLines @('Proceed? (y/n)')
Assert-True -Name 'C3 英文 y/n 樣式亦命中' -Condition (-not $c3.Clean) -Detail $c3.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 D：Test-ReworkStopCondition'
Write-Host '===================================================================='
$d1 = Test-ReworkStopCondition -GateFailed $false -PriorReworkCount 0
Assert-True -Name 'D1 未 fail => 不停不 rework' -Condition ((-not $d1.Stop) -and (-not $d1.ShouldRework))
$d2 = Test-ReworkStopCondition -GateFailed $true -PriorReworkCount 0
Assert-True -Name 'D2 首次 fail（先前 0 次）=> 安排第 1 次 rework，不停' -Condition ((-not $d2.Stop) -and $d2.ShouldRework -and ($d2.NewReworkCount -eq 1))
$d3 = Test-ReworkStopCondition -GateFailed $true -PriorReworkCount 1
Assert-True -Name 'D3 第二次 fail（先前 1 次）=> 安排第 2 次 rework，不停' -Condition ((-not $d3.Stop) -and $d3.ShouldRework -and ($d3.NewReworkCount -eq 2))
$d4 = Test-ReworkStopCondition -GateFailed $true -PriorReworkCount 2
Assert-True -Name 'D4 第三次 fail（已 rework 2 次）=> 停手（停因②）' -Condition ($d4.Stop -and (-not $d4.ShouldRework)) -Detail $d4.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 E：Get-LoopCandidatePool'
Write-Host '===================================================================='
$eEligible = @([pscustomobject]@{ RepoString = 'o/e'; Number = 204 })
$eRejected = @([pscustomobject]@{ RepoString = 'o/e'; Number = 201 }, [pscustomobject]@{ RepoString = 'o/e'; Number = 202 })
$eSel = [pscustomobject]@{ Eligible = $eEligible; Rejected = $eRejected }

# PS 5.1/StrictMode 陷阱③：Get-LoopCandidatePool 內部 `return ,@(...)` 已保護陣列型別，此處
# 不可直接 `@(函式呼叫本身)`（會把已保護好的陣列再包一層）——一律先賦值再對已賦值變數包 @()。
$e1Raw = Get-LoopCandidatePool -SelectResult $eSel -ExcludedNumbers @{}
$e1 = @($e1Raw)
Assert-True -Name 'E1 一般模式（無 -SkipFrontierFilter）僅回傳 Eligible' -Condition (($e1.Count -eq 1) -and ($e1[0].Number -eq 204))

$e2Raw = Get-LoopCandidatePool -SelectResult $eSel -SkipFrontierFilter -ExcludedNumbers @{}
$e2 = @($e2Raw)
Assert-True -Name 'E2 -SkipFrontierFilter 開啟 => 回傳 Eligible+Rejected 全體（依號排序，最小號在前）' -Condition (($e2.Count -eq 3) -and ($e2[0].Number -eq 201))

$e3Raw = Get-LoopCandidatePool -SelectResult $eSel -ExcludedNumbers @{ 'o/e#204' = $true }
$e3 = @($e3Raw)
Assert-True -Name 'E3 排除清單生效（204 被排除後一般模式為空）' -Condition ($e3.Count -eq 0)

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 F【紅燈①／綠燈①】：Invoke-StationRunLoop — 三判準過濾'
Write-Host '===================================================================='

$ticket4Blocked   = [pscustomobject]@{ number = 201; title = 'T-A'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }, [pscustomobject]@{ name = 'sc:blocked' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-f' }; RepoString = 'o/f' }
$ticket4DepUnmet  = [pscustomobject]@{ number = 202; title = 'T-B'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: [T-A]"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-f' }; RepoString = 'o/f' }
$ticket4Running   = [pscustomobject]@{ number = 203; title = 'T-C'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @([pscustomobject]@{ login = 'already-working' }); milestone = [pscustomobject]@{ title = 'W-f' }; RepoString = 'o/f' }
$ticket4Eligible  = [pscustomobject]@{ number = 204; title = 'T-D'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-f' }; RepoString = 'o/f' }
$script:MockResponses['https://api.github.com/repos/o/f/issues?labels=sc:ticket&state=all&per_page=100'] = @($ticket4Blocked, $ticket4DepUnmet, $ticket4Running, $ticket4Eligible)

New-MockIssue -Owner 'o' -Repo 'f' -Number 100 -Title 'W-f · primary anchor' -Labels @('sc:work', 'sc:station-4') | Out-Null

# 一次即通過的 gate provider（Pass），供 F 段迴圈自然收斂用（若真的選到 #204 就會走到這裡）
$passProvider = { param($Selected, $Iter) [pscustomobject]@{ Pass = $true; ScopeChangeNeeded = $false; Detail = 'F段 demo：一律 PASS' } }

Write-Host '--- F-RED：-SkipFrontierFilter 開啟，斷言「loop 只會派工 frontier 內合格票」真的失敗 ---'
$queueFRed = New-TempQueuePath -Prefix 'f-red'
$rFRed = Invoke-StationRunLoop -WorkId 'W-f' -PrimaryRepo 'o/f' -AnchorIssueNumber 100 -ParticipatingRepos @('o/f') -Headers $FakeHeaders `
    -QueuePath $queueFRed -AssigneeLogin 'tester' -GateResultProvider $passProvider -MaxIterations 6 -SkipFrontierFilter
$queueItemsFRedRaw = ConvertTo-SafeArray -RawValue (Read-QueueFile -QueuePath $queueFRed)
$queueItemsFRed = @($queueItemsFRedRaw)
$dispatchedTo201 = @($queueItemsFRed | Where-Object { $_.action -eq 'set-assignee' -and [int]$_.target.issue -eq 201 })
# 🔴 刻意不走 Assert-True／FailCount：斷言「loop 只會派工 frontier 內合格票（不含 #201 blocked）」
# 在 -SkipFrontierFilter 開啟時**應該失敗**（那正是紅燈的定義）。
if ($dispatchedTo201.Count -gt 0) {
    Write-Host "[RED-CONFIRMED] 斷言「loop 只會派工 frontier 內合格票」如預期失敗：-SkipFrontierFilter 開啟後，佇列中真的出現了對 #201（有 sc:blocked，本應被三判準拒絕）的 set-assignee 派工項（共 $($dispatchedTo201.Count) 筆）。證明若無三判準過濾正確接上 loop，loop 真的會派工給不合格候選。StopReason=$($rFRed.StopReason)"
    [void]$script:TestResults.Add('[RED-CONFIRMED] F-RED：-SkipFrontierFilter 開啟後 #201（blocked）真的被派工')
} else {
    Write-Host '[UNEXPECTED] F-RED 段落未能重現越權選件（斷言意外通過）——需人工複查 Get-LoopCandidatePool 的 -SkipFrontierFilter 分支。'
    [void]$script:TestResults.Add('[FAIL] F-RED 未如預期重現越權選件')
    $script:FailCount++
}
Remove-Item -LiteralPath $queueFRed -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '--- F-GREEN：正常模式（無 -SkipFrontierFilter），同一份四票 fixture ---'
$queueFGreen = New-TempQueuePath -Prefix 'f-green'
$rFGreen = Invoke-StationRunLoop -WorkId 'W-f' -PrimaryRepo 'o/f' -AnchorIssueNumber 100 -ParticipatingRepos @('o/f') -Headers $FakeHeaders `
    -QueuePath $queueFGreen -AssigneeLogin 'tester' -GateResultProvider $passProvider -MaxIterations 6
$queueItemsFGreenRaw = ConvertTo-SafeArray -RawValue (Read-QueueFile -QueuePath $queueFGreen)
$queueItemsFGreen = @($queueItemsFGreenRaw)
$dispatchedNumbersGreen = @($queueItemsFGreen | Where-Object { $_.action -eq 'set-assignee' } | ForEach-Object { [int]$_.target.issue } | Select-Object -Unique)
Assert-True -Name 'F-GREEN 斷言「loop 只會派工 frontier 內合格票」通過：只派工過 #204，從未派工 #201/#202/#203' -Condition (($dispatchedNumbersGreen.Count -eq 1) -and ($dispatchedNumbersGreen[0] -eq 204)) -Detail "實際派工過的票號=[$($dispatchedNumbersGreen -join ', ')]"
Assert-True -Name 'F-GREEN 迴圈最終以停因⑤（frontier 空）收斂（#204 派工完成後其餘三票仍不合格）' -Condition ($rFGreen.StopReason -eq '⑤') -Detail $rFGreen.StopDetail
Collect-QueueItems -QueuePath $queueFGreen
Remove-Item -LiteralPath $queueFGreen -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 G【紅燈③／綠燈③】：Invoke-StationRunLoop — 不可逆前停手'
Write-Host '===================================================================='

$ticketIrr = [pscustomobject]@{ number = 301; title = 'T-IRR'; body = "executor: fullstack-developer`nbasis: 理由`ndepends_on: []`n不可逆動作：有（將對外寄送 email 通知客戶）"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-g' }; RepoString = 'o/g' }
$script:MockResponses['https://api.github.com/repos/o/g/issues?labels=sc:ticket&state=all&per_page=100'] = @($ticketIrr)
New-MockIssue -Owner 'o' -Repo 'g' -Number 100 -Title 'W-g · primary anchor' -Labels @('sc:work', 'sc:station-4') | Out-Null

Write-Host '--- G-RED：-SkipIrreversibleHalt 開啟，斷言「dispatch 前必先查第八欄」真的失敗 ---'
$queueGRed = New-TempQueuePath -Prefix 'g-red'
$rGRed = Invoke-StationRunLoop -WorkId 'W-g' -PrimaryRepo 'o/g' -AnchorIssueNumber 100 -ParticipatingRepos @('o/g') -Headers $FakeHeaders `
    -QueuePath $queueGRed -AssigneeLogin 'tester' -GateResultProvider $passProvider -MaxIterations 4 -SkipIrreversibleHalt
$queueItemsGRedRaw = ConvertTo-SafeArray -RawValue (Read-QueueFile -QueuePath $queueGRed)
$queueItemsGRed = @($queueItemsGRedRaw)
$dispatchedIrr = @($queueItemsGRed | Where-Object { $_.action -eq 'set-assignee' -and [int]$_.target.issue -eq 301 })
# 🔴 刻意不走 Assert-True／FailCount：斷言「宣告不可逆動作的票，dispatch 前必被攔下、loop 必以
# 停因①停手」在 -SkipIrreversibleHalt 開啟時**應該失敗**。
if (($dispatchedIrr.Count -gt 0) -and ($rGRed.StopReason -ne '①')) {
    Write-Host "[RED-CONFIRMED] 斷言「dispatch 前必先查第八欄」如預期失敗：-SkipIrreversibleHalt 開啟後，佇列中真的出現了對 #301（宣告『不可逆動作：有』）的 set-assignee 派工項，且 loop 沒有以停因①停手（實際 StopReason=$($rGRed.StopReason)）。證明若無第八欄檢查正確接上 loop 的『必須整迴圈停手』語意，危險的票真的會被派工且迴圈繼續跑。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] G-RED：-SkipIrreversibleHalt 開啟後 #301（不可逆：有）真的被派工，loop 未以停因①停手')
} else {
    Write-Host '[UNEXPECTED] G-RED 段落未能重現越權派工（斷言意外通過）——需人工複查 Invoke-LoopNaiveDispatchIgnoringIrreversible 分支。'
    [void]$script:TestResults.Add('[FAIL] G-RED 未如預期重現越權派工')
    $script:FailCount++
}
Remove-Item -LiteralPath $queueGRed -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '--- G-GREEN：正常模式（無 -SkipIrreversibleHalt），同一份宣告不可逆的票 ---'
$queueGGreen = New-TempQueuePath -Prefix 'g-green'
$rGGreen = Invoke-StationRunLoop -WorkId 'W-g' -PrimaryRepo 'o/g' -AnchorIssueNumber 100 -ParticipatingRepos @('o/g') -Headers $FakeHeaders `
    -QueuePath $queueGGreen -AssigneeLogin 'tester' -GateResultProvider $passProvider -MaxIterations 4
$queueExistsGGreen = Test-Path -LiteralPath $queueGGreen
Assert-True -Name 'G-GREEN 斷言「dispatch 前必先查第八欄」通過：佇列檔未產生任何內容（未被派工）' -Condition (-not $queueExistsGGreen) -Detail "queue 檔存在=$queueExistsGGreen"
Assert-True -Name 'G-GREEN loop 以停因①（不可逆動作前）停手' -Condition ($rGGreen.StopReason -eq '①') -Detail $rGGreen.StopDetail
if ($queueExistsGGreen) { Remove-Item -LiteralPath $queueGGreen -Force -ErrorAction SilentlyContinue }

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 H：停因②（同一票 rework 2 次仍 fail）'
Write-Host '===================================================================='

$ticketRework = [pscustomobject]@{ number = 401; title = 'T-RW'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-h' }; RepoString = 'o/h' }
$script:MockResponses['https://api.github.com/repos/o/h/issues?labels=sc:ticket&state=all&per_page=100'] = @($ticketRework)
New-MockIssue -Owner 'o' -Repo 'h' -Number 100 -Title 'W-h · primary anchor' -Labels @('sc:work', 'sc:station-4') | Out-Null

$script:HCallLog = New-Object System.Collections.ArrayList
$alwaysFailProvider = {
    param($Selected, $Iter)
    [void]$script:HCallLog.Add("$($Selected.RepoString)#$($Selected.Number)@iter$Iter")
    [pscustomobject]@{ Pass = $false; ScopeChangeNeeded = $false; Detail = "H段 demo：一律 FAIL（第 $Iter 輪判定）" }
}

$queueH = New-TempQueuePath -Prefix 'h'
$rH = Invoke-StationRunLoop -WorkId 'W-h' -PrimaryRepo 'o/h' -AnchorIssueNumber 100 -ParticipatingRepos @('o/h') -Headers $FakeHeaders `
    -QueuePath $queueH -AssigneeLogin 'tester' -GateResultProvider $alwaysFailProvider -MaxIterations 10

Assert-True -Name 'H1 StopReason=②' -Condition ($rH.StopReason -eq '②') -Detail $rH.StopDetail
Assert-True -Name 'H2 gate 恰被呼叫 3 次（首判＋2 次 rework 後仍 fail）' -Condition (@($script:HCallLog).Count -eq 3) -Detail "呼叫次數=$(@($script:HCallLog).Count)：[$($script:HCallLog -join ', ')]"
$h3UniqueTickets = @(@($script:HCallLog) | ForEach-Object { $_ -replace '@iter\d+', '' } | Select-Object -Unique)
Assert-True -Name 'H3 全程只選中同一張票（#401），未曾選中其他候選' -Condition ($h3UniqueTickets.Count -eq 1) -Detail "[$($h3UniqueTickets -join ', ')]"
Assert-True -Name 'H4 ReworkCounts 記錄該票已 rework 2 次' -Condition ($rH.ReworkCounts['o/h#401'] -eq 2) -Detail "ReworkCounts['o/h#401']=$($rH.ReworkCounts['o/h#401'])"
Collect-QueueItems -QueuePath $queueH
Remove-Item -LiteralPath $queueH -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 I：停因③（work 位於站 1／2／3，不自動推進）'
Write-Host '===================================================================='

New-MockIssue -Owner 'o' -Repo 'i' -Number 100 -Title 'W-i · primary anchor' -Body 'spec 草案 body（無 executor 宣告）' -Labels @('sc:work', 'sc:station-2') | Out-Null
$queueI = New-TempQueuePath -Prefix 'i'
$rI = Invoke-StationRunLoop -WorkId 'W-i' -PrimaryRepo 'o/i' -AnchorIssueNumber 100 -ParticipatingRepos @('o/i') -Headers $FakeHeaders `
    -QueuePath $queueI -AssigneeLogin 'tester' -GateResultProvider $passProvider -MaxIterations 10
Assert-True -Name 'I1 StopReason=③' -Condition ($rI.StopReason -eq '③') -Detail $rI.StopDetail
Assert-True -Name 'I2 恰跑 1 輪（IterationsRun=1，不自動推進第二輪）' -Condition ($rI.IterationsRun -eq 1) -Detail "IterationsRun=$($rI.IterationsRun)"
Assert-True -Name 'I3 恰產生 1 則 RoundSummaries（一次派工）' -Condition (@($rI.RoundSummaries).Count -eq 1) -Detail "RoundSummaries=[$($rI.RoundSummaries -join ' | ')]"
Collect-QueueItems -QueuePath $queueI
Remove-Item -LiteralPath $queueI -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 J：停因⑤（frontier 空）'
Write-Host '===================================================================='

$script:MockResponses['https://api.github.com/repos/o/j/issues?labels=sc:ticket&state=all&per_page=100'] = @()
New-MockIssue -Owner 'o' -Repo 'j' -Number 100 -Title 'W-j · primary anchor' -Labels @('sc:work', 'sc:station-4') | Out-Null
$queueJ = New-TempQueuePath -Prefix 'j'
$rJ = Invoke-StationRunLoop -WorkId 'W-j' -PrimaryRepo 'o/j' -AnchorIssueNumber 100 -ParticipatingRepos @('o/j') -Headers $FakeHeaders `
    -QueuePath $queueJ -AssigneeLogin 'tester' -GateResultProvider $passProvider -MaxIterations 10
Assert-True -Name 'J1 StopReason=⑤（無票可選）' -Condition ($rJ.StopReason -eq '⑤') -Detail $rJ.StopDetail
Assert-True -Name 'J2 未產生任何佇列項（無候選，未派工）' -Condition (-not (Test-Path -LiteralPath $queueJ))

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 K：停因④（scope 需變更）'
Write-Host '===================================================================='

$ticketScope = [pscustomobject]@{ number = 501; title = 'T-SCOPE'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-k' }; RepoString = 'o/k' }
$script:MockResponses['https://api.github.com/repos/o/k/issues?labels=sc:ticket&state=all&per_page=100'] = @($ticketScope)
New-MockIssue -Owner 'o' -Repo 'k' -Number 100 -Title 'W-k · primary anchor' -Labels @('sc:work', 'sc:station-4') | Out-Null
$scopeProvider = { param($Selected, $Iter) [pscustomobject]@{ Pass = $false; ScopeChangeNeeded = $true; Detail = '判 gate 時發現實作已超出票面 scope，須改票' } }
$queueK = New-TempQueuePath -Prefix 'k'
$rK = Invoke-StationRunLoop -WorkId 'W-k' -PrimaryRepo 'o/k' -AnchorIssueNumber 100 -ParticipatingRepos @('o/k') -Headers $FakeHeaders `
    -QueuePath $queueK -AssigneeLogin 'tester' -GateResultProvider $scopeProvider -MaxIterations 10
Assert-True -Name 'K1 StopReason=④' -Condition ($rK.StopReason -eq '④') -Detail $rK.StopDetail
Collect-QueueItems -QueuePath $queueK
Remove-Item -LiteralPath $queueK -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 L：停因⑥（外廠成本達上限）＋ 已產出結果照常輸出'
Write-Host '===================================================================='

$ticketL1 = [pscustomobject]@{ number = 601; title = 'T-L1'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-l' }; RepoString = 'o/l' }
$ticketL2 = [pscustomobject]@{ number = 602; title = 'T-L2'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-l' }; RepoString = 'o/l' }
$script:MockResponses['https://api.github.com/repos/o/l/issues?labels=sc:ticket&state=all&per_page=100'] = @($ticketL1, $ticketL2)
New-MockIssue -Owner 'o' -Repo 'l' -Number 100 -Title 'W-l · primary anchor' -Labels @('sc:work', 'sc:station-4') | Out-Null

# 成本狀態檔：第 1、2 輪讀到 0%（未提供路徑時走 B1 邏輯不適用，這裡改用「輪次計數」模擬遞增成本，
# 用一個可變的暫存檔在測試腳本這一層於呼叫前後改寫，模擬 T-29 逐次記帳寫入的效果）
$costPathL = Join-Path ([System.IO.Path]::GetTempPath()) "t24-cost-l-$([Guid]::NewGuid().ToString('N').Substring(0,8)).json"
(@{ workId = 'W-l'; percentUsed = 0; provider = 'gemini'; limitType = 'quota' } | ConvertTo-Json -Compress) | Out-File -LiteralPath $costPathL -Encoding utf8

$script:LIterCount = 0
$costRisingProvider = {
    param($Selected, $Iter)
    $script:LIterCount++
    # 模擬：第一張票判 gate 完成後，外廠成本（由 T-29 逐次記帳，本測試直接改寫檔案模擬其效果）
    # 累計推過 100%——下一輪迴圈開頭的成本檢查應偵測到並停手，且本輪（第一張票 PASS）的結果
    # 必須仍保留在 RoundSummaries／Lines 內（§7.6：「已產出的結果照常輸出」）。
    if ($script:LIterCount -eq 1) {
        (@{ workId = 'W-l'; percentUsed = 100; provider = 'gemini'; limitType = 'quota' } | ConvertTo-Json -Compress) | Out-File -LiteralPath $costPathL -Encoding utf8
    }
    [pscustomobject]@{ Pass = $true; ScopeChangeNeeded = $false; Detail = "L段 demo：第 $Iter 輪 PASS" }
}

$queueL = New-TempQueuePath -Prefix 'l'
$rL = Invoke-StationRunLoop -WorkId 'W-l' -PrimaryRepo 'o/l' -AnchorIssueNumber 100 -ParticipatingRepos @('o/l') -Headers $FakeHeaders `
    -QueuePath $queueL -AssigneeLogin 'tester' -GateResultProvider $costRisingProvider -CostStatePath $costPathL -MaxIterations 10

Assert-True -Name 'L1 StopReason=⑥（外廠成本達上限 100%）' -Condition ($rL.StopReason -eq '⑥') -Detail $rL.StopDetail
Assert-True -Name 'L2 停手前第一張票（#601）PASS 的結果仍保留在 RoundSummaries（已產出結果照常輸出，不因停手被清空）' -Condition ((@(@($rL.RoundSummaries) | Where-Object { $_ -like '*601*PASS*' })).Count -eq 1) -Detail "RoundSummaries=[$($rL.RoundSummaries -join ' | ')]"
Assert-True -Name 'L3 第二張票（#602）從未被 gate 判定（成本停手發生在下一輪選件之前）' -Condition (-not ((@($rL.RoundSummaries) -join '') -like '*602*'))
Remove-Item -LiteralPath $costPathL -Force -ErrorAction SilentlyContinue
Collect-QueueItems -QueuePath $queueL
Remove-Item -LiteralPath $queueL -Force -ErrorAction SilentlyContinue

# 另補：50%／80% 僅告警續跑（不停手）的獨立情境，避免只靠上面單一情境佐證
$ticketL3 = [pscustomobject]@{ number = 603; title = 'T-L3'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-l2' }; RepoString = 'o/l2' }
$script:MockResponses['https://api.github.com/repos/o/l2/issues?labels=sc:ticket&state=all&per_page=100'] = @($ticketL3)
New-MockIssue -Owner 'o' -Repo 'l2' -Number 100 -Title 'W-l2 · primary anchor' -Labels @('sc:work', 'sc:station-4') | Out-Null
$costPathL2 = New-TempCostFile -PercentUsed 80
$queueL2 = New-TempQueuePath -Prefix 'l2'
$rL2 = Invoke-StationRunLoop -WorkId 'W-l2' -PrimaryRepo 'o/l2' -AnchorIssueNumber 100 -ParticipatingRepos @('o/l2') -Headers $FakeHeaders `
    -QueuePath $queueL2 -AssigneeLogin 'tester' -GateResultProvider $passProvider -CostStatePath $costPathL2 -MaxIterations 10
Assert-True -Name 'L4 80% 告警但續跑：#603 仍被正常派工並 PASS，StopReason≠⑥（最終應為⑤frontier空）' -Condition ($rL2.StopReason -eq '⑤') -Detail $rL2.StopDetail
Assert-True -Name 'L5 80% 告警文字有出現在 Lines 內' -Condition ((@(@($rL2.Lines) | Where-Object { $_ -like '*告警*80%*' })).Count -ge 1)
Remove-Item -LiteralPath $costPathL2 -Force -ErrorAction SilentlyContinue
Collect-QueueItems -QueuePath $queueL2
Remove-Item -LiteralPath $queueL2 -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 M：驗收⑥ 機械化檢查——多輪混合情境全程無確認提問'
Write-Host '===================================================================='

$ticketM1 = [pscustomobject]@{ number = 701; title = 'T-M1'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-m' }; RepoString = 'o/m' }
$ticketM2 = [pscustomobject]@{ number = 702; title = 'T-M2'; body = "executor: fullstack-developer`nbasis: ok`ndepends_on: []"; state = 'open'; labels = @([pscustomobject]@{ name = 'sc:ticket' }); assignees = @(); milestone = [pscustomobject]@{ title = 'W-m' }; RepoString = 'o/m' }
$script:MockResponses['https://api.github.com/repos/o/m/issues?labels=sc:ticket&state=all&per_page=100'] = @($ticketM1, $ticketM2)
New-MockIssue -Owner 'o' -Repo 'm' -Number 100 -Title 'W-m · primary anchor' -Labels @('sc:work', 'sc:station-5') | Out-Null

$script:MIterCount = 0
$mixedProvider = {
    param($Selected, $Iter)
    $script:MIterCount++
    # 第一張票第一次判定 FAIL（觸發一次 rework），其後與第二張票皆 PASS——涵蓋
    # dispatch／驗收（gate 判定本身）／雙審與 merge（此處以 PASS 收斂代表全過）三段常見路徑，
    # 全程不應出現任何確認提問。
    if ($Selected.Number -eq 701 -and $script:MIterCount -eq 1) {
        return [pscustomobject]@{ Pass = $false; ScopeChangeNeeded = $false; Detail = 'M段 demo：#701 第一次判定 fail，安排 rework' }
    }
    return [pscustomobject]@{ Pass = $true; ScopeChangeNeeded = $false; Detail = "M段 demo：第 $Iter 輪 PASS（雙審／merge 判準全過，站 5 承接舊常設授權不逐次問）" }
}

$queueM = New-TempQueuePath -Prefix 'm'
$rM = Invoke-StationRunLoop -WorkId 'W-m' -PrimaryRepo 'o/m' -AnchorIssueNumber 100 -ParticipatingRepos @('o/m') -Headers $FakeHeaders `
    -QueuePath $queueM -AssigneeLogin 'tester' -GateResultProvider $mixedProvider -MaxIterations 10

Assert-True -Name 'M1 站 4／5 混合多輪（含一次 rework）全程 Lines 掃描 Clean=true（驗收⑥機械化檢查）' -Condition ($rM.NoConfirmationPromptsCheck.Clean) -Detail $rM.NoConfirmationPromptsCheck.Detail
Assert-True -Name 'M2 迴圈最終以停因⑤收斂（兩張票皆已處理完畢）' -Condition ($rM.StopReason -eq '⑤') -Detail $rM.StopDetail
Assert-True -Name 'M3 掃描器並非恆真：手動在 Lines 尾端加一行違規文字，重新掃描應偵測到' -Condition (-not (Test-NoConfirmationPrompts -OutputLines (@($rM.Lines) + @('請確認是否繼續派工？'))).Clean)
Collect-QueueItems -QueuePath $queueM
Remove-Item -LiteralPath $queueM -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 N：run 產生權邊界——彙整前述所有情境的佇列項'
Write-Host '===================================================================='

$allItems = @($script:AllProducedQueueItems)
$forbiddenActions = @('set-labels', 'close-issue', 'create-issue', 'create-milestone')
$forbiddenHits = @($allItems | Where-Object { $forbiddenActions -contains $_.action })
Assert-True -Name 'N1 彙整全部情境產生的佇列項（共 N 筆）從未出現 label／開關 issue／建票類動作' -Condition ($forbiddenHits.Count -eq 0) -Detail "彙整筆數=$($allItems.Count)，違規筆數=$($forbiddenHits.Count)"
$allowedOnly = @($allItems | Where-Object { @('set-assignee', 'set-ticket-fields') -contains $_.action })
Assert-True -Name 'N2 彙整佇列項全數屬 run 允許的兩型（set-assignee／set-ticket-fields）' -Condition ($allowedOnly.Count -eq $allItems.Count) -Detail "允許型筆數=$($allowedOnly.Count)／總筆數=$($allItems.Count)"
Assert-True -Name 'N3 彙整筆數 > 0（確保本檢查不是因為空集合而恆真通過）' -Condition ($allItems.Count -gt 0) -Detail "總筆數=$($allItems.Count)"

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 O：Get-StopReasonText／Test-StopReasonRequiresNotification（六條窮舉與通知範圍）'
Write-Host '===================================================================='

foreach ($reason in @('①', '②', '③', '④', '⑤', '⑥')) {
    $txt = Get-StopReasonText -Reason $reason
    Assert-True -Name "O-$reason 具名文字非空" -Condition (-not [string]::IsNullOrWhiteSpace($txt)) -Detail $txt
}
Assert-True -Name 'O-notify ②③④⑥ 須主動推播' -Condition ((Test-StopReasonRequiresNotification -Reason '②') -and (Test-StopReasonRequiresNotification -Reason '③') -and (Test-StopReasonRequiresNotification -Reason '④') -and (Test-StopReasonRequiresNotification -Reason '⑥'))
Assert-True -Name 'O-silent ①⑤ 為安靜情形' -Condition ((-not (Test-StopReasonRequiresNotification -Reason '①')) -and (-not (Test-StopReasonRequiresNotification -Reason '⑤')))
$oThrew = $false
try { Get-StopReasonText -Reason '⑦' | Out-Null } catch { $oThrew = $true }
Assert-True -Name 'O-guard 不存在的第七條拋錯（窮舉不得自立第七條）' -Condition $oThrew

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Host '===================================================================='

$reportPath = Join-Path $T24TestDir 't24-offline-test-report.txt'
$reportLines = @("t24-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", '')
$reportLines += $script:TestResults
$reportLines += ''
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
