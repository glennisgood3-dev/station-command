# T-04 盤點清單 — 舊 fleet-command 規則哪些仍生效（只盤點，不搬移；搬移＝票 #5）

**負責人**：彥揚｜**完成日**：（留空待核）
**分母 fixture**：`t04-fixture.md`（78 條，凍結）｜**對照新 spec**：`Spec_station-command_v1.5.md`＋`ADR.md`（ADR-NP-001～008）
**紅燈紀錄**：盤點前先對空清單跑覆蓋率檢查（`/tmp/t04_coverage.py`）⇒ 0/78＝0.0%，RED（見報告）。本檔完成後重跑須 78/78 GREEN。

**分類**：`仍生效`＝Spec v1.5 未覆蓋、規則仍需存在，票 #5 須搬移｜`已吸收`＝已被 Spec v1.5／ADR 條文承接，舊文轉唯讀正典即可｜`作廢`＝標的機制已被 ADR 消滅或屬歷史紀錄，僅入作廢紀錄。
**判準基線**：站序鎖／出口 gate／merge 判準 → 多已吸收；fleet_state.json／dashboard／心跳／喚醒 → 多作廢（ADR-NP-002）；No-Hands／一級來源紀律／decision 紀律 → 多仍生效或已由 ADR-NP-008 吸收。

## 一、protocol.md（16 條）

| ID | 條目 | 判定 | 建議新家 | 一句理由 |
|---|---|---|---|---|
| PR-01 | ROLE & EXECUTION | 已吸收 | Spec §5（Commander 角色）＋§6（gate 正典） | 「gate 不可跳、放行要具名」由 Spec §6 承接；Phase-Locked P0–P5 模型本體隨五站消滅 |
| PR-02 | 5 LAWS | 作廢 | 作廢紀錄（L3 證偽精神註記已由站 4 紅燈承接） | 五律全綁 Phase 框架；唯 L3 證偽優先之精神已被 Spec §6 站 4「先紅後綠」吸收 |
| PR-03 | PIPELINE | 作廢 | 作廢紀錄 | 需求確認→Size→Charter→P0–P5 流程整條被五站裝配線（A-24→Spec）取代 |
| PR-04 | RED LINES | 仍生效（部分） | 未吸收子條→station-command spec 補充條文＋protocol 正典（Drive 照舊，ADR-NP-004）；已吸收子條免搬；作廢子條入作廢紀錄 | 混合節：No-Hands／verifier≠executor／executor+basis 已吸收（Spec §5.0/§5/§3.5）；Tracking/fleet_state/兩廠子條作廢（ADR-NP-002/007）；**NoURL=NoLog、No Inference、Existing Solutions First、Core 鎖定精神仍生效且 Spec 未覆蓋，須搬** |
| PR-05 | §Q.0 REQUIREMENTS LOCK | 已吸收 | Spec §6 站 1 出口條件 | ≥3 輪需求拷問即站 1 grill（A-24.1）；「使用者已確認共識」為站 1 出口 gate |
| PR-06 | §Q CHARTER + DUAL/TRI + TRACKING | 作廢 | 作廢紀錄（Charter 要素註記由站 2 spec 承接） | Charter 檔→站 2 spec（Goal/Scope/SC 已入 Spec §6 站 2）；Dual/Tri 兩廠作廢（ADR-NP-007）；Tracking.md/Track-sync 作廢（ADR-NP-002/004） |
| PR-07 | §A SUPERVISED AUTONOMY（§A.0 NO-HANDS） | 已吸收 | ADR-NP-008＋Spec §5.0（No-Hands）、§6（gate）、§3.5（executor+basis） | No-Hands 原文即 ADR-NP-008 的前身；§A.2/§A.3/§A.4 的 executor 研究、獨立驗證、fresh-context audit 分別由 §3.5、站 4 verifier、§7.2 auditor 承接 |
| PR-08 | §F FLEET LIVE | 作廢 | 作廢紀錄 | fleet_state.json＋dashboard＋心跳＋喚醒四步＋唯一真相源宣稱整組被 ADR-NP-002/003 消滅；面板改 Spec §4 |
| PR-09 | §K CODING BEHAVIOR | 仍生效 | 各 repo 規範文件（站 5 軸 A 的「repo 規範」正典）＋protocol 正典 | 通用程式行為四律（Think before/Simplicity/Surgical/Goal-driven）不綁艦隊機器，Spec 未覆蓋，正是站 5 軸 A 要引用的 repo 規範素材 |
| PR-10 | PCR FORMAT | 作廢 | 作廢紀錄 | Phase Completion Report 是 Phase 制產物；進度真相改 GitHub label＋timeline（ADR-NP-002） |
| PR-11 | HANDOFF FORMAT | 作廢 | 作廢紀錄 | 跨 agent 交接信封綁 PCR/Charter 生態；交接資訊由票模板七欄（§3.5）與 gate 報告承接 |
| PR-12 | CHECKPOINT | 作廢 | 作廢紀錄 | Log-YYYY-MM 8 欄/6 欄事件格式綁自建簿記，ADR-NP-002「無自建簿記」消滅；紀錄改 DECISIONS/CHANGELOG（Spec §8） |
| PR-13 | ANTI-DILUTION PROTOCOL | 作廢 | 作廢紀錄 | 每 20 訊息重讀 §R＋Charter 綁舊法規生態；新制正典散於 ADR/Spec/名詞表，無對應義務 |
| PR-14 | USER QUICK COMMANDS | 作廢 | 作廢紀錄（[FORCE STOP]／[INVALID] 語意註記由 gate fail-closed 承接） | 指令表整組綁 Phase gate 與 Charter；[INVALID] 語意已由 Spec SC#3 fail-closed 承接 |
| PR-15 | PROJECT SIZE ROUTER | 作廢 | 作廢紀錄 | S/M/L 分級決定廠數與 gate 密度；五站對所有 work 同構，且兩廠條款已廢（ADR-NP-007） |
| PR-16 | ON-DEMAND REFERENCE（動手前要跑什麼表） | 作廢 | 作廢紀錄 | 索引指向 Full Spec 章節與 fleet-command assets 腳本；機器停用（§9d），索引隨之失效 |

