#requires -Version 5.1
<#
.SYNOPSIS
    T-15a：站 5 票級雙審驗收器——輸入分離核對、報告不合併、verifier≠executor≠Commander、
    修復必須復驗、SC#6 隔離未實測標註、收尾摘要（軸內 worst、禁跨軸贏家）；全過才產生單一次
    close-issue 佇列項關票。

.DESCRIPTION
    依 Spec_station-command_v1.11.md §5.2（站 5 雙審規則）、§6 站5 出口條件、§3.3（sc:red-proven
    僅票、gate 唯一寫入者）、SC#6（雙審輸入分離可證、隔離未證須具名）實作。

    重用地基（不重寫，DRY）：dot-source ../t10/gate-reset.ps1 -FunctionsOnly（cascade 進
    ../t10/gate-check.ps1 → ../t21/queue-common.ps1），取得 Read-PatToken／Get-GithubHeaders／
    Split-RepoString／Get-CurrentIssue／Get-IssueTimelineEvents／ConvertTo-SafeArray／
    Write-Utf8BomFile／Set-ConsoleUtf8／Read-QueueFile／Write-QueueFile。另 dot-source本目錄
    station5-dispatch-prep.ps1 -FunctionsOnly 取得 Test-PromptTextMarkers（輸入分離第二道防線，
    避免兩檔各自維護一份同型判準）。本檔**不修改** build/t10／build/t21／build/station-command
    任何檔案（file ownership 邊界）。

    本票判讀對象是**兩軸 sub-agent 回傳的報告內容（結構化 JSON）**，🚫 不執行被測系統、不重跑
    diff 對應的程式碼。實際 dispatch（Task 呼叫兩個平行 fresh-context general-purpose sub-agent）
    是 Commander 的動作，本檔只做「輸入分離核對 → 報告驗證 → 產生關票佇列項」。

    七項查核（對應驗收①②③⑤⑥與 Spec §6 站5 checklist 其餘項）：
      ①a Test-AxisInputSeparation：軸 A inputList 僅 diff／standards／smell-baseline 三類
          （禁 spec 類）；軸 B inputList 僅 diff／spec 兩類（禁 standards／smell-baseline）。
          結構性（kind 白名單）為第一道防線；Test-PromptTextMarkers（dot-source 自
          station5-dispatch-prep.ps1）為第二道 best-effort 文字掃描。
      ①b Test-AxisStandardsNamed：軸 A 須具名本輪所用 repo 規範檔案與版本，或明文「該repo無
          落檔規範，本輪僅以基線審」（依 station-command/assets/fowler-smells.md「站 5 報告
          義務」段）。
       - Test-ReportsNotMerged：兩份報告分開留存，submission 不得出現任何合併／跨軸重排欄位。
       - Test-FindingsRemediated：hard finding 須附修法證據；judgement call 須有裁決紀錄
         （逐軸逐條）。
      ③  Test-Station5VerifierIndependent：verifier ≠ executor，且不得是 Commander。
      ②  Test-RemediationVerified：修復 commit 不得自動視為已驗，須經 verifier 重跑驗收條件
          或兩軸補審一輪；未經復驗即結案 ⇒ 拒絕。**本項為本票紅燈設計標的**（見 -SkipRemediation
          Check）。
      ⑤  Test-IsolationDisclaimer：SC-DEC-ISO-001 落檔前，結案報告缺隔離未實測固定字串
          ⇒ gate fail；落檔後解除。
      ⑥  Test-ClosingSummary：收尾摘要須含各軸 findings 總數與軸內 worst（若有），🚫 不得出現
          跨軸挑出的單一贏家。

    -SkipRemediationCheck：⚠️⚠️⚠️ 僅供紅燈驗證使用，正式流程與一般手動執行絕對不得使用——開啟
      後②的查核整段略過、一律視為已復驗，用於讓 t15a-offline-test.ps1 對「未經復驗即結案必須
      被拒絕」這條斷言在該次執行下真的失敗一次（斷言失敗型紅燈存證），詳見 README。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程（供離線／動態測試 dot-source 呼叫內部函式）。
#>

