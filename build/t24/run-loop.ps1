#requires -Version 5.1
<#
.SYNOPSIS
    T-24：`/station-run` 的 loop 主體——持續「選件 → 派工 → 收件 → 判 gate → 續派」，依 §5.3a
    三判準構成 frontier，遇六條停止條件之一即停手並具名停因。

.DESCRIPTION
    地基重用（依票面「直接呼叫，不要重寫」basis，本檔不重寫三判準與單次派工）：
      dot-source ../t12/run-common.ps1——該檔會 cascade dot-source ../t10/gate-check.ps1
      -FunctionsOnly，後者再 cascade dot-source ../t21/queue-common.ps1，一次載齊：
        - t21：Read-PatToken／Get-GithubHeaders／Read-QueueFile／Write-QueueFile／
          Split-RepoString／Get-CurrentIssue／ConvertTo-SafeArray／Set-ConsoleUtf8／
          Write-Utf8BomFile 等純工具與 GitHub 讀取函式。
        - t10：Get-CurrentStation（站別讀取，§3.4 結構性檢查）。
        - t12：**Select-NextActionableItem**（三判準過濾，frontier 定義，§5.3a）、
          **Invoke-RunDispatch**（含第八欄不可逆動作 dispatch 前檢查，§5.3a 停止條件①）、
          Add-RunQueueItemGuarded（run 產生權守門：僅 set-assignee／set-ticket-fields／comment）。
      本檔**不修改** t10／t12／t21 任何檔案（file ownership 邊界）。

    **本檔淨新增的邏輯**（T-24 的實際交付內容——loop 主體本身，不是三判準或單次派工）：
      ① Get-LoopStationKind：站別 → human-gate（1/2/3）／autonomous（4/5）／done 三分類，
         決定 loop 每輪的行為模式（§5.3a：「站 4／5 內部...不再逐次確認」vs「站 1／2／3...
         人類 gate」）。
      ② Test-CostLimitState：讀外廠成本狀態檔（schema 見 §7.6），判定 50%／80%／100%
         三段（100% ⇒ 觸發停止條件⑥）。**本票只負責讀取判定並讓停因⑥可被觸發**——逐次記帳
         本身（寫入 gate 紀錄）是 T-29 的職責，不在本票範圍；本函式對「檔案不存在」容忍降級為
         0%（尚無成本追蹤時不誤觸發停手）。
      ③ Test-ReworkStopCondition：同一票 rework 計數的純函式判定（§5.3a 停止條件②：
         「同一票 rework 2 次仍 fail」＝已 rework 2 次、第 3 次判定仍 fail ⇒ 停手）。
      ④ Test-NoConfirmationPrompts：機械掃描 loop 全程輸出行，命中「確認提問」樣式（是否確認／
         請確認／confirm?／y-n 等）視為違反驗收⑥「站 4／5 內部...全程未出現任何確認提問」。
      ⑤ Get-LoopCandidatePool／Invoke-LoopNaiveDispatchIgnoringIrreversible：**僅供紅燈驗證**
         的一對函式，刻意繞過三判準過濾／第八欄檢查，用來讓 T-24 自己的兩條核心斷言在測試中
         真的失敗一次（見 README「兩段紅燈設計」）。正式流程一律呼叫其對應的正常函式
         （Select-NextActionableItem 的 Eligible 清單／Invoke-RunDispatch）。
      ⑥ Invoke-StationRunLoop：loop 主體本身——把①～⑤與 t12 的三判準／單次派工／產生權守門
         串成一個真正會跑多輪的迴圈，直到六條停止條件之一成立。

    **「session 內記憶」的落地位置（依 §5.3a／§5.3b 對比說明：「session 內 loop 不受此影響，
    因為 Commander 自身即記憶」）**：手動階段寫入尚未落地（§4.6，佇列未套用），GitHub 上
    assignee 仍顯示為空；若每輪都重新查詢 GitHub 判斷「是否已派工過」，會把同一票重複選中。
    本檔用**迴圈本地的 `$excluded` 雜湊表**（迴圈執行期間的記憶體狀態，非狀態檔、不落地、
    迴圈結束即消失）記住「本輪迴圈已處理過的候選」，比照 t12 §5.3a 三判準③「尚無在跑
    executor」在手動階段「由 Commander 的 session 內記憶保證」的同一先例——差別只在於本檔
    的迴圈就是那個「session」的具體實作，取代了原本要由 Claude 對話記憶手動追蹤的部分。

    **與真實 sub-agent dispatch 的介面（誠實聲明，非規避）**：PowerShell 無法呼叫 Task 工具
    dispatch sub-agent（比照 t12 run-dispatch.ps1 的既有聲明），「收件 → 判 gate」這段本質上
    需要 Commander 實際執行 dispatch 並呼叫 `/station-gate`（T-10／T-13／未來 T-14／T-15a）
    取得結果。本檔用 `-GateResultProvider`（scriptblock，簽章 `param($Selected, $Iteration)`，
    回傳 `[pscustomobject]@{ Pass; ScopeChangeNeeded; Detail }`）把這段抽象成可注入介面：
      - 測試／未來 CI 自動化（§7.5／T-26）：注入模擬或真實呼叫的 provider，驅動 `Invoke-
        StationRunLoop` 真的跑完整多輪迴圈（本票 `t24-offline-test.ps1` 即此模式）。
      - 目前手動階段真實 session：Commander 在對話層扮演這個 provider 的角色——每輪讀本檔
        暴露的純函式（三判準／第八欄檢查／rework 計數／成本檢查／站別分類）做決策，實際
        dispatch 與呼叫 gate 由 Claude 自己執行後再回頭決定續派或停手，等同於手動展開本檔
        `Invoke-StationRunLoop` 內部同一套邏輯的其中一輪。兩者共用同一份決策函式，不重複
        維護兩份判準（DRY）。

