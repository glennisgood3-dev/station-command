#requires -Version 5.1
<#
.SYNOPSIS
    T-29 每票外廠成本／配額邊界、逐次記帳與三段告警。

.DESCRIPTION
    本檔複用 T-28 呼叫適配層、T-24 停因⑥判定，以及 T-25 的單一推播管道。
    付費層以金額計上限；免費層以 RPM／RPD／TPM 配額計上限。達 100% 時只寫出
    T-24 可讀的狀態並觸發既有停因⑥，絕不在本檔另立停止規則。

.PARAMETER FunctionsOnly
    只載入函式。供測試或其他腳本 dot-source 使用。
#>

[CmdletBinding()]
param([switch]$FunctionsOnly)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# CLI 參數作用域防火牆：下游 dot-source 鏈有同名參數，先存成 T29 獨有名稱。
$T29LibraryDir = $PSScriptRoot
$T29LibraryFunctionsOnlyRequested = [bool]$FunctionsOnly
$T29FinalizePath = Join-Path $T29LibraryDir '..\t25\run-finalize.ps1'
$T29AdapterPath = Join-Path $T29LibraryDir '..\t28\vendor-adapter.ps1'
if (-not (Test-Path -LiteralPath $T29FinalizePath -PathType Leaf)) { throw "找不到 T-25 地基：$T29FinalizePath" }
if (-not (Test-Path -LiteralPath $T29AdapterPath -PathType Leaf)) { throw "找不到 T-28 地基：$T29AdapterPath" }
. $T29FinalizePath -FunctionsOnly
. $T29AdapterPath
Set-StrictMode -Version Latest

function Get-T29MemberValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()]$Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function ConvertTo-T29Decimal {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string]$FieldName
    )
    if ($null -eq $Value) { throw "缺少數值欄位：$FieldName" }
    try { return [decimal]$Value }
    catch { throw "欄位 $FieldName 必須是數值，實得：$Value" }
}

function Assert-T29Budget {
    param([Parameter(Mandatory = $true)]$Budget)

    $tier = [string](Get-T29MemberValue -Object $Budget -Name 'tier')
    $limitType = [string](Get-T29MemberValue -Object $Budget -Name 'limitType')
    if ($tier -notin @('paid', 'free')) { throw 'budget.tier 只能是 paid 或 free。' }
    if ($tier -eq 'paid') {
        if ($limitType -ne 'amount') { throw '付費層的 limitType 必須是 amount（金額）。' }
        $limit = ConvertTo-T29Decimal -Value (Get-T29MemberValue -Object $Budget -Name 'limitValue') -FieldName 'limitValue'
        if ($limit -le 0) { throw '付費層 limitValue 必須大於 0。' }
        $inputRate = ConvertTo-T29Decimal -Value (Get-T29MemberValue -Object $Budget -Name 'inputUsdPerMillion') -FieldName 'inputUsdPerMillion'
        $outputRate = ConvertTo-T29Decimal -Value (Get-T29MemberValue -Object $Budget -Name 'outputUsdPerMillion') -FieldName 'outputUsdPerMillion'
        if ($inputRate -lt 0 -or $outputRate -lt 0) { throw 'token 單價不得為負數。' }
        return
    }

    if ($limitType -ne 'quota') { throw '免費層的 limitType 必須是 quota（配額）。' }
    $limits = Get-T29MemberValue -Object $Budget -Name 'quotaLimits'
    if ($null -eq $limits) { throw '免費層必須提供 quotaLimits（RPM／RPD／TPM）。' }
    foreach ($name in @('RPM', 'RPD', 'TPM')) {
        $value = ConvertTo-T29Decimal -Value (Get-T29MemberValue -Object $limits -Name $name) -FieldName "quotaLimits.$name"
        if ($value -le 0) { throw "quotaLimits.$name 必須大於 0。" }
    }
}

