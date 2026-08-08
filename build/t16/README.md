# T-16 · 跨 repo 聚合、work ID 分組、逐 repo 進度與消失偵測

依 `Spec_station-command_v1.11.md` §4.1／§4.2／§4.4／§3.1／§3.3 與 `tickets-draft.md` T-16（GitHub issue #17）定案。
地基：`../t09/render-board.ps1`（T-09 單 work 字卡最小可用；本票**不修改**該檔或 `../t09/board-template.html`，
file ownership，理由與擴充方式見下方「與 T-09 的關係」）。

## 目錄結構

```
build/t16/
  aggregate-board.ps1          核心：跨 repo 聚合＋work-id 分組＋逐 repo 進度＋消失偵測（dot-source T-09）
  fleet-board-template.html    多 work 面板外殼樣板（另立，不改 t09 board-template.html）
  t16-offline-test.ps1         離線 mock 測試：61 項斷言，十群組 A-J（沙盒可跑，不連網）
  build-sample-fleet-board.ps1 sample-fleet-board.html 的產生腳本（3 個示範 work + 1 個消失偵測示範）
  sample-fleet-board.html      成品範例，可直接用瀏覽器開啟
  README.md                    本檔
```

## 與 T-09 的關係（複用、不重寫；另立、不修改）

T-09 交付單一已知 work 的字卡 render 器；T-09 README「scope 邊界」已明文本票（T-16）負責「跨 repo 多 work
聚合與 anchor 消失偵測」。T-16 **dot-source** `../t09/render-board.ps1 -FunctionsOnly`，直接複用其純函式：
`Build-WorkCardHtml`（**逐字沿用，未修改**——這是「本票不得新增欄位」的落地手段：字卡長什麼樣仍由 T-09
決定，T-16 只負責餵給它正確分組後的資料）、`ConvertTo-StatusLight`、`Get-StationLabelInfo`、
`Build-RunningAndStaleCounts`、`Build-StepperHtml`、`Build-RepoProgressHtml`、`Get-ExecutorFromBody`、
`Get-ParticipatingReposFromBody`、`ConvertTo-HtmlEncoded`、`ConvertTo-BoardIssue`、`ConvertTo-SafeArray`、
`Save-StationBoardArtifact`、`Read-CacheBaselineFromExistingArtifact`、`Get-TicketDirtyStationLabels`、
`Read-PatToken`、`Get-GithubHeaders`、`Write-Utf8BomFile`。

**另立而非修改的三處**（比照 `build/t12/run-queue-ext.md` 先例：同一 repo 內另立擴充檔、不改原檔）：
1. `fleet-board-template.html`——t09 樣板的 `<h1>`／meta-line 文案固定「單 work 檢視」語意（該檔內建註解
   甚至已預告「跨 repo 多 work 聚合屬 T-16」），且需要多卡片間距 CSS（t09 只需單卡）與多一種 banner 樣式
   （`.banner--disappeared`）。CSS 變數與既有 class 命名逐字複製，確保卡片仍套得上樣式。
2. `Build-FleetBannersHtml`——t09 `Build-BannersHtml` 的 `switch` 只認 4 種 Kind，多一種 `disappeared`
   需要另一種樣式對照，函式本身很小，於 t16 內重寫一份（~15 行）而非修改原檔。
3. `Get-FleetStationInfoWithLabel`——包一層 t09 `Get-StationLabelInfo`，確保「站別來源不明」四字在**所有**
   髒資料情境（不只是「anchor 無任何站別 label」那一種）都恆定出現，滿足驗收⑥的字面要求，不改 t09 原函式。

## 驗收條件逐條對應

| 驗收 | 內容 | 對應離線測試 | 實跑結果 |
|---|---|---|---|
| ① | 同 work ID 的 milestone 分散兩 repo ⇒ 合併為一張字卡並分列兩組百分比、不出現合成單一數字 | 群組 C（C1-C5，尤其 C3/C3b/C4） | PASS |
| ② | milestone 同名但 work ID 不同 ⇒ 不得合併 | 群組 A（誤併紅燈＋A1-A9）、群組 B（B5-B8，補查詢路徑的標題撞名陷阱） | PASS（含 2 項紅燈存證） |
| ③ | 關掉一個站 3 的 anchor ⇒ 出現「工作消失」＋work ID＋上次所見站別 | 群組 D（D1-D3） | PASS |
| ④ | 刪除面板 artifact 後首刷 ⇒ 出現「消失偵測不可用（無基線）」且字卡內容與刪除前一致 | 群組 D（D4-D5，無基線紅燈）＋群組 F（F1-F3，字卡內容逐字相同） | PASS（含 1 項紅燈存證） |
| ⑤ | 零筆＋無基線 ⇒ 兩訊息並列 | 群組 E（E1-E4） | PASS |
| ⑥ | 手動竄改過站別的工作 ⇒ 字卡紅燈標「站別來源不明」 | 群組 G（G1-G3，兩種竄改手法＋對照組） | PASS |

