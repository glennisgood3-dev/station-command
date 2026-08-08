#requires -Version 5.1
<#
.SYNOPSIS
    T-10：出口條件檢查器——跑當前站出口條件（Spec §6），逐條 ✓／✗；跨站請求必須拒絕（§3.4）。

.DESCRIPTION
    依 Spec_station-command_v1.8.md §6（各站出口條件正典）與 §3.4（站別歸因與復位）實作。
    重用 T-21 地基（../t21/queue-common.ps1）的讀端函式與 UTF-8/陣列安全慣例，本檔不重寫。

    兩層判定，順序固定：
      ① 站序合法性（§3.4「站別推進＝單一動作」的前提——只允許推進到現站的「緊鄰下一站」）。
         不合法（含 1→3／2→4／3→5 等跳站）⇒ 立即拒絕，並具名列出「被跳過站」各自的未滿足出口條件
         （呼叫本檔的站別 checklist，對每個被跳過站各跑一次，fail-closed 呈現）。
      ② 若①合法，才對「現站」（即將被離開、要離開需先過的站）跑 §6 該站 checklist；全過 ⇒
         OverallPass=true（供 gate-advance.ps1 產生推進佇列項）；未過 ⇒ 具名缺項，拒絕推進。

    **scope 邊界（誠實聲明，非規避）**：
      - 站 1／2 的 checklist 全數屬「內容裁量項」（名詞表是否完備、spec 是否可驗證、使用者是否已
        確認共識等）——這些判斷不是「既有資料機械性推導」，依 §5.0 屬 deliverable／裁示紀錄範疇，
        gate 本身不越權替 Commander／使用者下判斷。本檔只負責「檢查裁定結果是否已提供」
        （-ChecklistOverrides，呼叫端＝已完成讀驗的 Commander 傳入其判定），未提供 ⇒ fail-closed。
      - 站 3 的「§3.5 全八項欄位」為結構性存在檢查（欄位關鍵字是否出現在票 body），純機械可判定，
        本檔實作；「切片可獨立驗收（垂直非水平）」仍屬內容裁量，走 override。
      - 站 4（紅綠證據判斷、verifier≠executor）與站 5（雙審、修復復驗、關票）**不在本票範圍**
        （🔒 scope 鎖，見 T-14／T-15a）。本檔對這兩站僅列「Deferred to T-14／T-15a」單一具名項，
        一律 fail-closed（不得靜默判 ✓），避免使用者誤以為本票已涵蓋深度驗收邏輯。
      - 「全參與 repo DECISIONS.md 過期豁免掃描」不在本票範圍（T-19），本檔明確標「N/A（T-19 範圍，
        本票不判定）」，**不計入 AND**，也不偽裝成已檢查。
      - 「站別歸因合法」「gate 執行身分」兩項依 ADR-NP-009：手動階段降為規範層＋人工複查，
        **不算入 AND 判定**（比照 T-08 init-path.md 判準⑤的既有先例），僅具名回報供人工複查；
        CI 階段（提供 -GateIdentityLogins）才轉為判定用途（deferred-to-CI，見 gate-reset.md）。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程（供離線／動態測試 dot-source 呼叫內部函式）。
#>

