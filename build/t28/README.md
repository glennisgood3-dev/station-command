# T-28 · 異廠呼叫適配層、key 路徑、逾時重試與降級

本目錄交付四個格式家族的最小唯讀推論適配、外部連接資料夾 key 讀取、逾時／5xx 至多一次重試、具名降級、四表面 key 掃描，以及供 Commander 在有網路環境執行的 12 家兩層式可達性檢查。

## Scope 與誠實聲明

本票只證明「請求形狀符合文件化 schema，且有一支可執行腳本能逐家驗證送得到」；**不驗、也不宣稱對方正確理解請求或回出可用業務內容**，該端到端語意驗證屬 T-31。本票未做成本記帳（T-29），未接站 5（T-30）。

執行環境依使用者禁令無外網，因此 executor **沒有執行 rework 後的 12 家真實可達性呼叫**，也沒有碰任何真 key。Commander 對舊版的實測事實是 10 家落在舊白名單、xAI Grok 回 400、Fireworks 回 404；後續逐點探測又證實 xAI `GET /v1/models` 與 Fireworks `GET /inference/v1/models` 都回 401。這證明兩家網路可達，舊失敗是 probe 路徑／方法與判準錯誤。rework 後的 12 家動態結果仍由 Commander 在可連外環境重跑，executor 不冒稱已通過。

Gemini 首發為免費層，不需開啟計費；其「上限」是 RPM／RPD／TPM 配額。付費層的「上限」才是金額。兩者的成本／配額記帳與 100% 停手均不在本票，留給 T-29；429 在本適配層只作具名降級且不阻塞生產線。

## 交付檔清單

| 檔案 | 用途 |
|---|---|
| `vendor-adapter.ps1` | 四家族請求組裝、回應解碼、唯讀白名單、key 讀取、逾時／5xx 重試與具名降級核心 |
| `invoke-vendor.ps1` | provider＋model CLI；含參數作用域防火牆與不連網的 `-DryRun` |
| `key-leak-scan.ps1` | 純函式庫；只定義四表面掃描函式，須由呼叫端 dot-source 使用；直接執行只顯示 usage、不會掃描 |
| `reachability-policy.ps1` | 可達性／探測品質兩層分類的共用純函式，供網路腳本與離線人造回應測試共用 |
| `check-reachability.ps1` | 12 家 fixture 離線驗證；Commander 的逐家無 key GET 網路檢查入口 |
| `t28-offline-test.ps1` | 68 條完整離線機械斷言；群組 C／E 實際呼叫四表面掃描函式；含兩個既有紅燈開關 |
| `fixtures/official-request-schemas.json` | 四家族官方文件化 schema 的凍結必要子集與官方來源 URL |
| `fixtures/family-responses.json` | 四家族獨立回應 fixture 與已知預期文字 |
| `fixtures/reachability-2026-08-08.json` | 12 家端點、GET 模型清單 probe、逐列選擇理由與探測品質區間 fixture |
| `evidence/red-assertion-failures.txt` | 兩條指定斷言真的失敗的紅燈摘要 |
| `evidence/green-offline.txt` | 正式綠燈摘要 |
| `evidence/verification.txt` | BOM、ParseFile、離線 fixture 與 CLI smoke 結果 |
| `README.md` | 本文件 |

本次 rework 只修改 `build/t28/` 內既有交付並新增共用政策檔；沒有修改 `build/t09`～`build/t27`、`build/station-command/`、Spec 或 tickets 檔。T-27 的 `build/station-command/assets/vendor-registry.md` 全程唯讀。

## 適配與 key 路徑

適配只按 `OpenAI-compatible`／`Gemini`／`Anthropic`／`Cohere` 四個格式家族分支；12 家 provider 的端點與格式家族由 T-27 registry 解析，不存在個別廠商專屬分支。四家族只允許下列推論端點：

| 家族 | method／路徑 | 認證 header | 最小回應出口 |
|---|---|---|---|
| OpenAI-compatible | `POST …/chat/completions` | `Authorization: Bearer …` | `choices[0].message.content` |
| Gemini | `POST …/models/{model}:generateContent` | `x-goog-api-key` | `candidates[0].content.parts[0].text` |
| Anthropic | `POST …/v1/messages` | `x-api-key`＋`anthropic-version` | `content[0].text` |
| Cohere | `POST …/chat` | `Authorization: Bearer …` | `text` |

連接資料夾由 `-ConnectionFolder` 設定；檔名為 provider 小寫 slug 加 `.key`，例如 `OpenAI` 對應 `openai.key`、`xAI Grok` 對應 `xai-grok.key`。連接資料夾必須位於 repo 外，若指向 repo 或其子目錄會直接拒絕。缺檔或空檔視為 provider 不可用，不送請求，立即產生具名降級。

