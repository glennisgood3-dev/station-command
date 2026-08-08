# T-31 Gemini 首發端到端結論（Commander 實跑後填寫）

> 本模板空白不代表通過。只有 Commander 在允許外網且持有真實 key 的環境跑完兩條路徑，才可填入實際值並交由 docs-manager／git-manager 開 PR，經使用者確認後寫入目標 repo 的 `DECISIONS.md`。

## 執行資訊

- 執行者：`Commander`
- 執行時間（含時區）：`{{EXECUTED_AT}}`
- 實際 diff 識別（commit／PR；不得貼 key 或個資）：`{{DIFF_ID}}`
- 成功路徑 model：`{{SUCCESS_MODEL}}`

## 錯誤體路徑實際回應碼與降級記錄

- 實際 HTTP 回應碼：`{{ERROR_HTTP_STATUS}}`
- `error.code`：`{{ERROR_CODE}}`
- `error.status`：`{{ERROR_STATUS}}`
- 適配層判定解析失敗：`{{ERROR_PARSE_FAILED}}`
- provider：`{{DEGRADATION_PROVIDER}}`
- 失敗原因：`{{DEGRADATION_REASON}}`
- 承接者：`{{DEGRADATION_FALLBACK}}`
- 該次 usage 記帳檔存在：`{{ERROR_USAGE_FILE_EXISTS}}`（預期 `False`）

## 正常路徑實際回應碼與用量原文

- 實際 HTTP 回應碼：`{{SUCCESS_HTTP_STATUS}}`
- finding 數：`{{FINDING_COUNT}}`
- finding 可逐條列舉：`{{FINDINGS_ENUMERABLE}}`
- `usageMetadata` 原文：`{{USAGE_METADATA_RAW_JSON}}`
- gate usage 記帳檔：`{{USAGE_RECORD_PATH}}`
- 免費層估算成本：`0 USD`；本票邊界為 RPM／RPD／TPM 配額

## 結論與 DECISIONS.md 條目草稿

| 日期 | ID（&lt;PROJ&gt;-DEC-NNN） | 類型（拍板／修改／豁免） | 裁示內容（一句話，含被否決選項） | 依據 | 裁示人 |
|---|---|---|---|---|---|
| `{{DATE}}` | `{{DECISION_ID}}` | `拍板` | `{{CONCLUSION_WITH_REJECTED_OPTION}}` | `T-31；錯誤 HTTP {{ERROR_HTTP_STATUS}}；成功 HTTP {{SUCCESS_HTTP_STATUS}}；usage {{USAGE_METADATA_RAW_JSON}}` | `{{DECIDER}}` |

## PR 分工

- Commander：執行兩次真實呼叫、核對兩個結果目錄、填妥本模板。
- docs-manager／git-manager：依本模板產生 DECISIONS.md 追加條目並開 PR。
- 使用者：確認後合併。任何腳本不得直接推送預設分支。
