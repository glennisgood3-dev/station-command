#requires -Version 5.1
<#
.SYNOPSIS
    T-09 · render-board.ps1 — station-command 面板核心 render 器（單 work 字卡＋四種異常狀態；已併入 T-23 待寫揭露）。

.DESCRIPTION
    依 Spec_station-command_v1.8.md §4.1／§4.2／§4.4／§4.5／§4.6 定案。§5.0 / §2 邊界裁定：面板 HTML 由
    `/station-board` 從既有 GitHub 資料**機械性 render**（欄位對應固定、無內容創作）⇒ 屬編排輸出，不受
    No-Hands 管轄——本檔即該「render 器」本身，交付的是產生器，不是手寫死的靜態 HTML。

    刻意把「抓資料」（不純，打 GitHub REST API／讀本機檔）與「算面板」（純函式）切開，理由：
    §4.4 的四種錯誤狀態必須能在沙盒離線、不連網的情況下被紮實驗證（t09-offline-test.ps1），純函式化是
    唯一能不靠真實 GitHub 斷網/假 repo 名等外部條件、仍能 100% 決定性重現四種狀態的做法。

        Get-StationBoardSnapshot   impure。打 GitHub REST API（issues／search／milestones）＋ 讀待寫佇列檔，
                                    組出一份「原始快照」物件（schema 見下方 SNAPSHOT SCHEMA）。任何單一子查詢
                                    失敗皆被個別捕捉，不讓整支函式擲例外中斷——查詢失敗本身就是要顯示的狀態
                                    之一，不是程式錯誤。
        Build-StationBoardReport   **pure**。只吃「快照」物件（可以是上面函式的真實回傳值，也可以是離線測試
                                    手造的 mock 物件——形狀相同即可）＋ 顯示快取（上一輪的 §4.2 基線）＋現在
                                    時間，算出 Html／TextSummary／Banners／Card model／ErrorStates，不碰網路、
                                    不碰檔案系統，同一輸入永遠同一輸出。t09-offline-test.ps1 只測這個函式。
        Save-StationBoardArtifact  impure。把 Html 字串寫到磁碟；獨立成一個函式方便測試「面板寫入失敗」
                                    （指向唯讀或不存在的目錄即可觸發真實 IO 例外，不需要 mock）。
        Invoke-StationBoardRender  impure。串接以上三者的頂層入口，也是 SKILL.md／t09-test.ps1／
                                    run／gate 的無對帳刷新呼叫介面（§4.5：兩者皆呼叫本函式，唯一寫面板實作
                                    點不變，只是 -NoReconcile 開關不同）。

    ⚠️ PS 5.1 + StrictMode 三個已知陷阱（依 T-21/T-10 先例，本檔全程套用）：
      1. 單一物件沒有 `.Count` 屬性 ⇒ 一律先用 ConvertTo-SafeArray 包過再用 .Count。
      2. `,@()` 用在「同一層直接賦值」是「1 元素陣列（該元素是空陣列）」，不是空陣列本身；
         只有在「跨函式邊界 return」時才需要逗號前綴保陣列型別，區域賦值一律直接 `@()`。
      3. `@(函式呼叫本身)` 會把該函式回傳的 0 筆結果錯誤包成「1 筆、內容是 $null」——
         必須先把函式回傳值賦值給變數，再對「已賦值的變數」包 `@()` 或呼叫 ConvertTo-SafeArray。

.NOTES
    白名單依 Spec §2：讀 GitHub（search／issues／milestones／issue body 欄位）｜讀本機待寫佇列檔（§4.6）｜
    寫面板 artifact｜文字輸出。🚫 本檔不呼叫任何 GitHub 寫入端點（無 PUT/POST/PATCH/DELETE），
    dispatch project-manager（完整模式對帳）屬 T-17 範圍，本票只留欄位位置，不在本檔實作。

    SNAPSHOT SCHEMA（Get-StationBoardSnapshot 的回傳形狀 = 離線測試手造 mock 時必須遵守的形狀）：

    [pscustomobject]@{
        WorkId                      = 'W-xxx'
        PrimaryRepo                 = 'owner/repo'
        ParticipatingReposDeclared  = @('owner/repo', ...)   # 來自 anchor body（真相源），非使用者輸入
        NowUtc                      = [datetime]（本輪查詢嘗試時間，UTC）
        AnchorQuery = [pscustomobject]@{
            Ok             = $true/$false   # 查詢本身是否成功「執行完成」（不含「查到與否」）
            Found          = $true/$false   # Ok=$true 時才有意義：是否真的查到 anchor
            FailureDetail  = $null 或 string  # Ok=$false 時，具名失敗對象與原因
            Issue          = $null 或 [pscustomobject]@{ Number; Title; Body; Labels=@(...); State; UpdatedAtUtc; HtmlUrl }
        }
        TicketsQuery = [pscustomobject]@{
            Ok                  = $true/$false
            FailedRepos         = @('owner/repo: <detail>', ...)   # 逐 repo 具名失敗（部分成功時用）
            Tickets             = @( [pscustomobject]@{ Number; Repo; Title; Body; Labels=@(...); State;
                                       UpdatedAtUtc; HasAssignee } , ... )
            ResultCountThisRun  = <int 或 $null>   # Ok=$false 時可為 $null
            TotalCountReported  = <int 或 $null>   # GitHub search 的 total_count（用於觸頂判定）
            HitPageCap          = $true/$false     # TotalCountReported > Tickets.Count
        }
        MilestoneProgress = @(
            [pscustomobject]@{ Repo; QueryOk; FailureDetail; MilestoneFound; Title; OpenIssues; ClosedIssues;
                                PercentComplete }
            , ...
        )
        Queue = [pscustomobject]@{ Exists; Count; Path; ParseError }
    }
#>

[CmdletBinding()]
param(
    # 只載入函式、不執行 render（供 t09-offline-test.ps1／t09-test.ps1 dot-source 本檔時使用）
    [switch]$FunctionsOnly,

    [string]$WorkId,
    [string]$PrimaryRepo,
    [int]$AnchorIssue,
    [string[]]$ParticipatingRepos,
    [string]$PatPath = "$PSScriptRoot/pat.txt",
    [string]$QueuePath = "$PSScriptRoot/../t21/queue.json",
    [string]$TemplatePath = "$PSScriptRoot/board-template.html",
    [string]$OutputPath = "$PSScriptRoot/station-board.html",
    [switch]$NoReconcile,
    [int]$MaxPages = 3,
    [int]$PerPage = 100,
    [switch]$SkipErrorStateHandling
)

Set-StrictMode -Version Latest

# ============================================================================
# 區塊 0：共用小工具（BOM／console／PAT／安全陣列包裝）
# ============================================================================

$Script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Set-ConsoleUtf8 {
    try {
        [Console]::OutputEncoding = $Script:Utf8Bom
        $Global:OutputEncoding = $Script:Utf8Bom
    } catch {
        Write-Warning "無法設定主控台輸出編碼，繼續執行：$($_.Exception.Message)"
    }
}

function Write-Utf8BomFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Script:Utf8Bom)
}

