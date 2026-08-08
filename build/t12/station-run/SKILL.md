---
name: station-run
description: 驗站別歸因合法後選出下一個可動作項，依路由表定 executor 與 basis 並寫入票（或 anchor）body 的 executor 欄位，指派 assignee 作二元開工訊號，dispatch 執行；失敗立即移除 assignee 並具名回報。當使用者要求「派工」「下一步做什麼」「/station-run」「開工」等語意時觸發。
user-invocable: true
---

# 動作白名單（Spec §2 v1.8，逐字承接）

`/station-run`：驗站別歸因合法（§3.4）→ 選出下一個可動作項，依路由表定 executor＋basis 並**寫入票 body 的 executor 欄位** → dispatch；**以指派 assignee 作為二元開工訊號**；dispatch 失敗 ⇒ **立即移除該 assignee** 並具名回報；結束時呼叫面板無對帳刷新。

允許動作：讀 GitHub｜**寫／移除 assignee**｜**寫票 body 的 executor／basis 欄位**｜寫人讀留言｜dispatch sub-agent｜**呼叫 gate**（判 gate 與產生 label 類佇列項——由 gate 自己產生，不是 run）｜**寫自己權責內的佇列項（assignee、留言）**｜呼叫 board 無對帳模式。

🚫 **明文禁令**：本 skill 不寫任何 label（含狀態 label `sc:station-*`／`sc:legacy`／`sc:red-proven`／`sc:blocked`／`sc:gate-fail`／`sc:awaiting-user` 與類型 label）、不開關任何 issue／milestone、**不產生 label 類佇列項**（強制點見下）。狀態 label 的唯一寫入者是 `/station-gate`（SC#7）。

# 手動階段的寫入路徑（依 ADR-NP-009／Spec §4.6）

本 skill 於執行期**不直接寫 GitHub**（`SC-DEC-BOT-001` 已實測：MCP 寫入端點 403、Bash 對 GitHub 被 proxy 攔截，讀取端點正常）。所有寫入一律先產生佇列項，追加進使用者本機佇列檔，明確告知使用者需執行套用腳本落地：

- **assignee／票 body executor-basis 欄位**：本票新增的兩個動作型別 `set-assignee`／`set-ticket-fields`（規格見 `../run-queue-ext.md`），由 `../run-apply.ps1` 套用（與 `../../t21/apply-queue.ps1` 共讀同一份 `queue.json`，比照 T-22 `apply-patch` 型的共存模式，不修改 T-21 原始檔案）。
- **留言**：沿用 T-21 原生 `comment` 型，由 `../../t21/apply-queue.ps1` 套用。

**產生權不變式**（`../run-queue-ext.md` ＋ `../../t21/enqueue-guard.md`）：run 只得產生 `set-assignee`／`set-ticket-fields`／`comment` 三型；`set-labels`／`close-issue`／`create-issue`／`create-milestone` 恆不得由 run 產生。**強制點在程式碼**（`run-common.ps1` 的 `Add-RunQueueItemGuarded`，run 產生佇列項的唯一入口），不是只寫在文件——見 `../t12-offline-test.ps1` 段落 F 的紅／綠對照證明此檢查真的擋得住。

# 執行步驟

## 段落一：選件（`../run-select.ps1`，本票交付，只讀不寫）

1. 讀 primary anchor，以 `Get-CurrentStation`（重用 T-10 地基）做站別歸因的結構性檢查——anchor 站別 label 不恰為一個（0 個或多個）⇒ **拒絕選件**，具名回報，提示先跑 gate 復位模式。**時間軸 actor 歸因**（誰改的 label）依 ADR-NP-009 手動階段不生效，不在本檢查範圍（留給 gate 復位模式，T-10 範圍）。
2. 依現站決定候選項集合：站 1／2／3（尚無票，§3.2）⇒ 候選＝anchor 本身；站 4／5 ⇒ 候選＝該 work 名下 `sc:ticket`，且**排除已有 `sc:red-proven` 的票**（那些等待站 5 雙審，dispatch 屬 gate 職責，不是 run）。
3. 對每個候選項套**三判準**（§5.3a，本票只做單次選件，loop 主體是 T-24——本步驟即 T-24 未來每輪呼叫的「選件」介面）：① 無未解 blocker（含跨站繼承：anchor 有 `sc:blocked` 則名下票一併視為 blocked）；② `depends_on` 已滿足（best-effort 比對票標題／body 文字，查無對應票視為未滿足，fail-closed，誠實聲明限制）；③ 尚無在跑 executor（candidate 的 `assignees` 為空）。三者皆滿足 ⇒ 進 frontier；frontier 內取編號最小者為選中項。
4. 依路由表 v1（`../../station-command/assets/routing-table.md`）定 executor＋basis 預設值；若票（或 anchor）body 已宣告 `executor:`（第二層覆寫，§5.1）⇒ 讀取該宣告作為有效值，缺 `basis:` 則判 `[INVALID]`，該項目不得被派工（需使用者裁示）。

