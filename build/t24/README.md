# T-24 · session 內 loop 主體（選件三判準＋六條停止條件）

依 `tickets-loop-draft.md` T-24（第 39 行起）與 `Spec_station-command_v1.11.md` §5.3a（loop 主體、選件三判準、停止條件窮舉六條）、§3.5 第八欄（不可逆動作宣告）、§2 `/station-run` 權限邊界、§4.6（待寫佇列）實作。**地基（直接重用，未重寫）**：`build/t12/`（`Select-NextActionableItem` 三判準過濾、`Invoke-RunDispatch` 單次派工含第八欄檢查、`Add-RunQueueItemGuarded` 產生權守門）、`build/t10/`（`Get-CurrentStation`）、`build/t21/`（佇列讀寫工具）。

## loop 一句話

`/station-run` 進入 loop：每輪讀 GitHub 現況（不落任何狀態檔）→ 依現站分「人類 gate（站 1/2/3，一輪即停）」與「自主（站 4/5，持續跑）」→ 自主段套三判準選件 → dispatch 前查第八欄 → 派工 → 呼叫外部「收件→判 gate」→ 依結果續派／rework／停手，直到六條停止條件之一成立。

## 交付檔清單

```
build/t24/
  run-loop.ps1              loop 主體（Invoke-StationRunLoop）＋ 停止條件判定函式 ＋ CLI（DemoMode／Real 單輪決策）
  t24-offline-test.ps1      離線 mock 測試，58 項斷言，含兩段紅燈（群組 F、G）
  t24-offline-test-report.txt   最近一次實跑報告（58 項，FAIL=0）
  README.md                 本檔
```

## ① 驗收條件逐條對應

票面驗收條件（① ~ ⑦，`tickets-loop-draft.md` T-24）：

| 驗收 | 內容 | 對應測試 | 結果 |
|---|---|---|---|
| ① | 選件三判準：四張人造票只第四張進 frontier | `t24-offline-test.ps1` 群組 F（含紅燈） | PASS（F-GREEN） |
| ② | 停因⑤：frontier 空 ⇒ 具名 | 群組 J（獨立情境）、群組 F-GREEN／M 的收斂結果 | PASS |
| ③ | 停因①：第八欄「不可逆：有」⇒ dispatch 前停手 | 群組 G（含紅燈） | PASS（G-GREEN） |
| ④ | 停因②：同票 rework 2 次仍 fail | 群組 H | PASS |
| ⑤ | 停因③：站 1/2/3 不自動推進 | 群組 I | PASS |
| ⑥ | 站 4/5 全程未出現確認提問 | 群組 M（機械化掃描，見下方④） | PASS |
| ⑦ | 停因⑥：成本破 100% 停手、已產出結果照常輸出 | 群組 L | PASS |

另補：群組 K（停因④ scope 需變更）、群組 N（run 產生權邊界）、群組 O（六條窮舉具名文字與通知範圍）、群組 A~E（各純函式單元測試）。**58 項全部 PASS**（含 2 段刻意設計為「真的失敗一次」的紅燈存證，見下）。

## ② 紅燈兩條斷言原文與「真的失敗」的證據摘要

依票面「先寫①（三判準過濾）與③（不可逆前停手）兩條斷言」：

**紅燈①（群組 F）**——斷言原文：「loop 只會派工 frontier 內合格票（不含 #201 blocked／#202 depends_on 未滿足／#203 已在跑）」。開 `-SkipFrontierFilter`（選件池改用 Eligible＋Rejected 全體，忽略三判準）後**真的失敗**：

```
[RED-CONFIRMED] 斷言「loop 只會派工 frontier 內合格票」如預期失敗：-SkipFrontierFilter 開啟後，
佇列中真的出現了對 #201（有 sc:blocked，本應被三判準拒絕）的 set-assignee 派工項（共 1 筆）。
```

關閉開關後同一斷言（`F-GREEN`）通過：只派工過 `#204`，`#201/#202/#203` 從未進佇列。

**紅燈③（群組 G）**——斷言原文：「宣告『不可逆動作：有』的票，dispatch 前必被攔下、loop 必以停因①停手」。開 `-SkipIrreversibleHalt`（繞過 t12 `Invoke-RunDispatch` 內建第八欄檢查，直接產生 `set-assignee`）後**真的失敗**：

```
[RED-CONFIRMED] 斷言「dispatch 前必先查第八欄」如預期失敗：-SkipIrreversibleHalt 開啟後，佇列中
真的出現了對 #301（宣告『不可逆動作：有』）的 set-assignee 派工項，且 loop 沒有以停因①停手
（實際 StopReason=⑤）。
```

關閉開關後同一斷言（`G-GREEN`）通過：佇列檔未產生任何內容，`StopReason=①`。

