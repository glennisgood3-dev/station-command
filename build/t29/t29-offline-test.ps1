#requires -Version 5.1
<# T-29 完整離線測試；兩個 Skip 開關只用來取得斷言失敗型紅燈。 #>

[CmdletBinding()]
param(
    [switch]$SkipLimitEnforcement,
    [switch]$SkipCompletedResultOutput,
    [string]$ReportPath = (Join-Path $PSScriptRoot 't29-offline-test-report.txt')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 測試 CLI 參數作用域防火牆：下游 dot-source 會宣告同名參數。
$T29TestDir = $PSScriptRoot
$T29TestSkipLimitEnforcement = [bool]$SkipLimitEnforcement
$T29TestSkipCompletedResultOutput = [bool]$SkipCompletedResultOutput
$T29TestReportPath = $ReportPath
. (Join-Path $T29TestDir 'cost-boundary.ps1') -FunctionsOnly

$script:T29FailCount = 0
$script:T29PassCount = 0
$script:T29Lines = New-Object System.Collections.ArrayList

function Write-T29TestLine {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Host $Text
    [void]$script:T29Lines.Add($Text)
}

function Assert-T29 {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Condition,
        [string]$Detail = ''
    )
    if ($Condition) {
        $script:T29PassCount++
        Write-T29TestLine "[PASS] $Name$(if ($Detail) { "｜$Detail" } else { '' })"
    } else {
        $script:T29FailCount++
        Write-T29TestLine "[ASSERTION FAILED] $Name$(if ($Detail) { "｜$Detail" } else { '' })"
    }
}

function Test-T29Near {
    param([decimal]$Actual, [decimal]$Expected)
    return ([Math]::Abs([double]($Actual - $Expected)) -lt 0.0000000001)
}

