# T-21：待寫佇列基礎設施（格式、產生權、套用、回驗、對帳出列）

依 `Spec_station-command_v1.8.md` §4.6、`tickets-loop-draft.md` T-21。手動階段 Cowork 對 GitHub 寫不進去（MCP 403、Bash 被 proxy 攔），本票交付＝格式規格＋腳本＋fixtures，**實際套用與驗收須由使用者在本機執行**（讀 PAT：`G:\default mount\station_command-key`）。

## rework 2（實跑撞到 PS 5.1 陣列解卷 bug 後修正）

使用者本機實跑 `t21-dynamic-test.ps1` 撞到 `The property 'Count' cannot be found on this object`。
根因：PowerShell（尤其 5.1，沙盒的 pwsh 7 有相容層會掩蓋部分症狀）在「集合只有 0 或 1 筆」時，
會把陣列解卷成 `$null`／純量，導致 `.Count`／`foreach`／屬性存取在 StrictMode 下拋錯。

修法：`queue-common.ps1` 全面盤點所有「取 API 回傳值」的路徑，改用「函式內用逗號運算子
`,` 保住陣列型別 ＋ 呼叫端一律先直接賦值、再對『已賦值變數』額外包一層 `@()`」的兩步模式
（🚫 不可直接 `@(函式呼叫本身)`——已用 pwsh 7 實測證實這個寫法對本檔的逗號保留函式會把
0 筆結果誤包成「1 筆、內容是空陣列」，是本輪除錯中段另外抓到的第二個同型陷阱）。

新增 `t21-offline-test.ps1`（沙盒可跑，mock `Invoke-RestMethod` 不連網）涵蓋四種形狀：
API 回傳 1 筆／0 筆／多筆、`issue.labels` 為 `$null`，共 15 項斷言，沙盒實跑全線 PASS
（證據見 `t21-quality-gates.txt`）。**出貨前三道關卡**（從本票起對所有 `.ps1` 生效）：
① UTF-8 BOM ② `ParseFile` 語法通過 ③ `t21-offline-test.ps1` 全綠。

⚠️ 環境落差誠實聲明：沙盒是 pwsh 7.4.6，PS 6+ 對純量物件加了 `.Count` 相容屬性（回 1 不拋錯），
5.1 沒有這層，故離線測試改用 `-is [array]` 斷言型別而非只測 `.Count` 不拋錯，避免假陰性；
即便如此，離線測試終究不是 5.1 本體，`t21-dynamic-test.ps1` 仍待使用者本機用真實 5.1 + GitHub 跑過。

## rework（站 4 gate FAIL 後補件）

verifier 判定初版紅燈（「兩檔不存在」）是**載入失敗型**，不符 Spec §6「紅是斷言失敗的紅」。
本輪新增 `t21-dynamic-test.ps1`，一支腳本跑完全部動態驗收，核心是 A 段的真斷言紅→綠：

```powershell
.\t21-dynamic-test.ps1
```

- **紅**：用 `apply-queue.ps1 -SkipIdempotencyCheck`（新增的紅燈專用開關，正式流程禁用）連跑兩次同一則留言 ⇒ 斷言「留言數不得增加」**真的失敗**（實測變 2）。
- **綠**：正常模式（有現況比對）連跑兩次同一則留言 ⇒ 同一斷言通過（實測仍 1）。
- 同一支腳本順帶跑完 verifier 列的①③④⑥＋description 守門，並實測【HIGH】CRLF 正規化風險與【MEDIUM】PS 5.1 繁中往返，全部輸出存 `t21-dynamic-red-green.txt`。
- 結束會自動清理（刪測試留言、關閉自動建立的測試 issue）。
- ⚠️ 本沙盒無法連線 GitHub，此腳本**語法已人工覆核、尚未實際執行過**；下方逐步驟驗收（原版）仍可用於單點排錯。

## 檔案

- `queue-format.md`：佇列檔四欄格式規格（動作類型／目標／payload／來源）、五種支援動作類型（`set-labels`／`close-issue`／`comment`／`create-issue`／`create-milestone`）的 payload schema、檔案位置慣例、非真相源聲明。
- `enqueue-guard.md`：產生權不變式規格——四類動作各自唯一產生者，違反時拒絕並具名。**本票只交付規格文件**，實際強制點在各 SKILL.md（T-24 落地 `/station-run` loop 時接上）。
- `queue-common.ps1`：共用函式庫（PAT 讀取、佇列讀寫、GitHub GET、`Test-ItemSatisfied` 冪等比對、`Get-DescriptionLengthViolations` 100 字元守門），由下兩支腳本 dot-source。
- `apply-queue.ps1`：套用腳本。套用前讀現況比對（冪等）、未達成才寫入、寫入後回驗、不符則留在佇列並具名回報；description 逾 100 字元先擋下不送出 API；佇列檔不存在則具名回報並正常結束（exit 0）。
- `reconcile-queue.ps1`：對帳出列腳本，loop 開頭用。只對 GitHub 發 GET（不寫 GitHub），比對佇列與現況，已落地項自動出列並改寫本機佇列檔。
- `fixtures/queue.json`：三筆人造佇列項（`set-labels`／`close-issue`／`comment`），對應驗收①。`target.issue` 為佔位數字 `999`，**使用前務必改成使用者本機測試用的真實 issue 編號**（見 `fixtures/README.md`）。
- `fixtures/description-too-long.json`：description 145 字元（>100）的 `create-milestone` 佇列項，驗證守門邏輯。
- `check-t21.sh`：紅燈先行的靜態檢查（沙盒可跑）。`t21-red-green.txt`：紅→綠證據。

