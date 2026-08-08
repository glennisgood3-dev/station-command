# T-05 搬移落檔對照表（migration-map）

**分母 fixture**：`t04-fixture.md`（78 條，凍結，本檔不得反過來改動它）
**分類承接**：仍生效 24／已吸收 17／作廢 37（見 `t04-inventory.md` 統計）
**本檔範圍**：僅搬移與落檔（T-05）。不含停用動作（T-20）。不改 `t04-fixture.md`。

## 狀態欄定義（本檔實際使用的四種值）

| 狀態 | 意義 |
|---|---|
| 已搬移 | 仍生效條目，新家已落地（spec patch 已寫入 `spec-additions.md` 且非草案性質，或既有機制已足以承載） |
| 已具名作廢 | 條目在 `decisions-additions.md` 有具名作廢紀錄，含「本項不再生效」字樣 |
| 已吸收（免搬） | T-04 判定已被 Spec/ADR 承接，本票核實後確認無需額外動作 |
| 待人工裁示 | 落點或是否採納存在真實分歧或未定門檻，本票只交草案，不代上游或使用者拍板 |

四類合計＝24＋37＋17＝78。實際落點統計（見下方各表）：已搬移 20／已具名作廢 42／已吸收（免搬）16／待人工裁示 0（20+42+16+0=78）。SK-07／AM-10／AM-11／SK-18／AM-16 五列已於 2026-08-08 由「待人工裁示」轉「作廢」（見 SC-DEC-RETIRE-038／039／040），故「已具名作廢」由 37 增至 42、「待人工裁示」由 5 歸零。

---

## 一、protocol.md（16 條）

| ID | 原文摘要 | 新家 | 新條目ID或位置 | 狀態 |
|---|---|---|---|---|
| PR-01 | ROLE & EXECUTION | Spec §5（Commander 角色）＋§6（gate 正典） | 既有條文，無新增 | 已吸收（免搬） |
| PR-02 | 5 LAWS | plugin repo DECISIONS.md | SC-DEC-RETIRE-001 | 已具名作廢 |
| PR-03 | PIPELINE | plugin repo DECISIONS.md | SC-DEC-RETIRE-002 | 已具名作廢 |
| PR-04 | RED LINES（混合節：NoURL=NoLog／No Inference／Existing Solutions First／Core 鎖定精神） | protocol.md（Drive，正典位置不變）＋ Spec v1.8 補充 | Spec-Add SP-0 | 已搬移 |
| PR-05 | §Q.0 REQUIREMENTS LOCK | Spec §6 站 1 出口條件 | 既有條文，無新增 | 已吸收（免搬） |
| PR-06 | §Q CHARTER + DUAL/TRI + TRACKING | plugin repo DECISIONS.md | SC-DEC-RETIRE-003 | 已具名作廢 |
| PR-07 | §A SUPERVISED AUTONOMY（含 §A.0 NO-HANDS） | ADR-NP-008＋Spec §5.0／§6／§3.5 | 既有條文，無新增 | 已吸收（免搬） |
| PR-08 | §F FLEET LIVE | plugin repo DECISIONS.md | SC-DEC-RETIRE-004 | 已具名作廢 |
| PR-09 | §K CODING BEHAVIOR（四律） | protocol.md（Drive，不變）＋各 repo 規範文件（站 5 軸 A 素材） | Spec-Add SP-0 ＋ Spec-Add SP-9 | 已搬移 |
| PR-10 | PCR FORMAT | plugin repo DECISIONS.md | SC-DEC-RETIRE-005 | 已具名作廢 |
| PR-11 | HANDOFF FORMAT | plugin repo DECISIONS.md | SC-DEC-RETIRE-006 | 已具名作廢 |
| PR-12 | CHECKPOINT | plugin repo DECISIONS.md | SC-DEC-RETIRE-007 | 已具名作廢 |
| PR-13 | ANTI-DILUTION PROTOCOL | plugin repo DECISIONS.md（本項【未】處理——無現行對應義務） | SC-DEC-RETIRE-008 | 已具名作廢 |
| PR-14 | USER QUICK COMMANDS | plugin repo DECISIONS.md | SC-DEC-RETIRE-009 | 已具名作廢 |
| PR-15 | PROJECT SIZE ROUTER | plugin repo DECISIONS.md | SC-DEC-RETIRE-010 | 已具名作廢 |
| PR-16 | ON-DEMAND REFERENCE | plugin repo DECISIONS.md | SC-DEC-RETIRE-011 | 已具名作廢 |