function New-T29TestConnection {
    param([Parameter(Mandatory = $true)][string]$Root)
    $path = Join-Path $Root ('connections-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $path)
    # 明顯假 key 只在執行期組合，完整值不落 repo，並沿用 T-28 的四表面防洩漏慣例。
    $fakeKey = @('FAKE', '-KEY', '-DO', '-NOT', '-USE') -join ''
    [IO.File]::WriteAllText((Join-Path $path 'fixture-vendor.key'), $fakeKey, (New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText((Join-Path $path 'gemini.key'), $fakeKey, (New-Object Text.UTF8Encoding($true)))
    return $path
}

function New-T29OpenAiBody {
    param([Parameter(Mandatory = $true)]$Case)
    return [pscustomobject]@{
        choices = @([pscustomobject]@{ message = [pscustomobject]@{ content = [string]$Case.output } })
        usage = [pscustomobject]@{
            prompt_tokens = [long]$Case.usage.prompt_tokens
            completion_tokens = [long]$Case.usage.completion_tokens
            total_tokens = [long]$Case.usage.total_tokens
        }
    }
}

function New-T29GeminiBody {
    param([Parameter(Mandatory = $true)]$Case)
    return [pscustomobject]@{
        candidates = @([pscustomobject]@{ content = [pscustomobject]@{ parts = @([pscustomobject]@{ text = [string]$Case.output }) } })
        usageMetadata = [pscustomobject]@{
            promptTokenCount = [long]$Case.usage.promptTokenCount
            candidatesTokenCount = [long]$Case.usage.candidatesTokenCount
            totalTokenCount = [long]$Case.usage.totalTokenCount
        }
    }
}

Write-T29TestLine "執行模式：SkipLimitEnforcement=$T29TestSkipLimitEnforcement；SkipCompletedResultOutput=$T29TestSkipCompletedResultOutput"
$fixture = [IO.File]::ReadAllText((Join-Path $T29TestDir 'fixtures\cost-cases.json')) | ConvertFrom-Json
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('t29-test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void](New-Item -ItemType Directory -Path $tempRoot)
$connection = New-T29TestConnection -Root $tempRoot
$openAiDefinition = [pscustomobject]@{ Provider = 'Fixture Vendor'; Endpoint = 'https://fixture.invalid/v1'; Authentication = 'Bearer'; Family = 'OpenAI-compatible'; Status = 'fixture' }
$geminiDefinition = [pscustomobject]@{ Provider = 'Gemini'; Endpoint = 'https://fixture.invalid/v1beta'; Authentication = 'x-goog-api-key'; Family = 'Gemini'; Status = 'fixture' }

try {
    Write-T29TestLine '群組 A【紅燈①／綠燈①】：極低上限、後續停手、輸入與輸出逐字完整'
    $ledgerA = Join-Path $tempRoot 'a-ledger.json'
    $caseA = $fixture.overLimitCall
    $script:T29ACalls = 0
    $script:T29ASentPrompts = New-Object System.Collections.ArrayList
    $transportA = {
        param($Request, $TransportTimeoutSec)
        $script:T29ACalls++
        [void]$script:T29ASentPrompts.Add([string]$Request.Body.messages[0].content)
        [pscustomobject]@{ StatusCode = 200; Body = (New-T29OpenAiBody -Case $caseA) }
    }
    $a1 = Invoke-T29MeteredVendorCall -WorkId 'W-A' -TicketId 'T-A' -ProviderDefinition $openAiDefinition `
        -Model 'fixture-model' -Prompt $caseA.prompt -ConnectionFolder $connection -FallbackProvider 'Claude' `
        -LedgerPath $ledgerA -Budget $fixture.tinyPaidBudget -CallId $caseA.callId -Transport $transportA
    $a2 = Invoke-T29MeteredVendorCall -WorkId 'W-A' -TicketId 'T-A' -ProviderDefinition $openAiDefinition `
        -Model 'fixture-model' -Prompt '這一筆不應送出' -ConnectionFolder $connection -FallbackProvider 'Claude' `
        -LedgerPath $ledgerA -Budget $fixture.tinyPaidBudget -CallId 'over-2' -Transport $transportA `
        -SkipLimitEnforcement:$T29TestSkipLimitEnforcement
    $aCondition = $a1.Success -and ($a1.SubmittedContent -ceq [string]$caseA.prompt) -and `
        ($script:T29ASentPrompts[0] -ceq [string]$caseA.prompt) -and ($a1.Content -ceq [string]$caseA.output) -and `
        ($a1.StopTrigger -eq '⑥') -and ($a1.NamedReport -like '*完整輸入*完整輸出*後續呼叫*') -and `
        $a2.Blocked -and (-not $a2.CallSent) -and ($script:T29ACalls -eq 1)
    Assert-T29 -Name '紅燈斷言①原文：超限點須具名觸發停手，下一次呼叫不得送出，且本次送出內容與回傳內容必須逐字完整' `
        -Condition $aCondition -Detail "calls=$script:T29ACalls；percent=$($a1.CostState.PercentUsed)；inputLen=$($caseA.prompt.Length)；outputLen=$($caseA.output.Length)"
    Assert-T29 -Name 'A2 極低金額上限依 fixture 算得 200%，本次完整結果先回傳' `
        -Condition ((Test-T29Near -Actual $a1.CostState.PercentUsed -Expected $caseA.expectedPercent) -and (Test-T29Near -Actual $a1.LedgerEntry.estimatedCost -Expected $caseA.expectedCost))

    Write-T29TestLine '群組 B：連續三次付費層逐次記帳；50%／80% 各一次且走 T-25 推播'
    $ledgerB = Join-Path $tempRoot 'b-ledger.json'
    $script:T29BIndex = 0
    $script:T29BPushes = New-Object System.Collections.ArrayList
    $transportB = {
        param($Request, $TransportTimeoutSec)
        $current = @($fixture.paidCalls)[$script:T29BIndex]
        $script:T29BIndex++
        [pscustomobject]@{ StatusCode = 200; Body = (New-T29OpenAiBody -Case $current) }
    }
    $sinkB = { param($Notification) [void]$script:T29BPushes.Add($Notification) }
    $resultsB = New-Object System.Collections.ArrayList
    foreach ($call in @($fixture.paidCalls)) {
        $result = Invoke-T29MeteredVendorCall -WorkId 'W-B' -TicketId 'T-B' -ProviderDefinition $openAiDefinition `
            -Model 'fixture-model' -Prompt $call.prompt -ConnectionFolder $connection -FallbackProvider 'Claude' `
            -LedgerPath $ledgerB -Budget $fixture.paidBudget -CallId $call.callId -Transport $transportB -NotificationSink $sinkB
        [void]$resultsB.Add($result)
    }
    $stateB = Read-T29Ledger -LedgerPath $ledgerB
    $entriesB = @($stateB.entries)
    Assert-T29 -Name 'B1 連續三次成功呼叫，gate ledger 恰有三筆記帳' -Condition (($resultsB.Count -eq 3) -and (@($resultsB | Where-Object { $_.Success }).Count -eq 3) -and ($entriesB.Count -eq 3)) -Detail "entries=$($entriesB.Count)"
    $usageMatches = $true
    $costMatches = $true
    for ($i = 0; $i -lt 3; $i++) {
        $expected = @($fixture.paidCalls)[$i]
        $actual = $entriesB[$i]
        if ($actual.inputTokens -ne $expected.usage.prompt_tokens -or $actual.outputTokens -ne $expected.usage.completion_tokens -or $actual.totalTokens -ne $expected.usage.total_tokens) { $usageMatches = $false }
        if (-not (Test-T29Near -Actual $actual.estimatedCost -Expected $expected.expectedCost)) { $costMatches = $false }
    }
    Assert-T29 -Name 'B2 三筆 input／output／total token 逐筆等於 fixture 回應 usage' -Condition $usageMatches
    Assert-T29 -Name 'B3 三筆估算成本逐筆等於 fixture usage × 人造單價 worked example' -Condition $costMatches
    Assert-T29 -Name 'B4 累計成本與百分比分別為 0.0004 USD／80%' -Condition ((Test-T29Near -Actual $stateB.estimatedCost -Expected 0.0004) -and (Test-T29Near -Actual $stateB.percentUsed -Expected 80))
    $pushesB = @($script:T29BPushes)
    $threshold50 = @($pushesB | Where-Object { $_.Message -like '*門檻=50%*' })
    $threshold80 = @($pushesB | Where-Object { $_.Message -like '*門檻=80%*' })
    Assert-T29 -Name 'B5 50%／80% 告警各恰一次，兩次皆明示續跑' -Condition (($pushesB.Count -eq 2) -and ($threshold50.Count -eq 1) -and ($threshold80.Count -eq 1) -and (@($pushesB | Where-Object { $_.Message -like '*續跑=True*' }).Count -eq 2))
    Assert-T29 -Name 'B6 告警直接沿用 T-25 Send-StationUserPush 的 channel／category，未另立通知管道' -Condition (@($pushesB | Where-Object { $_.Channel -ne 'station-user-push' -or $_.Category -ne 'cost-threshold' }).Count -eq 0)

    Write-T29TestLine '群組 C：Gemini 免費層費用為零，但逐次消耗 RPM／RPD／TPM 配額'
    $ledgerC = Join-Path $tempRoot 'c-ledger.json'
    $script:T29CIndex = 0
    $script:T29CCalls = 0
    $script:T29CPushes = New-Object System.Collections.ArrayList
    $transportC = {
        param($Request, $TransportTimeoutSec)
        $current = @($fixture.geminiCalls)[$script:T29CIndex]
        $script:T29CIndex++
        $script:T29CCalls++
        [pscustomobject]@{ StatusCode = 200; Body = (New-T29GeminiBody -Case $current) }
    }
    $sinkC = { param($Notification) [void]$script:T29CPushes.Add($Notification) }
    $cResults = New-Object System.Collections.ArrayList
    foreach ($call in @($fixture.geminiCalls)) {
        $result = Invoke-T29MeteredVendorCall -WorkId 'W-C' -TicketId 'T-C' -ProviderDefinition $geminiDefinition `
            -Model 'fixture-gemini' -Prompt $call.prompt -ConnectionFolder $connection -FallbackProvider 'Claude' `
            -LedgerPath $ledgerC -Budget $fixture.freeBudget -CallId $call.callId -Transport $transportC -NotificationSink $sinkC
        [void]$cResults.Add($result)
    }
    $c3 = Invoke-T29MeteredVendorCall -WorkId 'W-C' -TicketId 'T-C' -ProviderDefinition $geminiDefinition `
        -Model 'fixture-gemini' -Prompt '不得送出的第三次' -ConnectionFolder $connection -FallbackProvider 'Claude' `
        -LedgerPath $ledgerC -Budget $fixture.freeBudget -CallId 'gemini-3' -Transport $transportC -NotificationSink $sinkC
    $stateC = Read-T29Ledger -LedgerPath $ledgerC
    $entriesC = @($stateC.entries)
    Assert-T29 -Name 'C1 免費層兩筆 estimatedCost 及累計費用皆為 0' -Condition ((@($entriesC | Where-Object { $_.estimatedCost -ne 0 }).Count -eq 0) -and ($stateC.estimatedCost -eq 0))
    Assert-T29 -Name 'C2 Gemini 兩次仍消耗 RPM=2／RPD=2／TPM=500' -Condition (($stateC.quota.used.RPM -eq 2) -and ($stateC.quota.used.RPD -eq 2) -and ($stateC.quota.used.TPM -eq 500))
    Assert-T29 -Name 'C3 免費層以最高配額百分比 RPM=100% 觸發同一停因⑥' -Condition (($stateC.limitType -eq 'quota') -and ($stateC.quota.limitingDimension -eq 'RPM') -and ($stateC.percentUsed -eq 100) -and (@($cResults)[1].StopTrigger -eq '⑥'))
    Assert-T29 -Name 'C4 配額達 100% 後第三次呼叫未送出' -Condition ($c3.Blocked -and (-not $c3.CallSent) -and ($script:T29CCalls -eq 2))

    Write-T29TestLine '群組 D【紅燈④／綠燈④】：T-29 寫狀態、T-24 停因⑥、T-25 收尾與既有成果輸出'
    $ledgerD = Join-Path $tempRoot 'd-ledger.json'
    $queueD = Join-Path $tempRoot 'd-queue.json'
    $script:T29DGateCalls = 0
    $script:T29DTransportCalls = 0
    $script:T29DReviews = New-Object System.Collections.ArrayList
    $script:T29DPushes = New-Object System.Collections.ArrayList
    $script:T29DTickets = @(
        [pscustomobject]@{ Number = 701; RepoString = 'fixture/repo'; Kind = 'ticket'; Title = '先完成的審查' },
        [pscustomobject]@{ Number = 702; RepoString = 'fixture/repo'; Kind = 'ticket'; Title = '不得再呼叫' }
    )
    $transportD = {
        param($Request, $TransportTimeoutSec)
        $script:T29DTransportCalls++
        [pscustomobject]@{ StatusCode = 200; Body = (New-T29OpenAiBody -Case $caseA) }
    }
    $sinkD = { param($Notification) [void]$script:T29DPushes.Add($Notification) }
    function Get-CurrentIssue { param($Owner, $Repo, $IssueNumber, $Headers) return [pscustomobject]@{ number = 99; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-4' }) } }
    function Get-CurrentStation { param($Issue) return [pscustomobject]@{ Valid = $true; Station = 'sc:station-4'; Detail = 'fixture' } }
    function Select-NextActionableItem {
        param($AnchorIssue, $Station, $WorkId, $PrimaryRepo, $ParticipatingRepos, $Headers)
        return [pscustomobject]@{ HasCandidate = $true; Eligible = @($script:T29DTickets); Rejected = @(); Detail = '兩張人造可動作票' }
    }
    function Invoke-RunDispatch {
        param($Selected, $QueuePath, $AssigneeLogin, $WorkId, [switch]$SkipEnqueueGuard)
        $item = New-SetAssigneeItem -Repo $Selected.RepoString -IssueNumber $Selected.Number -Assignees @($AssigneeLogin) -Source $WorkId
        [void](Add-RunQueueItemGuarded -QueuePath $QueuePath -Item $item)
        return [pscustomobject]@{ Status = 'dispatch-ready'; Lines = @("fixture dispatch $($Selected.RepoString)#$($Selected.Number)") }
    }
    $gateD = {
        param($Selected, $Iteration)
        $script:T29DGateCalls++
        $review = Invoke-T29MeteredVendorCall -WorkId 'W-D' -TicketId "T-$($Selected.Number)" -ProviderDefinition $openAiDefinition `
            -Model 'fixture-model' -Prompt $caseA.prompt -ConnectionFolder $connection -FallbackProvider 'Claude' `
            -LedgerPath $ledgerD -Budget $fixture.tinyPaidBudget -CallId 'loop-review-1' -Transport $transportD
        [void]$script:T29DReviews.Add($review)
        return [pscustomobject]@{ Pass = $true; ScopeChangeNeeded = $false; Detail = "審查結果已輸出：$($review.Content)" }
    }
    $loopD = Invoke-StationRunLoop -WorkId 'W-D' -PrimaryRepo 'fixture/repo' -AnchorIssueNumber 99 `
        -ParticipatingRepos @('fixture/repo') -Headers @{} -QueuePath $queueD -AssigneeLogin 'fixture-executor' `
        -GateResultProvider $gateD -CostStatePath $ledgerD -MaxIterations 5
    $finalD = Complete-T29CostedLoop -WorkId 'W-D' -AnchorRepo 'fixture/repo' -AnchorIssueNumber 99 -QueuePath $queueD `
        -LoopResult $loopD -CompletedReviewResults @($script:T29DReviews) -NotificationSink $sinkD `
        -SkipCompletedResultOutput:$T29TestSkipCompletedResultOutput
    $dResults = @($finalD.ReviewResults)
    $dRoundText = @($loopD.RoundSummaries) -join ' | '
    $dRedCondition = ($loopD.StopReason -eq '⑥') -and ($script:T29DGateCalls -eq 1) -and ($script:T29DTransportCalls -eq 1) -and `
        ($dRoundText -like '*#701*PASS*') -and ($dRoundText -notlike '*#702*') -and ($dResults.Count -eq 1) -and `
        ($dResults[0].Content -ceq [string]$caseA.output) -and ($finalD.SummaryBody -like '*#701*PASS*')
    Assert-T29 -Name '紅燈斷言④原文：達 100% 必須由 T-24 以停因⑥停手，停的是後續呼叫，且停手前既有完整審查結果仍照常輸出' `
        -Condition $dRedCondition -Detail "stop=$($loopD.StopReason)；gateCalls=$script:T29DGateCalls；transportCalls=$script:T29DTransportCalls；reviewOutputs=$($dResults.Count)"
    $pushesD = @($script:T29DPushes)
    Assert-T29 -Name 'D2 停因⑥通知由 T-25 既有 station-user-push／loop-stop 發送' -Condition (($pushesD.Count -eq 1) -and ($pushesD[0].Channel -eq 'station-user-push') -and ($pushesD[0].Category -eq 'loop-stop') -and ($pushesD[0].StopReason -eq '⑥'))
    $queueRawD = Read-QueueFile -QueuePath $queueD
    if ($null -eq $queueRawD) { $queueItemsD = @() } else { $queueItemsD = @($queueRawD) }
    $exactFour = $true
    foreach ($item in $queueItemsD) {
        $names = @($item.PSObject.Properties.Name | Sort-Object)
        if (($names -join ',') -ne 'action,payload,source,target') { $exactFour = $false }
    }
    Assert-T29 -Name 'D3 所有待寫佇列項恰四欄 action／target／payload／source' -Condition ($exactFour -and ($queueItemsD.Count -eq 2)) -Detail "queue=$($queueItemsD.Count)"
    Assert-T29 -Name 'D4 只派工 #701，未替停手後的 #702 產生任何佇列項' -Condition (@($queueItemsD | Where-Object { $_.target.PSObject.Properties.Name -contains 'issue' -and $_.target.issue -eq 702 }).Count -eq 0)

    Write-T29TestLine '群組 E：格式家族 usage 正規化與上限語意拒絕混用'
    $anthropicUsage = Get-T29Usage -Family 'Anthropic' -ResponseBody ([pscustomobject]@{ usage = [pscustomobject]@{ input_tokens = 7; output_tokens = 3 } })
    $cohereUsage = Get-T29Usage -Family 'Cohere' -ResponseBody ([pscustomobject]@{ usage = [pscustomobject]@{ tokens = [pscustomobject]@{ input_tokens = 8; output_tokens = 4 } } })
    Assert-T29 -Name 'E1 Anthropic usage 正規化 input=7／output=3／total=10' -Condition (($anthropicUsage.InputTokens -eq 7) -and ($anthropicUsage.OutputTokens -eq 3) -and ($anthropicUsage.TotalTokens -eq 10))
    Assert-T29 -Name 'E2 Cohere usage 正規化 input=8／output=4／total=12' -Condition (($cohereUsage.InputTokens -eq 8) -and ($cohereUsage.OutputTokens -eq 4) -and ($cohereUsage.TotalTokens -eq 12))
    $paidQuotaRejected = $false
    try { Assert-T29Budget -Budget ([pscustomobject]@{ tier = 'paid'; limitType = 'quota'; quotaLimits = [pscustomobject]@{ RPM = 1; RPD = 1; TPM = 1 } }) } catch { $paidQuotaRejected = $true }
    $freeAmountRejected = $false
    try { Assert-T29Budget -Budget ([pscustomobject]@{ tier = 'free'; limitType = 'amount'; limitValue = 1 }) } catch { $freeAmountRejected = $true }
    Assert-T29 -Name 'E3 付費層不得冒用 quota；免費層不得冒用 amount' -Condition ($paidQuotaRejected -and $freeAmountRejected)
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-T29TestLine "總結：PASS=$script:T29PassCount FAIL=$script:T29FailCount"
Write-T29TestLine "結束碼：$(if ($script:T29FailCount -gt 0) { 1 } else { 0 })（由斷言失敗數決定）"
$reportParent = Split-Path -Parent $T29TestReportPath
if ($reportParent -and -not (Test-Path -LiteralPath $reportParent)) { [void](New-Item -ItemType Directory -Path $reportParent -Force) }
[IO.File]::WriteAllText($T29TestReportPath, ($script:T29Lines -join [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))
Write-Host "報告已寫入：$T29TestReportPath"
if ($script:T29FailCount -gt 0) { exit 1 }
exit 0