[CmdletBinding()]
param(
    [string]$WorkId,
    [string]$PrimaryRepo,
    [int]$AnchorIssue,
    [string]$TargetStation,
    [string[]]$ParticipatingRepos = @(),
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$ChecklistOverridesPath = '',
    [string[]]$GateIdentityLogins = @(),
    [switch]$BypassStationOrderCheck,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$QueueCommonPath = Join-Path $ScriptDir '..\t21\queue-common.ps1'
if (-not (Test-Path -LiteralPath $QueueCommonPath)) {
    throw ("找不到 T-21 共用函式庫：{0}。請確認 t10 與 t21 為同層兄弟目錄。" -f $QueueCommonPath)
}
. $QueueCommonPath
Set-ConsoleUtf8

# ============================================================
# 站序正典（§3.4／§6；done 為完成態，非「站 6」）
# ============================================================
$Script:StationOrder = @('sc:station-1', 'sc:station-2', 'sc:station-3', 'sc:station-4', 'sc:station-5', 'sc:station-done')

function Get-StationLabelsOnIssue {
    param([Parameter(Mandatory)]$Issue)
    $labelsRaw = ConvertTo-SafeArray -RawValue $Issue.labels
    $labelsRaw = @($labelsRaw)
    $names = $labelsRaw | ForEach-Object { $_.name }
    $names = @($names)
    $stationNames = @($names | Where-Object { $_ -match '^sc:station-' })
    return ,$stationNames
}

# --- 判準：anchor 現有站別 label 必須恰好一個（§3.3 互斥不變式），否則視為髒資料 ---
function Get-CurrentStation {
    param([Parameter(Mandatory)]$Issue)
    $stations = Get-StationLabelsOnIssue -Issue $Issue
    $stations = @($stations)
    if ($stations.Count -eq 0) {
        return [pscustomobject]@{ Station = $null; Valid = $false; Detail = 'anchor 無任何 sc:station-* label（尚未初始化，或髒資料）' }
    }
    if ($stations.Count -gt 1) {
        return [pscustomobject]@{ Station = $null; Valid = $false; Detail = "anchor 同時帶多個站別 label：[$($stations -join ', ')]（違反 §3.3 互斥不變式，髒資料，拒絕判定）" }
    }
    return [pscustomobject]@{ Station = $stations[0]; Valid = $true; Detail = "現有站別：$($stations[0])" }
}

function Get-NextStation {
    param([Parameter(Mandatory)][string]$Current)
    $idx = [array]::IndexOf($Script:StationOrder, $Current)
    if ($idx -lt 0) { throw "未知站別 label（不在 §3.4 站序正典內）：$Current" }
    if ($idx -ge ($Script:StationOrder.Count - 1)) { return $null }
    return $Script:StationOrder[$idx + 1]
}

# --- §3.4 站序不可跳：唯一允許的目標＝現站的緊鄰下一站 ---
function Test-StationOrderValid {
    param([Parameter(Mandatory)][string]$Current, [Parameter(Mandatory)][string]$Target)
    $next = Get-NextStation -Current $Current
    if ($null -eq $next) {
        return [pscustomobject]@{ Valid = $false; Detail = "現站 '$Current' 已是站序終態，無下一站可推進；請求目標='$Target'" }
    }
    if ($Target -eq $Current) {
        return [pscustomobject]@{ Valid = $false; Detail = "請求目標與現站相同（'$Target'），非推進動作" }
    }
    if ($Target -ne $next) {
        return [pscustomobject]@{ Valid = $false; Detail = "跨站請求被拒（§3.4 站序不可跳）：現站='$Current'，請求目標='$Target'，唯一允許的下一站='$next'" }
    }
    return [pscustomobject]@{ Valid = $true; Detail = "站序合法：'$Current' → '$Target'（緊鄰下一站）" }
}

# ============================================================
# §3.5 八項欄位存在性檢查（結構性，非內容品質；站 3 專用）
# ============================================================
function Test-TicketFieldsPresence {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$TicketBody)
    $fields = @('REQ-ID', '驗收條件', 'depends_on', 'executor', 'basis', 'scope', '測試先行', '不可逆動作')
    $missing = @()
    foreach ($f in $fields) {
        if ($TicketBody -notmatch [regex]::Escape($f)) { $missing += $f }
    }
    $missing = @($missing)
    return [pscustomobject]@{ Satisfied = ($missing.Count -eq 0); Missing = $missing }
}

function Test-Station3FieldsChecklistItem {
    param([array]$Tickets)
    $Tickets = @($Tickets)
    if ($Tickets.Count -eq 0) {
        return [pscustomobject]@{ Satisfied = $false; Detail = '該 work 尚無任何 sc:ticket，站 3 出口條件不成立（無票可判）' }
    }
    $bad = @()
    foreach ($t in $Tickets) {
        $body = if ($t.PSObject.Properties.Name -contains 'body' -and $null -ne $t.body) { $t.body } else { '' }
        $chk = Test-TicketFieldsPresence -TicketBody $body
        if (-not $chk.Satisfied) { $bad += "#$($t.number) 缺：$($chk.Missing -join '、')" }
    }
    $bad = @($bad)
    $ok = ($bad.Count -eq 0)
    $detail = if ($ok) { "共 $($Tickets.Count) 張票，§3.5 八項欄位關鍵字皆存在（結構性檢查，非內容品質判斷；深度邏輯屬 T-13）" } else { "$($bad.Count) 張票缺欄位（結構性檢查）：" + ($bad -join '；') }
    return [pscustomobject]@{ Satisfied = $ok; Detail = $detail }
}

