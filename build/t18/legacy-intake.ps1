#requires -Version 5.1
<#
.SYNOPSIS
    T-18：legacy 收編——`/station-intake` legacy 模式（共用 native 建立步驟）＋定站上限站 3
    （auditor 消化＋cap）＋ `sc:legacy` 掛上。badge 摘除邏輯見同目錄 `gate-legacy-advance.ps1`。

.DESCRIPTION
    地基重用（依票面「複用、不要重寫」，直接 dot-source，不重寫）：
      ① dot-source ../t13/gate-station3.ps1 -FunctionsOnly：cascade 連帶取得
         ../t12/run-common.ps1 → ../t10/gate-check.ps1 -FunctionsOnly → ../t21/queue-common.ps1
         全部工具函式，包含 Get-StationChecklistDefinition（§6 checklist 正典，站1-3）、
         Get-CurrentStation、Test-Station3TicketSetDeep（重用做§7.3路徑①判定）、
         Read-PatToken／Get-GithubHeaders／Read-QueueFile／Write-QueueFile／Split-RepoString／
         Get-CurrentIssue／ConvertTo-SafeArray／Set-ConsoleUtf8／Write-Utf8BomFile 等。
      ② dot-source ../t08/intake-native.ps1 -FunctionsOnly：取得 Find-AnchorByWorkId／
         Find-MilestoneByTitle／Get-AnchorDeclaration／Test-MilestoneDescriptionFormat／
         Test-GateInitCriteria／Add-QueueItemIfAbsent，供 Stage A/B/C 共用（§7.1「native 與
         legacy 共用同一套建立步驟」的程式碼層體現，理由與「為何不直接呼叫
         Invoke-IntakeNativeFlow 整個函式」見 ../station-intake-legacy.md）。
    本檔**不修改** t08／t10／t12／t13／t21 任何檔案（file ownership 邊界）。

    ⚠️ **變數 cascade 陷阱**（票面明列 T-12/T-13/T-15a/T-24 皆踩過）：上述兩次 dot-source 皆會
    綁定各自的 param 區塊變數（②尤其危險——t08 的 WorkId/PrimaryRepo/ParticipatingRepos 為
    Mandatory，dot-source 時必須傳入佔位值才能過參數繫結，繫結後會覆蓋本檔同名變數）。
    因此本檔在 param 區塊解析完成、**任何 dot-source 之前**，立刻把自己收到的每個參數另存為
    `$T18*` 獨有變數名；此後全程只讀寫 `$T18*`，不再信任裸 `$WorkId`／`$PrimaryRepo`／
    `$ParticipatingRepos`／`$PatPath`／`$QueuePath`／`$ScriptDir` 等常見名稱（那些名稱在
    dot-source 之後可能已被 t08／t10／t13 的同名參數或內部變數覆蓋，見 t13 README「開發過程中
    實際抓到的 bug」記載的同型事故）。CLI smoke test 見 t18-offline-test.ps1「CLI smoke test」
    段落與 README「⑥ CLI smoke test 結果」。

    本檔淨新增邏輯（T-18 實際交付）：
      - Get-AuditorCandidateStation：讀 auditor findings，依 §6 同一份 checklist（重用 t10
        Get-StationChecklistDefinition 站1-3定義，不另立第二份）從站1往上走，第一個未滿足即
        候選站別；站1-3全過⇒候選=4（不細分站4/5子項，理由見 auditor-prompt.md）。
      - Test-LegacyStationCap：legacy 定站上限站3（§7.3）——候選>3 且未收編完成 ⇒ 封頂3；
        -BypassCapForRedTest 僅供紅燈驗證。
      - Test-LegacyRemediationComplete：§7.3 兩條路徑——①重用 T-13 Test-Station3TicketSetDeep
        判定native票集是否通過§3.5八欄位深度檢查；②掃 DECISIONS.md 是否具名「不收編、僅供查閱」。
      - Test-LegacyTicketProtectionGuard／Add-Station18QueueItemIfAbsent：🔴「不改寫舊票」的
        程式碼層守門——任何 target 指向舊票保護清單內 issue 的佇列項一律拒絕產生，不是只有文件
        宣告（見 README「不改寫舊票的程式碼層守門」節）。
      - Test-AuditorFindingsWellFormed：auditor 報告品質守門——✗項必須有非空證據與合法缺件分類，
        不合格即 fail-closed 拒絕進入 Stage C 判定。
      - Format-AuditorReport：逐條 ✓／✗／N/A ＋證據＋缺件分類的人讀報告。
      - Invoke-LegacyIntakeFlow：Stage A（anchor）／B（milestones，重用 t08 函式）／C（legacy
        定站封頂＋sc:legacy，重用 t08 Test-GateInitCriteria 判準①②③④⑤）。