兩段紅燈皆為**斷言失敗型**（真的產生了不該有的佇列項/未停手），非「檔案不存在」或「語法錯誤」型。兩個開關（`-SkipFrontierFilter`／`-SkipIrreversibleHalt`）在 `run-loop.ps1` 的 doc comment 與函式內 `Write-Warning` 皆具名標「⚠️ 僅供紅燈驗證使用，正式流程絕對不得開啟」，`Get-LoopCandidatePool`／`Invoke-LoopNaiveDispatchIgnoringIrreversible` 兩個輔助函式的存在理由也僅此一項。

## ③ 驗收⑥「未出現確認提問」的機械化驗法

`Test-NoConfirmationPrompts`（`run-loop.ps1`）掃描 loop 全程輸出行（`Invoke-StationRunLoop` 回傳的 `Lines`），命中下列任一樣式即判「有確認提問」：`是否確認`／`請(您/使用者)確認`／`需要確認`／`confirm?`／`proceed?`／`continue?`／`y/n`／`yes/no`／`請問是否`／`要繼續嗎`／`OK嗎`／`同意嗎`／`是否同意`。

`t24-offline-test.ps1` 群組 M 構造一個涵蓋 dispatch／gate 判定（含一次 rework，模擬「驗收」重跑）／PASS 收斂（模擬雙審與 merge 判準全過）的多輪站 4/5 情境，對整段輸出跑 `Test-NoConfirmationPrompts`，斷言 `Clean=true`。**掃描器並非恆真**：群組 M 額外對同一段輸出手動附加一行違規文字（`請確認是否繼續派工？`）重新掃描，斷言必為 `Clean=false`，證明掃描器真的會抓到違規、不是永遠回真的空殼檢查（群組 C 也單獨驗證掃描器對中英文樣式皆命中）。

## ④ t12 兩行文案改前改後

Commander 裁示「loop 文案本就歸 T-24，由本票一併更新」，本票唯一被授權寫入 `build/t12/` 的兩行：

**`build/t12/README.md:64`**
- 改前：`...loop 主體（選件→派工→收件→判 gate→續派的完整迴圈與五條停止條件）不在本票範圍（T-24）...`
- 改後：`...loop 主體（選件→派工→收件→判 gate→續派的完整迴圈與**六條**停止條件，2026-08-08 由五條增為六條——新增⑥外廠累計成本達上限 100%）不在本票範圍（T-24）...此段文案由 T-24 一併更新（Commander 裁示：loop 文案歸 T-24）。`

**`build/t12/station-run/SKILL.md:53`**
- 改前：`...loop 的五條停止條件、收件與判 gate、續派迴圈、停因通知與批次摘要，一律不在本票範圍（T-24／T-25）。`
- 改後：`...loop 的**六條**停止條件（2026-08-08 由五條增為六條——新增⑥外廠累計成本達上限 100%）、收件與判 gate、續派迴圈、停因通知與批次摘要，一律不在本票範圍（T-24／T-25）。此段文案由 T-24 一併更新（Commander 裁示：loop 文案歸 T-24）。`

除這兩行外未動 `build/t12/` 任何其他內容（已用 `grep 五條停止條件` 確認全庫僅這兩處，皆已修正；未觸碰 `run-common.ps1`／`run-select.ps1`／`run-dispatch.ps1`／`run-apply.ps1`／`run-queue-ext.md`／`t12-offline-test.ps1`／`t12-test.ps1`）。

## ⑤ 六條停止條件的落地位置（窮舉，不自立第七條）

| 條 | 判定函式／位置 | 通知範圍（本票只讓可讀，通知實作屬 T-25） |
|---|---|---|
| ① 不可逆動作前 | 重用 t12 `Invoke-RunDispatch`（讀 `Get-IrreversibleDeclaration`），loop 收到 `Status=irreversible-stop` 即整迴圈 halt | 安靜 |
| ② rework 2 次仍 fail | `Test-ReworkStopCondition`（純函式），計數存於 `Invoke-StationRunLoop` 迴圈本地 `$reworkCounts` | 推播 |
| ③ 站 1/2/3 人類 gate | `Get-LoopStationKind` 分類，`human-gate` 恰跑一輪後強制停 | 推播 |
| ④ scope 需變更 | `GateResultProvider` 回傳 `ScopeChangeNeeded=$true` | 推播 |
| ⑤ frontier 空 | `Select-NextActionableItem.HasCandidate=$false` 或 `Get-LoopCandidatePool` 排空 | 安靜 |
| ⑥ 外廠成本達上限 100% | `Test-CostLimitState`（讀 `-CostStatePath` JSON，schema：`{workId,percentUsed,limitType,provider}`），每輪開頭先查 | 推播 |

