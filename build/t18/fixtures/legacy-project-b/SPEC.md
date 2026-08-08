# legacy-project-b／SPEC.md

## Goal
讓 WidgetSync 排程任務穩定同步遠端 widget 狀態，杜絕 StaleLock 累積。

## Scope In / Scope Out
- **In**：WidgetSync 排程邏輯、StaleLock 偵測、ReconcileWindow 自動清除。
- **Out**：遠端 API 本身的可靠性改善（非本專案控制範圍）。

## Success Criteria（可驗證）
1. 連續 7 天無 StaleLock 累積超過 ReconcileWindow 一次以上。
2. WidgetSync 排程任務失敗率低於 1%。

## 第三方缺口審
見 `GAP-REVIEW.md`，hard finding 共 2 條，皆已結案（見該檔逐條標註）。
使用者已於 2026-06-15 確認本 spec（會議紀錄見內部 wiki LP-2026-06-15）。