## ⚠️ 誠實聲明：紅→綠僅涵蓋靜態面

`check-t21.sh` 只檢查「腳本／規格文件是否含正確設計元素與具名條文」，**不能替代實跑冪等驗證**。Spec 驗收 ②（冪等）③（回驗）④（對帳出列）⑥（遺失降級）**必須由使用者在本機以真實 GitHub API 連線跑過才算數**——這正是本票（T-21）驗收條件寫「冪等與回驗只能實跑」的理由，也是本票本身依賴使用者本機 PowerShell 環境的原因。

## 待使用者本機執行的驗收步驟

前置：`git clone` 或直接把 `build/t21/` 整個資料夾複製到本機任一路徑；確認 `G:\default mount\station_command-key` 存在且內容為有效 fine-grained PAT（對 `glennisgood3-dev/station-command` 至少要有 Issues 的讀寫權限）。

### 步驟 0：準備測試 issue

在 `glennisgood3-dev/station-command` 開一張新 issue 當測試靶子（標題例如「T-21 驗收測試票」），記下編號 `<N>`。

### 驗收①：三筆佇列項套用後回驗相符

```powershell
cd <本機 t21 資料夾>
Copy-Item fixtures\queue.json queue.json
# 用編輯器把 queue.json 三筆的 "issue": 999 全部改成 <N>
.\apply-queue.ps1
```

預期：主控台三筆皆印 `APPLIED-VERIFIED`；到 GitHub 網頁確認該 issue 的 label 變成 `sc:ticket`＋`sc:awaiting-user`、狀態變 closed（`not_planned`）、且多了一則留言。`queue.json` 套用後應變成空陣列 `[]`（三筆皆出列）。

### 驗收②：冪等（同一佇列連續套用兩次）

```powershell
Copy-Item fixtures\queue.json queue.json  # 重置回三筆（issue 號記得再改一次 <N>）
.\apply-queue.ps1
.\apply-queue.ps1   # 立刻再跑一次
```

預期：第一次跑出 `APPLIED-VERIFIED` 三筆；第二次跑（此時 `queue.json` 已因第一次全部出列而是空陣列）應印「佇列檔存在但無任何待寫項目」。若想測試「佇列裡還留著已經被套用過的項目時重跑會不會重複寫」，可故意在第二次執行前**手動把已出列的三筆重新貼回 `queue.json`**再跑一次 `apply-queue.ps1`：預期三筆皆印 `SKIPPED-ALREADY-SATISFIED`（因為讀現況比對後發現已達成），GitHub 上不會出現第二則重複留言、label 不會重複寫入。

### 驗收③：回驗不符 ⇒ 留在佇列並具名回報

```powershell
Copy-Item fixtures\queue.json queue.json
# 把其中一筆的 issue 改成一個不存在的號碼（例如 999999），issue 號改回 <N> 的其餘兩筆保留
.\apply-queue.ps1
```

預期：該筆印 `FAILED-VERIFY`（或因目標不存在直接在套用階段丟例外 `FAILED-APPLY`，兩者皆屬「不符即留在佇列」的具名回報），`queue.json` 套用後仍留有這一筆；`apply-queue-report.txt` 具名列出該筆的 detail。

### 驗收④：對帳出列（使用者手動落地 → reconcile 自動出列）

```powershell
Copy-Item fixtures\queue.json queue.json  # issue 號改 <N>
# 先手動到 GitHub 網頁把其中一筆的效果做掉（例如手動幫 issue #<N> 貼上 sc:ticket + sc:awaiting-user 兩個 label）
.\reconcile-queue.ps1
```

預期：對應那筆印 `DEQUEUED-ALREADY-LANDED` 並從 `queue.json` 消失；其餘未落地的兩筆印 `KEPT-NOT-YET-LANDED` 並保留。全程 `reconcile-queue.ps1` 不應對 GitHub 發出任何 PUT/POST/PATCH（可用瀏覽器 Network 或 GitHub 稽核紀錄確認，或直接讀腳本原始碼確認只 dot-source 到 `Get-Current*` 系列 GET 函式）。

### 驗收⑤：產生權不變式（本票僅靜態驗證；動態驗證待 T-24）

打開 `enqueue-guard.md`，確認四類動作各自的唯一產生者已具名（`check-t21.sh` 已自動化此檢查，見 `t21-red-green.txt`）。**實際跑 `/station-run` 嘗試產生 label 類佇列項並觀察被拒**，屬 T-24 `/station-run` loop 落地後才能動態驗證——T-21 本身不含任何 skill 的執行邏輯，無法在本票範圍內產生「run 試圖越權」這個情境。

### 驗收⑥：遺失降級

```powershell
Remove-Item queue.json -ErrorAction SilentlyContinue
.\apply-queue.ps1
.\reconcile-queue.ps1
```

預期：兩支腳本皆印「待寫佇列不存在，本批動作將重新產生」並以 exit code 0 正常結束；到 GitHub 網頁確認 issue #<N> 的既有狀態（label／開關／留言）完全不受影響（因為兩支腳本此時直接 return，未曾嘗試讀寫）。

### description ≤100 字元守門驗證

```powershell
Copy-Item fixtures\description-too-long.json queue.json
# 若沒有 milestone 建立權限，可只觀察「是否在送出 API 前就被擋下」，不需要真的建立成功
.\apply-queue.ps1
```

預期：印 `FAILED-VALIDATION`，訊息具名指出哪個欄位、長度多少字元超過上限；**不應該**看到任何 GitHub API 呼叫被送出（若送出，145 字元的 description 應會收到 422，但本守門的設計目的正是不讓它送到那一步）。