## 二、SKILL.md（23 條）

| ID | 原文摘要 | 新家 | 新條目ID或位置 | 狀態 |
|---|---|---|---|---|
| SK-01 | 為什麼獨立成一層 | plugin repo DECISIONS.md | SC-DEC-RETIRE-012 | 已具名作廢 |
| SK-02 | 第一原則：不寫死 specific case | Spec §4.1／§4.2 | 既有條文，無新增 | 已吸收（免搬） |
| SK-03 | 四層地圖 | plugin repo DECISIONS.md | SC-DEC-RETIRE-013 | 已具名作廢 |
| SK-04 | 摩擦遙測 | plugin repo DECISIONS.md（本項【未】處理——教訓存證，非現行規則） | SC-DEC-RETIRE-014 | 已具名作廢 |
| SK-05 | 一級來源（A-7 執行層） | protocol.md（Drive）＋ Spec v1.8 補充 | Spec-Add SP-0 ＋ Spec-Add SP-1 | 已搬移 |
| SK-06 | lint（L1–L7） | plugin repo DECISIONS.md | SC-DEC-RETIRE-015 | 已具名作廢 |
| SK-07 | A-9 審核官（三段流程，規範本體） | 作廢，無新家（2026-08-08 裁示，SC-DEC-RETIRE-038）；原草案落點「草案：Spec v1.8 §5.1 之後」已不採納 | Spec-Add SP-11（草案，待裁示） | 作廢（2026-08-08 裁示，見 SC-DEC-RETIRE-038） |
| SK-08 | 心跳迴圈 | plugin repo DECISIONS.md | SC-DEC-RETIRE-016 | 已具名作廢 |
| SK-09 | 不可逆動作前的強制檢查（指標節，本體 A-5） | Spec v1.8 §5.3a 補充 | Spec-Add SP-2 | 已搬移 |
| SK-10 | 看板必須由 state 導出 | Spec §4.4 | 既有條文，無新增 | 已吸收（免搬） |
| SK-11 | 相關檔案 | plugin repo DECISIONS.md | SC-DEC-RETIRE-017 | 已具名作廢 |
| SK-12 | v0.5.0 機器規則層現況 | plugin repo DECISIONS.md | SC-DEC-RETIRE-018 | 已具名作廢 |
| SK-13 | v0.6.0 L14 blocker 複查 | plugin repo DECISIONS.md（機器層；義務本體見 AM-19） | SC-DEC-RETIRE-019 | 已具名作廢 |
| SK-14 | v0.7.0 收據綁定與派工信封 | plugin repo DECISIONS.md | SC-DEC-RETIRE-020 | 已具名作廢 |
| SK-15 | 站序鎖（Pocock 五站） | Spec §6＋SC#2 | 既有條文，無新增 | 已吸收（免搬） |
| SK-16 | 站 4/5 自閉環（v0.28.0） | 免搬——merge 常設授權已由 Spec §5.3a／ADR-NP-010 明文承接（見下方分歧#2） | 無新增（與 T-04 建議之額外 DECISIONS.md 條目分歧，見分歧記錄） | 已吸收（免搬） |
| SK-17 | 一體性修訂七處衝突 | plugin repo DECISIONS.md | SC-DEC-RETIRE-021 | 已具名作廢 |
| SK-18 | 站 3 出口 gate 兩廠×三軸 | 完備性部分：Spec §3.5／§6 站 3（既有，未受本次裁示影響）；三軸深審殘留部分＝**作廢，無新家（2026-08-08 裁示，SC-DEC-RETIRE-039）**；原草案落點「草案 Spec v1.8 §5.2 之後（與 T-04 建議之 §6 站 3 落點不同，見分歧#3）」已不採納 | Spec-Add SP-12（草案，待裁示） | 作廢（2026-08-08 裁示，見 SC-DEC-RETIRE-039） |
| SK-19 | 腳本真相源鐵則 | plugin repo DECISIONS.md | SC-DEC-RETIRE-022 | 已具名作廢 |
| SK-20 | 打包前檢查 | plugin repo DECISIONS.md（本項【未】處理——教訓存證，非現行規則） | SC-DEC-RETIRE-023 | 已具名作廢 |
| SK-21 | Subagent 上限的執行層 | Spec v1.8 §5.3a 補充 | Spec-Add SP-3 | 已搬移 |
| SK-22 | spec_lint（S1–S6） | plugin repo DECISIONS.md | SC-DEC-RETIRE-024 | 已具名作廢 |
| SK-23 | 防重複改四機制 | plugin repo DECISIONS.md（機器層；規則本體見 AM-36） | SC-DEC-RETIRE-025 | 已具名作廢 |

