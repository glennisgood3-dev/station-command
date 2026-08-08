# T-14 · 站 4 人造交件 fixtures

四份人造交件（皆為**靜態文本**，`station4-check.ps1` 只讀字串比對，不執行其中任何程式碼），逐一對應 `tickets-draft.md` T-14 驗收條件：

| fixture | 對應驗收 | 預期整體判定 | 唯一觸發拒絕的原因 |
|---|---|---|---|
| `load-failure-red.json` | ①「紅燈其實是載入失敗」⇒ gate 拒絕並具名原因 | FAIL | `redOutput` 命中 `ModuleNotFoundError`／`Interrupted: 1 error during collection` 等載入失敗特徵（① 紅燈型態） |
| `valid-submission.json` | ② 合格交件 ⇒ 通過（票上出現 `sc:red-proven`，actor=bot 部分 deferred-to-CI）；亦作為 ④「預期值來自獨立真相源者 ⇒ 通過」的正面案例 | PASS | 無（三項查核皆過） |
| `executor-is-verifier.json` | ③ 以 executor 本人充當 verifier ⇒ 拒絕 | FAIL | `executor` 與 `verifier` 欄位相同（皆為 `fullstack-developer`），其餘兩項（紅燈型態、預期值出處）與 `valid-submission.json` 完全相同，刻意只留這一個變因 |
| `self-referential-assertion.json` | ④「斷言的預期值由被測程式自身產生」⇒ verifier 須具名拒絕並指出該斷言 | FAIL | 斷言 A1 的 `text` 內 `$expected = Get-Sum 2 3` 與 `$actual = Get-Sum 2 3` 為完全相同的呼叫式（自證式斷言，Pocock `tdd` Anti-patterns · Tautological），`redOutput` 與 `verifier` 皆刻意設為合格值，只留這一個變因 |

**變因隔離設計說明**：`executor-is-verifier.json` 與 `self-referential-assertion.json` 都刻意讓「另外兩項查核」維持合格，只留下該 fixture 要驗證的那一項會失敗——這樣 `t14-offline-test.ps1` 斷言「NamedGaps 只含對應那一條」時，才能證明是**該項查核**單獨在起作用，不是三項連坐誤判。

## Schema（供交件產生者參照，非新格式正典——僅本票內部使用，不進 `../t21/queue-format.md`）

```json
{
  "ticket": "string，供 source 欄位預設值使用",
  "executor": "string，執行者身分（票 body 的 executor 欄位值）",
  "verifier": "string，驗收者身分（須 ≠ executor）",
  "redOutput": "string，紅燈階段的測試工具原始輸出文字（人造交件所附的測試輸出原文）",
  "greenOutput": "string，綠燈階段的測試工具原始輸出文字",
  "assertions": [
    {
      "id": "string，斷言識別（供具名拒絕時指出是哪一條）",
      "text": "string，該斷言的程式碼原文（或其摘錄）",
      "expectedSourceNote": "string（可為空字串，觸發 fail-closed），預期值出處說明；須提及 known-good literal／worked example／spec 三者之一或等價中文措辭，才能通過 ④ 查核"
    }
  ]
}
```
