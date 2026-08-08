#requires -Version 5.1
<#
.SYNOPSIS
    T-14：站 4 交件檢查器——紅燈型態（斷言失敗，非載入失敗）＋ 預期值出處（非自證）＋
    verifier≠executor 三項查核；全過才產生單一次 set-labels 佇列項落 sc:red-proven（僅票）。

.DESCRIPTION
    依 Spec_station-command_v1.11.md §6 站4、§3.5 註 A／註 C、§3.3、§2 gate 白名單實作。
    重用地基（不重寫，DRY）：dot-source ../t10/gate-reset.ps1 -FunctionsOnly，其內部 cascade
    dot-source ../t10/gate-check.ps1 -FunctionsOnly → ../t21/queue-common.ps1，一次取得
    Read-PatToken／Get-GithubHeaders／Split-RepoString／Get-CurrentIssue／ConvertTo-SafeArray／
    Write-Utf8BomFile／Set-ConsoleUtf8／Read-QueueFile／Write-QueueFile（皆來自 t21）與
    Get-TicketsForWork（t10）／Get-IssueTimelineEvents（t10 gate-reset）。本檔**不修改**
    build/t10／build/t21 任何檔案（file ownership 邊界）。

    本票判讀對象是**人造交件所附的測試輸出原文（靜態文本）**，🚫 不執行被測系統——所有查核皆為
    對交件 JSON 內字串欄位的正則／結構比對，不 import、不 eval、不呼叫任何被測程式碼。

    佇列動作型別沿用 T-21 原五型之一 `set-labels`（queue-format.md §3.1），**不引入新動作型別**
    ——`sc:red-proven` 只是加到票的既有 label 集合，寫入端點與冪等比對邏輯與站別推進完全相同，
    無需比照 T-12／T-22 另立套用腳本；仍與 T-10 共用同一份 `../t21/apply-queue.ps1` 落地。

    §2「gate 產生 set-labels 型佇列項寫 sc:red-proven，🚫 不得直接呼叫 GitHub 寫入 API」——
    本檔的 Check 模式只**產生**佇列項，Verify 模式只**讀**（GET issue／timeline），全程無任何
    PUT／PATCH／POST 呼叫。

    三項查核（對應驗收①③④，同源不同落點，見 Spec §3.5 註 C 與 §6 註 A）：
      ① Test-RedLightIsAssertionFailure：紅燈輸出文字須含斷言失敗特徵（AssertionError 等），
         命中載入／collection 失敗特徵（ImportError／ModuleNotFoundError 等）⇒ 立即拒絕具名。
      ③ Test-VerifierIndependent：verifier 欄位須≠ executor 欄位（大小寫／前後空白正規化後比對）。
      ④ Test-AssertionExpectedIndependent（逐條斷言）：
         - 結構性偵測：若斷言文字同時含 `expected = <呼叫式>` 與 `actual/result = <相同呼叫式>`
           （去空白後逐字相同，且該運算式外觀像函式／cmdlet 呼叫），判定為自證式斷言（tautological，
           Pocock tdd 原文 Anti-patterns），具名拒絕。
         - 未偵測到上述結構時，退回檢查 `expectedSourceNote`：為空 ⇒ fail-closed 拒絕；非空但未
           提及三種獨立真相源關鍵詞（known-good literal／worked example／spec 等）⇒ 拒絕；皆滿足
           ⇒ 通過。
      -SkipProvenanceCheck：⚠️⚠️⚠️ 僅供紅燈驗證使用，正式流程與一般手動執行絕對不得使用——開啟後
         ④ 的查核整段略過、一律視為通過，用於讓 t14-offline-test.ps1 對「自證式斷言必須被拒絕」
         這條斷言在該次執行下真的失敗一次（斷言失敗型紅燈存證），詳見 README。

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
    [switch]$SkipProvenanceCheck,

    [Parameter(ParameterSetName = 'Verify', Mandatory)]
    [switch]$VerifyRedProven,

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
# ⚠️ 用 $T14Dir 而非 $ScriptDir——理由同 T-12 README 記載的實跑 bug：dot-source
# ../t10/gate-reset.ps1 會 cascade 進 ../t10/gate-check.ps1，該檔宣告未加 Script: 範圍的
# $ScriptDir 並指向 t10 自己的目錄；dot-source 全程共用同一層作用域，後執行的賦值會覆蓋前面
# 的同名變數。改用本檔獨有變數名，避免報告檔被悄悄寫進 build/t10/。
$T14Dir = $PSScriptRoot
$GateResetPath = Join-Path $T14Dir '..\t10\gate-reset.ps1'
if (-not (Test-Path -LiteralPath $GateResetPath)) {
    throw ("找不到 T-10 地基：{0}。請確認 t14 與 t10 為同層兄弟目錄。" -f $GateResetPath)
}
. $GateResetPath -FunctionsOnly
Set-ConsoleUtf8

