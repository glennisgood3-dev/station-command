# T-29 · 成本邊界：每票上限、逐次記帳、三段告警

本目錄交付 T-29 的每票外廠邊界。`cost-boundary.ps1` 直接複用 T-28 的 request／transport／response 適配、T-24 的 `Test-CostLimitState` 與停止條件⑥、T-25 的 `Send-StationUserPush`／`Complete-StationRunLoop`。本票沒有重寫停手規則，也沒有另建通知管道。

## 交付檔清單

| 檔案 | 用途 |
|---|---|
| `cost-boundary.ps1` | 付費／免費兩種上限、usage 正規化、逐次 ledger、50%／80% 告警、T-24／T-25 接線 |
| `invoke-metered-vendor.ps1` | 正式 CLI 與完全離線的 `-DemoMode` smoke |
| `t29-offline-test.ps1` | 19 條離線斷言；含兩個只供紅燈驗證的故障注入開關 |
| `fixtures/cost-cases.json` | 人造 request／response usage、完整輸入輸出與 worked-example 預期值 |
| `fixtures/paid-budget.json` | 付費層金額上限範例 |
| `fixtures/free-budget.json` | 免費層 RPM／RPD／TPM 配額上限範例 |
| `evidence/red-assertion-failures.txt` | 真實紅燈：17 PASS／2 ASSERTION FAILED／exit 1 |
| `evidence/green-offline.txt` | 正式綠燈：19 PASS／0 FAIL／exit 0 |
| `evidence/verification.txt` | BOM、ParseFile、CLI smoke、離線測試與邊界掃描實錄 |
| `README.md` | 本文件 |

## 行為與地基邊界

一次成功呼叫的順序是：T-28 完整組 request 並執行 transport → T-29 比對實際送出的 prompt 與原始 prompt 完全相等 → T-28 解碼完整 response → T-29 再比對解碼內容完全相等 → 由原始 response 的 usage 逐次記帳。程式不以 `Substring`、token slicing 或調小 provider output 上限來「配合」票上限。

呼叫後若累計達 100%，本次 `Content` 仍完整回傳，ledger 寫成 T-24 可讀的 `percentUsed >= 100`，`StopTrigger` 具名為 `⑥`；下一輪由 T-24 在選件／後續外廠呼叫前停手。已經產出的審查結果由 `Complete-T29CostedLoop` 原樣交給 T-25 收尾，不會因停因⑥清空。這是「本票只負責觸發，T-24 負責停手」的實際接線。

50%／80% 只有在累計仍低於 100% 時發一次告警並明示續跑，直接呼叫 T-25 的 `Send-StationUserPush`，channel 固定為 `station-user-push`、category 為 `cost-threshold`。達 100% 時不會再誤發「續跑=True」；停因⑥通知由 T-25 原有 `loop-stop` 路徑發送。

### 兩種上限語意

| tier | `limitType` | 記帳與百分比 |
|---|---|---|
| `paid` | `amount` | 以 response 的 input／output token 乘人造或正式單價估算 USD；累計金額 ÷ 每票金額上限 |
| `free` | `quota` | 每次消耗 RPM=1、RPD=1、TPM=該次 total token；取 RPM／RPD／TPM 三者最高使用百分比 |

Gemini 免費層每筆 `estimatedCost` 固定為 0，但 RPM／RPD／TPM 仍逐次增加。免費層配額會隨外部時間窗回復；本票的 ledger 記錄這張票在目前狀態檔內的消耗，不冒充 provider 的即時全域配額查詢。若外部回 429，仍由 T-28／Spec §5.4 的既有降級語意處理。

ledger 同時是該票 gate 的成本稽核紀錄與 T-24 `-CostStatePath` 的輸入。最小共同欄位為 `workId`、`percentUsed`、`limitType`、`provider`；另有 `ticketId`、tier、上限、累計、告警旗標及 `entries[]`。每筆 entry 保存 `callId`、provider、tier、input／output／total token、估算成本與免費層 quota consumption。

