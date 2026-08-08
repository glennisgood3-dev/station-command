---
title: "station-command Plugin Spec v1.11（定稿）"
description: "五站生產線的薄編排層 Cowork plugin：狀態機 gate、GitHub 真相源、常駐面板、兩層 executor 路由"
status: pending
priority: P1
effort: 1 週（4 skills ＋ 面板 ＋ 路由表）
branch: n/a
tags: [station-command, cowork-plugin, five-stations, github-source-of-truth]
created: 2026-08-05
---

> 上游正典＝ADR-NP-001～011 與名詞表；**本 spec 不推翻任何 ADR**。站 5 依 ADR-NP-007、Commander 角色依 ADR-NP-008、timeline 歸因階段性啟用依 ADR-NP-009、異廠 executor 路由依 ADR-NP-011。
> 前幾輪審查的處置沿革寫 CHANGELOG，本檔只留現行條文與本輪審查回應（§12）。
> **v1.11 依 A-28 Pocock 至上條款（Pocock 原文 ＞ A-24 條文轉述 ＞ 其餘本地條文）回頭取證 `mattpocock/skills` 原文重判**：更正 §6 站 4 紅燈定義的來源標註、補採 §5.2 refactor 歸屬與 §5.1 站 1 問答邊界兩條漏採原文、於 §9.1 具名記載三條舊 fleet 條文作廢、更正 §5.1 Gemini 免費層計費事實。條文層級的實質變更皆在本輪，故起新版本號而非就地改 v1.10。

**本 spec 內定義的名詞**（提請補入名詞表）：
- **Commander**＝主 session 編排者，即發起 dispatch 的 Claude 主對話本身。
- **gate 執行身分**＝plugin 呼叫 GitHub API 所用的 identity，**依 ADR-NP-009 分兩階段**：① **手動階段（現行）**＝使用者本人身分（Cowork 取不到 ≠ 使用者的身分，已實測具名）⇒ **不成立機器歸因**，初始化與每次 gate 須具名回報當前身分，不作 fail 條件；② **CI 階段**＝`github-actions[bot]`（原生 ≠ 使用者帳號，強制）⇒ §3.4 全套歸因生效。兩階段身分皆具名記於 plugin repo 的 DECISIONS.md。
- **executor**＝ak-engineer 的 agent／skill 名稱（非 GitHub 帳號）。其唯一真相源是**票 body 的 `executor` 欄位**；GitHub `assignee` 只承載「已開工」的二元訊號，不承載 executor 身分。

## 1. Goal / Scope / Success Criteria

**Goal**：提供一個薄編排層 plugin，讓多個專案在 GitHub 上以「五站生產線」推進，狀態可查、gate 不可跳、派工有 basis、進度在 Cowork 側邊欄常駐可見。

**Scope In**：五站狀態機與各站出口條件｜GitHub milestone／label scheme ＋ 票模板（真相源）｜常駐面板 artifact（跨 repo 聚合、一工作一字卡、含 plans/ 對帳）｜兩層 executor 路由表｜進線入口（native 新建與 legacy 收編）｜**異廠 executor 路由（provider 維度、異廠交叉檢視、成本邊界）**｜**站 4／5 自主派工循環與排程喚醒**｜**待寫佇列**（寫入斷點期間）｜各專案 repo 的 DECISIONS.md／CHANGELOG.md 模板

**Scope Out**：任何實作能力（拆票、寫碼、審查、測試）全部 dispatch 給 ak-engineer，不複製任何 skill（ADR-NP-001）｜第二份狀態檔與任何自建簿記協定（ADR-NP-002）｜CI workflow 本體、外部廠 AI 接入路徑、`sc:dual-vendor` label（皆列升 CI 階段，見 §9a）｜hooks（Cowork 不可靠）｜protocol 層跨專案正典（照舊 Drive，ADR-NP-004）

**Success Criteria**（可驗證）
1. **零狀態複製**：plugin 不落任何持久化**狀態**檔；工作站別只能從 primary anchor 的 label ＋ 其 timeline 讀出。**兩項具名例外，皆非真相源、皆不參與 gate 判定**：① 面板 artifact 內的顯示快取（§4.2）；② 手動階段的待寫佇列檔（§4.6）。刪除面板快取後重跑 `/station-board` ⇒ 字卡內容與刪除前一致（僅消失偵測降級，§4.4）。
2. **站序不可跳**：任一工作從站 N 跳到站 N+2 ⇒ gate 拒絕並具名未滿足的出口條件。以 1→3、2→4、3→5 三組驗證，三組全拒。
3. **無 basis 即無效**：票缺 executor 或 basis ⇒ 站 3 gate 判 `[INVALID]` 並具名票號，fail-closed（非 warn）。
4. **錯誤不靜默**：查詢失敗／結果縮水或觸頂／面板寫入失敗 ⇒ 各自的具名告警（§4.4），且不得把失敗顯示為「無工作」。以斷網、假 repo 名、人為觸頂、面板寫入失敗四情境驗證。
5. **legacy 可辨識**：收編中工作字卡帶 `legacy` badge，只在通過第一個 native gate 後消失。
6. **雙審輸入分離可證、隔離未證須具名**：站 5 兩軸 sub-agent 各自只收到 §5 規定的輸入集合，兩份報告獨立留存未合併（以 prompt 輸入清單與報告核對）。**且**在 plugin repo 的 DECISIONS.md 出現具名的隔離實測結論條目（§5）之前，每份站 5 gate 結案報告必須含固定字串「context 隔離未實測，本結論僅由輸入分離支撐」；缺標註 ⇒ gate fail。
7. **狀態 label 寫入單點（兩層判準）**：①**機器層**——任一 `sc:` 狀態 label 的最後一次 `labeled`／`unlabeled` timeline 事件，actor 必須是 gate 執行身分；②**規範層**——四個 SKILL.md 中只有 gate 得含寫狀態 label 的指示，其餘三個明文禁止。⚠️ **①機器層標註「CI 階段生效」（ADR-NP-009）**：其成立前提是執行身分 ≠ 使用者互動帳號，該條件手動階段不可得。**手動階段以②規範層為準**，並以每次 gate 報告具名當前身分補足可稽核性（驗收 #6、#17a）。即便進入 CI 階段，四個 skill 仍共用同一身分，機器層只能證「非人手直接改」、證不了「哪個 skill 寫的」，故規範層恆不可省。
8. **薄度可量**：skill 數 ≤ 5，且每個 skill 的實際行為不超出 §2 的**逐 skill 允許動作白名單**（人工審 SKILL.md 逐條核對）。

## 2. Plugin 元件清單與動作白名單

結構：標準 plugin manifest ＋ 每個 skill 一個 SKILL.md 目錄（user-invocable ⇒ 自動成為 /slash-command）。無 hooks、無 scripts（第一階段）。原則：**能少一個 skill 就少一個**。

| Skill | 職責 | **允許動作白名單（超出即違反 SC#8）** |
|---|---|---|
| `/station-board` | 跨 repo 聚合（按 work ID）、建立／就地更新面板 artifact、輸出文字摘要；完整模式並起 `project-manager` 對帳。**唯一寫面板的實作點**（無對帳模式供 run／gate 呼叫，§4.5） | 讀 GitHub（search／issues／timeline／issue body 欄位）｜讀本機 `plans/`｜**讀待寫佇列檔（§4.6）**｜**dispatch `project-manager`（僅完整模式對帳）**｜寫面板 artifact｜文字輸出。🚫 不寫 GitHub 任何欄位 |
| `/station-run` | 驗站別歸因合法（§3.4）→ 選出下一個可動作項 → 依路由表定 executor＋basis 並**寫入票 body 的 executor 欄位** → dispatch；**以指派 assignee 作為二元開工訊號**；dispatch 失敗 ⇒ **立即移除該 assignee** 並具名回報；結束時呼叫面板無對帳刷新。**loop 模式（§5.3a，手動階段生效）**：持續「選件→派工→收件→判 gate→續派」，直到六條停止條件之一成立。⚠️ 「經使用者確認後 dispatch」**僅適用站 1／2／3 的人類 gate**（共識確認、spec 確認、拆票 quiz）；**站 4／5 的內部 dispatch 不再逐次確認** | 讀 GitHub｜**寫／移除 assignee**｜**寫票 body 的 executor／basis 欄位**｜寫人讀留言｜dispatch sub-agent｜**呼叫 gate**（判 gate 與產生 label 類佇列項）｜**寫自己權責內的佇列項（assignee、留言）**｜呼叫 board 無對帳模式。🚫 不寫任何 label、不開關 issue、不產生 label 類佇列項 |
| `/station-gate` | 跑當前站出口條件（§6），逐條 ✓／✗；全過才寫下一站 label，未過具名缺項並拒絕推進；**唯一寫狀態 label 者**；站 5 通過後關票、工作全完成後收尾（§3.2）；含初始化路徑（§6.1）與復位模式（§3.4） | 讀 GitHub＋timeline｜讀全參與 repo 的 DECISIONS.md｜**讀 plugin repo 的 DECISIONS.md**（SC#6 解除條目、gate 執行身分宣告）｜**寫狀態 label**｜**關／開 issue、關 milestone**｜寫人讀留言｜dispatch 審查／verifier／`docs-manager`／`git-manager` sub-agent｜呼叫 board 無對帳模式 |
| `/station-intake` | **native**：建 milestone ＋ primary anchor issue，產「定站站 1」結論。**legacy**：**共用同一套建立步驟**，再起 fresh-context auditor 定站退回、產補件清單與豁免草案。兩模式皆不自己落狀態 label，改呼叫 gate 初始化路徑 | 讀 GitHub｜**建 milestone**｜**建 issue 並附類型 label `sc:work`**｜dispatch auditor｜呼叫 gate 初始化路徑。🚫 不寫任何狀態 label |

