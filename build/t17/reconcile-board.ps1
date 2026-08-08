#requires -Version 5.1
<#
.SYNOPSIS
    T-17 · reconcile-board.ps1 — 對帳三態（範圍外／本次未對帳／對帳未執行）與漂移三類，只報不修。

.DESCRIPTION
    依 Spec_station-command_v1.11.md §4.3（對帳，含 A-10「只報不修，修復方向逐案由使用者裁示」）／
    §4.1（字卡欄位，不新增）／§4.2（面板＝顯示快取非真相源）／§2（/station-board 完整模式 dispatch
    project-manager 對帳）定案（tickets-draft.md T-17，GitHub issue #18）。

    地基：`../t16/aggregate-board.ps1`（跨 repo 聚合＋work-id 分組，T-16，本票不修改該檔）——本檔
    dot-source `../t16/aggregate-board.ps1 -T16FunctionsOnly`（該檔內部會再 dot-source
    `../t09/render-board.ps1 -FunctionsOnly`，transitively 一併帶入本檔作用域），複用：
      GitHub 側資料：Get-FleetSnapshot／Group-FleetIssuesByWorkId／Get-FleetMilestoneRowsForWork／
                      Read-FleetQueueInfoForWork／Get-FleetStationInfoWithLabel／ConvertTo-FleetIssue
      render 原語（t09）：Build-WorkCardHtml／ConvertTo-StatusLight／Build-StepperHtml／
                      Build-RepoProgressHtml／Build-RunningAndStaleCounts／Get-ExecutorFromBody／
                      Get-ParticipatingReposFromBody／ConvertTo-HtmlEncoded／ConvertTo-BoardIssue／
                      ConvertTo-SafeArray／Build-EmptyStateCardHtml／Save-StationBoardArtifact／
                      Read-CacheBaselineFromExistingArtifact／Read-PatToken／Get-GithubHeaders／
                      Write-Utf8BomFile／Set-ConsoleUtf8
      T-16 組裝原語：New-FleetWorkCardModel（呼叫、不修改——本檔用「呼叫後覆寫對帳三欄」的包裝法，
                      見區塊 3）／Build-FleetBannersHtml

    **為何 Build-ReconciledFleetBoardReport 是「另立一份、非呼叫 t16 Build-FleetBoardReport」**（比照
    t16 README 對 t09 Build-StationBoardReport 的同一種取捨，理由同構）：t16 的 `Build-FleetBoardReport`
    內部私有迴圈直接寫死呼叫 `New-FleetWorkCardModel`，**沒有任何注入點**能讓外部呼叫端替換「每張卡片
    的 model 怎麼組」這一步——而這正是本票「疊加對帳三態到既有欄位」必須介入的唯一位置。t16 本身面對
    t09 時也是同一個死結（t09 `Build-StationBoardReport` 同樣沒有 model 建構注入點），t16 的解法是**另
    立一份**「聚合版」的頂層組裝函式，只呼叫 t09 的低階純函式；本票原樣複製這個解法，對象換成 t16。
    🚫 不修改 `../t16/aggregate-board.ps1`／`../t09/render-board.ps1`（file ownership）。

    **本票不新增任何字卡欄位（§4.1 硬性要求）**——`ReconcileDataTimeText`／`StatusColor`／
    `StatusReasons` 三者皆是 t09 既有欄位（`render-board.ps1` L684「對帳資料時間」欄、L642-646「燈號
    理由」清單、L632 狀態燈 dot class）。本票的全部工作就是「把對帳結果算出來，塞進這三個既有欄位」，
    不開新欄、不改 `Build-WorkCardHtml` 本身的 HTML 結構。

    純／不純切分（承襲 T-09／T-16 架構，同一理由：對帳三態須能在沙盒離線 100% 決定性重現）：
        Compare-PlanVsGithubTickets   **pure**。漂移三類比對核心，T-17 驗收②「漂移筆數＝差異集筆數」
                                       的唯一測試 seam。
        Get-ReconcileStateForWork     **pure**。給定「plans/ 根目錄是否可用」＋單一 work 的 plan 紀錄＋
                                       GitHub 側票清單 ⇒ 決定三態之一與燈號覆寫內容。T-17 驗收①④與
                                       兩條紅燈正向斷言的核心 seam。
        Get-PlanWorkRecord            impure（可測：接受 -PlanReader 注入點，離線測試用 scriptblock
                                       取代真實檔案系統存取，決定性重現「plans/ 不可用」「查無此
                                       work」「該 work 讀取失敗」三種情境）。
        New-ReconciledFleetWorkCardModel   impure（呼叫 t16 New-FleetWorkCardModel，純覆寫三欄，見上）。
        Build-ReconciledFleetBoardReport   **pure**（吃 Snapshot＋PlansRoot 存取結果，可為真實或手造
                                       mock；本身不直接碰檔案系統——plans/ 讀取透過 Get-PlanWorkRecord，
                                       該函式支援 -PlanReader 完全離線注入，故整條路徑在離線測試下仍是
                                       決定性的）。T-17 驗收①②③④的整合測試 seam。
        Get-PlansTreeDigest／Get-SnapshotDigest   impure／pure 只讀工具，供「守恆檢查」（見下）。
        Invoke-ReconciledBoardRender  impure 頂層入口。

    **守恆檢查（Spec T-17：「對帳前後兩側內容摘要不變」，非紅燈，回歸檢查）**：
    `Get-PlansTreeDigest`（只讀，遞迴雜湊 plans/ 樹狀內容）與 `Get-SnapshotDigest`（只讀，序列化雜湊
    GitHub 側 Snapshot 物件）供離線測試在呼叫 `Build-ReconciledFleetBoardReport` 前後各算一次，斷言
    雜湊值相同——這是「只報不修」在檔案系統層與記憶體層的機器化保險：前者證明 plans/ 樹沒有任何檔案被
    新增／修改／刪除；後者證明本票的函式沒有就地竄改呼叫端傳入的 Snapshot 物件（pscustomobject 是參考
    型別，若程式碼誤寫成 `$w.Tickets = ...` 會就地污染呼叫端資料，此 hash 比對能抓到這類錯誤）。

    **只報不修的程式碼層守門（見 t17-offline-test.ps1 群組 I／README「GitHub 唯讀與 plans/ 唯讀」）**：
    本檔全程**不含**任何 `Set-Content`／`Out-File`／`New-Item`／`Remove-Item`／`Move-Item`／
    `Copy-Item`／`Add-Content` 針對 `$PlansRoot` 的呼叫（`Get-PlanWorkRecord` 只用
    `Test-Path`／`Get-Content`／`ConvertFrom-Json`，皆唯讀 cmdlet）；亦不含任何 `-Method Put/Post/
    Patch/Delete` 或 `set-labels`／`close-issue`／`create-issue` 型佇列項產生——三者皆屬 gate／intake／
    run 專屬，本票 scope 明文「不含任何自動修復」。全域 grep 證據見 README。

    ⚠️ PS 5.1 + StrictMode 三個已知陷阱（依 T-09/T-16 先例，本檔全程套用）：
      1. 單一物件沒有 `.Count` 屬性 ⇒ 先賦值變數再用 ConvertTo-SafeArray／@() 包過。
      2. `,@()` 只在跨函式邊界 return 時才需要逗號前綴；區域賦值一律直接 `@()`。
      3. `@(函式呼叫本身)` 會把 0 筆結果錯誤包成 1 筆 $null ⇒ 先賦值變數再包 @()。

    ⚠️ 變數命名紀律（依 T-12/T-13/T-15a 踩過的 `$ScriptDir`/`$FunctionsOnly` cascade 覆蓋教訓，
    T-16 檔頭已具名同一風險）：本檔頂層參數全部加 `T17` 前綴（`$T17Repos`／`$T17PlansRoot`…），
    🚫 不與 dot-source 進來的 `../t16/aggregate-board.ps1`（`$T16Repos`…）或
    `../t09/render-board.ps1`（`$WorkId`／`$PrimaryRepo`／`$OutputPath`…）頂層參數同名——
    dot-source 是 transitively 生效的（t17 dot-source t16、t16 內部又 dot-source t09，兩層參數
    預設值都會落進 t17 的作用域），若命名相同會被對方的預設值悄悄覆蓋（T-12/T-13 的 CLI 悄悄
    no-op 教訓）。函式內部參數（非頂層 script param）沿用 t16/t09 慣例可用裸名稱，因為函式呼叫
    各自有獨立作用域，無 cascade 風險。