.PARAMETER BypassCapForRedTest
    ⚠️ 僅供紅燈驗證使用（t18-offline-test.ps1 的 RED 段落）。開啟後 Test-LegacyStationCap
    不套用站3上限，候選站別原樣輸出。正式流程與一般手動執行絕對不得開啟。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程（供 t18-offline-test.ps1 dot-source 呼叫內部函式）。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkId,
    [Parameter(Mandatory)][string]$PrimaryRepo,
    [Parameter(Mandatory)][string[]]$ParticipatingRepos,
    [string]$WorkDescription = '',
    [string[]]$FleetRepos = @(),
    [string]$AuditorFindingsPath = '',
    [string]$DecisionsMdPath = '',
    [string]$RemediatedTicketsDir = '',
    [string]$ProtectedLegacyTicketsPath = '',
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [switch]$BypassCapForRedTest,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'

# ============================================================
# 🔴 立刻另存 $T18* 獨有變數名（dot-source 前），全程只用這組，不用裸參數名。
# ============================================================
$T18Dir                       = $PSScriptRoot
$T18WorkId                    = $WorkId
$T18PrimaryRepo               = $PrimaryRepo
$T18ParticipatingRepos        = @($ParticipatingRepos)
$T18WorkDescription           = $WorkDescription
$T18FleetRepos                = @($FleetRepos)
$T18AuditorFindingsPath       = $AuditorFindingsPath
$T18DecisionsMdPath           = $DecisionsMdPath
$T18RemediatedTicketsDir      = $RemediatedTicketsDir
$T18ProtectedLegacyTicketsPath = $ProtectedLegacyTicketsPath
$T18PatPath                   = $PatPath
$T18QueuePath                 = $QueuePath
$T18BypassCapForRedTest       = [bool]$BypassCapForRedTest
$T18FunctionsOnlyFlag         = [bool]$FunctionsOnly

Write-Host "[T18-SMOKE] 已收參數（dot-source 前存證，證明非 no-op）：WorkId='$T18WorkId' PrimaryRepo='$T18PrimaryRepo' ParticipatingRepos=[$($T18ParticipatingRepos -join ', ')]"

# ============================================================
# 地基 dot-source（順序：先 t13 鏈，後 t08——t08 有 Mandatory 參數，用佔位值繫結）
# ============================================================
$T18GateStation3Path = Join-Path $T18Dir '..\t13\gate-station3.ps1'
if (-not (Test-Path -LiteralPath $T18GateStation3Path)) {
    throw ("找不到 T-13 地基：{0}。請確認 t18 與 t13 為同層兄弟目錄。" -f $T18GateStation3Path)
}
. $T18GateStation3Path -FunctionsOnly

$T18IntakeNativePath = Join-Path $T18Dir '..\t08\intake-native.ps1'
if (-not (Test-Path -LiteralPath $T18IntakeNativePath)) {
    throw ("找不到 T-08 地基：{0}。請確認 t18 與 t08 為同層兄弟目錄。" -f $T18IntakeNativePath)
}
. $T18IntakeNativePath -WorkId 'W-t18-dotsource-placeholder' -PrimaryRepo 'placeholder/placeholder' -ParticipatingRepos 'placeholder/placeholder' -FunctionsOnly

Set-ConsoleUtf8
Write-Host "[T18-SMOKE] dot-source 完成後 `$T18WorkId 仍為 '$T18WorkId'（未被 t08 佔位值 'W-t18-dotsource-placeholder' 覆蓋——證明 `$T18* 命名隔離有效）"

# ============================================================
# §6 checklist 站別讀取／JSON 讀取小工具
# ============================================================
function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$WhatFor)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "找不到 $WhatFor 檔案：$Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

