# T-09 · 面板最小可用（單 work 字卡＋四種異常狀態；已併入 T-23 待寫揭露）

依 `Spec_station-command_v1.8.md` §4.1／§4.2／§4.4／§4.5／§4.6 與 `tickets-loop-draft.md` 對 T-09 的增修（併入原 T-23）定案。地基：`../t21/queue-format.md`（佇列格式）、`../t07/labels.json`（label scheme）、`../t10/`（gate 判定結果——本票只讀其寫下的 `sc:gate-fail` 等 label，不呼叫其腳本）。

## 目錄結構

```
build/t09/
  station-board/SKILL.md     動作白名單宣告＋兩種呼叫模式（完整／無對帳）說明
  render-board.ps1            核心 render 器：Get-StationBoardSnapshot（impure，打 GitHub）／
                               Build-StationBoardReport（**pure**，t09-offline-test.ps1 只測這個）／
                               Save-StationBoardArtifact（impure，寫檔）／
                               Invoke-StationBoardRender（impure，頂層入口）
  board-template.html         外殼樣板（ADR-NP-003 自包 HTML；四個 {{TOKEN}} 佔位字面）
  t09-offline-test.ps1        離線 mock 測試：70 項斷言，七個群組 A-G（沙盒可跑，不連網）
  t09-test.ps1                動態測試：需本機真實 PAT，紅燈為斷言失敗型（見檔頭文件）
  build-sample-board.ps1      sample-board.html 的產生腳本（本專案自己 26 張票的 mock 資料）
  sample-board.html           成品範例，可直接開啟；產生指令見 build-sample-board.ps1 檔頭
  t09-quality-gates.txt       出貨前三道關卡證據
```

## 架構：抓資料與算面板分離（純函式化）

`Get-StationBoardSnapshot`（impure，打 GitHub REST API＋讀待寫佇列檔）與 `Build-StationBoardReport`
（**pure**，只吃 Snapshot 物件算出 Html／TextSummary／ErrorStates）刻意切開。理由：§4.4 的四種錯誤
狀態必須能在沙盒離線、不連網的情況下被紮實驗證——純函式化是唯一能不靠真實 GitHub 斷網/假 repo 名
等外部條件、仍能 100% 決定性重現四種狀態的做法。SNAPSHOT SCHEMA 完整定義見 `render-board.ps1` 檔頭。

## §5.0 No-Hands 邊界裁定的落地方式

面板 HTML 由 `/station-board` 從 GitHub 現有資料**機械性 render**（欄位對應固定、無內容創作）⇒ 屬
編排輸出，不屬 No-Hands 管轄的 deliverable（Spec §2 邊界裁定）。本票交付的因此是**render 器**
（`render-board.ps1`）本身，不是手寫死的靜態 HTML——`sample-board.html` 也是用
`build-sample-board.ps1` 呼叫同一支 `Build-StationBoardReport` 產生，不是手刻 HTML。

## 四種錯誤狀態觸發手法（依 tickets-loop-draft.md 對 T-09 的驗收條件原文）

| 狀態 | 觸發手法 | 對應離線測試 |
|---|---|---|
| ① 數據過期 | 查詢清單混入一個不存在的 repo 名 ⇒ `AnchorQuery.Ok=$false` | 群組 A1 |
| ② 資料可能不完整 | 分頁上限調到低於實際筆數 ⇒ `TicketsQuery.HitPageCap=$true`（`total_count` > 實得筆數） | 群組 A2 |
| ③ 面板寫入失敗 | 對一個不存在的目錄路徑寫入 ⇒ `Save-StationBoardArtifact` 回 `Ok=$false` | 群組 A3、F4 |
| ④ 空狀態 | 對零筆結果的查詢條件執行 ⇒ `AnchorQuery.Found=$false` 且 `Ok=$true` | 群組 A4、A5（零筆＋無基線並列） |

## 紅燈設計（`t09-test.ps1`，斷言失敗型）

`-SkipErrorStateHandling` 關閉 `Build-StationBoardReport` 的正確錯誤狀態處理（旁路旗標，⚠️ 僅供本
測試使用，正式呼叫路徑不得開啟）⇒ 餵一個真打 GitHub、對不存在 repo 的 404 查詢結果 ⇒ 斷言「失敗
不得顯示為無工作」**真的斷言失敗**（因為旁路開啟時程式把失敗當成空結果，顯示成「目前無 active
work」）；關閉旁路（正常模式）重跑同一組真實查詢結果 ⇒ 同一斷言轉綠。離線部分（旁路旗標行為本身）
已由 `t09-offline-test.ps1` 群組 G 100% 覆蓋並綠燈；`t09-test.ps1` 補的是「旁路旗標接上真實 GitHub
404」這最後一段本機才驗得到的部分——本沙盒無 GitHub 連線，與 T-08／T-10 先例相同，無法在此環境
實跑到底。

## 使用者要跑的指令（本機 Windows PowerShell 5.1）

```powershell
cd <plugin repo>\build\t09

# 離線測試（沙盒／CI／本機皆可跑，不連網）
pwsh -NoProfile -File t09-offline-test.ps1

# 動態測試（需本機真實 PAT）
.\t09-test.ps1 -PatPath <PAT 檔路徑> -RealOwnerRepo <owner>/<repo>

# 產生範例面板
.\build-sample-board.ps1
```

## scope 邊界（誠實聲明）

**本票做**：單一 work 字卡、§4.1 全部欄位、§4.4 四種錯誤狀態、§4.6 待寫佇列揭露（併入原 T-23）。
**本票不做**：跨 repo 多 work 聚合與 anchor 消失偵測（T-16）、`plans/` 對帳三態實作（T-17——字卡已
留「對帳資料時間」欄位位置，誠實顯示「尚未實作」，不偽稱已對帳）。
