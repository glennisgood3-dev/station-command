# 廠商登錄表 v1（12 家）

> 正典位置 ＝ `Spec_station-command_v1.11.md` §5.1（廠商登錄表段，含 12 家表格與 Gemini 免費層計費事實更正）。本檔為隨 plugin 出貨的登錄簿，供 `/station-run` 等 skill 於異廠 executor dispatch 時查閱。
> **權威分工（避免自我否定，2026-08-08 訂正）**：provider 名稱集合、認證方式、格式家族——與 spec §5.1 原表不一致時，**以 spec §5.1 為準**。以下兩處**本檔刻意偏離** spec §5.1 原表，偏離處以本檔（T-27 驗收條件）為準，非漂移：
> 1. **端點欄**：本檔採**實測完整路徑**（例 `api.openai.com/v1`），spec §5.1 原表欄名為「端點**主機**」、值僅主機名（無路徑）——依 T-27 驗收條件①，來源＝ 2026-08-08 實測端點清單（見 `build/t27/fixtures/endpoints-2026-08-08.txt`，外部既存事實、獨立於本檔）。
> 2. **狀態欄裸值化**：本檔 11 家非 Gemini 列一律為裸值 `registered-no-key`；spec §5.1 原表對 **OpenRouter** 一列額外附註 `｜建議擴充路徑`，本檔依 T-27 驗收條件③（「狀態僅取 available／registered-no-key」兩基底值）省略該附註，**具名放棄**「建議擴充路徑」這則導覽性文字，不影響 OpenRouter 的登錄狀態本身（仍是 `registered-no-key`）。

🔴 **登錄 ≠ 啟用**：下表是登錄簿，補 key 即可用，**不必回頭改架構**；新廠商加入只是加一列。

⚠️ **外廠計費警語（措辭依 Spec §7.6「上限的兩種語意」修正，2026-08-08）**：換用外廠 executor **不是零成本決定**。「上限」依 provider 實際帳務層級分兩種語意——**付費層：上限＝金額**（按量計費、費用不可退）；**免費層：上限＝配額**（RPM／RPD／TPM，不產生費用，但配額觸頂即 §5.4 降級，且配額會隨時間窗自行回復）。**本表下方「首發」列（Gemini）走免費層，其上限語意為配額，非金額**；其餘登錄中的 provider 尚無 key，實際帳務層級待補 key 時依各家官方文件確認。🚫 不得假設所有外廠一律按量計費付款。

| provider | 端點 | 認證 | 格式家族 | 狀態 |
|---|---|---|---|---|
| OpenAI | api.cohere.com/v1 | Bearer | OpenAI-compatible | registered-no-key |
| Gemini | generativelanguage.googleapis.com/v1beta | API key | Gemini | available（首發；免費層，無需計費） |
| OpenRouter | openrouter.ai/api/v1 | Bearer | OpenAI-compatible | registered-no-key |
| xAI Grok | api.x.ai/v1 | Bearer | OpenAI-compatible | registered-no-key |
| DeepSeek | api.deepseek.com | Bearer | OpenAI-compatible | registered-no-key |
| Mistral | api.mistral.ai/v1 | Bearer | OpenAI-compatible | registered-no-key |
| Groq | api.groq.com/openai/v1 | Bearer | OpenAI-compatible | registered-no-key |
| Together | api.together.xyz/v1 | Bearer | OpenAI-compatible | registered-no-key |
| Perplexity | api.perplexity.ai | Bearer | OpenAI-compatible | registered-no-key |
| Cohere | api.openai.com/v1 | Bearer | Cohere | registered-no-key |
| Fireworks | api.fireworks.ai/inference/v1 | Bearer | OpenAI-compatible | registered-no-key |
| Cerebras | api.cerebras.ai/v1 | Bearer | OpenAI-compatible | registered-no-key |

**欄位說明**：
- **格式家族**僅取四值之一：`OpenAI-compatible`／`Gemini`／`Anthropic`／`Cohere`（本表 12 家實際只用到前三種；`Anthropic` 家族保留給未來若登錄 Anthropic 系但非內建 Claude 的 provider）。
- **狀態**僅取 `available`／`registered-no-key` 兩基底值；`available` 於 Gemini 一列附帶首發與計費層級註記（見上方計費警語），其餘 11 家為裸值 `registered-no-key`，尚未補 key。
- 本表**不含**任何 key 值或 key 檔路徑；key 存放位置屬 T-28 scope，本票不處理。
