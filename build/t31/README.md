# T-31 · Gemini 首發端到端實測交付

本目錄交付可執行的 Gemini v1beta `generateContent` 端到端腳本、請求內容模板、回應語意判讀、結論／佇列模板與完整離線 mock。依本次執行禁令，executor **沒有連網、沒有碰真實 key，也沒有宣稱端到端已通過**；真實錯誤體與正常路徑各一次呼叫，具名由 **Commander** 執行。

## Scope、seam 與獨立預期值

測試 seam 逐字承接票面：**適配層對 Gemini 回應體的解析出口**，輸入是原始回應 JSON 與 HTTP 狀態，輸出是 finding 清單或具名降級記錄。T-28 只負責請求與傳輸形狀；T-31 在其上新增語意守門，避免 `error` JSON 被當成成功空 finding。

獨立預期值不是從被測函式的輸出反推。`fixtures/gemini-success.json` 手寫固定 Gemini v1beta 成功外框 `candidates[].content`，`fixtures/gemini-error.json` 手寫固定錯誤外框 `error.code`／`error.status`，`fixtures/expected-outcomes.json` 另存 known-good literals：HTTP 200／404、finding ID／筆數與 token 數。這些 fixture 是票面允許的外部契約快照；本環境未連線重新查文件。

## 交付檔清單

| 檔案 | 用途 |
|---|---|
| `gemini-e2e-core.ps1` | Gemini 請求上限包裝、回應語意解析、finding JSON 驗證、具名降級、usage／gate 記錄與安全落檔；純函式庫直接執行會印 usage banner |
| `invoke-gemini-e2e.ps1` | Commander 真實兩路呼叫入口；亦支援完全離線 `-FixturePath` smoke |
| `request-template.json` | v1beta `generateContent` 端點、固定不存在 model 與含實際 diff 的規範審提示模板 |
| `fixtures/gemini-success.json` | `candidates[].content`＋`usageMetadata` 成功 fixture |
| `fixtures/gemini-error.json` | `error.code`／`error.status`、非 `candidates` 的錯誤 fixture |
| `fixtures/gemini-max-tokens.json` | `finishReason=MAX_TOKENS` 的截斷＋usage fixture |
| `fixtures/expected-outcomes.json` | 與被測程式分離的預期字面值 |
| `fixtures/sample.diff` | CLI 離線 smoke 的人造 diff；不冒充真實規範審輸入 |
| `t31-offline-test.ps1` | 60 條離線機械斷言與紅燈專用開關 |
| `conclusion-template.md` | Commander 填寫實際回應碼、用量原文與 DECISIONS.md 條目草稿 |
| `queue-item-template.json` | T-21 `comment` 白名單的單項範本，物件恰四欄 `action／target／payload／source` |
| `evidence/red-assertion-failures.txt` | 斷言失敗紅燈摘要 |
| `evidence/green-offline.txt` | 關閉紅燈開關後的離線綠燈摘要 |
| `evidence/verification.txt` | BOM、ParseFile、測試與 CLI smoke 摘要 |

`queue-item-template.json` 只示範符合 T-21 正典的 gate 留言待寫項；Commander 使用前須換成實際 repo／issue。它不能取代 DECISIONS.md PR。後者仍依 Spec §8：docs-manager／git-manager 開 PR，使用者確認後合併。

## 回應判讀與落檔規則

`ConvertFrom-T31GeminiResponse` 先檢查 `error` 外框。若存在，無論 findings 是否為空，一律回 `ParseFailed=True`，理由保存 `error.code`／`error.status`，並用 T-28 基礎函式產生 `provider／失敗原因／承接者` 具名降級；該次不建 `usage-record.json`，錯誤路徑的 `gate-record.json` 也刻意沒有 `usage` 欄。

真實請求固定帶 `generationConfig.maxOutputTokens`（預設 1024，可用 `-MaxOutputTokens` 下調或在白名單範圍內調整）與 `responseMimeType=application/json`。HTTP 2xx 必須存在 `candidates[0].content.parts[].text`，文字還必須能解析為 `{ "findings": [...] }`；若 `finishReason=MAX_TOKENS`，一律具名停止並拒絕把遭截斷審查當成功，但仍把該次 `usageMetadata` 寫入 gate／usage 記錄。每筆 finding 須含 `id／severity／summary／evidence／recommendation`，輸出為可列舉物件陣列，不是整包字串。正常路徑另外要求 `usageMetadata.promptTokenCount／candidatesTokenCount／totalTokenCount`，成功後才同時寫 `findings.json`、`usage-record.json` 與含 finding＋usage 的 `gate-record.json`。Gemini 首發記帳層級為 `free`、估算成本 `0 USD`，§7.6 邊界是 RPM／RPD／TPM 配額。

