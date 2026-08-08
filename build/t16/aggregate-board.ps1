#requires -Version 5.1
<#
.SYNOPSIS
    T-16 · aggregate-board.ps1 — 跨 repo 聚合、work ID 分組、逐 repo 進度與消失偵測。

.DESCRIPTION
    依 Spec_station-command_v1.11.md §4.1／§4.2／§4.4／§3.1／§3.3 定案（tickets-draft.md T-16，GitHub issue #17）。
    地基：`../t09/render-board.ps1`（單 work 字卡最小可用，T-09）——本檔 dot-source 該檔（`-FunctionsOnly`）
    複用其純函式（`Build-WorkCardHtml`／`ConvertTo-StatusLight`／`Get-StationLabelInfo`／
    `Build-RunningAndStaleCounts`／`Build-StepperHtml`／`Build-RepoProgressHtml`／`Get-ExecutorFromBody`／
    `Get-ParticipatingReposFromBody`／`ConvertTo-HtmlEncoded`／`ConvertTo-BoardIssue`／`ConvertTo-SafeArray`／
    `Save-StationBoardArtifact`／`Read-CacheBaselineFromExistingArtifact`／`Get-TicketDirtyStationLabels`／
    `Read-PatToken`／`Get-GithubHeaders`／`Write-Utf8BomFile`），🚫 不修改 `../t09/render-board.ps1` 本身
    （file ownership）。**呼叫 `Build-WorkCardHtml` 產生每張字卡是本票「不得新增欄位」的落地手段**——
    直接沿用 T-09 的欄位集合與 HTML 結構，T-16 只負責「餵給它正確的多 work 分組資料」，不改字卡本身
    長什麼樣。

    T-09 與 T-16 的職責分界（T-09 README「scope 邊界」已明文）：
      T-09＝單一已知 work 的字卡 render（呼叫端已知 WorkId／PrimaryRepo）。
      T-16＝**不**預先知道有哪些 work——一次跨 repo search 撈 `sc:work`＋`sc:ticket` 的 open issues，
            自己從 milestone description／anchor body 解出 work-id 分組，逐 work 各自組一張字卡，
            並疊加 anchor 消失偵測（§4.4）。

    純／不純切分（承襲 T-09 架構，同一理由：§4.4 的異常狀態須能在沙盒離線 100% 決定性重現）：
        Group-FleetIssuesByWorkId      **pure**。只吃已正規化的 issue 陣列，依 anchor body／milestone
                                        description 解出的 work-id 分組。**T-16 驗收②「誤併」的唯一測試
                                        seam**——t16-offline-test.ps1 直接呼叫本函式斷言分組正確性。
        Get-FleetMilestoneRowsForWork  impure（可測：接受 `-MilestoneListFetcher` 注入點，離線測試用
                                        scriptblock 取代真實 REST 呼叫）。逐 repo 分列進度（§4.1），
                                        比對鍵一律是 milestone description 的 work-id，🚫 不比對 title。
        Get-FleetSnapshot              impure。串接搜尋＋分組＋逐 repo 進度＋佇列讀取，組出 Snapshot。
        Build-FleetBoardReport         **pure**。吃 Snapshot（可為真實或手造 mock）＋顯示快取＋現在時間，
                                        算出 Html／TextSummary／ErrorStates／CacheData。
                                        **T-16 驗收①③④⑤⑥的整合測試 seam**。
        Invoke-FleetBoardRender        impure 頂層入口。

    ⚠️ PS 5.1 + StrictMode 三個已知陷阱（依 T-09/T-21/T-10 先例，本檔全程套用，理由同 T-09 檔頭）：
      1. 單一物件沒有 `.Count` 屬性 ⇒ 先賦值變數再用 ConvertTo-SafeArray／@() 包過。
      2. `,@()` 只在跨函式邊界 return 時才需要逗號前綴；區域賦值一律直接 `@()`。
      3. `@(函式呼叫本身)` 會把 0 筆結果錯誤包成 1 筆 $null ⇒ 先賦值變數再包 @()。

    ⚠️ 變數命名紀律（依 T-12/T-13 踩過的 `$ScriptDir` cascade 覆蓋教訓）：本檔頂層參數全部加
    `T16` 前綴（`$T16Repos`／`$T16OutputPath`…），🚫 不與 dot-source 進來的
    `../t09/render-board.ps1` 頂層參數（`$WorkId`／`$PrimaryRepo`／`$OutputPath`…）同名——dot-source
    會把對方的參數預設值也帶進本檔作用域，若命名相同會被其預設值（多半指向 t09 目錄）悄悄覆蓋。

