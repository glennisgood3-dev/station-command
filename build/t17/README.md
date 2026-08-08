# T-17 · 對帳三態（範圍外／未對帳／漂移）

依 `Spec_station-command_v1.11.md` §4.3（對帳，含 A-10「只報不修，修復方向逐案由使用者裁示」）／
§4.1（字卡欄位，🚫 不新增）／§4.2（面板＝顯示快取非真相源）／§2（`/station-board` 完整模式 dispatch
`project-manager` 對帳）與 `tickets-draft.md` T-17（GitHub issue #18）定案。
地基：`../t16/aggregate-board.ps1`（跨 repo 聚合＋work-id 分組，T-16，本票**不修改**該檔，亦不修改其
transitively 帶入的 `../t09/render-board.ps1`——file ownership，理由與擴充方式見下方「與 T-16／T-09
的關係」）。

## 目錄結構

```
build/t17/
  reconcile-board.ps1                     核心：對帳三態＋漂移三類＋只報不修守門（dot-source T-16）
  t17-offline-test.ps1                    離線 mock 測試：73 項斷言，十群組 A-J（沙盒可跑，不連網）
  build-sample-reconciled-board.ps1       兩份成品範例的產生腳本
  sample-reconciled-board.html            成品範例①：三態同頁（clean／drift／out-of-scope）
  sample-reconciled-board-plans-unavailable.html  成品範例②：plans/ 不可用（對帳未執行，全域態，另頁示範）
  plans/                                  人造 plans/ fixture（W-alpha.json／W-beta.json，供範例與手動複驗）
  README.md                               本檔
```

## 與 T-16／T-09 的關係（複用、不重寫；另立、不修改）

T-16 交付跨 repo 聚合＋work-id 分組（含逐 work 的 GitHub 票清單）；T-09 交付單一字卡 render 原語。
T-17 **dot-source** `../t16/aggregate-board.ps1 -T16FunctionsOnly`（該檔內部再 dot-source
`../t09/render-board.ps1 -FunctionsOnly`，transitively 一併帶入本檔作用域），直接複用其純函式：
`Get-FleetSnapshot`／`Group-FleetIssuesByWorkId`／`Get-FleetMilestoneRowsForWork`／
`Read-FleetQueueInfoForWork`／`Get-FleetStationInfoWithLabel`（皆 T-16）與
`Build-WorkCardHtml`／`ConvertTo-StatusLight`／`Build-StepperHtml`／`Build-RepoProgressHtml`／
`Build-RunningAndStaleCounts`／`Get-ExecutorFromBody`／`ConvertTo-HtmlEncoded`／`ConvertTo-SafeArray`／
`Build-EmptyStateCardHtml`／`Save-StationBoardArtifact`／`Read-CacheBaselineFromExistingArtifact`／
`Read-PatToken`／`Get-GithubHeaders`／`Write-Utf8BomFile`／`Set-ConsoleUtf8`（皆 T-09）。

**「呼叫 `New-FleetWorkCardModel`（T-16）產生每張卡片的基礎 model，僅覆寫既有三欄
（`ReconcileDataTimeText`／`StatusReasons`／`StatusColor`）」是本票「不得新增字卡欄位」的落地手段**——
三欄本來就是 t09 既有欄位（`render-board.ps1` L684「對帳資料時間」欄、L642-646「燈號理由」清單、
L632 狀態燈 dot class），T-17 只是把對帳結果算出來塞進這三個既有欄位，不開新欄、不改
`Build-WorkCardHtml` 的 HTML 結構本身。

**另立而非修改的一處**（比照 `build/t16/README.md` 對 T-09 `Build-StationBoardReport` 的同一種取捨，
理由同構）：