function Read-PatToken {
    param([Parameter(Mandatory)][string]$PatPath)
    if (-not (Test-Path -LiteralPath $PatPath)) {
        throw "PAT 檔案不存在：$PatPath"
    }
    $token = (Get-Content -LiteralPath $PatPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "PAT 檔案內容為空：$PatPath"
    }
    return $token
}

function Get-GithubHeaders {
    param([Parameter(Mandatory)][string]$Token, [string]$UserAgent = 'station-command-t09-board')
    return @{
        'Authorization'        = "Bearer $Token"
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = $UserAgent
    }
}

# 陷阱③的唯一安全解法：呼叫端必須先把函式回傳值賦值給變數，才可以呼叫本函式；
# 🚫 不得直接 `ConvertTo-SafeArray -RawValue (Get-Foo)` 對函式呼叫本身包裝。
function ConvertTo-SafeArray {
    param($RawValue)
    if ($null -eq $RawValue) { return , @() }
    return , @($RawValue)
}

# ============================================================================
# 區塊 1：待寫佇列讀取（§4.6／T-23 併入）
# ============================================================================

function Read-BoardQueueInfo {
    <#
      回傳 [pscustomobject]@{ Exists; Count; Path; ParseError }。
      - 檔案不存在 ⇒ Exists=$false（合法狀態，字卡須顯示「待寫佇列不存在」而非 0，§4.6 逐字規定）。
      - 檔案存在但 JSON 壞掉 ⇒ Exists=$true, Count=$null, ParseError=<訊息>（🚫 不得靜默當成 0 筆）。
      - 本函式只讀，不驗證佇列項 schema 細節（那是 T-21 apply-queue.ps1 的職責），只算「筆數」供揭露。
    #>
    param([Parameter(Mandatory)][string]$QueuePath)

    if (-not (Test-Path -LiteralPath $QueuePath)) {
        return [pscustomobject]@{ Exists = $false; Count = $null; Path = $QueuePath; ParseError = $null }
    }
    try {
        $raw = Get-Content -LiteralPath $QueuePath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]@{ Exists = $true; Count = 0; Path = $QueuePath; ParseError = $null }
        }
        $parsedRaw = $raw | ConvertFrom-Json
        $items = ConvertTo-SafeArray -RawValue $parsedRaw
        return [pscustomobject]@{ Exists = $true; Count = $items.Count; Path = $QueuePath; ParseError = $null }
    } catch {
        return [pscustomobject]@{ Exists = $true; Count = $null; Path = $QueuePath; ParseError = $_.Exception.Message }
    }
}

# ============================================================================
# 區塊 2：GitHub 讀取（impure；四種錯誤狀態的量測源頭）
# ============================================================================

function ConvertTo-BoardIssue {
    # 把 REST 回傳的 issue 物件正規化成 Snapshot schema 所需的最小欄位集合
    param([Parameter(Mandatory)]$RawIssue, [string]$RepoOverride)
    $labels = ConvertTo-SafeArray -RawValue $RawIssue.labels
    $labelNames = @($labels | ForEach-Object { $_.name })
    $hasAssignee = $false
    if ($RawIssue.PSObject.Properties.Name -contains 'assignees') {
        $assignees = ConvertTo-SafeArray -RawValue $RawIssue.assignees
        $hasAssignee = $assignees.Count -gt 0
    }
    if (-not $hasAssignee -and $RawIssue.PSObject.Properties.Name -contains 'assignee' -and $null -ne $RawIssue.assignee) {
        $hasAssignee = $true
    }
    $repo = $RepoOverride
    if ([string]::IsNullOrWhiteSpace($repo) -and $RawIssue.PSObject.Properties.Name -contains 'repository_url') {
        # repository_url 形如 https://api.github.com/repos/<owner>/<repo>
        $parts = $RawIssue.repository_url -split '/repos/'
        if ($parts.Count -eq 2) { $repo = $parts[1] }
    }
    return [pscustomobject]@{
        Number       = [int]$RawIssue.number
        Repo         = $repo
        Title        = [string]$RawIssue.title
        Body         = [string]$RawIssue.body
        Labels       = $labelNames
        State        = [string]$RawIssue.state
        UpdatedAtUtc = [datetime]$RawIssue.updated_at
        HasAssignee  = $hasAssignee
        HtmlUrl      = [string]$RawIssue.html_url
    }
}

function Get-BoardAnchorQuery {
    <# 取得 primary anchor：優先用 -AnchorIssue 直讀（GET，最準確）；未提供時用 search 以 work-id 比對 body。 #>
    param(
        [Parameter(Mandatory)][string]$PrimaryRepo,
        [int]$AnchorIssue,
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][hashtable]$Headers
    )
    try {
        if ($AnchorIssue -gt 0) {
            $url = "https://api.github.com/repos/$PrimaryRepo/issues/$AnchorIssue"
            $raw = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
            $issue = ConvertTo-BoardIssue -RawIssue $raw -RepoOverride $PrimaryRepo
            return [pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $issue }
        }
        # 沒給編號 ⇒ 以 search 找 primary repo 內帶 sc:work 且 body 含該 work-id 的 issue
        $q = "repo:$PrimaryRepo is:issue label:`"sc:work`" in:body `"work-id: $WorkId`""
        $url = "https://api.github.com/search/issues?q=" + [uri]::EscapeDataString($q) + "&per_page=5"
        $resp = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
        $itemsRaw = $resp.items
        $items = ConvertTo-SafeArray -RawValue $itemsRaw
        if ($items.Count -eq 0) {
            return [pscustomobject]@{ Ok = $true; Found = $false; FailureDetail = $null; Issue = $null }
        }
        $issue = ConvertTo-BoardIssue -RawIssue $items[0] -RepoOverride $PrimaryRepo
        return [pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $issue }
    } catch {
        $detail = "$PrimaryRepo：$($_.Exception.Message)"
        return [pscustomobject]@{ Ok = $false; Found = $false; FailureDetail = $detail; Issue = $null }
    }
}

function Get-BoardTicketsQuery {
    <#
      一次跨 repo issue search：open、label:sc:ticket、milestone 標題等於 WorkId，跨全部參與 repo。
      §4.1 硬規則：「一次跨 repo issue search」——本函式對外只發一次 search 呼叫（分頁除外，分頁是同一次
      查詢的延續，不是額外查詢）。
    #>
    param(
        [array]$ParticipatingRepos,
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][hashtable]$Headers,
        [int]$MaxPages = 3,
        [int]$PerPage = 100
    )
    $repoClauses = ($ParticipatingRepos | ForEach-Object { "repo:$_" }) -join ' '
    $q = "$repoClauses is:issue is:open label:`"sc:ticket`" milestone:`"$WorkId`""

    $allItems = @()
    $totalCount = $null
    $failedRepos = @()
    $ok = $true
    $hitPageCap = $false

    try {
        for ($page = 1; $page -le $MaxPages; $page++) {
            $url = "https://api.github.com/search/issues?q=" + [uri]::EscapeDataString($q) + "&per_page=$PerPage&page=$page"
            $resp = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
            if ($null -eq $totalCount -and $resp.PSObject.Properties.Name -contains 'total_count') {
                $totalCount = [int]$resp.total_count
            }
            $chunkRaw = $resp.items
            $chunk = ConvertTo-SafeArray -RawValue $chunkRaw
            $allItems += $chunk
            if ($chunk.Count -lt $PerPage) { break }
            if ($page -eq $MaxPages -and $chunk.Count -eq $PerPage) {
                # 還沒讀完就撞到頁數上限 ⇒ 有截斷風險，留給呼叫端用 total_count 比對確認
                $hitPageCap = $true
            }
        }
    } catch {
        $ok = $false
        $failedRepos += "search（$($ParticipatingRepos -join ', ')）：$($_.Exception.Message)"
    }

    $tickets = @()
    foreach ($rawItem in $allItems) {
        $tickets += (ConvertTo-BoardIssue -RawIssue $rawItem)
    }

    if ($null -ne $totalCount -and $totalCount -gt $tickets.Count) {
        $hitPageCap = $true
    }

    return [pscustomobject]@{
        Ok                 = $ok
        FailedRepos        = $failedRepos
        Tickets            = $tickets
        ResultCountThisRun = if ($ok) { $tickets.Count } else { $null }
        TotalCountReported = $totalCount
        HitPageCap         = $hitPageCap
    }
}

