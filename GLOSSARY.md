# 名詞表 — 新五站 plugin（取代 fleet-command）

Owner: 彥揚 | Status: 站 1 共識草案 | Created: 2026-08-05

| 名詞 | 定義 | 來源 |
|---|---|---|
| 五站 | grill → spec → tickets → implement → review 的生產線，站序不可跳 | Pocock（A-24，2026-07-30），至上條款 A-28 |
| 站（station） | 專案當前所在的生產線位置，跨 session 存在 | fleet-command 站序鎖 |
| 票（ticket） | GitHub Issue。每張帶 REQ-ID＋可執行驗收條件＋depends_on＋executor＋basis | Pocock ticket→Issue 映射＋ADR-5 |
| 真相源 | GitHub（Issues＋labels/Projects 欄位）。面板從 API 現算，不落第二份狀態檔 | ADR-2 |
| 面板 | Cowork 常駐 artifact（自包 HTML，desktop 側邊欄），一工作一字卡：所在站、執行者、紅燈狀態、在跑數量 | ADR-3 |
| 薄編排層 | 新 plugin 只含：五站狀態機、面板、executor 路由表。實作全部 dispatch 給 ak-engineer 現有 skills/agents，不複製 | ADR-1 |
| 兩層路由 | ① 站→預設 executor 表（附 basis）② 每張票必填 executor＋basis，可覆寫預設但需理由 | ADR-5，對齊 §A.2 |
| 紅燈 | 站 3 設計、站 4 執行的 TDD 先紅後綠證據；防作弊主力＝獨立 verifier 實測重放（手動階段在站 4 verifier 執行；升 CI 後移回站 5 CI 重放，見 v0.28.0） | A-24.4，2026-08-05 修訂 |
| Decision Log / Change Log | 各專案 repo 內 DECISIONS.md / CHANGELOG.md；protocol 層跨專案正典照舊 Drive | ADR-4，ART-DEC-001 |
| AgentKit 追蹤 | ak-project-management 的 plans/ 檔案（durable source）＋鏡射到 Cowork task 面板；ak 自帶 kanban 為 localhost-only，不作面板 | 站 1 事實查核 |
| legacy | 非本流程產出的既有專案。收編＝auditor 定站退回站 x＋關鍵補件＋具名豁免；字卡帶 legacy badge 至通過第一個 native gate | ADR-6 |

## 未決項（站 2 議）

1. **CI 怎麼接站 4/5 自閉環**（你明示保留）
2. GitHub 佈局：各專案 repo 各自帶票，面板跨 repo 聚合（目前假設，站 2 確認）
3. Plugin 命名（暫名 `station-command`，可改）
4. 面板刷新機制（skill 指令手動刷 vs 加 scheduled task 定時刷）
5. 舊 fleet-command 退場時機（建議：新 plugin 站 5 驗收過後移除）