.PARAMETER SkipFrontierFilter
    ⚠️ 僅供紅燈驗證使用（t24-offline-test.ps1 群組 F）。開啟後 `Invoke-StationRunLoop` 選件時
    改用「Eligible ＋ Rejected 全體候選（依票號排序）」而非僅 `Eligible`（三判準已過濾的清單），
    藉此讓「loop 只會派工 frontier 內合格票」這條斷言在測試中真的失敗一次（選中本應被拒絕的
    候選，例如有 `sc:blocked` 的票）。正式流程與一般手動執行絕對不得開啟。

.PARAMETER SkipIrreversibleHalt
    ⚠️ 僅供紅燈驗證使用（t24-offline-test.ps1 群組 G）。開啟後派工改呼叫
    `Invoke-LoopNaiveDispatchIgnoringIrreversible`——完全繞過 t12 `Invoke-RunDispatch` 內建的
    第八欄「不可逆動作」檢查，直接產生 `set-assignee` 佇列項，藉此讓「dispatch 前必先查第八欄」
    這條斷言真的失敗一次（宣告「不可逆動作：有」的票真的被派工、迴圈真的沒有停手）。正式流程
    與一般手動執行絕對不得開啟。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程（供 t24-offline-test.ps1 dot-source 呼叫內部函式）。
#>