function New-T29Ledger {
    param(
        [Parameter(Mandatory = $true)][string]$WorkId,
        [Parameter(Mandatory = $true)][string]$TicketId,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)]$Budget
    )
    Assert-T29Budget -Budget $Budget
    $tier = [string]$Budget.tier
    if ($tier -eq 'paid') {
        return [pscustomobject][ordered]@{
            schemaVersion = 1; workId = $WorkId; ticketId = $TicketId; provider = $Provider
            tier = 'paid'; limitType = 'amount'; limitUnit = 'USD'
            limitValue = [decimal]$Budget.limitValue; usedValue = [decimal]0; percentUsed = [decimal]0
            estimatedCost = [decimal]0; warning50Sent = $false; warning80Sent = $false
            quota = $null; entries = @()
        }
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 1; workId = $WorkId; ticketId = $TicketId; provider = $Provider
        tier = 'free'; limitType = 'quota'; limitUnit = 'RPM／RPD／TPM'
        limitValue = [decimal]100; usedValue = [decimal]0; percentUsed = [decimal]0
        estimatedCost = [decimal]0; warning50Sent = $false; warning80Sent = $false
        quota = [pscustomobject][ordered]@{
            limits = [pscustomobject][ordered]@{ RPM = [decimal]$Budget.quotaLimits.RPM; RPD = [decimal]$Budget.quotaLimits.RPD; TPM = [decimal]$Budget.quotaLimits.TPM }
            used = [pscustomobject][ordered]@{ RPM = [decimal]0; RPD = [decimal]0; TPM = [decimal]0 }
            percentages = [pscustomobject][ordered]@{ RPM = [decimal]0; RPD = [decimal]0; TPM = [decimal]0 }
            limitingDimension = 'RPM'
        }
        entries = @()
    }
}

function Read-T29Ledger {
    param([Parameter(Mandatory = $true)][string]$LedgerPath)
    if (-not (Test-Path -LiteralPath $LedgerPath -PathType Leaf)) { return $null }
    $raw = [IO.File]::ReadAllText($LedgerPath)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-T29Ledger {
    param(
        [Parameter(Mandatory = $true)][string]$LedgerPath,
        [Parameter(Mandatory = $true)]$Ledger
    )
    $parent = Split-Path -Parent $LedgerPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    $json = $Ledger | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($LedgerPath, $json, (New-Object Text.UTF8Encoding($true)))
}

function Get-T29Usage {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('OpenAI-compatible', 'Gemini', 'Anthropic', 'Cohere')][string]$Family,
        [Parameter(Mandatory = $true)]$ResponseBody
    )
    $inputTokens = $null
    $outputTokens = $null
    $totalTokens = $null
    switch ($Family) {
        'OpenAI-compatible' {
            $usage = Get-T29MemberValue -Object $ResponseBody -Name 'usage'
            $inputTokens = Get-T29MemberValue -Object $usage -Name 'prompt_tokens'
            $outputTokens = Get-T29MemberValue -Object $usage -Name 'completion_tokens'
            $totalTokens = Get-T29MemberValue -Object $usage -Name 'total_tokens'
        }
        'Gemini' {
            $usage = Get-T29MemberValue -Object $ResponseBody -Name 'usageMetadata'
            $inputTokens = Get-T29MemberValue -Object $usage -Name 'promptTokenCount'
            $outputTokens = Get-T29MemberValue -Object $usage -Name 'candidatesTokenCount'
            $totalTokens = Get-T29MemberValue -Object $usage -Name 'totalTokenCount'
        }
        'Anthropic' {
            $usage = Get-T29MemberValue -Object $ResponseBody -Name 'usage'
            $inputTokens = Get-T29MemberValue -Object $usage -Name 'input_tokens'
            $outputTokens = Get-T29MemberValue -Object $usage -Name 'output_tokens'
        }
        'Cohere' {
            $usage = Get-T29MemberValue -Object $ResponseBody -Name 'usage'
            $tokens = Get-T29MemberValue -Object $usage -Name 'tokens'
            if ($null -eq $tokens) { $tokens = $usage }
            $inputTokens = Get-T29MemberValue -Object $tokens -Name 'input_tokens'
            $outputTokens = Get-T29MemberValue -Object $tokens -Name 'output_tokens'
        }
    }
    if ($null -eq $inputTokens -or $null -eq $outputTokens) { throw "成功回應缺少 $Family token usage，拒絕產生不完整記帳。" }
    $input = [long]$inputTokens
    $output = [long]$outputTokens
    if ($input -lt 0 -or $output -lt 0) { throw 'token usage 不得為負數。' }
    if ($null -eq $totalTokens) { $total = $input + $output } else { $total = [long]$totalTokens }
    if ($total -ne ($input + $output)) { throw "usage.totalTokens 與 input＋output 不符：$total != $input＋$output" }
    return [pscustomobject][ordered]@{ InputTokens = $input; OutputTokens = $output; TotalTokens = $total }
}

