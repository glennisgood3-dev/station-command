# T-05 · 需補進 Spec_station-command_v1.8.md 的條文（patch 形式）

**用途**：本檔只列「加在哪一節之後、加什麼」，不重寫整份 spec。所有 patch 皆對應 `migration-map.md` 中至少一條 ID。
**狀態分兩類**：
- 標「（已定案）」的 patch：對應條目本身無爭議（T-04 判仍生效且本票同意落點），可直接由 `docs-manager` 併入下一版 Spec。
- 標「（草案，待裁示）」的 patch：對應 `migration-map.md` 的「待人工裁示」列，內容僅供使使用者參考裁決，**不得未經確認就併入正式 Spec**。

---

## SP-0（已定案）· 上游正典 pointer

**加在**：Spec 開頭「> 上游正典＝ADR-NP-001～009 與名詞表…」段落之後（第 12 行後）。
**加什麼**：
> 舊 fleet-command `protocol.md`（Drive，跨專案行為正典）**不隨本次五站重構變動**，持續管轄本 spec 未另行規定的通用執行行為：一級來源紀律（原 A-7／SK-05）、Existing Solutions First／No Inference／NoURL=NoLog／Core 鎖定（原 RED LINES 節）、時間紀律（原 A-12）、根因鐵律與決策不得默默翻案（原 A-33）、必讀層配置判準（原 A-34／A-35）、宣稱上線必有實跑證據（原 A-29.3）。本 spec 僅在 station-command 專屬情境（gate、dispatch、面板）另加規定時才重複或延伸該正典，不逐字複製其原文。

**對應 migration-map ID**：PR-04、SK-05（部分）、AM-08（部分）、AM-14、AM-32（29.3）、AM-36（部分）、AM-37（部分）、PR-09（部分，另見 SP-9）。

---

## SP-1（已定案）· dispatch 前置行為紀律

**加在**：§5.0 Commander No-Hands 段落之後，新增 §5.0a。
**加什麼**：
> ### 5.0a dispatch 前置行為紀律
> 依 protocol.md 一級來源紀律：Commander 對系統現狀的任何斷言（是否已有票、是否已存在解法、當前 gate 狀態等）須直讀 GitHub／DECISIONS.md 原始資料，不得採信摘要或記憶；`/station-run` 派工前之升級／通知內容（§5.3a-i）比照辦理。

**對應 migration-map ID**：SK-05。

---

## SP-2（已定案）· 不可逆動作三步檢查

**加在**：§5.3a「停止條件」清單的條件①之後，作為其細則。
**加什麼**：
> **不可逆動作三步檢查**（deploy／計費／刪資料類，適用 §3.5 第八欄宣告為「有」之票）：① 比對 base 主幹現況；② 自行計算即將造成的實際變更範圍（diff／影響筆數）；③ 若計算範圍與票面宣告範圍不符，停手並具名回報差異，不得逕行執行。

**對應 migration-map ID**：SK-09、AM-05。

---

## SP-3（已定案）· dispatch sub-agent 上限

**加在**：§5.3a 段落之後（或 §2 `/station-run` 白名單列末）。
**加什麼**：
> **dispatch 上限**：`/station-run` 每次 dispatch sub-agent 須綁定 `maxTurns` 上限，具體數值依任務複雜度設定並具名理由；此為單次 dispatch 的內層防線，與 loop 停止條件②（rework 2 次仍 fail，外層防線）不互相取代。

**對應 migration-map ID**：SK-21。

---

## SP-4（已定案）· 升級／通知內容格式

**加在**：§5.3a「痕跡與通知」段落之後，新增 §5.3a-i。
**加什麼**：
> ### 5.3a-i 升級／通知內容格式（`sc:awaiting-user`）
> 任何觸發停止條件②③④的推播通知，內容須含：① 一個具體問題 ② 預先分析過的選項（含各自代價）③ 不處理的代價 ④ 信心度。措辭須用白話、避免未定義術語。通知前 Commander 須先自查三問：這是否真的需要打斷使用者？是否已有現成先例可套用？信心是否足以自行選一個選項並僅請使用者否決？三問皆能自答則優先採用「先做＋可否決」模式，僅在無法自答時才升級為「待你」二分（阻塞待決 vs 可續跑僅供知會）。

**對應 migration-map ID**：AM-06、AM-22、AM-24（子條）。

---

## SP-5（已定案）· blocker 每次複查

**加在**：§6「全站（每次 gate 均查）」列，追加一項。
**加什麼**（追加至該列 checklist）：
> 既有 `sc:blocked` 是否仍成立——每次 gate 執行須重新核對，不成立即具名解除，不得放任過期 blocker 累積。

**對應 migration-map ID**：AM-19。

---

## SP-6（已定案）· 判例回寫

**加在**：§8 段落之後。
**加什麼**：
> **判例回寫**：每筆 DECISIONS.md 裁示落檔後，裁示人應追問「此類情境未來是否會重複出現」；若是，應同批或另開條目將其列為常設判準（類型＝拍板），不留待每次重新請示。

**對應 migration-map ID**：AM-21、AM-24（子條）。

---

## SP-7（已定案）· 授權邊界不可外推

**加在**：§8 段落之後（可與 SP-6 同段落）。
**加什麼**：
> **授權邊界不可外推**：任一 DECISIONS.md 條目僅涵蓋其裁示內容欄**字面具名**之標的，用掉即消耗；不得援引至未具名之相似情境。如需擴大適用範圍，須開新條目具名擴大範圍，或載明「適用於同類情境」字樣。

**對應 migration-map ID**：AM-15、AM-24（子條）。

---

## SP-8（已定案）· DECISIONS.md 類型擴充（作廢／外部審核回應）