[CmdletBinding(DefaultParameterSetName = 'Demo')]
param(
    [Parameter(ParameterSetName = 'Real')] [string]$WorkId,
    [Parameter(ParameterSetName = 'Real')] [string]$PrimaryRepo,
    [Parameter(ParameterSetName = 'Real')] [int]$AnchorIssue,
    [Parameter(ParameterSetName = 'Real')] [string[]]$ParticipatingRepos = @(),
    [Parameter(ParameterSetName = 'Real')] [string]$AssigneeLogin = '',
    [Parameter(ParameterSetName = 'Real')] [string]$PatPath = 'G:\default mount\station_command-key',
    [Parameter(ParameterSetName = 'Real')] [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [Parameter(ParameterSetName = 'Real')] [string]$CostStatePath = '',

    [Parameter(ParameterSetName = 'Demo')] [switch]$DemoMode,

    [switch]$SkipFrontierFilter,
    [switch]$SkipIrreversibleHalt,
    [switch]$SkipEnqueueGuard,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
# ⚠️ 命名為 $T24Dir 而非 $ScriptDir——理由見 ../t12/run-select.ps1／../t13/gate-station3.ps1 同段
# 註解（實跑抓到的真實 bug 先例，曾一度讓報告悄悄寫進 build/t10/）：下面 dot-source 的
# run-common.ps1 會 cascade dot-source ../t10/gate-check.ps1，該檔內部宣告未加 Script: 範圍的
# $ScriptDir 並指向 t10 自己的目錄；dot-source 全程共用同一層作用域，後執行的賦值會覆蓋前面的
# 同名變數。用一個下游任何被 dot-source 檔案都不會用到的獨有變數名，才能保證整個流程結束後
# 仍指向本檔（t24）自己的目錄。
$T24Dir = $PSScriptRoot
# 🔴 實跑抓到的第二個真實 bug（同一個 cascade 陷阱、不同變數）：run-common.ps1 內部以
# `. $Script:GateCheckPath -FunctionsOnly` dot-source ../t10/gate-check.ps1，而 gate-check.ps1
# **自己也宣告一個名為 `$FunctionsOnly` 的 `[switch]` 參數**（供它自己的 -FunctionsOnly 呼叫
# 綁定用）。dot-source 全程共用同一層作用域，t10 那次呼叫會把 `$FunctionsOnly` 重新綁定為
# `$true`（因為傳了 -FunctionsOnly），**覆蓋掉本檔自己的 `-FunctionsOnly` 參數變數**——即使
# 使用者呼叫本檔時完全沒帶 `-FunctionsOnly`，dot-source 結束後 `$FunctionsOnly` 也會被 t10
# 悄悄改成 `$true`，導致本檔結尾 `if (-not $FunctionsOnly) {...}` 永遠判 false、CLI 主流程
# 悄悄變成 no-op（症狀與票面警示的 $ScriptDir 案例同型：不是報錯，是安靜地什麼都不做）。
# 修法：在 dot-source 之前，把本檔自己收到的 `-FunctionsOnly` 值另存一份獨有變數名
# `$T24FunctionsOnlyRequested`，本檔結尾一律讀這個獨有變數，不再讀會被下游覆蓋的
# `$FunctionsOnly`。
$T24FunctionsOnlyRequested = [bool]$FunctionsOnly
# 🔴 同一個 cascade 陷阱的第三個實例，波及範圍更大：../t10/gate-check.ps1 的 param 區塊也宣告
# `$WorkId`／`$PrimaryRepo`／`$AnchorIssue`／`$ParticipatingRepos`／`$PatPath` 等同名參數（供它
# 自己的 CLI 呼叫綁定用）。run-common.ps1 內部 `. $Script:GateCheckPath -FunctionsOnly` 只傳
# `-FunctionsOnly`、不傳這些參數，dot-source 完成後這些變數會被 gate-check.ps1 的 param 預設值
# （空字串／0／空陣列）覆蓋——即使使用者呼叫本檔時明明有帶 `-WorkId W-xxx` 等真實值，dot-source
# 之後這些變數在本檔作用域內也會被靜靜清空，導致 CLI 的 Real 模式誤判成「未提供必要參數」。
# 修法（實跑 CLI smoke test 才抓到，證明測試真的有跑，非紙上談兵）：在 dot-source 之前，把本檔
# 自己收到的每個 Real 模式參數值另存一份獨有變數名（`$T24` 前綴），本檔結尾與 CLI 函式一律讀
# 這些獨有變數，不再讀會被下游覆蓋的原參數名。
$T24WorkId = $WorkId
$T24PrimaryRepo = $PrimaryRepo
$T24AnchorIssue = $AnchorIssue
$T24ParticipatingRepos = @($ParticipatingRepos)
$T24AssigneeLogin = $AssigneeLogin
$T24PatPath = $PatPath
$T24QueuePath = $QueuePath
$T24CostStatePath = $CostStatePath
$RunCommonPath = Join-Path $T24Dir '..\t12\run-common.ps1'
if (-not (Test-Path -LiteralPath $RunCommonPath)) {
    throw ("找不到 T-12 地基：{0}。請確認 t24 與 t12 為同層兄弟目錄。" -f $RunCommonPath)
}
. $RunCommonPath
Set-ConsoleUtf8

# ============================================================
# 六條停止條件正典（§5.3a 逐字承接，窮舉；本表僅供程式引用具名文字，不得散落他處自立停手規則）
# ============================================================
$Script:StopReasonCatalog = [ordered]@{
    '①' = '不可逆動作前（依 §3.5 第八欄的票級宣告判定，dispatch 前讀取，宣告「有」即停手待裁示）'
    '②' = '同一票 rework 2 次仍 fail'
    '③' = '站 1／2／3 的人類 gate（共識確認、spec 確認、拆票 quiz）'
    '④' = 'scope 需變更'
    '⑤' = 'frontier 空'
    '⑥' = '外廠累計成本達上限 100%（50%／80% 僅告警不停手）'
}
# 通知範圍（§5.3a：「停因為②③④⑥者 ⇒ 主動推播通知使用者；①⑤為安靜情形」）——本票只負責讓
# 停因可被外部讀取（下方 Test-StopReasonRequiresNotification），通知的**實作**屬 T-25，本票不做。
$Script:NotifyingStopReasons = @('②', '③', '④', '⑥')
$Script:SilentStopReasons = @('①', '⑤')

function Get-StopReasonText {
    param([Parameter(Mandatory)][string]$Reason)
    if (-not $Script:StopReasonCatalog.Contains($Reason)) {
        throw "Get-StopReasonText：'$Reason' 不在六條停止條件窮舉清單內（§5.3a 本清單為窮舉，不得自立第七條）"
    }
    return $Script:StopReasonCatalog[$Reason]
}

function Test-StopReasonRequiresNotification {
    param([Parameter(Mandatory)][string]$Reason)
    return [bool]($Script:NotifyingStopReasons -contains $Reason)
}

# ============================================================
# ① 站別分類：human-gate（1/2/3，不自動推進）／autonomous（4/5，loop 真正跑的範圍）／done
# ============================================================
function Get-LoopStationKind {
    param([Parameter(Mandatory)][string]$Station)
    switch ($Station) {
        'sc:station-1' { return 'human-gate' }
        'sc:station-2' { return 'human-gate' }
        'sc:station-3' { return 'human-gate' }
        'sc:station-4' { return 'autonomous' }
        'sc:station-5' { return 'autonomous' }
        'sc:station-done' { return 'done' }
        default { throw "Get-LoopStationKind：未知站別（不在 §3.4 站序正典內）：$Station" }
    }
}

# ============================================================
# ② 外廠成本上限（§7.6／§5.3a 停止條件⑥）——本票只負責讀取判定，逐次記帳本身是 T-29 職責。
# schema（本票定義的最小契約，供 T-29 未來寫入）：{ workId, percentUsed, limitType, provider }
# ============================================================
function Test-CostLimitState {
    param([string]$CostStatePath = '')
    if ([string]::IsNullOrWhiteSpace($CostStatePath) -or -not (Test-Path -LiteralPath $CostStatePath)) {
        return [pscustomobject]@{
            PercentUsed = 0; Reached100 = $false; Warn50 = $false; Warn80 = $false
            Detail      = '未提供成本狀態檔或檔案不存在：視為尚無外廠成本累計（§7.6 逐次記帳由 T-29 負責寫入，本票只負責讀取判定；未落地前不誤觸發任何告警或停手）'
        }
    }
    $raw = Get-Content -LiteralPath $CostStatePath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ PercentUsed = 0; Reached100 = $false; Warn50 = $false; Warn80 = $false; Detail = '成本狀態檔為空，視為 0%' }
    }
    $obj = $raw | ConvertFrom-Json
    if (-not ($obj.PSObject.Properties.Name -contains 'percentUsed')) {
        throw "成本狀態檔缺 percentUsed 欄位（schema：{workId, percentUsed, limitType, provider}）：$CostStatePath"
    }
    $pct = [double]$obj.percentUsed
    $reached100 = ($pct -ge 100)
    $warn80 = (-not $reached100) -and ($pct -ge 80)
    $warn50 = (-not $reached100) -and (-not $warn80) -and ($pct -ge 50)
    $limitType = if ($obj.PSObject.Properties.Name -contains 'limitType') { $obj.limitType } else { '未具名' }
    $provider = if ($obj.PSObject.Properties.Name -contains 'provider') { $obj.provider } else { '未具名' }
    $tail = if ($reached100) { '，已達上限 100% ⇒ 觸發 §5.3a 停止條件⑥（花下去拿不回來，與①不可逆同級）' }
            elseif ($warn80) { '，達 80% 告警（續跑，非停手）' }
            elseif ($warn50) { '，達 50% 告警（續跑，非停手）' }
            else { '，未達告警門檻' }
    $detail = "外廠累計成本 $pct%（provider=$provider，limitType=$limitType，§7.6）$tail"
    return [pscustomobject]@{ PercentUsed = $pct; Reached100 = $reached100; Warn50 = $warn50; Warn80 = $warn80; Detail = $detail }
}

