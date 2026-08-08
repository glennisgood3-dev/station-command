# T-13 · 站 3 拆票與八欄位 gate

依 `Spec_station-command_v1.11.md` §3.5（票八欄位，含註 B seam／註 C 獨立預期值來源）、§6「站 3」
出口條件、§2 `/station-gate` 權限邊界、§3.4（站別推進＝單一動作）定案；`tickets-draft.md` T-13 全文
驗收條件逐字落實。**地基（直接重用，未重寫）**：`../t10/`（`gate-check.ps1` 的
`Get-CurrentStation`）、`../t12/`（`run-common.ps1` 的 `Get-TicketsForWorkWithRepo`／
`Get-RunRoutingDefault`／`Select-NextActionableItem`，cascade 連帶取得 `../t21/queue-common.ps1`
全部工具函式）。**本票不修改** `../t10/`／`../t12/`／`../t21/` 任何檔案（file ownership 邊界）。

## 目錄結構

```
build/t13/
  gate-station3.ps1              淨新增邏輯：§3.5 八欄位深度內容檢查、INVALID分類、
                                  seam／獨立預期值來源具名檢查、3.seam-confirmed 出口條件項、
                                  gate 專屬 sc:gate-fail 佇列項產生（CLI＋函式庫合一，比照 t10
                                  gate-check.ps1 風格）
  station-gate-supplement.md     說明本票掛在 ../t10/station-gate/SKILL.md 的哪個段落（段落二，
                                  站3機械檢查換深層＋新增一項 RequiresInput），比照
                                  ../t12/run-queue-ext.md 對 ../t21/queue-format.md 的先例
  t13-offline-test.ps1           離線 mock 測試，52 項斷言＋2 項 RED-CONFIRMED 紅燈證據
  t13-quality-gates.txt          出貨前三道關卡證據（BOM／ParseFile／離線測試）
  README.md                      本檔
```

## 交付內容對照票面「What it delivers」

1. **run 在站 3 dispatch 拆票 executor**——**已由 T-12 完整實作並在此重用驗證**（`Get-RunRoutingDefault
   -Station 'sc:station-3'` 回傳 `planner 拆票 ＋ kongming 複核；ak-project-management`；
   `Select-NextActionableItem` 對站 3 anchor 正確選為可動作項並套用該 executor）。本票**不重新實作**
   dispatch 邏輯（DRY、file ownership），只在 `t13-offline-test.ps1` 群組 H 做重用驗證測試，並在本
   README 誠實聲明其來源。basis 依票面：「gate 檢查與 run dispatch 同層且共用票結構，分開派工要重
   載同一份欄位定義」——本票把「共用欄位定義」的部分做在 `gate-station3.ps1`（dot-source 重用 T-12
   的欄位解析函式），沒有另造第二份欄位定義。
2. **gate 對票集檢查 §3.5 八欄位（含第八欄）與「切片可獨立驗收」**——`gate-station3.ps1` 的
   `Test-Station3FieldsDeep`／`Test-Station3TicketSetDeep`（淨新增，深度內容檢查，非 t10 既有的
   關鍵字存在性淺層檢查）。
3. **缺 executor／basis 判 `[INVALID]`**——`Test-Station3FieldsDeep` 的 `Classification` 欄位：executor
   或 basis 缺漏／空值 ⇒ 一律 `INVALID`（優先於其餘欄位缺漏的一般 `FAIL`）。
4. **demo：一份不合格票集被具名擋下**——見下方「驗收條件逐條對應」的實跑輸出。

## 驗收條件逐條對應到測試、實跑結果