.NOTES
    白名單依 Spec §2（`/station-board`，完整模式對帳段）：讀 GitHub（透過 t16 的既有聚合結果，不另發
    查詢）｜讀本機 `plans/`（單一來源，不逐 repo 抓檔，§4.3）｜dispatch `project-manager`（概念上——
    本票是「比對邏輯本身」的實作票，執行期由 `/station-board` SKILL.md 呼叫 dispatch，接線本身不在
    T-17 scope，見 README「誠實聲明」，比照 T-16 先例）｜寫面板 artifact（唯一寫入，透過 t09 的
    Save-StationBoardArtifact 未修改重用，非 GitHub 端點、非 plans/）｜文字輸出。
    🚫 本檔不呼叫任何 GitHub 寫入端點、不寫 plans/ 任何檔案、不產生任何 label／assignee／issue 開關類
    佇列項——「只報不修」是本票判「不可逆動作：無」的唯一理由（票面第八欄原文），故此守門是硬約束，
    非建議。
#>

[CmdletBinding()]
param(
    # 只載入函式、不執行 render（供 t17-offline-test.ps1／build-sample-reconciled-board.ps1 dot-source 本檔時使用）
    [switch]$T17FunctionsOnly,

    [string[]]$T17Repos,
    [string]$T17PatPath = "$PSScriptRoot/pat.txt",
    [string]$T17QueuePath = "$PSScriptRoot/../t21/queue.json",
    [string]$T17PlansRoot = "$PSScriptRoot/plans",
    [string]$T17TemplatePath = "$PSScriptRoot/../t16/fleet-board-template.html",
    [string]$T17OutputPath = "$PSScriptRoot/reconciled-board.html",
    [switch]$T17NoReconcile,
    [int]$T17MaxPages = 5,
    [int]$T17PerPage = 100,

    # ⚠️⚠️ 下列旗標僅供紅燈驗證使用，正式流程（含未來 SKILL.md 呼叫路徑）一律不得帶入 ⚠️⚠️
    [switch]$T17BugDisableReconcile
)