# ============================================================
# 各站出口 checklist 定義（§6 逐條對照，含機械可判定／需外部裁定兩類）
# ============================================================
function Get-StationChecklistDefinition {
    param([Parameter(Mandatory)][string]$Station)
    switch ($Station) {
        'sc:station-1' {
            return @(
                [pscustomobject]@{ Id = '1.glossary'; Text = '名詞表存在且關鍵詞無未定義'; Type = 'RequiresInput' }
                [pscustomobject]@{ Id = '1.adr';      Text = 'ADR 記錄關鍵裁示（含理由與被否決方案）'; Type = 'RequiresInput' }
                [pscustomobject]@{ Id = '1.confirm';  Text = '使用者已確認共識'; Type = 'RequiresInput' }
            )
        }
        'sc:station-2' {
            return @(
                [pscustomobject]@{ Id = '2.spec';     Text = 'spec 有 Goal／Scope In-Out／可驗證 Success Criteria'; Type = 'RequiresInput' }
                [pscustomobject]@{ Id = '2.confirm';  Text = '使用者已確認'; Type = 'RequiresInput' }
                [pscustomobject]@{ Id = '2.gapreview';Text = '第三方缺口審報告存在且 hard finding 全結案'; Type = 'RequiresInput' }
            )
        }
        'sc:station-3' {
            return @(
                [pscustomobject]@{ Id = '3.fields';   Text = '每張票具備 §3.5 全八項欄位（結構性存在檢查）'; Type = 'Mechanical' }
                [pscustomobject]@{ Id = '3.vertical'; Text = '切片可獨立驗收（垂直非水平）'; Type = 'RequiresInput' }
            )
        }
        'sc:station-4' {
            return @(
                [pscustomobject]@{ Id = '4.deferred'; Text = '每張票紅→綠兩段證據、verifier≠executor 實測一致（🔒 深度驗收邏輯屬 T-14 範圍，本票不實作，fail-closed）'; Type = 'RequiresInput' }
            )
        }
        'sc:station-5' {
            return @(
                [pscustomobject]@{ Id = '5.deferred'; Text = '兩軸雙審、修復復驗、關票（🔒 深度驗收邏輯屬 T-15a 範圍，本票不實作，fail-closed）'; Type = 'RequiresInput' }
            )
        }
        'sc:station-done' {
            return @(
                [pscustomobject]@{ Id = 'done.deferred'; Text = 'open 票數為零且全票經站 5 gate 關閉（🔒 完成態收尾邏輯屬 T-15b 範圍，本票不實作，fail-closed）'; Type = 'RequiresInput' }
            )
        }
        # 注意：本分支刻意不用逗號運算子包裝（比照上方各分支的 return @(...) 慣例，非漏寫）——
        # 呼叫端一律以單行 @(Get-StationChecklistDefinition ...) 收集回傳值（見 Invoke-StationExitChecklist），
        # 若這裡改用 `return ,@()`，該 0 筆情境會被呼叫端的 @() 再包一層，變成「1 筆內容為空陣列」
        # 而非「0 筆」（與 queue-common.ps1 註解記載的同型陷阱一致，已用 pwsh 7 實測驗證並修正）。
        default { return @() }
    }
}

# --- 對單一站別跑 checklist：Mechanical 項自行判定；RequiresInput 項讀 overrides，缺 ⇒ fail-closed ---
function Invoke-StationExitChecklist {
    param(
        [Parameter(Mandatory)][string]$Station,
        [array]$Tickets = @(),
        [hashtable]$ChecklistOverrides = @{}
    )
    $Tickets = @($Tickets)
    $defs = @(Get-StationChecklistDefinition -Station $Station)
    $items = @()
    foreach ($d in $defs) {
        if ($d.Type -eq 'Mechanical') {
            switch ($d.Id) {
                '3.fields' {
                    $r = Test-Station3FieldsChecklistItem -Tickets $Tickets
                    $items += [pscustomobject]@{ Id = $d.Id; Text = $d.Text; Type = $d.Type; Satisfied = $r.Satisfied; Detail = $r.Detail }
                }
                default {
                    $items += [pscustomobject]@{ Id = $d.Id; Text = $d.Text; Type = $d.Type; Satisfied = $false; Detail = "未知 Mechanical 項（實作缺漏）：$($d.Id)" }
                }
            }
        } else {
            # RequiresInput：呼叫端（已完成讀／驗／dispatch 的 Commander）透過 -ChecklistOverrides 傳入裁定；
            # 缺 ⇒ fail-closed（不得因「沒傳」就默認通過）。
            if ($ChecklistOverrides.ContainsKey($d.Id)) {
                $ov = $ChecklistOverrides[$d.Id]
                $sat = [bool]$ov.Satisfied
                $detail = if ($ov.PSObject -and $ov.PSObject.Properties.Name -contains 'Detail') { $ov.Detail } elseif ($ov -is [hashtable] -and $ov.ContainsKey('Detail')) { $ov['Detail'] } else { '(無附加說明)' }
                $items += [pscustomobject]@{ Id = $d.Id; Text = $d.Text; Type = $d.Type; Satisfied = $sat; Detail = $detail }
            } else {
                $items += [pscustomobject]@{ Id = $d.Id; Text = $d.Text; Type = $d.Type; Satisfied = $false; Detail = '未提供裁定結果（本項需人工／dispatch 判斷，caller 尚未提供 -ChecklistOverrides，fail-closed）' }
            }
        }
    }
    $items = @($items)
    $unmet = @($items | Where-Object { -not $_.Satisfied })
    return [pscustomobject]@{ Station = $Station; Items = $items; AllSatisfied = ($unmet.Count -eq 0) }
}

