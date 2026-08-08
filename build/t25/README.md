# T-25 · 停因通知與收尾批次摘要

本交付只在 `build/t25/` 擴充 T-24：直接 dot-source `../t24/run-loop.ps1 -FunctionsOnly`，消費既有的 `StopReason`、`StopDetail` 與 `RoundSummaries`。沒有重寫 loop、frontier、gate 或六條停因判定，也沒有修改 `build/t09`～`build/t27` 的任何既有檔案。

## 交付檔清單

| 檔案 | 用途 |
|---|---|
| `run-finalize.ps1` | T-25 主實作：T-24 loop 薄封裝、單行批次摘要、comment 佇列項、停因通知策略、唯一推播入口 |
| `t25-offline-test.ps1` | 完整離線 mock 驗收；含三個刻意破壞正式行為的紅燈開關 |
| `t25-apply-mock.ps1` | 子程序攔截 REST；在 `/tmp` 的 T-21 套用器副本上驗證 comment 套用與讀回，全程不連網 |
| `t25-offline-test-report.txt` | 正式模式綠燈實錄：16 PASS、0 FAIL、exit 0 |
| `t25-red-missing-notification.txt` | 「該叫不叫」紅燈實錄：15 PASS、1 FAIL、exit 1 |
| `t25-red-notification-spam.txt` | 「不該叫狂叫」紅燈實錄：15 PASS、1 FAIL、exit 1 |
| `t25-red-per-round-comments.txt` | 「逐輪洗版」紅燈實錄：14 PASS、2 FAIL、exit 1 |
| `t25-quality-gates.txt` | BOM、ParseFile、離線測試與 smoke 數字 |
| `t25-cli-smoke.txt` | 主 CLI 直接執行且不是靜默 no-op 的輸出實錄 |
| `README.md` | 本交件說明與驗收對照 |

## 實作契約

`Invoke-StationRunLoopWithFinalization` 是完整整合入口。它先呼叫 T-24 的 `Invoke-StationRunLoop`，停止後才呼叫 `Complete-StationRunLoop`。正式模式只產生一個摘要 comment，目標固定為 primary anchor，內文是一行，包含本批所有 `RoundSummaries` 與具名停因。若 loop 尚未具名停止，收尾會 fail-closed，不會把安全閥或結構性錯誤冒充第七種停因。

推播只有一條底層管道：`Send-StationUserPush`，channel 固定為 `station-user-push`。`Send-StationStopNotification` 只負責套用停因策略後呼叫它：②③④⑥各送一次，①⑤零次。T-29 未來的 50%／80% 成本告警直接呼叫 `Send-StationUserPush -Category cost-warning`；本票沒有另立成本通知器，也沒有實作 T-29 的成本記帳。

`NotificationSink` 是宿主注入的推播 callback。離線驗收以 ArrayList sink 記錄實際呼叫；未注入時 CLI 明確輸出 `[主動推播][station-user-push]`，不會靜默吞掉通知。

摘要項遵守 T-21 正典，物件恰四欄：

```json
{
  "action": "comment",
  "target": { "repo": "owner/repo", "issue": 42 },
  "payload": { "body": "loop 批次摘要｜…｜停因⑤：frontier 空｜…" },
  "source": "W-demo"
}
```

所有 T-25 留言都經 T-12 的 `Add-RunQueueItemGuarded`，因此 run 的完整產生權仍只有 `set-assignee`／`set-ticket-fields`／`comment`；測試彙整實際佇列後確認沒有 `set-labels`、`close-issue`、`create-issue` 或 `create-milestone`。

## 驗收條件逐條對應