## 紅燈：斷言原文與真實失敗證據

紅燈指令：

```powershell
Set-StrictMode -Version Latest
& .\build\t31\t31-offline-test.ps1 -SkipErrorEnvelopeGuard
```

`-SkipErrorEnvelopeGuard` **僅供紅燈驗證，正式流程禁用**。它故意略過錯誤外框守門，重現 T-28 舊解析出口把錯誤 JSON 靜默當成功空 finding 的假綠形狀。斷言原文：

> 紅燈斷言 (a)：適配層須判定解析失敗，不得把 Gemini error JSON 當成沒有 finding。

> 紅燈斷言 (b)：解析失敗須產生同時含 provider／失敗原因／承接者三項的具名降級記錄。

> 紅燈斷言 (c)：錯誤體該次不得產生 usage 記帳。

本次真跑為 exit 1、`PASS=51 FAIL=2`；唯一失敗是 (a)(b)，(c) 通過。程式已成功載入 fixture、跑進斷言並一路執行到總結，並非檔案、語法、import、載入或 collection 失敗。完整摘要見 `evidence/red-assertion-failures.txt`。

關閉開關後以正式流程執行同一檔：

```powershell
Set-StrictMode -Version Latest
& .\build\t31\t31-offline-test.ps1
```

結果為 exit 0、`PASS=60 FAIL=0`，見 `evidence/green-offline.txt`。

## Commander：真實兩次呼叫分工與指令

請在允許外網的 **Windows PowerShell 5.1** 執行。Gemini key 檔名必須是 `gemini.key`，放在 repo 外的連接資料夾；腳本只透過 `x-goog-api-key` header 使用，絕不輸出或落檔 key。輸出目錄也建議放 repo 外，確認結果不含 key／token／個資後，只把填妥的結論模板交給 PR 流程。

先跑固定不存在 model 的錯誤體路徑：

```powershell
Set-StrictMode -Version Latest
$T31ConnectionFolder = 'G:\default mount'
$T31ResultRoot = 'G:\station-command-t31-results'

& .\build\t31\invoke-gemini-e2e.ps1 `
  -Scenario ErrorEnvelope `
  -ConnectionFolder $T31ConnectionFolder `
  -OutputDirectory $T31ResultRoot
```

Commander 預期看到 HTTP 非 2xx、`success=False`、`parseFailed=True`、`usageWritten=False`，以及含 provider／失敗原因／承接者的「具名降級」行。`ErrorEnvelope\raw-response.json` 應是含 `error.code`／`error.status`、不含 `candidates` 的 JSON；目錄應有 `degradation-record.json` 與無 `usage` 欄的 `gate-record.json`，且**不得存在** `usage-record.json`。若對方沒有回此錯誤 schema，不得硬填通過，應保留實際結果並回報。

再準備一份非空、確實來自待審變更的 diff，並由 Commander 填入當下已確認可用的免費層 model 名：

```powershell
$T31ActualDiff = 'G:\station-command-input\actual-review.diff'
$T31CurrentFreeModel = '<Commander 當下確認可用的免費層 model>'

& .\build\t31\invoke-gemini-e2e.ps1 `
  -Scenario Success `
  -ConnectionFolder $T31ConnectionFolder `
  -Model $T31CurrentFreeModel `
  -DiffPath $T31ActualDiff `
  -MaxOutputTokens 1024 `
  -OutputDirectory $T31ResultRoot