# ============================================================
# 全站列（§6「全站（每次 gate 均查）」）——依 ADR-NP-009，歸因與身分兩項手動階段不算入 AND
# ============================================================
function Test-WorkStationConsistency {
    param([Parameter(Mandatory)][string]$CurrentStation, [array]$OpenTickets = @())
    $OpenTickets = @($OpenTickets)
    if ($OpenTickets.Count -eq 0) {
        return [pscustomobject]@{ Satisfied = $true; Applicable = $false; Detail = '零 open 票，「未關閉票最小站」公式不適用，完成態改由 §3.2／T-15b 判定（本項不計入 AND）' }
    }
    $stations = @()
    foreach ($t in $OpenTickets) {
        $labelsRaw = ConvertTo-SafeArray -RawValue $t.labels
        $labelsRaw = @($labelsRaw)
        $names = @($labelsRaw | ForEach-Object { $_.name })
        $hasRedProven = ($names -contains 'sc:red-proven')
        $stations += if ($hasRedProven) { 5 } else { 4 }
    }
    $stations = @($stations)
    $minStation = ($stations | Measure-Object -Minimum).Minimum
    $expected = "sc:station-$minStation"
    $ok = ($CurrentStation -eq $expected)
    $detail = if ($ok) { "現站 '$CurrentStation' 與未關閉票最小站一致（$($OpenTickets.Count) 張 open 票，最小站=$minStation）" } else { "不一致：anchor 現站='$CurrentStation'，但未關閉票最小站應為 '$expected'（$($OpenTickets.Count) 張 open 票）" }
    return [pscustomobject]@{ Satisfied = $ok; Applicable = $true; Detail = $detail }
}

function Get-CrossStationChecklist {
    param(
        [Parameter(Mandatory)][string]$CurrentStation,
        [array]$OpenTickets = @(),
        [string[]]$GateIdentityLogins = @(),
        [string]$ObservedActorLogin = $null
    )
    $items = @()

    $wsc = Test-WorkStationConsistency -CurrentStation $CurrentStation -OpenTickets $OpenTickets
    $items += [pscustomobject]@{ Id = 'all.work-station'; Text = 'work 站別＝未關閉票的最小站（§3.2，零票時 N/A）'; Blocking = $wsc.Applicable; Satisfied = $wsc.Satisfied; Detail = $wsc.Detail }

    $items += [pscustomobject]@{ Id = 'all.decisions-exemption'; Text = '全參與 repo DECISIONS.md 無過期豁免'; Blocking = $false; Satisfied = $null; Detail = 'N/A（T-19 範圍，本票不判定，不計入 AND，不得誤讀為已檢查）' }

    if (@($GateIdentityLogins).Count -eq 0) {
        $items += [pscustomobject]@{ Id = 'all.attribution'; Text = '站別歸因合法（§3.4）'; Blocking = $false; Satisfied = $null; Detail = "手動階段：無機器歸因判準，依 ADR-NP-009 降為規範層＋人工複查，不算入 AND；deferred-to-CI（提供 -GateIdentityLogins 後生效，見 gate-reset.md）" }
        $items += [pscustomobject]@{ Id = 'all.identity';    Text = 'gate 執行身分 ≠ 使用者互動帳號'; Blocking = $false; Satisfied = $null; Detail = "手動階段：執行身分即使用者本人（已由 SC-DEC-BOT-001 實測確認），依 ADR-NP-009 不作 fail 條件；具名回報 actor='$ObservedActorLogin'" }
    } else {
        $legal = if ($null -ne $ObservedActorLogin) { $GateIdentityLogins -contains $ObservedActorLogin } else { $false }
        $items += [pscustomobject]@{ Id = 'all.attribution'; Text = '站別歸因合法（§3.4）'; Blocking = $true; Satisfied = $legal; Detail = "CI 階段：actor='$ObservedActorLogin'，gate 身分集合=[$($GateIdentityLogins -join ', ')]，legal=$legal" }
        $items += [pscustomobject]@{ Id = 'all.identity';    Text = 'gate 執行身分 ≠ 使用者互動帳號'; Blocking = $true; Satisfied = $legal; Detail = "CI 階段：actor='$ObservedActorLogin' $(if ($legal) { '屬於' } else { '不屬於' }) gate 執行身分集合" }
    }

    return ,@($items)
}

