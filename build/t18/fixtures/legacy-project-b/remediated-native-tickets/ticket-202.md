REQ-ID: REQ-LP-202
驗收條件: 可執行——人為構造一筆逾 10 分鐘的 StaleLock，跑清除流程一次，看該筆是否於 ReconcileWindow 內被清除
depends_on: [REQ-LP-201]
executor: fullstack-developer
basis: StaleLock 清除邏輯依賴 WidgetSync 既有排程掛勾，同一執行體較不易漏接時序
scope: StaleLock 偵測與 ReconcileWindow 內自動清除，不含 WidgetSync 排程本身（見 #201）
測試先行: 先寫「逾時鎖於 ReconcileWindow 內被清除」斷言取紅燈；seam: StaleLock 清除函式；獨立預期值來源: GLOSSARY.md 對 StaleLock／ReconcileWindow 的定義（10 分鐘門檻、02:00-03:00 時間窗）
不可逆動作: 無 —— 清除的是逾時鎖狀態，非使用者資料，可重建