`Get-StopReasonText -Reason '⑦'` 會直接拋錯（見群組 O），六條為窮舉正典，本票未新增第七條，也未把六條之一拆成兩條。

## 權限邊界

沿用 t12 的 `Add-RunQueueItemGuarded`（`run 只准產生 set-assignee／set-ticket-fields／comment`），loop 全程不繞道呼叫底層 `Add-RunQueueItemIfAbsent`。群組 N 彙整本測試檔跑過的**所有**情境（F/G/H/I/K/L/L4/M）產生的佇列項（共 9 筆），逐筆斷言 `action` 只落在 `{set-assignee, set-ticket-fields}`，從未出現 `set-labels`／`close-issue`／`create-issue`／`create-milestone`，且彙整筆數 > 0（避免空集合恆真）。

## PS 5.1／StrictMode 陷阱（本票實跑抓到，非票面複製）

1. **陣列 `.Count`／`return ,@()` 雙重包裝**：`Get-LoopCandidatePool` 內部以 `return ,@($pool)` 保護陣列型別；呼叫端若直接 `@(Get-LoopCandidatePool ...)` 會把已保護好的陣列再包一層（3 筆變成「1 筆內容為 3 筆的巢狀陣列」，實跑重現）。修法：一律先賦值給變數再對已賦值變數包 `@()`（本檔與離線測試全面套用，含既有的 `ConvertTo-SafeArray`／`Read-QueueFile` 呼叫點）。
2. **`Where-Object` 單一命中結果無 `.Count`**：離線測試多處 `(... | Where-Object {...}).Count` 在命中 1 筆時被解卷成純量，StrictMode 下拋錯；修法一律先 `@(...)` 包裹整段管線結果再取 `.Count`。
3. **`[Parameter(Mandatory)][string[]]` 對陣列內空字串元素的隱性檢查**（實跑抓到、非票面既有清單）：`Test-NoConfirmationPrompts` 的 `OutputLines` 若含空白分隔行（`Invoke-RunDispatch` 慣例會在 `Lines` 中插入 `""` 分段），Mandatory 參數綁定對 `[string[]]` 會逐元素檢查非空字串，命中空字串元素即整體綁定失敗（錯誤訊息「it is an empty string」易誤導成「整個參數是空字串」）。修法：加 `[AllowEmptyString()]`（與既有的 `[AllowEmptyCollection()]` 並用）。已用 `/opt/pwsh/pwsh` 縮小重現（`@("a","","b")` 直接觸發）並記錄於 `run-loop.ps1` 函式註解。

## ⚠️ 本票實跑抓到的第三個變數 cascade 陷阱（票面明確警示的那一類，且不只 `$ScriptDir`）

票面提醒「避免 `$ScriptDir`／`$FunctionsOnly` 這類同名變數被 cascade 覆蓋」——**本票實跑證實這句話字面成真，且波及範圍比 `$ScriptDir`／`$FunctionsOnly` 更廣**：

- `run-common.ps1` 內部以 `. $Script:GateCheckPath -FunctionsOnly` dot-source `../t10/gate-check.ps1`，該檔自己的 `param()` 也宣告 `$FunctionsOnly`（供它自己的 CLI 綁定）。dot-source 共用同一層作用域，t10 那次呼叫把 `$FunctionsOnly` 重新綁定為 `$true`，**覆蓋掉 `run-loop.ps1` 自己收到的 `-FunctionsOnly` 參數值**——即使使用者呼叫 `run-loop.ps1` 完全沒帶 `-FunctionsOnly`，dot-source 結束後 `$FunctionsOnly` 仍被悄悄改成 `$true`，導致 CLI 主流程判斷 `if (-not $FunctionsOnly)` 恆假、**整支 CLI 悄悄變成 no-op**（症狀與票面描述完全一致：不報錯、離線測試也測不出來，因為離線測試本就用 `-FunctionsOnly` dot-source，不會經過這段 CLI 判斷）。
- 同一機制還波及 `$WorkId`／`$PrimaryRepo`／`$AnchorIssue`／`$ParticipatingRepos`／`$PatPath`（`gate-check.ps1` 的 `param()` 也宣告同名參數）：dot-source 完成後這些變數會被 t10 的參數預設值（空字串／0／空陣列）蓋掉，即使呼叫 `run-loop.ps1` 時明明帶了真實值，Real CLI 模式仍會誤判「未提供必要參數」。

