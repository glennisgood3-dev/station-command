#requires -Version 5.1
<#
.SYNOPSIS
    T-30 完整離線測試；可用兩個正式禁用的開關取得③與⑤的斷言失敗紅燈。

.PARAMETER SkipVendorSeparation
    僅供紅燈驗證，正式流程禁用。刻意略過兩份廠別清單分離。

.PARAMETER SkipDisputeLanguageGuard
    僅供紅燈驗證，正式流程禁用。刻意略過分歧措辭守門。
#>

[CmdletBinding()]
param(
    [switch]$SkipVendorSeparation,
    [switch]$SkipDisputeLanguageGuard,
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：dot-source 前保存本測試入口參數。
$T30TestSkipVendorSeparation = $SkipVendorSeparation.IsPresent
$T30TestSkipDisputeLanguageGuard = $SkipDisputeLanguageGuard.IsPresent
$T30TestReportPath = $ReportPath
$T30TestDir = $PSScriptRoot
. (Join-Path $T30TestDir 't30-core.ps1') -FunctionsOnly

$script:T30PassCount = 0
$script:T30FailCount = 0
$script:T30TestLines = New-Object System.Collections.Generic.List[string]

function Write-T30TestLine {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Output $Text
    $script:T30TestLines.Add($Text)
}

function Assert-T30 {
    param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    if ($Condition) {
        $script:T30PassCount++
        Write-T30TestLine "[PASS] $Message"
    }
    else {
        $script:T30FailCount++
        Write-T30TestLine "[ASSERTION FAILED] $Message"
    }
}

function Assert-T30Sequence {
    param([Parameter(Mandatory = $true)][array]$Actual, [Parameter(Mandatory = $true)][array]$Expected, [Parameter(Mandatory = $true)][string]$Message)
    $actualItems = @($Actual)
    $expectedItems = @($Expected)
    $same = ($actualItems.Count -eq $expectedItems.Count)
    if ($same) {
        for ($i = 0; $i -lt $expectedItems.Count; $i++) {
            if ([string]$actualItems[$i] -cne [string]$expectedItems[$i]) { $same = $false; break }
        }
    }
    Assert-T30 -Condition $same -Message $Message
}

function Read-T30FixtureJson {
    param([Parameter(Mandatory = $true)][string]$Name)
    return ([IO.File]::ReadAllText((Join-Path $T30TestDir "fixtures\$Name")) | ConvertFrom-Json)
}

function Save-T30TestReport {
    if ([string]::IsNullOrWhiteSpace($T30TestReportPath)) { return }
    $parent = Split-Path -Parent $T30TestReportPath
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($T30TestReportPath, ($script:T30TestLines -join [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))
}

$claudeA = Read-T30FixtureJson -Name 'claude-axis-a.json'
$geminiA = Read-T30FixtureJson -Name 'gemini-axis-a.json'
$claudeB = Read-T30FixtureJson -Name 'claude-axis-b.json'
$expected = Read-T30FixtureJson -Name 'expected-dual-vendor.json'

if ($T30TestSkipVendorSeparation -or $T30TestSkipDisputeLanguageGuard) {
    Write-T30TestLine '【紅燈驗證】兩個開關僅供紅燈驗證，正式流程禁用。'
    if ($T30TestSkipVendorSeparation) {
        $redSeparation = New-T30GateResult -ClaudeAxisAReport $claudeA -ExternalAxisAReport $geminiA -ClaudeAxisBReport $claudeB -SkipVendorSeparation
        $hasSeparateLists = $redSeparation.PSObject.Properties.Name -contains 'axisAProviderReports'
        Assert-T30 -Condition $hasSeparateLists -Message '③ 兩份 finding 清單各自完整、原順序留存，輸出不得合併或跨廠重排'
    }
    if ($T30TestSkipDisputeLanguageGuard) {
        $redLanguage = New-T30GateResult -ClaudeAxisAReport $claudeA -ExternalAxisAReport $geminiA -ClaudeAxisBReport $claudeB -SkipDisputeLanguageGuard
        $redJson = $redLanguage | ConvertTo-Json -Depth 30 -Compress
        $languageClean = $redJson -notmatch '多數決|以\s*Claude\s*為準'
        Assert-T30 -Condition $languageClean -Message '⑤ 分歧輸出不得含票面禁止的兩種裁決字樣'
    }
    Write-T30TestLine "RED-PROOF SUMMARY：PASS=$script:T30PassCount；FAIL=$script:T30FailCount"
    Save-T30TestReport
    if ($script:T30FailCount -gt 0) { exit 1 }
    exit 0
}

Write-T30TestLine '【A】DECISIONS.md 裁示與三路 dispatch 計畫'
$decisionPath = Join-Path $T30TestDir 'fixtures\DECISIONS-two-vendor.md'
$decision = Read-T30UpgradeDecision -DecisionsPath $decisionPath -Ticket 'T-30-FIXTURE'
Assert-T30 -Condition ($decision.Provider -eq 'Gemini') -Message '票級裁示指定 A 軸外廠 Gemini'
Assert-T30 -Condition ($decision.Model -eq 'fixture-model') -Message '票級裁示保留指定 model'
Assert-T30 -Condition ($decision.Axis -eq 'A') -Message '裁示只覆寫 A 軸'

$diffText = [IO.File]::ReadAllText((Join-Path $T30TestDir 'fixtures\sample.diff'))
$specText = [IO.File]::ReadAllText((Join-Path $T30TestDir 'fixtures\spec-canary.txt'))
$smellPath = Join-Path $T30TestDir '..\station-command\assets\fowler-smells.md'
$smellText = [IO.File]::ReadAllText($smellPath)
$standards = @('docs/STANDARDS.md @ v3-fixture')
$plan = New-T30DispatchPlan -Ticket 'T-30-FIXTURE' -Decision $decision -DiffText $diffText -StandardsRefs $standards -SmellBaselineText $smellText -SpecText $specText
Assert-T30 -Condition ($plan.axisA.claude.provider -eq 'Claude') -Message 'A 軸保留 Claude 審查'
Assert-T30 -Condition ($plan.axisA.external.provider -eq 'Gemini') -Message 'A 軸另一路由至外廠'
Assert-T30 -Condition ($plan.axisB.provider -eq 'Claude') -Message 'B 軸維持 Claude'

Write-T30TestLine '【B】A 軸兩份實際 prompt 與輸入清單隔離'
$allowedKinds = @('diff', 'standards', 'smell-baseline')
$claudeKinds = @($plan.axisA.claude.inputList | ForEach-Object { $_.kind })
$vendorKinds = @($plan.axisA.external.inputList | ForEach-Object { $_.kind })
Assert-T30Sequence -Actual $claudeKinds -Expected $allowedKinds -Message 'Claude A 軸輸入恰為 diff／規範清單／12 條 smell 基線'
Assert-T30Sequence -Actual $vendorKinds -Expected $allowedKinds -Message '外廠 A 軸輸入恰為 diff／規範清單／12 條 smell 基線'
Assert-T30 -Condition ($plan.axisA.claude.prompt -notmatch 'T30-SPEC-CANARY-DO-NOT-SEND-TO-AXIS-A') -Message 'Claude A 軸 prompt 不含 spec 原文 canary'
Assert-T30 -Condition ($plan.axisA.external.prompt -notmatch 'T30-SPEC-CANARY-DO-NOT-SEND-TO-AXIS-A') -Message '外廠 A 軸 prompt 不含 spec 原文 canary'
Assert-T30 -Condition ($plan.axisB.prompt -match 'T30-SPEC-CANARY-DO-NOT-SEND-TO-AXIS-A') -Message '同一份 spec 只送入 Claude B 軸 prompt'
Assert-T30 -Condition ($plan.axisA.claude.prompt -ceq $plan.axisA.external.prompt) -Message '兩家 A 軸取得同一份未加評語的 prompt'

Write-T30TestLine '【C】T-28 實際呼叫 seam：只呼叫外廠 A 軸一次'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('station-t30-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)
try {
    [IO.File]::WriteAllText((Join-Path $tempRoot 'gemini.key'), 'FAKE-KEY-DO-NOT-USE', (New-Object Text.UTF8Encoding($true)))
    $vendorContent = [IO.File]::ReadAllText((Join-Path $T30TestDir 'fixtures\gemini-axis-a.json'))
    $script:T30MockCallCount = 0
    $script:T30PromptSeenByTransport = ''
    $mockTransport = {
        param($Request, $TransportTimeoutSec)
        $script:T30MockCallCount++
        $script:T30PromptSeenByTransport = [string]$Request.Body.contents[0].parts[0].text
        return [pscustomobject]@{
            StatusCode = 200
            Body = [pscustomobject]@{
                candidates = @([pscustomobject]@{
                    content = [pscustomobject]@{
                        parts = @([pscustomobject]@{ text = $vendorContent })
                    }
                })
            }
        }
    }
    $registryPath = Join-Path $T30TestDir '..\station-command\assets\vendor-registry.md'
    $dispatch = Invoke-T30ExternalAxisA -DispatchPlan $plan -ConnectionFolder $tempRoot -RegistryPath $registryPath -Transport $mockTransport
    Assert-T30 -Condition ($script:T30MockCallCount -eq 1) -Message '外廠 provider transport 實際執行恰一次'
    Assert-T30 -Condition ($script:T30PromptSeenByTransport -ceq $plan.axisA.external.prompt) -Message 'transport 收到完整 A 軸 prompt，smell 基線未被改寫'
    Assert-T30 -Condition $dispatch.externalExecuted -Message 'A 軸外廠執行結果具名為已執行'
    Assert-T30 -Condition ($dispatch.axisBProvider -eq 'Claude') -Message '外廠呼叫未改動 B 軸 provider'
    Assert-T30 -Condition ($dispatch.vendorReport.provider -eq 'Gemini') -Message '外廠原始 review 具名保存 provider'
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-T30TestLine '【D】兩份廠別 finding 清單原樣並列、重疊與分歧'
$gate = New-T30GateResult -ClaudeAxisAReport $claudeA -ExternalAxisAReport $geminiA -ClaudeAxisBReport $claudeB
Assert-T30 -Condition (@($gate.axisAProviderReports).Count -eq 2) -Message 'A 軸輸出含恰兩份廠別報告'
$claudeActualIds = @($gate.axisAProviderReports[0].findings | ForEach-Object { $_.id })
$geminiActualIds = @($gate.axisAProviderReports[1].findings | ForEach-Object { $_.id })
Assert-T30Sequence -Actual $claudeActualIds -Expected @($expected.claudeFindingIdsInOrder) -Message 'Claude finding 清單完整且原順序未變'
Assert-T30Sequence -Actual $geminiActualIds -Expected @($expected.geminiFindingIdsInOrder) -Message 'Gemini finding 清單完整且原順序未變'
$claudeOriginalJson = $claudeA.findings | ConvertTo-Json -Depth 10 -Compress
$claudePreservedJson = $gate.axisAProviderReports[0].findings | ConvertTo-Json -Depth 10 -Compress
$geminiOriginalJson = $geminiA.findings | ConvertTo-Json -Depth 10 -Compress
$geminiPreservedJson = $gate.axisAProviderReports[1].findings | ConvertTo-Json -Depth 10 -Compress
Assert-T30 -Condition ($claudePreservedJson -ceq $claudeOriginalJson) -Message 'Claude finding 物件全文逐欄完整留存'
Assert-T30 -Condition ($geminiPreservedJson -ceq $geminiOriginalJson) -Message 'Gemini finding 物件全文逐欄完整留存'
Assert-T30 -Condition (-not ($gate.PSObject.Properties.Name -contains 'combinedFindings')) -Message '輸出沒有廠別合併清單'
Assert-T30 -Condition (-not ($gate.PSObject.Properties.Name -contains 'crossVendorRanking')) -Message '輸出沒有跨廠排序欄位'
$overlapKeys = @($gate.overlaps | ForEach-Object { $_.matchKey })
Assert-T30Sequence -Actual $overlapKeys -Expected @($expected.overlapKeys) -Message '兩廠共同 finding 標為 strongest-overlap'
Assert-T30 -Condition ($gate.overlaps[0].signal -eq 'strongest-overlap') -Message '重疊處使用最強訊號標記'
$disagreementKeys = @($gate.disagreements | ForEach-Object { "$($_.provider)|$($_.findingId)|$($_.matchKey)" })
Assert-T30Sequence -Actual $disagreementKeys -Expected @($expected.disagreementsInOrder) -Message '單廠 finding 逐筆具名列為分歧且不改廠內順序'
Assert-T30 -Condition $gate.requiresUserDecision -Message '有分歧時明確要求使用者裁示'
Assert-T30 -Condition (-not $gate.gateMayProceed) -Message '未裁示的分歧不由 gate 自行選邊放行'
$gateJson = $gate | ConvertTo-Json -Depth 30 -Compress
Assert-T30 -Condition ($gateJson -notmatch '多數決|以\s*Claude\s*為準') -Message '正式分歧輸出不含票面禁止的兩種裁決字樣'

Write-T30TestLine '【E】各廠各自軸內 worst 與跨廠界線'
Assert-T30 -Condition ($gate.axisAProviderReports[0].worstIssue.id -eq $expected.claudeWorstId) -Message 'Claude A 軸清單自報一個軸內 worst'
Assert-T30 -Condition ($gate.axisAProviderReports[1].worstIssue.id -eq $expected.geminiWorstId) -Message 'Gemini A 軸清單自報一個軸內 worst'
Assert-T30 -Condition ($gate.axisB.worstIssue.id -eq $expected.axisBWorstId) -Message 'B 軸亦報自身軸內 worst'
$forbiddenWorstKeys = @('overallWorst', 'singleWorst', 'crossVendorWorst', 'winner')
$presentWorstKeys = @($forbiddenWorstKeys | Where-Object { $gate.PSObject.Properties.Name -contains $_ })
Assert-T30 -Condition ($presentWorstKeys.Count -eq 0) -Message '不存在跨廠合選的單一 worst 欄位'
Assert-T30 -Condition ($gate.closingSummary -match 'A 軸 Claude.*A 軸 Gemini.*B 軸 Claude') -Message '收尾一行逐一報兩家 A 軸及 B 軸數量與 worst'

Write-T30TestLine '【F】分歧佇列四欄契約'
$queueItem = New-T30DisputeQueueItem -Repo 'fixture/station' -Issue 30 -Ticket 'T-30-FIXTURE' -GateResult $gate
$queueKeys = @($queueItem.PSObject.Properties.Name)
Assert-T30Sequence -Actual $queueKeys -Expected @('action', 'target', 'payload', 'source') -Message '佇列項恰四欄 action／target／payload／source'
Assert-T30 -Condition ($queueItem.action -eq 'comment') -Message '分歧裁示使用 T-21 白名單 comment 動作'
Assert-T30 -Condition ($queueItem.target.repo -eq 'fixture/station' -and $queueItem.target.issue -eq 30) -Message 'target 恰含 repo 與 issue'
$payloadPropertyNamesRaw = $queueItem.payload.PSObject.Properties.Name
$payloadPropertyNames = @($payloadPropertyNamesRaw)
Assert-T30 -Condition ($payloadPropertyNames.Count -eq 1 -and $queueItem.payload.body -match '請使用者裁示') -Message 'payload 只含完整留言 body 並要求裁示'
Assert-T30 -Condition ($queueItem.source -eq 'T-30-FIXTURE') -Message 'source 為來源票號'

Write-T30TestLine '【G】外廠不可用時具名降級且 gate 不阻塞'
$missingFolder = Join-Path ([IO.Path]::GetTempPath()) ('station-t30-missing-' + [Guid]::NewGuid().ToString('N'))
$registryPath = Join-Path $T30TestDir '..\station-command\assets\vendor-registry.md'
$degraded = Invoke-T30ExternalAxisA -DispatchPlan $plan -ConnectionFolder $missingFolder -RegistryPath $registryPath
Assert-T30 -Condition (-not $degraded.externalExecuted) -Message '缺 key 時不冒稱外廠已執行'
Assert-T30 -Condition ($degraded.mode -eq 'single-vendor-dual-axis') -Message '降級模式為單廠雙軸'
Assert-T30 -Condition ($degraded.degradation.provider -eq 'Gemini') -Message '降級記錄具名失敗 provider'
Assert-T30 -Condition (-not [string]::IsNullOrWhiteSpace($degraded.degradation.'失敗原因')) -Message '降級記錄具名失敗原因'
Assert-T30 -Condition ($degraded.degradation.'承接者' -eq 'Claude') -Message '降級記錄具名承接者 Claude'
Assert-T30 -Condition $degraded.gateMayProceed -Message '外廠不可用時 gate 不阻塞'

Write-T30TestLine "GREEN SUMMARY：PASS=$script:T30PassCount；FAIL=$script:T30FailCount"
Save-T30TestReport
if ($script:T30FailCount -gt 0) { exit 1 }
exit 0