Set-StrictMode -Version Latest

# 複用 T-16 地基（不修改該檔；transitively 也帶入 T-09）。此行之後，$T16Repos/$WorkId/$PrimaryRepo/
# $OutputPath/... 等 t16／t09 頂層參數名稱會以其預設值存在於本檔作用域——本檔後續程式碼一律不得
# 引用這些「裸名稱」，只用 T17 前綴變數（頂層）或函式自己的區域參數（函式內）。
. "$PSScriptRoot/../t16/aggregate-board.ps1" -T16FunctionsOnly

# ============================================================================
# 區塊 1：漂移比對（**PURE**——T-17 驗收②「漂移筆數＝差異集筆數」的唯一測試 seam）
# ============================================================================

function Compare-PlanVsGithubTickets {
    <#
      **PURE**。§4.3 漂移三類：
        plan-only        （plans 有票 GitHub 無）：plan 記錄該票、狀態為 'open'，但該票不在 GithubTickets
                          內。⚠️ **設計取捨（獨立文件化，非拍腦袋）**：GitHub 側資料集固定只含目前
                          open 的票（§4.2 聚合定義：一次跨 repo search 只抓 open issues；§4.3 明文
                          「同一次聚合結果，不另發查詢」，故本函式的呼叫端不會、也不該為了對帳另外
                          去抓 closed 票）。若 plan 對該票的狀態已標為非 'open'（例如 'closed'），
                          它在 GitHub 開放集合中缺席屬**預期缺席**（票已結案，本就不會出現在
                          open 查詢結果內）——此情況不算漂移，避免把「正常結案」誤判為「票缺」假警報。
        github-only       （GitHub 有票 plans 無）：GithubTickets 有此票，但 PlanTickets 完全沒有對應
                          紀錄——無條件算漂移，不受票狀態影響（plans 完全不知道這張票存在，永遠是要
                          回報的落差）。
        status-mismatch   （同票狀態不一致）：兩側都記錄了同一張票（TicketRef 相同），但狀態值不同
                          （例如 plan 仍標 'open' 而 GitHub 側傳入的紀錄狀態不同）。本函式不假設
                          GithubTickets 一定全是 'open'（若呼叫端日後改抓全量含 closed，本規則仍
                          通用，不需修改）。

      輸入 $PlanTickets／$GithubTickets 皆為 @([pscustomobject]@{ TicketRef; Status }) 陣列，
      TicketRef 慣例格式 `owner/repo#number`（與 GitHub issue 的天然穩定識別鍵一致，見 README
      「plans/ fixture 格式假設」段的具名說明）。輸出依 TicketRef 字母序排序（決定性，供測試比對）。
    #>
    param([array]$PlanTickets, [array]$GithubTickets)

    $planByRef = @{}
    foreach ($p in $PlanTickets) { $planByRef[$p.TicketRef] = $p }
    $githubByRef = @{}
    foreach ($g in $GithubTickets) { $githubByRef[$g.TicketRef] = $g }

    $drift = @()

    foreach ($ref in $planByRef.Keys) {
        if (-not $githubByRef.ContainsKey($ref)) {
            if ($planByRef[$ref].Status -eq 'open') {
                $drift += [pscustomobject]@{ Kind = 'plan-only'; TicketRef = $ref; PlanStatus = $planByRef[$ref].Status; GithubStatus = $null }
            }
            # else：plan 標非 open 且 GitHub 開放集合缺席 ⇒ 預期缺席，不算漂移（見上方設計取捨說明）。
        }
    }
    foreach ($ref in $githubByRef.Keys) {
        if (-not $planByRef.ContainsKey($ref)) {
            $drift += [pscustomobject]@{ Kind = 'github-only'; TicketRef = $ref; PlanStatus = $null; GithubStatus = $githubByRef[$ref].Status }
        }
    }
    foreach ($ref in $planByRef.Keys) {
        if ($githubByRef.ContainsKey($ref)) {
            if ($planByRef[$ref].Status -ne $githubByRef[$ref].Status) {
                $drift += [pscustomobject]@{ Kind = 'status-mismatch'; TicketRef = $ref; PlanStatus = $planByRef[$ref].Status; GithubStatus = $githubByRef[$ref].Status }
            }
        }
    }

    $sorted = @($drift | Sort-Object TicketRef, Kind)
    return , $sorted
}