**這兩個問題都是本票直接跑 CLI smoke test（見下）才抓到**——`t24-offline-test.ps1`（全程 `-FunctionsOnly` dot-source）完全測不出來，證實票面「其中一次讓 CLI 悄悄 no-op 而離線測試測不出來」的警示不是舊聞、是本票自己又踩了一次同型坑。**修法**：在任何 dot-source 之前，把本檔自己收到的每個參數值另存一份獨有變數名（`$T24Dir`／`$T24FunctionsOnlyRequested`／`$T24WorkId`／`$T24PrimaryRepo`／`$T24AnchorIssue`／`$T24ParticipatingRepos`／`$T24AssigneeLogin`／`$T24PatPath`／`$T24QueuePath`／`$T24CostStatePath`），CLI 函式與結尾判斷一律讀這些獨有變數，不再讀會被下游覆蓋的原參數名。修法過程與判準記錄於 `run-loop.ps1` 對應行的行內註解。

## ⑥ 三道自檢數字 ＋ CLI smoke test 結果

1. **`ParseFile`**（`/opt/pwsh/pwsh`）：`run-loop.ps1`、`t24-offline-test.ps1` 皆 `PARSE OK`（零語法錯誤）。
2. **離線測試**：`/opt/pwsh/pwsh -NoProfile -File t24-offline-test.ps1` ⇒ **共 58 項，FAIL=0**（含 2 段 RED-CONFIRMED 紅燈存證，不計入 FAIL，符合 t12/t13/t14 既有慣例：紅燈段落刻意不走 `Assert-True`，而是斷言「真的失敗」本身才是通過條件）。
3. **CLI smoke test**（直接執行，證明非 no-op，見上一節背景）：
   - `run-loop.ps1 -DemoMode`：全程不連網、不需 PAT，印出 `T24Dir=/home/claude/station-plugin/build/t24`（確認路徑解析指向本檔自己的目錄，非 t10/t12）並實際跑過 `Get-LoopStationKind`／`Test-CostLimitState`／`Test-ReworkStopCondition`／`Test-NoConfirmationPrompts`／`Select-NextActionableItem`／`Invoke-RunDispatch`（真的寫出一份 2 筆的 demo 佇列並在結束後清空），exit 0。
   - `run-loop.ps1 -WorkId W-smoke -PrimaryRepo o/r -AnchorIssue 1 -PatPath /nonexistent/pat-file`：**修法前**曾誤報「直接執行模式須提供 -WorkId -PrimaryRepo -AnchorIssue」（即使三者都帶了值，證實變數被下游覆蓋）；**修法後**正確通過參數檢查、正確往下執行到 `Read-PatToken`，並以預期中的「PAT 檔案不存在：/nonexistent/pat-file」報錯收場——錯誤訊息落在**預期的那一行**（`t21/queue-common.ps1:37`），證明 CLI 真的執行到底層讀檔那一步，不是安靜地在參數檢查就 no-op。

## 已知限制（誠實聲明，非規避）

- **真實 sub-agent dispatch 與判 gate 不可能在 PowerShell 內完成**（比照 t12 既有聲明）：`Invoke-StationRunLoop` 的「收件 → 判 gate」段以 `-GateResultProvider` scriptblock 抽象化，本票離線測試與未來 CI 自動化（§7.5／T-26）可注入模擬或真實呼叫的 provider；目前手動階段真實 session 由 Commander 在對話層扮演這個角色，逐輪讀本檔暴露的純函式做決策，等同於手動展開 `Invoke-StationRunLoop` 內部同一套邏輯的其中一輪（README「loop 一句話」節已具名此對應關係）。
- **CLI 的 Real 模式僅做單輪決策**，不是真正跑滿全程的多輪自動迴圈（原因同上，PowerShell 無法自行等待/呼叫外部 dispatch 結果）；完整多輪迴圈的正確性由 `Invoke-StationRunLoop`（`t24-offline-test.ps1` 全部覆蓋）擔保。
- **停因⑥的逐次記帳本身不在本票範圍**（T-29）：`Test-CostLimitState` 只定義讀取 schema 與 50%/80%/100% 三段判定，檔案不存在時容忍降級為 0%（不誤觸發停手），寫入方由 T-29 負責；本票已在群組 B／L 完整測試讀取端行為。
- **`build/t12/` 存在與本票相同類型的 cascade 變數陷阱、未在本票範圍內修復**（誠實聲明，非我方職責）：t12 的 `run-select.ps1`／`run-dispatch.ps1` 同樣宣告 `-WorkId`／`-PrimaryRepo`／`-AnchorIssue` 等參數，且同樣 dot-source 會 cascade 進 `gate-check.ps1` 的同名參數——本票在自己的 `run-loop.ps1` 上實測重現了這個機制（見上節），高度懷疑 t12 的 Real CLI 模式（非 `-FunctionsOnly`）存在同型風險，但 t12 的動態測試本就因「本沙盒無法連線實跑」而未曾以真實參數值跑過 CLI 這一段（`t12/README.md` 已知限制自陳）。**本票僅在自己的交付檔內修復，不觸碰 `build/t12/` 除已授權兩行外的任何內容**，此發現留供後續票或使用者自行判斷是否需要回頭修 t12。
