# 人造 legacy 專案 fixture · 實際工件清單與獨立預期值（Spec §3.5 註 C／ticket 驗收條件③）

🔴 **本檔是本票測試的「獨立預期值來源」之一**（另一是 Spec §6 checklist 逐字文本）。撰寫順序：
先讀 fixture 實際內容 → 人工對照 Spec §6／§7.4 逐條判斷應該 ✓ 還是 ✗ → 寫下本檔 → **之後**才
依本檔內容去寫 `auditor-findings-*.json`（模擬一個誠實的 auditor 會給出的結論）。`t18-offline-
test.ps1` 的斷言預期值＝本檔內容，**不是**回頭讀 `Get-AuditorCandidateStation` 自己的輸出去定義
「應該通過」——避免 §3.5 註 C 所禁的自證式斷言。

## 實際檔案清單（`find fixtures -type f`，2026-08-08 執行）

```
legacy-project-a/NOTES.md
legacy-project-a/README.md
legacy-project-b/DECISIONS-path2-not-adopted.md
legacy-project-b/DECISIONS.md
legacy-project-b/GAP-REVIEW.md
legacy-project-b/GLOSSARY.md
legacy-project-b/SPEC.md
legacy-project-b/remediated-native-tickets/ticket-201.md
legacy-project-b/remediated-native-tickets/ticket-202.md
legacy-project-b/tickets/ticket-legacy-101.md
legacy-project-b/tickets/ticket-legacy-102.md
```

## legacy-project-a（預期候選站別＝1，退回站 1）

| §6 checklist 項 | 人工判定 | 理由（指向實際檔案） |
|---|---|---|
| `1.glossary` | ✗ | `README.md` 使用 FooWidget／BarQueue／三段式驗證三個詞彙，目錄內**無** GLOSSARY.md 或等效名詞表檔案（`find legacy-project-a -iname '*glossary*'` 零命中） |
| `1.adr` | ✗ | `NOTES.md` 明文「沒有任何書面 ADR 或會議紀錄檔案留存於本 repo」 |
| `1.confirm` | ✗ | `NOTES.md` 明文「沒有任何檔案記載『使用者已確認共識』這件事本身」 |
| `2.spec`／`2.confirm`／`2.gapreview` | ✗（找不到對象） | 目錄內無 SPEC.md 或等效檔案、無缺口審報告 |
| `3.fields`／`3.vertical` | ✗／N/A（找不到對象） | 目錄內無任何票（tickets/ 目錄不存在） |

**MissingClass（依 §7.4 明文分類）**：`1.glossary`＝**次要**（§7.4 明文「名詞表」屬次要工件可豁
免）；`1.adr`／`1.confirm`／`2.spec`／`2.confirm`／`2.gapreview`＝**關鍵**（§7.4 明文 spec／可執
行驗收條件為關鍵工件無豁免；ADR 與使用者確認屬決策留存證據，非 §7.4 minor 清單所列項目，保守
歸類為關鍵，不得因未列名而預設可豁免）。

**預期候選站別**：從站 1 往上走，第一個未滿足＝`1.glossary`（§6：「名詞表存在且關鍵詞無未定義」
不滿足）⇒ **候選站別＝1**。因 1 ≤ 3（cap 上限），本情境**不觸發 cap**（cap 只在候選 >3 時介入）。

## legacy-project-b（預期候選站別＝3，站 1／2 皆過）

