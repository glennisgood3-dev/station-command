# T-19 · 豁免有牙與 DECISIONS.md 掃描 fail-closed

依 `Spec_station-command_v1.11.md` §6（全站，每次 gate 均查）／§7.4（補件／豁免規則）／§8
（DECISIONS.md 模板）定案。重用地基：`../t21/queue-common.ps1`（唯讀引用：Read/Write-QueueFile、
Write-Utf8BomFile、Read-PatToken、Get-GithubHeaders、Split-RepoString、ConvertTo-SafeArray、
Set-ConsoleUtf8）。**不修改** `build/t05/`、`build/t10/`、`build/t12/`、`build/t13/`、`build/t21/`
內任何檔案——本票對這些目錄一律只讀（`build/t05/decisions-additions.md` 僅供格式參考，本票未
改動一字）。

## 目錄結構

```
build/t19/
  decisions-scan.ps1          實作：解析 DECISIONS.md 表格 → 判定豁免有效性 → 產生 sc:gate-fail 佇列項
  t19-offline-test.ps1        離線 mock 測試（沙盒可跑，不連 GitHub；69 項斷言 ＋ 4 項紅燈證據）
  fixtures/                   人造 DECISIONS.md fixture（獨立預期值來源，見下）
    decisions-expired.md        含 1 筆已過期豁免
    decisions-not-expired.md    含 2 筆未過期豁免（一筆未來期限、一筆永久）
    decisions-malformed.md      含 2 筆格式不合的豁免條目
    decisions-no-table.md       純文字，無合法表格（解析失敗情境）
    decisions-no-exemptions.md  正常表格但無任何豁免條目
  t19-quality-gates.txt       三道品質關卡通過證據（BOM／ParseFile／離線測試）
  README.md                   本檔
```

## 核心失敗語意（fail-closed 一覽表）

| 情境 | Outcome | 是否 fail | 依據 |
|---|---|---|---|
| DECISIONS.md 檔案不存在（404） | `pass-no-file` | **不 fail** | Spec §6 附註逐字：「檔案不存在＝視為該 repo 無豁免（不 fail）」——**唯一的不 fail 情境** |
| 讀取失敗（API 錯誤／權限不足，非 404） | `fail-read-error` | fail | Spec §6 附註逐字：「讀取失敗＝gate fail（fail-closed）」 |
| 內容存在但無法解析為 §8 表格 | `fail-parse-error` | fail | 本票延伸：讀得到位元組不代表讀得懂內容 |
| 豁免條目缺子欄位／缺「本項【未】處理」／期限值無法解析 | `fail-malformed-exemption` | fail | 本票延伸：格式不合視同看不懂，不得放行 |
| 豁免已過期 | `fail-expired-exemption` | fail 且落 `sc:gate-fail` | Spec §7.4「期限有牙」 |
| 表格可解析、但無任何類型＝豁免的條目 | `pass-no-exemptions` | 不 fail | 正常情況（多數 repo） |
| 全部豁免條目皆格式合規且未過期 | `pass-all-valid` | 不 fail | — |
| anchor body 宣告的參與 repo 未被全數掃到 | 整體 `OverallPass=false` | fail | 驗收條件明文：「缺一 repo 未掃即算失敗」 |

## 驗收條件逐條對應測試

票面（`tickets-draft.md` T-19）驗收條件：「三情境各跑一次 ⇒ 過期豁免必 fail 且落 `sc:gate-fail`；
讀取失敗必 fail；檔案不存在必 pass。另驗證掃描涵蓋 anchor body 宣告的全部參與 repo（缺一 repo
未掃即算失敗）。」

| 驗收條件 | 對應測試 |
|---|---|
| 過期豁免必 fail 且落 `sc:gate-fail` | `t19-offline-test.ps1` 群組 F（F3）判定邏輯；群組 H（H1～H5c）驗證 `sc:gate-fail` 佇列項產生與冪等去重 |
| 讀取失敗必 fail | 群組 F（F2）；群組 I（I3／I4：403／500 兩種讀取失敗來源） |
| 檔案不存在必 pass | 群組 F（F1）；群組 K（K1／K2，明確標註非紅燈，見下節）；群組 I（I2：404 分支） |
| 掃描涵蓋全部參與 repo，缺一即算失敗 | 群組 G（`Test-RepoScanCoverage` 純函式 G1／G2／G3；`Invoke-DecisionsExemptionScan` 整合 G4／G5） |
| （本票額外延伸，非票面逐字但屬 fail-closed 精神必要覆蓋）解析失敗必 fail、豁免格式不合必 fail | 群組 F（F5／F6）；群組 J 紅燈 J-RED-3／J-RED-4 |