**白名單與 No-Hands 的邊界（§5.0）**：上表四個 skill 的動作全屬**編排動作**（讀→驗→決→派→記），不是 deliverable 產出，故不受 No-Hands 禁令限制。判別法：動作的輸出若是**由既有資料機械性推導而得、無創作裁量**（查 GitHub、判 gate 條件、算面板、寫 label／assignee、派工），即為編排；若需要撰寫內容（程式、規格文字、票內容、測試、審查判斷），即為 deliverable，一律 dispatch。
🔴 **面板 HTML 的裁定**：面板由 `/station-board` 從 GitHub 現有資料**機械性 render**（欄位對應固定、無內容創作）⇒ **屬編排輸出，不屬 No-Hands 管轄的 deliverable**，主 session 得直接產生。反之，若日後面板要加入「由 AI 撰寫的摘要／建議文字」，那部分即為 deliverable，須 dispatch。

**為何 native 併入 intake**：兩模式產出物相同（定站結論＋初始化清單）、建立步驟相同、落 label 路徑相同；另立 `/station-new` 會複製 milestone／anchor 建立邏輯（違反 DRY）。以模式參數區分即可。
不做的 skill：`/station-status` 併入 board 文字摘要｜`/station-next` 併入 run 無參數行為｜`/station-ticket` 是 run 在站 3 的 dispatch 結果。

## 3. 資料模型（GitHub＝真相源）

### 3.1 work、primary anchor 與 milestone
- **work**：以 **work ID**（`W-<slug>`，全艦隊唯一）識別。**work ID 是聚合唯一鍵；milestone 名稱僅供顯示**。
- **primary anchor issue**：每工作**有且僅有一張**，住在具名的 **primary repo**；帶 `sc:work`，body 宣告 primary repo 與**參與 repo 全集**（此宣告即 repo 全集的真相源，面板不另猜）。**`sc:station-*` 只存在 primary anchor 上**（其他 issue 上出現一律視為髒資料並具名示警）；其餘狀態 label 的合法載體逐條見 §3.3。
- **milestone**：每個參與 repo 各建一個同 work 的 milestone，description 首行帶 `work-id` 與 `primary-anchor`（repo#issue）。只負責分組與**原生進度百分比**。
- **ticket（票）**：站 3 產出的 Issue，指派到所在 repo 的對應 milestone，帶 `sc:ticket`。

### 3.2 站別粒度（work 級 vs 票級）
- **票不帶 station label**。票級站別由狀態推導：open 且無 `sc:red-proven`＝站 4；open 且有 `sc:red-proven`＝站 5；closed＝該票完成。
- **work 站別（anchor 上的 label）＝全體未關閉票的最小站**；work 進站 4 後，gate 每次執行重算並寫回 anchor。站 4／5 的推進與雙審**以票為單位**；`sc:red-proven` 落在**票**上。
- 站 1／2／3（尚無票）：可動作項＝work 本身，開工訊號與時間軸落 **primary anchor**。
- **完成態（唯一斷點條件）**：當該 work 的 open 票數為零 **且**每一張票都是經站 5 gate 通過而關閉（非人手關閉）⇒ gate 寫 `sc:station-done`、**關閉 primary anchor、關閉全參與 repo 的對應 milestone**。⚠️「未關閉票的最小站」在零票時無定義，故完成態由本條判定，不由最小站公式推導。若 open 票數為零但存在人手關閉的票 ⇒ 不得判完成，落 `sc:awaiting-user` 交使用者裁示（重開該票或具名豁免）。

### 3.3 Label scheme 與唯一寫入者
**不變式**：類型 label 於建立時寫入且此後不可變；**所有狀態 label 的寫入者只有 `/station-gate`**（判準見 SC#7）。

| Label | 合法載體 | 用途 | 寫入者 |
|---|---|---|---|
| `sc:work` | anchor | 節點類型（不可變） | 建立者（intake） |
| `sc:ticket` | 票 | 節點類型（不可變） | 建立者（站 3 拆票 dispatch） |
| `sc:station-1` … `sc:station-5`、`sc:station-done` | **僅 anchor** | work 站別（互斥） | gate |
| `sc:legacy` | 僅 anchor | 收編中，未通過第一個 native gate | gate |
| `sc:red-proven` | **僅票** | 兩段證據已由 verifier（≠ executor）實測通過。缺席即未證明，不設反面 label | gate（依 verifier 實測） |
| `sc:blocked` | anchor **或**票 | 有未解 blocker（含跨站繼承）⇒ 紅燈 | gate |
| `sc:gate-fail` | anchor **或**票 | 最近一次 gate 未過 ⇒ 紅燈 | gate |
| `sc:awaiting-user` | anchor **或**票 | 等待使用者確認或裁示 ⇒ 黃燈 | gate |

**不引入的 label**：`sc:exec-*`（executor 身分住票 body 欄位，label 與 assignee 皆不承載）｜`sc:red-pending`（互斥雙 label 必漂移）｜`sc:dual-vendor`（無人可寫可摘、且外廠管道不存在 ⇒ 延至升 CI 階段；逃生口改由 DECISIONS.md 條目承載，見 §5）。

### 3.4 站別歸因與復位（原生 timeline，無自建簿記）
🔴 **階段性生效（ADR-NP-009）**：本節機器歸因判準與復位模式為 **CI 階段規格**。**手動階段不生效**（執行身分即使用者本人，actor 無從區分人手與 gate），改由**規範層＋人工複查**代位，每次 gate 報告須具名當前身分。
- **歸因判準**：讀 primary anchor 的 issue timeline，取當前 station label 最後一次 `labeled` 事件的 **actor 與時間**（GitHub 原生記錄）。actor ∈ gate 執行身分 ⇒ 合法；否則為人手直接改。
- **不合法時**：board 紅燈標「站別來源不明」；**`/station-run` 拒絕選件**，要求先跑 gate 復位模式。
- **gate 復位模式**：① 沿 timeline 回溯，找**最後一次合法** `labeled` 事件所設站別 ⇒ 回退至該站並具名回報回退理由與事件時間；② 若整條 timeline 無任何合法事件 ⇒ 落 `sc:awaiting-user`、停止推進、交使用者裁示。**復位只讀 timeline、不採信當前 label 值**，故不循環。
- **站別推進＝單一動作**：舊站 label 的移除與新站 label 的加入，必須以**一次「設定完整 label 集合」的 API 呼叫**完成，🚫 不得拆成 remove ＋ add 兩步（中間態會讓 anchor 短暫無站別或雙站別）。回驗時比對的也是**完整 label 集合**，不是單一 label 是否存在（§4.4）。
- 🚫 **不建立任何自建簿記（gate 紀錄留言、狀態檔）作為判準**。gate 得留人讀留言，但**留言不參與任何判定**——單一寫入動作即完成狀態變更，無「label ＋ 留言」雙寫的原子性問題。

### 3.5 票模板欄位（站 3 產出，全部必填）
`REQ-ID`｜**驗收條件**（可執行：怎麼跑、看什麼輸出算過）｜`depends_on`（可為空但欄位必須在）｜`executor`（ak-engineer 的 agent／skill 名，**本欄為 executor 身分的唯一真相源**）｜`basis`（一句話；覆寫預設須說明理由）｜`scope`（供 merge 判準⑤ 比對）｜**測試先行**（紅燈測試長什麼樣；不可自動測時寫人工驗法與證據形狀；**另須具名 ① 本票測試打在哪個 seam、② 獨立預期值來源**，見下註 B、註 C）｜**不可逆動作：有／無 ＋ 說明**（deploy／刪資料／對外寄送／付費／開權限；供 §5.3a 停止條件①判定）。

**八項任一缺漏 ⇒ 站 3 出口 gate fail**（缺 executor／basis 判 `[INVALID]`）。臨時換 executor ⇒ `ESCALATE`，需使用者裁示並補 basis。⚠️ 註 B、註 C 是**第七欄的內容要求，不新增第九欄**——欄位總數仍為八。

**註 B · seam 須事前寫下並經使用者確認（v1.11 補採漏採原文）**
依 Pocock `skills/engineering/tdd/SKILL.md`（Seams — where tests go）逐字：
> "Test only at pre-agreed seams. Before writing any test, write down the seams under test and confirm them with the user. No test is written at an unconfirmed seam."

- 票的「測試先行」欄須**寫下本票測試打在哪個 seam**；該 seam 須**經使用者確認**——確認動作**併入站 3 既有的拆票 quiz 人類 gate**（§6 站 3），🚫 **不另立獨立的 seam 審查步驟**（原文的 quiz 本來就是同一個人類關卡，多開一關等於憑空多一個 gate）。
- 🚫 **本 spec 不規定 seam 的判定標準與清單格式**：原文只要求「寫下來、跟使用者確認過」，超出部分**未定，待實作票處理**（見「未解問題」7）。

**註 C · 預期值須來自獨立真相源（v1.11 補採漏採原文；追認既有票面實務）**
依 Pocock `skills/engineering/tdd/SKILL.md`（Anti-patterns · Tautological）逐字：
> "Expected values must come from an independent source of truth — a known-good literal, a worked example, the spec."

- 票的「測試先行」欄須**具名獨立預期值來源**（known-good literal／worked example／spec 三者之一或等價物）。⚠️ 本條屬**追認**：既有票面早已逐票填寫「獨立預期值來源」欄，但條文層零命中——實務先行、正典缺位，正是 ADR-NP-010 記錄的那種「需求無人安置」成因形狀，本輪補位。
- **驗收落點在站 4**（§6 站 4：verifier 須查預期值非由被測程式自身產生）。
- 🔴 **與註 A（S3 防作弊）同源不同落點**：註 A 管紅燈的**型態**（要斷言失敗、不要載入失敗）；本註管斷言的**預期值出處**（不得自證）。**兩條合起來才蓋滿 S3 "Always design Red light to prevent Ai cheating"**——只管型態擋不住自證式斷言，只管出處擋不住根本沒跑到斷言。

