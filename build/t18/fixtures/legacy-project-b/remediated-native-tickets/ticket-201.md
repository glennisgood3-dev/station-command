REQ-ID: REQ-LP-201
驗收條件: 可執行——跑 WidgetSync 排程一次，看 BarQueue 是否收到對應筆數的結果紀錄
depends_on: []
executor: fullstack-developer
basis: 需要真的能跑排程與寫入 BarQueue 的執行體
scope: WidgetSync 排程任務本身，不含 StaleLock 清除（見 #202）
測試先行: 先寫「排程執行後 BarQueue 筆數增加」斷言取紅燈；seam: WidgetSync 排程主流程入口函式；獨立預期值來源: SPEC.md 的 Success Criteria 第 2 條（失敗率門檻）與人造排程輸入固件
不可逆動作: 無 —— 寫入 BarQueue 為可重放的冪等操作，可回退