- `Build-ReconciledFleetBoardReport`——t16 的 `Build-FleetBoardReport` 內部私有迴圈直接寫死呼叫
  `New-FleetWorkCardModel`，**沒有任何注入點**能讓外部替換「每張卡片的 model 怎麼組」這一步，而這正是
  T-17 疊加對帳三態必須介入的唯一位置。t16 面對 t09 時也是同一個死結（t09 `Build-StationBoardReport`
  同樣沒有 model 建構注入點），t16 的解法是另立一份「聚合版」頂層組裝函式，只呼叫 t09 的低階純函式；
  本票原樣複製這個解法，對象換成 t16。函式本體逐字對應 t16 版本（banner／空狀態／快取邏輯完全未改
  語意），差異只在每個 work 迴圈內插入「呼叫 `Get-PlanWorkRecord`＋`Get-ReconcileStateForWork`，改呼叫
  `New-ReconciledFleetWorkCardModel`」這一段（見檔內註解「T-17 新增」標註處）。

`fleet-board-template.html`（T-16 所有）**直接讀取重用，未複製一份、未修改**——本票的字卡內容沒有
新增任何欄位或新的 banner 種類，t16 樣板既有的 `<dt>對帳資料時間</dt>`／`燈號理由` 區塊與四色 CSS
（`.dot--red`／`.dot--green`…）已足夠承載「範圍外／漂移／對帳未執行」三態的視覺呈現，故不需要像 t16
對 t09 樣板那樣另立一份（t16 當時是因為需要新文案與新 CSS 規則；T-17 兩者都不需要）。

## 驗收條件逐條對應

| 驗收 | 內容 | 對應離線測試 | 實跑結果 |
|---|---|---|---|
| ① | `plans/` 整個查無此 work ⇒ 字卡上「對帳範圍外」標示**存在**且該卡非綠燈 | 群組 C（C3）、群組 D（D1，真實 HTML 字面斷言）、群組 G（紅燈①） | PASS |
| ② | `plans/` 有此 work 但票缺 ⇒ 漂移筆數＝人造差異集筆數，逐筆票號相符 | 群組 A（A1-A9，Compare-PlanVsGithubTickets 核心）、群組 C（C5）、群組 D（D2） | PASS |
| ③ | 由 run 觸發的刷新 ⇒ 標示為「本次未對帳，沿用 <時間> 結果」 | 群組 E（E1-E3，確認 T-17 不干預 t16/t09 既有行為） | PASS |
| ④ | `plans/` 不可用 ⇒ 標示為「對帳未執行」 | 群組 B（B1，讀取層）、群組 C（C1/C2）、群組 F（端到端，多 work 全部標記） | PASS |
| 守恆檢查（非紅燈） | 對帳前後兩側內容摘要不變 | 群組 I（I4-I7，plans/ 樹狀雜湊＋GitHub Snapshot 物件雜湊＋檔案逐字比對，三重驗證） | PASS |

驗收①②③④皆在**人造 fixture／離線 mock**上執行（群組 A-J 的 mock Snapshot／plans/ fixture 皆為測試
作者手造的 pscustomobject 字面值或臨時 JSON 檔），🚫 未連任何真實 GitHub API、未讀寫任何真實
`ak-project-management` plans/（群組 B／I 對真實暫存目錄的讀寫僅發生在系統 temp 目錄下的一次性測試
資料夾，測試結束於 `finally` 區塊清除）。

## 三態（＋對帳未執行）不塌成兩態——怎麼驗的

Spec 原文「範圍外／未對帳／漂移」三種標示 ＋ 票面驗收④額外的「對帳未執行」，共四種**互斥**情境：
`not-executed`（plans/ 全域不可用或該 work 局部讀取失敗）／`out-of-scope`（plans/ 查無此 work）／
`in-scope-clean`（已對帳、無漂移）／`in-scope-drift`（已對帳、有漂移）。

