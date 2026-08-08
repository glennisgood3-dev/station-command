# T-15b · work 級完成態收尾

依 `tickets-draft.md` T-15b（GitHub issue #16）、Spec v1.11 §3.2／§3.3／§6 done 列／
§2 gate 權限白名單／§4.6，以及 `../t21/queue-format.md` 實作。既有地基直接重用：
`work-complete.ps1` dot-source `../t15a/station5-check.ps1` 的 `Find-LastCloseEvent`，並由該路徑
cascade 重用 T-10／T-21 的陣列安全、UTF-8 與佇列讀寫函式；既有檔案完全未修改。

## 行為摘要

- 有 open 票：`incomplete`，不做 work 收尾。
- 完全零票：`no-tickets`，不套最小站公式，也不以空集合真值誤關 work。
- 零 open 且任一票最後的 closed actor 不在 `gateIdentityLogins`：`awaiting-user`，只產生
  anchor 的完整 `set-labels` 項（移除 station label、加入 `sc:awaiting-user`），絕不關 anchor
  或任何 milestone。
- 零 open 且全票皆由 gate actor 關閉：`complete`，產生完整 `set-labels`（`sc:station-done`）、
  anchor 的 `close-issue`，以及每個參與 repo 的 `close-milestone`。
- 沒有任何 delete 動作。label 可摘、issue 可 reopen、milestone 可 reopen，因此不可逆動作
  判定為「無」；若未來改成刪 milestone，必須重判為「有 ⇒ 刪資料」。

T-21 尚無關閉 milestone 型別；本票依 T-12／T-22 的 file-ownership 先例在本目錄新增
`close-milestone`，詳細 schema 與套用流程見 `milestone-queue-ext.md`。外層仍恰四欄，沒有第五欄。

## 紅燈開關

> ⚠️ `-SkipHumanClosureCheck` **僅供紅燈驗證，正式流程與一般手動執行絕對禁用**。

開啟後，所有 `state=closed` 的票都會被錯當成站 5 gate 關閉。離線測試以
`fixtures/human-closed.json` 開啟此旗標，執行原文斷言：

> `存在人手關閉的票 ⇒ Decision 不得為 complete`

該斷言會真的丟出 `ASSERTION FAILED`，測試捕捉後寫成 `[RED-CONFIRMED]` 證據；隨即關閉
旗標，以同一 fixture 重跑並得到 `Decision=awaiting-user`。這是斷言失敗的紅，不是檔案缺漏、
語法錯誤或 import 失敗。

## 獨立預期值來源

四份人造 fixture 的 `expected` 區塊由實驗者依 Spec §3.2 預先配置；被測程式完全不讀
`expected`，只有測試讀它做比對。關票 actor、票數、repo/milestone 對應與預期 action 筆數都
是 fixture 已知 literal，不從被測程式輸出反推。詳見 `fixtures/README.md`。

## 使用方式（Windows PowerShell 5.1）

```powershell
Set-StrictMode -Version Latest
cd <plugin repo>\build\t15b

# 從 gate 已讀得的 GitHub 現況製作 snapshot（schema 見 fixtures/README.md），只產生佇列項
.\work-complete.ps1 -SnapshotPath .\my-work-snapshot.json -QueuePath 'G:\default mount\station-command-queue.json'

# 先處理本票新增的 milestone 型，再由 T-21 處理 canonical metadata 型
.\apply-milestone-queue.ps1 -QueuePath 'G:\default mount\station-command-queue.json'
..\t21\apply-queue.ps1 -QueuePath 'G:\default mount\station-command-queue.json'
```

離線測試不讀 PAT、不連網：

```powershell
.\t15b-offline-test.ps1
```

## 交付檔與驗收／實跑結果

### ① 交付檔清單

| 檔案 | 用途 |
|---|---|
| `work-complete.ps1` | 完成態判定、完整 label 集合與收尾佇列批次產生；本檔不呼叫 GitHub 寫入 API |
| `apply-milestone-queue.ps1` | 只消費已存在的 `close-milestone` 佇列項，套用前冪等比對、套用後直讀回驗 |
| `t15b-offline-test.ps1` | 完全離線 mock；含紅燈斷言、fixture 預期值、0/1/N、四欄 schema、批次防線 |
| `t15b-offline-test-report.txt` | 最後一次完整離線實跑輸出（UTF-8 BOM） |
| `milestone-queue-ext.md` | `close-milestone` 最小擴充正典與 T-21 共存理由 |
| `fixtures/all-gate-closed.json` | 驗收①：跨 2 repo、3 張票全由 gate 關閉 |
| `fixtures/human-closed.json` | 驗收②及紅燈：零 open、其中 1 張由人手關閉 |
| `fixtures/no-tickets.json` | 驗收③：真正的空陣列 |
| `fixtures/open-ticket.json` | 非完成態：恰 1 張 open 票（單一物件／Count 邊界） |
| `fixtures/README.md` | fixture schema、實驗者預設 expected 值與來源說明 |
| `README.md` | 本交付說明與實跑紀錄 |

共 11 個檔案，全部位於 `build/t15b/`，未修改 T-09～T-27 或 `build/station-command/` 既有檔。

### ② 驗收條件逐條對應