# ============================================================================
# 區塊 2：plans/ 讀取（impure，可注入供離線測試；只讀 cmdlet，見檔頭「只報不修守門」）
# ============================================================================

function Get-PlanWorkRecord {
    <#
      讀取單一 work 在本機 plans/ 的紀錄。**只讀**：僅用 Test-Path／Get-Content／ConvertFrom-Json。
      🚫 本函式（與本檔全部函式）不含任何寫入 plans/ 的路徑。

      fixture 格式假設（best-effort，非正典——ak-project-management 的 plans/ 實際落檔格式未見於
      Spec 或既有 build/，見 README「誠實聲明」）：`$PlansRoot/<WorkId>.json`，形狀：
        { "workId": "W-xxx", "tickets": [ { "ticketRef": "owner/repo#12", "status": "open" }, ... ] }

      $PlanReader：離線測試注入點，scriptblock (PlansRoot, WorkId) -> 同形狀回傳值，完全略過檔案
      系統，用於決定性重現「plans/ 不可用」（reader 拋例外或回傳 RootAvailable=$false）等情境。

      回傳 [pscustomobject]@{
        RootAvailable = $true/$false   # plans/ 根目錄本身是否可讀（全域，跨 work 共用同一次判定邏輯）
        Found         = $true/$false/$null   # 該 work 是否在 plans/ 有紀錄；$null＝檔案存在但讀取/解析失敗
        Tickets       = @([pscustomobject]@{ TicketRef; Status })
        FailureDetail = $null 或 string
      }
    #>
    param(
        [Parameter(Mandatory)][string]$PlansRoot,
        [Parameter(Mandatory)][string]$WorkId,
        $PlanReader
    )
    if ($PlanReader) {
        return & $PlanReader $PlansRoot $WorkId
    }

    try {
        if (-not (Test-Path -LiteralPath $PlansRoot)) {
            return [pscustomobject]@{ RootAvailable = $false; Found = $false; Tickets = @(); FailureDetail = "plans 根目錄不存在：$PlansRoot" }
        }
    } catch {
        return [pscustomobject]@{ RootAvailable = $false; Found = $false; Tickets = @(); FailureDetail = "plans 根目錄無法存取：$($_.Exception.Message)" }
    }

    $filePath = Join-Path $PlansRoot "$WorkId.json"
    try {
        if (-not (Test-Path -LiteralPath $filePath)) {
            return [pscustomobject]@{ RootAvailable = $true; Found = $false; Tickets = @(); FailureDetail = $null }
        }
        $raw = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
        $parsed = $raw | ConvertFrom-Json
        $ticketsRaw = ConvertTo-SafeArray -RawValue $parsed.tickets
        $tickets = @($ticketsRaw | ForEach-Object { [pscustomobject]@{ TicketRef = [string]$_.ticketRef; Status = [string]$_.status } })
        return [pscustomobject]@{ RootAvailable = $true; Found = $true; Tickets = $tickets; FailureDetail = $null }
    } catch {
        # 該 work 的檔案存在但讀取／解析失敗 ⇒ 只影響這一個 work（不是全域 plans/ 不可用），
        # Found=$null 讓 Get-ReconcileStateForWork 判該 work 局部「對帳未執行」，不牽連其他 work。
        return [pscustomobject]@{ RootAvailable = $true; Found = $null; Tickets = @(); FailureDetail = $_.Exception.Message }
    }
}