## 4. 面板規格

### 4.1 載體與字卡
自包 HTML artifact，就地 update，跨 session 存活（ADR-NP-003）。**一 work 一張字卡**，欄位一律由「跨 repo issue search（含隨結果附帶的 issue body 欄位）＋ milestone 原生欄位 ＋ timeline」算出，**不解析任何 repo 內檔案、不發額外查詢**（唯一具名例外：手動階段讀本機待寫佇列檔以顯示「待寫 N 筆」，§4.6）：

工作名 ＋ work ID｜primary repo ＋ 參與 repo 清單（取自 anchor body 宣告）｜所在站｜**逐 repo 分列的 milestone 原生進度百分比**（不加權、不合成單一數字）｜**當前 executor（讀票／anchor body 的 `executor` 欄位，不讀 assignee）**｜狀態燈｜**在跑數量**（open、站 4／5 且**已有 assignee**的票數）｜**停滯票數**（該 issue timeline 最新事件距今逾 **24 小時**）｜`legacy` badge｜對帳資料時間（未對帳時標「本次未對帳，沿用 <時間> 結果」）｜最後成功完整同步時間。

**狀態燈**：紅＝`sc:blocked`／`sc:gate-fail`／對帳異常／髒 label／站別來源不明／anchor 消失；黃＝`sc:awaiting-user`；綠＝以上皆無。
🚫 字卡不放需逐 repo 抓檔解析的資訊（豁免明細、逃生口統計一律走 gate／intake 文字輸出）。

### 4.2 聚合邏輯與顯示快取
一次跨 repo issue search 撈 `sc:work` 與 `sc:ticket` 的 open issues，按 milestone description 的 work ID 分組；站別只採 primary anchor。
**顯示快取**：上次成功完整同步的 work 清單與時間，存於面板 artifact 自身 HTML 的 data 屬性。**它是顯示快取、不是真相源**：只供 anchor 消失偵測的比對基線；遺失或重建 ⇒ 只降級偵測能力（§4.4），不影響任何站別真相與 gate 判定 ⇒ 與 SC#1 相容。

### 4.3 對帳（`/station-board` 完整模式）
**資料路徑**：GitHub 側＝同一次聚合結果（不另發查詢）；`plans/` 側＝`project-manager` 讀當前 session 本機的 `ak-project-management` `plans/`（單一來源，不逐 repo 抓檔）。**範圍與漂移的分界（work 級 vs 票級）**：`plans/` **整個查無此 work** ⇒ 該字卡標「對帳範圍外」（不是漂移，也不得顯示為已對帳綠燈）；`plans/` **有此 work 的紀錄**時，該 work 即進入對帳範圍，其下票級差異一律算漂移。`plans/` 不可用 ⇒ 全部標「對帳未執行」。
**漂移三類**（僅適用於範圍內的 work）：plans 有票 GitHub 無／GitHub 有票 plans 無／同票狀態不一致 ⇒ 字卡紅燈標筆數，明細列文字摘要。
**修復方向無自動優先序**：GitHub 是機器狀態真相源，`plans/` 是計畫敘事 durable source，職責不同，任一方都不預設勝出 ⇒ 只報告不自動修（A-10）；修復方向**逐案由使用者裁示並記 DECISIONS.md**。

### 4.4 一致性與錯誤狀態（硬規則）
- **寫後回驗不經 search**：gate 寫完 label 後以 issues API **直讀 anchor** 確認；不符 ⇒ 重試一次，仍不符 ⇒ 判寫入失敗、具名回報、不宣稱推進成功（search index 為最終一致）。
- **search 僅用於全量聚合**，不用於任何判定。
- **不完整示警**：結果數較上次成功值異常縮水，或觸及 API 上限／分頁截斷 ⇒ 橫幅「資料可能不完整」＋ 具名徵狀 ＋ 上次成功完整同步時間。
- **查詢失敗**：橫幅「數據過期」＋ 失敗對象具名 ＋ 上次成功時間；受影響字卡打灰標「未更新」。
- **anchor 消失＝異常，不是空狀態**：與顯示快取比對，某 work 的 primary anchor 不在本次結果且站別非 `sc:station-done` ⇒ 具名示警「工作消失」＋ work ID ＋ 上次所見站別。**無快取基線時**（artifact 重建）⇒ 橫幅「消失偵測不可用（無基線）」，🚫 不得靜默視為正常。
- **面板寫入失敗**：artifact 建立／更新失敗 ⇒ 立即以文字輸出完整字卡摘要 ＋「面板未更新，畫面內容已過期（上次成功：<時間>）」。
- **空狀態**：查詢成功、零筆、且消失偵測可用且無消失 anchor ⇒ 顯示「目前無 active work」明示卡並附查詢條件。**零筆＋無基線** ⇒ 兩者**並列顯示**：「目前無 active work」卡 ＋「消失偵測不可用（無基線）」橫幅，🚫 不得只顯示其中一個（只留空狀態會把「全部消失」偽裝成「本來就沒有」）。
🚫 禁止靜默失敗、禁止把失敗顯示成空狀態、禁止顯示未標記的舊資料。

### 4.5 刷新時機
`/station-board` 手動＝**完整模式**（聚合＋對帳）。run／gate 結束時的順手刷＝**內部呼叫 board 的無對帳模式**，兩者不各自實作面板寫入（board 仍是唯一寫面板實作點）。無對帳模式下對帳欄位一律標「本次未對帳，沿用 <時間> 結果」。

### 4.6 待寫佇列（手動階段；升 CI 後本節廢止）
**前提分兩層，🚫 勿混為一談（依 ADR-NP-009 修訂版）**：①【**量測**】手動階段 Cowork 對 GitHub **寫不進去**——MCP 寫入端點回 403 `Resource not accessible by integration`、Bash 對 GitHub 的請求被 session proxy 攔截、讀取端點正常。**本節存在的唯一理由是①；① 一旦修復，本節即廢止。** ②【**推論**】即使寫得進去，MCP user-to-server token 的 actor 仍等於使用者本人 ⇒ timeline 歸因不成立——② 屬 §3.4 管轄、**須等 CI 階段**，與本節存廢無關。
**loop 照跑**（讀狀態、派工、收件、判 gate），寫入動作累積成待寫佇列，由使用者擇時以本機腳本一次落地。
⚠️ **宣稱範圍（依 ADR-NP-010⑤ 降級）**：「只有蓋章延後」**僅適用 issue metadata**（推站、發票、關票、label、assignee、留言）。**程式碼產出不適用**——它同樣推不上去且隨 ephemeral container 蒸發，故另立落地路徑（見下）。
- **載體**：使用者本機的具名佇列檔（由套用腳本消費）。**非真相源、不參與任何 gate 判定**；遺失只損失「尚未落地的待寫動作」，GitHub 上已存在的狀態不受影響 ⇒ 降級後果＝該批動作須由 loop 重新產生，**不會造成站別或票狀態錯誤**。
- **產生權**：**佇列項的產生權＝該動作原本的唯一寫入者**——label／開關 issue 類只能由 gate 產生，issue 與 milestone 建立只能由 intake 產生，assignee 與留言由 run 產生。🚫 不得因為「只是寫檔」就繞過 §3.3 的寫入者不變式。
- **佇列項欄位（四欄，各有消費者）**：動作類型（決定套用方式）｜目標（repo ＋ issue／milestone 識別）｜payload（欲寫入的**完整** label 集合／欄位值／開關狀態／留言內文）｜來源票號或 work ID（套用失敗時的回報與人工追查依據）。順序即檔內順序，不另設時間欄。
- **冪等（讀現況比對，不設動作指紋）**：套用前先讀目標現況，已達成 payload 所述狀態者跳過 ⇒ 同一佇列重跑兩次結果相同。**套用後回驗**：逐筆以 issues API 直讀目標，比對完整 label 集合與開關狀態；不符者留在佇列並具名回報，🚫 不得標記為已套用。
- **每輪 loop 開頭對帳**：比對佇列與 GitHub 現況，**已落地項出列**，避免使用者手動落地後殘留造成重複套用。**套用腳本由 dispatch 產生**（屬 deliverable，§5.0），非主 session 親手撰寫。
- **程式碼落地路徑**：站 4 的程式產出以 **patch 檔**形式進佇列，由同一支本機腳本套用到目標 repo 工作區；未套用前該產出**不得**被視為已交付。
- **面板揭露**：佇列非空時字卡顯示「待寫 N 筆」，且**「在跑數量」與「停滯票數」須加註「寫入斷點期間不可信」**（其依據的 assignee 與 timeline 事件尚未落地）。🚫 不得把待寫狀態顯示為已生效。

## 5. Commander 角色與兩層 executor 路由表 v1

### 5.0 Commander No-Hands（依 ADR-NP-008）
**Claude 主 session（Commander）在五站生產線只做五件事：讀 → 驗 → 決 → 派 → 記。** 五站每一站的 deliverable **一律由路由表 dispatch 的 executor 產生**，主 session 不親手產出。

**讀**＝查 GitHub、讀 timeline／DECISIONS.md、讀報告與交件；**驗**＝對照 §6 出口條件逐條判 ✓／✗、回驗寫入、驗歸因合法性；**決**＝判 gate 過否、定站、選件、依路由表定 executor＋basis；**派**＝dispatch 給 ak-engineer 的 agent／skill；**記**＝寫 label／assignee／狀態，**其邊界＝共識文件與裁示紀錄**（ADR、名詞表、DECISIONS.md 條目），不含任何 deliverable。

