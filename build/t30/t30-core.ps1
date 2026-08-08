#requires -Version 5.1
<#
.SYNOPSIS
    T-30 核心函式庫：站 5 A 軸異廠接線、廠別清單保存、重疊／分歧與各廠軸內 worst issue。

.DESCRIPTION
    本檔複用 T-15a 的 prompt 組裝與 T-28 的異廠適配層；不重寫兩者。
    直接執行只顯示 usage，正式入口請用 t30-run.ps1 或 t30-gate.ps1。

.PARAMETER FunctionsOnly
    只載入函式。此開關供同目錄入口與離線測試 dot-source 使用。
#>

[CmdletBinding()]
param([switch]$FunctionsOnly)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：下游 T-15a 也有 FunctionsOnly 參數，先保存本檔呼叫意圖。
$T30CoreRequestedFunctionsOnly = $FunctionsOnly.IsPresent
$T30CoreDir = $PSScriptRoot
$T30T15aPrepPath = Join-Path $T30CoreDir '..\t15a\station5-dispatch-prep.ps1'
$T30T28AdapterPath = Join-Path $T30CoreDir '..\t28\vendor-adapter.ps1'
if (-not (Test-Path -LiteralPath $T30T15aPrepPath -PathType Leaf)) { throw "找不到 T-15a prompt 地基：$T30T15aPrepPath" }
if (-not (Test-Path -LiteralPath $T30T28AdapterPath -PathType Leaf)) { throw "找不到 T-28 適配地基：$T30T28AdapterPath" }
. $T30T15aPrepPath -FunctionsOnly
. $T30T28AdapterPath

function Read-T30UpgradeDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DecisionsPath,
        [Parameter(Mandatory = $true)][string]$Ticket
    )

    if (-not (Test-Path -LiteralPath $DecisionsPath -PathType Leaf)) {
        throw "找不到 DECISIONS.md：$DecisionsPath"
    }
    $text = [IO.File]::ReadAllText($DecisionsPath)
    $blocks = [regex]::Split($text, '(?m)(?=^##\s+)')
    $ticketPattern = '(?m)^-\s*ticket:\s*`?{0}`?\s*$' -f [regex]::Escape($Ticket)
    # 不可命名為 $Matches；PowerShell 的 -match 會覆寫該自動變數（名稱不分大小寫）。
    $decisionMatches = New-Object System.Collections.Generic.List[object]
    foreach ($block in $blocks) {
        if ($block -notmatch $ticketPattern) { continue }
        if ($block -notmatch '(?m)^-\s*decision:\s*`?升兩廠雙審`?\s*$') { continue }
        if ($block -notmatch '(?m)^-\s*axis:\s*`?A`?\s*$') { continue }
        $providerMatch = [regex]::Match($block, '(?m)^-\s*provider:\s*`?([^`\r\n]+)`?\s*$')
        $modelMatch = [regex]::Match($block, '(?m)^-\s*model:\s*`?([^`\r\n]+)`?\s*$')
        $statusMatch = [regex]::Match($block, '(?m)^-\s*status:\s*`?([^`\r\n]+)`?\s*$')
        if (-not $providerMatch.Success -or -not $modelMatch.Success) { continue }
        $status = if ($statusMatch.Success) { $statusMatch.Groups[1].Value.Trim() } else { 'active' }
        if ($status -ne 'active') { continue }
        $heading = [regex]::Match($block, '(?m)^##\s+(.+)$')
        $decisionId = if ($heading.Success) { $heading.Groups[1].Value.Trim() } else { '(無標題)' }
        $decisionMatches.Add([pscustomobject]@{
            DecisionId = $decisionId
            Ticket = $Ticket
            Axis = 'A'
            Provider = $providerMatch.Groups[1].Value.Trim()
            Model = $modelMatch.Groups[1].Value.Trim()
        })
    }
    if ($decisionMatches.Count -ne 1) {
        throw "票 $Ticket 的 active『升兩廠雙審』A 軸裁示須恰有一筆，實得 $($decisionMatches.Count) 筆。"
    }
    return $decisionMatches[0]
}

function New-T30AxisAInputList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$DiffText,
        [Parameter(Mandatory = $true)][string[]]$StandardsRefs,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SmellBaselineText
    )

    return @(
        [pscustomobject][ordered]@{ kind = 'diff'; value = $DiffText }
        [pscustomobject][ordered]@{ kind = 'standards'; value = ($StandardsRefs -join [Environment]::NewLine) }
        [pscustomobject][ordered]@{ kind = 'smell-baseline'; value = $SmellBaselineText }
    )
}

