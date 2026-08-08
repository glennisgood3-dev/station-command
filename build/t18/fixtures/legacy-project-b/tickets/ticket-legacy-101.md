# [旧格式票] #101 WidgetSync 排程任務實作

負責人：Bob
內容：實作 WidgetSync 每小時排程，寫入結果到 BarQueue。
狀態：done

（本檔案刻意示範站 3「§3.5 全八項欄位」出口條件的反例——舊格式票只有「負責人／內容／狀態」
三個自由格式欄位，**完全沒有** REQ-ID／驗收條件／depends_on／executor／basis／scope／
測試先行／不可逆動作 任何一個 §3.5 欄位標記，可用 `grep -E 'REQ-ID|驗收條件|depends_on|
executor|basis|scope|測試先行|不可逆動作' ticket-legacy-101.md` 核對——零命中。）