**群組 J 專門驗證「不塌成兩態」**：對同一組輸入分別跑四種情境，斷言 ①四個 `Kind` 兩兩不同
（J2/J3/J4）、②去重後恰有 4 種（J5）、③「查不到」二態（`not-executed`／`out-of-scope`）的
`DriftCount` 恆為 0（J6/J7，證明「查不到」不會被誤標成「有筆數的不一致」）、④「不一致」態
`DriftCount` 恆＞0（J8）。另外群組 D 用**真實 render 出的 HTML 字面**交叉比對（D1 範圍外含
「對帳範圍外」不含漂移計數字樣、D2 漂移含「漂移 N 筆」不含「對帳範圍外」、D3 對照組零漂移時兩者皆
不含）——不是只在抽象 model 層面斷言「型別不同」，而是連最終使用者看到的畫面文字都交叉驗證過彼此
不會誤植對方的字樣。

「查不到」（`out-of-scope`／`not-executed`）與「不一致」（`in-scope-drift`）是本票刻意分開處理的兩類
語意：前者代表「這份資料對帳器根本沒看到」（不知道、不能比對），後者代表「兩邊都看到了、但內容兜不
起來」（知道、且確認有落差）——票面明文禁止的正是把這兩種語意混成同一個「異常」標籤，讓使用者分不清
「我該去補一份 plans 紀錄」還是「我該去查為什麼兩邊對不上」。

## 守恆檢查怎麼實作、怎麼證明真的沒寫入

**實作**（`reconcile-board.ps1` 區塊 5）：`Get-PlansTreeDigest`（只讀，遞迴列舉 `$PlansRoot` 下所有
檔案，相對路徑＋內容串接後算 SHA256）與 `Get-SnapshotDigest`（只讀，序列化 GitHub 側 Snapshot 物件後
算 SHA256）。離線測試群組 I（I4-I7）在呼叫 `Build-ReconciledFleetBoardReport`（含完整一輪對帳：讀
plans/ fixture、比對漂移、算三態）**前後各算一次**，斷言：

1. `Get-PlansTreeDigest` 前後雜湊值相同（I5）——證明 plans/ 樹沒有任何檔案被新增／修改／刪除。
2. `Get-SnapshotDigest` 前後雜湊值相同（I6）——證明本票函式沒有就地竄改呼叫端傳入的 Snapshot 物件
   （PowerShell `pscustomobject` 是參考型別，若程式碼誤寫成 `$w.Tickets = ...` 這類寫法會就地污染
   呼叫端資料，此 hash 比對能抓到這類記憶體層級的「偷改」錯誤，是 hash 比對唯一存在的意義）。
3. 對 plans/ fixture 檔案內容做**逐字字串比對**（I7，非只靠 hash，雙重保險——萬一雜湊函式本身有 bug
   或碰撞，逐字比對仍能抓到差異）。

**證明真的沒寫入**：三項斷言皆為 `Assert-Equal`（相等比對，非只檢查「沒拋例外」），且 I4 先斷言
「本輪對帳確實執行到底（有回傳非空 Html）」，排除「因為根本沒跑到讀寫路徑所以雜湊自然相同」這種假
陽性——本輪對帳**真的**讀過 plans/ fixture（W-cons 有紀錄、比對出正常結果），跑完之後雜湊仍相同，
才是有意義的守恆證據。另外群組 I（I1-I3）用 grep 對 `reconcile-board.ps1` 的**可執行程式碼**（已剝除
`<# #>` 區塊與 `#` 開頭整行註解，避免文件說明段落誤觸自己的靜態檢查）做靜態掃描，確認零命中
`Set-Content|Out-File|New-Item|Remove-Item|Move-Item|Copy-Item|Add-Content`（plans/ 寫入 cmdlet）、
`-Method Put|Post|Patch|Delete`（GitHub 寫入端點）、`set-labels|close-issue|create-issue`（gate／
intake／run 專屬的佇列項字面）——三者皆零命中，見下方「三道自檢」。

## 紅燈斷言原文與「真的失敗」的證據摘要（Spec §6 註 A：紅是斷言失敗的紅）

