# ADR — 新五站 plugin（取代 fleet-command）

Owner: 彥揚 | Status: 已確認（2026-08-05，站 1 出口） | Created: 2026-08-05
裁示方式：站 1 grill 逐題，一次一題附建議答案，彥揚逐題拍板。

## ADR-NP-001 · 薄編排層，不 fork AgentKit

新 plugin 只含五站狀態機＋面板＋executor 路由表；各站實作 dispatch 給 ak-engineer
現有 99 skills / 16 agents，不複製任何 skill。
理由：不打架、不重複載入（同 marketing kit 未裝的理由）、AgentKit 更新自動受益。

## ADR-NP-002 · GitHub 為機器狀態唯一真相源

票＝GitHub Issues，station 用 label 或 Projects 欄位；面板從 GitHub API 現算聚合，
不落第二份狀態檔。文件（spec／共識文件）照舊 Drive。
⚠️ 保留：CI 與站 4/5 自閉環的接法**未定**，站 2 再議（彥揚明示）。
取代：fleet_state.json（§F.6 整節 sync 陷阱隨之消滅）。

## ADR-NP-003 · 面板＝Cowork 常駐 artifact

自包 HTML 住 desktop artifact gallery，跨 session 存活，update_artifact 就地更新。
一工作一字卡：所在站、執行者、紅燈／審查狀態、在跑數量。
否決：GitHub Projects board（跨 repo 聚合難、字卡客製有限、不在 Claude 側邊欄）；
ak-plans-kanban（localhost-only，Cowork 開不了）。

## ADR-NP-004 · 兩本 Log 進各專案 repo

DECISIONS.md＋CHANGELOG.md 隨 repo 版本化、PR 可審、站 5 CI 查得到。
protocol 層跨專案正典照舊 Drive。
依據：ART-DEC-001（沒改檔案的裁示需要唯一的家）＋A-24.2.1（沿革外移 CHANGELOG）。

## ADR-NP-005 · 兩層 executor 路由

① plugin 內建「站→預設 executor」表，每格附 basis：
   站1→brainstormer／advisor｜站2→planner（＋ak-plan）｜站3→拆票＋kongming 複核｜
   站4→fullstack-developer／ak-cook｜站5→code-reviewer＋異廠 AI（A-30 兩軸兩廠）
② 站 3 拆票時每張票必填 executor＋basis，可覆寫預設，需一句理由。
對齊：§A.2（無 basis＝[INVALID]；臨時換人＝ESCALATE）。

## ADR-NP-006 · Legacy 收編：審計定站＋關鍵補件

非本流程產出的既有專案（品質／格式架構可能不同）不得直接混入生產線：
① 字卡標 `legacy` badge，直到通過第一個 native gate 才摘除；
② fresh-context auditor 對照各站出口條件，判定「退回到站 x」；
③ 關鍵工件（spec、可執行驗收條件）缺了必補；次要工件（名詞表、舊票格式）
   記豁免進該專案 DECISIONS.md——豁免必須具名，防「已知並記錄」被當成「已處理」
   （CS-DEC-GATE-001 教訓）。
否決：嚴格全補（收編成本過高沒人想收）；寬鬆全豁免（洞會被靜默帶進下游）。

## ADR-NP-007 · 站 5 回歸 Pocock 原版（supersedes NP-005 站 5 格與 A-30 兩廠條款）

彥揚 2026-08-05 裁示，依 A-28 至上條款（Pocock 原文 ＞ 轉述 ＞ 本地）：
兩軸（Standards＋Spec）都用同環境 parallel fresh-context `general-purpose` sub-agents
（原文：「Use the general-purpose subagent for both」）；輸入分離、報告不合併不重排、
verifier ≠ executor。
A-30「兩軸兩廠」標 superseded——實證：CS-DEC-GATE-001，廠 2 四次連不上、
A-30 R2 自始至終未被滿足；其效益是推論、成本是量測。
保留手動逃生口：任何票可單筆裁示升兩廠；升 CI 後有量測數據再議常設化。
NP-005 站 5 那格改讀本條；A-30 其餘各條（R1/R3/R4/R5）不受影響。

## ADR-NP-008 · Commander No-Hands：Claude 只指派不自己做

彥揚 2026-08-05 裁示（承接舊 protocol §A.0 精神，帶進新 plugin）：
Claude 主 session（Commander）在五站生產線中**只做：讀 → 驗 → 決 → 派 → 記**。
一切 deliverable（code、spec、票內容、面板 HTML、測試、審查報告）由 dispatch 出去的
executor（ak-engineer agents / sub-agents）產生；Commander 不親手產出任何 deliverable。
「記」的邊界：共識文件（ADR／名詞表）與裁示紀錄屬 Commander 職權；超出此邊界即違規。
此規則為 Pocock 沉默處的本地增設（原版無此條），不構成與至上條款衝突。

## 承接不變（非本次裁示，列出供對照）

站序不可跳｜站 2 出口第三方審｜站 4 先紅後綠｜站 5 兩軸平行、報告不合併（兩廠條款已由 NP-007 supersede）｜
merge 判準五條｜Pocock 至上條款（A-28）衝突裁決順序照舊。