# ============================================================
# 讀交件（人造交件所附的測試輸出原文，靜態 JSON；不執行任何被測程式碼）
# ============================================================
function Read-Station4Submission {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "交件檔不存在：$Path" }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $obj = $raw | ConvertFrom-Json
    $required = @('ticket', 'executor', 'verifier', 'redOutput', 'greenOutput', 'assertions')
    $missing = @($required | Where-Object { -not ($obj.PSObject.Properties.Name -contains $_) })
    if (@($missing).Count -gt 0) {
        throw "交件缺必填欄位：$($missing -join '、')（schema：ticket/executor/verifier/redOutput/greenOutput/assertions[]，見 fixtures/README.md）"
    }
    $assertions = @($obj.assertions)
    if ($assertions.Count -eq 0) {
        throw "交件 assertions 陣列為空，至少須有一條斷言可供查核（④ 逐條查預期值出處）"
    }
    foreach ($a in $assertions) {
        if (-not ($a.PSObject.Properties.Name -contains 'id') -or -not ($a.PSObject.Properties.Name -contains 'text')) {
            throw "assertions 陣列內有項目缺 id 或 text 欄位"
        }
    }
    return $obj
}

# ============================================================
# ① 紅燈型態：斷言失敗 vs 載入／collection 失敗（來源標註見 Spec §6 註 A：本地增設，依使用者 S3）
# ============================================================
function Test-RedLightIsAssertionFailure {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$RedOutputText)

    # 載入／collection 失敗特徵須先查（優先權高於斷言失敗特徵，符合 §6 註 A「連斷言都沒跑到」定義）
    $loadFailurePatterns = @(
        'ModuleNotFoundError', 'ImportError', 'SyntaxError', 'ERROR collecting', 'error while loading',
        'CommandNotFoundException', 'is not recognized as the (name of a cmdlet|term)', 'ParserError',
        'cannot be loaded because', 'Fatal error', '(?m)^fatal:', 'Cannot find module', 'collection error',
        'INTERNALERROR', 'Interrupted: \d+ error during collection'
    )
    foreach ($p in $loadFailurePatterns) {
        if ($RedOutputText -match $p) {
            return [pscustomobject]@{
                Satisfied = $false
                Kind      = 'load-failure'
                Detail    = "紅燈輸出命中載入／collection 失敗特徵（樣式：`"$p`"），非斷言失敗——依 Spec §6／註A：紅須為斷言失敗的紅（依據＝使用者 S3 原話『Always design Red light to prevent Ai cheating』，非 Pocock 原文），連斷言都沒跑到就宣稱紅過，正是要防的作弊型態"
            }
        }
    }

    $assertionPatterns = @(
        'AssertionError', 'assert(ion)?\s*failed', 'Expected .* (but|to) ', 'Should[- ]?Be',
        'expect\(.*\)\.to', 'FAILED.*(assert|Assert)', 'AssertFailedException', '斷言失敗', '不相等',
        '(?m)^\s*Expected:\s', '(?m)^\s*But was:\s'
    )
    foreach ($p in $assertionPatterns) {
        if ($RedOutputText -match $p) {
            return [pscustomobject]@{
                Satisfied = $true
                Kind      = 'assertion-failure'
                Detail    = "紅燈輸出命中斷言失敗特徵（樣式：`"$p`"），符合 Spec §6 站4紅燈型態要求"
            }
        }
    }

    return [pscustomobject]@{
        Satisfied = $false
        Kind      = 'unknown'
        Detail    = '紅燈輸出未命中任何已知斷言失敗特徵，亦未命中已知載入失敗特徵；無法確認為斷言失敗的紅，fail-closed 拒絕'
    }
}