驗收③④的「關掉一個站 3 的 anchor」「刪除面板 artifact」**全部在人造 fixture／離線 mock 上執行**（群組 D／F
的 mock Snapshot／CacheBaseline 皆為測試作者手造的 pscustomobject 字面值），🚫 未對任何真實 repo 執行關
anchor 步驟，亦未寫入或刪除任何真實檔案以外的東西（群組 I 對真實暫存檔的讀寫僅發生在系統 temp 目錄下的
一次性測試資料夾，測試結束於 `finally` 區塊清除）。

## 紅燈斷言原文與「真的失敗」的證據摘要（Spec §6 註 A：紅是斷言失敗的紅）

**紅燈①（驗收②，誤併）**：`t16-offline-test.ps1` 群組 A。斷言原文——

> `不同 work-id 不得合併`：開啟 `-BugGroupByMilestoneTitle`（僅供紅燈驗證的旁路旗標，改用
> `milestone.Title` 分組，複製「未實作時以名稱分組會誤併」的錯誤行為）後，斷言
> `$g.ContainsKey('W-alpha') -and $g.ContainsKey('W-beta') -and 兩者各恰 1 張票` 必須真的失敗。

實跑證據（見 `t16-offline-test.ps1` 執行輸出「紅燈存證 log」區塊，本檔亦附於下方「三道自檢」原始輸出）：

```
[RED-EVIDENCE FAIL（真的斷言失敗，存證）] 誤併旁路開啟：「不同 work-id 不得合併」斷言（預期真的失敗）
[PASS] 紅燈存證①：旁路開啟時「不同 work-id 不得合併」斷言確實失敗（誤併真的發生）
[PASS] 紅燈存證①附證：誤併後兩張票被塞進同一個鍵為 Sprint-42（標題）的群組
```

旁路開啟時，兩張分屬 W-alpha／W-beta、milestone 標題皆為 `Sprint-42` 的票被誤併進同一個以 `Sprint-42`
為鍵的群組（`$T16BugGrouped.Groups['Sprint-42']` 恰有 2 張票）——這就是斷言失敗的具體樣子，非載入或
collection 失敗。關閉旁路（`Group-FleetIssuesByWorkId` 預設路徑）重跑同一組輸入，群組 A1-A9 全轉綠。

**紅燈②（驗收④前置，無基線 banner）**：`t16-offline-test.ps1` 群組 D。斷言原文——

> `消失偵測不可用（無基線）banner 必須存在`：`CacheBaseline=$null` 時開啟 `-SkipNoBaselineBanner`
> （僅供紅燈驗證的旁路旗標）後，斷言 `$T16RDSkip.ErrorStates -contains 'no-baseline'` 必須真的失敗。

實跑證據：

```
[RED-EVIDENCE FAIL（真的斷言失敗，存證）] 無基線旁路開啟：「消失偵測不可用（無基線）banner 必須存在」斷言（預期真的失敗）
[PASS] 紅燈存證②：旁路開啟時「無基線 banner 必須存在」斷言確實失敗
```

旁路開啟時 `ErrorStates` 真的不含 `no-baseline`（`Build-FleetBoardReport` 內 `if ($noBaseline -and
-not $SkipNoBaselineBanner)` 這一整段被跳過）。關閉旁路（`Invoke-FleetBoardRender` 預設路徑永遠不帶
此旗標）重跑，群組 D4-D5 轉綠。