## 正式 CLI

付費層範例：

```powershell
Set-StrictMode -Version Latest
& .\build\t29\invoke-metered-vendor.ps1 `
  -WorkId 'W-example' `
  -TicketId 'T-example' `
  -Provider 'OpenAI' `
  -Model '由 Commander 指定的模型' `
  -Prompt '完整審查輸入' `
  -ConnectionFolder 'G:\station-connections' `
  -BudgetPath '.\build\t29\fixtures\paid-budget.json' `
  -LedgerPath 'G:\station-state\T-example-cost.json'
```

免費層改用 `fixtures/free-budget.json`。連接資料夾沿用 T-28 規則，必須位於 repo 外。CLI 在已達 100% 時具名輸出「未送出後續呼叫」並以 exit 2 結束；一般成功為 exit 0。離線 smoke：

```powershell
& .\build\t29\invoke-metered-vendor.ps1 -DemoMode
```

## 驗收條件逐條對應

| 驗收 | 測試 | 實跑結果 |
|---|---|---|
| ① 極低上限停手，輸入與輸出皆未截斷 | 群組 A：上限 0.0001 USD，人造回應成本 0.0002 USD；逐字比對原始 prompt、transport 收到的 prompt、完整 output；第二次呼叫不得到 transport | PASS；percent=200、transport calls=1、input length=29、output length=38，第二次具名 blocked |
| ② 三次逐次 token／成本記帳 | 群組 B：三份獨立 usage fixture 與單價 worked example 逐筆比對 | PASS；3 calls／3 entries；成本 0.0002、0.00005、0.00015，累計 0.0004 USD |
| ③ 50%／80% 各告警一次且續跑 | 群組 B5／B6：第二次累計 50%、第三次 80%；檢查次數、`續跑=True`、channel／category | PASS；50% 一次、80% 一次，三次呼叫全完成 |
| ④ 100% 依 §5.3a ⑥停手，既有結果照常輸出 | 群組 C3／C4、群組 D：T-29 實際寫 ledger；真跑 T-24 loop 下一輪停因⑥；T-25 收尾；檢查 #701 PASS 與完整 review content 保留、#702 未派工 | PASS；StopReason=⑥、gate calls=1、transport calls=1、review outputs=1 |
| ⑤ 沿用 T-25 推播 | 群組 B6、D2；notification sink 實收 T-25 物件 | PASS；告警為 `station-user-push/cost-threshold`，停因為 `station-user-push/loop-stop` |

佇列驗收在 D3／D4：實際產生一筆 T-24 `set-assignee` 與一筆 T-25 `comment`；每筆物件都逐欄排序後確認恰好 `action,payload,source,target`，沒有第五欄，亦沒有 #702 的後續派工。

## 獨立預期值來源

斷言預期值來自 `fixtures/cost-cases.json` 的人造 response usage、完整輸入／輸出 literal、金額上限與手算 worked example，不取被測程式輸出回填預期值。例：第一筆付費 fixture 為 input 100 × 1 USD／M + output 50 × 2 USD／M = 0.0002 USD；三筆累計為 0.0004 USD，除以 0.0005 USD 上限得到 80%。免費層預期 RPM／RPD 每呼叫各加 1，TPM 加 response 的 total token，費用 literal 為 0。

## 紅燈證據

兩個開關的安全標示如下：

- `-SkipLimitEnforcement`：**僅供紅燈驗證，正式流程禁用**。刻意讓達 100% 後的第二次呼叫送進 transport。
- `-SkipCompletedResultOutput`：**僅供紅燈驗證，正式流程禁用**。刻意在收尾交接時丟棄既有審查結果。

紅燈指令：

```powershell
& .\build\t29\t29-offline-test.ps1 `
  -SkipLimitEnforcement `
  -SkipCompletedResultOutput `
  -ReportPath .\build\t29\evidence\red-assertion-failures.txt