.NOTES
    白名單依 Spec §2（`/station-board`）：讀 GitHub（search／issues／milestones／issue body 欄位）｜
    讀本機待寫佇列檔（§4.6，僅讀不寫）｜寫面板 artifact｜文字輸出。🚫 本檔不呼叫任何 GitHub 寫入端點
    （無 PUT/POST/PATCH/DELETE），全程唯讀 GitHub。唯一的寫入動作是 `Save-StationBoardArtifact`
    （繼承自 t09，寫面板 HTML 到本機磁碟，非 GitHub）。

    FLEET SNAPSHOT SCHEMA（Get-FleetSnapshot 的回傳形狀 = 離線測試手造 mock 時必須遵守的形狀）：

    [pscustomobject]@{
        NowUtc                 = [datetime]
        Ok                     = $true/$false   # 跨 repo search 本身是否執行成功
        FailureDetail          = $null 或 string
        ResultCountThisRun     = <int 或 $null>
        TotalCountReported     = <int 或 $null>
        HitPageCap             = $true/$false
        QueryDescription       = '<純文字，供空狀態卡與失敗橫幅引用>'
        Works = @(
            [pscustomobject]@{
                WorkId              = 'W-xxx'
                AnchorIssue         = $null 或 BoardIssue（見 t09 schema，多一個 .Milestone 欄位）
                ParticipatingRepos  = @('owner/repo', ...)
                Tickets             = @(BoardIssue, ...)
                MilestoneRows       = @( [pscustomobject]@{ Repo; QueryOk; FailureDetail; MilestoneFound;
                                           Title; OpenIssues; ClosedIssues; PercentComplete }, ... )
                QueueInfo           = [pscustomobject]@{ Exists; Count; ParseError }
            }, ...
        )
        UnresolvedTicketsCount = <int>   # 診斷用：milestone description 解不出 work-id 的票數（best-effort，
                                          # 不阻擋主流程，票不會因此消失，只是暫不歸入任何字卡）
        DuplicateAnchorNotes   = @(string, ...)   # 診斷用：同一 work-id 出現一張以上 anchor 的具名紀錄
    }

    BoardIssue.Milestone（`ConvertTo-FleetIssue` 附加於 t09 `ConvertTo-BoardIssue` 輸出之上）：
    [pscustomobject]@{ Number; Title; Description; OpenIssues; ClosedIssues } 或 $null（issue 未掛 milestone）。
#>

[CmdletBinding()]
param(
    # 只載入函式、不執行 render（供 t16-offline-test.ps1／build-sample-fleet-board.ps1 dot-source 本檔時使用）
    [switch]$T16FunctionsOnly,

    [string[]]$T16Repos,
    [string]$T16PatPath = "$PSScriptRoot/pat.txt",
    [string]$T16QueuePath = "$PSScriptRoot/../t21/queue.json",
    [string]$T16TemplatePath = "$PSScriptRoot/fleet-board-template.html",
    [string]$T16OutputPath = "$PSScriptRoot/fleet-board.html",
    [switch]$T16NoReconcile,
    [int]$T16MaxPages = 5,
    [int]$T16PerPage = 100,

    # ⚠️⚠️ 下列兩個旗標僅供紅燈驗證使用，正式流程（含 SKILL.md 呼叫路徑）一律不得帶入 ⚠️⚠️
    [switch]$T16BugGroupByMilestoneTitle,
    [switch]$T16SkipNoBaselineBanner
)

Set-StrictMode -Version Latest

# 複用 T-09 地基（不修改該檔）。此行之後，$WorkId/$PrimaryRepo/$OutputPath/... 等 t09 頂層參數名稱
# 會以其預設值存在於本檔作用域——本檔後續程式碼一律不得引用這些「裸名稱」，只用 T16 前綴變數。
. "$PSScriptRoot/../t09/render-board.ps1" -FunctionsOnly

# ============================================================================
# 區塊 1：work-id 解析（純函式，字串比對）
# ============================================================================

function Get-FleetWorkIdFromAnchorBody {
    <# §3.1／T-07 templates.md §2：anchor body 首段機讀鍵值行 `work-id: W-<slug>`。 #>
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return $null }
    if ($Body -match '(?im)^\s*work-id\s*:\s*(W-\S+)\s*$') { return $Matches[1].Trim() }
    return $null
}

function Get-FleetWorkIdFromMilestoneDescription {
    <#
      §3.1／T-07 templates.md §3：milestone description 首行 `work-id: W-<slug> | primary-anchor: owner/repo#N`。
      🔴 T-16 驗收②的核心：分組鍵**只認這裡解出的 work-id，不認 milestone.Title**——標題僅供顯示，
      兩個不同 work 的 milestone 完全可能撞同一個顯示名稱。
    #>
    param([string]$Description)
    if ([string]::IsNullOrWhiteSpace($Description)) { return $null }
    $firstLine = ($Description -split "`r?`n")[0]
    if ($firstLine -match '(?i)work-id\s*:\s*(W-\S+?)\s*(?:\||$)') { return $Matches[1].Trim() }
    return $null
}

function ConvertTo-FleetIssue {
    <# 在 t09 ConvertTo-BoardIssue 的正規化結果上，附加 Milestone 子物件（t09 schema 沒有這欄）。 #>
    param([Parameter(Mandatory)]$RawIssue, [string]$RepoOverride)
    $base = ConvertTo-BoardIssue -RawIssue $RawIssue -RepoOverride $RepoOverride
    $milestone = $null
    if ($RawIssue.PSObject.Properties.Name -contains 'milestone' -and $null -ne $RawIssue.milestone) {
        $rm = $RawIssue.milestone
        $milestone = [pscustomobject]@{
            Number       = [int]$rm.number
            Title        = [string]$rm.title
            Description  = [string]$rm.description
            OpenIssues   = [int]$rm.open_issues
            ClosedIssues = [int]$rm.closed_issues
        }
    }
    Add-Member -InputObject $base -NotePropertyName 'Milestone' -NotePropertyValue $milestone -Force
    return $base
}

# ============================================================================
# 區塊 2：分組（**PURE**——t16-offline-test.ps1 的誤併紅燈斷言直接打這一段）
# ============================================================================