function Get-BoardMilestoneProgress {
    <# 逐 repo 分列 milestone 原生進度（§4.1：不加權、不合成單一數字——每個 repo 各自的 % 各自算，不跨 repo 合併）。 #>
    param(
        [array]$ParticipatingRepos,
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][hashtable]$Headers
    )
    $results = @()
    foreach ($repo in $ParticipatingRepos) {
        try {
            $url = "https://api.github.com/repos/$repo/milestones?state=all&per_page=100"
            $rawResp = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
            $milestones = ConvertTo-SafeArray -RawValue $rawResp
            $found = $milestones | Where-Object { $_.title -eq $WorkId } | Select-Object -First 1
            if ($null -eq $found) {
                $results += [pscustomobject]@{
                    Repo = $repo; QueryOk = $true; FailureDetail = $null; MilestoneFound = $false
                    Title = $null; OpenIssues = $null; ClosedIssues = $null; PercentComplete = $null
                }
                continue
            }
            $openN = [int]$found.open_issues
            $closedN = [int]$found.closed_issues
            $percent = $null
            if (($openN + $closedN) -gt 0) {
                $percent = [math]::Round(($closedN / ($openN + $closedN)) * 100, 0)
            }
            $results += [pscustomobject]@{
                Repo = $repo; QueryOk = $true; FailureDetail = $null; MilestoneFound = $true
                Title = $found.title; OpenIssues = $openN; ClosedIssues = $closedN; PercentComplete = $percent
            }
        } catch {
            $results += [pscustomobject]@{
                Repo = $repo; QueryOk = $false; FailureDetail = "$($repo)：$($_.Exception.Message)"
                MilestoneFound = $false; Title = $null; OpenIssues = $null; ClosedIssues = $null; PercentComplete = $null
            }
        }
    }
    return , $results
}

function Get-StationBoardSnapshot {
    <# impure 頂層抓資料函式。串接以上三個查詢＋佇列讀取，組出 Snapshot（schema 見檔頭文件）。 #>
    param(
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][string]$PrimaryRepo,
        [int]$AnchorIssue,
        [string[]]$ParticipatingRepos,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][string]$QueuePath,
        [int]$MaxPages = 3,
        [int]$PerPage = 100
    )
    $nowUtc = [datetime]::UtcNow

    $anchorQuery = Get-BoardAnchorQuery -PrimaryRepo $PrimaryRepo -AnchorIssue $AnchorIssue -WorkId $WorkId -Headers $Headers

    # 參與 repo 全集的真相源＝anchor body（§3.1／T-07 templates.md §2）；找不到 anchor 或 body 解析不出來時，
    # 退回呼叫端手動提供的 -ParticipatingRepos（若也沒給，至少含 PrimaryRepo 自身，不得整段留空）。
    $participating = @()
    if ($anchorQuery.Ok -and $anchorQuery.Found -and $anchorQuery.Issue) {
        $participating = Get-ParticipatingReposFromBody -Body $anchorQuery.Issue.Body
    }
    if ($participating.Count -eq 0) {
        if ($ParticipatingRepos -and $ParticipatingRepos.Count -gt 0) {
            $participating = @($ParticipatingRepos)
        } else {
            $participating = @($PrimaryRepo)
        }
    }

    $ticketsQuery = Get-BoardTicketsQuery -ParticipatingRepos $participating -WorkId $WorkId -Headers $Headers -MaxPages $MaxPages -PerPage $PerPage
    $milestoneProgress = Get-BoardMilestoneProgress -ParticipatingRepos $participating -WorkId $WorkId -Headers $Headers
    $queue = Read-BoardQueueInfo -QueuePath $QueuePath

    return [pscustomobject]@{
        WorkId                     = $WorkId
        PrimaryRepo                = $PrimaryRepo
        ParticipatingReposDeclared = $participating
        NowUtc                     = $nowUtc
        AnchorQuery                = $anchorQuery
        TicketsQuery               = $ticketsQuery
        MilestoneProgress          = $milestoneProgress
        Queue                      = $queue
    }
}

function Get-ParticipatingReposFromBody {
    <# 解析 anchor body 的 participating-repos 區塊（T-07 templates.md §2 格式）。找不到則回空陣列。 #>
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return @() }
    $lines = $Body -split "`r?`n"
    $inBlock = $false
    $repos = @()
    foreach ($line in $lines) {
        if ($line -match '^\s*participating-repos\s*:\s*$') { $inBlock = $true; continue }
        if ($inBlock) {
            if ($line -match '^\s*-\s*([^\s#]+)') {
                $repos += $Matches[1]
                continue
            }
            # 區塊只延續到第一個不是 "- xxx" 的行（含空白行）
            break
        }
    }
    return , @($repos)
}

function Get-ExecutorFromBody {
    <#
      §4.1：「當前 executor（讀票／anchor body 的 executor 欄位，不讀 assignee）」。
      T-12（寫 executor 欄位者）尚未出貨，票 body 尚無固定序列化格式的正典來源，本函式因此同時支援兩種
      合理慣例並列容忍（誠實聲明：非正典，待 T-12 落地後以其格式為準再收斂）：
        ① 機讀鍵值行（比照 anchor body 慣例）：`executor: <name>`
        ② tickets-draft.md 現行人讀慣例：`**executor**：\`<name>\`` 或 `**executor**：<name>`（全形／半形冒號皆容忍）
      皆找不到 ⇒ 回傳 $null（呼叫端顯示「（票 body 無 executor 欄位）」，不得靜默留白假裝沒問題）。
    #>
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return $null }
    if ($Body -match '(?im)^\s*executor\s*:\s*(.+?)\s*$') {
        return $Matches[1].Trim()
    }
    if ($Body -match '(?im)\*\*executor\*\*\s*[:：]\s*`?([^`\|\r\n]+?)`?\s*(?:｜|$)') {
        return $Matches[1].Trim()
    }
    return $null
}

# ============================================================================
# 區塊 3：純函式 render 核心（t09-offline-test.ps1 只測這一段）
# ============================================================================