function Get-AuditorFindingsFromFile {
    param([Parameter(Mandatory)][string]$Path)
    $parsed = Read-JsonFile -Path $Path -WhatFor 'auditor findings'
    $findings = ConvertTo-SafeArray -RawValue $parsed.Findings
    $suggested = if ($parsed.PSObject.Properties.Name -contains 'AuditorSuggestedRetreatStation') { $parsed.AuditorSuggestedRetreatStation } else { $null }
    # ⚠️ 陷阱②：這裡是「pscustomobject 屬性值賦值」，不是跨函式邊界的 return 陣列本身，
    # 前導逗號在此情境下會多包一層（把 8 筆錯包成「1 筆，內容是 8 筆的陣列」），故用 @(...)
    # 不加前導逗號（與 return ,@(...) 的用法區分，見同目錄各函式對照）。
    return [pscustomobject]@{ Findings = @($findings); AuditorSuggestedRetreatStation = $suggested }
}

function Get-ProtectedLegacyTicketsFromFile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return ,@() }
    $parsed = Read-JsonFile -Path $Path -WhatFor 'protected legacy tickets'
    # ⚠️ 陷阱③：不可直接 @(ConvertTo-SafeArray ...)（對已用逗號保護過的函式呼叫回傳值再包一層，
    # 見 ../t21/queue-common.ps1 同型註解）——先賦值，再對已賦值變數包 @()／逗號保護跨界回傳。
    $safe = ConvertTo-SafeArray -RawValue $parsed
    $safe = @($safe)
    return ,@($safe)
}

function Get-RemediatedTicketsFromDir {
    param([string]$Dir, [string]$RepoString)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return ,@() }
    if (-not (Test-Path -LiteralPath $Dir)) { throw "找不到 remediated tickets 目錄：$Dir" }
    $files = @(Get-ChildItem -LiteralPath $Dir -Filter '*.md' | Sort-Object Name)
    $tickets = @()
    foreach ($f in $files) {
        $numMatch = [regex]::Match($f.BaseName, '(\d+)')
        $num = if ($numMatch.Success) { [int]$numMatch.Groups[1].Value } else { 0 }
        $body = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        $tickets += [pscustomobject]@{ number = $num; body = $body; RepoString = $RepoString }
    }
    return ,@($tickets)
}

# ============================================================
# §6 checklist 逐站候選判定（重用 t10 Get-StationChecklistDefinition，站1-3；不另立第二份 Id 表）
# ============================================================
function Get-AuditorCandidateStation {
    param([Parameter(Mandatory)][array]$AuditorFindings)
    $AuditorFindings = @($AuditorFindings)
    $findingsById = @{}
    foreach ($f in $AuditorFindings) { $findingsById[$f.Id] = $f }

    $stationsToWalk = @('sc:station-1', 'sc:station-2', 'sc:station-3')
    foreach ($st in $stationsToWalk) {
        $defs = @(Get-StationChecklistDefinition -Station $st)
        $unmet = @()
        foreach ($d in $defs) {
            if ($findingsById.ContainsKey($d.Id)) {
                $f = $findingsById[$d.Id]
                if ($f.Mark -eq 'fail') {
                    $unmet += [pscustomobject]@{ Id = $d.Id; Text = $d.Text; Evidence = $f.Evidence; MissingClass = $f.MissingClass }
                }
                # pass／na 視為滿足（N/A＝不適用，不構成缺項）
            } else {
                $unmet += [pscustomobject]@{ Id = $d.Id; Text = $d.Text; Evidence = '(auditor 報告缺此項結論，fail-closed 視為未滿足)'; MissingClass = 'critical' }
            }
        }
        $unmet = @($unmet)
        if ($unmet.Count -gt 0) {
            $stationNum = [int]($st -replace 'sc:station-', '')
            $idsText = (@($unmet | ForEach-Object { $_.Id })) -join '、'
            return [pscustomobject]@{
                CandidateStation    = $stationNum
                RetreatStationLabel = $st
                UnmetItems          = @($unmet)
                Detail              = "從站 1 往上核對 §6 同一份 checklist（§7.3），第一個未滿足＝『$st』；未滿足項：$idsText"
            }
        }
    }
    return [pscustomobject]@{
        CandidateStation    = 4
        RetreatStationLabel = 'sc:station-4'
        UnmetItems          = @()
        Detail              = "站 1-3 checklist 全數滿足；候選站別以 4 表示『至少通過站 3』（本判定不細分站 4/5 子項，屬 T-14/T-15a 範圍，比照 ../t10/gate-check.ps1 既有 deferred 界線，見 auditor-prompt.md）"
    }
}