## 三、protocol-amendments.md（39 條）

| ID | 原文摘要 | 新家 | 新條目ID或位置 | 狀態 |
|---|---|---|---|---|
| AM-01 | A-1 rework 換手分級 | plugin repo DECISIONS.md | SC-DEC-RETIRE-026 | 已具名作廢 |
| AM-02 | A-2 gate 轉 AUTO 前提 | plugin repo DECISIONS.md（本項【未】處理——「放寬須有數據」原則未編碼為規則） | SC-DEC-RETIRE-027 | 已具名作廢 |
| AM-03 | A-3 [S] batch gate | plugin repo DECISIONS.md | SC-DEC-RETIRE-028 | 已具名作廢 |
| AM-04 | A-4 transport 偏好 | Spec §2（run dispatch 失敗即回報） | 既有條文，無新增 | 已吸收（免搬） |
| AM-05 | A-5 §A.6 不可逆動作前強制檢查 | Spec v1.8 §5.3a 補充（與 SK-09 同落點） | Spec-Add SP-2 | 已搬移 |
| AM-06 | A-6 決策就緒包 | Spec v1.8 §5.3a 之後新增子節 | Spec-Add SP-4 | 已搬移 |
| AM-07 | 永不動（四條不得放寬） | Spec §5／§5.0／ADR-NP-008／§7.2（第四條見 AM-05） | 既有條文，無新增 | 已吸收（免搬） |
| AM-08 | A-7 一級來源紀律（含 A-7.5） | protocol.md（Drive）＋ Spec 既有 §4.4 ＋ 補充 | Spec-Add SP-0 | 已搬移 |
| AM-09 | A-8 registry 廢止・fleet_state 唯一落點 | plugin repo DECISIONS.md | SC-DEC-RETIRE-029 | 已具名作廢 |
| AM-10 | A-9 獨立審核官 | 作廢，無新家（2026-08-08 裁示，SC-DEC-RETIRE-038）；原草案落點「草案：Spec v1.8 §5.1 之後（與 SK-07 同落點，見分歧#1）」已不採納 | Spec-Add SP-11（草案，待裁示） | 作廢（2026-08-08 裁示，見 SC-DEC-RETIRE-038） |
| AM-11 | A-9 R3 取證權（附屬 AM-10） | 作廢，無新家（2026-08-08 裁示，SC-DEC-RETIRE-038）；原草案落點「隨 AM-10 同落點」已不採納 | Spec-Add SP-11（草案，待裁示） | 作廢（2026-08-08 裁示，見 SC-DEC-RETIRE-038） |
| AM-12 | A-10 儲存紀律（兩界必備） | ADR-NP-002／004＋Spec §4.3 | 既有條文，無新增 | 已吸收（免搬） |
| AM-13 | A-11 共識觸發點 | plugin repo DECISIONS.md | SC-DEC-RETIRE-030 | 已具名作廢 |
| AM-14 | A-12 時間紀律 | protocol.md（Drive，必讀層） | Spec-Add SP-0 | 已搬移 |
| AM-15 | A-13 授權邊界不可外推 | Spec v1.8 §8 之後補充 | Spec-Add SP-7 | 已搬移 |
| AM-16 | A-14 忙碌不等於進展 | 作廢，無新家（2026-08-08 裁示，SC-DEC-RETIRE-040）；原草案落點「草案：Spec v1.8 §4.1 補充（與 T-04 全稱「仍生效」判斷有分歧，見分歧#5——本票判斷為部分已吸收＋部分殘留）」已不採納 | Spec-Add SP-10（草案，待裁示） | 作廢（2026-08-08 裁示，見 SC-DEC-RETIRE-040） |
| AM-17 | A-15 機器規則必須入文 | plugin repo DECISIONS.md | SC-DEC-RETIRE-031 | 已具名作廢 |
| AM-18 | A-9 R8 成本方案 | plugin repo DECISIONS.md（本項【未】處理——待 A-9 新落地後重議費用） | SC-DEC-RETIRE-032 | 已具名作廢 |
| AM-19 | A-16 blocker 複查 | Spec v1.8 §6「全站（每次 gate 均查）」列補充 | Spec-Add SP-5 | 已搬移 |
| AM-20 | A-17 預先授權清單 | Spec §8 既有「拍板」類型即可承載（機制已就緒，個案觸發時登入 DECISIONS.md） | 既有機制，無新增 spec 文字 | 已搬移 |
| AM-21 | A-18 判例回寫 | Spec v1.8 §8 之後補充 | Spec-Add SP-6 | 已搬移 |
| AM-22 | A-19 升級包合規自查（附屬 AM-06） | 隨 AM-06 同落點 | Spec-Add SP-4 | 已搬移 |
| AM-23 | A-20 操作面教訓（verdict 首行） | Spec v1.8 §6 之後補充 | Spec-Add SP-13 | 已搬移 |
| AM-24 | A-21 自主性提升包（A-21.2/21.3/21.5 子條） | 主體已吸收；子條併入 AM-06／AM-15／AM-21 落點，不另立 | Spec-Add SP-4／SP-6／SP-7 | 已吸收（免搬） |
| AM-25 | A-22 兩廠 FAIL 自動修正迴圈 | plugin repo DECISIONS.md | SC-DEC-RETIRE-033 | 已具名作廢 |
| AM-26 | A-23 executor session 輪替 | plugin repo DECISIONS.md | SC-DEC-RETIRE-034 | 已具名作廢 |
| AM-27 | A-24 五站裝配線 | Spec 全文 §5／§6＋ADR-NP-007 | 既有條文，無新增 | 已吸收（免搬） |
| AM-28 | A-25 writing-great-skills 三心法 | plugin repo DECISIONS.md（拍板） | `decisions-additions.md` Part B | 已搬移 |
| AM-29 | A-26 名詞表制度 | GLOSSARY.md（上游正典）＋Spec §6 站 1 出口 | 既有條文，無新增 | 已吸收（免搬） |
| AM-30 | A-27 ADR 制度 | ADR.md（上游正典）＋Spec §6 站 1 出口 | 既有條文，無新增 | 已吸收（免搬） |
| AM-31 | A-28 Pocock 至上條款 | ADR-NP-007 | 既有條文，無新增 | 已吸收（免搬） |
| AM-32 | A-29 結構性缺口堵法（29.3/29.4 仍生效；29.1/29.2 隨舊機制消滅） | 29.3→protocol.md（Drive）；29.4→Spec §8 新增「外部審核回應」類型 | Spec-Add SP-0（29.3）＋ Spec-Add SP-8（29.4） | 已搬移 |
| AM-33 | A-30 站 5 兩軸×兩廠 | ADR-NP-007＋Spec §5.2 | 既有條文，無新增 | 已吸收（免搬） |
| AM-34 | A-34 行為準則進必讀層 | protocol.md（Drive）＋plugin repo DECISIONS.md（拍板，方法論） | `decisions-additions.md` Part B | 已搬移 |
| AM-35 | A-31・A-32 跳號說明 | plugin repo DECISIONS.md | SC-DEC-RETIRE-035 | 已具名作廢 |
| AM-36 | A-33 根因鐵律＋決策不得默默翻案 | protocol.md（Drive，必讀層）＋Spec 既有 §8（翻案取代機制） | Spec-Add SP-0 | 已搬移 |
| AM-37 | A-35 必讀層補完＋一條規則只准一個家 | protocol.md（Drive）＋本次 migration-map 一列一家原則本身即實踐 | Spec-Add SP-0 | 已搬移 |
| AM-38 | A-36 全域矛盾稽核 | plugin repo DECISIONS.md | SC-DEC-RETIRE-036 | 已具名作廢 |
| AM-39 | A-37 不矛盾但錯誤稽核 | plugin repo DECISIONS.md（本項【未】處理——方法教訓存證，非現行規則） | SC-DEC-RETIRE-037 | 已具名作廢 |