function Get-StationLabelInfo {
    <#
      從 anchor labels 判定站別；同時做「髒 label」偵測（§3.1：sc:station-* 只能出現在 anchor 上；anchor 上
      出現一個以上互斥站別 label 亦屬髒資料）。回傳 [pscustomobject]@{ Station; IsDirty; DirtyDetail }。
    #>
    param([string[]]$Labels)
    $stationLabels = @($Labels | Where-Object { $_ -match '^sc:station-(1|2|3|4|5|done)$' })
    if ($stationLabels.Count -eq 0) {
        return [pscustomobject]@{ Station = $null; IsDirty = $true; DirtyDetail = 'anchor 無任何站別 label（站別來源不明）' }
    }
    if ($stationLabels.Count -gt 1) {
        return [pscustomobject]@{ Station = $null; IsDirty = $true; DirtyDetail = "anchor 帶多個互斥站別 label：$($stationLabels -join ', ')" }
    }
    return [pscustomobject]@{ Station = $stationLabels[0]; IsDirty = $false; DirtyDetail = $null }
}

function Get-TicketDirtyStationLabels {
    <# §3.1：sc:station-* 出現在非 anchor 的 issue（票）上一律視為髒資料並具名示警。 #>
    param([array]$Tickets)
    $dirty = @()
    foreach ($t in $Tickets) {
        $bad = @($t.Labels | Where-Object { $_ -match '^sc:station-(1|2|3|4|5|done)$' })
        if ($bad.Count -gt 0) {
            $dirty += "$($t.Repo)#$($t.Number) 帶站別 label（不合法載體）：$($bad -join ', ')"
        }
    }
    return , $dirty
}

function ConvertTo-StatusLight {
    <#
      §4.1：紅＝sc:blocked／sc:gate-fail／對帳異常／髒 label／站別來源不明／anchor 消失；黃＝sc:awaiting-user；
      綠＝以上皆無。對帳異常與 anchor 消失屬 T-17／T-16 範圍，本票不判定（欄位位置保留、恆不觸發）。
      回傳 [pscustomobject]@{ Color; Reasons=@(...) }（Reasons 為紅／黃燈具名理由，供字卡與文字摘要引用）。
    #>
    param(
        [Parameter(Mandatory)]$AnchorIssue,
        [Parameter(Mandatory)]$StationInfo,
        [array]$Tickets,
        [array]$TicketDirtyLabels
    )
    $redReasons = @()
    $yellowReasons = @()

    $anchorLabels = @($AnchorIssue.Labels)
    if ($anchorLabels -contains 'sc:blocked') { $redReasons += 'anchor 帶 sc:blocked' }
    if ($anchorLabels -contains 'sc:gate-fail') { $redReasons += 'anchor 帶 sc:gate-fail' }
    if ($anchorLabels -contains 'sc:awaiting-user') { $yellowReasons += 'anchor 帶 sc:awaiting-user' }

    foreach ($t in $Tickets) {
        if ($t.Labels -contains 'sc:blocked') { $redReasons += "$($t.Repo)#$($t.Number) 帶 sc:blocked" }
        if ($t.Labels -contains 'sc:gate-fail') { $redReasons += "$($t.Repo)#$($t.Number) 帶 sc:gate-fail" }
        if ($t.Labels -contains 'sc:awaiting-user') { $yellowReasons += "$($t.Repo)#$($t.Number) 帶 sc:awaiting-user" }
    }

    if ($StationInfo.IsDirty) { $redReasons += $StationInfo.DirtyDetail }
    if ($TicketDirtyLabels.Count -gt 0) { $redReasons += $TicketDirtyLabels }

    if ($redReasons.Count -gt 0) {
        return [pscustomobject]@{ Color = 'red'; Reasons = $redReasons }
    }
    if ($yellowReasons.Count -gt 0) {
        return [pscustomobject]@{ Color = 'yellow'; Reasons = $yellowReasons }
    }
    return [pscustomobject]@{ Color = 'green'; Reasons = @() }
}

function Build-RunningAndStaleCounts {
    <#
      §4.1：在跑數量＝open、站4／5、且已有 assignee 的票數。停滯票數＝open 票中，最新事件距今逾 24h
      （以 issue.updated_at 為 timeline 最新事件的代理量測——`updated_at` 本身即 GitHub 對「該 issue 任何欄位
      變動」的原生時間戳，涵蓋 label／comment／assignee 等變動，語意等同「timeline 最新事件時間」；
      逐票另發 timeline API 屬「額外查詢」，§4.1 明文只允許 search＋milestone＋timeline 三源，且本欄位
      search 結果已含 updated_at，改用它可以不多打一次 API，同時仍是三源之一，不違反「不發額外查詢」）。
    #>
    param([array]$Tickets, [Parameter(Mandatory)][datetime]$NowUtc)
    $openTickets = @($Tickets | Where-Object { $_.State -eq 'open' })
    $running = @($openTickets | Where-Object { $_.HasAssignee })
    $stale = @($openTickets | Where-Object { ($NowUtc - $_.UpdatedAtUtc).TotalHours -gt 24 })
    return [pscustomobject]@{ RunningCount = $running.Count; StaleCount = $stale.Count }
}