# ============================================================
# 🔴 定站上限站 3（§7.3，票面驗收條件①核心）
# ============================================================
function Test-LegacyStationCap {
    param(
        [Parameter(Mandatory)][int]$CandidateStation,
        [switch]$TicketsRemediated,
        [switch]$BypassCapForRedTest
    )
    if ($BypassCapForRedTest) {
        return [pscustomobject]@{
            DeterminedStation = $CandidateStation
            CapApplied        = $false
            Detail            = "⚠️⚠️⚠️ -BypassCapForRedTest 已開啟：未套用 legacy 定站上限（Spec §7.3：legacy 工作定站上限為站 3），候選站別 '$CandidateStation' 原樣輸出，僅供紅燈驗證，正式流程與一般手動執行絕對不得使用"
        }
    }
    if ($CandidateStation -gt 3 -and -not $TicketsRemediated) {
        return [pscustomobject]@{
            DeterminedStation = 3
            CapApplied        = $true
            Detail            = "候選站別=$CandidateStation 高於 legacy 定站上限站 3（Spec §7.3），且票尚未收編完成（§7.3 兩條路徑皆未滿足，見 Test-LegacyRemediationComplete），封頂為站 3"
        }
    }
    return [pscustomobject]@{
        DeterminedStation = $CandidateStation
        CapApplied        = $false
        Detail            = "候選站別=$CandidateStation：未超過站 3 上限，或票已收編完成（cap 不介入）"
    }
}

# ============================================================
# §7.3 補件／不收編兩條路徑判定（不改變任何舊票，純讀）
# ============================================================
function Test-LegacyRemediationComplete {
    param(
        [array]$NativeTickets = @(),
        [string]$DecisionsMdContent = ''
    )
    $NativeTickets = @($NativeTickets)
    if ($NativeTickets.Count -gt 0) {
        $deep = Test-Station3TicketSetDeep -Tickets $NativeTickets
        if ($deep.Satisfied) {
            return [pscustomobject]@{
                Remediated = $true
                Path       = 'path1-8fields'
                Detail     = "路徑①：$($NativeTickets.Count) 張 native 票通過 §3.5 八欄位深度檢查（重用 T-13 Test-Station3TicketSetDeep，不重寫）：$($deep.Detail)"
            }
        }
    }
    if ($DecisionsMdContent -match '不收編[、，,]\s*僅供查閱') {
        return [pscustomobject]@{
            Remediated = $true
            Path       = 'path2-not-adopted'
            Detail     = 'DECISIONS.md 具名記載「不收編、僅供查閱」（Spec §7.3 路徑②），舊票原樣保留、未被改寫'
        }
    }
    return [pscustomobject]@{
        Remediated = $false
        Path       = $null
        Detail     = '兩條路徑皆未滿足：無通過 §3.5 八欄位深度檢查之 native 票集，DECISIONS.md 亦無「不收編、僅供查閱」具名記載'
    }
}

# ============================================================
# auditor 報告品質守門（fail-closed；✗項須有非空證據與合法缺件分類）
# ============================================================
function Test-AuditorFindingsWellFormed {
    param([Parameter(Mandatory)][array]$AuditorFindings)
    $AuditorFindings = @($AuditorFindings)
    $problems = @()
    foreach ($f in $AuditorFindings) {
        $hasMark = ($f.PSObject.Properties.Name -contains 'Mark') -and -not [string]::IsNullOrWhiteSpace($f.Mark)
        if (-not $hasMark) { $problems += "缺 Mark 欄位：$($f.Id)"; continue }
        if ($f.Mark -notin @('pass', 'fail', 'na')) {
            $problems += "Mark 值不合法（須為 pass/fail/na）：$($f.Id)='$($f.Mark)'"
            continue
        }
        if ($f.Mark -eq 'fail') {
            $hasEvidence = ($f.PSObject.Properties.Name -contains 'Evidence') -and -not [string]::IsNullOrWhiteSpace($f.Evidence)
            if (-not $hasEvidence) { $problems += "✗ 項缺證據指向（不得空泛，§7.2）：$($f.Id)" }
            $mc = if ($f.PSObject.Properties.Name -contains 'MissingClass') { $f.MissingClass } else { $null }
            if ($mc -notin @('critical', 'minor')) { $problems += "✗ 項缺合法缺件分類（須為 critical/minor，§7.4）：$($f.Id)" }
        }
    }
    $problems = @($problems)
    return [pscustomobject]@{ WellFormed = ($problems.Count -eq 0); Problems = @($problems) }
}