function Group-FleetIssuesByWorkId {
    <#
      **PURE**。輸入已正規化的 AnchorIssues（帶 sc:work）／TicketIssues（帶 sc:ticket，含 .Milestone）
      陣列，輸出依 work-id 分組結果。不打網路、不讀檔，同一輸入永遠同一輸出。

      $BugGroupByMilestoneTitle：⚠️ 僅供紅燈驗證。開啟後票改用 `milestone.Title` 分組（複製 T-16 驗收②
      描述的錯誤行為：「未實作時以名稱分組會誤併」）——正式流程與 Get-FleetSnapshot 預設路徑絕不開啟。
    #>
    param(
        [array]$AnchorIssues,
        [array]$TicketIssues,
        [switch]$BugGroupByMilestoneTitle
    )
    $groups = @{}
    $unresolvedTickets = @()
    $duplicateAnchors = @()

    foreach ($a in $AnchorIssues) {
        $wid = Get-FleetWorkIdFromAnchorBody -Body $a.Body
        if (-not $wid) { continue }
        if ($groups.ContainsKey($wid) -and $null -ne $groups[$wid].AnchorIssue) {
            $duplicateAnchors += "$wid：$($groups[$wid].AnchorIssue.Repo)#$($groups[$wid].AnchorIssue.Number) 與 $($a.Repo)#$($a.Number) 皆宣稱同一 work-id"
            continue
        }
        if (-not $groups.ContainsKey($wid)) {
            $groups[$wid] = [pscustomobject]@{
                WorkId = $wid; AnchorIssue = $a
                ParticipatingRepos = (Get-ParticipatingReposFromBody -Body $a.Body)
                Tickets = @()
            }
        } else {
            $groups[$wid].AnchorIssue = $a
        }
    }

    foreach ($t in $TicketIssues) {
        $key = $null
        if ($BugGroupByMilestoneTitle) {
            if ($t.Milestone) { $key = $t.Milestone.Title }
        } else {
            if ($t.Milestone) { $key = Get-FleetWorkIdFromMilestoneDescription -Description $t.Milestone.Description }
        }
        if (-not $key) { $unresolvedTickets += $t; continue }
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [pscustomobject]@{
                WorkId = $key; AnchorIssue = $null; ParticipatingRepos = @(); Tickets = @()
            }
        }
        $groups[$key].Tickets += $t
    }

    return [pscustomobject]@{
        Groups             = $groups
        UnresolvedTickets  = (, $unresolvedTickets)
        DuplicateAnchors   = (, $duplicateAnchors)
    }
}

# ============================================================================
# 區塊 3：逐 repo milestone 進度（impure，可注入 fetcher 供離線測試）
# ============================================================================

function Get-FleetMilestoneRowsForWork {
    <#
      §4.1：逐 repo 分列的 milestone 原生進度百分比（不加權、不合成單一數字）。
      來源優先序（皆屬 §4.1 允許來源「milestone 原生欄位」，不算額外查詢類別之外的資訊）：
        ① 本次跨 repo search 已附帶的 ticket.Milestone（同一次查詢的隨附欄位，零額外成本）。
        ② ①未覆蓋到的參與 repo（如：該 repo 本輪無 open 票、或尚未開始），逐 repo 補一次
           milestone 列表查詢，**以 description 的 work-id 比對，不比對 title**（理由同區塊 1
           的 Get-FleetWorkIdFromMilestoneDescription 說明——title 可能撞名）。

      $MilestoneListFetcher：離線測試注入點，scriptblock (repo) -> 原始 milestone 陣列（模擬 REST
      回傳），提供時完全不打網路，可用來對「補查詢比對 description 而非 title」做決定性覆蓋率測試。
    #>
    param(
        [Parameter(Mandatory)][string]$WorkId,
        [array]$ParticipatingRepos,
        [array]$TicketsForWork,
        [hashtable]$Headers,
        $MilestoneListFetcher
    )
    $rowsByRepo = @{}

    foreach ($t in $TicketsForWork) {
        if ($t.Milestone -and -not $rowsByRepo.ContainsKey($t.Repo)) {
            $m = $t.Milestone
            $sum = [int]$m.OpenIssues + [int]$m.ClosedIssues
            $percent = if ($sum -gt 0) { [math]::Round(([int]$m.ClosedIssues / $sum) * 100, 0) } else { $null }
            $rowsByRepo[$t.Repo] = [pscustomobject]@{
                Repo = $t.Repo; QueryOk = $true; FailureDetail = $null; MilestoneFound = $true
                Title = $m.Title; OpenIssues = [int]$m.OpenIssues; ClosedIssues = [int]$m.ClosedIssues; PercentComplete = $percent
            }
        }
    }

    foreach ($repo in $ParticipatingRepos) {
        if ($rowsByRepo.ContainsKey($repo)) { continue }
        try {
            if ($MilestoneListFetcher) {
                $rawList = & $MilestoneListFetcher $repo
            } else {
                $url = "https://api.github.com/repos/$repo/milestones?state=all&per_page=100"
                $rawList = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
            }
            $list = ConvertTo-SafeArray -RawValue $rawList
            $found = $null
            foreach ($cand in $list) {
                $candWid = Get-FleetWorkIdFromMilestoneDescription -Description $cand.description
                if ($candWid -eq $WorkId) { $found = $cand; break }
            }
            if ($null -eq $found) {
                $rowsByRepo[$repo] = [pscustomobject]@{
                    Repo = $repo; QueryOk = $true; FailureDetail = $null; MilestoneFound = $false
                    Title = $null; OpenIssues = $null; ClosedIssues = $null; PercentComplete = $null
                }
                continue
            }
            $openN = [int]$found.open_issues; $closedN = [int]$found.closed_issues
            $percent = if (($openN + $closedN) -gt 0) { [math]::Round(($closedN / ($openN + $closedN)) * 100, 0) } else { $null }
            $rowsByRepo[$repo] = [pscustomobject]@{
                Repo = $repo; QueryOk = $true; FailureDetail = $null; MilestoneFound = $true
                Title = [string]$found.title; OpenIssues = $openN; ClosedIssues = $closedN; PercentComplete = $percent
            }
        } catch {
            $rowsByRepo[$repo] = [pscustomobject]@{
                Repo = $repo; QueryOk = $false; FailureDetail = "$($repo)：$($_.Exception.Message)"
                MilestoneFound = $false; Title = $null; OpenIssues = $null; ClosedIssues = $null; PercentComplete = $null
            }
        }
    }

    $orderedRows = @()
    foreach ($repo in $ParticipatingRepos) {
        if ($rowsByRepo.ContainsKey($repo)) { $orderedRows += $rowsByRepo[$repo] }
    }
    return , $orderedRows
}