# ============================================================
# ③ rework 計數純判定（§5.3a 停止條件②：「同一票 rework 2 次仍 fail」）
# 語意：已 rework N 次（N<2）且本輪仍 fail ⇒ 安排第 N+1 次 rework，續跑；
#       已 rework 2 次（皆已重派過）且本輪（第 3 次判定）仍 fail ⇒ 停手，具名停因②。
# ============================================================
function Test-ReworkStopCondition {
    param(
        [Parameter(Mandatory)][bool]$GateFailed,
        [Parameter(Mandatory)][int]$PriorReworkCount
    )
    if (-not $GateFailed) {
        return [pscustomobject]@{ Stop = $false; ShouldRework = $false; NewReworkCount = $PriorReworkCount; Detail = 'gate 判定通過，非 rework 情境' }
    }
    if ($PriorReworkCount -ge 2) {
        return [pscustomobject]@{ Stop = $true; ShouldRework = $false; NewReworkCount = $PriorReworkCount; Detail = "同一票已 rework $PriorReworkCount 次仍 fail（§5.3a 停止條件②）" }
    }
    $next = $PriorReworkCount + 1
    return [pscustomobject]@{ Stop = $false; ShouldRework = $true; NewReworkCount = $next; Detail = "第 $next 次 rework（尚未達 2 次上限，繼續重派同一票）" }
}

# ============================================================
# ④ 驗收⑥ 機械化檢查：站 4／5 內部全程不得出現「確認提問」樣式
# ============================================================
$Script:ConfirmationPromptPatterns = @(
    '(?i)是否確認', '(?i)請(您|使用者)?確認', '(?i)需要(您|使用者)?確認',
    '(?i)confirm\s*\?', '(?i)proceed\s*\?', '(?i)continue\s*\?',
    '(?i)\by/n\b', '(?i)\byes/no\b', '(?i)請問是否', '(?i)要繼續嗎', '(?i)OK嗎', '(?i)同意嗎', '(?i)是否同意'
)
function Test-NoConfirmationPrompts {
    # ⚠️ PS 5.1／7 皆同：Mandatory 參數對 [string[]] 陣列型別會逐元素套用「非空字串」檢查，
    # 陣列內任一元素為空字串（本檔的 $dr.Lines 慣例含分段用空白行）即整體綁定失敗，錯誤訊息
    # 具誤導性（「it is an empty string」聽起來像整個參數是空字串，其實是陣列裡的某一元素）。
    # 實測重現：PS 7.4.6 對 `[Parameter(Mandatory)][string[]]$X` 傳入 @("a","","b") 直接拋錯；
    # 補上 [AllowEmptyString()] 後才放行陣列內的空字串元素。修法非規避——本函式本就設計為
    # 接受含空白行的多行輸出。
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$OutputLines)
    $OutputLines = @($OutputLines)
    $hits = @()
    foreach ($line in $OutputLines) {
        foreach ($p in $Script:ConfirmationPromptPatterns) {
            if ($line -match $p) { $hits += [pscustomobject]@{ Line = $line; Pattern = $p }; break }
        }
    }
    $hits = @($hits)
    $detail = if ($hits.Count -eq 0) {
        "全程 $($OutputLines.Count) 行輸出，未出現任何確認提問樣式（Spec §5.3a：站 4／5 內部 dispatch／驗收／雙審／merge 一律不問）"
    } else {
        "命中 $($hits.Count) 處疑似確認提問：" + (($hits | ForEach-Object { "『$($_.Line)』(樣式:$($_.Pattern))" }) -join '；')
    }
    return [pscustomobject]@{ Clean = ($hits.Count -eq 0); Hits = $hits; Detail = $detail }
}