兩個旁路旗標皆在 `aggregate-board.ps1` 檔頭與參數區具名標註「⚠️ 僅供紅燈驗證，正式流程禁用」，且
`Invoke-FleetBoardRender`／腳本進入點 `if (-not $T16FunctionsOnly) {...}` 的預設呼叫路徑**從不帶入**
這兩個旗標——真正的紅燈證據被獨立記錄在 `$Script:RedLightLog`（列印區塊「紅燈存證 log」），不與主線
61 項 PASS/FAIL 總計混在一起，避免出貨版本永遠帶著一個失敗的斷言。

## 獨立預期值來源（Spec §3.5 註 C）

`t16-offline-test.ps1` 頂部 `$Script:FixtureWorkRepoMap` 為人造的 work↔repo 對應表（work ID、primary
repo、參與 repo 清單、票號皆為測試作者手寫字面值），另有各筆 mock milestone 的 open/closed issue 數字
（如 `OpenIssues=1; ClosedIssues=3` ⇒ 手算期望值 75%）——這些數字**從未**由 `Group-FleetIssuesByWorkId`／
`Get-FleetMilestoneRowsForWork`／`Build-FleetBoardReport` 自身算過再回填；比對時一律拿這些固定值當
`Assert-Equal` 的 `-Expected`，被測函式輸出只出現在 `-Actual` 那一側（見群組 A2-A7、B2-B7、I4-I5）。
群組 B 額外構造「同標題不同 work-id」的補查詢陷阱（`acme/repo-b` 回傳兩筆候選 milestone，一筆標題撞名
但屬於別的 work），驗證補查詢路徑（`Get-FleetMilestoneRowsForWork` 的 `-MilestoneListFetcher` 分支）
同樣以 description 而非 title 比對，不會被撞名誤導——這是驗收②在「補查詢」這條路徑上的延伸覆蓋。

## GitHub 唯讀與面板 artifact 唯一寫入（不可逆動作核對）

`grep -n "Method Put|Method Post|Method Patch|Method Delete"` 對本目錄全部 `.ps1` **零命中**（見下方
自檢原始輸出）——`aggregate-board.ps1` 全程只用 `Invoke-RestMethod ... -Method Get`（`Get-FleetSnapshot`／
`Get-FleetMilestoneRowsForWork` 的補查詢分支）。唯一的寫入動作是 `Save-StationBoardArtifact`（複用自
t09，寫面板 HTML 到本機磁碟，非 GitHub 端點）。`grep -n "set-labels|close-issue|create-issue"` 同樣零
命中——本票不產生任何佇列項（`Read-FleetQueueInfoForWork` 只讀，不寫），與票面「不可逆動作：無」一致。

## 三道自檢（交件前實跑）

**① BOM 檢查**（三個 `.ps1` 皆以 Python `open(p,'wb').write(b'\xef\xbb\xbf'+s.encode('utf-8'))` 手法確認）：

```
aggregate-board.ps1 BOM OK, size 41547
t16-offline-test.ps1 BOM OK, size 38518
build-sample-fleet-board.ps1 BOM OK, size 8722
```

**② `/opt/pwsh/pwsh` `ParseFile`**（三個 `.ps1` 全過）：

```
OK: aggregate-board.ps1
OK: build-sample-fleet-board.ps1
OK: t16-offline-test.ps1
```

**③ 離線測試**（`/opt/pwsh/pwsh -NoProfile -File t16-offline-test.ps1`）：

```
通過：61　失敗：0　總計：61
離線測試：PASS（全數 61 項斷言通過）
```

（含前述兩項「紅燈存證」——旁路開啟時真的斷言失敗、記錄於獨立 log 區塊，不計入上述 61 項；對「紅燈確實
發生」這件事本身的 meta 判定計入並列在 61 項之中，即「紅燈存證①」「紅燈存證②」兩條 PASS。）

## 使用者要跑的指令（本機 Windows PowerShell 5.1 或 pwsh）

```powershell
cd <plugin repo>\build\t16

# 離線測試（沙盒／CI／本機皆可跑，不連網）
pwsh -NoProfile -File t16-offline-test.ps1

# 產生範例面板（純離線，不連網）
pwsh -NoProfile -File build-sample-fleet-board.ps1

# 正式使用（需本機真實 PAT；未在本沙盒實跑，見下方「誠實聲明」）
.\aggregate-board.ps1 -T16Repos 'owner/repo-a','owner/repo-b','owner/repo-c' -T16PatPath <PAT 檔路徑>
```

## 誠實聲明：deferred-to-CI／best-effort 清單