**受管轄的 deliverable**（必須 dispatch）：程式碼、spec 文字、票內容、測試、審查報告、auditor 報告、對帳分析結論。**不受管轄的編排輸出**：GitHub 狀態寫入、gate 判定結果、面板 HTML（§2 邊界裁定）、「記」邊界內的共識文件與裁示紀錄。

🔴 **違規判定**：Commander 親手產出受管轄的 deliverable ⇒ **該 artifact 無效，必須作廢並重派 executor 產生**；不得以「已經寫好了、內容看起來沒問題」為由留用。理由：留用等於讓禁令只在不方便時生效，而那是它最該生效的時候。

### 5.1 路由表

| 站 | 預設 executor | basis |
|---|---|---|
| 1 grill | `brainstormer`（產題）＋ `advisor`（挑戰取捨）；`ak-brainstorm` | 拷問需要「發散」與「逆向挑戰」兩種人格，同一顆腦袋兩者互相稀釋 |
| 2 spec | `planner` ＋ `ak-plan`（需 `/ak-cli-setup`） | spec 是結構化計畫產物，planner 產出格式穩定、可被站 3 直接消費 |
| 2 出口 gate | `kongming`（fresh context） | 缺口審要求最強推理且不得是產出者本人 |
| 3 tickets | `planner` 拆票 ＋ `kongming` 複核；`ak-project-management` | 垂直切片切錯要到站 4 才爆，複核成本遠低於返工 |
| 3 出口 gate | `code-reviewer`（票集完備性） | 判的是欄位完備與可執行性，屬規範型檢查 |
| 4 implement | `fullstack-developer` ＋ `ak-cook`／`ak-test`；卡關轉 `debugger`／`ak-debug` | 先紅後綠需要真的能跑測試的執行體 |
| 4 驗收 | `tester`（verifier，≠ executor） | 執行者自陳不能當驗收；`sc:red-proven` 依其實測結果落在票上 |
| 5 雙審 | 同環境、平行、fresh-context 的兩個 `general-purpose` sub-agent，各執一軸 | 依 **ADR-NP-007**：隔離靠輸入分離與平行不互通，不靠廠牌 |
| 全站 | `git-manager`｜`docs-manager`｜`Explore`／`ak-scout`｜`project-manager`（對帳） | 支援角色，不佔站別主線 |

🔴 **站 1 問答邊界紀律（v1.11 補採漏採原文；依 Pocock `skills/productivity/grilling/SKILL.md`）**——站 1 的 grill 除了「發散＋逆向挑戰」兩人格外，另受下列兩條原文約束，逐字：
> "Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it — don't ask the user for anything you could look up yourself. ... The _decisions_ are the user's — put each to them and wait."
> "Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round."

- **事實／決策的分界**：**能查得到的事實一律 dispatch sub-agent 自己查，🚫 不得拿去問使用者**；只有**決策**才進問題清單。
- **提問形狀**：整輪 frontier **一次問完**、每題編號、**每題附上建議答案**，然後**等使用者回覆才進下一輪**；🚫 不得逐題零散追問。
- **查證不得阻塞整輪提問**——逐字：
  > "Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report — ask the rest of the frontier now."

  即：查證中的 sub-agent 是**尚未定案的前提（unsettled prerequisite）**，**只有其下游問題**等它回報，frontier 其餘部分**照問不誤**；🚫 不得因為有一個 sub-agent 在跑就停下整輪。
- 🟢 **與 ADR-NP-008（Commander 只指派不自己做）不衝突，兩者正交**：NP-008 管的是**產出物歸屬**（deliverable 一律 dispatch，Commander 不親手產出，§5.0）；本條管的是**問問題的邊界**（哪些該問使用者、哪些該自己查）。本條說的「自己查」＝**dispatch sub-agent 去查**，不是 Commander 親手動手 ⇒ 兩條同時滿足，無取捨。

**防作弊主力的階段性位置**（與名詞表一致）：手動階段在**站 4 verifier 實測**；升 CI 後回到**站 5 的 manifest 重放**。

**provider 維度（依 ADR-NP-011）**：executor 由「agent 名」擴為「**provider ＋ model**」。上表未標 provider 者一律為內建 Claude sub-agent（AgentKit 16 agent 皆是，差別只在 system prompt 與模型層級）。
🔴 **【量測，2026-08-08 沙盒實測】下列 12 家 API 全部可從 Cowork 沙盒直達，無一被 proxy 攔截**（401/403/429＝連得到僅缺 key，OpenRouter 回 200）；另以現有 Gemini key 實呼得 429 配額不足 ⇒ key 驗證通過、請求確實送達。⚠️ **此事實與 §4.6 的「GitHub 寫入被攔截」是兩件事，🚫 不得混為一談**——外廠 API 通、GitHub 寫入不通。
🔴 **登錄 ≠ 啟用**：下表是登錄簿，補 key 即可用，**不必回頭改架構**；新廠商加入只是加一列。

| provider | 端點主機 | 認證 | 格式家族 | 狀態 |
|---|---|---|---|---|
| Gemini | generativelanguage.googleapis.com | API key | Gemini | **available（首發；免費層，無需計費）** |
| OpenRouter | openrouter.ai | Bearer | OpenAI-compatible | registered-no-key｜**建議擴充路徑** |
| OpenAI | api.openai.com | Bearer | OpenAI-compatible | registered-no-key |
| xAI Grok | api.x.ai | Bearer | OpenAI-compatible | registered-no-key |
| DeepSeek | api.deepseek.com | Bearer | OpenAI-compatible | registered-no-key |
| Mistral | api.mistral.ai | Bearer | OpenAI-compatible | registered-no-key |
| Groq | api.groq.com | Bearer | OpenAI-compatible | registered-no-key |
| Together | api.together.xyz | Bearer | OpenAI-compatible | registered-no-key |
| Perplexity | api.perplexity.ai | Bearer | OpenAI-compatible | registered-no-key |
| Fireworks | api.fireworks.ai | Bearer | OpenAI-compatible | registered-no-key |
| Cerebras | api.cerebras.ai | Bearer | OpenAI-compatible | registered-no-key |
| Cohere | api.cohere.com | Bearer | Cohere | registered-no-key |

**OpenRouter 為建議的第二家**（一把 key 覆蓋多廠、格式統一、換模型只改字串 ⇒ 擴充成本最低）。⚠️ **外廠按量計費**，與 Claude session 成本模型不同——換 executor **不是零成本決定**（§7.6）。

🔴 **Gemini 首發的計費事實更正（v1.11）**：Gemini API **免費層不需開啟計費**——官方 rate-limits 文件的 tier 表列 Free tier 的取得條件為「active project 或 free trial」、計費欄為 N/A ⇒ 首發**不以使用者儲值為前提**。🚫 先前「待儲值」的註記為事實錯誤，已更正。⚠️ **但免費層仍有 RPM／RPD（及 TPM）配額上限**（實際數值依模型，以官方文件與 AI Studio 顯示的 active rate limits 為準）——§5.1 實呼得 429 即為配額觸頂的實證。⇒ **首發的成本邊界意義從「花錢」變成「配額」**（§7.6 具名）。

### 5.2 站 5 雙審規則
**本站流程依 Pocock 原版：兩軸 parallel fresh-context `general-purpose` sub-agents，實作依據 ADR-NP-007**（兩軸的審查報告皆為 deliverable，一律 dispatch，Commander 不自審，§5.0）。

🔴 **refactor 歸屬（v1.11 補採漏採原文）**：**站 4 只做 red → green，refactor 不屬站 4 的 loop；refactor 歸站 5 review 階段。** 依據為 Pocock `skills/engineering/tdd/SKILL.md`（Rules of the loop）逐字：
> "**Refactoring is not part of the loop.** It belongs to the review stage (see the `code-review` skill), not the red → green implementation cycle."

- **對站 4 的效果**：站 4 的 executor 不得以「順手重構」擴大 diff；§6 站 4 出口條件**不含任何 refactor 要求**（現行條文核對後確認無隱含要求）⇒ 本輪 §6 無須修改，兩處一致。
- 🚫 **本條只規定歸屬，不規定驗收**：Pocock 原文只說 refactor 屬 review 階段，未規定 refactor 的驗收條件，故本 spec **不新增軸、不新增站 5 出口條件、不新增停止條件**。refactor 在站 5 的具體處理方式（由哪一軸提出、修法證據形狀、是否走 §5.2「修復必須復驗」路徑）**未定，待實作票處理**（見「未解問題」6）。
- **軸 A 規範審**輸入**只有** diff ＋ repo 規範 ＋ 12 條 Fowler smell 基線；**軸 B 規格對照審**輸入**只有** diff ＋ spec 原文（逐項 ✓／✗）。
- **兩份基線的正典位置**：**12 條 smell 基線隨 plugin 出貨，住 plugin assets**（版本與 plugin 綁定，各 repo 不各存一份）；**repo 規範**＝該 repo 內既有的規範文件，gate 須在報告中**具名指出本輪採用的檔案與版本**（無規範文件 ⇒ 具名「該 repo 無落檔規範，本輪僅以基線審」）。兩者衝突時 **repo 規範優先**，且基線永遠是判斷題、非硬違規。
- 兩軸平行啟動、互不可見；🚫 報告不得合併、不得跨軸重排、**不得跨軸挑「單一最嚴重問題」**。
- 🔴 **收尾摘要的正面要求（v1.11 依原文更正，原條文把「跨軸」漏寫成全稱禁令）**：兩軸報告並列呈現後，收尾**一行摘要**須含 ① **各軸的 findings 總數**、② **該軸軸內的 worst issue（若有）**。🚫 禁的只是**跨軸**挑贏家，**軸內**的 worst issue 不但可挑、而且必報。依據 Pocock `skills/engineering/code-review/SKILL.md` 逐字：
  > "End with a one-line summary: total findings per axis, and the worst issue _within each axis_ (if any). Don't pick a single winner across axes"
  ⚠️ **層級分辨**：本條是**軸內**排序；§5.5 的「🚫 禁多數決、🚫 禁以 Claude 為準」是**跨廠**分歧裁決，兩者不同層、互不覆蓋。
  ⚠️ **兩廠升級時的界線（由 §5.5 推導，非新規則）**：單票經 DECISIONS.md 升兩廠後，A 軸存在兩份廠別清單 ⇒ worst issue **由各廠各自報一個**，🚫 **不得跨廠合選出單一 worst**——那正是 §5.5 禁止的跨廠重排。Pocock 原文假設一軸一個 sub-agent，對此情形沉默，本句為沉默處的本地推導。