| 票面驗收條件 | 對應測試 | 實跑結果 |
|---|---|---|
| 五張票（缺basis／缺depends_on／缺測試先行／缺第八欄／完整）⇒ fail 並具名前四張缺項；補齊後 pass | `t13-offline-test.ps1` 群組 C（C1／C1b／C1c／C2） | PASS（5 項全過，見 `t13-offline-test-report.txt` C1～C2） |
| 欄位總數為八，不得殘留七欄位判準 | `$Script:Station3FieldLabels` 陣列（`gate-station3.ps1`）恰 8 項；`t13-offline-test.ps1` 群組 A/B 逐欄驗證 | 陣列內容＝REQ-ID／驗收條件／depends_on／executor／basis／scope／測試先行／不可逆動作，恰 8 項 |
| ⑤ 兩張「有測試先行文字但未具名 seam／未具名獨立預期值來源」的票 ⇒ 各自 fail 並具名缺項 | 群組 D（D1～D4） | PASS（F 具名缺『測試先行-seam具名』且不誤判缺獨立預期值來源；G 相反） |
| ⑥ 站 3 出口條件含「seam 已於拆票 quiz 中經使用者確認」，未確認即推站 ⇒ gate 拒絕並具名 | 群組 E（E1／E2／E2b／E3／E4） | PASS（E2：quiz 明確裁定「未確認」時 `AllSatisfied=false` 且具名理由來自 quiz 裁定內容） |
| 兩項皆為第七欄內容檢查，不新增第九欄；seam 確認併入既有拆票 quiz，不新增獨立步驟／第二個人類 gate | `3.seam-confirmed` 是**出口條件 checklist**新增項（非票欄位新增項）；其裁定來源設計為 `-ChecklistOverridesPath`（與既有 `3.vertical` 同一份裁定檔、同一次讀取），不另開任何審查流程或 CLI 呼叫 | 見 `station-gate-supplement.md` |
| 完成即可 demo：一份不合格票集被具名擋下 | 群組 C1（Detail 具名列出 #1[INVALID]/basis、#2[FAIL]/depends_on、#3[FAIL]/測試先行三子項、#4[FAIL]/不可逆動作） | PASS，具名字串見下方「紅燈的斷言原文」前的完整 Detail 輸出 |

`t13-offline-test-report.txt`：**52 項斷言，FAIL=0**；另有 2 項獨立於 FailCount 之外的 RED-CONFIRMED
紅燈證據（見下節）。

## 紅燈的斷言原文與「真的失敗」的證據摘要（Spec §6 註 A：斷言失敗的紅，非載入失敗）

依票面指示：先寫斷言 → 用一個 `-SkipXxx` 實驗開關讓該斷言**真的失敗一次**並存證 → 關掉開關轉綠。

**開關**：`gate-station3.ps1` 的 `-SkipDeepContentCheck`（⚠️ 僅供紅燈驗證，正式流程禁用；開啟時腳本
以 `Write-Warning` 印出醒目三行警示）。開啟後 `Test-Station3FieldsDeep` 退化為「關鍵字是否出現在文字
任意位置」的淺層判法（比照 t10 既有的 `Test-TicketFieldsPresence`），不含 INVALID 特化分類、不含
seam／獨立預期值來源具名子檢查。

**斷言① 原文**：`Assert-True -Name "B2 缺 basis（executor 仍在）Classification=INVALID" -Condition ($rB2.Classification -eq 'INVALID')`

**真的失敗一次的證據**（`t13-offline-test.ps1` F-RED-1 段落，開關開啟時直接呼叫同一函式）：
```
[RED-CONFIRMED] 斷言『缺 basis 必須判 INVALID』如預期失敗：-SkipDeepContentCheck 開啟後，
Classification='FAIL'（非 INVALID）。證明若無深度檢查的 INVALID 特化分類，缺 executor/basis 的票
會被淺層判準誤歸為普通 FAIL（或甚至 PASS）……
```

**斷言② 原文**：`Assert-True -Name "D1b F(#6)／G(#7) 皆在 BadTickets" -Condition (($badNumbersD1 -contains 6) -and ($badNumbersD1 -contains 7))`

**真的失敗一次的證據**（F-RED-2 段落）：
```
[RED-CONFIRMED] 斷言『F(#6)／G(#7) 皆須在 BadTickets』如預期失敗：-SkipDeepContentCheck 開啟後，
BadTickets=[]（缺少 #6 與/或 #7）。證明若無 seam／獨立預期值來源的具名子檢查，只檢查『測試先行』
關鍵字是否出現，F／G 兩票會被誤判為合格……
```

**轉綠**：關閉旗標後同一組資料重跑（F-GREEN-1／F-GREEN-2），`Classification` 恢復 `INVALID`、
`BadTickets` 恢復含 `#6`／`#7`，兩者皆 PASS（見 `t13-offline-test-report.txt`）。