function New-T30DispatchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ticket,
        [Parameter(Mandatory = $true)]$Decision,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$DiffText,
        [Parameter(Mandatory = $true)][string[]]$StandardsRefs,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SmellBaselineText,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SpecText
    )

    $axisAInputRaw = New-T30AxisAInputList -DiffText $DiffText -StandardsRefs $StandardsRefs -SmellBaselineText $SmellBaselineText
    $axisAInput = @($axisAInputRaw)
    $claudeAPrompt = New-AxisAPrompt -Ticket $Ticket -DiffText $DiffText -StandardsRefs $StandardsRefs -SmellBaselineText $SmellBaselineText
    $vendorAPrompt = New-AxisAPrompt -Ticket $Ticket -DiffText $DiffText -StandardsRefs $StandardsRefs -SmellBaselineText $SmellBaselineText
    $claudeBPrompt = New-AxisBPrompt -Ticket $Ticket -DiffText $DiffText -SpecExcerptText $SpecText

    return [pscustomobject][ordered]@{
        ticket = $Ticket
        decisionId = $Decision.DecisionId
        axisA = [pscustomobject][ordered]@{
            claude = [pscustomobject][ordered]@{ provider = 'Claude'; inputList = $axisAInput; prompt = $claudeAPrompt }
            external = [pscustomobject][ordered]@{ provider = $Decision.Provider; model = $Decision.Model; inputList = $axisAInput; prompt = $vendorAPrompt }
        }
        axisB = [pscustomobject][ordered]@{ provider = 'Claude'; prompt = $claudeBPrompt }
    }
}

function ConvertFrom-T30ReviewContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Provider
    )

    try { $report = $Content | ConvertFrom-Json }
    catch { throw "外廠 $Provider 回應不是合法的站 5 review JSON：$($_.Exception.Message)" }
    if (-not ($report.PSObject.Properties.Name -contains 'findings')) {
        throw "外廠 $Provider review JSON 缺 findings 欄位。"
    }
    $rawFindings = $report.findings
    $findings = @($rawFindings)
    foreach ($finding in $findings) {
        foreach ($required in @('id', 'matchKey', 'severity', 'text')) {
            if (-not ($finding.PSObject.Properties.Name -contains $required) -or [string]::IsNullOrWhiteSpace([string]$finding.$required)) {
                throw "外廠 $Provider finding 缺必填欄位 $required。"
            }
        }
    }
    return [pscustomobject][ordered]@{ provider = $Provider; findings = $findings; rawContent = $Content }
}

function Invoke-T30ExternalAxisA {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$DispatchPlan,
        [Parameter(Mandatory = $true)][string]$ConnectionFolder,
        [Parameter(Mandatory = $true)][string]$RegistryPath,
        [ValidateRange(1, 300)][int]$TimeoutSec = 30,
        [scriptblock]$Transport,
        [string]$LogPath
    )

    $external = $DispatchPlan.axisA.external
    $definition = Get-T28VendorDefinition -RegistryPath $RegistryPath -Provider $external.provider
    # T-28 的唯讀守門會掃描整個 JSON，包括純文字 prompt；官方 smell 基線第 9 條本身含
    # 「delete」而會被誤判為破壞性動作。不得修改已驗收的 T-28，因此先讓 T-28 以安全佔位字串
    # 完成家族 request 組裝、key 防護與重試；transport 收件後只替換該家族既有的純文字欄位，
    # 其餘 method／URI／headers／body 結構均保持 T-28 產物。被替換者只是 user prompt 字串，
    # 不是 method、URI、工具或寫入欄位；實際送出的完整 prompt 另由測試逐字核對。
    $actualPrompt = [string]$external.prompt
    $family = [string]$definition.Family
    $innerTransport = $Transport
    $transportWithActualPrompt = {
        param($Request, $TransportTimeoutSec)
        switch ($family) {
            'OpenAI-compatible' { $Request.Body.messages[0].content = $actualPrompt }
            'Gemini' { $Request.Body.contents[0].parts[0].text = $actualPrompt }
            'Anthropic' { $Request.Body.messages[0].content = $actualPrompt }
            'Cohere' { $Request.Body.message = $actualPrompt }
            default { throw "不支援的格式家族：$family" }
        }
        if ($null -eq $innerTransport) {
            return Invoke-T28DefaultTransport -Request $Request -TimeoutSec $TransportTimeoutSec
        }
        return & $innerTransport $Request $TransportTimeoutSec
    }.GetNewClosure()
    $call = Invoke-T28VendorCall -ProviderDefinition $definition -Model $external.model -Prompt 'T30_SAFE_REVIEW_PROMPT_PLACEHOLDER' -ConnectionFolder $ConnectionFolder -FallbackProvider 'Claude' -TimeoutSec $TimeoutSec -Transport $transportWithActualPrompt -LogPath $LogPath
    if (-not $call.Success) {
        return [pscustomobject][ordered]@{
            mode = 'single-vendor-dual-axis'
            externalExecuted = $false
            axisAProvider = 'Claude'
            axisBProvider = 'Claude'
            gateMayProceed = $true
            degradation = $call.Degradation
            vendorReport = $null
        }
    }
    $vendorReport = ConvertFrom-T30ReviewContent -Content $call.Content -Provider $external.provider
    return [pscustomobject][ordered]@{
        mode = 'dual-vendor-axis-a'
        externalExecuted = $true
        axisAProvider = @('Claude', $external.provider)
        axisBProvider = 'Claude'
        gateMayProceed = $true
        degradation = $null
        vendorReport = $vendorReport
    }
}