票面原文：「先對人造差異集跑『漂移筆數＝差異集筆數』與『範圍外標示存在且非綠燈』兩條正向斷言 ⇒ 必紅
（未實作時筆數為 0、標示不存在）」。`t17-offline-test.ps1` 群組 G 用 `-BugDisableReconcile`（唯一的
紅燈旁路旗標，複製 T-17 出票前 `ReconcileDataTimeText` 欄位的真實原始佔位文案「對帳：尚未實作
（T-17 範圍），本欄位僅保留位置」、`DriftCount` 恆 0、不強制非綠燈——這正是本票實作**之前**這個欄位
的真實行為，非憑空編造的假 bug）。

**紅燈①**（驗收②，漂移筆數）——斷言原文：

> `漂移筆數＝人造差異集筆數（3）`：對 `Get-ReconcileStateForWork` 開啟 `-BugDisableReconcile` 後，
> 斷言 `$T17BugState_Drift.DriftCount -eq $Script:FixtureDriftSet.ExpectedDriftCount` 必須真的失敗。

實跑證據：

```
[RED-EVIDENCE FAIL（真的斷言失敗，存證）] 「漂移筆數＝人造差異集筆數（3）」斷言（旁路開啟，預期真的失敗）
[PASS] 紅燈存證①：旁路開啟時「漂移筆數＝差異集筆數」斷言確實失敗（未實作時筆數恆為 0）
[PASS] 紅燈存證①附證：旁路開啟時 DriftCount 確實恆為 0（複製未實作前的行為）
```

**紅燈②**（驗收①，範圍外標示存在且非綠燈）——斷言原文：

> `範圍外標示存在且非綠燈`：對 `Get-ReconcileStateForWork` 開啟 `-BugDisableReconcile` 後，斷言
> `($T17BugState_OutScope.ReconcileDataTimeText -match '對帳範圍外') -and $T17BugState_OutScope.ForceNonGreen`
> 必須真的失敗。

實跑證據：

```
[RED-EVIDENCE FAIL（真的斷言失敗，存證）] 「範圍外標示存在且非綠燈」斷言（旁路開啟，預期真的失敗）
[PASS] 紅燈存證②：旁路開啟時「範圍外標示存在且非綠燈」斷言確實失敗（未實作時標示不存在、不強制非綠燈）
[PASS] 紅燈存證②附證：旁路開啟時文案退回原始佔位字串
```

旁路開啟時，`ReconcileDataTimeText` 真的退回 `對帳：尚未實作（T-17 範圍），本欄位僅保留位置`
（`$T17BugState_OutScope.ReconcileDataTimeText -match '尚未實作'` 為真）——這就是斷言失敗的具體樣子，
非載入或 collection 失敗。關閉旁路（`Get-ReconcileStateForWork` 預設路徑）重跑同一組輸入，群組 C3／
C5／D1／D2 全轉綠（群組 G 末尾兩條「G-關閉旁路」斷言即再次確認）。

`$BugDisableReconcile` 旗標在 `reconcile-board.ps1` 檔頭與參數區具名標註「⚠️ 僅供紅燈驗證，正式流程
禁用」，且 `Invoke-ReconciledBoardRender`／腳本進入點 `if (-not $T17FunctionsOnly) {...}` 的預設呼叫
路徑**從不帶入**此旗標——真正的紅燈證據被獨立記錄在 `$Script:RedLightLog`（列印區塊「紅燈存證
log」），不與主線 73 項 PASS/FAIL 總計混在一起，避免出貨版本永遠帶著一個失敗的斷言。

## 獨立預期值來源（Spec §3.5 註 C）

`t17-offline-test.ps1` 頂部 `$Script:FixtureDriftSet` 為人造的差異集（plan 側票清單與 GitHub 側票
清單皆為測試作者手寫固定字面值，逐筆手算「應落在哪一類漂移、應有幾筆」——4 筆 plan 紀錄 ＋ 3 筆
GitHub 紀錄，交叉比對後期望恰有 3 筆漂移、票號逐一列出），另有群組 B 的 plans/ fixture JSON（手寫
字面值，非任何函式回填）與群組 F/I 的 mock Snapshot（AnchorIssue／Tickets 皆為 `New-T17MockIssue`
手造的固定值）。這些數字**從未**由 `Compare-PlanVsGithubTickets`／`Get-ReconcileStateForWork`／
`Build-ReconciledFleetBoardReport` 自身算過再回填；比對時一律拿這些固定值當 `Assert-Equal` 的
`-Expected`，被測函式輸出只出現在 `-Actual` 那一側。