---

## 四、與 T-04 的分歧記錄（五條低確信條目，具名交使用者裁示，不代為覆蓋上游結論）

### 分歧#1：SK-07／AM-10／AM-11（A-9 審核官族）
**T-04 判定**：仍生效，新家「station-command spec 補充（/station-run dispatch 前檢查）或 plugin repo DECISIONS.md」。
**本票判斷**：同意仍生效（Spec 現行機制確實無「派工令獨立審查」對應物）。**但發現 T-04 未點出的張力**：ADR-NP-010 已裁示「站 4／5 內部的 dispatch、驗收、雙審、merge 一律不問」（自主 loop，不逐次確認）。若把 A-9 獨立審核官原樣搬回站 4／5 的每次 dispatch，等於在已自動化的 loop 中重新插入人工／第三方關卡，可能與 ADR-NP-010 的自主化決策衝突。
**本票處置**：只落草案（`spec-additions.md` SP-11），**不寫入正式 spec**，狀態標「待人工裁示」，草案中已載明此張力，交使用者決定是否採納、以及採納範圍（僅審派工令本身，或也審每次 dispatch）。
**裁示結果**：不採納，作廢（彥揚，2026-08-08）。依據：Pocock 六份原文唯一的第三方覆核（`code-review/SKILL.md` 兩軸平行 sub-agent）發生在實作完成後（站 5），派工前覆核零命中；使用者原話 S4「Execute with S3.」、S5「S4 S5 gives high autonomy to Ai.」亦無此關卡；且防作弊方向相反——使用者原話 S3「Always design Red light to prevent Ai cheating.」，看產物才抓得到，看派工令抓不到；A-9 唯一有效成分（角色分離）已被 §6「verifier ≠ executor」吸收。詳見 `decisions-additions.md` SC-DEC-RETIRE-038、`spec-additions.md` SP-11、`Spec_station-command_v1.11.md` §9.1。

