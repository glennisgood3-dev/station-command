# T-05 · 需寫入 plugin repo DECISIONS.md 的條目

**寫入路徑**：依 Spec §8，本檔所有條目皆為草案（`draft`），須經 `docs-manager`／`git-manager` 開 PR、使用者確認合併後方生效，任何 skill 不得直接 push。
**類型欄前提**：「作廢」與「外部審核回應」為本票（依 `spec-additions.md` SP-8）新增的類型，需與該 patch 一併確認採納後，Part A 的條目方可視為格式合規；若使用者不採納 SP-8，Part A 條目需改標「修改」並補述「取代 <原規則>」語意。

---

## Part A · 作廢紀錄類（37 條，對應 `migration-map.md` 的「已具名作廢」）

| 日期 | ID | 類型 | 裁示內容 | 依據 | 裁示人 | 狀態 |
|---|---|---|---|---|---|---|
| 2026-08-06 | SC-DEC-RETIRE-001 | 作廢 | 舊 `protocol.md` 5 LAWS（L1–L5）本項不再生效；L3 證偽優先精神已由 Spec §6 站 4「先紅後綠」承接，其餘四律隨 Phase 框架消滅，無殘留缺口 | t04-inventory.md PR-02；Spec_station-command_v1.8.md §6（站4） | 彥揚（依 T-04/T-05 盤點提交，待 PR 確認） | draft |
| 2026-08-06 | SC-DEC-RETIRE-002 | 作廢 | 舊 `protocol.md` PIPELINE（需求確認→Size→Charter→P0–P5）本項不再生效；整條流程已由 Spec §6 五站裝配線取代 | t04-inventory.md PR-03；Spec §6；ADR-NP-007 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-003 | 作廢 | 舊 `protocol.md` §Q CHARTER + DUAL/TRI-AGENT + TRACKING 本項不再生效；Charter 要素已入 Spec §6 站 2 出口條件，Dual/Tri 兩廠條款由 ADR-NP-007 廢止，Tracking.md／Track-sync 隨 ADR-NP-002/004 消滅 | t04-inventory.md PR-06；Spec §6；ADR-NP-007 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-004 | 作廢 | 舊 `protocol.md` §F FLEET LIVE（fleet_state.json＋dashboard＋心跳＋喚醒）本項不再生效；全數由 ADR-NP-002/003 消滅，面板改由 Spec §4 現算聚合承接 | t04-inventory.md PR-08；ADR-NP-002／003；Spec §4 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-005 | 作廢 | 舊 `protocol.md` PCR FORMAT（Phase Completion Report）本項不再生效；進度真相改由 GitHub label 與 timeline 承接 | t04-inventory.md PR-10；ADR-NP-002 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-006 | 作廢 | 舊 `protocol.md` HANDOFF FORMAT 本項不再生效；跨 agent 交接資訊改由票模板七欄與 gate 報告承接 | t04-inventory.md PR-11；Spec §3.5 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-007 | 作廢 | 舊 `protocol.md` CHECKPOINT（Log-YYYY-MM 事件格式）本項不再生效；紀錄改由 DECISIONS.md／CHANGELOG.md 承接 | t04-inventory.md PR-12；Spec §8 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-008 | 作廢 | 舊 `protocol.md` ANTI-DILUTION PROTOCOL（每 20 訊息重讀 §R＋Charter）本項不再生效。**本項【未】處理**——新制無「每 20 訊息重讀」對應義務，其精神散於 ADR／Spec／名詞表但無單一承接條文，本裁示僅記錄此為已知落差，不代為補上新義務 | t04-inventory.md PR-13 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-009 | 作廢 | 舊 `protocol.md` USER QUICK COMMANDS 本項不再生效；`[INVALID]` fail-closed 語意已由 Spec SC#3 承接，其餘指令表隨 Phase gate 與 Charter 消滅 | t04-inventory.md PR-14；Spec SC#3 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-010 | 作廢 | 舊 `protocol.md` PROJECT SIZE ROUTER（S/M/L 分級）本項不再生效；兩廠條款隨 ADR-NP-007 廢止，五站對所有 work 同構，不再分廠數 | t04-inventory.md PR-15；ADR-NP-007 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-011 | 作廢 | 舊 `protocol.md` ON-DEMAND REFERENCE（動手前索引表）本項不再生效；索引指向的 Full Spec 章節與 fleet-command assets 腳本隨機器停用同步失效 | t04-inventory.md PR-16；Spec §9 決 d | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-012 | 作廢 | 舊 `SKILL.md`「為什麼獨立成一層」（三層架構論證）本項不再生效；新制分層改由 ADR-NP-001 薄編排層承接 | t04-inventory.md SK-01；ADR-NP-001 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-013 | 作廢 | 舊 `SKILL.md`「四層地圖」（hook/script 強制層）本項不再生效；Spec Scope Out 明文「無 hooks（Cowork 不可靠）、無 scripts（第一階段）」 | t04-inventory.md SK-03；Spec §1 Scope Out | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-014 | 作廢 | 舊 `SKILL.md`「摩擦遙測」本項不再生效。**本項【未】處理**——telemetry 全綁 fleet_state（已消滅），新制無對應量測面；「趨勢不看單點、不拿遙測當 KPI」之教訓僅存證，非現行規則 | t04-inventory.md SK-04 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-015 | 作廢 | 舊 `SKILL.md` lint（L1–L7）本項不再生效；`fleet_lint` 腳本停用，fail-closed 精神已由 Spec §4.4／SC#3／SC#4 明文承接 | t04-inventory.md SK-06；Spec §4.4 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-016 | 作廢 | 舊 `SKILL.md`「心跳迴圈」本項不再生效；心跳／間隔表／喚醒鏈／出板兩次整組由 ADR-NP-002/003 消滅，刷新改由 Spec §4.5 事件驅動承接 | t04-inventory.md SK-08；Spec §4.5 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-017 | 作廢 | 舊 `SKILL.md`「相關檔案」（assets 清單）本項不再生效；隨機器停用同步失效 | t04-inventory.md SK-11；Spec §9 決 d | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-018 | 作廢 | 舊 `SKILL.md` v0.5.0 機器規則層（L1–L13/M1–M8）本項不再生效；規則清單綁停用腳本，「清單與實作不得漂移」精神已由 SC#8 白名單人工審承接 | t04-inventory.md SK-12；Spec SC#8 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-019 | 作廢 | 舊 `SKILL.md` v0.6.0 L14 blocker 複查（機器化）本項不再生效；L14 機制隨腳本停用消滅，複查義務本體改由 AM-19 落地承接（見 `migration-map.md`、`spec-additions.md` SP-5），非本項承接 | t04-inventory.md SK-13；spec-additions.md SP-5 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-020 | 作廢 | 舊 `SKILL.md` v0.7.0 收據綁定與派工信封本項不再生效；Turn-end 五支／決策指紋／喚醒協定／常設裁決全綁 fleet_state 已消滅，executor＋basis＋scope 要素已入 Spec §3.5 票模板 | t04-inventory.md SK-14；Spec §3.5 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-021 | 作廢 | 舊 `SKILL.md`「一體性修訂七處衝突」（歷史紀錄）本項不再生效；為一次性歷史處置紀錄，結論已分別由新 spec/ADR 承接或隨機器停用失效 | t04-inventory.md SK-17 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-022 | 作廢 | 舊 `SKILL.md`「腳本真相源鐵則」本項不再生效；唯一可執行目錄綁停用腳本，「不要有第二份」原則已由 SC#1 零狀態複製與名詞表「一個家」原則承接 | t04-inventory.md SK-19；Spec SC#1 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-023 | 作廢 | 舊 `SKILL.md` v0.8.1 打包前檢查本項不再生效。**本項【未】處理**——檢查項綁 fleet-command bundle 與 `package_check.py`，新 plugin 打包教訓（如 description<500 字元）值得記取但未另立現行檢查機制 | t04-inventory.md SK-20 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-024 | 作廢 | 舊 `SKILL.md` v0.12.1 `spec_lint.py`（S1–S6）本項不再生效；腳本停用，站 2 缺口審改由 `kongming` fresh-context 承接 | t04-inventory.md SK-22；Spec §5.1 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-025 | 作廢 | 舊 `SKILL.md` v0.13.0 防重複改四機制（機器層）本項不再生效；L29/L30/L32/decision_sweep/decision_index 全綁停用腳本，決策紀錄制度已由 Spec §8 承接；規則本體（推翻須具名取代）另由 AM-36 落地 | t04-inventory.md SK-23 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-026 | 作廢 | 舊 A-1 rework 換手分級本項不再生效；綁 §A.5／step／Tracking 生態，站 4 卡關轉 `debugger` 已承接換手情境 | t04-inventory.md AM-01；Spec §5.1 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-027 | 作廢 | 舊 A-2 gate 轉 AUTO 前提本項不再生效。**本項【未】處理**——P0→P1/P1→P2 gate 隨 Phase 消滅，「放寬須有數據」原則未被編碼為現行規則，僅存證 | t04-inventory.md AM-02 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-028 | 作廢 | 舊 A-3 [S] 專案 batch gate 本項不再生效；Size 分級機制隨 ADR-NP-007（兩廠廢止）與五站同構設計消滅 | t04-inventory.md AM-03；ADR-NP-007 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-029 | 作廢 | 舊 A-8 registry 廢止・fleet_state 唯一落點本項不再生效；其結論本身再被 ADR-NP-002 消滅，單一真相源原則改由 GitHub 承接 | t04-inventory.md AM-09；ADR-NP-002 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-030 | 作廢 | 舊 A-11 共識觸發點界定（＋Charter 禁花費）本項不再生效；兩廠 95% 共識與 Charter/Phase 入口全數隨 ADR-NP-007 消滅，「共識未確認不得往下」已由 Spec §6 站 1 出口承接 | t04-inventory.md AM-13；ADR-NP-007；Spec §6 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-031 | 作廢 | 舊 A-15 執行層機器規則必須入文本項不再生效；第一階段無 scripts，無「執行層機器規則」可列，文件與實務不得漂移精神已入 SC#8 | t04-inventory.md AM-17；Spec SC#8 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-032 | 作廢 | 舊 A-9 R8 審核官成本方案本項不再生效。**本項【未】處理**——子代理模型選型綁舊機器；待 A-9 新機制（見 SK-07/AM-10/AM-11 待裁示草案）落地後另議費用，本裁示不預先決定新方案 ⚠️ **2026-08-08 更正**：A-9 族已裁定作廢（SC-DEC-RETIRE-038），本條所述「待 A-9 新機制落地後另議」之前提消滅；本條因此無後續費用議題 | t04-inventory.md AM-18；spec-additions.md SP-11 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-033 | 作廢 | 舊 A-22 兩廠共識 FAIL＝自動修正迴圈入口本項不再生效；兩廠共識隨 ADR-NP-007 消滅，「FAIL 不是終點、修完要復驗」已由 Spec §5.2 結案條件「修復必須復驗」承接 | t04-inventory.md AM-25；ADR-NP-007；Spec §5.2 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-034 | 作廢 | 舊 A-23 executor session 輪替紀律本項不再生效；Devin session XL／輪替生態消滅，新制 dispatch sub-agent 每次 fresh-context，無長壽 session 可輪替 | t04-inventory.md AM-26 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-035 | 作廢 | 舊 A-31・A-32 編號說明（跳號佔位）本項不再生效（原文照留於舊檔供查閱）；兩條本來就不存在，本裁示僅為防編號重用之歷史說明，不影響現行規則 | t04-inventory.md AM-35 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-036 | 作廢 | 舊 A-36 全域矛盾稽核本項不再生效；為一次性稽核紀錄（9 條已改），無現行規範力 | t04-inventory.md AM-38 | 彥揚 | draft |
| 2026-08-06 | SC-DEC-RETIRE-037 | 作廢 | 舊 A-37「不矛盾但完全錯誤」稽核本項不再生效。**本項【未】處理**——為一次性稽核紀錄，其「斷言拿去撞真實世界」查證方法值得記取但未編碼為現行機制 | t04-inventory.md AM-39 | 彥揚 | draft |
| 2026-08-08 | SC-DEC-RETIRE-038 | 作廢 | 舊 SK-07／AM-10／AM-11（A-9 派工令獨立審核官族，含 R3 取證權）本項不再生效，不搬入 station-command spec；`spec-additions.md` SP-11「派工令獨立審查」**不採納**。① Pocock 六份原文中唯一的第三方覆核是 `code-review/SKILL.md` 的兩軸平行 sub-agent，發生在**實作完成後**（站 5）；「派工前覆核」在六份原文中零命中。② 使用者原話 S4 為 `"Execute with S3."`、S5 附註 `"S4 S5 gives high autonomy to Ai."`，亦無此關卡。③ 方向相反——使用者原話 S3：`"Always design Red light to prevent Ai cheating."`，防作弊要看**產物**才抓得到，看派工令抓不到。④ A-9 唯一有效成分（角色分離）已被 Spec §6／§5.2「verifier ≠ executor」完整吸收，無殘留 | t04-inventory.md SK-07／AM-10／AM-11；migration-map.md 分歧#1；spec-additions.md SP-11；Spec_station-command_v1.11.md §9.1 | 彥揚 | draft |
| 2026-08-08 | SC-DEC-RETIRE-039 | 作廢 | 舊 SK-18（站 3 出口 gate 兩廠×三軸）本項不再生效，不搬入 station-command spec；`spec-additions.md` SP-12「第三軸：過度設計/複雜度審」**不採納**。① `code-review/SKILL.md` 明訂兩軸且逐字寫死：`"Do **not** merge or rerank findings — the two axes are deliberately separate"`，加第三軸即違反原文。② 三軸中的「過度設計」已有家——在 Standards 軸 Fowler baseline，逐字：`"**Speculative Generality** — abstraction, parameters, or hooks added for needs the spec doesn't have."`。③ 位置也錯——`to-tickets/SKILL.md` 的站 3 出口原文是 `"### 4. Quiz the user ... Iterate until the user approves the breakdown."`，站 3 出口是使用者核准，不是機器三軸審。④ 兩廠部分早由 ADR-NP-007 廢止 | t04-inventory.md SK-18；migration-map.md 分歧#3；spec-additions.md SP-12；Spec_station-command_v1.11.md §9.1 | 彥揚 | draft |
| 2026-08-08 | SC-DEC-RETIRE-040 | 作廢 | 舊 AM-16（A-14 忙碌不等於進展）本項不再生效，不搬入 station-command spec；`spec-additions.md` SP-10「忙碌未進展警示」**不採納**。① 六份 Pocock 原文與使用者 S1–S5 原話皆零命中。② `grilling/SKILL.md` 的 "frontier" 是設計樹推進機制，不是停滯警示，不得援引為本條原文依據。③ 面板不加新指標，維持 Spec §4.1 現有「停滯票數（24h 無事件）」字卡欄位不動，本輪不動。**附註**：「看得到進度」仍是使用者新需求第 2 條的要求，但其依據換成新需求本身，非 A-14 之繼承——依據換了，日後設計不必照 A-14 原樣 | t04-inventory.md AM-16；migration-map.md 分歧#5；spec-additions.md SP-10；Spec_station-command_v1.11.md §9.1 | 彥揚 | draft |