[CmdletBinding(DefaultParameterSetName = 'Check')]
param(
    [Parameter(ParameterSetName = 'Check', Mandatory)]
    [string]$SubmissionPath,

    [Parameter(ParameterSetName = 'Check', Mandatory)]
    [string]$Repo,

    [Parameter(ParameterSetName = 'Check', Mandatory)]
    [int]$Issue,

    [Parameter(ParameterSetName = 'Check')]
    [string]$Source = '',

    [Parameter(ParameterSetName = 'Check')]
    [switch]$SkipRemediationCheck,

    [Parameter(ParameterSetName = 'Verify', Mandatory)]
    [switch]$VerifyClosed,

    [Parameter(ParameterSetName = 'Verify', Mandatory)]
    [string]$VerifyRepoArg,

    [Parameter(ParameterSetName = 'Verify', Mandatory)]
    [int]$VerifyIssueArg,

    [Parameter(ParameterSetName = 'Verify')]
    [string[]]$GateIdentityLogins = @(),

    [string]$PatPath = 'G:\default mount\station_command-key',

    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),

    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
# ⚠️ 用 $T15aCheckDir 而非 $ScriptDir／$T15aDir——理由同 T-12／T-14 記載的實跑 bug：dot-source
# ../t10/gate-reset.ps1 會 cascade 進 ../t10/gate-check.ps1（宣告未加 Script: 範圍的 $ScriptDir
# 並指向 t10 目錄），且本檔自己也會 dot-source 同層的 station5-dispatch-prep.ps1（宣告
# $T15aPrepDir）——全程共用同一層作用域，用互不相同的獨有變數名才不會互相覆蓋。
$T15aCheckDir = $PSScriptRoot

# 🔴 rework（實跑抓到並修正的真實 bug，非憑空預防）：../t10/gate-reset.ps1／
# ../t10/gate-check.ps1／station5-dispatch-prep.ps1 三檔**各自也都宣告了一個同名參數
# `$FunctionsOnly`**。dot-source 與被 dot-source 的腳本共用同一層作用域，被 dot-source 腳本
# 自己的 param 綁定會**覆蓋**呼叫端已綁定好的同名變數——下面兩行 `. ... -FunctionsOnly` 執行完
# 後，本檔自己的 `$FunctionsOnly`（使用者從命令列傳入的值，這裡預期是 `$false`，因為要跑
# Check／Verify 模式）會被內層腳本綁定時建立的 `$FunctionsOnly = $true` 蓋掉，導致本檔最後的
# `if (-not $FunctionsOnly) { ... }` 誤判為「只載入函式、不執行」，CLI 模式因而悄悄變成
# no-op（無輸出、exit 0，看起來像成功但其實整段 Check／Verify 邏輯根本沒跑）。用實際跑
# `.\station5-check.ps1 -SubmissionPath ... -Repo ... -Issue ...`（不帶 -FunctionsOnly）
# 才會抓到——離線測試因為本來就是用 -FunctionsOnly 呼叫本檔，測不出這條路徑。
# 修法：在任何 dot-source 之前，先把呼叫端原始意圖存進獨有變數名 `$T15aRequestedFunctionsOnly`，
# 底部一律讀這個變數，不再信任可能已被覆蓋的 `$FunctionsOnly`。
$T15aRequestedFunctionsOnly = $FunctionsOnly.IsPresent

$GateResetPath = Join-Path $T15aCheckDir '..\t10\gate-reset.ps1'
if (-not (Test-Path -LiteralPath $GateResetPath)) {
    throw ("找不到 T-10 地基：{0}。請確認 t15a 與 t10 為同層兄弟目錄。" -f $GateResetPath)
}
. $GateResetPath -FunctionsOnly

$DispatchPrepPath = Join-Path $T15aCheckDir 'station5-dispatch-prep.ps1'
if (-not (Test-Path -LiteralPath $DispatchPrepPath)) {
    throw ("找不到本票的 dispatch-prep 檔：{0}" -f $DispatchPrepPath)
}
. $DispatchPrepPath -FunctionsOnly
Set-ConsoleUtf8

# ============================================================
# 讀交件（兩軸 sub-agent 報告的結構化 JSON；靜態文本，不執行任何被測程式碼）
# ============================================================
function Read-Station5Submission {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "交件檔不存在：$Path" }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $obj = $raw | ConvertFrom-Json
    $required = @('ticket', 'executor', 'verifier', 'axisA', 'axisB', 'remediation', 'isolationDecisionRecorded', 'closingReportText', 'closingSummary')
    $missing = @($required | Where-Object { -not ($obj.PSObject.Properties.Name -contains $_) })
    if (@($missing).Count -gt 0) {
        throw "交件缺必填欄位：$($missing -join '、')（schema 見 fixtures/README.md）"
    }
    foreach ($axisName in @('axisA', 'axisB')) {
        $axis = $obj.$axisName
        if (-not ($axis.PSObject.Properties.Name -contains 'inputList') -or -not ($axis.PSObject.Properties.Name -contains 'findings')) {
            throw "$axisName 缺 inputList 或 findings 欄位"
        }
    }
    return $obj
}