## 只報不修：程式碼層守門（不是只有文件宣告）

1. **無任何路徑可寫 `plans/`**：`Get-PlanWorkRecord`（唯一讀 plans/ 的函式）只用
   `Test-Path`／`Get-Content`／`ConvertFrom-Json` 三個唯讀 cmdlet；本檔（含守恆檢查工具）**不含**
   `Set-Content`／`Out-File`／`New-Item`／`Remove-Item`／`Move-Item`／`Copy-Item`／`Add-Content` 任何
   一個寫入 cmdlet——見下方「三道自檢」的 grep 證據（對可執行程式碼掃描，已剝除文件註解段落避免
   「說明本檔不含什麼」的文字誤觸自己的檢查）。
2. **無任何路徑可寫 GitHub**：`grep -n "Method Put|Method Post|Method Patch|Method Delete"` 對
   `reconcile-board.ps1` 零命中——本票不直接呼叫任何 GitHub REST 端點，GitHub 側資料完全來自 t16
   `Get-FleetSnapshot`（其本身已在 T-16 驗收時確認全程只用 `-Method Get`，見 `../t16/README.md`）。
3. **無任何佇列項產生**：`grep -n "set-labels|close-issue|create-issue"` 零命中——本票不產生任何
   label／issue 開關類佇列項，與票面第八欄「不可逆動作：無，理由＝只報不修」一致。唯一的寫入動作是
   `Invoke-ReconciledBoardRender` 內對 `Save-StationBoardArtifact`（T-09 所有，未修改重用）的呼叫，
   寫的是本機面板 artifact HTML 檔（非 GitHub、非 plans/），與 T-09／T-16 的「唯一寫入」性質一致。
4. **守恆檢查**（見上一節）是這條守門的機器化回歸保險：不是只信任「程式碼看起來沒有寫入語句」，而是
   實際跑一輪完整對帳、比對前後雜湊與逐字內容，證明「看起來沒有」等於「真的沒有」。

## 三道自檢（交件前實跑）

**① BOM 檢查**（三個 `.ps1` 皆以 Python `open(p,'wb').write(b'\xef\xbb\xbf'+s.encode('utf-8'))` 手法
確認）：

```
reconcile-board.ps1 BOM OK, size 40091
t17-offline-test.ps1 BOM OK, size 41942
build-sample-reconciled-board.ps1 BOM OK, size 4971
```

**② `/opt/pwsh/pwsh` `ParseFile`**（三個 `.ps1` 全過）：

```
OK: reconcile-board.ps1
OK: t17-offline-test.ps1
OK: build-sample-reconciled-board.ps1
```

**③ 離線測試**（`/opt/pwsh/pwsh -NoProfile -File t17-offline-test.ps1`）：

```
通過：73　失敗：0　總計：73
離線測試：PASS（全數 73 項斷言通過）
```

（含前述兩項「紅燈存證」——旁路開啟時真的斷言失敗、記錄於獨立 log 區塊，不計入上述 73 項；對「紅燈
確實發生」這件事本身的 meta 判定計入並列在 73 項之中，即「紅燈存證①」「紅燈存證②」兩條 PASS。）

**只報不修 grep 自檢**（對可執行程式碼，已剝除文件註解）：

