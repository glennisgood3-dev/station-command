# T-15b · `close-milestone` 佇列型別擴充

本檔只定義 T-21 正典尚未涵蓋的 milestone 關閉動作；四欄骨架、非真相源、冪等、回驗、
失敗留隊等規則全部承接 `../t21/queue-format.md`，不另造格式。

## 為何必須擴充

T-15b 明文要求關閉全參與 repo 的 milestone，但 T-21 既有白名單只有 `create-milestone`，
沒有修改 milestone state 的動作。把 milestone 假裝成 `close-issue` 會違反該型
`target.repo + target.issue` 的正典 schema，也會打錯 API 端點。因此依 T-12／T-22 先例，
在本目錄加入最小的 `close-milestone` 型，絕不修改 T-21 owns 的檔案。

## Schema

```json
{
  "action": "close-milestone",
  "target": { "repo": "owner/repo", "milestone": 7 },
  "payload": { "state": "closed" },
  "source": "W-demo"
}
```

- 外層仍須恰好 `action`／`target`／`payload`／`source` 四欄，不多不少。
- `target.repo` 是參與 repo；`target.milestone` 是該 repo 對應 milestone number。
- `payload.state` 本票只准 `closed`。本票不支援也不產生 delete；milestone 可另以 `open`
  reopen，故票面第八欄維持「無」。
- 唯一產生者是 `/station-gate` 的 T-15b 完成態路徑。

## 套用順序與回驗

同一份 `queue.json` 建議先跑 `apply-milestone-queue.ps1`，再跑 `../t21/apply-queue.ps1`。
前者只認 `close-milestone`，其餘型別原樣保留；後者處理 `set-labels`／`close-issue`。

`apply-milestone-queue.ps1` 對每筆執行：GET 現況 → 已 closed 則出列 → 否則 PATCH
`state=closed` → 再 GET 直讀回驗。不存在、API 失敗或回驗不符都留在佇列並回報。
它是佇列消費器，並不繞過佇列直接替完成態判定器寫 GitHub；`work-complete.ps1` 本身零個
GitHub 寫入呼叫。