- **verifier ≠ executor，亦不得是 Commander**（定義見開頭）——hard rule，未滿足 ⇒ gate fail。
- 🚫 禁餵過程對話與先前任何評分或評語（防 anchoring）。
- **結案條件**：hard violation 全清且各附修法證據；每條 judgement call 有裁決紀錄；兩軸皆完成；含 SC#6 標註。
- **修復必須復驗**：為清除 finding 而產生的修復 commit **不得自動視為已驗**——須經 ① verifier（≠ executor）對修復後的狀態重跑該票驗收條件，**或** ② 兩軸就修復後的 diff 補審一輪。二者擇一完成後方可結案。理由：修復 diff 是最後一段沒有任何人看過的程式碼。
- 結案後由 **gate 關閉該票**；該 work 全票關閉後走完成態收尾（§3.2）。
- **逃生口（載體＝DECISIONS.md，非 label）**：使用者得對任一票單筆裁示「升兩廠雙審」，寫入該 repo DECISIONS.md（ADR-NP-007 語意不變，僅換載體）。🟢 **本逃生口自 ADR-NP-011 起有實體**：外廠管道＝§5.1 登錄的 API 直呼（§5.4），不再是無處可去的空條款。gate 於站 5 讀到該條目而外廠不可用 ⇒ 依 §5.4 降級並具名，🚫 不得阻塞。
- **A 軸最適合外包**：規範審只需 **diff ＋ 規範清單 ＋ 12 條 smell 基線**，脈絡依賴最低，API 給得起；B 軸需 spec 全文與需求脈絡，外包風險較高。故異廠交叉檢視自 A 軸開始。
- **隔離實測的具名位置**：隔離實測票的結論以具名條目（如 `SC-DEC-ISO-001`）寫入 **plugin repo 的 DECISIONS.md**；gate 讀到該條目且結論為「隔離成立」後，SC#6 的強制標註方得解除。

**第二層：每票覆寫**——站 3 拆票時每張票必填 executor＋basis；覆寫預設須在 basis 說明理由。無 basis ⇒ `[INVALID]`。

### 5.3a session 內自主派工 loop（依 ADR-NP-010；手動階段生效）
承接使用者原版 S4／S5 的 high-autonomy 要求：站 4／5 一旦開跑，不靠人逐次推動。
`/station-run` 進入 loop，持續「選件 → 派工 → 收件 → 判 gate → 續派」，至停止條件成立。
🟢 **狀態一律從 GitHub 現算，不引入任何狀態檔**——這正是優於舊 fleet 心跳之處：舊心跳把喚醒綁在一份會與真相漂移的狀態檔上，本設計沒有那份檔案可漂。

**選件判準（frontier 的定義，非循環定義）**：可動作項＝① 無未解 blocker（含跨站繼承）② `depends_on` 列出的票皆已完成 ③ **尚無在跑 executor**（同一票不得併行派兩人；手動階段此條由 Commander 的 session 內記憶保證，寫入落地後改由 assignee 判定）。三條皆滿足者進入 frontier；frontier 空＝停止條件⑤。

**停止條件（窮舉六條，其餘一律自動續跑；依 ADR-NP-010②）**：① 不可逆動作前——**依 §3.5 第八欄的票級宣告判定**，run 於 dispatch 前讀取，宣告為「有」即停手待裁示；② 同一票 rework **2 次仍 fail**；③ 站 1／2／3 的人類 gate（共識確認、spec 確認、拆票 quiz）；④ scope 需變更；⑤ frontier 空；⑥ **外廠累計成本達上限 100%**——理由具名：**花下去拿不回來，與①不可逆同級**；50%／80% 僅告警、不停手。
🔴 **本清單為窮舉**：日後新增任何停止條件**一律改本條並具名**，🚫 不得散落他處自立停手規則。
⚠️ **具名承認涵蓋範圍**：①只攔得住**票級事前宣告**的不可逆動作；**dispatch 之後 executor 在其內部自行觸發的不可逆動作不在本機制涵蓋範圍**，須由該 executor 自身的權限邊界與 §5.2 的交件檢查承接。
🔴 **站 4／5 內部的 dispatch、驗收、雙審、merge 一律不問**——承接舊常設授權「merge 五條判準全過即合」，本 spec 不推翻。逐顆問的代價已有實錄：十一張票做完、驗收過，全卡在等授權。

**痕跡與通知**：**續跑不逐輪留痕**，改於 loop 收尾留**一行批次摘要**（本輪派了哪些票、gate 判定結果）；**只有停止必須具名停因**（六條中的哪一條）。停因為②③④⑥者 ⇒ **主動推播通知使用者**；①⑤為安靜情形。痕跡與摘要屬留言類寫入，手動階段一併進待寫佇列（§4.6）。

### 5.3b 跨 session 排程喚醒〔**deferred-to-CI｜本段手動階段整段不生效**〕
規格：由排程開新 session，讀 GitHub 現況後**只在站 4／5 選件續派**（站 1／2／3 屬人類 gate，排程不得代行），共用 5.3a 的選件判準與停止條件。
🔴 **為何延至 CI（依 ADR-NP-010⑤，不是單純「延後」）**：loop 賴以跨 session 運作的三個訊號——**在跑標記（assignee）、失敗計數（`sc:gate-fail`）、稽核痕跡（留言）——全部需要寫 GitHub**。手動階段寫不進去 ⇒ 新 session 讀到的必然是過期視圖 ⇒ ① **同一票每小時被重派**且重派無聲；② **多個併行 session 派出的 executor 同時改同一檔案、互相覆蓋**，全程無人察覺。session 內 loop 不受此影響，因為 Commander 自身即記憶。CI 階段三個訊號皆可寫入後，本段連同 §7.5 一併生效。

### 5.4 異廠呼叫規格（依 ADR-NP-011）
**適用站別（先寫上、逐步啟用）**：站 5 雙審 **A 軸**（規範審）｜站 2 出口缺口審｜站 3 拆票複核。
🔴 **站 4 實作維持 Claude**——實作需要完整 repo 脈絡與工具鏈（讀檔、跑測試、改多處），純 API 給不了；把實作外包等於讓對方盲寫。
**呼叫介面抽象**：只針對四個**格式家族**各寫一份最小適配（OpenAI-compatible／Gemini／Anthropic／Cohere），路由表指定 provider＋model 即可切換；🚫 不為個別廠商寫專屬分支。
**key 取得路徑**：一律讀連接資料夾內的 key 檔。🚫 **key 不進對話、不進 repo、不寫 log、不進待寫佇列**；缺 key 視為該 provider 不可用，走降級。
**逾時與重試**：單次呼叫設逾時上限，逾時或 5xx 最多重試一次；仍失敗即判該 provider 不可用。🚫 不得無限重試（重試風暴會把配額燒在錯誤上）。
**降級（承接 ADR-NP-011⑦）**：無 key／配額不足／API 錯誤／逾時 ⇒ **降級回單廠並具名記錄**（記入該票 gate 紀錄，含 provider、失敗原因、降級後由誰承接）。🚫 不得靜默跳過、🚫 不得阻塞生產線。

### 5.5 分歧裁決（兩廠 finding 的處理）
- 兩廠的 finding **各自完整存在**，不合併、不跨廠重排（承接 A-30 R1 與 §5.2 的兩軸規則）。
- **重疊處＝最強訊號**（優先處理）；**分歧處由 gate 具名列出**交使用者裁示，gate 不自行選邊。
- 🚫 **禁多數決**（承接禁 2vs1）——多數決會把「只有一家看到的真問題」投掉，而那正是異廠的全部價值。
- 🚫 **禁「Claude 為準、外廠僅供參考」的降級**——那等於抛棄盲點互補這個唯一理由。

## 6. 各站出口條件（gate 正典）

本節是出口條件的**唯一正典**：gate 的 native 判準與 §7.3 legacy 定站判準共用同一份，不得各自維護。

| 站 | 出口條件 checklist |
|---|---|
| 1 | 名詞表存在且關鍵詞無未定義；ADR 記錄關鍵裁示（含理由與被否決方案）；使用者已確認共識 |
| 2 | spec 有 Goal／Scope In-Out／可驗證 Success Criteria；使用者已確認；第三方缺口審報告存在且 hard finding 全結案 |
| 3 | 每張票具備 §3.5 **全八項**欄位（含測試先行與不可逆動作宣告）；切片可獨立驗收（垂直非水平）；**每張票的測試 seam 已寫下且已於拆票 quiz 中經使用者確認**（§3.5 註 B；併入既有 quiz，非獨立步驟） |
| 4 | 每張票有紅→綠兩段證據且紅是**斷言失敗的紅**（非載入／collection 失敗）〔來源標註見表下註 A〕；**verifier 另須查斷言的預期值非由被測程式自身產生**（獨立真相源，§3.5 註 C；自證式斷言＝紅燈作假的一種）；由 verifier（≠ executor）逐項實測一致 ⇒ 票上落 `sc:red-proven` |
| 5 | 兩軸報告分開存在且未合併；各軸輸入清單與所用 repo 規範版本具名；verifier ≠ executor 且非 Commander 可查；hard violation 全清且各附修法證據；**修復 commit 已復驗**（§5）；judgement call 有裁決紀錄；含 SC#6 標註 ⇒ 通過後 gate 關票 |
| **完成（done）** | open 票數為零 **且**全票皆經站 5 gate 關閉 ⇒ 寫 `sc:station-done`、關 anchor、關全參與 repo 的 milestone；若有人手關閉的票 ⇒ 不判完成，落 `sc:awaiting-user`（§3.2） |
| 全站（每次 gate 均查） | **全參與 repo** 的 DECISIONS.md 皆無已過期豁免條目；站別歸因合法（§3.4）；gate 執行身分 ≠ 使用者互動帳號；**若本輪有異廠呼叫失敗，該票 gate 紀錄須有具名降級記錄（provider＋原因＋承接者），無記錄即 fail**；work 站別＝未關閉票的最小站（§3.2，零票時改用完成態判定） |