```
[PASS] I1 reconcile-board.ps1 可執行程式碼不含任何 GitHub 寫入 HTTP 動詞（Put/Post/Patch/Delete）
[PASS] I2 reconcile-board.ps1 可執行程式碼不含 plans/ 寫入 cmdlet（Set-Content/Out-File/New-Item/Remove-Item/Move-Item/Copy-Item/Add-Content）
[PASS] I3 reconcile-board.ps1 可執行程式碼不產生 label/issue 開關類佇列項字面（set-labels/close-issue/create-issue）
```

## CLI smoke test（確認不是 no-op，見指示第 7 點）

直接以 `pwsh -File reconcile-board.ps1`（非 dot-source）跑兩次，確認頂層參數真的流到底、沒有被
transitively dot-source 進來的 t16／t09 同名參數（`$T16Repos`／`$WorkId`／`$PrimaryRepo`／
`$OutputPath`…）悄悄覆蓋（T-12/T-13 曾踩過的坑，其中一次讓 CLI 悄悄 no-op）：

```
$ pwsh -File ./reconcile-board.ps1
Exception: ...reconcile-board.ps1:657
請提供 -T17Repos（或改用 -T17FunctionsOnly dot-source 本檔供測試呼叫）
# ⇒ 缺 -T17Repos 時正確中止於本檔自己的進入點守門，證明本檔的 param 區塊真的生效、不是被繞過的空殼。

$ pwsh -File ./reconcile-board.ps1 -T17Repos 'acme/repo-a' -T17PatPath '/tmp/t17-distinctive-nonexistent-pat-marker.txt'
Exception: ...t09/render-board.ps1:116
PAT 檔案不存在：/tmp/t17-distinctive-nonexistent-pat-marker.txt
# ⇒ 帶了一個「獨一無二、絕不可能是任何預設值」的 -T17PatPath 字串，錯誤訊息逐字回顯這個字串——
#   證明它從 CLI 參數一路流過 Invoke-ReconciledBoardRender → Read-PatToken（定義於 t09，經 t16
#   transitively dot-source 進來），沒有在中途被 $T16PatPath 或裸名 $PatPath 的預設值悄悄取代。
#   若曾經發生 cascade 覆蓋 bug，這裡看到的路徑會是 "$PSScriptRoot/pat.txt"（某個其他目錄的預設值），
#   而不是我們自己輸入的這串 marker。
```

兩次呼叫皆退出碼 1（正確失敗，非靜默成功），且 `build-sample-reconciled-board.ps1`（使用
`-MockSnapshot` 略過網路）完整跑過一輪，正確產生兩份範例 HTML（見下方「使用者要跑的指令」）。

## 使用者要跑的指令（本機 Windows PowerShell 5.1 或 pwsh）

```powershell
cd <plugin repo>\build\t17

# 離線測試（沙盒／CI／本機皆可跑，不連網）
pwsh -NoProfile -File t17-offline-test.ps1

# 產生兩份範例面板（純離線，不連網）
pwsh -NoProfile -File build-sample-reconciled-board.ps1

# 正式使用（需本機真實 PAT ＋ 真實 ak-project-management plans/ 目錄；未在本沙盒實跑，見下方「誠實聲明」）
.\reconcile-board.ps1 -T17Repos 'owner/repo-a','owner/repo-b' -T17PatPath <PAT 檔路徑> -T17PlansRoot <ak-project-management plans/ 路徑>
```

## 誠實聲明：deferred-to-CI／best-effort／假設清單

1. **`Get-FleetSnapshot`（T-16 所有，透過 dot-source 重用）未在本沙盒實跑其真實 REST 分支**——本票
   完全繼承 T-16 對此函式的既有誠實聲明（環境無 GitHub 連線，指示明文禁止呼叫真實 API）。T-17 本身
   **不新增**任何 GitHub REST 呼叫，故沒有新增這一類的風險面，只是原樣繼承。