# ============================================================
# ①a 輸入分離：結構性（kind 白名單）＋ 第二道 best-effort 文字掃描（重用 dispatch-prep）
# ============================================================
function Test-AxisInputSeparation {
    param(
        [Parameter(Mandatory)][ValidateSet('AxisA', 'AxisB')][string]$Axis,
        [Parameter(Mandatory)][array]$InputList
    )
    $InputList = @($InputList)
    $allowedKinds = if ($Axis -eq 'AxisA') { @('diff', 'standards', 'smell-baseline') } else { @('diff', 'spec') }
    $forbiddenLabel = if ($Axis -eq 'AxisA') { 'spec' } else { 'standards／smell-baseline' }

    $violations = @()
    foreach ($item in $InputList) {
        $kind = if ($item.PSObject.Properties.Name -contains 'kind') { $item.kind } else { $null }
        if ($null -eq $kind -or $allowedKinds -notcontains $kind) {
            $valuePreview = if ($item.PSObject.Properties.Name -contains 'value' -and $item.value) { ($item.value.ToString()).Substring(0, [Math]::Min(60, $item.value.ToString().Length)) } else { '(無 value)' }
            $violations += "kind='$kind'（不在允許清單 [$($allowedKinds -join '／')] 內，禁止類別：$forbiddenLabel）：`"$valuePreview...`""
        }
    }
    $violations = @($violations)

    $concatText = ($InputList | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'value') { $_.value } else { '' } }) -join "`n"
    $markerAxis = if ($Axis -eq 'AxisA') { 'AxisA' } else { 'AxisB' }
    $markerChk = Test-PromptTextMarkers -Axis $markerAxis -PromptText $concatText

    $structuralOk = ($violations.Count -eq 0)
    $overallOk = $structuralOk -and $markerChk.Satisfied

    $detail = if ($overallOk) {
        "$Axis 輸入清單共 $($InputList.Count) 項，kind 皆在允許清單內，且第二道文字掃描未命中禁止標記"
    } else {
        $parts = @()
        if (-not $structuralOk) { $parts += "結構性違規：" + ($violations -join '；') }
        if (-not $markerChk.Satisfied) { $parts += "文字掃描：$($markerChk.Detail)" }
        ($parts -join '｜')
    }
    return [pscustomobject]@{ Satisfied = $overallOk; Detail = $detail }
}

# ============================================================
# ①b 軸 A 須具名本輪所用 repo 規範檔案與版本（或明文無落檔規範）
# ============================================================
function Test-AxisAStandardsNamed {
    param([Parameter(Mandatory)]$AxisA)
    $fileUsed = if ($AxisA.PSObject.Properties.Name -contains 'standardsFileUsed') { $AxisA.standardsFileUsed } else { $null }
    $version = if ($AxisA.PSObject.Properties.Name -contains 'standardsVersion') { $AxisA.standardsVersion } else { $null }
    $noStatement = if ($AxisA.PSObject.Properties.Name -contains 'noStandardsStatement') { $AxisA.noStandardsStatement } else { $null }

    if (-not [string]::IsNullOrWhiteSpace($fileUsed) -and -not [string]::IsNullOrWhiteSpace($version)) {
        return [pscustomobject]@{ Satisfied = $true; Detail = "已具名採用檔案='$fileUsed'，版本='$version'" }
    }
    if (-not [string]::IsNullOrWhiteSpace($noStatement) -and ($noStatement -match '(?i)無落檔規範|no.*standards.*(file|doc)')) {
        return [pscustomobject]@{ Satisfied = $true; Detail = "已具名『無落檔規範』聲明：`"$noStatement`"" }
    }
    return [pscustomobject]@{ Satisfied = $false; Detail = '軸 A 報告未具名本輪所用 repo 規範檔案與版本，亦無「該repo無落檔規範」明文聲明（依 station-command/assets/fowler-smells.md「站 5 報告義務」，fail-closed）' }
}

# ============================================================
# 兩份報告分開留存，不得合併／跨軸重排（結構上已用兩個獨立欄位保證；本項擋「另開合併欄位」偷渡）
# ============================================================
function Test-ReportsNotMerged {
    param([Parameter(Mandatory)]$Submission)
    $forbiddenKeys = @('mergedFindings', 'combinedFindings', 'allFindings', 'rankedFindings', 'overallWinner', 'singleWinner', 'crossAxisRanking')
    $present = @($forbiddenKeys | Where-Object { $Submission.PSObject.Properties.Name -contains $_ })
    $ok = (@($present).Count -eq 0)
    $detail = if ($ok) {
        '未出現任何合併／跨軸重排欄位；軸 A／軸 B findings 各自獨立留存（Pocock code-review 逐字：Do not merge or rerank findings — the two axes are deliberately separate）'
    } else {
        "出現禁止的合併／重排欄位：$($present -join '、')（違反『兩軸不得合併重排』）"
    }
    return [pscustomobject]@{ Satisfied = $ok; Detail = $detail }
}

# ============================================================
# hard finding 須附修法證據；judgement call 須有裁決紀錄（逐軸逐條）
# ============================================================
function Test-FindingsRemediated {
    param([Parameter(Mandatory)][string]$AxisLabel, [Parameter(Mandatory)][AllowEmptyCollection()][array]$Findings)
    $Findings = @($Findings)
    $bad = @()
    foreach ($f in $Findings) {
        $sev = if ($f.PSObject.Properties.Name -contains 'severity') { $f.severity } else { $null }
        $id = if ($f.PSObject.Properties.Name -contains 'id') { $f.id } else { '(無 id)' }
        if ($sev -eq 'hard') {
            $ev = if ($f.PSObject.Properties.Name -contains 'remediationEvidence') { $f.remediationEvidence } else { '' }
            if ([string]::IsNullOrWhiteSpace($ev)) { $bad += "$id（hard）缺修法證據（remediationEvidence）" }
        } elseif ($sev -eq 'judgement') {
            $dec = if ($f.PSObject.Properties.Name -contains 'decision') { $f.decision } else { '' }
            if ([string]::IsNullOrWhiteSpace($dec)) { $bad += "$id（judgement）缺裁決紀錄（decision）" }
        } else {
            $bad += "$id 的 severity 值不合法（須為 hard 或 judgement，實得='$sev'）"
        }
    }
    $bad = @($bad)
    $ok = ($bad.Count -eq 0)
    $detail = if ($ok) { "$AxisLabel 共 $($Findings.Count) 條 findings，hard 皆附修法證據、judgement 皆有裁決紀錄" } else { "$AxisLabel 缺項：" + ($bad -join '；') }
    return [pscustomobject]@{ Satisfied = $ok; Detail = $detail }
}

# ============================================================
# ③ verifier ≠ executor，且不得是 Commander（Spec §5.2 hard rule）
# ============================================================
function Test-Station5VerifierIndependent {
    param([Parameter(Mandatory)][string]$Executor, [Parameter(Mandatory)][AllowEmptyString()][string]$Verifier)
    $execN = $Executor.Trim().ToLowerInvariant()
    $verN = $Verifier.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($verN)) {
        return [pscustomobject]@{ Satisfied = $false; Detail = 'verifier 欄位為空，無法確認 verifier≠executor（fail-closed）' }
    }
    if ($verN -eq $execN) {
        return [pscustomobject]@{ Satisfied = $false; Detail = "verifier 與 executor 相同（'$Executor'）——執行者自陳不能當驗收（Spec §5.2）" }
    }
    if ($verN -match '^(commander|主\s*session|main\s*session|claude\s*主\s*session)$') {
        return [pscustomobject]@{ Satisfied = $false; Detail = "verifier 為 Commander（'$Verifier'）——Spec §5.2『verifier ≠ executor，亦不得是 Commander』" }
    }
    return [pscustomobject]@{ Satisfied = $true; Detail = "verifier（'$Verifier'）≠ executor（'$Executor'）且非 Commander" }
}

# ============================================================
# ② 修復必須復驗（Spec §5.2）——本票紅燈設計標的
# ============================================================
function Test-RemediationVerified {
    param([Parameter(Mandatory)]$Remediation, [switch]$SkipRemediationCheck)

    if ($SkipRemediationCheck) {
        return [pscustomobject]@{
            Satisfied = $true
            Detail    = '⚠️⚠️⚠️ -SkipRemediationCheck 已開啟：略過修復復驗查核，一律視為已復驗（僅供紅燈驗證使用，正式流程與一般手動執行絕對不得使用，見 README）'
        }
    }

    $verified = if ($Remediation.PSObject.Properties.Name -contains 'verified') { [bool]$Remediation.verified } else { $false }
    if (-not $verified) {
        return [pscustomobject]@{ Satisfied = $false; Detail = '未經復驗即結案——Spec §5.2『修復必須復驗』：為清除 finding 而產生的修復 commit 不得自動視為已驗，須經 verifier 重跑該票驗收條件或兩軸補審一輪（remediation.verified=false 或缺漏）' }
    }
    $method = if ($Remediation.PSObject.Properties.Name -contains 'method') { $Remediation.method } else { $null }
    if ($method -notin @('verifier-rerun', 'two-axis-supplement')) {
        return [pscustomobject]@{ Satisfied = $false; Detail = "remediation.method 不合法（須為 verifier-rerun 或 two-axis-supplement 之一，實得='$method'）——二擇一完成後方可結案（Spec §5.2）" }
    }
    $evidence = if ($Remediation.PSObject.Properties.Name -contains 'evidence') { $Remediation.evidence } else { '' }
    if ([string]::IsNullOrWhiteSpace($evidence)) {
        return [pscustomobject]@{ Satisfied = $false; Detail = 'remediation.evidence 為空——復驗須留存證據（重跑結果或補審結論），不得只填 verified=true 沒有內容' }
    }
    return [pscustomobject]@{ Satisfied = $true; Detail = "已復驗：方式=$method，證據：$evidence" }
}

# ============================================================
# ⑤ SC#6 隔離未實測標註（在 SC-DEC-ISO-001 落檔前為預設狀態，不需 T-03 完成即可測）
# ============================================================
function Test-IsolationDisclaimer {
    param([Parameter(Mandatory)][bool]$IsolationDecisionRecorded, [Parameter(Mandatory)][AllowEmptyString()][string]$ClosingReportText)
    $fixedString = 'context 隔離未實測，本結論僅由輸入分離支撐'
    if ($IsolationDecisionRecorded) {
        return [pscustomobject]@{ Satisfied = $true; Detail = 'SC-DEC-ISO-001 已落檔（隔離成立）——依 SC#6，本項強制標註要求已解除' }
    }
    if ($ClosingReportText -match [regex]::Escape($fixedString)) {
        return [pscustomobject]@{ Satisfied = $true; Detail = "結案報告含固定字串「$fixedString」" }
    }
    return [pscustomobject]@{ Satisfied = $false; Detail = "SC-DEC-ISO-001 尚未落檔（隔離未實測為預設狀態），但結案報告缺固定字串「$fixedString」——依 SC#6，gate fail" }
}

# ============================================================
# ⑥ 收尾摘要：各軸 findings 總數 ＋ 軸內 worst（若有）；🚫 不得出現跨軸單一贏家
# 獨立預期值來源：closingSummary.axisACount／axisBCount 由人造 fixture 自行填寫，非由本檔
# 動態計算後拿來跟自己比對——本函式只做「submission 內兩個各自獨立填寫的欄位是否一致」的核對。
# ============================================================
function Test-ClosingSummary {
    param([Parameter(Mandatory)]$ClosingSummary, [Parameter(Mandatory)][int]$ActualAxisACount, [Parameter(Mandatory)][int]$ActualAxisBCount)

    $gaps = @()

    $declaredA = if ($ClosingSummary.PSObject.Properties.Name -contains 'axisACount') { [int]$ClosingSummary.axisACount } else { -1 }
    $declaredB = if ($ClosingSummary.PSObject.Properties.Name -contains 'axisBCount') { [int]$ClosingSummary.axisBCount } else { -1 }
    if ($declaredA -ne $ActualAxisACount) { $gaps += "(a) 軸 A findings 總數不符：摘要宣稱 $declaredA，實際 $ActualAxisACount" }
    if ($declaredB -ne $ActualAxisBCount) { $gaps += "(a) 軸 B findings 總數不符：摘要宣稱 $declaredB，實際 $ActualAxisBCount" }

    $worstA = if ($ClosingSummary.PSObject.Properties.Name -contains 'axisAWorst') { $ClosingSummary.axisAWorst } else { '' }
    $worstB = if ($ClosingSummary.PSObject.Properties.Name -contains 'axisBWorst') { $ClosingSummary.axisBWorst } else { '' }
    if ($ActualAxisACount -gt 0 -and [string]::IsNullOrWhiteSpace($worstA)) { $gaps += '(b) 軸 A 有 findings 但摘要缺軸內 worst issue' }
    if ($ActualAxisBCount -gt 0 -and [string]::IsNullOrWhiteSpace($worstB)) { $gaps += '(b) 軸 B 有 findings 但摘要缺軸內 worst issue' }

    $text = if ($ClosingSummary.PSObject.Properties.Name -contains 'text') { $ClosingSummary.text } else { '' }
    $crossWinnerPatterns = @(
        '(?i)single\s*winner', '唯一贏家', '唯一最嚴重', '總體最嚴重', '全站最嚴重', '整體最嚴重',
        '(?i)overall\s*worst', '跨軸.*(最嚴重|winner)', '(?i)the\s*worst\s*issue\s*overall'
    )
    foreach ($p in $crossWinnerPatterns) {
        if ($text -match $p) {
            $gaps += "摘要文字命中禁止的跨軸單一贏家樣式（`"$p`"）——Pocock code-review 逐字：Don't pick a single winner across axes"
            break
        }
    }

    $gaps = @($gaps)
    $ok = ($gaps.Count -eq 0)
    $detail = if ($ok) { "收尾摘要合格：軸 A $ActualAxisACount 條（worst：$worstA），軸 B $ActualAxisBCount 條（worst：$worstB），未見跨軸單一贏家" } else { '缺項：' + ($gaps -join '｜') }
    return [pscustomobject]@{ Satisfied = $ok; Detail = $detail }
}

# ============================================================
# 整合：Invoke-Station5Check
# ============================================================
function Invoke-Station5Check {
    param([Parameter(Mandatory)]$Submission, [switch]$SkipRemediationCheck)

    $axisASep = Test-AxisInputSeparation -Axis 'AxisA' -InputList $Submission.axisA.inputList
    $axisBSep = Test-AxisInputSeparation -Axis 'AxisB' -InputList $Submission.axisB.inputList
    $standardsNamed = Test-AxisAStandardsNamed -AxisA $Submission.axisA
    $notMerged = Test-ReportsNotMerged -Submission $Submission
    $remediatedA = Test-FindingsRemediated -AxisLabel '軸 A' -Findings $Submission.axisA.findings
    $remediatedB = Test-FindingsRemediated -AxisLabel '軸 B' -Findings $Submission.axisB.findings
    $verifierChk = Test-Station5VerifierIndependent -Executor $Submission.executor -Verifier $Submission.verifier
    $remediationChk = Test-RemediationVerified -Remediation $Submission.remediation -SkipRemediationCheck:$SkipRemediationCheck
    $isolationChk = Test-IsolationDisclaimer -IsolationDecisionRecorded ([bool]$Submission.isolationDecisionRecorded) -ClosingReportText $Submission.closingReportText
    $summaryChk = Test-ClosingSummary -ClosingSummary $Submission.closingSummary -ActualAxisACount (@($Submission.axisA.findings).Count) -ActualAxisBCount (@($Submission.axisB.findings).Count)

    $namedGaps = @()
    if (-not $axisASep.Satisfied) { $namedGaps += "[①a 軸A輸入分離] $($axisASep.Detail)" }
    if (-not $axisBSep.Satisfied) { $namedGaps += "[①a 軸B輸入分離] $($axisBSep.Detail)" }
    if (-not $standardsNamed.Satisfied) { $namedGaps += "[①b 規範版本具名] $($standardsNamed.Detail)" }
    if (-not $notMerged.Satisfied) { $namedGaps += "[報告不合併] $($notMerged.Detail)" }
    if (-not $remediatedA.Satisfied) { $namedGaps += "[修法證據/裁決] $($remediatedA.Detail)" }
    if (-not $remediatedB.Satisfied) { $namedGaps += "[修法證據/裁決] $($remediatedB.Detail)" }
    if (-not $verifierChk.Satisfied) { $namedGaps += "[③ verifier獨立] $($verifierChk.Detail)" }
    if (-not $remediationChk.Satisfied) { $namedGaps += "[② 修復復驗] $($remediationChk.Detail)" }
    if (-not $isolationChk.Satisfied) { $namedGaps += "[⑤ SC#6隔離標註] $($isolationChk.Detail)" }
    if (-not $summaryChk.Satisfied) { $namedGaps += "[⑥ 收尾摘要] $($summaryChk.Detail)" }
    $namedGaps = @($namedGaps)

    $overallPass = $axisASep.Satisfied -and $axisBSep.Satisfied -and $standardsNamed.Satisfied -and $notMerged.Satisfied `
        -and $remediatedA.Satisfied -and $remediatedB.Satisfied -and $verifierChk.Satisfied -and $remediationChk.Satisfied `
        -and $isolationChk.Satisfied -and $summaryChk.Satisfied

    $detail = if ($overallPass) { '全過：可產生 close-issue 佇列項關票' } else { '未過，缺項：' + ($namedGaps -join '｜') }

    return [pscustomobject]@{
        OverallPass         = $overallPass
        AxisASeparation     = $axisASep
        AxisBSeparation     = $axisBSep
        StandardsNamed      = $standardsNamed
        ReportsNotMerged    = $notMerged
        RemediatedA         = $remediatedA
        RemediatedB         = $remediatedB
        VerifierCheck       = $verifierChk
        RemediationCheck    = $remediationChk
        IsolationCheck      = $isolationChk
        ClosingSummaryCheck = $summaryChk
        NamedGaps           = $namedGaps
        Detail              = $detail
    }
}

# ============================================================
# 關票：close-issue 佇列項（沿用 T-21 原五型之一，🚫 不新增動作型別，🚫 不直接呼叫寫入 API）
# ============================================================
function New-CloseTicketQueueItem {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][int]$IssueNumber, [Parameter(Mandatory)][string]$Source)
    return [pscustomobject]@{
        action  = 'close-issue'
        target  = [pscustomobject]@{ repo = $Repo; issue = $IssueNumber }
        payload = [pscustomobject]@{ state = 'closed'; state_reason = 'completed' }
        source  = $Source
    }
}