| §6 checklist 項 | 人工判定 | 理由（指向實際檔案） |
|---|---|---|
| `1.glossary` | ✓ | `GLOSSARY.md` 定義 WidgetSync／StaleLock／ReconcileWindow，涵蓋 README／SPEC／DECISIONS 內出現的全部關鍵詞 |
| `1.adr` | ✓ | `DECISIONS.md` LP-DEC-001 含被否決方案（即時 webhook，否決理由：對方 API 無 webhook 能力） |
| `1.confirm` | ✓ | `DECISIONS.md` LP-DEC-002：「使用者已確認本專案共識」 |
| `2.spec` | ✓ | `SPEC.md` 含 Goal／Scope In-Out／Success Criteria 三段，且 Success Criteria 為可驗證數字（7 天、1%） |
| `2.confirm` | ✓ | `SPEC.md` 末行：「使用者已於 2026-06-15 確認本 spec」 |
| `2.gapreview` | ✓ | `GAP-REVIEW.md` 兩條 hard finding 皆標「已結案」 |
| `3.fields` | ✗ | `tickets/ticket-legacy-101.md`、`tickets/ticket-legacy-102.md` 皆為「負責人／內容／狀態」三欄自由格式，`grep -E 'REQ-ID|驗收條件|depends_on|executor|basis|scope|測試先行|不可逆動作'` 對兩檔皆零命中（§3.5 全八項欄位缺漏） |
| `3.vertical` | N/A | 舊票未採用 §3.5 切片模型，垂直／水平切片的概念不適用於自由格式票 |

**MissingClass**：`3.fields`＝**次要**（§7.3 明文「舊票格式屬次要工件，可依 §7.4 具名豁免，但
『可執行驗收條件』屬關鍵工件、不得豁免」——本情境兩張舊票雖無 §3.5 格式，但**確實各自寫了一句
可執行的工作內容**（WidgetSync 排程實作／StaleLock 偵測清除），故只是格式次要缺陷，非「完全沒
有可執行驗收條件」的關鍵缺陷；此區分即 §7.3 該句存在的理由——若 3.fields 恆為關鍵不可豁免，
§7.3 路徑②「不收編、僅供查閱」就不會被允許為合法路徑）。

**預期候選站別**：站 1／2 全過，站 3 的 `3.fields` 未過 ⇒ **候選站別＝3**。因 3 ≤ 3（cap 上限），
**本情境仍不觸發 cap**（這是 legacy 收編最典型、預期最常見的自然結果，cap 只是防呆備援，不是
主要判定路徑——大多數真正的 legacy 專案會像本情境一樣自然落在站 3，不需要 cap 出手）。

## legacy-project-b／optimistic（人造「過度樂觀 auditor」情境，僅供紅燈驗證）

`auditor-findings-legacy-project-b-optimistic.json` **刻意**把 `3.fields` 也判成 ✓（現實中不
應該發生——兩張舊票明明沒有 §3.5 格式，見上表——但用來模擬 ticket 驗收條件擔心的風險：「未實作
時 auditor 可能直接判在站 4」）。**人工預期**：若不套用 cap，候選站別會被錯誤計算成 4；套用 cap
（且未提供補齊證據）後，必須被強制封頂為 3。此檔**不代表任何真實 fixture 內容的誠實判讀**，僅
用於證明 cap 這道防呆真的擋得住 over-optimistic 的輸入，命名已標註 `optimistic` 以資區別。

## legacy-project-b／remediated-native-tickets（路徑① 情境）

`ticket-201.md`／`ticket-202.md` 皆含 §3.5 全八項欄位標記（`REQ-ID:`／`驗收條件:`／
`depends_on:`／`executor:`／`basis:`／`scope:`／`測試先行:`（內含 `seam:`／`獨立預期值來源:`）／
`不可逆動作:`，皆有非空內容），可用 `grep -c` 逐檔核對八個 label 皆恰出現一次。**人工預期**：
`Test-Station3TicketSetDeep`（T-13，重用不重寫）對這兩張票跑深度檢查應回傳 `Satisfied=true`。

## legacy-project-b／DECISIONS-path2-not-adopted.md（路徑② 情境）

內容含 `LP-DEC-003` 一筆，裁示內容含逐字「不收編、僅供查閱」六字。**人工預期**：
`Test-LegacyRemediationComplete` 讀到此檔內容應判定路徑②成立（`Remediated=true`,
`Path='path2-not-adopted'`）。
