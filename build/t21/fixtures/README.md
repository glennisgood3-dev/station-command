# fixtures — T-21 驗收用人造佇列項

`queue.json` 內含三筆人造佇列項，對應 Spec 驗收①「造三筆佇列項（label 集合／開關 issue／留言）」：

1. `T-21-fixture-1`：`set-labels` — 對 issue #999 設定 `["sc:ticket", "sc:awaiting-user"]`。
2. `T-21-fixture-2`：`close-issue` — 關閉 issue #999，`state_reason: not_planned`。
3. `T-21-fixture-3`：`comment` — 對 issue #999 貼一則驗收留言。

## ⚠️ 使用前必改：`issue: 999` 是佔位數字

**不要對真正的生產票（T-08～T-26 任一張）直接套用本 fixture**——`999` 只是佔位，避免本檔誤動到真實 issue。使用者在本機驗收前，請：

1. 在 `glennisgood3-dev/station-command`（或任一測試用 repo）**另開一張專供測試的 issue**（例如標題「T-21 驗收測試票（可隨時關閉）」）。
2. 把 `queue.json` 三筆項目的 `target.issue` 全部改成該測試 issue 的實際編號。
3. 複製 `queue.json` 到 `apply-queue.ps1` 同目錄（或用 `-QueuePath` 指到本檔），再依 `../README.md`（或本回報訊息末段）的驗收步驟操作。

## 獨立預期值來源（供回驗比對）

- fixture-1 套用後預期：該 issue 的 label 集合 = `{sc:ticket, sc:awaiting-user}`（不多不少）。
- fixture-2 套用後預期：該 issue `state = closed`、`state_reason = not_planned`。
- fixture-3 套用後預期：該 issue 的留言列表中存在一則 `body` 完全等於 `"T-21 fixture：驗收用留言，套用後應可在 issue #999 讀到本則文字。"`（若已改過 issue 號，文字本身不必跟著改，只要 body 逐字相符即可比對）。

## 用於驗收⑤（產生權）的具名標註

三筆 fixture 依 `queue-format.md` §5／`enqueue-guard.md` §1 的產生權表，其**合法產生者**分別為：

- fixture-1（`set-labels`）：唯一合法產生者＝`/station-gate`。
- fixture-2（`close-issue`）：唯一合法產生者＝`/station-gate`。
- fixture-3（`comment`）：依原動作歸屬——本則若為 gate 判定類留言則歸 `/station-gate`，若為 run 派工／收件／摘要類留言則歸 `/station-run`（見 `enqueue-guard.md` §2）。

本 fixture 檔案是**人造測試資料**，其本身由 T-21 executor 直接寫入 `build/t21/fixtures/`（開發階段的測試 fixture，不經過任何 skill 的產生權路徑）——這與「正式 loop 運作時佇列項須由對應 skill 產生」是兩回事，不衝突。
