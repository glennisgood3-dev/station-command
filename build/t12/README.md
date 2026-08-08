# T-12 · 派工：選件、executor 寫入、開工訊號與失敗回滾

依 `Spec_station-command_v1.8.md` §2／§3.5／§4.1／§5.1／§5.3a，`tickets-draft.md` T-12（全文三條驗收），`tickets-loop-draft.md` 統一修正條款。**地基（直接重用，未重寫）**：`build/t21/`（四欄佇列格式、`queue-common.ps1`、`apply-queue.ps1`、`enqueue-guard.md`）、`build/t10/`（`gate-check.ps1` 的 `Get-CurrentStation`／`Get-TicketsForWork`）、`build/station-command/assets/routing-table.md`（T-11 交付的路由表，本檔逐字轉錄進 `run-common.ps1` 供程式引用）。

## 派工流程一句話

`/station-run` 讀 GitHub → 驗站別歸因（結構性）→ 三判準（無 blocker／depends_on 已滿足／尚無在跑 executor）過濾出 frontier → 依路由表 v1 定 executor＋basis（尊重票已宣告的第二層覆寫）→ 第八欄不可逆動作檢查 → 產生 `set-ticket-fields`／`set-assignee` 兩型佇列項 → 落地後由 Commander 實際 dispatch；dispatch 失敗立即產生「移除 assignee」佇列項並具名回報。

## 目錄結構

```
build/t12/
  station-run/SKILL.md      完整職責、白名單宣告、No-Hands 邊界、loop 介面位置
  run-common.ps1            共用函式庫：三判準、路由表、欄位解析、產生權守門、新兩型佇列邏輯
  run-select.ps1            選件器（只讀，不寫）
  run-dispatch.ps1          派工器（Dispatch／ReportFailure 兩模式）
  run-apply.ps1             set-assignee／set-ticket-fields 套用腳本（與 t21 共讀 queue.json）
  run-queue-ext.md          兩個新佇列動作型別的規格與產生權擴充表
  t12-offline-test.ps1      離線 mock 測試，62 項斷言，含兩段紅燈
  t12-test.ps1              動態紅→綠測試（需真實 PAT，本沙盒無法實跑）
  t12-quality-gates.txt     出貨前三道關卡證據
```

## 兩段紅燈設計

**①產生權守門**（`Test-RunProducerAllowed`／`Add-RunQueueItemGuarded`，`run-common.ps1`）：`-SkipEnqueueGuard` 開啟後，強制產生一筆 `set-labels` 佇列項 ⇒ 斷言「run 不得產生 label 類佇列項」**真的失敗**（佇列中真的出現 1 筆）；關閉後同一斷言通過（`Blocked=true`，具名「唯一產生者：gate」）。

**②失敗回滾**（`Invoke-DispatchFailureRollback`，`run-common.ps1`）：以**有狀態 mock GitHub**造出「assignee 已指派」的人造中間態 fixture，模擬 dispatch 隨後失敗。`-SkipRollback` 開啟後 ⇒ 斷言「回滾後 assignee 必為空」對著 mock **現況直接查詢**（非僅佇列存在性）**真的失敗**（assignee 依然殘留）；關閉後產生 `set-assignee(assignees=[])`，模擬套用（呼叫 `Invoke-SetAssigneeWrite` 寫進 mock）後，核心斷言通過（mock 現況 assignee 真的變空）。

兩段皆為**斷言失敗型**紅燈（非「檔案不存在」型），見 `t12-offline-test.ps1` 群組 F／H 與 `t12-quality-gates.txt`。

## 產生權怎麼在程式碼裡真的擋住

`run-common.ps1` 定義 `$Script:RunAllowedQueueActions = @('set-assignee', 'set-ticket-fields', 'comment')`。`Add-RunQueueItemGuarded` 是 **run 產生佇列項的唯一入口**——`run-select.ps1`／`run-dispatch.ps1` 全程不繞道直接呼叫底層的 `Add-RunQueueItemIfAbsent`。每次產生前先呼叫 `Test-RunProducerAllowed -Action`，動作類型不在白名單內 ⇒ **拒絕寫入佇列檔**（不是寫入後再擋，是產生階段就擋）並具名回報「唯一產生者」。`-SkipEnqueueGuard` 是唯一的繞道旗標，且僅供紅燈驗證使用（開啟時印出三行醒目警告）。

`set-labels`／`close-issue`／`create-issue`／`create-milestone` 恆不在 run 的允許清單內；`set-assignee`／`set-ticket-fields` 是本票引入的兩個新動作型別（`queue-format.md` 原五型未涵蓋 assignee 與票 body 欄位寫入），規格與產生權擴充見 `run-queue-ext.md`——**不修改** `build/t21/` 任何檔案，比照 T-22 `apply-patch` 型的共存模式（`run-apply.ps1` 與 `../t21/apply-queue.ps1` 共讀同一份 `queue.json`，只認自己的動作型別，其餘原樣通過）。

## 使用者本機驗證步驟

```powershell
cd <plugin repo>\build\t12

# 離線測試（沙盒／CI 皆可跑，不連網）
.\t12-offline-test.ps1

# 動態測試（需本機真實 PAT，會在指定 repo 建立並清理一張測試票）
.\t12-test.ps1 -Owner <owner> -Repo <repo>

# 實際派工（範例）
.\run-select.ps1 -WorkId W-demo -PrimaryRepo owner/repo -AnchorIssue 1 -ParticipatingRepos owner/repo
.\run-dispatch.ps1 -WorkId W-demo -PrimaryRepo owner/repo -AnchorIssue 1 -AssigneeLogin <your-login>
..\t21\apply-queue.ps1 -QueuePath .\queue.json    # 若佇列混有 metadata 型項目
.\run-apply.ps1 -QueuePath .\queue.json           # 落地 set-assignee／set-ticket-fields

# dispatch 失敗後的回滾
.\run-dispatch.ps1 -TargetRepo owner/repo -TargetIssue 42 -Reason 'sub-agent 逾時無回應' -WorkId W-demo
.\run-apply.ps1 -QueuePath .\queue.json
```

## 已知限制（誠實聲明，非規避）

- `depends_on` 依賴解析為 best-effort（比對票標題與 body 文字，非精確 ID 索引，查無對應票一律 fail-closed）——與 T-08 `create-issue` 冪等比對「best-effort，僅掃最近 100 筆」屬同一類已知限制。
- 站別歸因僅做結構性檢查（anchor 站別 label 是否恰為一個）；時間軸 actor 歸因依 ADR-NP-009 手動階段不生效，deferred-to-CI（重用 T-10 既有先例，不重複實作）。
- 各站專屬 gate 檢查（票八欄位完備性判定、紅綠證據判斷、雙審）不在本票範圍（T-13／T-14／T-15a）；loop 主體（選件→派工→收件→判 gate→續派的完整迴圈與**六條**停止條件，2026-08-08 由五條增為六條——新增⑥外廠累計成本達上限 100%）不在本票範圍（T-24），本票只交付「選件」與「單次派工」兩段可重用函式介面。此段文案由 T-24 一併更新（Commander 裁示：loop 文案歸 T-24）。
- `t12-test.ps1`（動態紅→綠，需真實 GitHub PAT）本沙盒無法連線實跑，已通過 ParseFile 語法檢查與人工覆核；核心邏輯的兩段紅燈已由 `t12-offline-test.ps1`（有狀態 mock，沙盒可 100% 實跑）完整證明。