# ============================================================
# 整合：Invoke-GateCheck（gate-advance.ps1 的唯一判定入口）
# ============================================================
function Invoke-GateCheck {
    param(
        [Parameter(Mandatory)]$AnchorIssue,
        [Parameter(Mandatory)][string]$TargetStation,
        [array]$Tickets = @(),
        [hashtable]$ChecklistOverrides = @{},
        [string[]]$GateIdentityLogins = @(),
        [string]$ObservedActorLogin = $null,
        [switch]$BypassStationOrderCheck
    )
    $Tickets = @($Tickets)
    $cur = Get-CurrentStation -Issue $AnchorIssue
    if (-not $cur.Valid) {
        return [pscustomobject]@{ OverallPass = $false; Reason = 'dirty-anchor'; CurrentStation = $null; TargetStation = $TargetStation; Detail = $cur.Detail; OrderValid = $false; StationChecklist = $null; CrossStationItems = @() }
    }

    $orderCheck = Test-StationOrderValid -Current $cur.Station -Target $TargetStation
    $orderOkForGating = if ($BypassStationOrderCheck) { $true } else { $orderCheck.Valid }

    if (-not $orderOkForGating) {
        $skippedDetails = @()
        $curIdx = [array]::IndexOf($Script:StationOrder, $cur.Station)
        $targetIdx = [array]::IndexOf($Script:StationOrder, $TargetStation)
        if ($targetIdx -gt ($curIdx + 1)) {
            for ($i = $curIdx + 1; $i -lt $targetIdx; $i++) {
                $skipStation = $Script:StationOrder[$i]
                $cl = Invoke-StationExitChecklist -Station $skipStation -Tickets $Tickets -ChecklistOverrides $ChecklistOverrides
                $unmet = @($cl.Items | Where-Object { -not $_.Satisfied })
                $names = @($unmet | ForEach-Object { $_.Text })
                $namesText = if ($names.Count -gt 0) { $names -join '；' } else { '（本站無具名缺項，仍因跳站本身被拒）' }
                $skippedDetails += "被跳過站 '$skipStation' 未滿足條件：$namesText"
            }
        }
        $fullDetail = if (@($skippedDetails).Count -gt 0) { $orderCheck.Detail + '｜' + (($skippedDetails) -join '｜') } else { $orderCheck.Detail }
        return [pscustomobject]@{
            OverallPass = $false; Reason = 'station-order-violation'; CurrentStation = $cur.Station; TargetStation = $TargetStation
            Detail = $fullDetail; OrderValid = $false; StationChecklist = $null; CrossStationItems = @()
        }
    }

    $checklist = Invoke-StationExitChecklist -Station $cur.Station -Tickets $Tickets -ChecklistOverrides $ChecklistOverrides
    $openTickets = @($Tickets | Where-Object { $_.state -eq 'open' })
    $crossItems = Get-CrossStationChecklist -CurrentStation $cur.Station -OpenTickets $openTickets -GateIdentityLogins $GateIdentityLogins -ObservedActorLogin $ObservedActorLogin
    $crossBlockingUnmet = @($crossItems | Where-Object { $_.Blocking -and (-not $_.Satisfied) })

    $overallPass = $checklist.AllSatisfied -and (@($crossBlockingUnmet).Count -eq 0)

    $namedGaps = @()
    if (-not $checklist.AllSatisfied) {
        $namedGaps += @(($checklist.Items | Where-Object { -not $_.Satisfied }) | ForEach-Object { "[站別 checklist] $($_.Text) — $($_.Detail)" })
    }
    if (@($crossBlockingUnmet).Count -gt 0) {
        $namedGaps += @($crossBlockingUnmet | ForEach-Object { "[全站列] $($_.Text) — $($_.Detail)" })
    }
    $namedGaps = @($namedGaps)

    return [pscustomobject]@{
        OverallPass = $overallPass; Reason = if ($overallPass) { 'pass' } else { 'checklist-unmet' }
        CurrentStation = $cur.Station; TargetStation = $TargetStation; OrderValid = $true
        StationChecklist = $checklist; CrossStationItems = $crossItems; NamedGaps = $namedGaps
        Detail = if ($overallPass) { "全過：現站 '$($cur.Station)' 出口條件全部滿足，允許推進到 '$TargetStation'" } else { "未過，缺項：" + ($namedGaps -join '｜') }
    }
}