# ============================================================
# 人讀報告：逐條 ✓／✗／N/A ＋證據＋缺件分類
# ============================================================
function Format-AuditorReport {
    param([Parameter(Mandatory)][array]$AuditorFindings, [string]$AuditorSuggestedRetreatStation = '')
    $AuditorFindings = @($AuditorFindings)
    $lines = @()
    foreach ($f in $AuditorFindings) {
        $symbol = switch ($f.Mark) { 'pass' { '✓' }; 'fail' { '✗' }; 'na' { 'N/A' }; default { '?' } }
        $line = "[$symbol] $($f.Station) $($f.Id)"
        if ($f.Mark -eq 'fail') {
            $mc = if ($f.MissingClass) { $f.MissingClass } else { '(未分類)' }
            $line += " — 證據：$($f.Evidence)（缺件分類：$mc）"
        } elseif ($f.Evidence) {
            $line += " — $($f.Evidence)"
        }
        $lines += $line
    }
    if ($AuditorSuggestedRetreatStation) {
        $lines += "（auditor 自報建議退回站別：$AuditorSuggestedRetreatStation——僅供人讀參考，實際判定一律由程式從 Findings 重新算出，不採信此欄位本身，見 auditor-prompt.md）"
    }
    return ,@($lines)
}

# ============================================================
# 🔴 不改寫舊票——程式碼層守門（不是只有文件宣告）
# ============================================================
function Test-LegacyTicketProtectionGuard {
    param(
        [Parameter(Mandatory)]$Item,
        [array]$ProtectedLegacyTickets = @()
    )
    $ProtectedLegacyTickets = @($ProtectedLegacyTickets)
    if (-not ($Item.target.PSObject.Properties.Name -contains 'issue')) {
        return [pscustomobject]@{ Blocked = $false; Detail = 'target 無 issue 欄位（例如 create-issue／create-milestone 型，尚未指向既有 issue），不適用本守門' }
    }
    $targetRepo = $Item.target.repo
    $targetIssue = [int]$Item.target.issue
    $hit = @($ProtectedLegacyTickets | Where-Object { $_.repo -eq $targetRepo -and [int]$_.issue -eq $targetIssue })
    if ($hit.Count -gt 0) {
        return [pscustomobject]@{
            Blocked = $true
            Detail  = "🚫 拒絕產生：目標 $targetRepo#$targetIssue 屬既有 legacy 舊票保護清單（Spec §7.3 兩條路徑皆不改寫舊票）；action='$($Item.action)' 一律被擋，不寫入佇列，不呼叫 Write-QueueFile"
        }
    }
    return [pscustomobject]@{ Blocked = $false; Detail = "目標 $targetRepo#$targetIssue 不在 legacy 舊票保護清單內，放行" }
}

function Add-Station18QueueItemIfAbsent {
    param(
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)]$Item,
        [array]$ProtectedLegacyTickets = @()
    )
    $guard = Test-LegacyTicketProtectionGuard -Item $Item -ProtectedLegacyTickets $ProtectedLegacyTickets
    if ($guard.Blocked) {
        return [pscustomobject]@{ Added = $false; Blocked = $true; Detail = $guard.Detail }
    }
    # 重用 t08 Add-QueueItemIfAbsent（去重＋寫入邏輯，不重寫；dot-source 後可直接呼叫）
    $r = Add-QueueItemIfAbsent -QueuePath $QueuePath -Item $Item
    return [pscustomobject]@{ Added = $r.Added; Blocked = $false; Detail = $r.Detail }
}

# ============================================================
# badge 生命週期階段①：intake 定站時計算初始 label 集合（含 sc:legacy）——獨立成函式供單元測試
# ============================================================
function Get-LegacyInitialLabelSet {
    param([Parameter(Mandatory)][string[]]$ExistingLabels, [Parameter(Mandatory)][int]$DeterminedStation)
    $determinedLabel = "sc:station-$DeterminedStation"
    return ,@(@($ExistingLabels) + @($determinedLabel, 'sc:legacy') | Select-Object -Unique)
}