| 票面／硬性條件 | 測試 | 實跑結果 |
|---|---|---|
| 停因②③④須推播、①⑤安靜；依 v1.11 再納入⑥須推播 | A1、A2 | ②③④⑥各 1 次；①⑤各 0 次，PASS |
| 「該叫不叫」與「不該叫狂叫」獨立驗收 | A1、A2；兩份獨立紅燈實錄 | 正式模式兩者皆 PASS；破壞模式各自只讓對應斷言 FAIL |
| 不得另立第二套通知機制，T-29 可沿用 | A3、A4 | 所有停因推播 channel 均為 `station-user-push`；人造 `cost-warning` 亦走相同入口，PASS |
| loop 跑滿三輪只留一則摘要，不是三則 | B1、B2、B4 | 真正呼叫 T-24 loop，三個 PASS 輪次、3 個派工項、1 個 comment，PASS |
| 摘要涵蓋三輪派票與 gate 判定，且具名停因 | B3 | 同一行含 `#101 PASS`、`#102 PASS`、`#103 PASS` 與停因⑤，PASS |
| 續跑不得逐輪留痕 | B1、B4 | 三輪期間無 comment；停止後唯一 comment 指向 anchor，PASS |
| 摘要與停因紀錄皆為留言型佇列項 | B3、C1、C4 | 同一個 `comment` 內同時包含批次摘要與停因；恰四欄且 payload 只有 body，PASS |
| 套用後能從對應票或 anchor 讀到 | D1～D3 | 在隔離副本中執行既有 T-21 `apply-queue.ps1`；mock anchor `mock/apply#77` 讀回完全相同 body，套用後出列，PASS |
| 摘要不參與 gate | E1 | 帶摘要跑一次既有 `Invoke-GateCheck`，移除摘要再跑；投影結果逐字相同且皆 pass，PASS |
| run 權限邊界 | C1～C3 | 4 筆實際項目全為允許型，禁用型 0，四欄錯誤 0，PASS |
| 獨立預期值來源 | A、B 段固定 fixture | A 的人造六停因表固定為 `{①:0,②:1,③:1,④:1,⑤:0,⑥:1}`；B 在被測 loop 執行前固定票號 101／102／103 與預期 comment=1，未拿被測輸出反推預期 |

完整正式測試指令與結果：

```powershell
/opt/pwsh/pwsh -NoProfile -File build/t25/t25-offline-test.ps1
# exit 0；PASS=16；FAIL=0
```

## 紅燈證據

以下三個開關都在主實作與測試檔的 comment-based help 中具名標示：**僅供紅燈驗證，正式流程禁用**。

### 1. 該叫不叫

```powershell
/opt/pwsh/pwsh -NoProfile -File build/t25/t25-offline-test.ps1 `
  -SkipRequiredNotifications `
  -ReportPath build/t25/t25-red-missing-notification.txt
```

exit 1，斷言原文與證據：

> `[FAIL] A1 斷言「停因②③④⑥必須各主動推播一次」（錯誤模式：該叫不叫） 獨立預期=②:1,③:1,④:1,⑥:1；實際=②:0,③:0,④:0,⑥:0`

### 2. 不該叫狂叫

```powershell
/opt/pwsh/pwsh -NoProfile -File build/t25/t25-offline-test.ps1 `
  -SkipSilentNotificationGuard `
  -ReportPath build/t25/t25-red-notification-spam.txt
```

exit 1，斷言原文與證據：

> `[FAIL] A2 斷言「停因①⑤必須安靜、零推播」（錯誤模式：不該叫狂叫） 獨立預期=①:0,⑤:0；實際=①:1,⑤:1`

### 3. 逐輪洗版

```powershell
/opt/pwsh/pwsh -NoProfile -File build/t25/t25-offline-test.ps1 `
  -SkipBatchAggregation `
  -ReportPath build/t25/t25-red-per-round-comments.txt
```

exit 1，核心斷言原文與證據：

> `[FAIL] B1 斷言「loop 跑三輪只產生恰一則摘要留言，非逐輪洗版」 獨立預期=1；實際 comment=4；RoundSummaries=3`