function Get-T29RequestPrompt {
    param([Parameter(Mandatory = $true)]$Request)
    switch ([string]$Request.Family) {
        'OpenAI-compatible' { return [string]$Request.Body.messages[0].content }
        'Gemini' { return [string]$Request.Body.contents[0].parts[0].text }
        'Anthropic' { return [string]$Request.Body.messages[0].content }
        'Cohere' { return [string]$Request.Body.message }
        default { throw "不支援的請求家族：$($Request.Family)" }
    }
}

function Add-T29LedgerEntry {
    param(
        [Parameter(Mandatory = $true)]$Ledger,
        [Parameter(Mandatory = $true)]$Budget,
        [Parameter(Mandatory = $true)]$Usage,
        [Parameter(Mandatory = $true)][string]$CallId
    )
    $cost = [decimal]0
    $quotaConsumption = $null
    if ($Ledger.tier -eq 'paid') {
        $inputCost = ([decimal]$Usage.InputTokens * [decimal]$Budget.inputUsdPerMillion) / [decimal]1000000
        $outputCost = ([decimal]$Usage.OutputTokens * [decimal]$Budget.outputUsdPerMillion) / [decimal]1000000
        $cost = [decimal]::Round(($inputCost + $outputCost), 12)
        $Ledger.estimatedCost = [decimal]::Round(([decimal]$Ledger.estimatedCost + $cost), 12)
        $Ledger.usedValue = $Ledger.estimatedCost
        $Ledger.percentUsed = [decimal]::Round((([decimal]$Ledger.usedValue / [decimal]$Ledger.limitValue) * 100), 6)
    } else {
        $quotaConsumption = [pscustomobject][ordered]@{ RPM = 1; RPD = 1; TPM = [long]$Usage.TotalTokens }
        foreach ($name in @('RPM', 'RPD', 'TPM')) {
            $Ledger.quota.used.$name = [decimal]$Ledger.quota.used.$name + [decimal]$quotaConsumption.$name
            $Ledger.quota.percentages.$name = [decimal]::Round((([decimal]$Ledger.quota.used.$name / [decimal]$Ledger.quota.limits.$name) * 100), 6)
        }
        $dimension = 'RPM'
        foreach ($name in @('RPD', 'TPM')) {
            if ([decimal]$Ledger.quota.percentages.$name -gt [decimal]$Ledger.quota.percentages.$dimension) { $dimension = $name }
        }
        $Ledger.quota.limitingDimension = $dimension
        $Ledger.percentUsed = [decimal]$Ledger.quota.percentages.$dimension
        $Ledger.usedValue = [decimal]$Ledger.percentUsed
        $Ledger.estimatedCost = [decimal]0
    }

    $entry = [pscustomobject][ordered]@{
        callId = $CallId
        provider = [string]$Ledger.provider
        tier = [string]$Ledger.tier
        inputTokens = [long]$Usage.InputTokens
        outputTokens = [long]$Usage.OutputTokens
        totalTokens = [long]$Usage.TotalTokens
        estimatedCost = $cost
        quotaConsumption = $quotaConsumption
    }
    $oldRaw = $Ledger.entries
    if ($null -eq $oldRaw) { $old = @() } else { $old = @($oldRaw) }
    $Ledger.entries = @($old + @($entry))
    return $entry
}

function Send-T29ThresholdAlerts {
    param(
        [Parameter(Mandatory = $true)]$Ledger,
        [scriptblock]$NotificationSink
    )
    $sent = New-Object System.Collections.ArrayList
    foreach ($threshold in @(50, 80)) {
        $flag = if ($threshold -eq 50) { 'warning50Sent' } else { 'warning80Sent' }
        # 100% 由 T-24／T-25 的停因⑥接手；不得同時把 50%／80% 訊息誤報成「續跑」。
        if ([decimal]$Ledger.percentUsed -lt 100 -and [decimal]$Ledger.percentUsed -ge $threshold -and -not [bool]$Ledger.$flag) {
            $Ledger.$flag = $true
            $message = "外廠邊界告警｜ticket=$($Ledger.ticketId)｜provider=$($Ledger.provider)｜tier=$($Ledger.tier)｜limitType=$($Ledger.limitType)｜累計=$($Ledger.percentUsed)%｜門檻=$threshold%｜續跑=True"
            $push = Send-StationUserPush -Message $message -Category 'cost-threshold' -NotificationSink $NotificationSink
            [void]$sent.Add($push)
        }
    }
    return $sent.ToArray()
}