**DECISIONS.md 讀取的失敗語意**：讀取失敗（API 錯誤／權限不足）＝**gate fail（fail-closed）**；檔案不存在＝視為該 repo 無豁免（不 fail）。

**註 A · 站 4 紅燈型態的來源標註（v1.11 更正，條文內容不變）**
本條由兩個**不同來源**疊成，🚫 不得整條掛在 Pocock 名下：
- **「先紅後綠」的順序要求**來自 Pocock `skills/engineering/tdd/SKILL.md`（Rules of the loop），逐字：
  > "**Red before green.** Write the failing test first, then only enough code to pass it. Don't anticipate future tests or add speculative features."
  ⚠️ **該原文全篇未定義紅燈長什麼樣**——無 assertion／compile error／import error／load failure 任何字樣，亦未禁止以載入失敗充當紅燈。
- **「須為斷言失敗的紅」這層加嚴屬本地增設，其依據是使用者 S1–S5 原話 S3**，逐字：
  > "Always design Red light to prevent Ai cheating"
  理由具名：測試連斷言都沒跑到（載入／collection 失敗）就宣稱「紅過了」，正是 S3 要防的作弊型態。
- 依 A-28 至上條款，本條屬 **Pocock 沉默處的本地增設**，不構成與原文衝突（同 ADR-NP-007 的處理方式）。

### 6.1 gate 初始化路徑（intake 呼叫）
逐條核對：① milestone 已建且 description 含 work ID 與 primary anchor 指標；② primary anchor 存在、帶 `sc:work`、body 已宣告 primary repo 與參與 repo 全集；③ work ID 全艦隊唯一（聚合查無同 ID）；④ anchor 上無任何既有 station label（有 ⇒ 轉復位模式，§3.4）；⑤ **gate 執行身分檢查與具名回報**——實查當前 identity 並寫入初始化報告；**不作 fail 條件**。若身分為使用者本人（手動階段常態），報告須含固定字串「**手動階段：無機器歸因，依 ADR-NP-009**」。CI 階段身分應為 `github-actions[bot]`，此時 §3.4 全套生效。
全過 ⇒ 落首個狀態 label：native＝`sc:station-1`；legacy＝auditor 判定站別 ＋ `sc:legacy`。任一條不過 ⇒ 不落 label、具名缺項。

## 7. 進線與 Legacy 收編

### 7.1 建立步驟（native 與 legacy **共用**）
使用者指定 work ID、primary repo、參與 repo 清單 ⇒ intake 在每個參與 repo 建 milestone（description 帶 work ID 與 primary anchor 指標）＋ 在 primary repo 建 primary anchor issue（`sc:work`，body 宣告 repo 全集）⇒ 呼叫 gate 初始化路徑（§6.1）落首個 label。legacy 模式**不得跳過本步驟**——否則首個 label 無載體。

### 7.2 legacy 模式 · auditor prompt 要件
fresh context（不得由曾參與者執行）｜**只餵**：repo 現況工件（README／spec／票／測試／log）＋ §6 checklist｜🚫 **禁餵**：過程對話、先前任何評分或評語、原作者自陳｜**輸出**：逐站逐條 ✓／✗／N/A ＋ 每個 ✗ 的證據指向 ＋ 建議退回站別 ＋ 缺件分類（關鍵／次要）。

### 7.3 定站判準
對照 **§6 同一份 checklist**，從站 1 往上逐站核對，**第一個未完全滿足出口條件的站即退回站別**。legacy 不另立寬鬆標準。

**舊票收編（定站上限）**：既有專案的舊票格式與本 spec §3.5 不同 ⇒ **legacy 工作的定站上限為站 3**，不得直接判在站 4／5，直到下列其一完成：① 舊票逐張補齊 §3.5 **八欄位**並掛上 `sc:ticket`；或 ② 舊票**不收編**、由站 3 重新拆出 native 票，舊票在 DECISIONS.md 具名記為「不收編、僅供查閱」。舊票格式屬**次要工件**，可依 §7.4 具名豁免，但**「可執行驗收條件」屬關鍵工件、不得豁免**。

### 7.4 補件／豁免規則
- **關鍵工件必補、無豁免**：spec、可執行驗收條件。
- **次要工件可豁免**：名詞表、舊票格式、歷史 CHANGELOG 補寫、命名規範等。
- **豁免必須具名**：寫入**該工作全參與 repo**中相關的那個 repo 的 DECISIONS.md，欄位＝豁免 ID／項目／理由／範圍／期限或永久／批准人；必含「本項【未】處理」（防「已知並記錄」被讀成「已處理」，CS-DEC-GATE-001 教訓）。
- **期限有牙**：gate 每次執行掃全參與 repo 的 DECISIONS.md，發現過期 ⇒ 本次 gate fail 並落 `sc:gate-fail`。明細走文字輸出，**面板不解析 DECISIONS.md**。
- **badge 生命週期**：`sc:legacy` 自收編起掛上，通過第一個 native gate 後由 gate 摘除。

### 7.5 排程喚醒規格〔**deferred-to-CI｜整節手動階段不生效**，理由見 §5.3b〕
**頻率**：平日 **09:00–22:00（Asia/Taipei）每小時一次**；夜間不跑。
**行為**：有活就做（進入 §5.3a loop）；**無活安靜退出、不發通知**——會叫的排程若九成在報「沒事」，人就會關掉它。⚠️ 「不發通知」**僅適用無活退出**；停因為②③④⑥的停止一律主動推播（§5.3a）。
**prompt 自足**：排程開的是**無記憶的新 session**，其 prompt 必須自帶「讀哪些 repo、以什麼條件選件、六條停止條件、痕跡怎麼留」，🚫 不得依賴前次 session 的任何上下文。

### 7.6 異廠成本邊界（依 ADR-NP-011⑥）
- **每票 token 上限**：每張票的外廠呼叫設 token 上限；**超過即停手並具名回報**，🚫 不得靜默截斷輸入或輸出（被截斷的審查會回一份看起來正常、其實只看了一半的報告）。
- **逐次記帳**：每次呼叫將 token 用量與估算成本寫入該票 gate 紀錄，供事後稽核。
- **累計三段告警**：達門檻 **50%／80%** 發告警**續跑**；**100% ⇒ 觸發 §5.3a 停止條件⑥**。🚫 本節不自行另立停手規則——停手語意的唯一正典是 §5.3a。停手時**已產出的結果照常輸出**（停的是後續呼叫，不是既有成果）。
- ⚠️ **計費模型差異須具名**：外廠按量計費，Claude session 非按量；🚫 不得把「換一家 executor」當成零成本決定。
- 🔴 **「上限」的兩種語意須具名（v1.11）**：本節的「成本上限」對**付費層**是金額，對**免費層是配額**（RPM／RPD／TPM）。Gemini 首發走免費層、**無需開啟計費**（§5.1）⇒ 其邊界是**配額觸頂**而非花費超支；🚫 本 spec 任何處不得假設「首發需儲值」。**兩者共用同一條停手語意**：達上限 100%（金額或配額）⇒ 觸發 §5.3a 停止條件⑥；配額觸頂在單次呼叫層另走 §5.4 降級（429＝配額不足 ⇒ 降級具名、不阻塞）。⚠️ 差異須知：**金額上限跨票累計、配額上限會隨時間窗自行回復**，故配額觸頂**不等於**本輪工作已花掉不可回收的資源——但停手條件仍照第⑥條執行，不另立規則（§5.3a 為停手語意唯一正典）。

## 8. DECISIONS.md / CHANGELOG.md 模板（各專案 repo）

兩份都住 repo 根、隨版本控管、PR 可審；protocol 層正典不放這裡。
**DECISIONS.md**：追加式表格，欄位 `日期｜ID（<PROJ>-DEC-NNN）｜類型（拍板／修改／豁免）｜裁示內容（一句話，含被否決選項）｜依據｜裁示人`。只追加不改寫；推翻舊條目須開新條目並具名「取代 <舊 ID>」；豁免類必含「本項【未】處理」。
**寫入路徑（兩條，皆需使用者參與）**：① **使用者手寫**；或 ② 由 gate／intake **dispatch `docs-manager`／`git-manager` 產生條目並開 PR，經使用者確認後合併**。🚫 任何 skill 皆不得直接 push 到預設分支寫入 DECISIONS.md——決策紀錄若能被機器單方寫入，它就不再是決策紀錄。

**CHANGELOG.md**：Keep a Changelog 形式（版本號／日期／`Added`／`Changed`／`Fixed`／`Removed`）。spec 與 ADR 不寫沿革，一律外移到此；entry 盡量帶票號或 DECISIONS ID。

## 9. 已裁決事項（使用者拍板）