# ============================================================================
# 區塊 4：待寫佇列（§4.6，唯讀；依 work-id 篩選 source 欄位）
# ============================================================================

function Read-FleetQueueInfoForWork {
    <# 比照 t09 Read-BoardQueueInfo 的三態（不存在／讀取失敗／N 筆），但依 payload.source 篩選出屬於本 work 的筆數。 #>
    param([Parameter(Mandatory)][string]$QueuePath, [Parameter(Mandatory)][string]$WorkId)
    if (-not (Test-Path -LiteralPath $QueuePath)) {
        return [pscustomobject]@{ Exists = $false; Count = $null; ParseError = $null }
    }
    try {
        $raw = Get-Content -LiteralPath $QueuePath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]@{ Exists = $true; Count = 0; ParseError = $null }
        }
        $parsedRaw = $raw | ConvertFrom-Json
        $items = ConvertTo-SafeArray -RawValue $parsedRaw
        $matched = @($items | Where-Object { $_.PSObject.Properties.Name -contains 'source' -and $_.source -eq $WorkId })
        return [pscustomobject]@{ Exists = $true; Count = $matched.Count; ParseError = $null }
    } catch {
        return [pscustomobject]@{ Exists = $true; Count = $null; ParseError = $_.Exception.Message }
    }
}

# ============================================================================
# 區塊 5：站別來源標註（包一層 t09 Get-StationLabelInfo，確保「站別來源不明」字樣恆出現於髒資料理由）
# ============================================================================

function Get-FleetStationInfoWithLabel {
    <#
      T-16 驗收⑥：「手動竄改過站別的工作 ⇒ 字卡紅燈標『站別來源不明』」。t09 Get-StationLabelInfo 在
      「anchor 無任何站別 label」情境已含此字樣；本函式補齊「anchor 帶多個互斥站別 label」與「anchor
      缺席」兩種情境，確保只要 IsDirty 即恆含「站別來源不明」四字（🚫 不修改 t09 原函式，用包裝取代）。
    #>
    param($AnchorIssue)
    if (-not $AnchorIssue) {
        return [pscustomobject]@{ Station = $null; IsDirty = $true; DirtyDetail = 'anchor 缺席或查詢失敗，站別來源不明' }
    }
    $info = Get-StationLabelInfo -Labels $AnchorIssue.Labels
    if ($info.IsDirty -and ($info.DirtyDetail -notmatch '站別來源不明')) {
        return [pscustomobject]@{ Station = $info.Station; IsDirty = $true; DirtyDetail = "$($info.DirtyDetail)（站別來源不明）" }
    }
    return $info
}

# ============================================================================
# 區塊 6：單張字卡 Model（**PURE**；直接餵給 t09 Build-WorkCardHtml，不新增任何面板欄位）
# ============================================================================