# ============================================================
# ⑤ 【僅供紅燈驗證】刻意繞過三判準過濾的候選池——正式流程一律用 -SkipFrontierFilter:$false
# （即只用 Eligible），本函式存在的唯一理由是讓「loop 只會派工 frontier 內合格票」這條斷言
# 在測試中可以真的失敗一次。
# ============================================================
function Get-LoopCandidatePool {
    param(
        [Parameter(Mandatory)]$SelectResult,
        [switch]$SkipFrontierFilter,
        [hashtable]$ExcludedNumbers = @{}
    )
    $pool = if ($SkipFrontierFilter) {
        Write-Warning "⚠️⚠️⚠️ -SkipFrontierFilter 已開啟：選件池改用『Eligible＋Rejected 全體候選』，忽略三判準過濾，僅供紅燈驗證使用，正式流程絕對不得使用。"
        @(@($SelectResult.Eligible) + @($SelectResult.Rejected) | Sort-Object Number)
    } else {
        @($SelectResult.Eligible | Sort-Object Number)
    }
    $pool = @($pool | Where-Object { -not $ExcludedNumbers.ContainsKey("$($_.RepoString)#$($_.Number)") })
    return , @($pool)
}

# ============================================================
# ⑥ 【僅供紅燈驗證】完全繞過 t12 Invoke-RunDispatch 內建的第八欄不可逆動作檢查，直接產生
# set-assignee 佇列項——正式流程一律呼叫 Invoke-RunDispatch（其內建檢查見 ../t12/run-common.ps1
# Invoke-RunDispatch）。本函式存在的唯一理由是讓「dispatch 前必先查第八欄」這條斷言在測試中
# 可以真的失敗一次：宣告「不可逆動作：有」的票，若繞過本檢查，真的會被派工。
# ============================================================
function Invoke-LoopNaiveDispatchIgnoringIrreversible {
    param(
        [Parameter(Mandatory)]$Selected,
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)][string]$AssigneeLogin,
        [Parameter(Mandatory)][string]$WorkId
    )
    Write-Warning "⚠️⚠️⚠️ -SkipIrreversibleHalt 已開啟：完全略過第八欄不可逆動作檢查，直接派工，僅供紅燈驗證使用，正式流程絕對不得使用。"
    $item = New-SetAssigneeItem -Repo $Selected.RepoString -IssueNumber $Selected.Number -Assignees @($AssigneeLogin) -Source $WorkId
    $add = Add-RunQueueItemGuarded -QueuePath $QueuePath -Item $item
    return [pscustomobject]@{
        Status = 'dispatch-ready'
        Lines  = @("⚠️ 紅燈模式（-SkipIrreversibleHalt）：略過不可逆檢查直接派工：$($add.Detail)")
    }
}