---

## Part B · 仍生效類、需寫入 DECISIONS.md 的條目（2 條，非作廢，供 T-05 落地完整性佐證）

> 此二條屬「仍生效」分類（見 `migration-map.md`），非本檔主體「作廢紀錄類」範疇，因其內容是方法論／維護準則而非狀態機規則，天然歸屬 DECISIONS.md 而非 Spec 條文。仍沿用七欄表格格式一併列出，維持單一檔案可查。

| 日期 | ID | 類型 | 裁示內容 | 依據 | 裁示人 | 狀態 |
|---|---|---|---|---|---|---|
| 2026-08-06 | SC-DEC-ADOPT-001 | 拍板 | 沿用舊 A-25 writing-great-skills 三心法（修剪冗詞／指引詞優先於長段落／完成標準明確化）作為新 plugin 四份 SKILL.md 的維護準則；Spec §2 白名單管動作邊界，本條例管寫法品質，兩者互補不重疊 | t04-inventory.md AM-28 | 彥揚（依 T-04/T-05 盤點提交，待 PR 確認） | draft |
| 2026-08-06 | SC-DEC-ADOPT-002 | 拍板 | 沿用舊 A-34「需要在無觸發時就生效的規則必進必讀層」之配置判準，作為後續任何新規則決定放進 Spec 正文／protocol.md 必讀層／DECISIONS.md 個案記錄三者之一時的裁決依據；本次 T-05 逐條落點判斷即依此準則執行 | t04-inventory.md AM-34 | 彥揚 | draft |