## 二、SKILL.md（23 條）

| ID | 條目 | 判定 | 建議新家 | 一句理由 |
|---|---|---|---|---|
| SK-01 | 為什麼獨立成一層 | 作廢 | 作廢紀錄 | 三層架構論證隨 fleet-command 停用；新制分層由 ADR-NP-001 薄編排層取代 |
| SK-02 | 第一原則：不寫死 specific case | 已吸收 | Spec §4.1/§4.2（字卡一律由查詢算出、快取非真相源） | 「板上不寫死任何值、資訊必須是本輪讀到的」已成 Spec 面板硬規則 |
| SK-03 | 四層地圖 | 作廢 | 作廢紀錄 | hook/script 強制層整層失效：Spec Scope Out 明文「無 hooks（Cowork 不可靠）、無 scripts（第一階段）」 |
| SK-04 | 摩擦遙測 | 作廢 | 作廢紀錄（「趨勢不看單點、不拿遙測當 KPI」可註記 DECISIONS） | telemetry 全綁 fleet_state（ADR-NP-002 消滅）；新制無對應量測面 |
| SK-05 | 一級來源（A-7 執行層） | 仍生效 | protocol 正典（Drive 照舊）＋station-command spec 補充（裁示前 context gate） | 一級來源紀律是判準基線點名的仍生效項；Spec §4.4「判定走 issues API 直讀」只吸收了 GitHub 面，primary source 直讀義務本體未覆蓋（primary_sources[] 欄位機制作廢） |
| SK-06 | lint（L1–L7） | 作廢 | 作廢紀錄（fail-closed 原則已由 Spec §4.4/SC#3/SC#4 承接） | fleet_lint 腳本停用；「跳過規則＝沒有板」的 fail-closed 精神已明文入 Spec 硬規則 |
| SK-07 | A-9 審核官（三段流程） | 仍生效（規範本體；機器層作廢） | station-command spec 補充（/station-run dispatch 前檢查）或 plugin repo DECISIONS.md | 派工令出手前獨立審查是 Glenn 硬要求且 Spec 未覆蓋（手動階段僅「經使用者確認後 dispatch」暫代）；review_token/a9_integrate/hook 機器作廢 |
| SK-08 | 心跳迴圈 | 作廢 | 作廢紀錄 | 心跳/間隔表/喚醒鏈/出板兩次整組被 ADR-NP-002/003 消滅；刷新改 Spec §4.5 事件驅動 |
| SK-09 | 不可逆動作前的強制檢查（指標節） | 仍生效（本體 A-5） | 同 AM-05：protocol 正典＋spec 補充 | 本節僅指標；merge 格已被 Spec §3.5 scope 欄＋merge 判準吸收，deploy/花錢/刪資料三步仍無新家 |
| SK-10 | 看板必須由 state 導出 | 已吸收 | Spec §4（未量測不得綠燈→§4.4 錯誤狀態硬規則） | 「無條件綠燈是假 gate」「失敗不得顯示為空狀態」已逐條入 Spec §4.4 |
| SK-11 | 相關檔案 | 作廢 | 作廢紀錄 | assets 清單隨機器停用（§9d）失效 |
| SK-12 | v0.5.0 機器規則層現況（L1–L13/M1–M8） | 作廢 | 作廢紀錄 | lint 規則清單綁停用腳本；「清單與實作不得漂移」精神由 SC#8 白名單人工審承接 |
| SK-13 | v0.6.0 L14 blocker 複查 | 作廢 | 作廢紀錄（複查義務本體＝AM-19，另判） | L14 是 A-16 的機器化；機器作廢，義務本體見 A-16（仍生效） |
| SK-14 | v0.7.0 收據綁定與派工信封 | 作廢 | 作廢紀錄（executor+basis 已由 Spec §3.5 吸收） | Turn-end 五支/決策指紋/喚醒協定/常設裁決全綁 fleet_state；派工信封的 executor＋basis＋scope 要素已入票模板 |
| SK-15 | 站序鎖（Pocock 五站） | 已吸收 | Spec §6＋SC#2（站序不可跳） | 站序不可跳、各站出口 gate 即 Spec 核心；站 2/3 出口 gate 亦入 §5.1 路由 |
| SK-16 | 站 4/5 自閉環（v0.28.0） | 已吸收（部分作廢/延後） | Spec §5.1 註記（防作弊：手動階段站 4 verifier、升 CI 後 manifest 重放）＋§9a（CI 兩階段）；merge 常設授權裁示→plugin repo DECISIONS.md | CI 自閉環明列升 CI 階段（Spec §9a）；站 4 verifier 實測＝Spec §6 站 4；merge 五判準中 scope 比對入 §3.5/§9b，「五條過了就合」的常設授權是使用者裁示、載體應為 DECISIONS |
| SK-17 | 一體性修訂七處衝突 | 作廢 | 作廢紀錄（歷史處置） | 衝突處置是一次性歷史紀錄；其結論已分別由新 spec/ADR 承接或隨機器停用失效 |
| SK-18 | 站 3 出口 gate 兩廠×三軸 | 已吸收（部分） | Spec §5.1（站 3 gate＝code-reviewer）＋§6 站 3；三軸深審（尤其「過度設計」軸）若要保留→spec 補充條文 | 票完備性檢查已入 §3.5 七欄＋站 3 gate；兩廠要求作廢（ADR-NP-007 同理，實測從未跑成）；三軸深審未被明文吸收，屬殘留缺口 |
| SK-19 | 腳本真相源鐵則 | 作廢 | 作廢紀錄 | 唯一可執行目錄綁停用腳本；「不要有第二份」原則已由 SC#1 零狀態複製＋A-35 一個家承接 |
| SK-20 | 打包前檢查 | 作廢 | 作廢紀錄（教訓可註記新 plugin repo DECISIONS.md） | 檢查項綁 fleet-command bundle 與 package_check.py；新 plugin 打包教訓（description<500 字元等）值得註記但非現行規則 |
| SK-21 | Subagent 上限的執行層 | 仍生效 | station-command spec 補充（dispatch sub-agent 須綁 maxTurns 具名定義）或 plugin repo DECISIONS.md | 「避免 agent 無限迴圈」是 Glenn 硬要求且 Spec 對 dispatch 的 sub-agent 無任何上限規範；pretool_agent_gate/agent_ledger 機器作廢，maxTurns 判準需在新 plugin 重落地 |
| SK-22 | spec_lint（S1–S6） | 作廢 | 作廢紀錄（S5 舊值殘留/S6 假結案教訓可註記 DECISIONS） | 腳本停用；站 2 缺口審改由 kongming fresh-context 承接（Spec §5.1） |
| SK-23 | 防重複改四機制 | 作廢（機器層） | 作廢紀錄；規則本體 A-33 另判（仍生效，見 AM-36）；決策紀錄制度已由 Spec §8 吸收 | L29/L30/L32/decision_sweep/decision_index 全綁停用腳本與 gate_rounds[]；「推翻舊條目須開新條目並具名取代」已入 Spec §8 |