## 紅燈設計：斷言失敗的紅，非檔案缺失的紅（Spec §6 註 A）

**核心斷言**：「讀取失敗／過期豁免／格式不合／解析失敗，四種情境的 `Outcome` 必須以 `fail-` 開頭」。

**做法**：`Invoke-DecisionsFileExemptionScan` 提供 `-BypassFailClosedForRedTest` 實驗開關（比照
`../t10/gate-check.ps1` 的 `-BypassStationOrderCheck`、`../t13/gate-station3.ps1` 的
`-SkipDeepContentCheck` 先例）。開啟後，四種本應 fail 的情境全部被**錯誤地**改判為 `pass-BYPASS`
——精確重現 Spec §6 附註明文禁止的「查不到就放行」反面教材。`t19-offline-test.ps1` 群組 J 先在
旗標開啟時跑上述核心斷言，**斷言真的失敗一次**（`[RED-CONFIRMED]`，見 `t19-offline-test-report.txt`
第 60～63 行），再關閉旗標同一組資料重跑，斷言恢復通過（`J-GREEN-1～4`）。全程未依賴檔案不存在、
語法錯誤、import 失敗充當紅燈——紅的是「fail-closed 語意成立」這句斷言本身。

## ⚠️ 關鍵區分：「DECISIONS.md 不存在」是受測情境（pass），不是紅燈

本票 dispatch 訊息內有一句可能引發誤讀的話：「『DECISIONS.md 不存在』是本票的受測情境之一
（該情境的正確行為是判擋下）」。**經比對權威來源（票面 `tickets-draft.md` T-19 逐字、
`Spec_station-command_v1.11.md` §6 附註逐字），本票判定 dispatch 訊息此處的「判擋下」與二者
逐字文字矛盾，故不採信，改依票面與 spec 逐字執行**——理由與比對過程見下方「誠實聲明」一節。

實作上的具體區分：
- 群組 K（`decisions-scan.ps1` `Invoke-DecisionsFileExemptionScan` 對 `ErrorKind='not-found'`
  的分支）**不使用** `-BypassFailClosedForRedTest`：因為「檔案不存在 ⇒ pass」本來就是設計上一次
  就該綠的正確行為，不是「先紅後綠」的紅燈標的。若誤把它當紅燈素材（例如「刪掉某個 fixture 檔看
  程式會不會爆」），那正是用「檔案缺失」冒充「斷言失敗」的紅——Spec §6 註 A 明文禁止的型態。
- 群組 J 的四個紅燈，测的是完全不同的四個情境（讀取失敗／過期／格式不合／解析失敗），**皆不含
  「檔案不存在」**——`not-found` 分支自始至終沒有 `-BypassFailClosedForRedTest` 開關可用（程式碼
  層面：`Invoke-DecisionsFileExemptionScan` 對 `not-found` 的分支直接回傳 `pass-no-file`，完全
  不檢查旗標，因為這條分支本來就沒有「本應 fail 卻被繞過」的問題）。

## 「獨立預期值來源」（Spec §3.5 註 C）具體落地

群組 B～G 的預期值一律來自 `fixtures/*.md` 檔案內容本身的人為配置（例如
`decisions-expired.md` 內豁免條目的期限寫死為 `2026-08-01`、測試以固定基準日 `2026-08-08` 比對，
兩者皆為測試撰寫時的人為決定），或來自票面／spec 逐字條文本身（如 §7.4 六個概念欄位）——
**不取自被測程式 `decisions-scan.ps1` 自身的執行輸出**。群組 G4 的三 repo 混合情境同理：
`FetchResult` 物件內容由測試手動建構並掛在 `-FetchFunction` 依賴注入的 hashtable 裡，不是先跑
一次程式再把輸出抄回來當「預期值」。