function Assert-T29LedgerIdentity {
    param(
        [Parameter(Mandatory = $true)]$Ledger,
        [Parameter(Mandatory = $true)][string]$WorkId,
        [Parameter(Mandatory = $true)][string]$TicketId,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)]$Budget
    )
    if ($Ledger.workId -ne $WorkId -or $Ledger.ticketId -ne $TicketId -or $Ledger.provider -ne $Provider) {
        throw '既有 ledger 的 workId／ticketId／provider 與本次呼叫不符。'
    }
    if ($Ledger.tier -ne $Budget.tier -or $Ledger.limitType -ne $Budget.limitType) {
        throw '既有 ledger 的付費層／免費層上限語意與本次 budget 不符。'
    }
}

function Invoke-T29MeteredVendorCall {
    param(
        [Parameter(Mandatory = $true)][string]$WorkId,
        [Parameter(Mandatory = $true)][string]$TicketId,
        [Parameter(Mandatory = $true)]$ProviderDefinition,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$ConnectionFolder,
        [Parameter(Mandatory = $true)][string]$FallbackProvider,
        [Parameter(Mandatory = $true)][string]$LedgerPath,
        [Parameter(Mandatory = $true)]$Budget,
        [Parameter(Mandatory = $true)][string]$CallId,
        [ValidateRange(1, 300)][int]$TimeoutSec = 30,
        [scriptblock]$Transport,
        [scriptblock]$NotificationSink,
        [switch]$SkipLimitEnforcement
    )
    Assert-T29Budget -Budget $Budget
    $ledger = Read-T29Ledger -LedgerPath $LedgerPath
    if ($null -eq $ledger) {
        $ledger = New-T29Ledger -WorkId $WorkId -TicketId $TicketId -Provider $ProviderDefinition.Provider -Budget $Budget
    } else {
        Assert-T29LedgerIdentity -Ledger $ledger -WorkId $WorkId -TicketId $TicketId -Provider $ProviderDefinition.Provider -Budget $Budget
    }

    $existingCostState = Test-CostLimitState -CostStatePath $LedgerPath
    if ($existingCostState.Reached100 -and -not $SkipLimitEnforcement) {
        return [pscustomobject][ordered]@{
            Success = $false; Blocked = $true; Available = $true; CallSent = $false
            SubmittedContent = $null; Content = $null; Usage = $null; LedgerEntry = $null
            StopTrigger = '⑥'; CostState = $existingCostState; Alerts = @()
            NamedReport = "已達每票上限，未送出後續呼叫；交由 T-24 依 §5.3a 停止條件⑥停手。$($existingCostState.Detail)"
        }
    }
    if ($existingCostState.Reached100 -and $SkipLimitEnforcement) {
        Write-Warning '⚠️ -SkipLimitEnforcement 已開啟：刻意略過已達 100% 的後續呼叫守門，僅供紅燈驗證，正式流程禁用。'
    }

    $capture = @{ Request = $null; Response = $null }
    if ($null -eq $Transport) { $Transport = ${function:Invoke-T28DefaultTransport} }
    $innerTransport = $Transport
    $capturingTransport = {
        param($Request, $InnerTimeoutSec)
        $capture.Request = $Request
        $raw = & $innerTransport $Request $InnerTimeoutSec
        $capture.Response = $raw
        return $raw
    }.GetNewClosure()

    $vendorResult = Invoke-T28VendorCall -ProviderDefinition $ProviderDefinition -Model $Model -Prompt $Prompt `
        -ConnectionFolder $ConnectionFolder -FallbackProvider $FallbackProvider -TimeoutSec $TimeoutSec `
        -Transport $capturingTransport
    if (-not $vendorResult.Success) {
        return [pscustomobject][ordered]@{
            Success = $false; Blocked = $false; Available = $vendorResult.Available; CallSent = ($vendorResult.Attempts -gt 0)
            SubmittedContent = $Prompt; Content = $null; Usage = $null; LedgerEntry = $null
            StopTrigger = $null; CostState = $existingCostState; Alerts = @(); NamedReport = '外廠呼叫失敗，未寫 usage 記帳。'
            Degradation = $vendorResult.Degradation
        }
    }
    if ($null -eq $capture.Request -or $null -eq $capture.Response) { throw 'T-28 呼叫成功但 T-29 未捕捉到完整 request／response。' }
    $submitted = Get-T29RequestPrompt -Request $capture.Request
    if ($submitted -cne $Prompt) { throw '送出內容與原始輸入不一致；拒絕靜默截斷。' }
    $rawContent = ConvertFrom-T28VendorResponse -Family $ProviderDefinition.Family -ResponseBody $capture.Response.Body
    if ([string]$rawContent -cne [string]$vendorResult.Content) { throw 'T-28 回傳內容與原始 response 解碼結果不一致；拒絕靜默截斷。' }

    $usage = Get-T29Usage -Family $ProviderDefinition.Family -ResponseBody $capture.Response.Body
    $entry = Add-T29LedgerEntry -Ledger $ledger -Budget $Budget -Usage $usage -CallId $CallId
    # 先落 usage 再送告警：即使推播 sink 例外，已花掉的 token／金額／配額也不會遺失。
    Write-T29Ledger -LedgerPath $LedgerPath -Ledger $ledger
    $alertsRaw = Send-T29ThresholdAlerts -Ledger $ledger -NotificationSink $NotificationSink
    if ($null -eq $alertsRaw) { $alerts = @() } else { $alerts = @($alertsRaw) }
    Write-T29Ledger -LedgerPath $LedgerPath -Ledger $ledger
    $costState = Test-CostLimitState -CostStatePath $LedgerPath
    $stopTrigger = if ($costState.Reached100) {
        [void](Get-StopReasonText -Reason '⑥')
        '⑥'
    } else { $null }
    $report = if ($null -ne $stopTrigger) {
        "本次完整輸入與完整輸出均已保留；累計達 100%，已觸發 T-24 停止條件⑥，停的是後續呼叫。"
    } else {
        "本次完整輸入與完整輸出均已保留；累計 $($costState.PercentUsed)%，流程續跑。"
    }
    return [pscustomobject][ordered]@{
        Success = $true; Blocked = $false; Available = $true; CallSent = $true
        SubmittedContent = $submitted; Content = [string]$vendorResult.Content; Usage = $usage; LedgerEntry = $entry
        StopTrigger = $stopTrigger; CostState = $costState; Alerts = @($alerts); NamedReport = $report
        Degradation = $null
    }
}