# ============================================================================
# 區塊 3：三態判定（**PURE**——T-17 驗收①④與兩條紅燈正向斷言的核心 seam）
# ============================================================================

function Get-ReconcileStateForWork {
    <#
      **PURE**。給定「plans/ 根目錄是否可用」（全域，跨 work 共用同一次判定）＋單一 work 的
      Get-PlanWorkRecord 結果＋該 work 本輪 GitHub 側票清單 ⇒ 決定對帳三態之一，並算出要覆寫進
      字卡既有欄位（ReconcileDataTimeText／StatusReasons／StatusColor 強制條件）的內容。

      三態＋額外一態（Spec T-17 原文「對帳範圍外／本次未對帳／對帳未執行」三種標示；「本次未對帳」
      由呼叫端 -NoReconcile 開關另行處理，不進本函式，見 New-ReconciledFleetWorkCardModel）：
        not-executed    對帳未執行（plans/ 不可用，或該 work 的紀錄讀取失敗）
        out-of-scope    對帳範圍外（plans/ 整個查無此 work）——驗收①：字卡標示存在且非綠燈
        in-scope-clean  已對帳、無漂移
        in-scope-drift  已對帳、有漂移——驗收②：漂移筆數＝Compare-PlanVsGithubTickets 輸出筆數

      $BugDisableReconcile：⚠️ 僅供紅燈驗證。開啟後一律回傳「未實作」狀態（複製 T-17 出票前的
      實際狀態——t09/t16 對 ReconcileDataTimeText 欄位的原始佔位文案「對帳：尚未實作（T-17 範圍），
      本欄位僅保留位置」、DriftCount 恆 0、不強制非綠燈），正式流程與 Build-ReconciledFleetBoardReport
      預設路徑絕不開啟。
    #>
    param(
        [Parameter(Mandatory)][bool]$RootAvailable,
        [Parameter(Mandatory)]$PlanRecord,
        [array]$GithubTickets,
        [Parameter(Mandatory)][datetime]$NowLocal,
        [string]$TimeZoneLabel = 'local',
        [switch]$BugDisableReconcile
    )

    if ($BugDisableReconcile) {
        return [pscustomobject]@{
            Kind = 'unimplemented-bug'
            ReconcileDataTimeText = '對帳：尚未實作（T-17 範圍），本欄位僅保留位置'
            ExtraStatusReasons = @()
            ForceNonGreen = $false
            DriftCount = 0
            Drift = @()
        }
    }

    $genAt = $NowLocal.ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel"

    if (-not $RootAvailable) {
        return [pscustomobject]@{
            Kind = 'not-executed'; ReconcileDataTimeText = '對帳未執行（plans/ 不可用）'
            ExtraStatusReasons = @(); ForceNonGreen = $false; DriftCount = 0; Drift = @()
        }
    }

    if ($null -eq $PlanRecord.Found) {
        return [pscustomobject]@{
            Kind = 'not-executed'; ReconcileDataTimeText = "對帳未執行（plans/ 該工作紀錄讀取失敗：$($PlanRecord.FailureDetail)）"
            ExtraStatusReasons = @(); ForceNonGreen = $false; DriftCount = 0; Drift = @()
        }
    }

    if (-not $PlanRecord.Found) {
        return [pscustomobject]@{
            Kind = 'out-of-scope'; ReconcileDataTimeText = '對帳範圍外（plans/ 查無此 work）'
            ExtraStatusReasons = @('對帳範圍外：plans/ 查無此 work，非已對帳綠燈')
            ForceNonGreen = $true; DriftCount = 0; Drift = @()
        }
    }

    $driftRaw = Compare-PlanVsGithubTickets -PlanTickets $PlanRecord.Tickets -GithubTickets $GithubTickets
    $drift = ConvertTo-SafeArray -RawValue $driftRaw   # 陷阱③防護：先賦值再包 @()

    if ($drift.Count -eq 0) {
        return [pscustomobject]@{
            Kind = 'in-scope-clean'; ReconcileDataTimeText = "已對帳：$genAt（無漂移）"
            ExtraStatusReasons = @(); ForceNonGreen = $false; DriftCount = 0; Drift = @()
        }
    }

    $driftDetail = ($drift | ForEach-Object { "$($_.TicketRef)[$($_.Kind)]" }) -join '；'
    return [pscustomobject]@{
        Kind = 'in-scope-drift'; ReconcileDataTimeText = "已對帳：$genAt（漂移 $($drift.Count) 筆）"
        ExtraStatusReasons = @("對帳異常：漂移 $($drift.Count) 筆（$driftDetail）")
        ForceNonGreen = $true; DriftCount = $drift.Count; Drift = $drift
    }
}