```

Commander 預期看到 HTTP 200、`success=True`、`parseFailed=False`、`usageWritten=True`，並逐條列出 `finding：id=...`；零 finding 仍須是可列舉的空陣列。`Success\gate-record.json` 應同時含 `findings` 與 `usage`，`usage.rawUsage` 保存對方的 `usageMetadata` 原文，`estimatedCost=0`。

最後填 `conclusion-template.md`：

- 錯誤路徑的 HTTP／`error.code`／`error.status`／三項具名降級／錯誤 usage 檔是否存在，填「錯誤體路徑實際回應碼與降級記錄」。
- 成功路徑的 HTTP／finding 數與可列舉結果／完整 `usageMetadata` 原文與 `usage-record.json` 路徑，填「正常路徑實際回應碼與用量原文」。
- 將兩路事實濃縮到 DECISIONS.md 追加條目草稿，再由 docs-manager／git-manager 開 PR；未經使用者確認不得合併。

## 驗收條件逐條對應與目前結果

| 票面驗收 | 測試與落點 | executor 本環境結果 |
|---|---|---|
| ① 錯誤體不得誤讀空清單；(a)(b)(c) | `t31-offline-test.ps1` A／C；`gemini-error.json`；錯誤 `gate-record.json` | 離線 PASS；紅燈也證明未守門時 (a)(b) 真的失敗；**真實呼叫待 Commander** |
| ② HTTP 200 且內容解析為 finding 清單 | 測試 B；`gemini-success.json`；`findings.json`；Success CLI smoke | 離線 PASS，2 筆物件可列舉；**含實際 diff 的真實呼叫待 Commander** |
| ③ token 與成本落 gate 紀錄 | 測試 B／C；Success `gate-record.json`＋`usage-record.json` | 離線 PASS，31／19／50 tokens、0 USD；**真實用量待 Commander** |
| ④ Gemini 狀態精確，T-31 全檔無廢止計費字串 | 測試 D 唯讀解析既有 registry 並掃 T-31 全檔 | PASS；狀態精確為 `available（首發；免費層，無需計費）`，沒有修改 T-27／registry |
| ⑤ 結論含實際回應碼與用量原文 | `conclusion-template.md` 欄位斷言；兩路 `raw-response.json`／`result-summary.json` | 模板 PASS；**實際值、DECISIONS 條目與 PR 待 Commander／docs-manager／git-manager／使用者** |

另有硬性契約：測試 D 證明佇列項恰四欄且順序／名稱為 `action／target／payload／source`；所有腳本使用 PowerShell 5.1 可解析語法與 `Set-StrictMode -Version Latest`。陣列處理均先將函式或屬性結果賦值，再以 `@()` 包裝；沒有用同層逗號 `@()` 表示空陣列。CLI 在 dot-source 前以 T-31 獨有變數保存參數，避免 cascade 覆寫。

## BOM、ParseFile、離線測試與 CLI smoke

- UTF-8 BOM：最終驗證為 3/3 個 `.ps1` 首三 bytes 皆 `EF BB BF`。
- ParseFile：3/3，`errors=0`。
- 完整離線測試：60/60 PASS，0 FAIL，exit 0。
- 紅燈：51 PASS、2 assertion FAIL，exit 1；只有 (a)(b) 失敗。
- 純函式庫 CLI：`gemini-e2e-core.ps1` 直接執行 exit 0，印三行 usage banner，非零輸出 no-op。
- ErrorEnvelope fixture CLI：exit 0；HTTP 404、解析失敗、具名降級、usage 未寫。
- Success fixture CLI：exit 0；HTTP 200、2 筆 finding 逐條輸出、usage 已寫。
- `t31-offline-test.ps1` 直接執行即完整測試，exit 0 且有 60 條 PASS 輸出。

完整機械摘要見 `evidence/verification.txt`。

## 最終誠實聲明

已實證：離線 Gemini 成功／錯誤 schema 判讀；錯誤不會靜默放行；具名降級三欄；錯誤不記 usage；成功 finding 可列舉；成功 token／成本進 gate 記錄；請求與結論模板；四欄佇列；PS 5.1 StrictMode、BOM、ParseFile 與 CLI 離線路徑。

未實證：任何 Gemini 真實 key 呼叫、指定不存在 model 在 Commander 環境的實際回應碼／內容、當下可用免費層 model 的 HTTP 200、對實際 diff 的真實 finding、真實 token 用量、DECISIONS.md PR 或使用者合併。因此 **T-31 端到端驗收目前尚未通過**；本交付是待 Commander 執行的完整工具與離線證據，沒有粉飾成真實端到端成果。