# 佇列項冪等追加（同 T-10／T-14 各自本地一份的既有模式，理由同前：產生權自查與去重邏輯屬各
# skill 自己的產生階段責任，不下放共用檔改動既有 T-21 交付）
function Add-QueueItemIfAbsent {
    param([Parameter(Mandatory)][string]$QueuePath, [Parameter(Mandatory)]$Item)
    $existing = Read-QueueFile -QueuePath $QueuePath
    if ($null -eq $existing) { $existing = @() }
    $existing = @($existing)
    $itemTargetJson = $Item.target | ConvertTo-Json -Compress
    $dupe = @($existing | Where-Object {
        $_.action -eq $Item.action -and $_.source -eq $Item.source -and
        (($_.target | ConvertTo-Json -Compress) -eq $itemTargetJson)
    })
    if ($dupe.Count -gt 0) {
        return [pscustomobject]@{ Added = $false; Detail = '佇列中已有相同動作待落地，未重複加入' }
    }
    $updated = @($existing) + @($Item)
    Write-QueueFile -QueuePath $QueuePath -Items $updated
    return [pscustomobject]@{ Added = $true; Detail = '已加入佇列' }
}

# ============================================================
# 驗收④後段：票被關閉、actor 為 bot（deferred-to-CI，比照 T-10／T-14 既有先例）
# ============================================================
function Test-TicketClosed {
    param([Parameter(Mandatory)]$Issue)
    $closed = ($Issue.state -eq 'closed')
    $detail = if ($closed) { "票現況 state='closed'" } else { "票現況 state='$($Issue.state)'（尚未關閉）" }
    return [pscustomobject]@{ Satisfied = $closed; Detail = $detail }
}