# ============================================================================
# 區塊 4：字卡 model 覆寫（impure；包一層 t16 New-FleetWorkCardModel，🚫 不修改該函式）
# ============================================================================

function New-ReconciledFleetWorkCardModel {
    <#
      呼叫 t16 `New-FleetWorkCardModel`（未修改）取得基礎 model，僅覆寫／附加對帳相關的**既有**欄位
      （ReconcileDataTimeText／StatusReasons／StatusColor），🚫 不新增任何字卡欄位（§4.1 硬性要求）。

      $NoReconcile 為真，或 $ReconcileState 為 $null（呼叫端在無對帳模式下不會算 ReconcileState，
      見 Build-ReconciledFleetBoardReport 區塊 6）⇒ 完全不覆寫，維持 t16 對「本次未對帳，沿用 <時間>
      結果」的既有正確行為（§4.5，T-17 不得干預）。
    #>
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
        [Parameter(Mandatory)][string]$LastFullSyncText,
        $ReconcileState
    )
    $model = New-FleetWorkCardModel -WorkId $WorkId -AnchorIssue $AnchorIssue -ParticipatingRepos $ParticipatingRepos `
        -Tickets $Tickets -MilestoneRows $MilestoneRows -QueueInfo $QueueInfo -NowUtc $NowUtc `
        -NoReconcile:$NoReconcile -CacheBaseline $CacheBaseline -LastFullSyncText $LastFullSyncText

    if ($NoReconcile -or $null -eq $ReconcileState) {
        return $model
    }

    $model.ReconcileDataTimeText = $ReconcileState.ReconcileDataTimeText
    $extraReasons = ConvertTo-SafeArray -RawValue $ReconcileState.ExtraStatusReasons
    if ($extraReasons.Count -gt 0) {
        $existingReasons = ConvertTo-SafeArray -RawValue $model.StatusReasons
        $model.StatusReasons = @($existingReasons + $extraReasons)
    }
    if ($ReconcileState.ForceNonGreen -and $model.StatusColor -eq 'green') {
        $model.StatusColor = 'red'
    }
    return $model
}

# ============================================================================
# 區塊 5：只讀摘要工具（供守恆檢查；T-17 票面「守恆檢查（非紅燈）」的機器化落地）
# ============================================================================

function Get-PlansTreeDigest {
    <#
      只讀：對 $PlansRoot 下所有檔案（遞迴，相對路徑＋內容）算出穩定 SHA256 摘要，供守恆檢查前後
      比對。$PlansRoot 不存在 ⇒ 回傳固定字串（仍可比較「前後都是這個值」＝沒有被憑空建立）。
    #>
    param([Parameter(Mandatory)][string]$PlansRoot)
    if (-not (Test-Path -LiteralPath $PlansRoot)) { return '(plans-root-absent)' }
    $files = @(Get-ChildItem -LiteralPath $PlansRoot -Recurse -File | Sort-Object FullName)
    $sb = New-Object System.Text.StringBuilder
    $rootFull = (Resolve-Path -LiteralPath $PlansRoot).Path
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/')
        $content = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        [void]$sb.Append("$rel`0$content`0")
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
        $hashBytes = $sha.ComputeHash($bytes)
        return -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    } finally {
        $sha.Dispose()
    }
}

