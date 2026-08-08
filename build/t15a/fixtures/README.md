# T-15a · 站 5 人造交件 fixtures

十四份人造交件（皆為**靜態結構化 JSON**，`station5-check.ps1` 只讀欄位比對，不執行其中任何程式碼），逐一對應 `tickets-draft.md` T-15a 驗收條件與 Spec §6 站 5 出口條件。**變因隔離設計**：除下列表格明文標「多變因示範」者外，每份 fixture 皆只刻意留下要驗證的那一項缺項，其餘欄位與 `valid-submission.json` 一致——這樣 `t15a-offline-test.ps1` 斷言「`NamedGaps` 只含對應那一條」時，才能證明是**該項查核**單獨在起作用。

| fixture | 對應驗收／查核 | 預期整體判定 | 唯一（或主要）觸發拒絕的原因 |
|---|---|---|---|
| `valid-submission.json` | 全過的基準案例（軸 A 2 findings、軸 B 1 finding） | PASS | 無 |
| `not-reverified.json` | ②「未經復驗即結案 ⇒ 拒絕」；**本票紅燈設計標的** | FAIL | `remediation.verified=false` |
| `two-axis-supplement.json` | ②的另一合法路徑（兩軸補審一輪，非 verifier 重跑） | PASS | 無（示範 `remediation.method="two-axis-supplement"` 亦可通過） |
| `executor-is-verifier.json` | ③「以 executor 本人當 verifier ⇒ 拒絕」 | FAIL | `verifier` 與 `executor` 相同 |
| `verifier-is-commander.json` | ③「verifier 亦不得是 Commander」（Spec §5.2 hard rule 的另一半） | FAIL | `verifier="Commander"` |
| `missing-isolation-disclaimer.json` | ⑤「SC-DEC-ISO-001 落檔前，缺隔離未實測標註 ⇒ gate fail」 | FAIL | `isolationDecisionRecorded=false` 且 `closingReportText` 缺固定字串 |
| `isolation-decision-recorded.json` | ⑤ 的解除情境：已落檔後標註要求解除 | PASS | 無（`isolationDecisionRecorded=true`，`closingReportText` 刻意仍不含固定字串，證明此時不再要求） |
| `closing-summary-3-1-good.json` | ⑥ 收尾摘要，逐字比照驗收⑥「軸 A 3 條、軸 B 1 條」範例 | PASS | 無（兩軸各自具名 worst，無跨軸贏家） |
| `closing-summary-3-1-cross-winner.json` | ⑥「🚫 不得出現跨軸挑出的單一贏家」，同一 3/1 配置 | FAIL | `closingSummary.text` 含跨軸單一贏家樣式 |
| `closing-summary-missing-worst.json` | ⑥「軸內 worst（若有）缺項 ⇒ gate fail」 | FAIL | 軸 A 有 1 條 finding 但 `axisAWorst` 為空 |
| `spec-leak-axisA.json` | ①「軸 A 無 spec 原文」 | FAIL | 軸 A `inputList` 出現 `kind="spec"` 項目 |
| `smell-leak-axisB.json` | ①「軸 B 無 smell 基線」 | FAIL | 軸 B `inputList` 出現 `kind="smell-baseline"` 項目（結構性＋文字掃描雙重命中） |
| `standards-not-named.json` | Spec §6 站5「各軸輸入清單與所用 repo 規範版本具名」 | FAIL | 軸 A 缺 `standardsFileUsed`／`standardsVersion`，亦無 `noStandardsStatement` |
| `merged-findings.json` | Spec §5.2「兩軸不得合併重排」 | FAIL | 頂層出現禁止的 `mergedFindings` 欄位 |
| `hard-finding-no-evidence.json` | Spec §6 站5「hard violation 全清且各附修法證據」 | FAIL | 軸 A 的 `A1`（severity=hard）`remediationEvidence` 為空 |

## Schema（供交件產生者參照，非新格式正典——僅本票內部使用，不進 `../t21/queue-format.md`）

```json
{
  "ticket": "string，供 source 欄位預設值使用",
  "executor": "string，站 4 執行者身分（票 body 的 executor 欄位值）",
  "verifier": "string，修復復驗者身分（須 ≠ executor，且不得是 'Commander'/'主session'/'main session' 等字樣）",
  "axisA": {
    "inputList": [
      { "kind": "diff | standards | smell-baseline（🚫 禁 spec）", "value": "string" }
    ],
    "standardsFileUsed": "string，可留空但須搭配 noStandardsStatement",
    "standardsVersion": "string，可留空但須搭配 noStandardsStatement",
    "noStandardsStatement": "string，若該 repo 無落檔規範，須含『無落檔規範』或等義字樣",
    "findings": [
      { "id": "string", "severity": "hard | judgement", "text": "string",
        "remediationEvidence": "string，severity=hard 時必填", "decision": "string，severity=judgement 時必填" }
    ]
  },
  "axisB": {
    "inputList": [
      { "kind": "diff | spec（🚫 禁 standards／smell-baseline）", "value": "string" }
    ],
    "findings": [ "同 axisA.findings schema" ]
  },
  "remediation": {
    "verified": "bool，false 或缺漏 ⇒ ② fail-closed",
    "method": "verifier-rerun | two-axis-supplement",
    "evidence": "string，復驗證據，不可為空"
  },
  "isolationDecisionRecorded": "bool，SC-DEC-ISO-001 是否已於 plugin repo DECISIONS.md 落檔（隔離成立）",
  "closingReportText": "string，結案報告全文；isolationDecisionRecorded=false 時須含固定字串「context 隔離未實測，本結論僅由輸入分離支撐」",
  "closingSummary": {
    "axisACount": "int，須等於 axisA.findings 實際筆數（獨立填寫，非由檢查器動態計算後自我比對）",
    "axisBCount": "int，同上",
    "axisAWorst": "string，軸 A 有 findings 時必填",
    "axisBWorst": "string，軸 B 有 findings 時必填",
    "text": "string，人讀收尾摘要全文，🚫 不得出現跨軸單一贏家樣式"
  }
}
```

**🚫 禁止的頂層欄位（觸發「兩軸不得合併重排」拒絕）**：`mergedFindings`／`combinedFindings`／`allFindings`／`rankedFindings`／`overallWinner`／`singleWinner`／`crossAxisRanking`。