### 分歧#2：SK-16（站 4/5 自閉環）
**T-04 判定**：已吸收（部分作廢/延後），並列出「merge 常設授權裁示→plugin repo DECISIONS.md」為待落地項。
**本票判斷**：**部分不同意**——merge 五判準常設授權已在 Spec §5.3a／ADR-NP-010 明文承接（原文：「站4／5內部的dispatch、驗收、雙審、merge一律不問…承接舊常設授權『merge五條判準全過即合』」）。此裁示已具名存在，不需要本票再開一條新的 DECISIONS.md 條目重複記錄。
**本票處置**：狀態標「已吸收（免搬）」，不產生新條目；此分歧記錄本身即具名說明理由，不覆蓋 T-04 對「CI 自閉環／站4 verifier」兩塊判定（本票同意此二者已吸收）。
**裁示結果**：維持原判「已吸收（免搬）」，不需新條目（彥揚複核同意，2026-08-08）。

### 分歧#3：SK-18（站 3 出口 gate 兩廠×三軸）
**T-04 判定**：已吸收（部分），三軸深審（尤其「過度設計」軸）若要保留 → spec 補充條文，暗示落點在 Spec §6 站 3。
**本票判斷**：**落點不同意**。現行 Spec 站 3 出口條件（§3.5／§6 站 3）的角色定義是「票欄位完備性＋切片可獨立驗收」，屬結構性檢查，深入的設計品質審查與此角色不符；而站 5 雙審（§5.2）軸 A 已包含 12 條 Fowler smell 基線，其中「Speculative Generality」與舊「過度設計」軸有實質重疊。若確有殘留缺口，更合理的家是 §5.2 新增第三軸，而非塞進站 3。
**本票處置**：草案落在 `spec-additions.md` SP-12（放在 §5.2 之後），狀態標「待人工裁示」，並具名此落點分歧，交使用者決定是否採納、以及採用站 3 或站 5 版本。
**裁示結果**：不採納，作廢（彥揚，2026-08-08）。依據：`code-review/SKILL.md` 明訂兩軸且逐字寫死「Do **not** merge or rerank findings — the two axes are deliberately separate」；三軸中的「過度設計」已有家，在 Standards 軸 Fowler baseline「**Speculative Generality** — abstraction, parameters, or hooks added for needs the spec doesn't have.」；位置也錯——`to-tickets/SKILL.md` 站 3 出口原文是「### 4. Quiz the user ... Iterate until the user approves the breakdown.」，站 3 出口是使用者核准，不是機器三軸審。詳見 `decisions-additions.md` SC-DEC-RETIRE-039、`spec-additions.md` SP-12、`Spec_station-command_v1.11.md` §9.1。

