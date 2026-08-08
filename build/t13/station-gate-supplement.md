# T-13 · station-gate 增補說明（掛在既有哪支 SKILL.md）

依票面「`station-gate/SKILL.md` 增補（或說明掛在既有哪支）」——本票**不新建**一份 `station-gate/SKILL.md`
（那會造成兩份互相漂移的 gate skill 定義，違反 SC#8 薄度與 DRY）。本票掛在
`../t10/station-gate/SKILL.md`（下稱「母檔」）**段落二「站別推進、寫後回驗」**之下，比照
`../t12/run-queue-ext.md` 對 `../t21/queue-format.md` 的既有先例（另立補充文件、不修改被補充檔案的
file ownership 邊界）。

## 為何需要增補（誠實聲明，非規避）

母檔段落二的站 3 檢查目前引用 `../t10/gate-check.ps1` 的 `Invoke-StationExitChecklist`，其對站 3
`3.fields` 項的判定是 `Test-Station3FieldsChecklistItem`——**結構性存在檢查**（欄位關鍵字是否出現在
票 body 任意位置），母檔自己在「已知限制與 scope 邊界」段落已明文承認：「更深的欄位品質邏輯
（`[INVALID]` 判定細節）屬 T-13」。本檔正是把那段留白補上，且**不修改** `../t10/` 任何檔案。

## 增補內容對照母檔段落二的插入點

母檔段落二「步驟 1：判定站序合法性與出口條件」原文列了三類 checklist 項（機械可判定／內容裁量／站
4-5 deferred）。本增補在**站 3 的機械可判定項**這一類下，把 `Test-Station3FieldsChecklistItem`（淺層）
換成本票的 `Test-Station3FieldsDeep` / `Test-Station3TicketSetDeep`（深層），並在**內容裁量項**這一類
新增一筆：

| 出口條件項 ID | 類型 | 判定者 | 母檔原有／本票新增 |
|---|---|---|---|
| `3.fields` | Mechanical | `gate-station3.ps1` 的 `Test-Station3TicketSetDeep`（深度：逐欄內容檢查、缺 executor／basis 判 `[INVALID]`、測試先行欄位另檢 seam／獨立預期值來源具名） | 母檔原有項，**本票加深判準** |
| `3.vertical` | RequiresInput | Commander（透過 `-ChecklistOverridesPath`，沿用母檔既有介面，未新增機制） | 母檔原有項，未改動 |
| `3.seam-confirmed` | RequiresInput | Commander（透過同一份 `-ChecklistOverridesPath`；裁定來源＝拆票 quiz 逐字記錄，**非獨立審查步驟**） | **本票新增項**（§3.5 註 B／§6 站 3 出口條件：「每張票的測試 seam 已寫下且已於拆票 quiz 中經使用者確認」） |

⚠️ **欄位總數仍為 8**（§3.5）：`3.seam-confirmed` 是**出口條件（checklist）清單**的新增項，不是**票欄
位**清單的新增項——票模板仍是 REQ-ID／驗收條件／depends_on／executor／basis／scope／測試先行／不
可逆動作八項，註 B／註 C 只是第七欄「測試先行」的內容要求。

## 執行順序（銜接母檔步驟 1→2→3，不重複實作站別推進）

1. Commander 在票集完成拆票 quiz（planner＋kongming，站 3 既有 `/station-run` dispatch，見
   `../t12/run-common.ps1` 的 `Get-RunRoutingDefault -Station 'sc:station-3'`）後，取得 quiz 逐字紀錄
   中「seam 是否經使用者確認」與「切片是否垂直可獨立驗收」兩項人工裁定。
2. 執行本票 `.\gate-station3.ps1 -ChecklistOverridesPath <裁定檔>`：
   - 全過 ⇒ 寫出 `station3-overrides-for-t10.json`（含 `3.fields`／`3.vertical`／`3.seam-confirmed`
     三鍵皆 `Satisfied=true`），並提示接續執行母檔既有的
     `..\t10\gate-advance.ps1 -ChecklistOverridesPath station3-overrides-for-t10.json` 完成**站別推進**
     （母檔 §3.4 原子性單一動作邏輯，本票不重複實作）。
   - 未過 ⇒ 具名列出問題票與缺項，產生 `sc:gate-fail` 的 `set-labels` 佇列項（anchor 一筆＋每張問題
     票各一筆），**不產生任何站別推進的佇列項**（母檔既有邏輯：未過不得推進）。
3. **唯一寫入者不變式**（SC#7）：本票的 `gate-station3.ps1` 與母檔一樣，只產生佇列項、不直接呼叫
   GitHub 寫入 API；`sc:gate-fail` 屬狀態 label，寫入者恆為 gate 一側（本票扮演 gate 角色的一部分，
   非新增第二個寫入者）。

## No-Hands／白名單邊界（延續母檔宣告，未新增動作類型）

本增補的動作（讀票 body、逐欄機械判定、讀 `-ChecklistOverridesPath` 裁定結果、產生 `set-labels`
佇列項）全落在母檔已宣告的白名單「讀 GitHub｜寫狀態 label｜dispatch 審查 sub-agent」範圍內，
未新增任何動作類型，不觸發 SC#8 薄度上限的重新核算。