| 驗收條件 | 實作／測項 | 最後實跑 |
|---|---|---|
| ① 最後一票經站 5 gate 關閉 ⇒ `sc:station-done`、關 anchor、關全參與 repo milestone | `Invoke-T15bCompletionDecision`、`New-T15bCompletionQueueItems`；C1～C12、F1～F4 | PASS；產 1 `set-labels`＋1 `close-issue`＋2 `close-milestone`，2 個參與 repo 皆命中 |
| ② 零 open 但有人手關閉 ⇒ 不完成、落 `sc:awaiting-user` | `Test-T15bTicketClosedByGate`；A、B1～B10 | PASS；正常模式為 `awaiting-user`，只產 1 筆 `set-labels`，0 筆 anchor／milestone 關閉 |
| ③ 零票不得套最小站公式，且無錯誤 | `Invoke-T15bCompletionDecision` 的 `no-tickets` 分支；D1～D3 | PASS；`MinimumStationApplicable=False`、queue Count=0，未發生 `.Count`／空陣列錯誤 |

補充守門：E 組逐筆驗證外層恰四欄並測佇列重跑冪等；G 組證明 milestone work ID 慣例不符時
在產生任何部分批次前拒絕，且沒有任何 delete 動作。

### ③ 紅燈原文與真的失敗證據

斷言原文：

> `存在人手關閉的票 ⇒ Decision 不得為 complete`

以 `fixtures/human-closed.json` 開啟 `-SkipHumanClosureCheck` 的實跑證據：

```text
[RED-CONFIRMED] ASSERTION FAILED: 存在人手關閉的票 ⇒ Decision 不得為 complete；-SkipHumanClosureCheck 開啟後實得 Decision='complete'
```

隨即關閉開關重跑同一 fixture：B1～B10 全過，`Decision='awaiting-user'`。證據已保存在
`t15b-offline-test-report.txt`。正式流程禁用旗標的警告同時寫在腳本註解、CLI warning 與本 README。

### ④ 三道自檢數字

最後一次以 `/opt/pwsh/pwsh` 7.4.6、`Set-StrictMode -Version Latest` 執行：

| 自檢 | 數字 | 結果 |
|---|---:|---|
| UTF-8 BOM | 3/3 支 `.ps1` 首三 bytes 皆 `EF BB BF` | PASS |
| `Parser.ParseFile` | 3/3 支 `.ps1`，parse errors=0 | PASS |
| 完整離線測試 | TOTAL=55、PASS=55、FAIL=0、RED-CONFIRMED=1 | PASS |

第一次完整離線測試曾真實抓到一個已修復缺陷：以 `if` 表達式輸出 `@()` 時空陣列被管線解卷成
`$null`，StrictMode 下讀 `.Count` 失敗。已改為在分支內直接賦值，之後完整重跑為 55/55；
此載入後 runtime 缺陷沒有被拿來當紅燈，紅燈仍是上節的斷言失敗。

### ⑤ CLI smoke test

直接執行（未帶 `-FunctionsOnly`）：

```text
/opt/pwsh/pwsh -NoProfile -File build/t15b/work-complete.ps1 \
  -SnapshotPath build/t15b/fixtures/all-gate-closed.json \
  -QueuePath /tmp/t15b-smoke-20260808/queue.json \
  -ReportPath /tmp/t15b-smoke-20260808/report.txt
```

結果：exit 0；主控台有 13 行實質輸出（不是 no-op）；`Decision=complete`；queue 4 筆，action
依序為 `set-labels, close-issue, close-milestone, close-milestone`；四筆外層欄數皆為 4；
queue 853 bytes、report 757 bytes。

## 誠實聲明

| 類別 | 本輪做到什麼 | 還差什麼才能驗完 |
|---|---|---|
| deferred-to-CI：真實 actor 歸因 | 程式完整讀最後一次 closed event；離線測 gate bot／human 兩路 | 本輪禁止連網且無 token。需 CI 的獨立 gate bot 身分、測試 repo 與真實 timeline；手動階段 actor 等於使用者時無法機器區分，會安全落 `awaiting-user` |
| deferred-to-CI：跨 repo 真實落地 | `close-milestone` 套用器已實作 GET→PATCH→GET、離線 mock 回驗通過 | 需可寫的測試 repo/token，真實套用 2+ repo 後逐 repo 直讀確認；本輪沒有也不聲稱做過真實 GitHub 寫入 |
| best-effort：Windows PowerShell 5.1 | 所有腳本 `#requires -Version 5.1`、StrictMode Latest；刻意測 0/1/N 與 dot-source 參數 cascade；ParseFile／runtime 由指定的 pwsh 7.4.6 通過 | 沙盒沒有 Windows PowerShell 5.1；仍需 Windows CI 以 `powershell.exe` 重跑同一 55 項與 CLI smoke，才能稱原生 5.1 動態驗完 |
| best-effort：snapshot 完整性 | 對已宣告 participatingRepos 的每個 milestone 做 work ID、anchor 指標、number、重複 repo fail-closed 檢查 | 本票不做 T-16 跨 repo search；接線端仍須保證 tickets／participatingRepos 快照沒有漏 repo。未宣告的 repo 無法由本票猜出 |

除上述四項外，沒有其他 deferred 或 best-effort 項目。`close-milestone` 是「關閉」而非「刪除」；
本票不可逆動作仍誠實判定為「無」。