同次執行的 B4 亦因逐輪 comment 而失敗；這是同一個刻意注入的錯誤模式，不是載入失敗。最初一次嘗試曾先碰到空集合參數綁定錯誤；該次已明確作廢、未當成紅燈證據。加入 `[AllowEmptyCollection()]` 後重跑，以上留存檔才是有效紅燈：三支腳本均成功載入並跑到斷言，失敗原因是實際 comment=4 而非預期 1。

## BOM／ParseFile／離線測試三道自檢

交件前最終結果：

- `.ps1` 共 3 支；UTF-8 BOM：3/3。
- ParseFile：3/3 已跑；總語法錯誤 0。
- 完整離線測試：16 PASS、0 FAIL、exit 0。
- 測試中的所有 REST 呼叫均由白名單 mock 攔截；未列入的 URL 或方法會立刻 throw，沒有任何真 GitHub API、key、token 或個資。

實跑器為題目指定的 `/opt/pwsh/pwsh`，版本 7.4.6。程式以 `#requires -Version 5.1`、`Set-StrictMode -Version Latest` 與 PS 5.1 安全陣列模式撰寫：函式回傳先賦值再 `@()`、空集合不以同層 `,@()` 賦值、所有 dot-source 前參數均存入 `$T25...` 防火牆。

## CLI smoke test

```powershell
/opt/pwsh/pwsh -NoProfile -File build/t25/run-finalize.ps1 -DemoMode
```

結果 exit 0，且有以下非空輸出：

- 收到 `channel=station-user-push`、停因④的 callback。
- 實際寫入佇列總數 1、comment 1。
- `Notification.Sent=True`。
- 輸出含三輪摘要與具名停因④。

因此不是 CLI cascade 導致的 exit 0／零輸出 no-op。`t25-offline-test.ps1` 本身亦直接執行；其中 D 段另以子程序直接執行 `t25-apply-mock.ps1`，三支 `.ps1` 都走過實際執行路徑。

## 誠實聲明：deferred-to-CI 與 best-effort

- **deferred-to-CI**：§7.5 的跨 session 排程整節依規格在手動階段不生效，本票沒有偷做排程、頻率或無記憶 prompt。要驗完需 T-26 的 CI 階段 spec、可寫 GitHub 的 `github-actions[bot]` 身分與排程執行環境。
- **best-effort：Windows PowerShell 5.1 實機**：目前容器只有 `/opt/pwsh/pwsh` 7.4.6，沒有 `powershell`／`powershell.exe`，故無法誠實宣稱已在 Windows PowerShell 5.1 實跑。已完成 3/3 ParseFile、BOM 與 StrictMode 動態測試；要驗完仍需 Windows 主機上的 `powershell.exe -Version 5.1` 跑同一測試檔。
- **best-effort：真 GitHub 留言落地**：題目明禁外網與真 GitHub API，因此 D 段把既有 T-21 `apply-queue.ps1` 與 `queue-common.ps1` 複製到 `/tmp` 隔離目錄後，用假 PAT 與有狀態 REST mock 實跑「讀現況→POST comment→回驗→出列」。這也避免既有 T-21 報告檔被改動。要驗完真端點仍需可寫 GitHub 的測試 repo 與授權身分。
- **best-effort：宿主 UI 推播**：本票已實作且驗證唯一 callback 管道與停因策略，但離線 PowerShell 無法自行觸發 Cowork／Codex 宿主 UI。要驗完最後一哩需宿主把 `NotificationSink` 綁到實際的使用者推播能力，再分別觀察②③④⑥有通知、①⑤無通知。未注入 sink 時 CLI 會明確寫到主控台，不會靜默。
- **沿用 T-24 的既有限制**：真 sub-agent dispatch／收件／判 gate 不可能由離線 PowerShell 自行完成；完整多輪以 T-24 的 `GateResultProvider` seam 注入人造結果。要驗完真人／sub-agent 端到端，需 Commander 宿主提供實際 dispatch 與 gate callback。本票沒有重做或擴張 T-24 loop。

除以上逐項具名者外，本票驗收沒有宣稱 deferred 或 best-effort。