# ============================================================
# Stage A/B 前置狀態偵測（唯讀，重用 t08 Find-AnchorByWorkId／Find-MilestoneByTitle，不觸發 t08 Stage C）
# ============================================================
function Get-LegacyIntakeStageState {
    param(
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][string]$PrimaryRepo,
        [Parameter(Mandatory)][string[]]$ParticipatingRepos,
        [Parameter(Mandatory)][hashtable]$Headers
    )
    $anchor = Find-AnchorByWorkId -Repo $PrimaryRepo -WorkId $WorkId -Headers $Headers
    if ($null -eq $anchor) {
        return [pscustomobject]@{ Stage = 'A-pending'; Anchor = $null; MissingMilestones = @() }
    }
    $missing = @()
    foreach ($repo in $ParticipatingRepos) {
        $ms = Find-MilestoneByTitle -Repo $repo -Title $WorkId -Headers $Headers
        if ($null -eq $ms) { $missing += $repo }
    }
    $missing = @($missing)
    if ($missing.Count -gt 0) {
        return [pscustomobject]@{ Stage = 'B-pending'; Anchor = $anchor; MissingMilestones = @($missing) }
    }
    return [pscustomobject]@{ Stage = 'ready-for-C'; Anchor = $anchor; MissingMilestones = @() }
}