# ============================================================
# ⑦ loop 主體：把上面各函式與 t12 的三判準／單次派工串成真正會跑多輪的迴圈，
# 直到六條停止條件之一成立。
# ============================================================
function Invoke-StationRunLoop {
    param(
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][string]$PrimaryRepo,
        [Parameter(Mandatory)][int]$AnchorIssueNumber,
        [Parameter(Mandatory)][string[]]$ParticipatingRepos,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)][string]$AssigneeLogin,
        [Parameter(Mandatory)][scriptblock]$GateResultProvider,
        [string]$CostStatePath = '',
        [int]$MaxIterations = 50,
        [switch]$SkipFrontierFilter,
        [switch]$SkipIrreversibleHalt,
        [switch]$SkipEnqueueGuard
    )

    $allLines = New-Object System.Collections.ArrayList
    $roundSummaries = New-Object System.Collections.ArrayList
    $reworkCounts = @{}
    $excluded = @{}
    $pendingSelected = $null
    $stopReason = $null
    $stopDetail = $null
    $iterationsRun = 0

    for ($i = 1; $i -le $MaxIterations; $i++) {
        $iterationsRun = $i
        $r = Split-RepoString -RepoString $PrimaryRepo
        $anchor = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $AnchorIssueNumber -Headers $Headers
        if ($null -eq $anchor) {
            $stopDetail = "anchor 不存在：$PrimaryRepo#$AnchorIssueNumber（非六條停止條件之一，屬結構性錯誤，loop 終止）"
            [void]$allLines.Add($stopDetail)
            break
        }

        # ⑥ 成本檢查（每輪開頭先查，符合「已產出的結果照常輸出，停的是後續呼叫」）
        $cost = Test-CostLimitState -CostStatePath $CostStatePath
        if ($cost.Warn50 -or $cost.Warn80) { [void]$allLines.Add("[第 $i 輪][告警] $($cost.Detail)") }
        if ($cost.Reached100) {
            $stopReason = '⑥'; $stopDetail = $cost.Detail
            [void]$allLines.Add("[第 $i 輪][停止] 停因⑥：$stopDetail")
            break
        }

        $cur = Get-CurrentStation -Issue $anchor
        if (-not $cur.Valid) {
            $stopDetail = "站別歸因不合法，loop 無法安全判斷站別：$($cur.Detail)（非六條停止條件之一）"
            [void]$allLines.Add($stopDetail)
            break
        }

        $kind = Get-LoopStationKind -Station $cur.Station
        [void]$allLines.Add("[第 $i 輪] 現站：$($cur.Station)（$kind）")

        if ($kind -eq 'done') {
            $stopReason = '⑤'; $stopDetail = 'work 已完成態（sc:station-done），frontier 空'
            [void]$allLines.Add("[第 $i 輪][停止] 停因⑤：$stopDetail")
            break
        }

        if ($kind -eq 'human-gate') {
            $sel = Select-NextActionableItem -AnchorIssue $anchor -Station $cur.Station -WorkId $WorkId -PrimaryRepo $PrimaryRepo -ParticipatingRepos $ParticipatingRepos -Headers $Headers
            if (-not $sel.HasCandidate) {
                $stopReason = '⑤'; $stopDetail = "frontier 空（人類 gate 站別亦無可動作項）：$($sel.Detail)"
                [void]$allLines.Add("[第 $i 輪][停止] 停因⑤：$stopDetail")
                break
            }
            $dr = if ($SkipIrreversibleHalt) {
                Invoke-LoopNaiveDispatchIgnoringIrreversible -Selected $sel.Selected -QueuePath $QueuePath -AssigneeLogin $AssigneeLogin -WorkId $WorkId
            } else {
                Invoke-RunDispatch -Selected $sel.Selected -QueuePath $QueuePath -AssigneeLogin $AssigneeLogin -WorkId $WorkId -SkipEnqueueGuard:$SkipEnqueueGuard
            }
            [void]$allLines.AddRange(@($dr.Lines))
            if ($dr.Status -eq 'irreversible-stop') {
                $stopReason = '①'; $stopDetail = "dispatch 前偵測第八欄「不可逆動作：有」（$($sel.Selected.RepoString)#$($sel.Selected.Number)）"
                [void]$allLines.Add("[第 $i 輪][停止] 停因①：$stopDetail")
                break
            }
            [void]$roundSummaries.Add("第 $i 輪（$($cur.Station)）：$($sel.Selected.Kind) $($sel.Selected.RepoString)#$($sel.Selected.Number) — $($dr.Status)")
            $stopReason = '③'; $stopDetail = "工作位於 $($cur.Station)（站 1／2／3），不自動推進，停在人類 gate（共識確認／spec 確認／拆票 quiz）"
            [void]$allLines.Add("[第 $i 輪][停止] 停因③：$stopDetail")
            break
        }

        # kind -eq 'autonomous'（站 4／5，loop 真正持續運轉的範圍，站內部不逐次問）
        if ($null -ne $pendingSelected) {
            $selectedItem = $pendingSelected
            $pendingSelected = $null
        } else {
            $sel = Select-NextActionableItem -AnchorIssue $anchor -Station $cur.Station -WorkId $WorkId -PrimaryRepo $PrimaryRepo -ParticipatingRepos $ParticipatingRepos -Headers $Headers
            # PS 5.1/StrictMode 陷阱③：Get-LoopCandidatePool 內部以 `return ,@(...)` 保住陣列型別，
            # 呼叫端不可再直接 `@(函式呼叫本身)`（會把已保護好的陣列再包一層，3 筆變 1 筆內容為
            # 3 筆的巢狀陣列）——一律先賦值給變數，再對已賦值變數包 @()（同 queue-common.ps1 慣例）。
            $poolRaw = Get-LoopCandidatePool -SelectResult $sel -SkipFrontierFilter:$SkipFrontierFilter -ExcludedNumbers $excluded
            $pool = @($poolRaw)
            if ($pool.Count -eq 0) {
                $stopReason = '⑤'; $stopDetail = "frontier 空：$($sel.Detail)"
                [void]$allLines.Add("[第 $i 輪][停止] 停因⑤：$stopDetail")
                break
            }
            $selectedItem = $pool[0]
            $selKey = "$($selectedItem.RepoString)#$($selectedItem.Number)"
            # 迴圈本地記憶（本檔頭部說明的「session 內記憶」）：本輪選過就排除，避免手動階段
            # 佇列未落地、GitHub 現況仍顯示無 assignee 而被重複選中。
            $excluded[$selKey] = $true

            $dr = if ($SkipIrreversibleHalt) {
                Invoke-LoopNaiveDispatchIgnoringIrreversible -Selected $selectedItem -QueuePath $QueuePath -AssigneeLogin $AssigneeLogin -WorkId $WorkId
            } else {
                Invoke-RunDispatch -Selected $selectedItem -QueuePath $QueuePath -AssigneeLogin $AssigneeLogin -WorkId $WorkId -SkipEnqueueGuard:$SkipEnqueueGuard
            }
            [void]$allLines.AddRange(@($dr.Lines))

            if ($dr.Status -eq 'irreversible-stop') {
                $stopReason = '①'; $stopDetail = "dispatch 前偵測第八欄「不可逆動作：有」（$selKey）"
                [void]$allLines.Add("[第 $i 輪][停止] 停因①：$stopDetail")
                break
            }
            if ($dr.Status -ne 'dispatch-ready') {
                # invalid／guard-blocked：非六條停止條件之一（§5.3a 窮舉不含此項），視為該候選
                # 本輪不可派工，已排除（$excluded），本輪不呼叫 gate，續下一輪重新選件。
                [void]$allLines.Add("[第 $i 輪] 候選 $selKey 派工未就緒（$($dr.Status)），已排除後續選件，本輪不呼叫 gate")
                continue
            }
        }

        $selKey = "$($selectedItem.RepoString)#$($selectedItem.Number)"
        $gateResult = & $GateResultProvider $selectedItem $i

        if ($gateResult.ScopeChangeNeeded) {
            $stopReason = '④'; $stopDetail = "票 $selKey 判 gate 時偵測 scope 需變更：$($gateResult.Detail)"
            [void]$allLines.Add("[第 $i 輪][停止] 停因④：$stopDetail")
            break
        }

        if ($gateResult.Pass) {
            [void]$allLines.Add("[第 $i 輪] 票 $selKey gate 判定：PASS — $($gateResult.Detail)")
            [void]$roundSummaries.Add("第 $i 輪：$selKey PASS")
            continue
        }

        $priorCount = if ($reworkCounts.ContainsKey($selKey)) { $reworkCounts[$selKey] } else { 0 }
        $rc = Test-ReworkStopCondition -GateFailed $true -PriorReworkCount $priorCount
        [void]$allLines.Add("[第 $i 輪] 票 $selKey gate 判定：FAIL — $($gateResult.Detail)；$($rc.Detail)")
        if ($rc.Stop) {
            $stopReason = '②'; $stopDetail = "票 $selKey：$($rc.Detail)"
            [void]$allLines.Add("[第 $i 輪][停止] 停因②：$stopDetail")
            break
        }
        $reworkCounts[$selKey] = $rc.NewReworkCount
        $pendingSelected = $selectedItem
        [void]$roundSummaries.Add("第 $i 輪：$selKey FAIL，安排第 $($rc.NewReworkCount) 次 rework")
    }

    if ($null -eq $stopReason -and $iterationsRun -ge $MaxIterations) {
        $stopDetail = "已達安全上限 $MaxIterations 輪仍未觸發任何停止條件（非六條之一，屬迴圈安全閥，防止測試或誤用情境下無限迴圈；正式六條停止條件見上方逐輪紀錄）"
        [void]$allLines.Add("[安全閥] $stopDetail")
    }

    $confirmChk = Test-NoConfirmationPrompts -OutputLines @($allLines)

    return [pscustomobject]@{
        StopReason                = $stopReason
        StopReasonText            = if ($stopReason) { Get-StopReasonText -Reason $stopReason } else { $null }
        StopDetail                = $stopDetail
        RequiresNotification      = if ($stopReason) { Test-StopReasonRequiresNotification -Reason $stopReason } else { $false }
        Lines                     = @($allLines)
        RoundSummaries            = @($roundSummaries)
        IterationsRun             = $iterationsRun
        ReworkCounts              = $reworkCounts
        NoConfirmationPromptsCheck = $confirmChk
    }
}