# ============================================================
# 讀現況：某 work 的全部票（sc:ticket，跨參與 repo，依 milestone 標題比對）
# ============================================================
function Get-TicketsForWork {
    param([Parameter(Mandatory)][string]$WorkId, [Parameter(Mandatory)][string[]]$ParticipatingRepos, [Parameter(Mandatory)][hashtable]$Headers)
    $all = @()
    foreach ($repoStr in $ParticipatingRepos) {
        $r = Split-RepoString -RepoString $repoStr
        $url = "https://api.github.com/repos/$($r.Owner)/$($r.Repo)/issues?labels=sc:ticket&state=all&per_page=100"
        $raw = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
        $issues = ConvertTo-SafeArray -RawValue $raw
        $issues = @($issues)
        foreach ($iss in $issues) {
            $msTitle = $null
            if ($iss.PSObject.Properties.Name -contains 'milestone' -and $null -ne $iss.milestone) { $msTitle = $iss.milestone.title }
            if ($msTitle -eq $WorkId) { $all += $iss }
        }
    }
    return ,@($all)
}

# ============================================================
# 主流程（CLI 直接執行）
# ============================================================
function Invoke-GateCheckCli {
    if (-not $WorkId -or -not $PrimaryRepo -or -not $AnchorIssue -or -not $TargetStation) {
        throw '直接執行模式須提供 -WorkId -PrimaryRepo -AnchorIssue -TargetStation（或改用 -FunctionsOnly 供測試 dot-source）'
    }
    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t10-gate-check'

    $participating = if (@($ParticipatingRepos).Count -gt 0) { @($ParticipatingRepos) } else { @($PrimaryRepo) }
    $r = Split-RepoString -RepoString $PrimaryRepo
    $anchor = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber $AnchorIssue -Headers $Headers
    if ($null -eq $anchor) { throw "找不到 anchor：$PrimaryRepo#$AnchorIssue" }

    $tickets = Get-TicketsForWork -WorkId $WorkId -ParticipatingRepos $participating -Headers $Headers

    $overrides = @{}
    if ($ChecklistOverridesPath -and (Test-Path -LiteralPath $ChecklistOverridesPath)) {
        $raw = Get-Content -LiteralPath $ChecklistOverridesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $raw.PSObject.Properties) { $overrides[$p.Name] = $p.Value }
    }

    $observedActor = $null
    try { $observedActor = (Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $Headers -Method Get).login } catch { }

    $result = Invoke-GateCheck -AnchorIssue $anchor -TargetStation $TargetStation -Tickets $tickets -ChecklistOverrides $overrides `
        -GateIdentityLogins $GateIdentityLogins -ObservedActorLogin $observedActor -BypassStationOrderCheck:$BypassStationOrderCheck

    $lines = @("gate-check 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "WorkId=$WorkId  Anchor=$PrimaryRepo#$AnchorIssue  Target=$TargetStation", "")
    $lines += "現站：$($result.CurrentStation)　請求目標：$($result.TargetStation)　站序合法：$($result.OrderValid)"
    $lines += "整體判定：$(if ($result.OverallPass) { 'PASS' } else { 'FAIL' })（$($result.Reason)）"
    $lines += $result.Detail
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $ScriptDir 'gate-check-report.txt') -Content ($lines -join [Environment]::NewLine)

    if ($result.OverallPass) { exit 0 } else { exit 1 }
}

if (-not $FunctionsOnly) {
    Invoke-GateCheckCli
}