## 段落二：派工（`../run-dispatch.ps1`，本票交付）

1. 重跑同一套選件邏輯（不重複維護第二份判準）取得選中項。
2. `[INVALID]`（缺 basis）⇒ 拒絕，不產生任何佇列項，回報需使用者裁示。
3. **第八欄不可逆動作檢查**（§3.5，dispatch 前讀取）：票 body 宣告「不可逆動作：有」⇒ **dispatch 前停手**，不產生任何佇列項，具名回報，交使用者裁示（§5.3a 停止條件①）。⚠️ 本機制只攔得住**票級事前宣告**的不可逆動作；dispatch 之後 executor 內部自行觸發的不可逆動作不在本機制涵蓋範圍。
4. 需要時產生 `set-ticket-fields` 佇列項（寫入 executor／basis，僅當票 body 原本未宣告時）；產生 `set-assignee` 佇列項（`assignees=[執行身分帳號]`，二元開工訊號）。兩者皆經 `Add-RunQueueItemGuarded` 產生權自查。
5. 輸出「佇列已就緒」報告，指示使用者執行 `../run-apply.ps1`（連同 `../../t21/apply-queue.ps1`）落地。**落地後，由 Commander（主 session）實際 dispatch 該 executor**——這一步是 Claude 呼叫 sub-agent 的動作，不是 PowerShell 腳本能做的事，本 skill 的 .ps1 只負責選件與寫入前置動作。
6. **dispatch 失敗**（Commander 實際呼叫 sub-agent 後回報失敗，例如逾時、拒絕、ak CLI 不可用）⇒ 立即呼叫 `run-dispatch.ps1 -TargetRepo -TargetIssue -Reason`（`ReportFailure` 模式）：產生 `set-assignee`（`assignees=[]`）佇列項移除該 assignee，並具名回報失敗原因。不留下「已開工但沒人在做」的假象。

## 段落三：結束（本票不實作，僅留介面）

- **呼叫 board 無對帳模式刷新**：屬 Commander 在 skill 執行完畢後的收尾動作（呼叫 `/station-board` 的無對帳模式），本票不在 .ps1 內實作（那是跨 skill 呼叫，發生在 Claude 對話層，非 PowerShell 腳本層）。
- **呼叫 gate**：v1.8 新增的白名單項，供收件後判 gate 是否可推進站別。**本票 scope 不含收件與判 gate**（🔒 單次派工不含這段，屬 T-24 loop 主體「收件 → 判 gate → 續派」的職責），此處只留白名單宣告與介面位置。

# No-Hands 邊界（§5.0）

本 skill 的動作（讀 GitHub、驗歸因、選件、依路由表定 executor、寫 assignee／body 欄位、產生佇列項）皆由既有資料機械性推導而得、無創作裁量，屬編排動作，不受 No-Hands 管轄。**票內容、程式、測試等 deliverable 一律由 dispatch 出去的 executor 產出，主 session 不親手撰寫**——`New-BodyWithExecutorBasis` 只附加固定格式的 `executor:`/`basis:` 兩行（機械性欄位寫入，非內容創作），不涉及撰寫票的實質內容（那是站 3 dispatch `planner` 的職責，T-13 範圍）。

# loop 模式的位置（v1.8 §5.3a，手動階段生效；本票只做單次派工）

**本票 scope 明定為單次派工**：選件、寫欄位、開工訊號、dispatch、失敗回滾。`Select-NextActionableItem`（`../run-common.ps1`）已完整實作三判準過濾，是 T-24 loop 主體「持續選件 → 派工 → 收件 → 判 gate → 續派」中「選件」這一步的**現成介面**，T-24 直接呼叫本票交付的函式即可，不需重新實作三判準。loop 的**六條**停止條件（2026-08-08 由五條增為六條——新增⑥外廠累計成本達上限 100%）、收件與判 gate、續派迴圈、停因通知與批次摘要，一律不在本票範圍（T-24／T-25）。此段文案由 T-24 一併更新（Commander 裁示：loop 文案歸 T-24）。

# 已知限制（誠實聲明，非規避）

- `depends_on` 依賴解析為 best-effort（比對票標題與 body 文字，非精確 ID 索引）；查無對應票一律視為未滿足（fail-closed），見 `run-common.ps1` `Test-DependsOnSatisfied` 的 `Unresolved` 欄位。
- 站別歸因僅做結構性檢查（anchor 是否恰有一個站別 label）；時間軸 actor 歸因依 ADR-NP-009 手動階段不生效，deferred-to-CI（同 T-10 既有先例）。
- 各站專屬 gate 檢查（票八欄位完備性判定、紅綠證據判斷、雙審）不在本票範圍（T-13／T-14／T-15a）。