# ============================================================
# CLI：DemoMode（不連網、不需 PAT，純示範接線是否正確，供交件前 smoke test 使用）
# ============================================================
function Invoke-RunLoopDemoCli {
    $lines = @("run-loop DemoMode 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "T24Dir=$T24Dir", "")

    $lines += "① Get-LoopStationKind 三分類：station-1=$(Get-LoopStationKind -Station 'sc:station-1')　station-4=$(Get-LoopStationKind -Station 'sc:station-4')　station-done=$(Get-LoopStationKind -Station 'sc:station-done')"

    $costNone = Test-CostLimitState -CostStatePath ''
    $lines += "② Test-CostLimitState（未提供檔案）：Reached100=$($costNone.Reached100)　$($costNone.Detail)"

    $reworkChk = Test-ReworkStopCondition -GateFailed $true -PriorReworkCount 2
    $lines += "③ Test-ReworkStopCondition（已 rework 2 次仍 fail）：Stop=$($reworkChk.Stop)　$($reworkChk.Detail)"

    $confirmChk = Test-NoConfirmationPrompts -OutputLines @('派工完成，繼續下一輪', '是否確認要繼續？')
    $lines += "④ Test-NoConfirmationPrompts（含一行故意違規文字）：Clean=$($confirmChk.Clean)（預期 False，證明掃描器真的會抓到）　$($confirmChk.Detail)"

    # 用 t12 已重用的純函式（不連網）示範選件＋派工在人類 gate 站別（work 級，anchor 本身即候選，
    # Select-NextActionableItem 對此路徑不發任何 Invoke-RestMethod 呼叫，可安全在無 PAT 環境執行）
    $demoAnchor = [pscustomobject]@{
        number    = 1
        title     = 'W-t24-demo · primary anchor'
        body      = 'spec 草案 body（demo，無 executor 宣告）'
        labels    = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-2' })
        assignees = @()
    }
    $demoQueuePath = Join-Path $T24Dir 'run-loop-demo-queue.json'
    if (Test-Path -LiteralPath $demoQueuePath) { Remove-Item -LiteralPath $demoQueuePath -Force }
    $sel = Select-NextActionableItem -AnchorIssue $demoAnchor -Station 'sc:station-2' -WorkId 'W-t24-demo' -PrimaryRepo 'demo/repo' -ParticipatingRepos @('demo/repo') -Headers @{}
    $lines += "⑤ Select-NextActionableItem（station-2，work 級，不連網）：HasCandidate=$($sel.HasCandidate)　$($sel.Detail)"
    if ($sel.HasCandidate) {
        $dr = Invoke-RunDispatch -Selected $sel.Selected -QueuePath $demoQueuePath -AssigneeLogin 'demo-user' -WorkId 'W-t24-demo'
        $lines += "⑥ Invoke-RunDispatch：Status=$($dr.Status)"
        $lines += ($dr.Lines | ForEach-Object { "    $_" })
        $queueAfter = ConvertTo-SafeArray -RawValue (Read-QueueFile -QueuePath $demoQueuePath)
        $lines += "⑦ demo 佇列檔筆數：$(@($queueAfter).Count)（$demoQueuePath）"
    }
    Remove-Item -LiteralPath $demoQueuePath -Force -ErrorAction SilentlyContinue

    $lines += ''
    $lines += 'DemoMode 全程不連網、不需 PAT、不修改 build/t24 之外任何檔案；純粹證明本檔的函式真的會執行（非靜默 no-op）且路徑解析正確指向 T24Dir。'

    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T24Dir 'run-loop-demo-report.txt') -Content ($lines -join [Environment]::NewLine)
    exit 0
}