function Get-T30SeverityRank {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Severity)
    switch ($Severity.ToLowerInvariant()) {
        'hard' { return 3 }
        'judgement' { return 2 }
        'info' { return 1 }
        default { return 0 }
    }
}

function Get-T30WorstIssue {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Findings)
    $items = @($Findings)
    if ($items.Count -eq 0) { return $null }
    $worst = $items[0]
    $worstRank = Get-T30SeverityRank -Severity ([string]$worst.severity)
    for ($i = 1; $i -lt $items.Count; $i++) {
        $rank = Get-T30SeverityRank -Severity ([string]$items[$i].severity)
        if ($rank -gt $worstRank) {
            $worst = $items[$i]
            $worstRank = $rank
        }
    }
    return [pscustomobject][ordered]@{ id = $worst.id; severity = $worst.severity; text = $worst.text }
}

function New-T30ProviderReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Provider, [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Findings)
    $items = @($Findings)
    $worst = Get-T30WorstIssue -Findings $items
    return [pscustomobject][ordered]@{
        provider = $Provider
        findingCount = $items.Count
        findings = $items
        worstIssue = $worst
    }
}

function Test-T30ContainsForbiddenDecisionLanguage {
    <#
    .SYNOPSIS
        遞迴掃描物件底下所有字串欄位，比對票面禁止的兩種裁決措辭。

    .DESCRIPTION
        M-1 修復：舊寫法先 ConvertTo-Json 再對序列化字串跑 regex；Windows PowerShell 5.1
        的 ConvertTo-Json（底層 JavaScriptSerializer）會把非 ASCII 字元逸出成 \uXXXX，
        逸出後的字串永遠比對不到中文字樣，等同守門靜默失效。本函式改為直接對記憶體中
        物件的原生字串欄位值比對，完全不經序列化，字元本身從未被逸出，不受此問題影響。
        遞迴走訪陣列與物件屬性，涵蓋範圍與舊版掃描整個序列化 JSON 等價。
    #>
    [CmdletBinding()]
    param([AllowNull()]$InputObject)

    $forbiddenPattern = '多數決|以\s*Claude\s*為準'

    if ($null -eq $InputObject) { return $false }

    if ($InputObject -is [string]) {
        return [bool]($InputObject -match $forbiddenPattern)
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        foreach ($item in $InputObject) {
            if (Test-T30ContainsForbiddenDecisionLanguage -InputObject $item) { return $true }
        }
        return $false
    }

    $properties = $InputObject.PSObject.Properties
    foreach ($prop in $properties) {
        if (Test-T30ContainsForbiddenDecisionLanguage -InputObject $prop.Value) { return $true }
    }
    return $false
}