---

## Part C · 2026-08-08 站 4 實作期裁示（6 條裁示＋1 條待裁示）

> 類別 token 沿用本 repo 既有慣例（`SC-DEC-<類別>-NNN`，先例：BOT／ISO／RETIRE／ADOPT）。本節條目同屬 draft，走 §8 PR 路徑生效；末條為**待裁示**，僅記錄 finding，不預作選邊。

| 日期 | ID | 類型 | 裁示內容 | 依據 | 裁示人 | 狀態 |
|---|---|---|---|---|---|---|
| 2026-08-08 | SC-DEC-GATE-001 | 拍板 | T-15a 與 T-15b 對「gate 身分集合為空」判定分歧的裁決：實況為 `build/t15a/station5-check.ps1`（`Test-CloseActorLegit`）空集合回 `Blocking=false`（放行降級），`build/t15b/work-complete.ps1` 要求 `identities.Count -gt 0` 才可能判 complete（fail-closed）。**裁示：採 T-15b 的 fail-closed 方向**，理由具名「寫入端從嚴」；T-15a 於 CI 接線時對齊。本分歧由**異廠交叉檢視**發現（executor＝OpenAI Codex，verifier＝Claude fable） | build/t15a/station5-check.ps1；build/t15b/work-complete.ps1；ADR-NP-009 | 彥揚 | draft |
| 2026-08-08 | SC-DEC-CLI-001 | 修改（修正 ADR-NP-011①） | ADR-NP-011①「否決本機 CLI 路線」之修正：原否決理由逐字「沙盒碰不到本機，每票需使用者當人肉管道，非同步交接成本高於收益」**已被實測推翻**——【量測】`@openai/codex` 0.147.0 可直接 npm 安裝於 Cowork 沙盒內，具備檔案系統與 shell、可自行執行 `/opt/pwsh/pwsh` 測試並迭代；`api.openai.com` 自沙盒回 401（可達，僅缺 key）。**裁示：否決範圍縮限為「跑在使用者本機的 CLI」；跑在沙盒內的 CLI 不在否決之列**。量測依據具名：Codex CLI 於沙盒內完成 T-15b／T-25／T-28／T-29／T-30／T-31 六張票的 executor 工作，每張約 180k tokens 計於 OpenAI 帳，未消耗主 session context。ADR.md 已於同日後加具名修正段（原文照留不刪） | ADR-NP-011①（2026-08-08 修正段）；沙盒實測 | 彥揚 | draft |
| 2026-08-08 | SC-DEC-ROUTE-001 | 修改（部分推翻 ADR-NP-011④） | executor 路由變更：**站 4 實作的 executor 改由 Codex CLI（gpt-5.6-sol，reasoning effort high）承接；Plan 與 Review 維持 Claude（fable）；Commander 職責不變**（ADR-NP-008 只指派不自己做）。理由具名：① verifier ≠ executor 同時成為**真正的異廠交叉檢視**，ADR-NP-011④ 想要的盲點互補由此達成；② 三方分工實測有效——executor（無網路）、Commander（有網路）、verifier（對抗性）各補一塊，T-28 可達性缺陷即由此鏈抓出。⚠️ 本裁示**部分推翻 ADR-NP-011④「站 4 實作維持 Claude」**；ADR.md 已於同日後加具名部分推翻段（原文照留不刪） | ADR-NP-011④（2026-08-08 部分推翻段）；SC-DEC-CLI-001；SC-DEC-GATE-001 之發現鏈 | 彥揚 | draft |
| 2026-08-08 | SC-DEC-DEFER-001 | 拍板 | T-26 的 P-04 待裁示結案：票面（`tickets-loop-draft.md` 第 63 行 What-it-delivers）本身即明列**恰好 9 條語意條目**（§3.4、§5.3b、§7.5、驗收 #7、#17、#25、風險 2、風險 9、§9a），「9 處」指這份枚舉而非字面字串計數，該 9 條已全數涵蓋。**裁示：以票面枚舉結案，不再佔裁示額度** | tickets-loop-draft.md T-26；build/t26/ci-stage-spec.md、deferred-sources.tsv | 彥揚 | draft |
| 2026-08-08 | SC-DEC-ADV-001 | 拍板 | T-28 advisory 之處置：① `key-leak-scan.ps1` 直接執行為零輸出 exit 0（純函式庫）——**裁示：要修**，理由具名「這正是本專案兩次事故（T-12、T-13 的 CLI 靜默 no-op）的形狀」，已補 usage banner；② PS 5.1 專屬慣用法在 pwsh 7 下為「大聲炸」而非假 PASS，README 已釘死平台——**裁示：接受現狀**，記為已知限制；③ Perplexity 無 `GET /models` 端點，其 probe 品質恆為 WARN——**裁示：為預期非缺陷**，已於 fixture 具名 | build/t28/key-leak-scan.ps1（usage banner）；build/t28/README.md；build/t28/fixtures/reachability-2026-08-08.json（Perplexity 列 probeReason） | 彥揚 | draft |
| 2026-08-08 | SC-DEC-REACH-001 | 修改（取代原單層可達性判準） | 可達性判準修正：原判準「回應碼須落 200／401／403／429」**過窄**，會把「伺服器有回應但路徑或方法不對」誤判成連不到。**裁示：改為兩層**——第一層可達性＝有無收到任何 HTTP 回應（只有網路層失敗與 421 proxy 攔截才算不可達）；第二層探測品質＝狀態碼是否落該區間，落區間外判 WARN 非 FAIL。實測結果：REACHABILITY 12/12、PROBE 11/12（Perplexity WARN，預期）。⚠️ Spec v1.11 驗收 #26 原文仍為單層判準——spec 已定稿不改，條文對齊列為下版待辦，現行判準以本條為準 | build/t28/reachability-policy.ps1；build/t28/check-reachability.ps1；build/t28/README.md 兩層判準節 | 彥揚 | draft |
| 2026-08-08 | SC-DEC-PEND-001 | 待裁示 | **T-12 佇列去重鍵不含 payload**（僅記錄，不選邊）：`Add-RunQueueItemIfAbsent`（`build/t12/run-common.ps1`）以 `action+source+target` 判重，而套用端 comment 冪等是 body 全文比對（`build/t21/queue-common.ps1`）。後果：同一 anchor 若在佇列落地前產生兩則**內文不同**的摘要，第二則會被靜默丟棄。現階段無實害（單次 finalize 恰一則），CI 階段多 session 下會變得可能。由 fable verifier 於驗 T-25 時發現 | build/t12/run-common.ps1 `Add-RunQueueItemIfAbsent`；build/t21/queue-common.ps1 comment 現況比對；build/t25/ | —（尚未裁示；發現者：fable verifier） | pending（待彥揚裁示） |
