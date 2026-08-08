---
name: station-board
description: 產生／就地更新單一 work 的常駐面板 artifact（一 work 一字卡），並輸出文字摘要。當使用者要求「看面板」「查進度」「/station-board」「工作現況」等語意時觸發（完整模式）；`/station-run`、`/station-gate` 結束時亦內部呼叫本 skill 的無對帳模式做順手刷新。
user-invocable: true
---

# 動作白名單（Spec §2，逐字承接）

`/station-board`：跨 repo 聚合（按 work ID）、建立／就地更新面板 artifact、輸出文字摘要；完整模式並起
`project-manager` 對帳。**唯一寫面板的實作點**（無對帳模式供 run／gate 呼叫，§4.5）。

允許動作：讀 GitHub（search／issues／milestones／issue body 欄位）｜讀本機 `plans/`｜**讀待寫佇列檔（§4.6）**｜**dispatch `project-manager`（僅完整模式對帳）**｜寫面板 artifact｜文字輸出。

🚫 **不寫 GitHub 任何欄位**——不寫狀態 label、不寫 assignee、不寫 issue body、不開關 issue 或 milestone。狀態 label 的唯一寫入者是 `/station-gate`（SC#7）。

🔒 **本檔案範圍鎖（T-09，已併入 T-23）**：本票只做**單一 work 字卡**（一次呼叫聚合一個 work 的資料，不做跨 work 分組）；**不含**跨 repo 多 work 聚合與 anchor 消失偵測（留給 T-16）、**不含**`plans/` 對帳三態實作（留給 T-17，本票只在字卡上留「對帳資料時間」欄位位置，誠實顯示「對帳：尚未實作（T-17 範圍）」，不偽稱已對帳）。已併入原 T-23 範圍：字卡含「待寫 N 筆」＋佇列非空時「在跑數量」「停滯票數」加註「寫入斷點期間不可信」；本白名單已擴充**讀待寫佇列檔**一項。

# No-Hands 邊界（§5.0／§2）

依 §5.0：面板由 `/station-board` 從 GitHub 現有資料**機械性 render**（欄位對應固定、無內容創作）⇒ **屬編排輸出，不屬 No-Hands 管轄的 deliverable**，Commander／主 session 得直接產生。本票交付的是**render 器**（`render-board.ps1` 的 `Build-StationBoardReport` 等純函式＋外層 orchestrator），不是手寫死的靜態 HTML——每次呼叫都是從當下的 GitHub 查詢結果重新算出字卡內容，符合「機械性推導、無創作裁量」的裁定要件。

若日後面板要加入「由 AI 撰寫的摘要／建議文字」（例如自動生成一段風險評估敘述），那部分即為 deliverable，須 dispatch，不得由本 skill 或 Commander 親手撰寫。

# 兩種呼叫模式（§4.5）

兩者共用**同一份實作**（`render-board.ps1` 的 `Invoke-StationBoardRender`），唯一寫面板的實作點不變，差異只在 `-NoReconcile` 開關：

| 模式 | 觸發者 | 行為 | 對帳資料時間欄位文案 |
|---|---|---|---|
| **完整模式** | 使用者手動呼叫 `/station-board` | 聚合＋（未來 T-17）對帳 | 目前誠實顯示「對帳：尚未實作（T-17 範圍），本欄位僅保留位置」——不偽稱已對帳，欄位位置已留好供 T-17 接手 |
| **無對帳模式** | `/station-run`、`/station-gate` 結束時內部呼叫（`-NoReconcile`） | 只聚合、跳過對帳 | 「本次未對帳，沿用 `<上次對帳時間>` 結果」（無上次紀錄時顯示「（尚無對帳紀錄）」） |

呼叫介面（供 `/station-run`、`/station-gate` 內部呼叫參考）：

```powershell
. ./render-board.ps1 -FunctionsOnly
Invoke-StationBoardRender -WorkId 'W-xxx' -PrimaryRepo 'owner/repo' -AnchorIssue <N> `
    -PatPath <PAT 檔路徑> -QueuePath <佇列檔路徑> -TemplatePath ./board-template.html `
    -OutputPath <輸出面板 HTML 路徑> [-NoReconcile]
```

# 字卡欄位（Spec §4.1，逐項對應）

工作名＋work ID｜primary repo＋參與 repo 清單（取自 anchor body 宣告，非使用者輸入猜測）｜所在站（五段視覺化 stepper）｜逐 repo 分列的 milestone 原生進度百分比（不加權、不合成單一數字）｜當前 executor（**讀票 body 的 `executor` 欄位，不讀 assignee**）｜狀態燈（紅／黃／綠，具名理由）｜在跑數量（open、站 4／5 且已有 assignee 的票數）｜停滯票數（24h 無更新）｜`legacy` badge｜**待寫 N 筆**（T-23 併入）｜對帳資料時間｜最後成功完整同步時間。

字卡欄位一律由「一次跨 repo issue search（含隨結果附帶的 issue body 欄位）＋ milestone 原生欄位」算出，不解析任何 repo 內檔案、不發額外查詢（唯一具名例外：讀本機待寫佇列檔）。停滯票數以 issue 的 `updated_at`（search 結果自帶欄位）作為「timeline 最新事件時間」的代理量測，避免逐票另發 timeline API 查詢（理由與取捨見 `render-board.ps1` 內 `Build-RunningAndStaleCounts` 的行內文件）。

# 四種錯誤狀態（§4.4，SC#4，硬規則）

🚫 禁止靜默失敗、禁止把失敗顯示成空狀態、禁止顯示未標記的舊資料。

1. **查詢失敗**：橫幅「數據過期」＋失敗對象具名＋上次成功時間；受影響字卡打灰標「未更新」（`card--stale` 樣式）。
2. **資料可能不完整**：橫幅「資料可能不完整」＋具名徵狀（觸頂：GitHub `total_count` 大於實際取得筆數；縮水：best-effort 比對上次成功值，跌幅逾五成才提出，避免與「票結案使計數自然下降」的正常現象混淆）。
3. **面板寫入失敗**：立即以文字輸出完整字卡摘要＋「面板未更新，畫面內容已過期（上次成功：<時間>）」。
4. **空狀態**：查詢成功、零筆 ⇒「目前無 active work」明示卡＋查詢條件；**零筆＋無基線** ⇒ 與「消失偵測不可用（無基線）」橫幅**並列顯示**，不得只留其一。

# 產出檔案（本票交付）

`render-board.ps1`——核心 render 器（純函式 `Build-StationBoardReport` ＋ impure 的抓資料／存檔／頂層入口函式，架構理由與 SNAPSHOT SCHEMA 定義見檔頭文件）。
`board-template.html`——外殼樣板（ADR-NP-003 自包 HTML；四個 `{{TOKEN}}` 佔位字面，`render-board.ps1` 純字面取代）。
`t09-offline-test.ps1`——離線 mock 測試（70 項斷言，全綠）。
`t09-test.ps1`——動態測試（需本機真實 PAT；紅燈為斷言失敗型，見檔頭文件）。
`sample-board.html`——用本 repo（station-command 自身）真實現況資料 render 的成品範例，可直接開啟檢視。