1. **`Get-FleetSnapshot`（跨 repo search 主查詢）與 `Get-FleetMilestoneRowsForWork` 的真實 REST 分支未在
   本沙盒實跑**——環境無 GitHub 連線，且指示明文禁止呼叫真實 API／連外網。離線測試改為對
   `Get-FleetMilestoneRowsForWork` 用 `-MilestoneListFetcher` 注入 scriptblock 覆蓋整條補查詢路徑的邏輯
   （不是繞過，是用假資料源替換真實 HTTP 呼叫，函式本體邏輯本身有被執行到），`Get-FleetSnapshot` 本身
   （含跨 repo search 語法組字串、分頁、`OR` 查詢語法是否被 GitHub search 正確解析）則完全未實跑。
   **差什麼才能驗完**：需一組真實 PAT ＋ 至少兩個測試 repo（各建一個 work，milestone 撞名但 work-id
   不同），跑 `aggregate-board.ps1 -T16Repos ...` 對照期望輸出——這與 T-09 `t09-test.ps1` 的先例（該檔
   同樣需要本機真實 PAT 才能補完「旁路旗標接上真實 GitHub 404」那段）性質相同，本票尚未提供對應的
   `t16-test.ps1`（票面驗收條件未要求動態測試腳本，僅要求離線測試＋範例面板，故未額外產出；若後續需要，
   可比照 t09-test.ps1 的結構直接補一份）。
2. **`is:issue is:open (label:"sc:work" OR label:"sc:ticket")` 這個 GitHub search 查詢語法字串未經真實
   GitHub search API 驗證**——依公開文件記憶寫成，语法上应可行（GitHub search 自 2021 年起支援
   `label:x OR label:y` 佈林運算式），但字面正確性（含跨 repo 的 `repo:` 子句與 `OR` 群組混用時的優先序）
   仍待真實環境確認。若語法有誤，`Get-FleetSnapshot` 的 `catch` 區塊會把它降級為「數據過期」硬性失敗
   （§4.4 已定義的行為），不會靜默漏資料，但仍應在有真實 PAT 的環境跑一次確認語法本身無誤。
3. **逐 repo milestone 進度的「補查詢」路徑對「該 repo 完全沒有任何票（連 closed 都沒有）」情境的行為**
   （`Get-FleetMilestoneRowsForWork` 找不到任何符合 description work-id 的 milestone ⇒ 回「尚無
   milestone」）已由群組 B（`acme/repo-nomatch`）覆蓋，但這是 mock fetcher 模擬，非真實 GitHub milestone
   列表 API 回應形狀的逐欄位核對（例如 `state=all` 參數是否正確涵蓋已關閉的 milestone）——best-effort，
   欄位名稱依 GitHub REST 文件慣例（`open_issues`／`closed_issues`／`description`），未實測驗證。
4. **`Get-FleetSnapshot` 的分頁與 `HitPageCap` 邏輯**（直接複製 T-09 `Get-BoardTicketsQuery` 的分頁演算法
   模式）未針對「跨 repo 聚合下同時有數百個 work」的真實規模測試過效能與正確性，僅離線驗證過邏輯結構
   （`ConvertTo-SafeArray` 陷阱回歸），未做壓力測試。
5. **`Get-FleetSnapshot`／`Invoke-FleetBoardRender` 尚未接入 `station-board/SKILL.md`**（`SKILL.md` 屬
   `build/t09/` file ownership，本票不修改）——票面驗收條件本身不要求接線，僅要求聚合/分組/進度/消失偵測
   的實作與離線驗證；若要讓 `/station-board` 完整模式真正呼叫到跨 repo 聚合，屬後續整合工作（不在 T-16
   scope，T-16 scope 明文「聚合、分組、進度分列、消失偵測、站別來源不明顯示；不含對帳」，且票面未提及
   SKILL.md 接線動作）。

以上五項皆為「函式本身已完整實作且離線邏輯測試 100% 通過（61/61），但『打真實 GitHub 的那一段』與
『接進 SKILL.md 呼叫鏈』未在本沙盒環境驗證」，性質與 T-09／T-10 交付時的先例（`t09-test.ps1`／
`t10-test.ps1` 系列的「動態測試待本機真實 PAT」誠實聲明）一致，不是遺漏，是環境限制下的如實分界。