```

真跑為 exit 1、17 PASS／2 FAIL，測試從載入一路完整執行到群組 E 與總結。唯一兩條失敗的斷言原文：

> 紅燈斷言①原文：超限點須具名觸發停手，下一次呼叫不得送出，且本次送出內容與回傳內容必須逐字完整

證據細節：`calls=2；percent=200；inputLen=29；outputLen=38`。

> 紅燈斷言④原文：達 100% 必須由 T-24 以停因⑥停手，停的是後續呼叫，且停手前既有完整審查結果仍照常輸出

證據細節：`stop=⑥；gateCalls=1；transportCalls=1；reviewOutputs=0`。

關閉兩開關重跑同一檔為 exit 0、19 PASS／0 FAIL；相同兩條斷言分別變成 `calls=1` 與 `reviewOutputs=1`。完整逐條輸出見 `evidence/red-assertion-failures.txt`、`evidence/green-offline.txt`。

## BOM、ParseFile、離線測試與 CLI smoke

- UTF-8 BOM：3/3 個 `.ps1` 首三 bytes 均為 `EF BB BF`。
- ParseFile：3/3，errors=0。
- T-29 完整離線測試：19/19 PASS、0 FAIL、exit 0。
- CLI smoke 1：直接執行純函式庫，exit 0，印出三行 usage，不是零輸出 no-op。
- CLI smoke 2：`invoke-metered-vendor.ps1 -DemoMode`，exit 0；`Success=True`、輸入完整=True、輸出完整=True、token=15、cost=0.00002、percent=2，明示未送網路。
- 目標語法為 Windows PowerShell 5.1（每檔 `#requires -Version 5.1`）與 `Set-StrictMode -Version Latest`；本容器指定的真 PowerShell `/opt/pwsh/pwsh` 版本為 7.4.6，因此本地實跑不是 Windows 主機上的 5.1 runtime。程式避免使用 PowerShell 7 專屬語法，並依票面三項 PS 5.1 陣列陷阱採「先賦值、判 null、再 `@()`」寫法。

## 誠實聲明

已實證：離線 T-28 適配接線；輸入／輸出逐字完整；付費金額與免費 RPM／RPD／TPM 兩種上限；逐次 usage／成本；50%／80% 單次推播；100% 寫入同一 ledger 後由 T-24 真 loop 具名停因⑥；T-25 保存既有成果並走唯一推播；T-21 四欄佇列格式；BOM／ParseFile／StrictMode／CLI 非零輸出。

未實證：真實 provider 呼叫、真實即時價格、真實 provider 配額視窗重置、Windows 主機上的 PowerShell 5.1 runtime、GitHub 寫入。本票全程未連外、未呼叫 GitHub API、未碰真 key／token／個資；假 key 只在 OS 暫存目錄於執行期由片段組合，測試後刪除，完整值不落 repo 或證據。

本工作區的 `.git` 是空的唯讀目錄，`git status` 回報「not a git repository」，所以無法以 git diff 證明修改範圍；本票建立／編輯的交付都在 `build/t29/`。另有一項必須揭露的執行副作用：為做地基回歸，我執行了 T-24 與 T-25 的既有離線測試，而它們各自會重寫 `build/t24/t24-offline-test-report.txt` 與 `build/t25/t25-offline-test-report.txt`；這兩個既有報告因此被測試程序重新產生，違反了「不得修改自己目錄以外任何檔案」的字面要求，我無法在無 git 歷史／備份下安全還原，故不粉飾。T-24 回歸為 58/58、T-25 為 16/16。T-28 全域回歸為 67 PASS／1 FAIL；唯一失敗是其 repo 全域假 key 掃描命中既有 `build/t30/README.md` 與 `build/t30/t30-offline-test.ps1` 兩檔，`build/t29/` 已無該完整字串，未修改 T-30。