## 三、protocol-amendments.md（39 條）

| ID | 條目 | 判定 | 建議新家 | 一句理由 |
|---|---|---|---|---|
| AM-01 | A-1 rework 換手分級 | 作廢 | 作廢紀錄 | 綁 §A.5/step/Tracking 生態；站 4 卡關轉 debugger（Spec §5.1）承接換手情境 |
| AM-02 | A-2 gate 轉 AUTO 前提 | 作廢 | 作廢紀錄（「放寬須有數據」原則可註記 DECISIONS） | P0→P1/P1→P2 gate 已隨 Phase 消滅；escalation outcome 欄位生態不存在 |
| AM-03 | A-3 [S] batch gate | 作廢 | 作廢紀錄 | Size 分級消滅（同 PR-15） |
| AM-04 | A-4 transport 偏好 | 已吸收 | Spec §2（run：dispatch 失敗⇒立即移除 assignee 並具名回報） | 「transport 失敗必須具名中止、不得靜默」已入 run 白名單行為；api/manual/subagent 分類隨 Devin 生態失效 |
| AM-05 | A-5 §A.6 不可逆動作前強制檢查 | 仍生效（部分吸收） | protocol 正典（Drive 照舊）＋station-command spec 補充 | merge 格已由 scope 欄（§3.5）＋merge 判準承接；deploy/計費/刪資料前三步（base 主幹→自量 diff→對不上停手）Spec 未覆蓋，仍需家 |
| AM-06 | A-6 決策就緒包 | 仍生效 | station-command spec 補充（sc:awaiting-user 升級件格式）或 protocol 正典 | 「一個問題＋預分析選項＋不做的代價＋信心度」是 decision 紀律；Spec 只有 sc:awaiting-user 標籤，無升級格式要求 |
| AM-07 | 永不動（四條不得放寬） | 已吸收 | Spec §5（verifier≠executor hard rule）、§5.0/ADR-NP-008（No-Hands）、§7.2（fresh-context）；「不可逆必 HARD」隨 AM-05 搬 | 四條中三條已明文入 Spec；第四條（不可逆必 HARD）由 A-5 承載，見 AM-05 |
| AM-08 | A-7 一級來源紀律（含 A-7.5） | 仍生效 | protocol 正典（Drive 照舊，ADR-NP-004）＋Spec 已部分實例化（§4.4 直讀） | 判準基線點名仍生效；「對系統現狀的斷言必須直讀來源本身」是跨專案行為律，Spec 只覆蓋 GitHub 面 |
| AM-09 | A-8 registry 廢止・fleet_state 唯一落點 | 作廢 | 作廢紀錄 | 其結論（fleet_state 為唯一執行時狀態）本身再被 ADR-NP-002 消滅；「單一真相源」原則由 GitHub 承接 |
| AM-10 | A-9 獨立審核官 | 仍生效 | 同 SK-07：spec 補充或 plugin repo DECISIONS.md | 「審核官不得是 Commander/Verifier/Executor」為使用者原話硬性規定；Spec 無派工令審查對應物 |
| AM-11 | A-9 R3 取證權 | 仍生效（附屬 AM-10） | 隨 AM-10 同落點；輸入紀律面已由 §7.2「只餵工件、禁餵自陳」同構吸收 | 「用證據驗、不用轉述驗」是 A-9 可運作的前提；若 AM-10 搬移則本條必須隨行 |
| AM-12 | A-10 儲存紀律（兩界必備） | 已吸收 | ADR-NP-002/004＋Spec §4.3（明引 A-10：只報告不自動修） | GitHub＝機器真相、plans/=敘事來源、修復逐案裁示——Spec §4.3 已具名引用本條 |
| AM-13 | A-11 共識觸發點（＋Charter 禁花費） | 作廢 | 作廢紀錄 | 兩廠 95% 共識與 Charter/Phase 入口全數消滅（ADR-NP-007）；「共識未確認不得往下」已由站 1 出口承接 |
| AM-14 | A-12 時間紀律 | 仍生效 | protocol 正典必讀層（Drive 照舊） | 「時間戳動筆前先取實值、回溯值必標推估」是無條件行為律，與艦隊機器無關，Spec 未覆蓋 |
| AM-15 | A-13 授權邊界不可外推 | 仍生效 | protocol 正典必讀層＋DECISIONS.md 制度說明（Spec §8 可加註） | 「一次裁示只涵蓋字面具名標的、用掉即消耗」是 decision 紀律；Spec §8 只管紀錄形式，未管授權射程 |
| AM-16 | A-14 忙碌不等於進展 | 仍生效 | station-command spec 補充（面板或 gate 的「站別停滯」檢視）或 DECISIONS.md | Spec 停滯票數量的是「24h 沒動」；A-14 抓的是「一直在動卻不進站」——兩者不同義，後者未被覆蓋 |
| AM-17 | A-15 機器規則必須入文 | 作廢 | 作廢紀錄（精神由 SC#8 白名單人工審承接） | 第一階段無 scripts，無「執行層機器規則」可列；文件與實務不得漂移之精神已入 SC#8 |
| AM-18 | A-9 R8 成本方案 | 作廢 | 作廢紀錄 | 審核官子代理模型選型綁舊機器；「已否決勿重提」項隨 A-9 新落地重議 |
| AM-19 | A-16 blocker 複查 | 仍生效 | station-command spec 補充（gate/board 每次執行複查 sc:blocked 是否仍成立） | Spec 有 sc:blocked 標籤與過期豁免掃描，但無「每回合複查既有 blocker 還成不成立」義務——原事故（9/20 筆過期）會重演 |
| AM-20 | A-17 預先授權清單 | 仍生效 | 各 repo／plugin repo DECISIONS.md（常設授權條目） | 常設授權制度本體不綁機器；新制天然載體是 DECISIONS.md，但需明文其「白名單」語意 |
| AM-21 | A-18 判例回寫 | 仍生效 | DECISIONS.md 制度補充（每次裁示後追問「同類是否轉常設」） | decision 紀律；Spec §8 未含判例回寫義務 |
| AM-22 | A-19 升級包合規自查 | 仍生效（附屬 AM-06） | 隨 AM-06 同落點 | 「先抓執行違規再改條款」是 A-6 的執行面檢查，隨 A-6 存廢 |
| AM-23 | A-20 操作面教訓（命名具名化/verdict 首行） | 仍生效 | station-command spec 補充（gate/verifier 報告首行只能 PASS 或 FAIL） | verdict 型輸出防歧義對新制 gate/verifier 報告同樣適用；Spec 未規定報告首行格式 |
| AM-24 | A-21 自主性提升包 | 已吸收（部分仍生效） | merge 轉 AUTO 沿革→作廢紀錄（被 SK-16 判準取代）；A-21.2 三問/A-21.3 白話/A-21.5「待你」二分→DECISIONS.md 或 spec 補充 | 主體（merge AUTO）已被新 merge 判準與 Spec 承接；打擾前自查三問與白話紀律是仍生效的溝通行為律 |
| AM-25 | A-22 兩廠 FAIL 自動修正迴圈 | 作廢 | 作廢紀錄（精神由 Spec §5「修復必須復驗」承接） | 兩廠共識消滅（ADR-NP-007）；「FAIL 不是終點、修完要復驗」已入站 5 結案條件 |
| AM-26 | A-23 executor session 輪替 | 作廢 | 作廢紀錄 | Devin session XL/輪替生態消滅；新制 dispatch sub-agent 每次 fresh-context，無長壽 session 可輪替 |
| AM-27 | A-24 五站裝配線 | 已吸收 | Spec 全文（§5/§6）＋ADR-NP-007；A-24.2.1 沿革另檔已入 Spec §8 CHANGELOG 規則 | 本條就是 Spec 的直系前身，逐站對應 §6 出口條件 |
| AM-28 | A-25 writing-great-skills 三心法 | 仍生效 | plugin repo DECISIONS.md／新 plugin 開發規範 | 修剪/指引詞/完成標準適用於新 plugin 的 4 份 SKILL.md 維護；Spec 只管白名單不管寫法 |
| AM-29 | A-26 名詞表制度 | 已吸收 | 名詞表＝上游正典（Spec 開頭明列）；站 1 出口含「名詞表存在且無未定義」 | 制度已是新制第一站的出口條件 |
| AM-30 | A-27 ADR 制度 | 已吸收 | ADR.md＝上游正典；站 1 出口含「ADR 記錄關鍵裁示」 | 同上，制度本身已是正典層 |
| AM-31 | A-28 Pocock 至上條款 | 已吸收 | ADR-NP-007（站 5 回歸 Pocock 原版）；vendored 21 支的取用改由 ak-engineer 生態承接 | 「與 Pocock 衝突以原文為準」的最大宗爭點（站 5）已由 ADR-NP-007 定案 |
| AM-32 | A-29 結構性缺口堵法 | 仍生效（A-29.3/29.4；29.1/29.2 作廢） | A-29.3「宣稱上線必有實跑證據」→protocol 正典必讀層或 spec 補充；A-29.4 外部審核處理紀律→DECISIONS.md | 29.1/29.2 綁 escalation 欄位生態（作廢）；29.3 是通用行為律（Spec 驗收 #17 等僅為實例）；29.4 逐條查證外部審核仍適用 |
| AM-33 | A-30 站 5 兩軸×兩廠 | 已吸收 | ADR-NP-007（明文 supersedes A-30 兩廠條款）＋Spec §5.2（兩軸輸入分離逐字承接） | 兩軸×輸入分離×禁餵過程對話全數入 §5.2；兩廠與廢除信心分數的裁決由 ADR 定案 |
| AM-34 | A-34 行為準則進必讀層 | 仍生效 | protocol 正典（Drive 照舊）＋新 plugin SKILL.md 取捨判準（plugin repo DECISIONS.md） | 「需要在無觸發時就生效的規則必進必讀層」是配置判準，決定票 #5 各條搬去哪一層時本身就要用到 |
| AM-35 | A-31・A-32 跳號說明 | 作廢 | 作廢紀錄（原文照留，防編號重用） | 兩條本來就不存在；本節唯一功能是解釋跳號，隨舊檔轉唯讀即可 |
| AM-36 | A-33 根因鐵律＋決策不得默默翻案 | 仍生效 | protocol 正典必讀層（session-preamble §A.7/§A.8 對應物）；「翻案須具名取代」半條已由 Spec §8 吸收 | 兩條是無條件行為律（Glenn 明示要在主行為 prompt 層）；Spec §8 只吸收了 DECISIONS 紀錄面，修改順序（先查根因→先立字據→再動手）未覆蓋 |
| AM-37 | A-35 必讀層補完＋一條規則只准一個家 | 仍生效 | protocol 正典＋票 #5 搬移作業準則 | 「同一規則只准一個家、其餘放指標」是搬移作業本身的方法論；Spec §6「唯一正典」同精神但只及 gate checklist |
| AM-38 | A-36 全域矛盾稽核 | 作廢 | 作廢紀錄 | 一次性稽核紀錄（9 條已改），無現行規範力 |
| AM-39 | A-37 不矛盾但錯誤稽核 | 作廢 | 作廢紀錄（「斷言拿去撞真實世界」方法可註記 DECISIONS） | 同上，一次性稽核；其方法教訓值得留名但非現行條文 |