key 只在記憶體中進入認證 header：不放 body、不放 URI、不回傳 request、不寫 log、不寫佇列。若回應內容意外含 key，內容會被攔截並改走具名降級。log 只含 provider、事件和預先限定的原因／HTTP code。

一般 CLI 範例：

```powershell
& .\invoke-vendor.ps1 `
  -Provider 'OpenAI' `
  -Model '由 Commander 指定的模型' `
  -Prompt '最小唯讀提示' `
  -ConnectionFolder 'G:\station-connections' `
  -FallbackProvider 'Claude' `
  -TimeoutSec 30
```

只驗請求形狀、不送網路：

```powershell
& .\invoke-vendor.ps1 -Provider 'OpenAI' -Model 'fixture-model' -Prompt 'smoke' -ConnectionFolder 'G:\station-connections' -DryRun
```

## 驗收②的兩層判定

`check-reachability.ps1` 對每家分開輸出兩行，兩層不可互相替代：

1. **可達性（驗收②判定）**：只要取得 provider 的任何 HTTP 回應，不論狀態碼，皆為 `[REACHABILITY PASS]`。DNS 解析失敗、連線被拒、逾時等沒有 HTTP 回應的網路錯誤才是 `[REACHABILITY FAIL]`；本專案實錄的 HTTP 421 是 proxy 攔截而非 provider 回應，因此也判 FAIL。腳本 exit code 只由本層是否有 FAIL 決定。
2. **探測品質（診斷訊號）**：200／401／403／429 表示清單端點形狀合理，輸出 `[PROBE PASS]`；400／404／405 等其他 provider HTTP 狀態輸出 `[PROBE WARN]`，並具名「probe 路徑或方法可能不適用於該 provider」，但不把可達性改判 FAIL。沒有 provider 回應或遇 proxy 421 時，本層輸出 `[PROBE N/A]`。

註記（本專案實錄教訓）：**400／404 不等於連不到**。它們已是伺服器送回的 HTTP 回應，只能說 probe 的路徑、方法或請求形狀可能不合。舊版曾把 404 誤報為被攔截；本次 rework 將網路層可達性與應用層 probe 品質拆開，避免再犯同一判讀錯誤。

12 家 fixture 現在全用無 body 的 `GET .../models` 清單端點，且逐列保存理由。Gemini 採官方形狀 `GET /v1beta/models`，避開 `POST ...:generateContent`；Cohere 採 `GET /v1/models`，避開 `POST /v1/chat`。xAI 與 Fireworks 分別固定為 Commander 已證實回 401 的 `GET /v1/models` 與 `GET /inference/v1/models`。

Perplexity 是具名例外：它沒有 `GET /models` 端點；fixture 保留統一的無 body GET 作網路層可達性探測，因此本家 `PROBE WARN` 恆為預期，非缺陷，也不是可達性迴歸。驗收②仍只看獨立的可達性層；此註記不改動兩層判準。

## 驗收條件逐條對應與實跑結果

| 驗收 | 測試落點 | 本環境實跑結果 |
|---|---|---|
| ① 四家族請求構造與回應解碼 | `t28-offline-test.ps1` 群組 B；逐家族比對 fixture 的 method、endpoint suffix、必要 header、認證位置、body paths、response path | PASS；四家族全過 |
| ② 12 家可達性 | 群組 A 比對 registry 與 fixture 的 12 個 GET models probe；群組 A2 用 8 組人造回應驗兩層政策；`check-reachability.ps1` 逐家送一次無 key GET | fixture／政策／腳本 PASS；**rework 後動態 12 家未跑，待 Commander** |
| ③ key 不外洩 | 群組 C／E；四表面合併掃描、四表面逐一植入測試 key 的陽性控制、正式 repo 全域掃描、repo 內連接資料夾拒絕、回應含 key 攔截 | PASS；正式命中數 0，四個陽性控制各檢出 1 |
| ④ 逾時與 5xx 重試 | 群組 D；兩種 transport 模擬、`RetryCount` 與 mock 呼叫計數雙重機械斷言、attempt 上限斷言 | PASS；兩者 retry=1、attempts=2、最終 unavailable |
| ⑤ 降級具名且續跑 | 群組 D；逾時、503、缺 key、回應含 key 四種失敗 | PASS；每筆皆含 provider／失敗原因／承接者／生產線繼續=True |