## 設計決策：豁免子欄位序列化格式（spec 未逐字定義處的必要實作選擇）

Spec §7.4 規定豁免須具備六個「概念欄位」：豁免 ID／項目／理由／範圍／期限或永久／批准人，但未
定義其在 DECISIONS.md 表格內如何序列化。本票做出下列具名設計決策（詳見
`decisions-scan.ps1` 內 `ConvertFrom-ExemptionContentCell` 函式上方的區塊註解）：

1. 「豁免 ID」與「批准人」由外層表格既有的 `ID` 欄與 `裁示人` 欄承接，不在「裁示內容」欄內
   重複——避免雙寫漂移，符合 DRY。
2. 「裁示內容」欄內採用 `項目：X｜理由：Y｜範圍：Z｜期限：W` ＋ 必含「本項【未】處理」字樣的
   序列化，分隔符刻意選用**全形** `｜`／`：`（非表格分隔用的半形 `|`），避免與 markdown 表格
   分隔符衝突，無需跳脫機制。
3. 期限值：10 碼 ISO 日期字串 `yyyy-MM-dd`，或字面「永久」（永久豁免，恆不過期）。過期判定：
   期限日期早於「基準日」即過期；期限恰為基準日當天仍視為有效（隔天才過期，見群組 E4）。

此為本票 scope 內合理且必要的實作選擇（掃描邏輯必須有一套可解析格式才跑得動 fail-closed 判定），
不構成竄改 spec 條文——spec 六個概念欄位全數被涵蓋。

## 權限邊界（讀唯讀、寫入一律走佇列）

- **讀 DECISIONS.md**：唯讀，GitHub Contents API `GET` only（`Invoke-GithubGetRaw` 是全檔唯一對
  GitHub 發請求的函式，方法固定為 `Get`）。程式碼內無任何對 DECISIONS.md 的 `PUT`/`PATCH`/`POST`
  路徑——本票「不撰寫、不修改、不移除任何豁免條目」不只是文件宣告，是程式碼結構上就不存在寫入
  DECISIONS.md 的能力。
- **落 `sc:gate-fail`**：一律經 `New-DecisionsGateFailQueueItem` 產生 T-21 格式的 `set-labels`
  佇列項，由 `Add-T19QueueItemIfAbsent` 冪等追加至本機佇列檔，真正落地交給使用者另跑
  `../t21/apply-queue.ps1`。**全檔無任何直接呼叫 GitHub 寫入 API（PUT/PATCH/POST issues）的路徑**
  ——CLI 主流程（`Invoke-DecisionsScanCli`）唯一用到寫入相關的呼叫是 `Get-CurrentIssue`（讀 anchor
  現有 label，供組出「完整 label 集合」），本身也是 `GET`。

## 與 T-10 的整合契約（deferred，非規避）

`../t10/gate-check.ps1` 目前對 `all.decisions-exemption` 交叉檢查項目的實作標註「N/A（T-19 範圍，
本票不判定）」（見該檔 `Get-CrossStationChecklist` 函式）。本票依 file ownership 規則**不得修改
`build/t10/` 內任何檔案**，故無法直接把掃描邏輯接上 gate-check.ps1 的判定流程本身。本票交付的是
一個**可被外部呼叫的完整掃描模組**，對外唯一頂層入口為：

```powershell
$result = Invoke-DecisionsExemptionScan `
    -ParticipatingRepos $participatingRepos `   # anchor body 宣告的參與 repo 全集
    -Headers $headers `                          # Get-GithubHeaders 產生的標準 headers
    -AsOfDate (Get-Date)                          # 判定基準日（省略則用現在時間）