**加在**：§8「DECISIONS.md：…欄位『類型（拍板／修改／豁免）』」定義句之後。
**加什麼**：
> 類型欄擴充為「拍板／修改／豁免／**作廢**／**外部審核回應**」：
> - **作廢**：標記舊規則（多來自舊 fleet-command 三份文件）不再生效，裁示內容須含「本項不再生效」字樣，並具名新機制承接位置；若無承接，須加註「本項【未】處理，僅留存歷史紀錄」。
> - **外部審核回應**：記錄對外部（非本團隊）審核意見的逐條處理過程與結論，含被否決的意見與理由，供稽核回溯（依 A-29.4）。

**對應 migration-map ID**：AM-32（29.4）。此 patch 亦是 `decisions-additions.md` 得以使用「作廢」類型七欄表格的依據，**應優先於 T-05 其他 DECISIONS.md 落地動作併入**。

---

## SP-9（已定案）· repo 規範文件起始模板來源

**加在**：§5.2「兩份基線的正典位置」段落之後（第 172 行後）。
**加什麼**：
> **建議來源**：新專案首次撰寫 repo 規範文件時，可比照舊 protocol.md §K CODING BEHAVIOR 四律（Think before acting／Simplicity／Surgical edits／Goal-driven）為起始模板；四律原文正典仍在 protocol.md（Drive），本 spec 不重複收錄。

**對應 migration-map ID**：PR-09。

---

## SP-13（已定案）· gate／verifier 報告輸出格式

**加在**：§6（各站出口條件表格）之後。
**加什麼**：
> **gate／verifier 報告輸出格式**：任何 gate 或 verifier（含站 4 tester、站 5 兩軸 sub-agent）產出的判定報告，**首行**必須是且僅是 `PASS` 或 `FAIL` 二擇一（不得用「大致通過」「基本完成」等模糊詞），其後方可接理由與細節。

**對應 migration-map ID**：AM-23。

---

## SP-10（不採納，2026-08-08 裁示）· 忙碌未進展警示

**加在**：§4.1 字卡欄位「停滯票數」定義之後。
**加什麼**（草案文字，**未經使用者確認前不得併入正式 Spec**）：
> **（草案）忙碌未進展警示**：與「停滯票數」（24h 無事件）不同義的另一種紅燈——同一票經 gate 判定 rework ≥2 次仍 fail（即觸及 §5.3a 停止條件②）但仍持續有 assignee／commits，字卡具名標「忙碌未進展」。

**裁示結果**：不採納（彥揚，2026-08-08）。六份 Pocock 原文與使用者 S1–S5 原話皆零命中；`grilling/SKILL.md` 的 "frontier" 是設計樹推進機制，不是停滯警示，不得援引為本條依據。面板不加新指標，維持 Spec §4.1 現有「停滯票數（24h 無事件）」欄位不動。詳見 `decisions-additions.md` SC-DEC-RETIRE-040。
**對應 migration-map ID**：AM-16（見 `migration-map.md` 分歧#5）。

---

## SP-11（不採納，2026-08-08 裁示）· 派工令獨立審查

**加在**：§5.1 路由表之後。
**加什麼**（草案文字，**與 ADR-NP-010 站 4／5「一律不問」存在潛在張力，未經使用者確認前不得併入正式 Spec**）：
> **（草案）派工令獨立審查**：`/station-run` 於 dispatch 前，由**非 Commander、非該票 verifier、非該票 executor** 之第三方（如另一 fresh-context sub-agent）覆核派工令的 executor＋basis 是否合理，通過方可 dispatch；覆核意見具名附於票留言。

**裁示結果**：不採納（彥揚，2026-08-08）。Pocock 六份原文唯一的第三方覆核（`code-review/SKILL.md` 兩軸平行 sub-agent）發生在實作完成後（站 5），派工前覆核零命中；使用者原話 S4「Execute with S3.」、S5「S4 S5 gives high autonomy to Ai.」亦無此關卡；防作弊方向相反——使用者原話 S3「Always design Red light to prevent Ai cheating.」，看產物才抓得到，看派工令抓不到；A-9 唯一有效成分（角色分離）已被 §6「verifier ≠ executor」吸收。詳見 `decisions-additions.md` SC-DEC-RETIRE-038。

**對應 migration-map ID**：SK-07、AM-10、AM-11（見 `migration-map.md` 分歧#1）。

---

## SP-12（不採納，2026-08-08 裁示）· 第三軸：過度設計/複雜度審

**加在**：§5.2「兩軸」定義之後（**非** T-04 原建議的 §6 站 3，理由見 `migration-map.md` 分歧#3）。
**加什麼**（草案文字，**未經使用者確認前不得併入正式 Spec**）：
> **（草案）第三軸：過度設計/複雜度審**——若使用者認為現行軸 A 的 12 條 Fowler 基線（已含 Speculative Generality，見 `assets/fowler-smells.md` #9）不足以覆蓋舊 SK-18「過度設計」深審的力度，可另開軸 C，同環境 fresh-context sub-agent，輸入僅 diff＋設計簡潔性判準。

**裁示結果**：不採納（彥揚，2026-08-08）。`code-review/SKILL.md` 明訂兩軸且逐字寫死「Do **not** merge or rerank findings — the two axes are deliberately separate」；三軸中的「過度設計」已有家，在 Standards 軸 Fowler baseline「**Speculative Generality** — abstraction, parameters, or hooks added for needs the spec doesn't have.」；位置也錯——`to-tickets/SKILL.md` 站 3 出口原文是「### 4. Quiz the user ... Iterate until the user approves the breakdown.」，站 3 出口是使用者核准，不是機器三軸審。詳見 `decisions-additions.md` SC-DEC-RETIRE-039。
**對應 migration-map ID**：SK-18（見 `migration-map.md` 分歧#3）。