function Find-LastCloseEvent {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$TimelineEvents)
    $events = @($TimelineEvents)
    $closed = @($events | Where-Object { $_.event -eq 'closed' })
    if ($closed.Count -eq 0) {
        return [pscustomobject]@{ Found = $false; Actor = $null; CreatedAt = $null; Detail = 'timeline 中無 closed 事件' }
    }
    $last = $closed[$closed.Count - 1]
    $actor = if ($last.PSObject.Properties.Name -contains 'actor' -and $null -ne $last.actor) { $last.actor.login } else { $null }
    return [pscustomobject]@{ Found = $true; Actor = $actor; CreatedAt = $last.created_at; Detail = "最後一次 closed 事件：actor='$actor'，時間='$($last.created_at)'" }
}

function Test-CloseActorLegit {
    param([Parameter(Mandatory)]$Event, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$GateIdentityLogins)
    if (-not $Event.Found) {
        return [pscustomobject]@{ Blocking = $true; Satisfied = $false; Detail = $Event.Detail }
    }
    if (@($GateIdentityLogins).Count -eq 0) {
        return [pscustomobject]@{
            Blocking = $false; Satisfied = $null
            Detail   = "手動階段：無機器歸因判準，依 ADR-NP-009 降為規範層＋人工複查，不算入 AND；deferred-to-CI（提供 -GateIdentityLogins 後生效，比照 ../t10/gate-reset.md 先例）。具名回報 actor='$($Event.Actor)'"
        }
    }
    $legal = $GateIdentityLogins -contains $Event.Actor
    return [pscustomobject]@{ Blocking = $true; Satisfied = $legal; Detail = "CI 階段：actor='$($Event.Actor)'，gate 身分集合=[$($GateIdentityLogins -join ', ')]，legal=$legal" }
}