function Get-SnapshotDigest {
    <#
      只讀：序列化（測試用）GitHub 側 Snapshot 物件後算 SHA256，供守恆檢查比對「本檔函式沒有就地
      竄改呼叫端傳入的 Snapshot 物件」（pscustomobject 是參考型別，`$w.Tickets = ...` 這類寫法會
      就地污染呼叫端資料——這正是「只報不修」在記憶體層級的對應風險，此 hash 比對能抓到）。
    #>
    param([Parameter(Mandatory)]$Snapshot)
    $json = ConvertTo-Json -InputObject $Snapshot -Depth 12 -Compress
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $hashBytes = $sha.ComputeHash($bytes)
        return -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    } finally {
        $sha.Dispose()
    }
}

# ============================================================================
# 區塊 6：頂層對帳報告（**PURE**——T-17 驗收①②③④的整合測試 seam；另立自 t16 Build-FleetBoardReport，理由見檔頭）
# ============================================================================

function Build-ReconciledFleetBoardReport {
    <#
      **PURE**（不直接碰檔案系統——plans/ 存取透過 Get-PlanWorkRecord 的 -PlanReader 完全可離線注入）。
      輸入與 t16 `Build-FleetBoardReport` 相同的 $Snapshot／$TemplateContent／$CacheBaseline／
      $NowLocal／$TimeZoneLabel／$NoReconcile，另加：
        $PlansRoot            plans/ 根目錄路徑（$NoReconcile 為真時完全不讀取，見下）
        $PlanReader           離線測試注入點（見 Get-PlanWorkRecord）
        $BugDisableReconcile  ⚠️ 僅供紅燈驗證（見 Get-ReconcileStateForWork）
        $SkipNoBaselineBanner 透傳給既有的無基線 banner 邏輯（比照 t16，非本票新增行為）

      回傳 [pscustomobject]@{ Html; TextSummary; ErrorStates; CacheData; CardsHtml; ReconcileSummary }
      （ReconcileSummary＝@([pscustomobject]@{WorkId; Kind; DriftCount; Drift}, ...)，測試／文字摘要用
      內部欄位，非面板欄位——比照 t16 CardsHtml 的「測試用內部欄位」先例，不算面板新增欄位）。
    #>
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$TemplateContent,
        $CacheBaseline,
        [Parameter(Mandatory)][datetime]$NowLocal,
        [string]$TimeZoneLabel = 'local',
        [switch]$NoReconcile,
        [string]$PlansRoot,
        $PlanReader,
        [switch]$BugDisableReconcile,
        [switch]$SkipNoBaselineBanner
    )

    # --- 以下區塊逐字對應 t16 Build-FleetBoardReport 的錯誤狀態／banner／空狀態邏輯（未改動語意），
    #     唯一新增的是每個 work 迴圈內的對帳步驟（見下方標註）。---
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
            ReconcileSummary = @()
        }
    }

    $cardsHtml = New-Object System.Text.StringBuilder
    $textLines = @()
    $cacheWorks = @()
    $reconcileSummary = @()
    foreach ($w in $works) {
        $milestoneFailuresForWork = @($w.MilestoneRows | Where-Object { -not $_.QueryOk })
        $fullSyncOkForWork = ($null -ne $w.AnchorIssue) -and ($milestoneFailuresForWork.Count -eq 0) -and (-not $hasHardQueryFailure)
        $lastFullSyncTextForWork = if ($fullSyncOkForWork) { $NowLocal.ToString('yyyy-MM-dd HH:mm') + " $TimeZoneLabel" } else { $lastSuccessText }

        # --- T-17 新增：對帳三態判定（僅在非 -NoReconcile 時進行；無對帳模式完全不碰 plans/，
        #     符合 §4.5「無對帳模式下對帳欄位一律標本次未對帳」與守恆檢查精神——不需要對帳的一輪
        #     連讀都不讀 plans/）。---
        $reconcileState = $null
        if (-not $NoReconcile) {
            $planRecord = Get-PlanWorkRecord -PlansRoot $PlansRoot -WorkId $w.WorkId -PlanReader $PlanReader
            $githubTicketsRaw = @($w.Tickets | ForEach-Object { [pscustomobject]@{ TicketRef = "$($_.Repo)#$($_.Number)"; Status = $_.State } })
            $githubTicketsNorm = ConvertTo-SafeArray -RawValue $githubTicketsRaw
            $reconcileState = Get-ReconcileStateForWork -RootAvailable $planRecord.RootAvailable -PlanRecord $planRecord `
                -GithubTickets $githubTicketsNorm -NowLocal $NowLocal -TimeZoneLabel $TimeZoneLabel -BugDisableReconcile:$BugDisableReconcile
            $reconcileSummary += [pscustomobject]@{ WorkId = $w.WorkId; Kind = $reconcileState.Kind; DriftCount = $reconcileState.DriftCount; Drift = $reconcileState.Drift }
        }

        $model = New-ReconciledFleetWorkCardModel -WorkId $w.WorkId -AnchorIssue $w.AnchorIssue -ParticipatingRepos $w.ParticipatingRepos `
            -Tickets $w.Tickets -MilestoneRows $w.MilestoneRows -QueueInfo $w.QueueInfo -NowUtc $Snapshot.NowUtc `
            -NoReconcile:$NoReconcile -CacheBaseline $CacheBaseline -LastFullSyncText $lastFullSyncTextForWork -ReconcileState $reconcileState

        [void]$cardsHtml.Append((Build-WorkCardHtml -Model $model))
        $textLines += "工作：$($model.WorkName)（$($model.WorkId)）｜狀態燈：$($model.StatusColor)$(if ($model.StatusReasons.Count -gt 0) { '（' + ($model.StatusReasons -join '；') + '）' })｜在跑：$($model.RunningCount)｜停滯：$($model.StaleCount)"

        if ($reconcileState) {
            if ($reconcileState.Kind -eq 'in-scope-drift') {
                $textLines += "對帳漂移：$($w.WorkId)：$($reconcileState.DriftCount) 筆（$(($reconcileState.Drift | ForEach-Object { "$($_.TicketRef)[$($_.Kind)]" }) -join '；')）"
            } elseif ($reconcileState.Kind -eq 'out-of-scope') {
                $textLines += "對帳範圍外：$($w.WorkId)"
            } elseif ($reconcileState.Kind -eq 'not-executed') {
                $textLines += "對帳未執行：$($w.WorkId)"
            }
        }

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
        lastReconcileTimeUtc = if ($NoReconcile) { if ($noBaseline) { $null } elseif ($CacheBaseline.PSObject.Properties.Name -contains 'lastReconcileTimeUtc') { $CacheBaseline.lastReconcileTimeUtc } else { $null } } else { $Snapshot.NowUtc.ToString('o') }
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
        ReconcileSummary = $reconcileSummary
    }
}

# ============================================================================
# 區塊 7：頂層入口（impure；供本機手動執行與 build-sample-reconciled-board.ps1／未來 SKILL.md 整合呼叫）
# ============================================================================

function Invoke-ReconciledBoardRender {
    param(
        [array]$Repos,
        [string]$PatPath,
        [string]$QueuePath,
        [string]$PlansRoot,
        [string]$TemplatePath,
        [string]$OutputPath,
        [switch]$NoReconcile,
        [int]$MaxPages = 5,
        [int]$PerPage = 100,
        [switch]$BugDisableReconcile,
        $PlanReader,
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
        $headers = Get-GithubHeaders -Token $token -UserAgent 'station-command-t17-reconcile-board'
        $snapshot = Get-FleetSnapshot -Repos $Repos -Headers $headers -QueuePath $QueuePath -MaxPages $MaxPages -PerPage $PerPage
    }

    $nowLocal = (Get-Date)
    $tzLabel = "UTC$(('{0:+00;-00}' -f ((Get-Date).ToUniversalTime() - (Get-Date)).Hours))"

    $report = Build-ReconciledFleetBoardReport -Snapshot $snapshot -TemplateContent $templateContent -CacheBaseline $cacheBaseline `
        -NowLocal $nowLocal -TimeZoneLabel $tzLabel -NoReconcile:$NoReconcile -PlansRoot $PlansRoot -PlanReader $PlanReader `
        -BugDisableReconcile:$BugDisableReconcile

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

if (-not $T17FunctionsOnly) {
    Set-ConsoleUtf8
    if (-not $T17Repos) {
        throw "請提供 -T17Repos（或改用 -T17FunctionsOnly dot-source 本檔供測試呼叫）"
    }
    Invoke-ReconciledBoardRender -Repos $T17Repos -PatPath $T17PatPath -QueuePath $T17QueuePath -PlansRoot $T17PlansRoot `
        -TemplatePath $T17TemplatePath -OutputPath $T17OutputPath -NoReconcile:$T17NoReconcile -MaxPages $T17MaxPages -PerPage $T17PerPage `
        -BugDisableReconcile:$T17BugDisableReconcile
}