### 分歧#4：AM-24（A-21 自主性提升包）
**T-04 判定**：已吸收（部分仍生效），A-21.2 三問／A-21.3 白話／A-21.5「待你」二分 → DECISIONS.md 或 spec 補充。
**本票判斷**：同意仍生效，**非落點分歧，屬合併精簡**——三個子條的內容與 AM-06（決策就緒包）在「使用者升級/通知格式」這件事上高度重疊，本票將其併入同一個 spec patch（SP-4），未另立條目，以符合 AM-37「一條規則只准一個家」的方法論。此為整併而非否決 T-04 結論。
**裁示結果**：維持原判「已吸收（免搬）」，不需新條目（彥揚複核同意，2026-08-08）。

### 分歧#5：AM-16（A-14 忙碌不等於進展）
**T-04 判定**：仍生效（全稱），因與 Spec「停滯票數（24h 無事件）」不同義。
**本票判斷**：**部分不同意 T-04 的全稱判斷**——Spec §5.3a 停止條件②「同一票 rework 2 次仍 fail ⇒ 停手」，對站 4／5 情境而言已經是「忙碌不等於進展」的一種操作化（loop 層級）。真正未覆蓋的殘留，是**面板／gate 層級**對非 rework 情境（例如站 1–3 的人類 gate 卡住、或票一直有動作但站別不動）的「忙碌未進展」可視化，且觸發門檻（幾次？幾小時？）未定。
**本票處置**：狀態標「待人工裁示」，草案落在 `spec-additions.md` SP-10（§4.1 之後），具名此為部分已吸收＋部分殘留，非 T-04 原判定的「全稱仍生效」，門檻由使用者裁示。
**裁示結果**：不採納，作廢（彥揚，2026-08-08）。依據：六份 Pocock 原文與使用者 S1–S5 原話皆零命中；`grilling/SKILL.md` 的 "frontier" 是設計樹推進機制，不是停滯警示。使用者另裁示面板不加新指標，維持 Spec §4.1 現有「停滯票數（24h 無事件）」欄位不動。附註：「看得到進度」仍是使用者新需求第 2 條的要求，但依據換成新需求本身，非 A-14 之繼承——依據換了，日後設計不必照 A-14 原樣。詳見 `decisions-additions.md` SC-DEC-RETIRE-040、`spec-additions.md` SP-10、`Spec_station-command_v1.11.md` §9.1。