# ============================================================
# 主流程：Stage A（intake 產生權）／B（intake 產生權）／C（gate 產生權，legacy 定站封頂）
# ============================================================
function Invoke-LegacyIntakeFlow {
    param([switch]$BypassCapForRedTest)

    if (-not ($T18WorkId -match '^W-[a-z0-9-]+$')) {
        throw ("WorkId 格式錯誤（須符合 ^W-[a-z0-9-]+`$，依 ../t07/templates.md §1 慣例）：{0}" -f $T18WorkId)
    }
    $participating = @($T18ParticipatingRepos | Select-Object -Unique)
    if ($participating -notcontains $T18PrimaryRepo) {
        $participating = @($participating + @($T18PrimaryRepo))
    }
    $fleet = if (@($T18FleetRepos).Count -gt 0) { @($T18FleetRepos) } else { @($participating) }

    $token = Read-PatToken -PatPath $T18PatPath
    $headers = Get-GithubHeaders -Token $token -UserAgent 'station-command-t18-legacy-intake'

    $lines = New-Object System.Collections.ArrayList
    function RepLine([string]$s) { Write-Host $s; [void]$lines.Add($s) }

    RepLine "legacy-intake 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
    RepLine "WorkId=$T18WorkId  PrimaryRepo=$T18PrimaryRepo  ParticipatingRepos=[$($participating -join ', ')]"
    RepLine ""

    $state = Get-LegacyIntakeStageState -WorkId $T18WorkId -PrimaryRepo $T18PrimaryRepo -ParticipatingRepos $participating -Headers $headers

    # --- Stage A：anchor（intake 產生權，重用 t08 body 模板） ---
    if ($state.Stage -eq 'A-pending') {
        RepLine "--- Stage A（intake 產生權，與 native 模式共用同一套建立步驟）：primary anchor ---"
        $bodyParts = @("work-id: $T18WorkId", "primary-repo: $T18PrimaryRepo", "participating-repos:")
        foreach ($p in $participating) { $bodyParts += "- $p" }
        $bodyParts += ""
        if ($T18WorkDescription) { $bodyParts += $T18WorkDescription }
        $item = [pscustomobject]@{
            action  = 'create-issue'
            target  = [pscustomobject]@{ repo = $T18PrimaryRepo }
            payload = [pscustomobject]@{ title = "$T18WorkId · primary anchor"; body = ($bodyParts -join "`n"); labels = @('sc:work'); milestone = $null }
            source  = $T18WorkId
        }
        $add = Add-QueueItemIfAbsent -QueuePath $T18QueuePath -Item $item
        RepLine "anchor 尚不存在；$($add.Detail)（action=create-issue，產生權=intake）"
        RepLine "=> 請先執行 ..\t21\apply-queue.ps1 -QueuePath `"$T18QueuePath`" 落地，落地後重跑本腳本繼續。"
        Write-Utf8BomFile -Path (Join-Path $T18Dir 'legacy-intake-report.txt') -Content (($lines.ToArray()) -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'A-pending'; OverallPass = $false }
    }
    RepLine "anchor 已存在：$T18PrimaryRepo#$($state.Anchor.number)"
    RepLine ""

    # --- Stage B：milestones（intake 產生權，重用 t08 函式） ---
    if ($state.Stage -eq 'B-pending') {
        RepLine "--- Stage B（intake 產生權）：milestones ---"
        $anchorPointer = "$T18PrimaryRepo#$($state.Anchor.number)"
        foreach ($repo in $state.MissingMilestones) {
            $desc = "work-id: $T18WorkId | primary-anchor: $anchorPointer"
            $msItem = [pscustomobject]@{
                action  = 'create-milestone'
                target  = [pscustomobject]@{ repo = $repo }
                payload = [pscustomobject]@{ title = $T18WorkId; description = $desc }
                source  = $T18WorkId
            }
            # ⚠️ 陷阱③：不可直接 @(Get-DescriptionLengthViolations ...)（該函式以 `return ,$violations`
            # 逗號保護回傳，call site 再包一層 @() 會把 N 筆錯包成 1 筆——先賦值，再對已賦值變數包 @()。
            $violations = Get-DescriptionLengthViolations -Payload $msItem.payload
            $violations = @($violations)
            if ($violations.Count -gt 0) {
                RepLine "$repo：milestone description 逾 100 字元，已擋下未加入佇列。請縮短 WorkId slug 後重試。"
                continue
            }
            $add = Add-QueueItemIfAbsent -QueuePath $T18QueuePath -Item $msItem
            RepLine "$repo：milestone 尚不存在；$($add.Detail)"
        }
        RepLine "=> 請先執行 ..\t21\apply-queue.ps1 -QueuePath `"$T18QueuePath`" 落地 milestone(s)，落地後重跑本腳本繼續。"
        Write-Utf8BomFile -Path (Join-Path $T18Dir 'legacy-intake-report.txt') -Content (($lines.ToArray()) -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'B-pending'; OverallPass = $false }
    }

    # --- Stage C：legacy 定站（gate 產生權；重用 t08 Test-GateInitCriteria 判準①②③④⑤，自定站別) ---
    RepLine "--- Stage C（gate 產生權，legacy 定站封頂＋sc:legacy）---"
    $anchor = $state.Anchor
    # ⚠️ 陷阱③：不可直接 @(ConvertTo-SafeArray ...)——先賦值，再對已賦值變數包 @()。
    $existingLabelsRaw = ConvertTo-SafeArray -RawValue $anchor.labels
    $existingLabelsRaw = @($existingLabelsRaw)
    $existingLabels = @($existingLabelsRaw | ForEach-Object { $_.name })
    $existingStationLabels = @($existingLabels | Where-Object { $_ -match '^sc:station-' })
    if (($existingStationLabels.Count -gt 0) -or ($existingLabels -contains 'sc:legacy')) {
        RepLine "anchor 已有站別 label 或 sc:legacy，本工作已完成初始化（或須轉復位模式，非本票範圍），無需動作。"
        Write-Utf8BomFile -Path (Join-Path $T18Dir 'legacy-intake-report.txt') -Content (($lines.ToArray()) -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'Done'; OverallPass = $true }
    }

    $gateInit = Test-GateInitCriteria -WorkId $T18WorkId -PrimaryRepo $T18PrimaryRepo -ParticipatingRepos $participating `
        -AnchorIssue $anchor -FleetRepos $fleet -Headers $headers
    foreach ($k in '1', '2', '3', '4') {
        $c = $gateInit.Criteria[$k]
        $mark = if ($c.Satisfied) { '✓' } else { '✗' }
        RepLine "判準$k（重用 T-08 Test-GateInitCriteria，與 native 共用）：$mark — $($c.Detail)"
    }
    RepLine "判準5（身分檢查，依 ADR-NP-009 不作 fail 條件）：$($gateInit.Criteria['5'].Detail)"

    if (-not $gateInit.OverallPass) {
        RepLine "=> gate 初始化判準①②③④未全過，未落任何 label，具名缺項如上。"
        Write-Utf8BomFile -Path (Join-Path $T18Dir 'legacy-intake-report.txt') -Content (($lines.ToArray()) -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'C-fail'; OverallPass = $false }
    }

    # --- auditor findings 消化 ---
    if ([string]::IsNullOrWhiteSpace($T18AuditorFindingsPath)) {
        RepLine "=> gate 初始化判準①②③④已全過，但尚未提供 -AuditorFindingsPath，無法定站（legacy 模式須先 dispatch fresh-context auditor，見 auditor-prompt.md），本次停手不猜測。"
        Write-Utf8BomFile -Path (Join-Path $T18Dir 'legacy-intake-report.txt') -Content (($lines.ToArray()) -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'C-awaiting-auditor'; OverallPass = $false }
    }
    $auditorData = Get-AuditorFindingsFromFile -Path $T18AuditorFindingsPath
    $wellFormed = Test-AuditorFindingsWellFormed -AuditorFindings $auditorData.Findings
    if (-not $wellFormed.WellFormed) {
        RepLine "=> auditor 報告品質守門未過（fail-closed，不猜測缺項）：$($wellFormed.Problems -join '；')"
        Write-Utf8BomFile -Path (Join-Path $T18Dir 'legacy-intake-report.txt') -Content (($lines.ToArray()) -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'C-fail-malformed-auditor'; OverallPass = $false }
    }
    RepLine ""
    RepLine "--- auditor 報告（逐條 ✓／✗／N/A ＋證據＋缺件分類） ---"
    foreach ($l in (Format-AuditorReport -AuditorFindings $auditorData.Findings -AuditorSuggestedRetreatStation $auditorData.AuditorSuggestedRetreatStation)) { RepLine $l }

    $candidate = Get-AuditorCandidateStation -AuditorFindings $auditorData.Findings
    RepLine ""
    RepLine "候選站別（程式重新計算，不採信 auditor 自報摘要）：$($candidate.CandidateStation) — $($candidate.Detail)"

    # --- §7.3 兩條路徑（remediation）判定 ---
    $decisionsContent = ''
    if ($T18DecisionsMdPath -and (Test-Path -LiteralPath $T18DecisionsMdPath)) {
        $decisionsContent = Get-Content -LiteralPath $T18DecisionsMdPath -Raw -Encoding UTF8
    }
    $remediatedTickets = Get-RemediatedTicketsFromDir -Dir $T18RemediatedTicketsDir -RepoString $T18PrimaryRepo
    $remediation = Test-LegacyRemediationComplete -NativeTickets $remediatedTickets -DecisionsMdContent $decisionsContent
    RepLine "§7.3 兩條路徑判定：Remediated=$($remediation.Remediated) — $($remediation.Detail)"

    $cap = Test-LegacyStationCap -CandidateStation $candidate.CandidateStation -TicketsRemediated:$remediation.Remediated -BypassCapForRedTest:$BypassCapForRedTest
    RepLine "定站上限（Spec §7.3）：DeterminedStation=$($cap.DeterminedStation)  CapApplied=$($cap.CapApplied) — $($cap.Detail)"

    $determinedLabel = "sc:station-$($cap.DeterminedStation)"
    $desiredLabels = Get-LegacyInitialLabelSet -ExistingLabels $existingLabels -DeterminedStation $cap.DeterminedStation
    # ⚠️ 陷阱③：不可直接 @(Get-ProtectedLegacyTicketsFromFile ...)——先賦值，再對已賦值變數包 @()。
    $protectedTickets = Get-ProtectedLegacyTicketsFromFile -Path $T18ProtectedLegacyTicketsPath
    $protectedTickets = @($protectedTickets)
    $labelItem = [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $T18PrimaryRepo; issue = $anchor.number }
        payload = [pscustomobject]@{ labels = @($desiredLabels) }
        source  = $T18WorkId
    }
    $add = Add-Station18QueueItemIfAbsent -QueuePath $T18QueuePath -Item $labelItem -ProtectedLegacyTickets $protectedTickets
    if ($add.Blocked) {
        RepLine "🚫 不改寫舊票守門觸發（不應發生於 anchor 自身，若發生代表守門邏輯有誤，需人工複查）：$($add.Detail)"
        Write-Utf8BomFile -Path (Join-Path $T18Dir 'legacy-intake-report.txt') -Content (($lines.ToArray()) -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'C-guard-blocked'; OverallPass = $false }
    }
    RepLine "定站結果：$determinedLabel ＋ sc:legacy；$($add.Detail)（action=set-labels，產生權=gate）"
    RepLine "=> 請執行 ..\t21\apply-queue.ps1 -QueuePath `"$T18QueuePath`" 落地。"

    Write-Utf8BomFile -Path (Join-Path $T18Dir 'legacy-intake-report.txt') -Content (($lines.ToArray()) -join [Environment]::NewLine)
    return [pscustomobject]@{
        Stage = 'C-pass'; OverallPass = $true
        DeterminedStation = $cap.DeterminedStation; CapApplied = $cap.CapApplied
        CandidateStation = $candidate.CandidateStation; Remediation = $remediation
    }
}

if (-not $T18FunctionsOnlyFlag) {
    $result = Invoke-LegacyIntakeFlow -BypassCapForRedTest:$T18BypassCapForRedTest
    switch ($result.Stage) {
        'Done'   { exit 0 }
        'C-pass' { exit 0 }
        'A-pending' { exit 2 }
        'B-pending' { exit 2 }
        'C-awaiting-auditor' { exit 2 }
        default  { exit 1 }
    }
}