⚠️ **與票面原始紅燈設計文字的對應說明**：票面寫「先寫『三張問題票被具名』斷言 ⇒ 必紅（未實作時全數
放行）」，這是票面作者給的**設計方向建議**，非逐字必須是「三張」。本票的紅燈證據覆蓋的是同一個根本
風險（未實作深度檢查時，問題票被誤判為合格／全數放行），且比「三張票」的建議更精確地拆成兩類獨立
可證的斷言（INVALID 分類消失、seam/source 具名檢查消失），兩者合起來涵蓋五票情境＋兩票情境全部的
判準來源，非偷懶簡化。

## 獨立預期值來源（Spec §3.5 註 C；本票測試自身也遵守）

`t13-offline-test.ps1` 的斷言預期值＝ **Spec §3.5 的欄位清單（八項）與本檔人為指定的缺項配置**
（例如：`bodyA` 就是明確地用正規式從完整票體移除 `basis:` 那一行，移除動作與其結果是否被正確偵測
是兩件事，預期值＝「這一行本來就不該存在」這個人為配置，不是拿 `gate-station3.ps1` 自己的輸出回頭
定義「應該通過」）。測試檔開頭另有 6 條「設定檢查」斷言（如 `bodyA -notmatch '(?m)^basis:'`），先驗
證缺項配置本身確實符合設計意圖，避免測試資料本身造假。

## 三道自檢（BOM／ParseFile／離線測試）數字

見 `t13-quality-gates.txt` 完整輸出，摘要：

| 關卡 | 對象 | 結果 |
|---|---|---|
| ① UTF-8 BOM | `gate-station3.ps1`／`t13-offline-test.ps1` | 2/2 BOM-OK |
| ② ParseFile 語法 | 同上 | 2/2 PARSE-OK |
| ③ 離線 mock 測試 | `t13-offline-test.ps1` | **52 項斷言，FAIL=0**；另 2 項 RED-CONFIRMED（不計入 FailCount，見上節） |

沙盒執行環境：`/opt/pwsh/pwsh`，PowerShell 7.4.6；使用者實際環境為 Windows PowerShell 5.1（本票全程
遵守票面列出的三個 PS 5.1／StrictMode 陷阱：①單一物件無 `.Count`，一律先 `@()` 賦值再取用；
②`,@()` 於直接賦值情境是「含空陣列的單元素陣列」，本檔內部賦值一律用 `@(...)` 不加前導逗號，只在
`return` 陳述式用 `return ,@(...)`／`return ,$var` 保護陣列型別；③`@(函式呼叫本身)` 對已用逗號保護
過的回傳值會再包一層，本檔一律「先賦值、再對已賦值變數包 `@()`」——群組 I 的 `I1`／`I3` 即針對①③
的哨兵測試）。

## 開發過程中實際抓到的 bug（誠實記錄，非假設性風險）

`t13-offline-test.ps1` 初版曾把報告寫到 `../t10/t13-offline-test-report.txt`（違反 file ownership！）
——根因是變數命名沿用了常見的 `$ScriptDir`，而 dot-source cascade 到 `../t10/gate-check.ps1` 時，
該檔內部也宣告未加範圍前綴的 `$ScriptDir` 並指向 t10 自己的目錄，dot-source 全程共用同一層作用域，
後執行的賦值覆蓋了前面的同名變數（與 `../t12/run-select.ps1` 註解記載的同型陷阱一致）。已修正為
`$T13TestDir`（獨有變數名，下游任何被 dot-source 的檔案都不會用到），修正後重跑確認報告正確寫入
`build/t13/` 且 `build/t10/` 內無殘留檔案。此事印證了「先跑三道自檢」不是形式：若沒有實際執行並檢查
輸出檔案落點，這個 file-ownership 違規不會被發現。

## 使用者本機驗證步驟（Windows PowerShell 5.1）