2. **`plans/` fixture 格式是本票的假設，非正典**——Spec 與既有 `build/` 目錄皆未定義
   `ak-project-management` 實際的 `plans/` 落檔格式（檔案結構、欄位命名、票狀態的詞彙表）。本票採用
   最小、明確、可測試的假設：`$PlansRoot/<WorkId>.json`，形狀
   `{ "workId": "...", "tickets": [ { "ticketRef": "owner/repo#N", "status": "open"|"closed" } ] }`，
   `TicketRef` 格式對齊 GitHub issue 的天然穩定識別鍵（`owner/repo#number`）。**差什麼才能收斂為
   正典**：需要 `ak-project-management` skill 實際落檔的一份真實 `plans/` 樣本，或該 skill 的格式
   規格文件；屆時只需改寫 `Get-PlanWorkRecord` 的解析段（區塊 2），`Compare-PlanVsGithubTickets`／
   `Get-ReconcileStateForWork`（區塊 1／3，核心比對邏輯）與所有 model／render 層完全不受影響，因為
   它們吃的是已正規化的 `{TicketRef; Status}` 物件，不依賴原始檔案格式。
3. **「GitHub 側只含 open 票」對漂移判定的取捨是本票的設計決策，已在程式碼與測試中具名**——§4.2
   聚合定義（一次跨 repo search 只抓 open issues）＋§4.3「同一次聚合結果，不另發查詢」的雙重限制下，
   GitHub 側資料集structurally 不含已關閉票。若不做任何取捨，直接對 GitHub 側「缺席」一律判定
   `plan-only` 漂移，會把「票已正常結案」誤判為「票缺」假警報。本票的解法（見
   `Compare-PlanVsGithubTickets` 檔內註解與 README「三態不塌成兩態」節旁的設計說明）：只有當 plan
   側狀態為 `open` 時，GitHub 側缺席才算 `plan-only` 漂移；plan 側狀態非 `open`（如 `closed`）而
   GitHub 側缺席，視為預期缺席、不算漂移。此取捨已用群組 A（A7）與獨立 fixture 覆蓋測試，非事後
   合理化。
4. **`Get-PlanWorkRecord` 的真實檔案系統權限錯誤情境（如目錄存在但無讀取權限）未在本沙盒實測**——
   沙盒環境以 root 執行，難以可靠地構造「目錄存在但讀取被拒」的情境；程式碼邏輯已用 try/catch 包住
   `Test-Path`／`Get-Content`，理論上會被同一條 catch 分支處理（歸類為 `RootAvailable=$false`／
   `Found=$null`），但這條分支本身未被真實觸發過，僅由邏輯覆蓋（`-PlanReader` 注入測試模擬了同等效果，
   見群組 B5，但那是「模擬」不是「真實觸發」）。
5. **`reconcile-board.ps1` 尚未接入 `../t09/station-board/SKILL.md`**（該檔屬 `build/t09/` file
   ownership，本票不修改）——票面驗收條件本身不要求接線，僅要求對帳三態＋漂移筆數＋守恆檢查的實作與
   離線驗證；若要讓 `/station-board` 完整模式真正呼叫到本票的對帳邏輯，屬後續整合工作（不在 T-17
   scope，票面 scope 明文「對帳三態、漂移筆數回報與守恆檢查；不含任何自動修復」，且未提及 SKILL.md
   接線動作）。此點與 T-16 README「誠實聲明」第 5 項的分界完全同構。
6. **`project-manager` sub-agent 的實際 dispatch 未在本票實作**——票面 executor basis 明文
   「三態判定與筆數比對是實作題；`project-manager` 於執行期被 dispatch 負責比對本身」，意即：本票
   交付的是「比對邏輯本身」（`Compare-PlanVsGithubTickets`／`Get-ReconcileStateForWork` 等），實際
   執行期由 `/station-board` 完整模式 dispatch `project-manager` 這件事屬編排層接線（見上一項，同樣
   deferred）。本票所有函式皆可被未來的 dispatch 呼叫端直接呼叫，不需重寫。

以上六項與 T-09／T-16 交付時的先例（各自的「動態測試待本機真實 PAT／real fixture」誠實聲明）性質
一致，不是遺漏，是環境限制與 scope 邊界下的如實分界。