function New-FleetWorkCardModel {
    param(
        [Parameter(Mandatory)][string]$WorkId,
        $AnchorIssue,
        [array]$ParticipatingRepos,
        [array]$Tickets,
        [array]$MilestoneRows,
        [Parameter(Mandatory)]$QueueInfo,
        [Parameter(Mandatory)][datetime]$NowUtc,
        [switch]$NoReconcile,
        $CacheBaseline,
        [Parameter(Mandatory)][string]$LastFullSyncText
    )
    $stationInfo = Get-FleetStationInfoWithLabel -AnchorIssue $AnchorIssue
    $ticketDirty = Get-TicketDirtyStationLabels -Tickets $Tickets
    $statusLight =
        if ($AnchorIssue) {
            ConvertTo-StatusLight -AnchorIssue $AnchorIssue -StationInfo $stationInfo -Tickets $Tickets -TicketDirtyLabels $ticketDirty
        } else {
            [pscustomobject]@{ Color = 'red'; Reasons = @($stationInfo.DirtyDetail) }
        }
    $counts = Build-RunningAndStaleCounts -Tickets $Tickets -NowUtc $NowUtc

    $executors = @()
    foreach ($t in $Tickets) {
        if ($t.State -eq 'open' -and $t.HasAssignee) {
            $ex = Get-ExecutorFromBody -Body $t.Body
            if ($ex) { $executors += $ex }
        }
    }
    $executors = @($executors | Select-Object -Unique)

    $queueUntrusted = $QueueInfo.Exists -and ($QueueInfo.Count -is [int]) -and ($QueueInfo.Count -gt 0)
    $reconcileText =
        if ($NoReconcile) {
            $prevReconcile =
                if ($CacheBaseline -and ($CacheBaseline.PSObject.Properties.Name -contains 'lastReconcileTimeUtc') -and $CacheBaseline.lastReconcileTimeUtc) {
                    (([datetime]$CacheBaseline.lastReconcileTimeUtc).ToLocalTime()).ToString('yyyy-MM-dd HH:mm')
                } else { '（尚無對帳紀錄）' }
            "本次未對帳，沿用 $prevReconcile 結果"
        } else {
            '對帳：尚未實作（T-17 範圍），本欄位僅保留位置'
        }

    $primaryRepoText = if ($AnchorIssue) { $AnchorIssue.Repo } elseif ((ConvertTo-SafeArray -RawValue $ParticipatingRepos).Count -gt 0) { $ParticipatingRepos[0] } else { '（未知，anchor 缺席）' }

    # ⚠️ 陷阱②的變形（依 t09 render-board.ps1 檔頭同一段註解／t09 第 800-804 行的實測對比）：
    # if/elseif/else **表達式賦值**（`$x = if (...) {...} else {...}`）本身會對區塊輸出再做一次管線
    # 展開，1 元素陣列會被攤平成純量（下游 .Count 在 StrictMode 直接拋錯）。本欄位（OtherRepos）是
    # 陣列型別，改用**陳述式形式**（賦值寫在各分支內部）即可避開；本檔曾在此處真的踩過一次（開發期間
    # `Build-WorkCardHtml` 對 `$Model.OtherRepos.Count` 拋出「屬性 Count 找不到」，訊息與 t09 檔頭
    # 描述的陷阱②完全吻合），修正後回歸鎖在 t16-offline-test.ps1 群組 H。
    if ($AnchorIssue) {
        $otherRepos = @($ParticipatingRepos | Where-Object { $_ -ne $AnchorIssue.Repo })
    } elseif ((ConvertTo-SafeArray -RawValue $ParticipatingRepos).Count -gt 1) {
        $otherRepos = @($ParticipatingRepos | Select-Object -Skip 1)
    } else {
        $otherRepos = @()
    }

    $milestoneFailures = @($MilestoneRows | Where-Object { -not $_.QueryOk })

    return [pscustomobject]@{
        WorkId                = $WorkId
        WorkName              = if ($AnchorIssue) { ($AnchorIssue.Title -replace '\s*·\s*primary anchor\s*$', '') } else { "$WorkId（anchor 缺席，僅餘票，見紅燈理由）" }
        PrimaryRepo           = $primaryRepoText
        OtherRepos            = $otherRepos
        StepperHtml           = Build-StepperHtml -Station $stationInfo.Station
        RepoProgressHtml      = Build-RepoProgressHtml -MilestoneProgress $MilestoneRows
        ExecutorList          = $executors
        StatusColor           = $statusLight.Color
        StatusReasons         = $statusLight.Reasons
        RunningCount          = $counts.RunningCount
        StaleCount            = $counts.StaleCount
        IsLegacy              = ($AnchorIssue -and ($AnchorIssue.Labels -contains 'sc:legacy'))
        PendingWriteCount     = $QueueInfo.Count
        QueueExists           = $QueueInfo.Exists
        QueueParseError       = $QueueInfo.ParseError
        QueueUntrusted        = $queueUntrusted
        ReconcileDataTimeText = $reconcileText
        LastFullSyncText      = $LastFullSyncText
        AnchorRef             = if ($AnchorIssue) { "$($AnchorIssue.Repo)#$($AnchorIssue.Number)" } else { '（查無 anchor）' }
        IsStaleCard           = ($milestoneFailures.Count -gt 0)
        PartialDataCaveat     = ($milestoneFailures.Count -gt 0)
        # --- 以下為 T-16 內部簿記欄位，不進 HTML／不算面板欄位，僅供 Build-FleetBoardReport 組顯示快取用 ---
        StationLabel          = $stationInfo.Station
    }
}

# ============================================================================
# 區塊 7：Banner（多一種 disappeared kind；因需要多一種樣式對照，於此另立，不改 t09 Build-BannersHtml）
# ============================================================================