| # | 裁決 | 一句理由 |
|---|---|---|
| a | **CI：C → A 兩階段**——先純手動 skill 上線，走完第一條完整生產線後升 GitHub Actions 全自動；`sc:dual-vendor` 與外廠接入同列該階段 | 先在真實使用中驗證 label scheme 與出口條件，再固化進 workflow |
| b | **各專案 repo 各自帶票，面板跨 repo 聚合**（§3） | 票與 code 同 repo 才撐得起 merge 判準⑤ 的 scope 比對 |
| c | **面板：手動 ＋ station skill 後順手刷；手動刷含對帳**（§4）〔**superseded by i**〕 | 原理由「不引入未驗證的 scheduled task」已被 i 推翻——排程確定要用，只是延至 CI；本列的手動刷新規格續行，僅該否決理由失效。**同時結掉名詞表未決項 4（面板刷新機制）：手動刷為現行、排程為 CI 階段** |
| d | **舊 fleet-command 停用機器、文件轉唯讀正典**；**「仍生效規則盤點並搬移完成」是停用的前置條件**，盤點票須具名負責人與完成日 | 先停用再盤點會製造規則真空期，比並行更糟 |
| e | **站 5 回歸 Pocock 原版**（ADR-NP-007，§5 為其實作） | 兩廠條款四次連不上、從未被滿足 |
| f | **anchor：work ID ＋ 唯一 primary anchor ＋ milestone 分組**（§3.1） | 進度由 GitHub 原生算；唯一 anchor 避免跨 repo 各持一份站別 |
| g | **Commander No-Hands**（ADR-NP-008，§5.0 為其實作） | 主 session 既編排又產出＝被審者兼審查者；deliverable 一律外派才有獨立的第二雙眼睛 |
| h | **timeline 歸因延至 CI 階段啟用**（ADR-NP-009；手動階段降為規範層＋人工複查，§6.1⑤ 只回報不 fail） | Cowork 手動階段取不到 ≠ 使用者的身分（已實測），與其擺一條攔不住東西的規則，不如具名降級並在 CI 階段用 `github-actions[bot]` 一次補齊 |
| i | **站 4／5 自主派工：手動階段只啟用 session 內 loop（停止條件六條，成本 100% 為第⑥條），跨 session 排程延至 CI**（ADR-NP-010 含⑤，§5.3a／§5.3b／§7.5） | 使用者原版 S4／S5 明寫 high autonomy 而站 1 漏採，本條接回；但跨 session 的三個訊號都要寫 GitHub，手動階段開它等於保證重派與併行互蓋 |
| j | **異廠 executor 路由：provider 維度＋12 家登錄＋異廠交叉檢視**（ADR-NP-011，§5.1／§5.4／§5.5／§7.6） | AgentKit 16 個 agent 全是 Claude，A-30「兩廠」想要的異廠交叉檢視至今零發生；沙盒實測 12 家 API 全部直達 ⇒ 缺的只是登錄與 key，不是可行性 |

### 9.1 舊 fleet-command 條文作廢紀錄（v1.11 一級來源重判，2026-08-08）

t04 盤點（`t04-inventory.md`）曾把下列三條標為「仍生效／殘留缺口」，待搬進新 plugin。**依 A-28 至上條款回頭取證 Pocock 六份原文與使用者 S1–S5 原話後重判為作廢**——本節是它們的作廢紀錄，🚫 三條皆**不搬進 station-command**，日後不得以「t04 說仍生效」為由重提。

| 舊條文 | 舊判定 | v1.11 重判 | 作廢依據（一級來源） |
|---|---|---|---|
| **SK-07／AM-10／AM-11**（A-9 派工令獨立審核官） | 仍生效，待搬 | **作廢** | ① Pocock 六份原文中**唯一的第三方覆核**是 `code-review` 的兩軸平行 sub-agent，發生在**實作完成後**（本 spec 站 5）；**派工前覆核零命中**。② 使用者原話 S4 為 "Execute with S3"、S5 為 "S4 S5 gives high autonomy to Ai"，**皆無此關卡**（且與 §5.3a「站 4／5 內部不逐次問」相斥）。③ **方向相反**：紅燈防作弊要看**產物**才抓得到，看派工令抓不到。④ A-9 唯一有效成分＝**角色分離**，已被 §6／§5.2「verifier ≠ executor 且非 Commander」完整吸收 ⇒ 無殘留。 |
| **SK-18**（站 3 出口 gate 兩廠×三軸） | 已吸收（部分），三軸屬殘留缺口 | **作廢** | ① `code-review` 明訂**兩軸**且逐字寫死：> "Do **not** merge or rerank findings — the two axes are deliberately separate" ⇒ 加第三軸即違反原文。② 三軸中的「**過度設計**」**已有家**——在 Standards 軸的 Fowler smell 基線內，逐字：> "**Speculative Generality** — abstraction, parameters, or hooks added for needs the spec doesn't have." ③ **位置也錯**：`to-tickets` 的站 3 出口是 "### 4. Quiz the user … Iterate until the user approves the breakdown." ⇒ **站 3 出口是使用者核准，不是機器三軸審**。④ 兩廠部分早由 ADR-NP-007 廢止。 |
| **AM-16**（A-14 忙碌不等於進展） | 仍生效，建議加「站別停滯」檢視 | **作廢** | ① 六份 Pocock 原文與使用者 S1–S5 **皆零命中**。② `grilling` 的 "frontier" 是**設計樹推進機制**（"The **frontier** is every decision whose prerequisites are already settled"），**不是停滯警示**，不能拿來當本條的原文依據。③ **使用者已裁示面板不加新指標**：維持 §4.1 現有「**停滯票數（24h 無事件）**」，🚫 不新增「站別未推進 N 小時」之類維度 ⇒ §4.1 字卡欄位**維持現狀，本輪不動**。 |

## 10. 驗收測試