# ============================================================
# CLI：Real 模式——單輪決策（讀 GitHub 現況 → 站別分類 → 成本檢查 → 選件＋派工或具名停手）。
# 真正的多輪迴圈（Invoke-StationRunLoop）需要「收件→判 gate」的真實結果，PowerShell 無法自行
# dispatch sub-agent（見檔頭說明），故 CLI 每次呼叫只做一輪，由 Commander 在對話層重複呼叫並
# 提供實際 dispatch／gate 結果來決定下一輪動作；`Invoke-StationRunLoop` 本身供自動化測試／未來
# CI（§7.5／T-26）以可注入 provider 的方式跑完整多輪。
# ============================================================
function Invoke-RunLoopRealCli {
    if (-not $T24WorkId -or -not $T24PrimaryRepo -or -not $T24AnchorIssue) {
        throw '直接執行模式須提供 -WorkId -PrimaryRepo -AnchorIssue（或改用 -DemoMode／-FunctionsOnly）'
    }
    $Token = Read-PatToken -PatPath $T24PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t24-run-loop'
    $participating = if (@($T24ParticipatingRepos).Count -gt 0) { @($T24ParticipatingRepos) } else { @($T24PrimaryRepo) }
    $r = Split-RepoString -RepoString $T24PrimaryRepo
    $anchor = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $T24AnchorIssue -Headers $Headers
    if ($null -eq $anchor) { throw "找不到 anchor：$T24PrimaryRepo#$T24AnchorIssue" }

    $lines = @("run-loop 執行報告（單輪決策） — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "WorkId=$T24WorkId  Anchor=$T24PrimaryRepo#$T24AnchorIssue", "")

    $cost = Test-CostLimitState -CostStatePath $T24CostStatePath
    $lines += "成本檢查：$($cost.Detail)"
    if ($cost.Reached100) {
        $lines += "[停止] 停因⑥：$($cost.Detail)"
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T24Dir 'run-loop-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 6
    }

    $cur = Get-CurrentStation -Issue $anchor
    if (-not $cur.Valid) {
        $lines += "拒絕（§3.4 站別歸因，結構性檢查）：$($cur.Detail)"
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T24Dir 'run-loop-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 1
    }
    $kind = Get-LoopStationKind -Station $cur.Station
    $lines += "現站：$($cur.Station)（$kind）"

    $sel = Select-NextActionableItem -AnchorIssue $anchor -Station $cur.Station -WorkId $T24WorkId -PrimaryRepo $T24PrimaryRepo -ParticipatingRepos $participating -Headers $Headers
    if (-not $sel.HasCandidate) {
        $lines += "[停止] 停因⑤：$($sel.Detail)"
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T24Dir 'run-loop-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 2
    }

    $effectiveAssignee = if ($T24AssigneeLogin) { $T24AssigneeLogin } else {
        try { (Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $Headers -Method Get).login } catch { $null }
    }
    if (-not $effectiveAssignee) {
        $lines += '無法決定 assignee 帳號（-AssigneeLogin 未提供且 /user 讀取失敗），拒絕派工。'
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T24Dir 'run-loop-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 1
    }

    $dr = Invoke-RunDispatch -Selected $sel.Selected -QueuePath $T24QueuePath -AssigneeLogin $effectiveAssignee -WorkId $T24WorkId -SkipEnqueueGuard:$SkipEnqueueGuard
    $lines += $dr.Lines
    if ($dr.Status -eq 'irreversible-stop') {
        $lines += "[停止] 停因①"
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T24Dir 'run-loop-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 5
    }
    if ($kind -eq 'human-gate') {
        $lines += "[停止] 停因③：工作位於 $($cur.Station)，不自動推進，停在人類 gate"
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T24Dir 'run-loop-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 3
    }
    $lines += "本輪派工完成，等待 Commander 實際 dispatch＋判 gate 後再次呼叫本 CLI 決定續派或停手（見檔頭說明）。"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T24Dir 'run-loop-report.txt') -Content ($lines -join [Environment]::NewLine)
    switch ($dr.Status) {
        'dispatch-ready' { exit 0 }
        'invalid'        { exit 4 }
        'guard-blocked'  { exit 7 }
        default          { exit 1 }
    }
}

if (-not $T24FunctionsOnlyRequested) {
    if ($DemoMode) { Invoke-RunLoopDemoCli } else { Invoke-RunLoopRealCli }
}