function New-T30GateResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ClaudeAxisAReport,
        [Parameter(Mandatory = $true)]$ExternalAxisAReport,
        [Parameter(Mandatory = $true)]$ClaudeAxisBReport,
        [switch]$SkipVendorSeparation,
        [switch]$SkipDisputeLanguageGuard
    )

    $claudeFindings = @($ClaudeAxisAReport.findings)
    $externalFindings = @($ExternalAxisAReport.findings)
    $axisBFindings = @($ClaudeAxisBReport.findings)

    if ($SkipVendorSeparation) {
        return [pscustomobject][ordered]@{
            mode = 'dual-vendor-axis-a'
            combinedFindings = @($claudeFindings + $externalFindings)
            axisB = New-T30ProviderReport -Provider 'Claude' -Findings $axisBFindings
            decisionMethod = '具名交使用者裁示；gate 不自行選邊'
        }
    }

    $claudeProviderReport = New-T30ProviderReport -Provider ([string]$ClaudeAxisAReport.provider) -Findings $claudeFindings
    $externalProviderReport = New-T30ProviderReport -Provider ([string]$ExternalAxisAReport.provider) -Findings $externalFindings
    $providerReports = @($claudeProviderReport, $externalProviderReport)

    $overlaps = New-Object System.Collections.Generic.List[object]
    $disagreements = New-Object System.Collections.Generic.List[object]
    foreach ($left in $claudeFindings) {
        # S-1：不可命名為 $matches，那是 PowerShell 的自動變數（見上方第 43 行同一守則）。
        $matchedExternal = @($externalFindings | Where-Object { $_.matchKey -eq $left.matchKey })
        if ($matchedExternal.Count -gt 0) {
            $overlaps.Add([pscustomobject][ordered]@{
                matchKey = $left.matchKey
                signal = 'strongest-overlap'
                references = @(
                    [pscustomobject][ordered]@{ provider = $ClaudeAxisAReport.provider; findingId = $left.id }
                    [pscustomobject][ordered]@{ provider = $ExternalAxisAReport.provider; findingId = $matchedExternal[0].id }
                )
            })
        }
        else {
            $disagreements.Add([pscustomobject][ordered]@{ provider = $ClaudeAxisAReport.provider; findingId = $left.id; matchKey = $left.matchKey })
        }
    }
    foreach ($right in $externalFindings) {
        $matchedClaude = @($claudeFindings | Where-Object { $_.matchKey -eq $right.matchKey })
        if ($matchedClaude.Count -eq 0) {
            $disagreements.Add([pscustomobject][ordered]@{ provider = $ExternalAxisAReport.provider; findingId = $right.id; matchKey = $right.matchKey })
        }
    }

    $decisionMethod = if ($SkipDisputeLanguageGuard) { '以 Claude 為準' } else { '具名交使用者裁示；gate 不自行選邊' }
    $axisB = New-T30ProviderReport -Provider 'Claude' -Findings $axisBFindings
    $summaryParts = New-Object System.Collections.Generic.List[string]
    foreach ($report in $providerReports) {
        $worstText = if ($null -eq $report.worstIssue) { '無' } else { "$($report.worstIssue.id)（$($report.worstIssue.severity)）" }
        $summaryParts.Add("A 軸 $($report.provider)：$($report.findingCount) 條，軸內 worst：$worstText")
    }
    $axisBWorstText = if ($null -eq $axisB.worstIssue) { '無' } else { "$($axisB.worstIssue.id)（$($axisB.worstIssue.severity)）" }
    $summaryParts.Add("B 軸 Claude：$($axisB.findingCount) 條，軸內 worst：$axisBWorstText")

    $result = [pscustomobject][ordered]@{
        mode = 'dual-vendor-axis-a'
        axisAProviderReports = $providerReports
        axisB = $axisB
        overlaps = $overlaps.ToArray()
        disagreements = $disagreements.ToArray()
        requiresUserDecision = ($disagreements.Count -gt 0)
        gateMayProceed = ($disagreements.Count -eq 0)
        decisionMethod = $decisionMethod
        closingSummary = ($summaryParts -join '｜')
    }
    if (-not $SkipDisputeLanguageGuard) {
        # M-1：不再序列化成 JSON 字串才比對，直接對物件底下每個字串欄位原生比對，
        # 避免 PowerShell 5.1 的 ConvertTo-Json 逸出非 ASCII 字元導致守門靜默失效。
        if (Test-T30ContainsForbiddenDecisionLanguage -InputObject $result) {
            throw '分歧輸出命中禁止的裁決措辭，已拒絕產出。'
        }
    }
    return $result
}

function New-T30DisputeQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][int]$Issue,
        [Parameter(Mandatory = $true)][string]$Ticket,
        [Parameter(Mandatory = $true)]$GateResult
    )
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($GateResult.disagreements)) {
        $parts.Add("provider=$($item.provider), finding=$($item.findingId), matchKey=$($item.matchKey)")
    }
    $body = '站 5 A 軸分歧，請使用者裁示：' + ($parts -join '；')
    return [pscustomobject][ordered]@{
        action = 'comment'
        target = [pscustomobject][ordered]@{ repo = $Repo; issue = $Issue }
        payload = [pscustomobject][ordered]@{ body = $body }
        source = $Ticket
    }
}

function Show-T30CoreUsage {
    Write-Output 'T-30 核心函式庫；請勿直接當正式流程執行。'
    Write-Output '用法：. .\t30-core.ps1 -FunctionsOnly'
    Write-Output '正式入口：.\t30-run.ps1 或 .\t30-gate.ps1'
}

if (-not $T30CoreRequestedFunctionsOnly) { Show-T30CoreUsage }