1. **站序不可跳（三組）**：1→3、2→4、3→5 各跑一次 ⇒ 三組皆遭拒、各自列出被跳過站的未滿足條件、回讀 anchor 確認 label 未變。
2. **票欄位 fail-closed**：四張票（缺 basis／缺 depends_on／缺測試先行／完整）⇒ 站 3 gate fail 並具名前三張；補齊後 pass。
3. **面板錯誤四情境**：假 repo ⇒「數據過期」；人為觸頂 ⇒「資料可能不完整」；關掉站 3 的 anchor ⇒「工作消失」＋ work ID ＋ 上次所見站別；面板寫入失敗 ⇒ 文字輸出完整摘要＋過期告警。
4. **消失偵測無基線**：刪除面板 artifact 後首刷 ⇒ 橫幅「消失偵測不可用（無基線）」，且字卡內容與刪除前一致（對應 SC#1）。
5. **寫後回驗**：gate 寫入後直讀 anchor 一致才回報成功；模擬寫入失敗 ⇒ 不宣稱推進成功並具名。
6. **狀態 label 寫入單點（兩層）**：跑 board／run／intake（含 native）後，檢查所有 `sc:` 狀態 label 的最後 `labeled` 事件 actor 皆為 gate 執行身分；併同人工審四份 SKILL.md，確認只有 gate 含寫狀態 label 指示。
7. **站別歸因與復位**〔**deferred-to-CI**〕：以個人帳號手動改 anchor station label ⇒ board 紅燈「站別來源不明」、run 拒絕選件；跑 gate 復位 ⇒ 回退至最後一次合法事件站別；刪光合法事件後再跑 ⇒ 落 `sc:awaiting-user` 並停手。手動階段不測（判準未生效），改測 #17a。
8. **站 5 雙審**：兩份報告分開留存未合併；輸入清單核對（軸 A 無 spec 原文、軸 B 無 smell 基線）；含隔離未實測標註（移除 ⇒ gate fail）；以 executor 本人當 verifier ⇒ gate fail；通過後該票被 gate 關閉。
9. **逃生口不死鎖**：在 DECISIONS.md 記一筆「本票升兩廠」⇒ gate fail 並提示二擇一；選降級並記 DECISIONS.md 後 ⇒ 可繼續推進。
10. **站別粒度**：一個 work 下三張票（兩張站 5、一張站 4）⇒ anchor 站別為站 4；關閉站 4 那張後重跑 gate ⇒ anchor 升為站 5。
11. **進度分列**：同 work ID 的 milestone 分散兩 repo ⇒ 字卡逐 repo 分列原生百分比、不出現合成單一數字；work ID 不同但 milestone 同名 ⇒ 不得合併。
12. **進線兩模式**：native 與 legacy 各跑一次 ⇒ 皆建出 milestone、primary anchor（body 含 repo 全集）、首個 label 由 gate 落；legacy 另有定站結論與缺件分類且字卡帶 `legacy` badge，補齊後 gate 通過 ⇒ badge 消失。
13. **開工、executor 與失敗回滾**：對站 4 票跑 run ⇒ 票 body 的 `executor` 欄位被寫入 agent 名、assignee 被指派為執行身分帳號、該票計入「在跑數量」；**字卡的 executor 顯示值須等於 body 欄位而非 assignee 帳號**；無 assignee 的 open 站 4 票不得計入；模擬 dispatch 失敗 ⇒ assignee 被移除並具名回報；造一張逾 24 小時無 timeline 事件的票 ⇒ 計入「停滯票數」。**手動階段替代驗證**：上述各項改以「佇列中出現對應動作項且 payload 正確」認定，並確認字卡已標「寫入斷點期間不可信」。
14. **對帳三態**：`plans/` 無紀錄 ⇒「對帳範圍外」；run 觸發刷新 ⇒「本次未對帳，沿用 <時間> 結果」；`plans/` 不可用 ⇒「對帳未執行」。
15. **豁免有牙與 fail-closed**：參與 repo 之一放過期豁免 ⇒ gate fail 並落 `sc:gate-fail`；使某 repo 的 DECISIONS.md 讀取失敗 ⇒ gate fail；該檔不存在 ⇒ 不 fail。
16. **薄度**：run 在站 4 派工 ⇒ 實際執行者為 ak-engineer 的 agent／skill；四份 SKILL.md 行為皆不超出 §2 白名單。
17. **執行身分驗證**〔**deferred-to-CI**〕：CI 身分下跑初始化 ⇒ 通過，且後續 gate 寫入的 `labeled` 事件 actor 為 `github-actions[bot]`。
17a. **手動階段替代測項**：以現行身分跑初始化與任一次 gate ⇒ 兩份報告皆具名當前身分，且初始化報告含固定字串「手動階段：無機器歸因，依 ADR-NP-009」；缺該字串即判失敗。
18. **完成態收尾**：一個 work 的最後一張票經站 5 gate 通過關閉 ⇒ anchor 落 `sc:station-done`、anchor 被關閉、全參與 repo 的 milestone 被關閉；另造一個「零 open 票但有一張人手關閉的票」的 work ⇒ 不判完成、落 `sc:awaiting-user`。
19. **站別推進原子性**：觀察 gate 推進站別的 API 呼叫 ⇒ 為單一次「設定完整 label 集合」；回驗比對的是完整集合；過程中不存在無站別或雙站別的中間態。
20. **站 5 修復復驗**：清完 finding 後直接結案 ⇒ gate 拒絕；補上 verifier 對修復後狀態的重驗（或兩軸補審）後 ⇒ 方可結案關票。
21. **legacy 舊票上限**：對一個帶舊格式票的既有專案跑 intake ⇒ 定站不得高於站 3；補齊八欄位（或具名記「不收編」並重拆 native 票）後 ⇒ 方得經 gate 進站 4。
22. **No-Hands**：任一站的 deliverable（spec 文字、票內容、程式、測試、審查報告）⇒ 追查其產出者必為 dispatch 的 executor，非主 session；以「主 session 直接寫出票內容」情境驗證 ⇒ 該 artifact 判無效並被重派（§5.0）。面板 HTML 由 board 現算 ⇒ **不觸發**違規（§2 邊界裁定）。
23. **loop 停止條件**：至少測兩種——① 讓 frontier 空 ⇒ loop 安靜退出且留下「停因：frontier 空」痕跡；② 讓下一步為不可逆動作（如 deploy）⇒ loop 在動作前停手並具名停因。另驗證同一票 rework 2 次仍 fail ⇒ 停手、不再自動重派、且**主動推播通知**（停因②③④⑥須通知，①⑤安靜）。**另測停因⑥**：把外廠累計成本推過 100% ⇒ loop 停手、具名停因⑥、已產出結果照常輸出。
24. **待寫佇列冪等與遺失偵測**：對同一份佇列連續套用兩次 ⇒ 因套用前讀現況比對，目標狀態相同、無重複發票或重複 label 寫入；套用後逐筆回驗，人為讓一筆不符 ⇒ 留在佇列並具名回報。**遺失情境**：刪除佇列檔後重跑 loop ⇒ 具名回報「待寫佇列不存在，本批動作將重新產生」，且 GitHub 既有狀態不受影響。另驗證 label 類佇列項只由 gate 產生、run 產不出來。
26. **廠商登錄表與實測相符**：對登錄表 12 家逐一發最小請求 ⇒ 回應碼落在「連得到」區間（200／401／403／429），無任何一家出現網路層攔截；有 key 者狀態為 `available`、無 key 者為 `registered-no-key`，與表列一致。
27. **異廠不可用即降級且具名**：移除／填入錯誤 key 後跑站 5 A 軸 ⇒ 產生具名降級記錄（provider＋失敗原因＋承接者）、生產線繼續推進不阻塞；**移除該記錄後重跑 gate ⇒ 必須 fail**（證明具名不是可選項）。另驗證重試至多一次。
28. **兩廠 finding 未被合併或重排**：一票升兩廠後 ⇒ 兩份 finding 清單各自完整留存、順序未跨廠重排；人為製造一條分歧 finding ⇒ gate 具名列出並要求使用者裁示，**不得出現多數決或「以 Claude 為準」的字樣**（比照 SC#6 的輸入分離驗法，核對兩份原始輸出）。
25. **排程接續不靠記憶**〔**deferred-to-CI**〕：關閉現有 session 後由排程觸發新 session ⇒ 僅憑 GitHub 現況選出正確的下一個可動作項並續派（只在站 4／5 選件）；人為清空本機殘留 ⇒ 結果不變（**待寫佇列檔不屬於此處的「本機殘留」**，其遺失行為見 #24）。手動階段不測。

## 11. 風險

| # | 風險 | 影響 | 可能性 | 緩解 |
|---|---|---|---|---|
| 1 | **label 被人手動改** | 高——站序鎖失效 | 中 | §3.4 原生 timeline actor 歸因（無自建簿記可被繞過）：board 紅燈、run 拒絕選件、gate 復位模式；驗收 #7 |
| 2 | **手動階段無機器歸因**（已裁示接受，ADR-NP-009）——人手改 label 與 gate 寫入的 actor 相同，機器無從區分 | 中——站序鎖此階段僅靠規範與人工把關 | 確定（非機率，是現況） | 規範層（僅 gate 的 SKILL.md 含寫 label 指示）＋ 人工複查 ＋ 每次 gate 報告具名身分與 ADR-NP-009 字串（驗收 #17a）；CI 階段以 `github-actions[bot]` 補齊機器層（驗收 #7、#17） |
| 3 | **ak CLI 在 Cowork 為 ephemeral**（`ak-plan` 與對帳同時受影響） | 中 | 高 | 路由表標註前置需求；run 於 dispatch 前檢查並提示 `/ak-cli-setup`，提供純 agent 退路；對帳不可用時標「對帳未執行」而非綠燈 |
| 4 | **同環境雙審的共享盲點** | 中——雙審只覆蓋一種視角 | 中 | 輸入分離為主要防線；SC#6 強制標註直到實測條目落地；站 4 verifier 為獨立第二道防線 |
| 5 | **逃生口長期不可用**（外廠管道不存在） | 中 | 高 | 逃生口載體改為 DECISIONS.md（不製造無人可摘的 label）；降級須具名可稽核；接入路徑列入升 CI 階段必要項 |
| 6 | **search 最終一致性／結果上限** | 中——面板誤報 | 中 | 判定一律走 issues API 直讀＋timeline；search 只做聚合並附不完整示警 |
| 7 | **skill 膨脹** ⇒ 退化成第二個 fleet-command | 中 | 中 | SC#8 白名單＋硬上限 ≤5；新增 skill 須在 DECISIONS.md 具名說明「為何不能併入既有四個」 |
| 8 | **豁免累積成靜默技術債** | 中 | 中 | 條目強制含「本項【未】處理」與期限；gate 每次掃全參與 repo，過期即 fail；明細走 gate 文字輸出 |
| 10 | **異廠成本失控**（按量計費、審查型呼叫 token 量大） | 中——花費無聲累積且事後難歸因 | 中 | 每票 token 上限＋超限停手具名（🚫 不靜默截斷）；逐次記帳進 gate 紀錄；50／80／100% 三段告警且 100% 強停；計費模型差異在 §5.1 具名 |
| 9 | **loop 空轉燒 token** | 中——成本無聲累積 | 中（手動階段僅 session 內，暴露面小） | 無活即安靜退出、收尾批次摘要使空轉可稽核；排程層延至 CI（§5.3b），屆時夜間不跑且 §7.5 為唯一頻率正典 |

## 12. 審查回應

站 2 歷經三輪第三方缺口審（v1.1→v1.2→v1.3→v1.4 定稿）與其後四次上游 ADR 增修（NP-008 No-Hands／NP-009 歸因延後／NP-010 自主循環＋⑤修訂／NP-011 異廠路由）。
**逐條處置紀錄（含每條 HARD／judgement 的採納或調整理由）已外移 CHANGELOG**，依本 spec 自身「沿革不寫在條文檔」的規則（§8）。
**結論**：三輪合計 26 條 HARD、37 條 judgement，**不採納者為零**；唯二偏離原建議處為 ① 站 5 關票時點改至站 5 通過後（原建議站 4，與票級雙審衝突）② 軸3-04 判為已被前輪改動覆蓋。兩者理由均留存於 CHANGELOG。

## 未解問題

1. 舊 fleet-command「仍生效規則」盤點的**負責人與完成日**未定——依 §9d 為停用前置條件。
2. Cowork 平行 sub-agent 的 context 是否真互不可見——**未實測**；SC#6 強制標註，實測票須列站 3，結論寫 plugin repo DECISIONS.md。
3. ~~獨立 bot token 取得方式~~ **已由 T-02 實測結案並裁示為 ADR-NP-009**（手動階段降級、CI 階段以 `github-actions[bot]` 補齊）；殘留待辦＝CI 階段 spec 須把 §3.4 的啟用與驗收 #7／#17 一併納入。
4. 名詞表補「Commander」「gate 執行身分」「executor（≠ assignee）」三條目——本 spec 已自定義，待站 1 正典追認。
5. plugin 命名 `station-command` 是否定案。
6. **refactor 在站 5 的具體處理方式未定**（v1.11 新增）——Pocock `tdd` 原文只裁定**歸屬**（refactor 屬 review 階段、不屬站 4 的 red → green loop），**未規定驗收**。故本 spec 只寫歸屬，🚫 未新增軸、未新增出口條件。待實作票決定：由哪一軸提出 refactor finding、修法證據形狀、是否適用 §5.2「修復必須復驗」。
7. **seam 的判定標準與清單格式未定**（v1.11 新增）——Pocock `tdd` 原文只要求「寫下來、與使用者確認」（§3.5 註 B），未規定 seam 的粒度判準、命名法或清單格式。故本 spec 只寫「須寫下＋須經 quiz 確認」，🚫 未發明格式。待實作票決定：seam 欄的填寫形狀、以及跨票 seam 重複時是否共用一次確認。