function Complete-T29CostedLoop {
    param(
        [Parameter(Mandatory = $true)][string]$WorkId,
        [Parameter(Mandatory = $true)][string]$AnchorRepo,
        [Parameter(Mandatory = $true)][int]$AnchorIssueNumber,
        [Parameter(Mandatory = $true)][string]$QueuePath,
        [Parameter(Mandatory = $true)]$LoopResult,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$CompletedReviewResults,
        [scriptblock]$NotificationSink,
        [switch]$SkipCompletedResultOutput
    )
    $outputResults = @($CompletedReviewResults)
    if ($SkipCompletedResultOutput) {
        Write-Warning '⚠️ -SkipCompletedResultOutput 已開啟：刻意丟棄停手前已產出的審查結果，僅供紅燈驗證，正式流程禁用。'
        $outputResults = @()
    }
    $finalized = Complete-StationRunLoop -WorkId $WorkId -AnchorRepo $AnchorRepo -AnchorIssueNumber $AnchorIssueNumber `
        -QueuePath $QueuePath -LoopResult $LoopResult -NotificationSink $NotificationSink
    return [pscustomobject][ordered]@{
        LoopResult = $finalized.LoopResult
        SummaryBody = $finalized.SummaryBody
        CommentItems = @($finalized.CommentItems)
        Notification = $finalized.Notification
        ReviewResults = @($outputResults)
    }
}

function Show-T29CostBoundaryUsage {
    Write-Host 'T-29 成本邊界函式庫（直接執行不會發送網路請求）'
    Write-Host '用法：dot-source .\cost-boundary.ps1 -FunctionsOnly，再呼叫 Invoke-T29MeteredVendorCall。'
    Write-Host '正式 CLI：.\invoke-metered-vendor.ps1 -Provider ... -BudgetPath ... -LedgerPath ...'
}

if (-not $T29LibraryFunctionsOnlyRequested) { Show-T29CostBoundaryUsage }