function Build-FleetBannersHtml {
    param([array]$ErrorStates)
    $sb = New-Object System.Text.StringBuilder
    foreach ($e in $ErrorStates) {
        $cls = switch ($e.Kind) {
            'query-failed' { 'banner banner--stale' }
            'incomplete' { 'banner banner--incomplete' }
            'empty' { 'banner banner--empty' }
            'no-baseline' { 'banner banner--no-baseline' }
            'disappeared' { 'banner banner--disappeared' }
            default { 'banner' }
        }
        $textEsc = ConvertTo-HtmlEncoded -Text $e.Text
        [void]$sb.Append("<div class=`"$cls`"><strong>$(ConvertTo-HtmlEncoded -Text $e.Title)</strong>$textEsc</div>`n")
    }
    return $sb.ToString()
}

# ============================================================================
# 區塊 8：頂層聚合（**PURE**；T-16 驗收①③④⑤⑥的整合測試 seam）
# ============================================================================

function Build-FleetBoardReport {
    <#
      **PURE**。輸入：$Snapshot（見檔頭 FLEET SNAPSHOT SCHEMA，可為真實或手造 mock）、$TemplateContent、
      $CacheBaseline（上一輪 §4.2 顯示快取物件，形狀＝下方 CacheData，或 $null＝無基線）、$NowLocal、
      $TimeZoneLabel、$NoReconcile（§4.5）、$SkipNoBaselineBanner（⚠️ 僅供紅燈驗證：強制不輸出
      「消失偵測不可用（無基線）」橫幅，正式流程禁用）。

      回傳 [pscustomobject]@{ Html; TextSummary; ErrorStates=@(...); CacheData=@{...}; CardsHtml }
      （CardsHtml 為測試用內部欄位，非面板欄位，供「刪除 artifact 後字卡內容不變」的比對用）。
    #>
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$TemplateContent,
        $CacheBaseline,
        [Parameter(Mandatory)][datetime]$NowLocal,
        [string]$TimeZoneLabel = 'local',
        [switch]$NoReconcile,
        [switch]$SkipNoBaselineBanner
    )

    $errorStates = @()
    $works = ConvertTo-SafeArray -RawValue $Snapshot.Works

    $hasHardQueryFailure = (-not $Snapshot.Ok)
    $milestoneFailuresAll = @()
    foreach ($w in $works) { $milestoneFailuresAll += @($w.MilestoneRows | Where-Object { -not $_.QueryOk }) }
    if ($milestoneFailuresAll.Count -gt 0) { $hasHardQueryFailure = $true }

    $lastSuccessText =
        if ($CacheBaseline -and ($CacheBaseline.PSObject.Properties.Name -contains 'lastFullSyncTimeUtc') -and $CacheBaseline.lastFullSyncTimeUtc) {
            (([datetime]$CacheBaseline.lastFullSyncTimeUtc).ToLocalTime()).ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel"
        } else { '（無上次成功紀錄）' }

    if ($hasHardQueryFailure) {
        $failedNames = @()
        if (-not $Snapshot.Ok) { $failedNames += "跨 repo search（$($Snapshot.FailureDetail)）" }
        foreach ($mf in $milestoneFailuresAll) { $failedNames += "milestone（$($mf.FailureDetail)）" }
        $text = "失敗對象：$($failedNames -join '；')。上次成功時間：$lastSuccessText。"
        $errorStates += [pscustomobject]@{ Kind = 'query-failed'; Title = '數據過期　'; Text = $text }
    }

    if ($Snapshot.HitPageCap) {
        $text = "跨 repo search 已觸頂：GitHub 回報總筆數 $($Snapshot.TotalCountReported)，本次僅取得 $($Snapshot.ResultCountThisRun) 筆（分頁上限已用盡）。上次成功完整同步時間：$lastSuccessText。"
        $errorStates += [pscustomobject]@{ Kind = 'incomplete'; Title = '資料可能不完整　'; Text = $text }
    }

    # --- §4.4「anchor 消失＝異常」：與顯示快取比對，比對鍵是 work-id，站別非 sc:station-done 才算異常 ---
    $noBaseline = ($null -eq $CacheBaseline)
    $currentAnchorWorkIds = @($works | Where-Object { $_.AnchorIssue } | ForEach-Object { $_.WorkId })

    $disappeared = @()
    if (-not $noBaseline -and ($CacheBaseline.PSObject.Properties.Name -contains 'works') -and $CacheBaseline.works) {
        $baselineWorks = ConvertTo-SafeArray -RawValue $CacheBaseline.works
        foreach ($bw in $baselineWorks) {
            if ($bw.station -eq 'sc:station-done') { continue }
            if ($currentAnchorWorkIds -notcontains $bw.workId) {
                $disappeared += [pscustomobject]@{ WorkId = $bw.workId; LastSeenStation = $bw.station }
            }
        }
    }
    foreach ($d in $disappeared) {
        $lastSeenText = if ($d.LastSeenStation) { $d.LastSeenStation } else { '（未知，上次亦為髒資料）' }
        $errorStates += [pscustomobject]@{ Kind = 'disappeared'; Title = '工作消失　'; Text = "work ID：$($d.WorkId)｜上次所見站別：$lastSeenText" }
    }

    if ($noBaseline -and -not $SkipNoBaselineBanner) {
        $errorStates += [pscustomobject]@{ Kind = 'no-baseline'; Title = '消失偵測不可用（無基線）　'; Text = '面板快取尚無基線（首次 render 或快取已重建），無法比對是否有工作消失；此為降級提示，不代表任何工作異常。' }
    }

    $queryDesc = if ($Snapshot.PSObject.Properties.Name -contains 'QueryDescription' -and $Snapshot.QueryDescription) { $Snapshot.QueryDescription } else { '跨 repo 聚合（sc:work／sc:ticket, open）' }
    $isEmpty = ($works.Count -eq 0) -and (-not $hasHardQueryFailure)

    if ($isEmpty) {
        # 'empty' 本身不產生 banner 文字（空狀態文案由 Build-EmptyStateCardHtml 承載），只作為
        # ErrorStates 的內部標記供呼叫端判斷「這輪是零筆」；比照 t09 isEmpty 分支的相同做法，
        # 組 banner HTML 時排除它，避免印出一格空白 banner。
        $errorStates += [pscustomobject]@{ Kind = 'empty'; Title = ''; Text = '' }
        $bannersHtml = Build-FleetBannersHtml -ErrorStates (@($errorStates | Where-Object { $_.Kind -ne 'empty' }))
        $mainHtml = Build-EmptyStateCardHtml -QueryDescription $queryDesc
        $textSummary = "目前無 active work（查詢條件：$queryDesc）。" + $(if ($noBaseline -and -not $SkipNoBaselineBanner) { ' 消失偵測不可用（無基線）。' } else { '' }) + $(if ($disappeared.Count -gt 0) { " 另偵測到 $($disappeared.Count) 個工作消失。" } else { '' })
        $cacheData = @{
            lastFullSyncTimeUtc = if (-not $hasHardQueryFailure) { $Snapshot.NowUtc.ToString('o') } elseif ($noBaseline) { $null } else { $CacheBaseline.lastFullSyncTimeUtc }
            lastReconcileTimeUtc = if ($noBaseline) { $null } elseif ($CacheBaseline.PSObject.Properties.Name -contains 'lastReconcileTimeUtc') { $CacheBaseline.lastReconcileTimeUtc } else { $null }
            works = @()
        }
        $genAt = $NowLocal.ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel"
        $cacheJson = (ConvertTo-Json -InputObject $cacheData -Depth 6 -Compress)
        $cacheJsonEsc = $cacheJson -replace '&', '&amp;' -replace '"', '&quot;'
        return [pscustomobject]@{
            Html        = ($TemplateContent.Replace('{{GENERATED_AT}}', $genAt).Replace('{{BANNERS_HTML}}', $bannersHtml).Replace('{{MAIN_CONTENT_HTML}}', $mainHtml).Replace('{{CACHE_DATA_JSON_ESCAPED}}', $cacheJsonEsc))
            TextSummary = $textSummary
            ErrorStates = @($errorStates | ForEach-Object { $_.Kind })
            CacheData   = $cacheData
            CardsHtml   = ''
        }
    }

    $cardsHtml = New-Object System.Text.StringBuilder
    $textLines = @()
    $cacheWorks = @()
    foreach ($w in $works) {
        $milestoneFailuresForWork = @($w.MilestoneRows | Where-Object { -not $_.QueryOk })
        $fullSyncOkForWork = ($null -ne $w.AnchorIssue) -and ($milestoneFailuresForWork.Count -eq 0) -and (-not $hasHardQueryFailure)
        $lastFullSyncTextForWork = if ($fullSyncOkForWork) { $NowLocal.ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel" } else { $lastSuccessText }

        $model = New-FleetWorkCardModel -WorkId $w.WorkId -AnchorIssue $w.AnchorIssue -ParticipatingRepos $w.ParticipatingRepos `
            -Tickets $w.Tickets -MilestoneRows $w.MilestoneRows -QueueInfo $w.QueueInfo -NowUtc $Snapshot.NowUtc `
            -NoReconcile:$NoReconcile -CacheBaseline $CacheBaseline -LastFullSyncText $lastFullSyncTextForWork

        [void]$cardsHtml.Append((Build-WorkCardHtml -Model $model))
        $textLines += "工作：$($model.WorkName)（$($model.WorkId)）｜狀態燈：$($model.StatusColor)$(if ($model.StatusReasons.Count -gt 0) { '（' + ($model.StatusReasons -join '；') + '）' })｜在跑：$($model.RunningCount)｜停滯：$($model.StaleCount)"

        if ($null -ne $w.AnchorIssue) {
            $cacheWorks += @{ workId = $w.WorkId; station = $model.StationLabel; primaryRepo = $model.PrimaryRepo }
        }
    }

    $mainHtml = $cardsHtml.ToString()
    $bannersHtml = Build-FleetBannersHtml -ErrorStates $errorStates
    foreach ($e in $errorStates) { $textLines += "[$($e.Kind)] $($e.Title)$($e.Text)" }
    $textSummary = ($textLines -join "`n")

    $fullSyncOkOverall = (-not $hasHardQueryFailure)
    $cacheData = @{
        lastFullSyncTimeUtc  = if ($fullSyncOkOverall) { $Snapshot.NowUtc.ToString('o') } elseif ($noBaseline) { $null } else { $CacheBaseline.lastFullSyncTimeUtc }
        lastReconcileTimeUtc = if ($noBaseline) { $null } elseif ($CacheBaseline.PSObject.Properties.Name -contains 'lastReconcileTimeUtc') { $CacheBaseline.lastReconcileTimeUtc } else { $null }
        works                = $cacheWorks
    }
    $cacheJson = (ConvertTo-Json -InputObject $cacheData -Depth 6 -Compress)
    $cacheJsonEsc = $cacheJson -replace '&', '&amp;' -replace '"', '&quot;'
    $genAt = $NowLocal.ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel"

    $html = $TemplateContent.Replace('{{GENERATED_AT}}', $genAt).Replace('{{BANNERS_HTML}}', $bannersHtml).Replace('{{MAIN_CONTENT_HTML}}', $mainHtml).Replace('{{CACHE_DATA_JSON_ESCAPED}}', $cacheJsonEsc)

    return [pscustomobject]@{
        Html        = $html
        TextSummary = $textSummary
        ErrorStates = @($errorStates | ForEach-Object { $_.Kind })
        CacheData   = $cacheData
        CardsHtml   = $mainHtml
    }
}

# ============================================================================
# 區塊 9：impure 抓資料（跨 repo search＋分組＋逐 repo 進度＋佇列）
# ============================================================================

function Get-FleetSnapshot {
    <#
      impure。一次跨 repo issue search 撈 `sc:work`／`sc:ticket` 的 open issues（§4.2 硬規則：
      「一次跨 repo issue search」——分頁是同一次查詢的延續，不算額外查詢）。
      ⚠️ 本函式未在本沙盒實跑（環境無 GitHub 連線，依指示不得呼叫真實 API）；離線測試只測
      Group-FleetIssuesByWorkId／Get-FleetMilestoneRowsForWork（注入 fetcher）／Build-FleetBoardReport
      三個 seam，本函式本身待有真實 PAT 的本機環境驗證（誠實聲明，見 README「deferred」一節）。
    #>
    param(
        [Parameter(Mandatory)][array]$Repos,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][string]$QueuePath,
        [int]$MaxPages = 5,
        [int]$PerPage = 100,
        [switch]$BugGroupByMilestoneTitle
    )
    $nowUtc = [datetime]::UtcNow
    $repoClauses = ($Repos | ForEach-Object { "repo:$_" }) -join ' '
    $q = "$repoClauses is:issue is:open (label:`"sc:work`" OR label:`"sc:ticket`")"

    $allItems = @()
    $totalCount = $null
    $ok = $true
    $failureDetail = $null
    $hitPageCap = $false

    try {
        for ($page = 1; $page -le $MaxPages; $page++) {
            $url = "https://api.github.com/search/issues?q=" + [uri]::EscapeDataString($q) + "&per_page=$PerPage&page=$page"
            $resp = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
            if ($null -eq $totalCount -and $resp.PSObject.Properties.Name -contains 'total_count') { $totalCount = [int]$resp.total_count }
            $chunkRaw = $resp.items
            $chunk = ConvertTo-SafeArray -RawValue $chunkRaw
            $allItems += $chunk
            if ($chunk.Count -lt $PerPage) { break }
            if ($page -eq $MaxPages -and $chunk.Count -eq $PerPage) { $hitPageCap = $true }
        }
    } catch {
        $ok = $false
        $failureDetail = "跨 repo search（$($Repos -join ', ')）：$($_.Exception.Message)"
    }
    if ($null -ne $totalCount -and $totalCount -gt $allItems.Count) { $hitPageCap = $true }

    $anchorIssues = @()
    $ticketIssues = @()
    foreach ($raw in $allItems) {
        $issue = ConvertTo-FleetIssue -RawIssue $raw
        if ($issue.Labels -contains 'sc:work') { $anchorIssues += $issue }
        elseif ($issue.Labels -contains 'sc:ticket') { $ticketIssues += $issue }
    }

    $grouped = Group-FleetIssuesByWorkId -AnchorIssues $anchorIssues -TicketIssues $ticketIssues -BugGroupByMilestoneTitle:$BugGroupByMilestoneTitle

    $works = @()
    foreach ($key in $grouped.Groups.Keys) {
        $g = $grouped.Groups[$key]
        $participating = ConvertTo-SafeArray -RawValue $g.ParticipatingRepos
        if ($participating.Count -eq 0) {
            $ticketRepos = @($g.Tickets | ForEach-Object { $_.Repo } | Select-Object -Unique)
            $participating = $ticketRepos
        }
        $milestoneRows = Get-FleetMilestoneRowsForWork -WorkId $g.WorkId -ParticipatingRepos $participating -TicketsForWork $g.Tickets -Headers $Headers
        $queueInfo = Read-FleetQueueInfoForWork -QueuePath $QueuePath -WorkId $g.WorkId
        $works += [pscustomobject]@{
            WorkId = $g.WorkId; AnchorIssue = $g.AnchorIssue; ParticipatingRepos = $participating
            Tickets = $g.Tickets; MilestoneRows = $milestoneRows; QueueInfo = $queueInfo
        }
    }

    return [pscustomobject]@{
        NowUtc                 = $nowUtc
        Ok                     = $ok
        FailureDetail          = $failureDetail
        ResultCountThisRun     = if ($ok) { $allItems.Count } else { $null }
        TotalCountReported     = $totalCount
        HitPageCap             = $hitPageCap
        QueryDescription       = "跨 repo：$($Repos -join ', ')"
        Works                  = $works
        UnresolvedTicketsCount = (ConvertTo-SafeArray -RawValue $grouped.UnresolvedTickets).Count
        DuplicateAnchorNotes   = $grouped.DuplicateAnchors
    }
}

