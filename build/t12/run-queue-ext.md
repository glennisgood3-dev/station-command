# T-12 · 佇列動作型別擴充（`set-assignee`／`set-ticket-fields`）

依 `Spec_station-command_v1.8.md` §4.6、`tickets-draft.md` T-12。**地基**：`build/t21/`（四欄佇列格式、`queue-common.ps1`、`apply-queue.ps1`、`enqueue-guard.md`）。

## 為何需要擴充（誠實聲明，非規避）

`queue-format.md` §3 定義的原五型動作（`set-labels`／`close-issue`／`comment`／`create-issue`／`create-milestone`）**沒有涵蓋** §4.6 產生權表明文列出的「assignee 與留言由 run 產生」中的 **assignee** 一類——T-21 交付時 run 尚未實作，這塊留白直到本票才補齊。同理，run 白名單「寫票 body 的 executor／basis 欄位」也沒有對應的通用「改 issue body」動作型別。

**依 file ownership 邊界，本票不修改** `build/t21/queue-format.md`／`queue-common.ps1`／`apply-queue.ps1`／`enqueue-guard.md`。做法比照 **T-22 `apply-patch` 型的先例**（見 `build/t22/patch-format.md` §1、`build/t22/README.md`）：另立套用腳本（本目錄 `run-apply.ps1`），與 `../t21/apply-queue.ps1` **共讀同一份 `queue.json`**，只認自己的動作型別，其餘項目原樣通過、不觸碰、不重排。使用者若同一份佇列混有多型項目，建議順序：`run-apply.ps1` → `../t21/apply-queue.ps1`（純粹避免噪音，理由同 T-22 README；順序顛倒不會遺失或誤套，只是對方會印一行 schema 不符的噪音後跳過）。

## 兩個新動作型別

### `set-assignee`

用途：對單一 issue（票或 anchor）設定**完整**的 assignee login 集合，作為 §2「二元開工訊號」的寫入端；`payload.assignees = []` 即移除全部 assignee（**失敗回滾的手段**：run-dispatch.ps1 的 `Invoke-DispatchFailureRollback` 就是產生這一型的空陣列版本）。

```json
{
  "action": "set-assignee",
  "target": { "repo": "owner/repo", "issue": 42 },
  "payload": { "assignees": ["glennisgood3-dev"] },
  "source": "W-demo-work"
}
```

- `target.repo`／`target.issue`：必填，同 `set-labels`。
- `payload.assignees`：**該 issue 套用後應有的完整 assignee login 陣列**（不是差量）；空陣列 = 移除全部 assignee。
- 套用端點：`PATCH /repos/{owner}/{repo}/issues/{issue_number}`，body `{"assignees": [...]}`（GitHub Issues API 原生支援此欄位於同一端點，不需另開 assignees 專屬端點）。
- 冪等比對：讀現有 `issue.assignees[].login`，排序後與 `payload.assignees` 排序後比對，集合相等 ⇒ 已達成，跳過（比照 `set-labels` 的比對邏輯，見 `queue-common.ps1` `Test-ItemSatisfied` 的 `set-labels` 分支）。

### `set-ticket-fields`

用途：覆寫單一 issue（票或 anchor，站 1-3 尚無票時目標即 anchor 本身，見下方「anchor 作為目標」）的 body **完整內容**，供 run 寫入 executor／basis 欄位使用（§5.1 第二層覆寫：若票已自帶 executor/basis，不產生本型項目）。

```json
{
  "action": "set-ticket-fields",
  "target": { "repo": "owner/repo", "issue": 42 },
  "payload": { "body": "<完整的新 body 內容，含既有內容 + 附加的 executor/basis 區塊>" },
  "source": "W-demo-work"
}
```

- `payload.body`：**完整期望的 body 內容**（覆蓋式，非差量 diff）——與 `set-labels` 的「完整集合」哲學一致：套用端只需整段覆寫，不需理解原內容結構。產生端（`run-common.ps1` 的 `New-BodyWithExecutorBasis`）以「原 body ＋ 附加一段標明來源的 `executor:`/`basis:` 區塊」組出完整內容。
- 套用端點：`PATCH /repos/{owner}/{repo}/issues/{issue_number}`，body `{"body": "..."}`。
- 冪等比對：讀現有 `issue.body`，換行正規化後（沿用 `../t21/queue-common.ps1` 的 `ConvertTo-NormalizedText`，理由同 T-21 comment 型的 CRLF/LF 正規化考量）與 `payload.body` 正規化後逐字比對，相等 ⇒ 已達成，跳過。

### anchor 作為目標（§3.2）

站 1／2／3「尚無票」時，`target.issue` 直接填 **primary anchor 的 issue number**（不是虛構的票號）——這是 Spec §3.2「站 1／2／3（尚無票）：可動作項＝work 本身，開工訊號與時間軸落 primary anchor」的直接體現：本兩型動作的 payload／套用／冪等邏輯完全不分「這是票還是 anchor」，兩者都只是一個 issue number，寫入端點相同。

## 產生權擴充（延伸 `../t21/enqueue-guard.md` 的表，不修改原檔）

| 佇列動作類型 | 唯一產生者 | 對應 §3.3／§2 白名單依據 |
|---|---|---|
| `set-assignee` | **`/station-run`** | §4.6「assignee 與留言由 run 產生」；§2 run 白名單「寫／移除 assignee」 |
| `set-ticket-fields` | **`/station-run`** | §2 run 白名單「寫票 body 的 executor／basis 欄位」 |

**run 的完整產生權範圍（本票新增後）**：`set-assignee`／`set-ticket-fields`／`comment`（`comment` 沿用 t21 原五型之一，見 `enqueue-guard.md` §2「依原動作歸屬」）。`set-labels`／`close-issue`／`create-issue`／`create-milestone` **恆不在此列**，run 一律拒絕產生（`../t21/enqueue-guard.md` §1 原表已明文「set-labels 與 close-issue 兩型恆為 gate 專屬」；`create-issue`／`create-milestone` 恆為 intake 專屬）。

**強制點**：`run-common.ps1` 的 `Test-RunProducerAllowed` ＋ `Add-RunQueueItemGuarded`（run 產生佇列項的**唯一入口**，run-select.ps1／run-dispatch.ps1 全程不繞道直接呼叫 `Add-RunQueueItemIfAbsent`）。違反時的判定行為比照 `enqueue-guard.md` §3：**拒絕**（不得寫入佇列檔）＋ **具名回報**（`Test-RunProducerAllowed` 的 `Detail` 字串具名動作類型與唯一產生者）＋ **不得降級處理**（不得把該動作偷改成 `comment` 繞過）。`-SkipEnqueueGuard` 旗標**僅供紅燈驗證**繞過本檢查，正式流程與一般手動執行絕對不得使用（見 `t12-offline-test.ps1` 段落 F 的紅／綠對照）。

## 與 T-21／T-22 的操作順序建議

若 `queue.json` 同時混有 metadata 型（T-21）、`apply-patch` 型（T-22）、本票兩型項目，建議順序：**先 `run-apply.ps1`，再 `../t22/apply-patch.ps1`，最後 `../t21/apply-queue.ps1`**（順序間本身不影響正確性，各腳本互相 pass-through 不認得的型別；此建議純粹避免中間輸出噪音）。