# ============================================================
# CLI：Check 模式
# ============================================================
function Invoke-Station5CheckCli {
    $submission = Read-Station5Submission -Path $SubmissionPath
    $result = Invoke-Station5Check -Submission $submission -SkipRemediationCheck:$SkipRemediationCheck

    $lines = @("station5-check 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "Ticket=$($submission.ticket)  Target=$Repo#$Issue", "")
    $lines += "①a 軸A輸入分離：$($result.AxisASeparation.Detail)"
    $lines += "①a 軸B輸入分離：$($result.AxisBSeparation.Detail)"
    $lines += "①b 規範版本具名：$($result.StandardsNamed.Detail)"
    $lines += "報告不合併：$($result.ReportsNotMerged.Detail)"
    $lines += "軸A修法/裁決：$($result.RemediatedA.Detail)"
    $lines += "軸B修法/裁決：$($result.RemediatedB.Detail)"
    $lines += "③ verifier獨立：$($result.VerifierCheck.Detail)"
    $lines += "② 修復復驗：$($result.RemediationCheck.Detail)"
    $lines += "⑤ SC#6隔離標註：$($result.IsolationCheck.Detail)"
    $lines += "⑥ 收尾摘要：$($result.ClosingSummaryCheck.Detail)"
    $lines += ""
    $lines += "整體判定：$(if ($result.OverallPass) { 'PASS' } else { 'FAIL' })"
    if (-not $result.OverallPass) { $lines += "缺項：" + ($result.NamedGaps -join '｜') }

    if (-not $result.OverallPass) {
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T15aCheckDir 'station5-check-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 1
    }

    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t15a-station5-check'
    $r = Split-RepoString -RepoString $Repo
    $issue = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $Issue -Headers $Headers
    if ($null -eq $issue) { throw "找不到目標票：$Repo#$Issue" }

    $srcVal = if ($Source) { $Source } else { $submission.ticket }
    $item = New-CloseTicketQueueItem -Repo $Repo -IssueNumber $Issue -Source $srcVal
    $addResult = Add-QueueItemIfAbsent -QueuePath $QueuePath -Item $item

    $lines += "已產生單一次 close-issue 佇列項（$($addResult.Detail)）：state=closed, state_reason=completed"
    $lines += "=> 請執行 ..\t21\apply-queue.ps1 -QueuePath `"$QueuePath`" 落地（🚫 本檔不直接呼叫 GitHub 寫入 API，重用 T-21 既有的 close-issue 落地邏輯）。"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T15aCheckDir 'station5-check-report.txt') -Content ($lines -join [Environment]::NewLine)
    exit 0
}

# ============================================================
# CLI：Verify 模式（deferred-to-CI，actor=bot 僅具名回報；本沙盒無法連真實 GitHub 實跑）
# ============================================================
function Invoke-Station5VerifyCli {
    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t15a-station5-verify'
    $r = Split-RepoString -RepoString $VerifyRepoArg
    $issue = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $VerifyIssueArg -Headers $Headers
    if ($null -eq $issue) { throw "找不到目標票：$VerifyRepoArg#$VerifyIssueArg" }

    $closedChk = Test-TicketClosed -Issue $issue
    $timeline = Get-IssueTimelineEvents -Owner $r.Owner -Repo $r.Repo -IssueNumber $VerifyIssueArg -Headers $Headers
    $ev = Find-LastCloseEvent -TimelineEvents $timeline
    $actorChk = Test-CloseActorLegit -Event $ev -GateIdentityLogins $GateIdentityLogins

    $lines = @("station5-verify 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "Target=$VerifyRepoArg#$VerifyIssueArg", "")
    $lines += "票已關閉：$(if ($closedChk.Satisfied) { 'PASS' } else { 'FAIL' }) — $($closedChk.Detail)"
    $lines += "actor 合法性（deferred-to-CI，比照 ADR-NP-009）：$($actorChk.Detail)"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T15aCheckDir 'station5-verify-report.txt') -Content ($lines -join [Environment]::NewLine)

    $overallOk = $closedChk.Satisfied -and ((-not $actorChk.Blocking) -or $actorChk.Satisfied)
    if ($overallOk) { exit 0 } else { exit 1 }
}

if (-not $T15aRequestedFunctionsOnly) {
    if ($PSCmdlet.ParameterSetName -eq 'Verify') { Invoke-Station5VerifyCli } else { Invoke-Station5CheckCli }
}