# ============================================================
# ③ verifier ≠ executor（執行者自陳不能當驗收，Spec §5.2／§6 站4）
# ============================================================
function Test-VerifierIndependent {
    param([Parameter(Mandatory)][string]$Executor, [Parameter(Mandatory)][AllowEmptyString()][string]$Verifier)
    $execN = $Executor.Trim().ToLowerInvariant()
    $verN = $Verifier.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($verN)) {
        return [pscustomobject]@{ Satisfied = $false; Detail = 'verifier 欄位為空，無法確認 verifier≠executor（fail-closed）' }
    }
    $ok = ($execN -ne $verN)
    $detail = if ($ok) {
        "verifier（'$Verifier'）≠ executor（'$Executor'）"
    } else {
        "verifier 與 executor 相同（'$Executor'），違反 verifier≠executor 硬規則（Spec §5.2／§6 站4）——執行者自陳不能當驗收"
    }
    return [pscustomobject]@{ Satisfied = $ok; Detail = $detail }
}

# ============================================================
# ④ 預期值出處：非由被測程式自身產生（Spec §3.5 註 C，逐字依據 Pocock tdd Anti-patterns · Tautological）
# ============================================================
function Test-AssertionExpectedIndependent {
    param(
        [Parameter(Mandatory)][string]$AssertionText,
        [AllowEmptyString()][string]$Note = '',
        [switch]$SkipProvenanceCheck
    )

    if ($SkipProvenanceCheck) {
        return [pscustomobject]@{
            Satisfied = $true
            Self      = $false
            Detail    = '⚠️⚠️⚠️ -SkipProvenanceCheck 已開啟：略過預期值出處查核，一律視為獨立來源（僅供紅燈驗證使用，正式流程與一般手動執行絕對不得使用，見 README）'
        }
    }

    # 結構性偵測：expected 與 actual/result 兩行賦值運算式完全相同，且外觀像函式／cmdlet 呼叫
    # （而非字面值）⇒ 疑似「呼叫被測函式兩次、拿其中一次回傳值當預期值」的自證式斷言。
    $expM = [regex]::Match($AssertionText, '(?im)\bexpected\w*\s*=\s*(.+?)\s*$')
    $actM = [regex]::Match($AssertionText, '(?im)\b(actual|result)\w*\s*=\s*(.+?)\s*$')
    if ($expM.Success -and $actM.Success) {
        $expRhsRaw = $expM.Groups[1].Value.Trim()
        $actRhsRaw = $actM.Groups[2].Value.Trim()
        $expNorm = ($expRhsRaw -replace '\s+', '').ToLowerInvariant()
        $actNorm = ($actRhsRaw -replace '\s+', '').ToLowerInvariant()
        $looksLikeCall = $expRhsRaw -match '^[A-Za-z_][A-Za-z0-9_\-\.]*[\s\(]'
        if ($expNorm -eq $actNorm -and $looksLikeCall) {
            return [pscustomobject]@{
                Satisfied = $false
                Self      = $true
                Detail    = "expected（`"$expRhsRaw`"）與 actual/result（`"$actRhsRaw`"）的運算式完全相同，疑似直接呼叫被測函式（或其等價運算）的回傳值當作預期值——即 Pocock `tdd` 原文 Anti-patterns · Tautological 所指的自證式斷言（Spec §3.5 註 C：預期值不得由被測程式自身產生）"
            }
        }
    }

    # 未偵測到結構性自證 ⇒ 退回檢查獨立來源標記：缺 ⇒ fail-closed；有但未指明三種來源之一 ⇒ 拒絕。
    if ([string]::IsNullOrWhiteSpace($Note)) {
        return [pscustomobject]@{
            Satisfied = $false
            Self      = $false
            Detail    = '斷言缺獨立預期值來源標記（expectedSourceNote 為空），依 Spec §3.5 註 C fail-closed：不得默認為獨立真相源'
        }
    }
    if ($Note -notmatch '(?i)spec|規格|literal|字面值|known-good|worked example|範例|已知正確|條文') {
        return [pscustomobject]@{
            Satisfied = $false
            Self      = $false
            Detail    = "來源標記未指明三種獨立真相源之一（known-good literal／worked example／spec）：`"$Note`""
        }
    }
    return [pscustomobject]@{ Satisfied = $true; Self = $false; Detail = "獨立預期值來源：$Note" }
}

# ============================================================
# 整合：Invoke-Station4Check（三項查核合一，全過才可落 sc:red-proven）
# ============================================================
function Invoke-Station4Check {
    param([Parameter(Mandatory)]$Submission, [switch]$SkipProvenanceCheck)

    $redChk = Test-RedLightIsAssertionFailure -RedOutputText $Submission.redOutput
    $verChk = Test-VerifierIndependent -Executor $Submission.executor -Verifier $Submission.verifier

    $assertions = @($Submission.assertions)
    $provItems = @()
    foreach ($a in $assertions) {
        $note = if ($a.PSObject.Properties.Name -contains 'expectedSourceNote' -and $null -ne $a.expectedSourceNote) { $a.expectedSourceNote } else { '' }
        $r = Test-AssertionExpectedIndependent -AssertionText $a.text -Note $note -SkipProvenanceCheck:$SkipProvenanceCheck
        $provItems += [pscustomobject]@{ Id = $a.id; Satisfied = $r.Satisfied; Self = $r.Self; Detail = $r.Detail }
    }
    $provItems = @($provItems)
    $provFailed = @($provItems | Where-Object { -not $_.Satisfied })

    $namedGaps = @()
    if (-not $redChk.Satisfied) { $namedGaps += "[① 紅燈型態] $($redChk.Detail)" }
    if (-not $verChk.Satisfied) { $namedGaps += "[③ verifier≠executor] $($verChk.Detail)" }
    foreach ($pf in $provFailed) { $namedGaps += "[④ 預期值出處，斷言 $($pf.Id)] $($pf.Detail)" }
    $namedGaps = @($namedGaps)

    $overallPass = $redChk.Satisfied -and $verChk.Satisfied -and (@($provFailed).Count -eq 0)

    $detail = if ($overallPass) {
        "全過：紅燈為斷言失敗型、verifier≠executor、全部 $($assertions.Count) 條斷言預期值皆來自獨立真相源 ⇒ 可落 sc:red-proven"
    } else {
        "未過，缺項：" + ($namedGaps -join '｜')
    }

    return [pscustomobject]@{
        OverallPass     = $overallPass
        RedLightCheck   = $redChk
        VerifierCheck   = $verChk
        ProvenanceItems = $provItems
        NamedGaps       = $namedGaps
        Detail          = $detail
    }
}

# ============================================================
# 落標：sc:red-proven 只加不減（單一次完整 label 集合，比照 §3.4 原子性精神，重用 t21 set-labels 型別）
# ============================================================
function New-RedProvenLabelSet {
    param([Parameter(Mandatory)]$Issue)
    $labelsRaw = ConvertTo-SafeArray -RawValue $Issue.labels
    $labelsRaw = @($labelsRaw)
    $existingNames = @($labelsRaw | ForEach-Object { $_.name })
    if ($existingNames -contains 'sc:red-proven') {
        return ,@($existingNames | Select-Object -Unique)
    }
    return ,@(@($existingNames) + @('sc:red-proven') | Select-Object -Unique)
}

function New-RedProvenQueueItem {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][int]$IssueNumber, [Parameter(Mandatory)][array]$DesiredLabels, [Parameter(Mandatory)][string]$Source)
    return [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $Repo; issue = $IssueNumber }
        payload = [pscustomobject]@{ labels = @($DesiredLabels) }
        source  = $Source
    }
}

# 佇列項冪等追加（同 T-08／T-10 各自本地一份的既有模式，理由同 T-10 README：產生權自查與去重
# 邏輯屬各 skill 自己的產生階段責任，不下放共用檔改動既有 T-21 交付）
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
# 驗收②後段：actor 為 bot（deferred-to-CI，比照 T-10 gate-reset／gate-check 既有先例）
# ============================================================
function Test-RedProvenLabelPresent {
    param([Parameter(Mandatory)]$Issue)
    $labelsRaw = ConvertTo-SafeArray -RawValue $Issue.labels
    $labelsRaw = @($labelsRaw)
    $names = @($labelsRaw | ForEach-Object { $_.name })
    $present = ($names -contains 'sc:red-proven')
    $detail = if ($present) { "票上已出現 sc:red-proven（現有 label 集合：[$($names -join ', ')]）" } else { "票上尚無 sc:red-proven（現有 label 集合：[$($names -join ', ')]）" }
    return [pscustomobject]@{ Satisfied = $present; Detail = $detail }
}

function Find-LastRedProvenLabelEvent {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$TimelineEvents)
    $events = @($TimelineEvents)
    $labeled = @($events | Where-Object {
        $_.event -eq 'labeled' -and $_.PSObject.Properties.Name -contains 'label' -and $null -ne $_.label -and $_.label.name -eq 'sc:red-proven'
    })
    if ($labeled.Count -eq 0) {
        return [pscustomobject]@{ Found = $false; Actor = $null; CreatedAt = $null; Detail = 'timeline 中無 sc:red-proven 的 labeled 事件' }
    }
    $last = $labeled[$labeled.Count - 1]
    $actor = if ($last.PSObject.Properties.Name -contains 'actor' -and $null -ne $last.actor) { $last.actor.login } else { $null }
    return [pscustomobject]@{ Found = $true; Actor = $actor; CreatedAt = $last.created_at; Detail = "最後一次 sc:red-proven labeled 事件：actor='$actor'，時間='$($last.created_at)'" }
}

function Test-RedProvenActorLegit {
    param([Parameter(Mandatory)]$Event, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$GateIdentityLogins)
    if (-not $Event.Found) {
        return [pscustomobject]@{ Blocking = $true; Satisfied = $false; Detail = $Event.Detail }
    }
    if (@($GateIdentityLogins).Count -eq 0) {
        return [pscustomobject]@{
            Blocking = $false; Satisfied = $null
            Detail   = "手動階段：無機器歸因判準，依 ADR-NP-009 降為規範層＋人工複查，不算入 AND；deferred-to-CI（提供 -GateIdentityLogins 後生效，見 ../t10/gate-reset.md 同型先例）。具名回報 actor='$($Event.Actor)'"
        }
    }
    $legal = $GateIdentityLogins -contains $Event.Actor
    return [pscustomobject]@{ Blocking = $true; Satisfied = $legal; Detail = "CI 階段：actor='$($Event.Actor)'，gate 身分集合=[$($GateIdentityLogins -join ', ')]，legal=$legal" }
}

# ============================================================
# CLI：Check 模式（讀交件 → 三項查核 → 全過才產生 set-labels 佇列項）
# ============================================================
function Invoke-Station4CheckCli {
    $submission = Read-Station4Submission -Path $SubmissionPath
    $result = Invoke-Station4Check -Submission $submission -SkipProvenanceCheck:$SkipProvenanceCheck

    $lines = @("station4-check 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "Ticket=$($submission.ticket)  Target=$Repo#$Issue", "")
    $lines += "① 紅燈型態：$($result.RedLightCheck.Kind)（$($result.RedLightCheck.Detail)）"
    $lines += "③ verifier≠executor：$($result.VerifierCheck.Detail)"
    foreach ($p in @($result.ProvenanceItems)) { $lines += "④ 斷言 $($p.Id) 預期值出處：$($p.Detail)" }
    $lines += ""
    $lines += "整體判定：$(if ($result.OverallPass) { 'PASS' } else { 'FAIL' })"
    if (-not $result.OverallPass) { $lines += "缺項：" + ($result.NamedGaps -join '｜') }

    if (-not $result.OverallPass) {
        $lines | ForEach-Object { Write-Host $_ }
        Write-Utf8BomFile -Path (Join-Path $T14Dir 'station4-check-report.txt') -Content ($lines -join [Environment]::NewLine)
        exit 1
    }

    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t14-station4-check'
    $r = Split-RepoString -RepoString $Repo
    $issue = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $Issue -Headers $Headers
    if ($null -eq $issue) { throw "找不到目標票：$Repo#$Issue" }

    $desired = New-RedProvenLabelSet -Issue $issue
    $srcVal = if ($Source) { $Source } else { $submission.ticket }
    $item = New-RedProvenQueueItem -Repo $Repo -IssueNumber $Issue -DesiredLabels $desired -Source $srcVal
    $addResult = Add-QueueItemIfAbsent -QueuePath $QueuePath -Item $item

    $lines += "已產生單一次「設定完整 label 集合」佇列項（$($addResult.Detail)）：labels=[$($desired -join ', ')]"
    $lines += "=> 請執行 ..\t21\apply-queue.ps1 -QueuePath `"$QueuePath`" 落地（🚫 本檔不直接呼叫 GitHub 寫入 API，重用 T-21 既有的 set-labels 落地邏輯）。"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T14Dir 'station4-check-report.txt') -Content ($lines -join [Environment]::NewLine)
    exit 0
}

# ============================================================
# CLI：Verify 模式（deferred-to-CI，actor=bot 僅具名回報；本沙盒無法連真實 GitHub 實跑）
# ============================================================
function Invoke-Station4VerifyCli {
    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t14-station4-verify'
    $r = Split-RepoString -RepoString $VerifyRepoArg
    $issue = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $VerifyIssueArg -Headers $Headers
    if ($null -eq $issue) { throw "找不到目標票：$VerifyRepoArg#$VerifyIssueArg" }

    $presentChk = Test-RedProvenLabelPresent -Issue $issue
    $timeline = Get-IssueTimelineEvents -Owner $r.Owner -Repo $r.Repo -IssueNumber $VerifyIssueArg -Headers $Headers
    $ev = Find-LastRedProvenLabelEvent -TimelineEvents $timeline
    $actorChk = Test-RedProvenActorLegit -Event $ev -GateIdentityLogins $GateIdentityLogins

    $lines = @("station4-verify 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "Target=$VerifyRepoArg#$VerifyIssueArg", "")
    $lines += "sc:red-proven 存在性：$(if ($presentChk.Satisfied) { 'PASS' } else { 'FAIL' }) — $($presentChk.Detail)"
    $lines += "actor 合法性（deferred-to-CI，比照 ADR-NP-009）：$($actorChk.Detail)"
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $T14Dir 'station4-verify-report.txt') -Content ($lines -join [Environment]::NewLine)

    $overallOk = $presentChk.Satisfied -and ((-not $actorChk.Blocking) -or $actorChk.Satisfied)
    if ($overallOk) { exit 0 } else { exit 1 }
}

if (-not $FunctionsOnly) {
    if ($PSCmdlet.ParameterSetName -eq 'Verify') { Invoke-Station4VerifyCli } else { Invoke-Station4CheckCli }
}