獨立預期值不是由適配層輸出反推：四家族結構採 `official-request-schemas.json` 內凍結的官方必要子集與官方 URL；回應採手寫的 `family-responses.json`；12 家端點採 Spec v1.11:198,400 與 T-27 凍結端點事實；xAI／Fireworks 路徑採 Commander 本輪逐點實測事實。因本環境禁網，本輪沒有重新瀏覽官方網站，fixture 是可審核的外部契約快照，不冒稱 executor 做過線上即時查證。

## 紅燈：兩條斷言原文與真的失敗

斷言③原文：

> key 不得出現在對話輸出、repo 內容、log、待寫佇列四處任一處。

斷言④原文：

> 模擬逾時與 5xx，各重試恰一次後判該 provider 不可用，不得無限重試。

紅燈指令：

```powershell
& .\t28-offline-test.ps1 -SkipKeyRedaction -SkipRetry
```

`-SkipKeyRedaction` 與 `-SkipRetry` **僅供紅燈驗證，正式流程禁用**。本次真跑結果為 exit 1、PASS=66、FAIL=2；只有上述兩條出現 `[ASSERTION FAILED]`。前者報命中數 4 但不顯示 key，後者報 timeout retry=0、5xx retry=0。腳本完整跑到最後，並非載入／collection 失敗。摘要見 `evidence/red-assertion-failures.txt`。

關閉兩個開關後重跑同一檔：exit 0、PASS=68、FAIL=0；新增斷言以子行程直接執行 `key-leak-scan.ps1`，鎖定輸出不得為空；timeout retry=1、5xx retry=1，四表面命中數 0。政策斷言涵蓋 200／401／403／429／400／404／405／連線失敗，並額外鎖定 proxy 421 特例。摘要見 `evidence/green-offline.txt`；新斷言的獨立紅綠證據見 `evidence/rework2-key-leak-usage-red-green.txt`。

## BOM、ParseFile、離線測試與 CLI smoke

- UTF-8 BOM：6/6 個 `.ps1` 的首三 bytes 皆為 `EF BB BF`。
- ParseFile：6/6，errors=0。
- 完整離線測試：68/68 PASS，0 FAIL，exit 0。
- 可達性 fixture 離線檢查：exit 0；12 家逐列符合 T-27 asset，皆為具名理由的 GET models probe；探測品質區間逐字為 200／401／403／429；未送網路。
- CLI smoke 1：repo 外暫存連接資料夾＋執行期組合的測試 key＋`-DryRun`，exit 0，輸出只含 provider／family／method／host／「認證 header 已設定」，未顯示 key、未送網路。
- CLI smoke 2：Cohere 缺 key，exit 0，輸出具名 `provider=Cohere`、`失敗原因=缺少 key`、`承接者=Claude`、`生產線繼續=True`。

完整摘要見 `evidence/verification.txt`。

## Commander：12 家可達性檢查怎麼跑

先在 repo 根目錄做 fixture-only 確認（不連網）：

```powershell
& .\build\t28\check-reachability.ps1 -ValidateFixtureOnly
```

再於允許外網的 Windows PowerShell 5.1 執行：

```powershell
Set-StrictMode -Version Latest
& .\build\t28\check-reachability.ps1 `
  -RunNetworkCheck `
  -TimeoutSec 20 `
  -OutputPath .\build\t28\commander-reachability-result.txt
```

腳本固定逐家一次、共 12 次 `GET .../models`；不送 body、不讀連接資料夾、不帶 key、不重試，也沒有寫入、部署、付費升級或工具呼叫。請分開看每家的 `[REACHABILITY ...]` 與 `[PROBE ...]`，以及最後兩行 `REACHABILITY RESULT`／`PROBE QUALITY RESULT`。驗收②以 `unreachable=0` 與 exit 0 為準；`PROBE WARN` 是診斷警告，不是可達性失敗。若 Commander 實測產生 `commander-reachability-result.txt`，該檔是尚未存在的外部動態證據，不應由本離線交付預造。

## 最終誠實聲明

已實證：四家族請求形狀與認證 header 位置、fixture 回應解碼、key 路徑與防洩漏、逾時／5xx 恰一次重試、具名降級與生產線續跑、兩層可達性政策的人造回應分類、PS 5.1 語法／BOM／StrictMode 邊界、CLI 離線路徑。

未實證：12 家目前在 Commander 網路環境的動態可達性、任何真 key 呼叫、對方是否正確理解提示與回出可用內容、成本記帳、站 5 接線。沒有真實 key／token／個資寫入程式碼、repo、log、證據或 README；沒有宣稱 T-31、T-29、T-30 的成果。