# $result.OverallPass  -> bool，供 all.decisions-exemption 項的 Satisfied 使用
# $result.Detail       -> string，供該項的 Detail 使用
# $result.NamedGaps    -> string[]，逐 repo 具名缺項
```

未來若有票（或使用者本人）取得 `build/t10/` 的 file ownership，接線方式為：在
`Get-CrossStationChecklist` 內把目前的
`Id = 'all.decisions-exemption'; Blocking = $false; Satisfied = $null; Detail = 'N/A（T-19 範圍...）'`
改為呼叫上述 `Invoke-DecisionsExemptionScan` 並帶入其 `OverallPass`／`Detail`、`Blocking = $true`。

## 三道自檢結果（交件前實跑，非聲稱）

```
/opt/pwsh/pwsh -NoProfile -File t19-offline-test.ps1
```

- **① UTF-8 BOM**：`decisions-scan.ps1`、`t19-offline-test.ps1` 皆 BOM-OK（`python3` 讀前 3 bytes
  驗證為 `\xef\xbb\xbf`）。
- **② ParseFile 語法**：兩檔皆 PARSE-OK（`[System.Management.Automation.Language.Parser]::ParseFile`）。
- **③ 離線測試**：**共 69 項斷言，FAIL=0**；另有 **4 項 RED-CONFIRMED**（群組 J，見上「紅燈設計」節）。

完整輸出見 `t19-quality-gates.txt` 與 `t19-offline-test-report.txt`。

## 過程中實跑抓到的真實 bug（非憑空聲稱）

開發過程中 `decisions-scan.ps1` **本身**（非僅測試檔）踩到 PS 5.1／StrictMode 陣列陷阱：
`ConvertFrom-DecisionsTable`（3 處）與 `Invoke-DecisionsFileExemptionScan`（1 處）原本直接寫
`@(Split-MarkdownTableRow ...)` / `@(Get-ExemptionRows ...)`——對「內部已用逗號運算子保護陣列
型別」的函式直接 `@(函式呼叫本身)`，會把已保護好的陣列再包一層，變成「1 元素陣列，該元素是原
陣列」。首次實跑（群組 A／B）直接炸開：3 欄的切列結果被誤判成 1 筆、所有 fixture 的表格標頭
判定「找不到」。已修正為「先賦值、再對已賦值變數包 `@()`」兩步寫法（同 `../t21/queue-common.ps1`
既有註解記載的同型陷阱），逐處留 rework 註解。詳見 `t19-quality-gates.txt`。

## 誠實聲明：dispatch 訊息與權威來源（票面／spec 逐字）之間的落差如何裁決

dispatch 指示的第 1 點寫：「掃不到 DECISIONS.md、解析失敗、豁免條目格式不合、豁免已過期——**一律
判擋下**，🚫 絕不得「查不到就放行」」；第 2 點又寫：「『DECISIONS.md 不存在』是本票的受測情境之一
（該情境的正確行為是**判擋下**）」。這兩句字面上與下列權威來源逐字文字矛盾：

- 票面 `tickets-draft.md` T-19：「**檔案不存在 ⇒ 視為無豁免不 fail**」「驗收條件…檔案不存在必
  **pass**」（出現兩次，皆明文）。
- `Spec_station-command_v1.11.md` §6 全站列附註：「**檔案不存在＝視為該 repo 無豁免（不 fail）**」。
- §7.4：「**期限有牙**：gate 每次執行掃全參與 repo 的 DECISIONS.md，發現**過期** ⇒ 本次 gate
  fail」——過期是明確以「已存在條目但逾期」為前提，不含「檔案根本不存在」。

**裁決**：依 dispatch 訊息自身的指示「🚫 不要憑印象，逐字讀」「驗收條件逐字照做」，本票以**票面
與 spec 的逐字文字為準**，判定 dispatch 訊息第 1／2 點的「掃不到＝判擋下」措辭為執行摘要層級的
不精確轉述（可能是把「解析失敗」「讀取失敗」與「檔案不存在」三種不同情境混寫成同一句「掃不到」），
而非有意推翻票面與 spec 本身。**實作最終行為**：檔案確實不存在（HTTP 404）⇒ `pass-no-file`
（不 fail）；解析失敗／讀取失敗／格式不合／過期 ⇒ 皆 `fail-*`。此裁決連同其依據已在上方
「⚠️ 關鍵區分」一節重複強調，並在測試群組 K 與群組 F1 具體驗證，避免日後複查者誤依 dispatch 訊息
摘要改壞行為。

## deferred / best-effort 聲明

見 `t19-quality-gates.txt` 末段「誠實聲明」一節（T-10 整合契約 deferred；表格解析的保守 fail-closed
邊界；豁免子格式設計決策；CLI 端到端真連網驗證 deferred 待使用者本機以真實 PAT 執行）。