## 四、統計

| 檔案 | 仍生效 | 已吸收 | 作廢 | 小計 |
|---|---|---|---|---|
| protocol.md | 2 | 3 | 11 | 16 |
| SKILL.md | 4 | 5 | 14 | 23 |
| protocol-amendments.md | 18 | 9 | 12 | 39 |
| **合計** | **24** | **17** | **37** | **78** |

覆蓋率：78/78＝100%（重跑 `/tmp/t04_coverage.py` 須 GREEN）。每條「新家」欄非空。

## 五、盤點者信心註記（供 verifier 抽驗聚焦）

最沒把握的 5 條：
1. **SK-07／AM-10／AM-11（A-9 審核官族）**——標「仍生效」，但手動階段 Spec 以「使用者確認 dispatch」暫代，也可論證為「已吸收（由使用者確認取代）」。
2. **SK-16（站 4/5 自閉環）**——CI 自閉環（延後）、站 4 verifier（吸收）、merge 常設授權（裁示→DECISIONS）三塊拆歸，單一標籤必然失真。
3. **SK-18（站 3 三軸審）**——Spec 站 3 gate 只查欄位完備性；三軸深審（尤其「過度設計」軸）判「未被吸收的殘留缺口」是否成立，需裁示。
4. **AM-24（A-21 自主性提升包）**——主標「已吸收」但 A-21.2/21.3/21.5 子條仍生效，混合條拆法可爭。
5. **AM-16（A-14 忙碌不等於進展）**——與 Spec「停滯票數（24h 無事件）」是否同義：我判不同義故標仍生效，反方論證存在。