function Build-StepperHtml {
    <# 五段視覺化進度指示（1 grill / 2 spec / 3 tickets / 4 implement / 5 雙審），done 時五段全綠＋done 標記。 #>
    param([string]$Station)
    $labels = @('1 grill', '2 spec', '3 tickets', '4 implement', '5 雙審')
    $done = ($Station -eq 'sc:station-done')
    $currentIdx = -1
    if ($Station -match '^sc:station-(\d)$') { $currentIdx = [int]$Matches[1] - 1 }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<div class="stepper" role="img" aria-label="站別進度">')
    for ($i = 0; $i -lt 5; $i++) {
        $cls = 'step'
        if ($done -or $i -lt $currentIdx) { $cls += ' step--done' }
        elseif ($i -eq $currentIdx) { $cls += ' step--current' }
        [void]$sb.Append("<div class=`"$cls`" title=`"$($labels[$i])`">$($i + 1)</div>")
        if ($i -lt 4) {
            $connCls = 'step-connector'
            if ($done -or $i -lt $currentIdx) { $connCls += ' step-connector--done' }
            [void]$sb.Append("<div class=`"$connCls`"></div>")
        }
    }
    [void]$sb.Append('</div>')
    $labelText = if ($done) { '完成（sc:station-done）' } elseif ($currentIdx -ge 0) { "目前：$($labels[$currentIdx])" } else { '站別不明（髒資料，見紅燈理由）' }
    [void]$sb.Append("<div class=`"stepper-label`">$(ConvertTo-HtmlEncoded -Text $labelText)</div>")
    return $sb.ToString()
}

function ConvertTo-HtmlEncoded {
    <#
      自製 HTML 屬性／內文編碼，不依賴 System.Web（Windows PowerShell 5.1 預設不載入該組件、需額外
      Add-Type，為求兩邊環境零依賴一律自己實作，符合自包 artifact 精神——render 器本身也不多背外部依賴）。
      順序刻意 & 最先跳脫，避免把後續跳脫序列裡的 & 又跳脫一次。
    #>
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $escaped = $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#39;')
    return $escaped
}

function Build-RepoProgressHtml {
    param([array]$MilestoneProgress)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<ul class="repo-progress">')
    foreach ($m in $MilestoneProgress) {
        $repoEsc = ConvertTo-HtmlEncoded -Text $m.Repo
        if (-not $m.QueryOk) {
            $detailEsc = ConvertTo-HtmlEncoded -Text $m.FailureDetail
            [void]$sb.Append("<li><strong>$repoEsc</strong>：<span class=`"err`">查詢失敗（$detailEsc）</span></li>")
            continue
        }
        if (-not $m.MilestoneFound) {
            [void]$sb.Append("<li><strong>$repoEsc</strong>：尚無 milestone（可能仍在站 1–3）</li>")
            continue
        }
        $pct = $m.PercentComplete
        $pctText = if ($null -eq $pct) { 'N/A（open+closed=0）' } else { "$pct%" }
        $pctNum = if ($null -eq $pct) { 0 } else { $pct }
        [void]$sb.Append("<li><strong>$repoEsc</strong>：$pctText（closed $($m.ClosedIssues) / open $($m.OpenIssues)）" +
            "<div class=`"progress-bar`"><div class=`"progress-bar-fill`" style=`"width:${pctNum}%`"></div></div></li>")
    }
    [void]$sb.Append('</ul>')
    return $sb.ToString()
}

function Build-BannersHtml {
    <# 四種異常狀態的 banner 組裝（純函式，僅字串），§4.4 硬規則逐條對應。 #>
    param([array]$ErrorStates)
    $sb = New-Object System.Text.StringBuilder
    foreach ($e in $ErrorStates) {
        $cls = switch ($e.Kind) {
            'query-failed' { 'banner banner--stale' }
            'incomplete' { 'banner banner--incomplete' }
            'empty' { 'banner banner--empty' }
            'no-baseline' { 'banner banner--no-baseline' }
            default { 'banner' }
        }
        $textEsc = ConvertTo-HtmlEncoded -Text $e.Text
        [void]$sb.Append("<div class=`"$cls`"><strong>$(ConvertTo-HtmlEncoded -Text $e.Title)</strong>$textEsc</div>`n")
    }
    return $sb.ToString()
}

function Build-StatRowHtml {
    <#
      dataviz 慣例的 stat tile／KPI row：把「在跑數量／停滯票數／待寫筆數」三個最想一眼看到的數字
      放大字體、並排展示在字卡最上方（緊接 stepper 之後），紅／黃色只在數值本身帶異常語意時才上色
      （停滯>0 用黃、待寫非 0 用黃——待寫非異常只是「有事要做」，不用紅；燈號紅黃已由狀態燈承載，
      這裡的配色刻意保守，避免和狀態燈的紅黃語意互相稀釋）。
    #>
    param([Parameter(Mandatory)]$Model)
    $runningEsc = $Model.RunningCount
    $staleCls = if ($Model.StaleCount -gt 0) { ' stat-tile-value--warn' } else { '' }
    $queueLabel = if (-not $Model.QueueExists) { 'N/A' } elseif ($null -ne $Model.QueueParseError) { '!' } else { $Model.PendingWriteCount }
    $queueCls = if ($Model.QueueUntrusted) { ' stat-tile-value--warn' } else { '' }
    return @"
<div class="stat-row">
  <div class="stat-tile"><div class="stat-tile-value">$runningEsc</div><div class="stat-tile-label">在跑數量</div></div>
  <div class="stat-tile"><div class="stat-tile-value$staleCls">$($Model.StaleCount)</div><div class="stat-tile-label">停滯票數（24h）</div></div>
  <div class="stat-tile"><div class="stat-tile-value$queueCls">$queueLabel</div><div class="stat-tile-label">待寫筆數</div></div>
</div>
"@
}

function Build-EmptyStateCardHtml {
    param([Parameter(Mandatory)][string]$QueryDescription)
    $descEsc = ConvertTo-HtmlEncoded -Text $QueryDescription
    return "<div class=`"empty-card`">目前無 active work<div class=`"meta-line`" style=`"margin-top:8px`">查詢條件：$descEsc</div></div>"
}

function Build-WorkCardHtml {
    <#
      §4.1 逐項欄位一律照 spec 列出的順序組字串。$Model 是本函式與 t09-offline-test.ps1 之間唯一的契約，
      形狀見 Build-StationBoardReport 內組裝處。
    #>
    param([Parameter(Mandatory)]$Model)

    $dotClass = "dot dot--$($Model.StatusColor)"
    $staleCardClass = if ($Model.IsStaleCard) { ' card--stale' } else { '' }

    $badges = New-Object System.Text.StringBuilder
    if ($Model.IsLegacy) { [void]$badges.Append('<span class="badge badge--legacy">legacy</span> ') }
    if ($Model.IsStaleCard) { [void]$badges.Append('<span class="badge badge--stale">未更新</span> ') }
    if ($Model.PendingWriteCount -is [int] -and $Model.PendingWriteCount -gt 0) {
        [void]$badges.Append("<span class=`"badge badge--queue`">待寫 $($Model.PendingWriteCount) 筆</span> ")
    }

    $reasonsHtml = ''
    if ($Model.StatusReasons.Count -gt 0) {
        $items = ($Model.StatusReasons | ForEach-Object { "<li>$(ConvertTo-HtmlEncoded -Text $_)</li>" }) -join ''
        $reasonsHtml = "<div class=`"meta-line`">燈號理由：<ul style=`"margin:4px 0 0 18px;padding:0`">$items</ul></div>"
    }

    $untrustedNote = ''
    if ($Model.QueueUntrusted) {
        $untrustedNote = '<div class="meta-line" style="color:var(--yellow)">⚠️ 待寫佇列非空，寫入斷點期間不可信（在跑數量／停滯票數依據的 assignee 與事件尚未落地）</div>'
    }

    $reposLine = "$(ConvertTo-HtmlEncoded -Text $Model.PrimaryRepo)（primary）"
    if ($Model.OtherRepos.Count -gt 0) {
        $reposLine += '、' + (($Model.OtherRepos | ForEach-Object { ConvertTo-HtmlEncoded -Text $_ }) -join '、')
    }

    $executorText = if ($Model.ExecutorList.Count -gt 0) { ($Model.ExecutorList -join '、') } else { '（無在跑票，或票 body 無 executor 欄位）' }

    $pendingWriteText =
        if (-not $Model.QueueExists) { '待寫佇列不存在' }
        elseif ($null -ne $Model.QueueParseError) { "待寫佇列讀取失敗：$($Model.QueueParseError)" }
        else { "待寫 $($Model.PendingWriteCount) 筆" }

    $html = @"
<div class="card$staleCardClass">
  <div class="card-header">
    <span class="$dotClass" title="狀態燈：$($Model.StatusColor)"></span>
    <h2 class="card-title">$(ConvertTo-HtmlEncoded -Text $Model.WorkName)</h2>
    <span class="work-id">$(ConvertTo-HtmlEncoded -Text $Model.WorkId)</span>
    $($badges.ToString())
  </div>
  $($Model.StepperHtml)
  $(Build-StatRowHtml -Model $Model)
  $reasonsHtml
  $untrustedNote
  <dl class="fields">
    <dt>primary／參與 repo</dt><dd>$reposLine</dd>
    <dt>逐 repo 進度</dt><dd>$($Model.RepoProgressHtml)</dd>
    <dt>當前 executor</dt><dd>$(ConvertTo-HtmlEncoded -Text $executorText)</dd>
    <dt>在跑數量</dt><dd>$($Model.RunningCount)$(if ($Model.QueueUntrusted) { '（寫入斷點期間不可信）' })$(if ($Model.PartialDataCaveat) { '（部分 repo 查詢失敗，數字可能不完整）' })</dd>
    <dt>停滯票數（24h）</dt><dd>$($Model.StaleCount)$(if ($Model.QueueUntrusted) { '（寫入斷點期間不可信）' })$(if ($Model.PartialDataCaveat) { '（部分 repo 查詢失敗，數字可能不完整）' })</dd>
    <dt>待寫佇列</dt><dd>$(ConvertTo-HtmlEncoded -Text $pendingWriteText)</dd>
    <dt>對帳資料時間</dt><dd>$(ConvertTo-HtmlEncoded -Text $Model.ReconcileDataTimeText)</dd>
    <dt>最後成功完整同步</dt><dd>$(ConvertTo-HtmlEncoded -Text $Model.LastFullSyncText)</dd>
  </dl>
  <div class="card-footer">
    <div>work ID：$(ConvertTo-HtmlEncoded -Text $Model.WorkId)　primary anchor：$(ConvertTo-HtmlEncoded -Text $Model.AnchorRef)</div>
  </div>
</div>
"@
    return $html
}

function Build-StationBoardReport {
    <#
      **PURE**。輸入：$Snapshot（見檔頭 SNAPSHOT SCHEMA，可為真實或手造 mock）、$TemplateContent（樣板原文字串）、
      $CacheBaseline（上一輪 §4.2 顯示快取物件，或 $null）、$NowLocal（本地時區時間，供輸出文案）、
      $TimeZoneLabel（時區代碼字串，如 "UTC+8"）、$NoReconcile（§4.5 無對帳模式）、
      $SkipErrorStateHandling（⚠️ 僅供紅燈驗證：關閉後把「查詢失敗」錯誤當「合法空結果」處理，刻意製造
      「失敗顯示成無工作」的 bug，供 t09-test.ps1 證明「此斷言在關閉正確處理時必須失敗」）。

      回傳 [pscustomobject]@{ Html; TextSummary; ErrorStates=@(...); CacheData=@{...} }。
    #>
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$TemplateContent,
        $CacheBaseline,
        [Parameter(Mandatory)][datetime]$NowLocal,
        [string]$TimeZoneLabel = 'local',
        [switch]$NoReconcile,
        [switch]$SkipErrorStateHandling
    )

    $errorStates = @()

    # --- 判定三個查詢子項各自的健康度 ---
    $anchorOk = $Snapshot.AnchorQuery.Ok
    $anchorFound = $Snapshot.AnchorQuery.Found
    $ticketsOk = $Snapshot.TicketsQuery.Ok
    $milestoneFailures = @($Snapshot.MilestoneProgress | Where-Object { -not $_.QueryOk })

    $hasHardQueryFailure = (-not $anchorOk) -or (-not $ticketsOk) -or ($milestoneFailures.Count -gt 0) -or ($Snapshot.TicketsQuery.FailedRepos.Count -gt 0)

    # ⚠️ 紅燈驗證專用旁路：把「查詢失敗」硬性視為「查詢成功、剛好零筆」——這是刻意錯誤的行為，
    # 用來讓「失敗不得顯示為無工作」這條斷言在開啟本旗標時真的斷言失敗（見 t09-test.ps1）。
    if ($SkipErrorStateHandling) {
        $hasHardQueryFailure = $false
        if (-not $anchorOk) { $anchorOk = $true; $anchorFound = $false }
    }

    $lastSuccessText = if ($CacheBaseline -and $CacheBaseline.LastFullSyncTimeUtc) {
        (([datetime]$CacheBaseline.LastFullSyncTimeUtc).ToLocalTime()).ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel"
    } else { '（無上次成功紀錄）' }

    if ($hasHardQueryFailure) {
        $failedNames = @()
        if (-not $anchorOk) { $failedNames += "anchor（$($Snapshot.AnchorQuery.FailureDetail)）" }
        if (-not $ticketsOk) { $failedNames += @($Snapshot.TicketsQuery.FailedRepos) }
        elseif ($Snapshot.TicketsQuery.FailedRepos.Count -gt 0) { $failedNames += @($Snapshot.TicketsQuery.FailedRepos) }
        foreach ($mf in $milestoneFailures) { $failedNames += "milestone（$($mf.FailureDetail)）" }
        $text = "失敗對象：$($failedNames -join '；')。上次成功時間：$lastSuccessText。"
        $errorStates += [pscustomobject]@{ Kind = 'query-failed'; Title = '數據過期　'; Text = $text }
    }

    # --- 不完整（觸頂／縮水）判定 ---
    $incompleteReasons = @()
    if ($Snapshot.TicketsQuery.HitPageCap) {
        $incompleteReasons += "票查詢已觸頂：GitHub 回報總筆數 $($Snapshot.TicketsQuery.TotalCountReported)，本次僅取得 $($Snapshot.TicketsQuery.ResultCountThisRun) 筆（分頁上限已用盡）"
    }
    if ($CacheBaseline -and ($null -ne $CacheBaseline.LastTicketCount) -and $ticketsOk -and ($null -ne $Snapshot.TicketsQuery.ResultCountThisRun)) {
        $prev = [int]$CacheBaseline.LastTicketCount
        $cur = [int]$Snapshot.TicketsQuery.ResultCountThisRun
        if ($prev -gt 0 -and $cur -lt $prev -and $cur -le ($prev * 0.5)) {
            $incompleteReasons += "票數較上次成功值異常縮水：上次 $prev 筆 → 本次 $cur 筆（best-effort 偵測，正常結案流程也會使票數自然下降，僅在跌幅逾五成時提出，仍請人工複核）"
        }
    }
    if ($incompleteReasons.Count -gt 0) {
        $text = ($incompleteReasons -join '；') + "。上次成功完整同步時間：$lastSuccessText。"
        $errorStates += [pscustomobject]@{ Kind = 'incomplete'; Title = '資料可能不完整　'; Text = $text }
    }

    # --- 站別／燈號／字卡欄位計算（僅在有 anchor 資料時進行；查詢失敗且無資料可用時，字卡改走「灰標占位」分支） ---
    $isEmpty = $anchorOk -and (-not $anchorFound) -and (-not $hasHardQueryFailure)

    $noBaseline = ($null -eq $CacheBaseline)

    if ($isEmpty) {
        if ($noBaseline) {
            $errorStates += [pscustomobject]@{ Kind = 'no-baseline'; Title = '消失偵測不可用（無基線）　'; Text = '面板快取尚無基線（首次 render 或快取已重建），無法比對是否有工作消失；此為降級提示，不代表任何工作異常。' }
        }
        $errorStates += [pscustomobject]@{ Kind = 'empty'; Title = ''; Text = '' }  # 佔位，實際文案由空狀態卡本身承載
        $bannersHtml = Build-BannersHtml -ErrorStates (@($errorStates | Where-Object { $_.Kind -ne 'empty' }))
        $queryDesc = "work-id=$($Snapshot.WorkId)｜primary-repo=$($Snapshot.PrimaryRepo)"
        $mainHtml = Build-EmptyStateCardHtml -QueryDescription $queryDesc
        $textSummary = "目前無 active work（查詢條件：$queryDesc）。" + $(if ($noBaseline) { ' 消失偵測不可用（無基線）。' } else { '' })
        # $CacheBaseline 在「無基線」情境下就是 $null——StrictMode 下對 $null 取屬性會拋例外，逐欄位以
        # $noBaseline 短路判斷，不得直接 $CacheBaseline.Xxx（陷阱示範見 t21/queue-common.ps1 前例）。
        $cacheData = @{
            workId               = $Snapshot.WorkId
            lastFullSyncTimeUtc  = if ($noBaseline) { $null } else { $CacheBaseline.LastFullSyncTimeUtc }
            lastReconcileTimeUtc = if ($noBaseline) { $null } else { $CacheBaseline.LastReconcileTimeUtc }
            lastTicketCount      = if ($noBaseline) { $null } else { $CacheBaseline.LastTicketCount }
            anchorFound          = $false
        }
        $genAt = $NowLocal.ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel"
        $cacheJson = (ConvertTo-Json -InputObject $cacheData -Depth 5 -Compress)
        $cacheJsonEsc = $cacheJson -replace '&', '&amp;' -replace '"', '&quot;'
        return [pscustomobject]@{
            Html         = ($TemplateContent.Replace('{{GENERATED_AT}}', $genAt).Replace('{{BANNERS_HTML}}', $bannersHtml).Replace('{{MAIN_CONTENT_HTML}}', $mainHtml).Replace('{{CACHE_DATA_JSON_ESCAPED}}', $cacheJsonEsc))
            TextSummary  = $textSummary
            ErrorStates  = @($errorStates | ForEach-Object { $_.Kind })
            CacheData    = $cacheData
        }
    }

    # --- 有資料（或部分查詢失敗但仍有能顯示的殘餘資料）分支 ---
    $anchorIssue = $Snapshot.AnchorQuery.Issue
    $stationInfo = if ($anchorIssue) { Get-StationLabelInfo -Labels $anchorIssue.Labels } else { [pscustomobject]@{ Station = $null; IsDirty = $true; DirtyDetail = 'anchor 查詢失敗，無法讀站別' } }
    # ⚠️ 陷阱②的變形：if/else「表達式賦值」本身會對區塊輸出再做一次管線展開，0 筆陣列會被攤平成
    # $null（即使區塊內已經 @() 包過一次）。改用「陳述式形式」（賦值寫在各分支內部）即可避開，
    # 因為此時每個分支各自是一次直接賦值，不經過 if 整體表達式值的管線收集這一層。已用 pwsh 實測
    # 對比驗證：expression 形式在 0 筆時 $tickets 變 $null 且下游 .Count 在 StrictMode 直接拋錯；
    # statement 形式在同樣輸入下 $tickets.Count 正確為 0。
    if ($ticketsOk) { $tickets = @($Snapshot.TicketsQuery.Tickets) } else { $tickets = @() }
    $ticketDirty = Get-TicketDirtyStationLabels -Tickets $tickets
    $statusLight = if ($anchorIssue) {
        ConvertTo-StatusLight -AnchorIssue $anchorIssue -StationInfo $stationInfo -Tickets $tickets -TicketDirtyLabels $ticketDirty
    } else {
        [pscustomobject]@{ Color = 'unknown'; Reasons = @('anchor 查詢失敗，無法判定燈號') }
    }
    $counts = Build-RunningAndStaleCounts -Tickets $tickets -NowUtc $Snapshot.NowUtc

    $executors = @()
    foreach ($t in $tickets) {
        if ($t.State -eq 'open' -and $t.HasAssignee) {
            $ex = Get-ExecutorFromBody -Body $t.Body
            if ($ex) { $executors += $ex }
        }
    }
    $executors = @($executors | Select-Object -Unique)

    $queue = $Snapshot.Queue
    $queueUntrusted = $queue.Exists -and ($queue.Count -is [int]) -and ($queue.Count -gt 0)

    $reconcileText =
        if ($NoReconcile) {
            $prevReconcile = if ($CacheBaseline -and $CacheBaseline.LastReconcileTimeUtc) { (([datetime]$CacheBaseline.LastReconcileTimeUtc).ToLocalTime()).ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel" } else { '（尚無對帳紀錄）' }
            "本次未對帳，沿用 $prevReconcile 結果"
        } else {
            '對帳：尚未實作（T-17 範圍），本欄位僅保留位置'
        }

    $fullSyncOk = $anchorOk -and $anchorFound -and $ticketsOk -and ($milestoneFailures.Count -eq 0) -and ($Snapshot.TicketsQuery.FailedRepos.Count -eq 0)
    $lastFullSyncText = if ($fullSyncOk) {
        $NowLocal.ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel"
    } else {
        $lastSuccessText
    }

    $model = [pscustomobject]@{
        WorkId              = $Snapshot.WorkId
        WorkName            = if ($anchorIssue) { ($anchorIssue.Title -replace '\s*·\s*primary anchor\s*$', '') } else { $Snapshot.WorkId }
        PrimaryRepo         = $Snapshot.PrimaryRepo
        OtherRepos          = @($Snapshot.ParticipatingReposDeclared | Where-Object { $_ -ne $Snapshot.PrimaryRepo })
        StepperHtml         = Build-StepperHtml -Station $stationInfo.Station
        RepoProgressHtml    = Build-RepoProgressHtml -MilestoneProgress $Snapshot.MilestoneProgress
        ExecutorList        = $executors
        StatusColor         = $statusLight.Color
        StatusReasons       = $statusLight.Reasons
        RunningCount        = $counts.RunningCount
        StaleCount          = $counts.StaleCount
        IsLegacy            = ($anchorIssue -and ($anchorIssue.Labels -contains 'sc:legacy'))
        PendingWriteCount   = $queue.Count
        QueueExists         = $queue.Exists
        QueueParseError     = $queue.ParseError
        QueueUntrusted      = $queueUntrusted
        ReconcileDataTimeText = $reconcileText
        LastFullSyncText    = $lastFullSyncText
        AnchorRef           = if ($anchorIssue) { "$($Snapshot.PrimaryRepo)#$($anchorIssue.Number)" } else { '（查詢失敗，無法取得）' }
        IsStaleCard         = $hasHardQueryFailure
        PartialDataCaveat   = ($Snapshot.TicketsQuery.FailedRepos.Count -gt 0) -or ($milestoneFailures.Count -gt 0)
    }

    $mainHtml = Build-WorkCardHtml -Model $model
    $bannersHtml = Build-BannersHtml -ErrorStates $errorStates

    $textLines = @(
        "工作：$($model.WorkName)（$($model.WorkId)）"
        "primary/參與 repo：$($model.PrimaryRepo)、$($model.OtherRepos -join '、')"
        "狀態燈：$($model.StatusColor)$(if ($model.StatusReasons.Count -gt 0) { '（' + ($model.StatusReasons -join '；') + '）' })"
        "在跑數量：$($model.RunningCount)　停滯票數：$($model.StaleCount)$(if ($queueUntrusted) { '（寫入斷點期間不可信）' })"
        "當前 executor：$(if ($executors.Count -gt 0) { $executors -join '、' } else { '（無在跑票或無 executor 欄位）' })"
        "待寫佇列：$(if (-not $queue.Exists) { '待寫佇列不存在' } elseif ($queue.ParseError) { "讀取失敗：$($queue.ParseError)" } else { "$($queue.Count) 筆" })"
        "對帳資料時間：$reconcileText"
        "最後成功完整同步：$lastFullSyncText"
    )
    foreach ($e in $errorStates) { $textLines += "[$($e.Kind)] $($e.Title)$($e.Text)" }
    $textSummary = $textLines -join "`n"

    $cacheData = @{
        workId               = $Snapshot.WorkId
        lastFullSyncTimeUtc  = if ($fullSyncOk) { $Snapshot.NowUtc.ToString('o') } elseif ($CacheBaseline) { $CacheBaseline.LastFullSyncTimeUtc } else { $null }
        lastReconcileTimeUtc = if ($CacheBaseline) { $CacheBaseline.LastReconcileTimeUtc } else { $null }
        lastTicketCount      = if ($ticketsOk) { $Snapshot.TicketsQuery.ResultCountThisRun } elseif ($CacheBaseline) { $CacheBaseline.LastTicketCount } else { $null }
        anchorFound          = $anchorFound
    }
    $cacheJson = (ConvertTo-Json -InputObject $cacheData -Depth 5 -Compress)
    $cacheJsonEsc = $cacheJson -replace '&', '&amp;' -replace '"', '&quot;'
    $genAt = $NowLocal.ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel"

    $html = $TemplateContent.Replace('{{GENERATED_AT}}', $genAt).Replace('{{BANNERS_HTML}}', $bannersHtml).Replace('{{MAIN_CONTENT_HTML}}', $mainHtml).Replace('{{CACHE_DATA_JSON_ESCAPED}}', $cacheJsonEsc)

    return [pscustomobject]@{
        Html        = $html
        TextSummary = $textSummary
        ErrorStates = @($errorStates | ForEach-Object { $_.Kind })
        CacheData   = $cacheData
    }
}

# ============================================================================
# 區塊 4：面板寫入（impure；獨立成函式方便觸發「面板寫入失敗」異常狀態）
# ============================================================================

function Save-StationBoardArtifact {
    param([Parameter(Mandatory)][string]$Html, [Parameter(Mandatory)][string]$OutputPath)
    try {
        $dir = Split-Path -Path $OutputPath -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            throw "目錄不存在：$dir"
        }
        Write-Utf8BomFile -Path $OutputPath -Content $Html
        return [pscustomobject]@{ Ok = $true; Detail = $null }
    } catch {
        return [pscustomobject]@{ Ok = $false; Detail = $_.Exception.Message }
    }
}

function Read-CacheBaselineFromExistingArtifact {
    <# §4.2：顯示快取住在上一輪 artifact 自身的 data 屬性。讀不到／解析失敗 ⇒ 回 $null（＝無基線，合法降級）。 #>
    param([string]$OutputPath)
    if (-not (Test-Path -LiteralPath $OutputPath)) { return $null }
    try {
        $content = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8
        if ($content -notmatch 'data-station-board-cache=''([^'']*)''') { return $null }
        $jsonEsc = $Matches[1]
        $json = $jsonEsc -replace '&quot;', '"' -replace '&amp;', '&'
        if ([string]::IsNullOrWhiteSpace($json) -or $json -eq '{{CACHE_DATA_JSON_ESCAPED}}') { return $null }
        return ($json | ConvertFrom-Json)
    } catch {
        return $null
    }
}

# ============================================================================
# 區塊 5：頂層入口（impure；SKILL.md／run／gate／t09-test.ps1 呼叫本函式）
# ============================================================================

function Invoke-StationBoardRender {
    param(
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][string]$PrimaryRepo,
        [int]$AnchorIssue,
        [string[]]$ParticipatingRepos,
        [Parameter(Mandatory)][string]$PatPath,
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$OutputPath,
        [switch]$NoReconcile,
        [int]$MaxPages = 3,
        [int]$PerPage = 100,
        [switch]$SkipErrorStateHandling,
        # 測試專用：提供 mock snapshot 時完全略過網路呼叫（Get-StationBoardSnapshot 不會被呼叫）
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
        $headers = Get-GithubHeaders -Token $token
        $snapshot = Get-StationBoardSnapshot -WorkId $WorkId -PrimaryRepo $PrimaryRepo -AnchorIssue $AnchorIssue `
            -ParticipatingRepos $ParticipatingRepos -Headers $headers -QueuePath $QueuePath -MaxPages $MaxPages -PerPage $PerPage
    }

    $nowLocal = (Get-Date)
    $tzLabel = "UTC$(('{0:+00;-00}' -f ((Get-Date).ToUniversalTime() - (Get-Date)).Hours))"

    $report = Build-StationBoardReport -Snapshot $snapshot -TemplateContent $templateContent -CacheBaseline $cacheBaseline `
        -NowLocal $nowLocal -TimeZoneLabel $tzLabel -NoReconcile:$NoReconcile -SkipErrorStateHandling:$SkipErrorStateHandling

    $saveResult = Save-StationBoardArtifact -Html $report.Html -OutputPath $OutputPath

    if (-not $saveResult.Ok) {
        # §4.4：面板寫入失敗 ⇒ 立即以文字輸出完整字卡摘要 ＋ 過期告警，🚫 不得靜默。
        Write-Host $report.TextSummary
        Write-Warning "面板未更新，畫面內容已過期（寫入失敗：$($saveResult.Detail)）"
    } else {
        Write-Host $report.TextSummary
    }

    return [pscustomobject]@{
        Report       = $report
        SaveResult   = $saveResult
        OutputPath   = $OutputPath
        ErrorStates  = $report.ErrorStates
    }
}

# ============================================================================
# 進入點
# ============================================================================

if (-not $FunctionsOnly) {
    Set-ConsoleUtf8
    if ([string]::IsNullOrWhiteSpace($WorkId) -or [string]::IsNullOrWhiteSpace($PrimaryRepo)) {
        throw "請提供 -WorkId 與 -PrimaryRepo（或改用 -FunctionsOnly dot-source 本檔供測試呼叫）"
    }
    Invoke-StationBoardRender -WorkId $WorkId -PrimaryRepo $PrimaryRepo -AnchorIssue $AnchorIssue `
        -ParticipatingRepos $ParticipatingRepos -PatPath $PatPath -QueuePath $QueuePath -TemplatePath $TemplatePath `
        -OutputPath $OutputPath -NoReconcile:$NoReconcile -MaxPages $MaxPages -PerPage $PerPage `
        -SkipErrorStateHandling:$SkipErrorStateHandling
}
