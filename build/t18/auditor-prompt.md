# legacy 收編 auditor · prompt 要件（Spec §7.2，逐字承接）＋輸出 schema（T-18 淨新增）

依 `Spec_station-command_v1.11.md` §7.2 逐字：

> fresh context（不得由曾參與者執行）｜**只餵**：repo 現況工件（README／spec／票／測試／log）＋
> §6 checklist｜🚫 **禁餵**：過程對話、先前任何評分或評語、原作者自陳｜**輸出**：逐站逐條
> ✓／✗／N/A ＋ 每個 ✗ 的證據指向 ＋ 建議退回站別 ＋ 缺件分類（關鍵／次要）。

## dispatch 時機與角色邊界

由 `/station-intake` legacy 模式在 Stage A／B（共用 native 建立步驟，見 `station-intake-legacy.md`）
完成後、Stage C（定站）之前 dispatch。**fresh context**＝一個全新的、未曾參與過本工作任何前置
討論的 sub-agent（比照站 5 雙審與站 2 缺口審的既有先例，Commander 不得自己扮演這個角色，§5.0
No-Hands：auditor 報告屬 deliverable，一律 dispatch）。

## 輸入邊界（🚫 禁餵清單，逐一對照如何在本實作落實）

| 允許餵 | 🚫 禁止餵 | 本實作如何保證 |
|---|---|---|
| repo 現況工件（README／spec／票／測試／log） | 過程對話 | auditor 的 prompt 模板（見下）只含「請讀取以下路徑清單」，不含任何 Commander 與使用者的對話記錄 |
| §6 checklist（`Spec_station-command_v1.11.md` §6 表格逐字，或本репo `../t10/gate-check.ps1` 的 `Get-StationChecklistDefinition` 站 1-3 文字，兩者須一致，見下「與 t10 checklist 定義的關係」） | 先前任何評分或評語 | 本票不把任何舊有審查紀錄、CS-DEC 系列教訓文字放進 auditor prompt——那些是本檔／README 給人看的，不進 auditor 輸入 |
| （無其他） | 原作者自陳 | prompt 模板明文「不得詢問或採信原作者對本專案現況的自我陳述，只採信可獨立查驗的工件內容」 |

## 與 t10 checklist 定義的關係（誠實聲明，避免兩份定義漂移）

`../t10/gate-check.ps1` 的 `Get-StationChecklistDefinition` 對站 1／2／3 的 `Id`／`Text` 是
Spec §6 表格的逐字轉錄（供 gate 機器判定用）。本票 **auditor 輸出的 `Id` 欄位沿用同一組 Id
命名**（`1.glossary`／`1.adr`／`1.confirm`／`2.spec`／`2.confirm`／`2.gapreview`／`3.fields`／
`3.vertical`），**直接 dot-source 重用該函式**（見 `legacy-intake.ps1`），不另立第二份 Id 對照
表——這正是 Spec §7.3「對照 §6 同一份 checklist」的字面要求：legacy 與 native 共用同一份 checklist
正典，不得各自維護。站 4／5 的深度驗收邏輯屬 T-14／T-15a 範圍（`../t10/gate-check.ps1` 對這兩站
只留 deferred 佔位項），本票**不越權**幫站 4／5 定義細項 checklist——若 auditor 判定站 1-3 全過，
本票的候選站別判定即回報「候選＝4」（代表『至少通過站 3』），不再往下細分 4／5 子項，理由與範圍
見 `README.md`「設計選擇：候選站別只細分到站 3」一節。

## auditor prompt 模板（供 dispatch 時使用）

```
你是一個 fresh-context 的稽核員（auditor），任務是逐條核對下列既有專案的工件是否滿足
station-command Spec §6 出口條件 checklist（見下方逐條列出）。

【只讀這些工件，不得讀取或採信本 prompt 之外的任何內容】：
<repo 現況工件路徑清單，例如 README.md、SPEC.md、DECISIONS.md、GAP-REVIEW.md、
tickets/*.md、測試檔、log 檔——由 dispatch 者列出實際路徑>

【禁止事項】：
- 不得詢問或採信原作者對專案現況的自我陳述。
- 不得參考任何過程對話、先前評分或評語（你沒有被餵這些，也不應該去找）。
- 只能根據上面列出的工件實際內容下判斷。

【逐條核對下列 checklist，每項給出 Mark（pass／fail／na）與（若為 fail）具體證據指向
（須指到實際檔名，可含行號或引述片段，不得只寫「不符合」這種空泛描述）】：
1.glossary：名詞表存在且關鍵詞無未定義
1.adr：ADR 記錄關鍵裁示（含理由與被否決方案）
1.confirm：使用者已確認共識
2.spec：spec 有 Goal／Scope In-Out／可驗證 Success Criteria
2.confirm：使用者已確認
2.gapreview：第三方缺口審報告存在且 hard finding 全結案
3.fields：每張票具備 §3.5 全八項欄位（REQ-ID／驗收條件／depends_on／executor／basis／
          scope／測試先行／不可逆動作）
3.vertical：切片可獨立驗收（垂直非水平）

【輸出格式（JSON）】：
{
  "AuditorSuggestedRetreatStation": "sc:station-N",
  "Findings": [
    { "Station": "sc:station-1", "Id": "1.glossary", "Mark": "pass|fail|na",
      "Evidence": "具體證據指向（fail 時必填，pass/na 亦鼓勵填）",
      "MissingClass": "critical|minor|null（fail 時依 Spec §7.4 分類：spec／可執行驗收
                        條件＝critical；名詞表／舊票格式／歷史CHANGELOG補寫／命名規範等
                        ＝minor；不在此兩類明文清單者，保守歸類為 critical）" },
    ...
  ]
}
```

## 輸出消費方式

`legacy-intake.ps1` 的 `Get-AuditorCandidateStation` 讀取上述 `Findings` 陣列（**不採信**
`AuditorSuggestedRetreatStation` 這個auditor 自報的摘要值本身作為判定依據——只把它當人讀參考，
真正的候選站別由程式重新從 `Findings` 逐條走一遍算出，理由：gate 一貫的原則是「不自證」，若
直接採信 auditor 自己算好的摘要值，等於把判定權交還給被審對象，與 §3.5 註 C「預期值不得自證」
同一精神的延伸）。