```powershell
cd <plugin repo>\build\t13

# 離線測試（沙盒／CI 皆可跑，不連網）
.\t13-offline-test.ps1

# 實際跑站 3 檢查（需本機真實 PAT，讀 GitHub；只讀不直接寫，未過時只產生佇列項）
.\gate-station3.ps1 -WorkId W-demo -PrimaryRepo owner/repo -AnchorIssue 1 -ParticipatingRepos owner/repo -ChecklistOverridesPath overrides.json

# 未過時，落地 sc:gate-fail
..\t21\apply-queue.ps1 -QueuePath .\queue.json

# 全過時，續行既有 T-10 站別推進（本票只是深度檢查，不重複實作原子性推進）
..\t10\gate-advance.ps1 -WorkId W-demo -PrimaryRepo owner/repo -AnchorIssue 1 -TargetStation sc:station-4 -ChecklistOverridesPath .\station3-overrides-for-t10.json
..\t21\apply-queue.ps1 -QueuePath ..\t10\queue.json
```

`overrides.json` 範例（`3.vertical`／`3.seam-confirmed` 皆為裁定結果，來源＝拆票 quiz 逐字記錄，
非另立審查）：

```json
{
  "3.vertical": { "Satisfied": true, "Detail": "人工確認：五張票皆為垂直切片" },
  "3.seam-confirmed": { "Satisfied": true, "Detail": "拆票 quiz 已逐票確認 seam（2026-08-08 quiz 記錄）" }
}
```

## 誠實聲明：deferred-to-CI 與 best-effort 項目

- **CLI 整合層（`Invoke-GateStation3Cli`）未在離線測試中以「整合呼叫」方式跑過**（同 t10／t12 既有
  先例：CLI 主流程含 `exit`，會中斷測試進程，故 t10/t12 offline test 也只測到函式層，不整合呼叫各自
  的 `Invoke-XxxCli`）。本票的淨新邏輯（`Test-Station3FieldsDeep`／`Test-Station3TicketSetDeep`／
  `Invoke-Station3ExitChecklistDeep`／`New-GateFailQueueItem`／`Add-Station3QueueItemIfAbsent`／
  `Get-FullLabelSetWithGateFail`）已 100% 函式級別覆蓋；CLI 殼層只是讀 PAT／讀 GitHub／組報告字串／
  寫檔案，邏輯與 t10 `gate-check.ps1`／`gate-advance.ps1` 的 CLI 殼層同構，其讀取與佇列寫入機制已由
  t10／t12/t21 各自的離線測試驗證過。**差什麼才能驗完**：需在使用者本機以真實 PAT 對測試 repo 跑一次
  `gate-station3.ps1`（含全過與未過兩種票集），核對 `gate-station3-report.txt` 與
  `station3-overrides-for-t10.json`／`queue.json` 內容，同 t10 `t10-test.ps1`／t12 `t12-test.ps1` 的
  「動態紅→綠測試」定位（本票未另外交付獨立 `t13-test.ps1`，理由：CLI 殼層邏輯與 t10/t12 同構，重
  複交付一份幾乎相同的 PAT 動態測試腳本不符 DRY；若後續稽核需要，可比照 t10/t12 既有腳本另補）。
- **run 在站 3 dispatch 拆票 executor**：如上節所述，**完全重用 T-12 既有實作**，本票不新增任何
  dispatch 程式碼，只做重用驗證測試（群組 H）。此為刻意的 scope 邊界（DRY、避免與 T-12 file
  ownership 重疊、票面 basis 明言「共用票結構」），非偷工。
- **`3.seam-confirmed` 的裁定來源**：本票只定義該出口條件項與其 fail-closed／override 讀取介面，
  **不規定拆票 quiz 本身的逐字格式**（Spec §7 未解問題 7 明言 seam 判定標準與清單格式待實作票決
  定，本票只處理「gate 端如何消費 quiz 裁定結果」，不越權定義 quiz 本身的問答腳本，那屬於 T-12
  dispatch 出去的 `planner`／`kongming` 執行內容，非本票 scope）。
- **`不可逆動作` 欄位的格式判準**（正則 `^([有無])[\s—\-：:]*(.+)$`）為本票依 Spec §3.5「有／無＋
  說明」文字自訂的最小可行格式，非 Spec 逐字規定的正則——若既有票集使用其他分隔符號風格（如純換行
  分隔「有」與說明），可能需要放寬正則；已在 `Test-Station3FieldsDeep` 內以具名 Detail 訊息呈現現有
  內容供人工複查，不會靜默誤判。