# ============================================================================
# 區塊 10：頂層入口（impure；供本機手動執行與 build-sample-fleet-board.ps1／未來 SKILL.md 整合呼叫）
# ============================================================================

function Invoke-FleetBoardRender {
    param(
        [array]$Repos,
        [string]$PatPath,
        [string]$QueuePath,
        [string]$TemplatePath,
        [string]$OutputPath,
        [switch]$NoReconcile,
        [int]$MaxPages = 5,
        [int]$PerPage = 100,
        [switch]$BugGroupByMilestoneTitle,
        [switch]$SkipNoBaselineBanner,
        # 測試／範例產生專用：提供 mock snapshot 時完全略過網路呼叫（Get-FleetSnapshot 不會被呼叫）
        $MockSnapshot
    )
    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        throw "樣板檔不存在：$TemplatePath"
    }
    $templateContent = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
    $cacheBaseline = Read-CacheBaselineFromExistingArtifact -OutputPath $OutputPath

    if ($MockSnapshot) {
        $snapshot = $MockSnapshot
    } else {
        $token = Read-PatToken -PatPath $PatPath
        $headers = Get-GithubHeaders -Token $token -UserAgent 'station-command-t16-fleet-board'
        $snapshot = Get-FleetSnapshot -Repos $Repos -Headers $headers -QueuePath $QueuePath -MaxPages $MaxPages -PerPage $PerPage -BugGroupByMilestoneTitle:$BugGroupByMilestoneTitle
    }

    $nowLocal = (Get-Date)
    $tzLabel = "UTC$(('{0:+00;-00}' -f ((Get-Date).ToUniversalTime() - (Get-Date)).Hours))"

    $report = Build-FleetBoardReport -Snapshot $snapshot -TemplateContent $templateContent -CacheBaseline $cacheBaseline `
        -NowLocal $nowLocal -TimeZoneLabel $tzLabel -NoReconcile:$NoReconcile -SkipNoBaselineBanner:$SkipNoBaselineBanner

    $saveResult = Save-StationBoardArtifact -Html $report.Html -OutputPath $OutputPath

    if (-not $saveResult.Ok) {
        Write-Host $report.TextSummary
        Write-Warning "面板未更新，畫面內容已過期（寫入失敗：$($saveResult.Detail)）"
    } else {
        Write-Host $report.TextSummary
    }

    return [pscustomobject]@{
        Report      = $report
        SaveResult  = $saveResult
        OutputPath  = $OutputPath
        ErrorStates = $report.ErrorStates
    }
}

# ============================================================================
# 進入點
# ============================================================================

if (-not $T16FunctionsOnly) {
    Set-ConsoleUtf8
    if (-not $T16Repos) {
        throw "請提供 -T16Repos（或改用 -T16FunctionsOnly dot-source 本檔供測試呼叫）"
    }
    Invoke-FleetBoardRender -Repos $T16Repos -PatPath $T16PatPath -QueuePath $T16QueuePath -TemplatePath $T16TemplatePath `
        -OutputPath $T16OutputPath -NoReconcile:$T16NoReconcile -MaxPages $T16MaxPages -PerPage $T16PerPage `
        -BugGroupByMilestoneTitle:$T16BugGroupByMilestoneTitle -SkipNoBaselineBanner:$T16SkipNoBaselineBanner
}
