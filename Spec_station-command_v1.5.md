---
title: "station-command Plugin Spec v1.5（定稿）"
description: "五站生產線的薄編排層 Cowork plugin：狀態機 gate、GitHub 真相源、常駐面板、兩層 executor 路由"
status: pending
priority: P1
effort: 1 週（4 skills ＋ 面板 ＋ 路由表）
branch: n/a
tags: [station-command, cowork-plugin, five-stations, github-source-of-truth]
created: 2026-08-05
---

> 上游正典＝ADR-NP-001～008 與名詞表；**本 spec 不推翻任何 ADR**。站 5 規則依 ADR-NP-007，Commander 角色依 ADR-NP-008。
> 前幾輪審查的處置沿革寫 CHANGELOG，本檔只留現行條文與本輪審查回應（§12）。

**本 spec 內定義的名詞**（提請補入名詞表）：
- **Commander**＝主 session 編排者，即發起 dispatch 的 Claude 主對話本身。
- **gate 執行身分**＝plugin 呼叫 GitHub API 所用的 identity。🔴 **必須是獨立 bot token（GitHub App／machine user），且不得等於使用者的人類互動帳號**——Cowork 預設 token 是使用者本人 OAuth，若沿用，人手改 label 與 gate 寫入的 actor 會完全相同，§3.4 的整組 timeline 歸因**靜默失效**。安裝與每次初始化時驗證此不等式，驗證不過 ⇒ **拒絕完成安裝／初始化並具名說明**（§6.1⑤、驗收 #17）。身分具名記於 plugin repo 的 DECISIONS.md。
- **executor**＝ak-engineer 的 agent／skill 名稱（非 GitHub 帳號）。其唯一真相源是**票 body 的 `executor` 欄位**；GitHub `assignee` 只承載「已開工」的二元訊號，不承載 executor 身分。

## 1. Goal / Scope / Success Criteria

**Goal**：提供一個薄編排層 plugin，讓多個專案在 GitHub 上以「五站生產線」推進，狀態可查、gate 不可跳、派工有 basis、進度在 Cowork 側邊欄常駐可見。

**Scope In**：五站狀態機與各站出口條件｜GitHub milestone／label scheme ＋ 票模板（真相源）｜常駐面板 artifact（跨 repo 聚合、一工作一字卡、含 plans/ 對帳）｜兩層 executor 路由表｜進線入口（native 新建與 legacy 收編）｜各專案 repo 的 DECISIONS.md／CHANGELOG.md 模板

**Scope Out**：任何實作能力（拆票、寫碼、審查、測試）全部 dispatch 給 ak-engineer，不複製任何 skill（ADR-NP-001）｜第二份狀態檔與任何自建簿記協定（ADR-NP-002）｜CI workflow 本體、外部廠 AI 接入路徑、`sc:dual-vendor` label（皆列升 CI 階段，見 §9a）｜hooks（Cowork 不可靠）｜protocol 層跨專案正典（照舊 Drive，ADR-NP-004）

**Success Criteria**（可驗證）
1. **零狀態複製**：plugin 不落任何持久化**狀態**檔；工作站別只能從 primary anchor 的 label ＋ 其 timeline 讀出。面板 artifact 內的顯示快取（§4.2）不參與任何判定，刪除後重跑 `/station-board` ⇒ 字卡內容與刪除前一致（僅消失偵測降級，見 §4.4）。
2. **站序不可跳**：任一工作從站 N 跳到站 N+2 ⇒ gate 拒絕並具名未滿足的出口條件。以 1→3、2→4、3→5 三組驗證，三組全拒。
3. **無 basis 即無效**：票缺 executor 或 basis ⇒ 站 3 gate 判 `[INVALID]` 並具名票號，fail-closed（非 warn）。
4. **錯誤不靜默**：查詢失敗／結果縮水或觸頂／面板寫入失敗 ⇒ 各自的具名告警（§4.4），且不得把失敗顯示為「無工作」。以斷網、假 repo 名、人為觸頂、面板寫入失敗四情境驗證。
5. **legacy 可辨識**：收編中工作字卡帶 `legacy` badge，只在通過第一個 native gate 後消失。
6. **雙審輸入分離可證、隔離未證須具名**：站 5 兩軸 sub-agent 各自只收到 §5 規定的輸入集合，兩份報告獨立留存未合併（以 prompt 輸入清單與報告核對）。**且**在 plugin repo 的 DECISIONS.md 出現具名的隔離實測結論條目（§5）之前，每份站 5 gate 結案報告必須含固定字串「context 隔離未實測，本結論僅由輸入分離支撐」；缺標註 ⇒ gate fail。
7. **狀態 label 寫入單點（兩層判準）**：①**機器層**——任一 `sc:` 狀態 label 的最後一次 `labeled`／`unlabeled` timeline 事件，actor 必須是 gate 執行身分；②**規範層**——四個 SKILL.md 中只有 gate 得含寫狀態 label 的指示，其餘三個明文禁止。⚠️ **機器層成立的前提是 gate 執行身分為獨立 bot token 且 ≠ 使用者互動帳號**（否則人手改與 gate 寫的 actor 相同，判準歸零）——此前提由 §6.1⑤ 於初始化強制驗證。即便如此，四個 skill 共用同一 bot，機器層仍只能證「非人手直接改」、證不了「哪個 skill 寫的」，故規範層不可省，兩層缺一不可（驗收 #6、#17）。
8. **薄度可量**：skill 數 ≤ 5，且每個 skill 的實際行為不超出 §2 的**逐 skill 允許動作白名單**（人工審 SKILL.md 逐條核對）。

## 2. Plugin 元件清單與動作白名單

結構：標準 plugin manifest ＋ 每個 skill 一個 SKILL.md 目錄（user-invocable ⇒ 自動成為 /slash-command）。無 hooks、無 scripts（第一階段）。原則：**能少一個 skill 就少一個**。

| Skill | 職責 | **允許動作白名單（超出即違反 SC#8）** |
|---|---|---|
| `/station-board` | 跨 repo 聚合（按 work ID）、建立／就地更新面板 artifact、輸出文字摘要；完整模式並起 `project-manager` 對帳。**唯一寫面板的實作點**（無對帳模式供 run／gate 呼叫，§4.5） | 讀 GitHub（search／issues／timeline／issue body 欄位）｜讀本機 `plans/`｜**dispatch `project-manager`（僅完整模式對帳）**｜寫面板 artifact｜文字輸出。🚫 不寫 GitHub 任何欄位 |
| `/station-run` | 驗站別歸因合法（§3.4）→ 選出下一個可動作項（無 blocker、depends_on 已滿足）→ 依路由表定 executor＋basis 並**寫入票 body 的 executor 欄位** → 經使用者確認後 dispatch；**指派 assignee 為執行身分帳號，作為二元開工訊號**；dispatch 失敗 ⇒ **立即移除該 assignee** 並具名回報，不留下「已開工但沒人在做」的假象；結束時呼叫面板無對帳刷新 | 讀 GitHub｜**寫／移除 assignee**｜**寫票 body 的 executor／basis 欄位**｜寫人讀留言｜dispatch sub-agent｜呼叫 board 無對帳模式。🚫 不寫任何 label、不開關 issue |
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
- **歸因判準**：讀 primary anchor 的 issue timeline，取當前 station label 最後一次 `labeled` 事件的 **actor 與時間**（GitHub 原生記錄）。actor ∈ gate 執行身分 ⇒ 合法；否則為人手直接改。
- **不合法時**：board 紅燈標「站別來源不明」；**`/station-run` 拒絕選件**，要求先跑 gate 復位模式。
- **gate 復位模式**：① 沿 timeline 回溯，找**最後一次合法** `labeled` 事件所設站別 ⇒ 回退至該站並具名回報回退理由與事件時間；② 若整條 timeline 無任何合法事件 ⇒ 落 `sc:awaiting-user`、停止推進、交使用者裁示。**復位只讀 timeline、不採信當前 label 值**，故不循環。
- **站別推進＝單一動作**：舊站 label 的移除與新站 label 的加入，必須以**一次「設定完整 label 集合」的 API 呼叫**完成，🚫 不得拆成 remove ＋ add 兩步（中間態會讓 anchor 短暫無站別或雙站別）。回驗時比對的也是**完整 label 集合**，不是單一 label 是否存在（§4.4）。
- 🚫 **不建立任何自建簿記（gate 紀錄留言、狀態檔）作為判準**。gate 得留人讀留言，但**留言不參與任何判定**——單一寫入動作即完成狀態變更，無「label ＋ 留言」雙寫的原子性問題。

### 3.5 票模板欄位（站 3 產出，全部必填）
`REQ-ID`｜**驗收條件**（可執行：怎麼跑、看什麼輸出算過）｜`depends_on`（可為空但欄位必須在）｜`executor`（ak-engineer 的 agent／skill 名，**本欄為 executor 身分的唯一真相源**）｜`basis`（一句話；覆寫預設須說明理由）｜`scope`（供 merge 判準⑤ 比對）｜**測試先行**（紅燈測試長什麼樣；不可自動測時寫人工驗法與證據形狀）。

**七項任一缺漏 ⇒ 站 3 出口 gate fail**（缺 executor／basis 判 `[INVALID]`）。臨時換 executor ⇒ `ESCALATE`，需使用者裁示並補 basis。

## 4. 面板規格

### 4.1 載體與字卡
自包 HTML artifact，就地 update，跨 session 存活（ADR-NP-003）。**一 work 一張字卡**，欄位一律由「跨 repo issue search（含隨結果附帶的 issue body 欄位）＋ milestone 原生欄位 ＋ timeline」算出，**不解析任何 repo 內檔案、不發額外查詢**：

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

## 5. Commander 角色與兩層 executor 路由表 v1

### 5.0 Commander No-Hands（依 ADR-NP-008）
**Claude 主 session（Commander）在五站生產線只做五件事：讀 → 驗 → 決 → 派 → 記。** 五站每一站的 deliverable **一律由路由表 dispatch 的 executor 產生**，主 session 不親手產出。

**讀**＝查 GitHub、讀 timeline／DECISIONS.md、讀報告與交件；**驗**＝對照 §6 出口條件逐條判 ✓／✗、回驗寫入、驗歸因合法性；**決**＝判 gate 過否、定站、選件、依路由表定 executor＋basis；**派**＝dispatch 給 ak-engineer 的 agent／skill；**記**＝寫 label／assignee／狀態，**其邊界＝共識文件與裁示紀錄**（ADR、名詞表、DECISIONS.md 條目），不含任何 deliverable。

**受管轄的 deliverable**（必須 dispatch）：程式碼、spec 文字、票內容、測試、審查報告、auditor 報告、對帳分析結論。
**不受管轄的編排輸出**：GitHub 狀態寫入、gate 判定結果、面板 HTML（§2 邊界裁定）、以及「記」邊界內的共識文件與裁示紀錄。

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

**防作弊主力的階段性位置**（與名詞表一致）：手動階段在**站 4 verifier 實測**；升 CI 後回到**站 5 的 manifest 重放**。

### 5.2 站 5 雙審規則
**本站流程依 Pocock 原版：兩軸 parallel fresh-context `general-purpose` sub-agents，實作依據 ADR-NP-007**（兩軸的審查報告皆為 deliverable，一律 dispatch，Commander 不自審，§5.0）。
- **軸 A 規範審**輸入**只有** diff ＋ repo 規範 ＋ 12 條 Fowler smell 基線；**軸 B 規格對照審**輸入**只有** diff ＋ spec 原文（逐項 ✓／✗）。
- **兩份基線的正典位置**：**12 條 smell 基線隨 plugin 出貨，住 plugin assets**（版本與 plugin 綁定，各 repo 不各存一份）；**repo 規範**＝該 repo 內既有的規範文件，gate 須在報告中**具名指出本輪採用的檔案與版本**（無規範文件 ⇒ 具名「該 repo 無落檔規範，本輪僅以基線審」）。兩者衝突時 **repo 規範優先**，且基線永遠是判斷題、非硬違規。
- 兩軸平行啟動、互不可見；🚫 報告不得合併、不得跨軸重排、不得挑「單一最嚴重問題」。
- **verifier ≠ executor，亦不得是 Commander**（定義見開頭）——hard rule，未滿足 ⇒ gate fail。
- 🚫 禁餵過程對話與先前任何評分或評語（防 anchoring）。
- **結案條件**：hard violation 全清且各附修法證據；每條 judgement call 有裁決紀錄；兩軸皆完成；含 SC#6 標註。
- **修復必須復驗**：為清除 finding 而產生的修復 commit **不得自動視為已驗**——須經 ① verifier（≠ executor）對修復後的狀態重跑該票驗收條件，**或** ② 兩軸就修復後的 diff 補審一輪。二者擇一完成後方可結案。理由：修復 diff 是最後一段沒有任何人看過的程式碼。
- 結案後由 **gate 關閉該票**；該 work 全票關閉後走完成態收尾（§3.2）。
- **逃生口（載體＝DECISIONS.md，非 label）**：使用者得對任一票單筆裁示「升兩廠雙審」，寫入該 repo DECISIONS.md（ADR-NP-007 的逃生口語意不變，僅換載體）。gate 於站 5 讀到該條目 ⇒ 若無可用外廠管道，**gate fail 並要求二擇一**：① 降級回單廠雙軸並記 DECISIONS.md，或 ② 提供可用管道。外廠接入路徑列入升 CI 階段 spec。
- **隔離實測的具名位置**：隔離實測票的結論以具名條目（如 `SC-DEC-ISO-001`）寫入 **plugin repo 的 DECISIONS.md**；gate 讀到該條目且結論為「隔離成立」後，SC#6 的強制標註方得解除。

**第二層：每票覆寫**——站 3 拆票時每張票必填 executor＋basis；覆寫預設須在 basis 說明理由。無 basis ⇒ `[INVALID]`。

## 6. 各站出口條件（gate 正典）

本節是出口條件的**唯一正典**：gate 的 native 判準與 §7.3 legacy 定站判準共用同一份，不得各自維護。

| 站 | 出口條件 checklist |
|---|---|
| 1 | 名詞表存在且關鍵詞無未定義；ADR 記錄關鍵裁示（含理由與被否決方案）；使用者已確認共識 |
| 2 | spec 有 Goal／Scope In-Out／可驗證 Success Criteria；使用者已確認；第三方缺口審報告存在且 hard finding 全結案 |
| 3 | 每張票具備 §3.5 **全七項**欄位（含測試先行）；切片可獨立驗收（垂直非水平） |
| 4 | 每張票有紅→綠兩段證據且紅是**斷言失敗的紅**（非載入／collection 失敗）；由 verifier（≠ executor）逐項實測一致 ⇒ 票上落 `sc:red-proven` |
| 5 | 兩軸報告分開存在且未合併；各軸輸入清單與所用 repo 規範版本具名；verifier ≠ executor 且非 Commander 可查；hard violation 全清且各附修法證據；**修復 commit 已復驗**（§5）；judgement call 有裁決紀錄；含 SC#6 標註 ⇒ 通過後 gate 關票 |
| **完成（done）** | open 票數為零 **且**全票皆經站 5 gate 關閉 ⇒ 寫 `sc:station-done`、關 anchor、關全參與 repo 的 milestone；若有人手關閉的票 ⇒ 不判完成，落 `sc:awaiting-user`（§3.2） |
| 全站（每次 gate 均查） | **全參與 repo** 的 DECISIONS.md 皆無已過期豁免條目；站別歸因合法（§3.4）；gate 執行身分 ≠ 使用者互動帳號；work 站別＝未關閉票的最小站（§3.2，零票時改用完成態判定） |

**DECISIONS.md 讀取的失敗語意**：讀取失敗（API 錯誤／權限不足）＝**gate fail（fail-closed）**；檔案不存在＝視為該 repo 無豁免（不 fail）。

### 6.1 gate 初始化路徑（intake 呼叫）
逐條核對：① milestone 已建且 description 含 work ID 與 primary anchor 指標；② primary anchor 存在、帶 `sc:work`、body 已宣告 primary repo 與參與 repo 全集；③ work ID 全艦隊唯一（聚合查無同 ID）；④ anchor 上無任何既有 station label（有 ⇒ 轉復位模式，§3.4）；⑤ 🔴 **gate 執行身分驗證**——實查當前 token 的 identity，確認其為 bot／machine 帳號**且不等於使用者的人類互動帳號**；不通過 ⇒ **拒絕初始化**，具名輸出「timeline 歸因在此身分下失效，請改配獨立 bot token」。
全過 ⇒ 落首個狀態 label：native＝`sc:station-1`；legacy＝auditor 判定站別 ＋ `sc:legacy`。任一條不過 ⇒ 不落 label、具名缺項。

## 7. 進線與 Legacy 收編

### 7.1 建立步驟（native 與 legacy **共用**）
使用者指定 work ID、primary repo、參與 repo 清單 ⇒ intake 在每個參與 repo 建 milestone（description 帶 work ID 與 primary anchor 指標）＋ 在 primary repo 建 primary anchor issue（`sc:work`，body 宣告 repo 全集）⇒ 呼叫 gate 初始化路徑（§6.1）落首個 label。legacy 模式**不得跳過本步驟**——否則首個 label 無載體。

### 7.2 legacy 模式 · auditor prompt 要件
fresh context（不得由曾參與者執行）｜**只餵**：repo 現況工件（README／spec／票／測試／log）＋ §6 checklist｜🚫 **禁餵**：過程對話、先前任何評分或評語、原作者自陳｜**輸出**：逐站逐條 ✓／✗／N/A ＋ 每個 ✗ 的證據指向 ＋ 建議退回站別 ＋ 缺件分類（關鍵／次要）。

### 7.3 定站判準
對照 **§6 同一份 checklist**，從站 1 往上逐站核對，**第一個未完全滿足出口條件的站即退回站別**。legacy 不另立寬鬆標準。

**舊票收編（定站上限）**：既有專案的舊票格式與本 spec §3.5 不同 ⇒ **legacy 工作的定站上限為站 3**，不得直接判在站 4／5，直到下列其一完成：① 舊票逐張補齊 §3.5 七欄位並掛上 `sc:ticket`；或 ② 舊票**不收編**、由站 3 重新拆出 native 票，舊票在 DECISIONS.md 具名記為「不收編、僅供查閱」。舊票格式屬**次要工件**，可依 §7.4 具名豁免，但**「可執行驗收條件」屬關鍵工件、不得豁免**。

### 7.4 補件／豁免規則
- **關鍵工件必補、無豁免**：spec、可執行驗收條件。
- **次要工件可豁免**：名詞表、舊票格式、歷史 CHANGELOG 補寫、命名規範等。
- **豁免必須具名**：寫入**該工作全參與 repo**中相關的那個 repo 的 DECISIONS.md，欄位＝豁免 ID／項目／理由／範圍／期限或永久／批准人；必含「本項【未】處理」（防「已知並記錄」被讀成「已處理」，CS-DEC-GATE-001 教訓）。
- **期限有牙**：gate 每次執行掃全參與 repo 的 DECISIONS.md，發現過期 ⇒ 本次 gate fail 並落 `sc:gate-fail`。明細走文字輸出，**面板不解析 DECISIONS.md**。
- **badge 生命週期**：`sc:legacy` 自收編起掛上，通過第一個 native gate 後由 gate 摘除。

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
| c | **面板：手動 ＋ station skill 後順手刷；手動刷含對帳**（§4） | 精準覆蓋「狀態變了面板沒變」，不引入未驗證的 scheduled task |
| d | **舊 fleet-command 停用機器、文件轉唯讀正典**；**「仍生效規則盤點並搬移完成」是停用的前置條件**，盤點票須具名負責人與完成日 | 先停用再盤點會製造規則真空期，比並行更糟 |
| e | **站 5 回歸 Pocock 原版**（ADR-NP-007，§5 為其實作） | 兩廠條款四次連不上、從未被滿足 |
| f | **anchor：work ID ＋ 唯一 primary anchor ＋ milestone 分組**（§3.1） | 進度由 GitHub 原生算；唯一 anchor 避免跨 repo 各持一份站別 |
| g | **Commander No-Hands**（ADR-NP-008，§5.0 為其實作） | 主 session 既編排又產出＝被審者兼審查者；deliverable 一律外派才有獨立的第二雙眼睛 |

## 10. 驗收測試

1. **站序不可跳（三組）**：1→3、2→4、3→5 各跑一次 ⇒ 三組皆遭拒、各自列出被跳過站的未滿足條件、回讀 anchor 確認 label 未變。
2. **票欄位 fail-closed**：四張票（缺 basis／缺 depends_on／缺測試先行／完整）⇒ 站 3 gate fail 並具名前三張；補齊後 pass。
3. **面板錯誤四情境**：假 repo ⇒「數據過期」；人為觸頂 ⇒「資料可能不完整」；關掉站 3 的 anchor ⇒「工作消失」＋ work ID ＋ 上次所見站別；面板寫入失敗 ⇒ 文字輸出完整摘要＋過期告警。
4. **消失偵測無基線**：刪除面板 artifact 後首刷 ⇒ 橫幅「消失偵測不可用（無基線）」，且字卡內容與刪除前一致（對應 SC#1）。
5. **寫後回驗**：gate 寫入後直讀 anchor 一致才回報成功；模擬寫入失敗 ⇒ 不宣稱推進成功並具名。
6. **狀態 label 寫入單點（兩層）**：跑 board／run／intake（含 native）後，檢查所有 `sc:` 狀態 label 的最後 `labeled` 事件 actor 皆為 gate 執行身分；併同人工審四份 SKILL.md，確認只有 gate 含寫狀態 label 指示。
7. **站別歸因與復位**：以個人帳號手動改 anchor station label ⇒ board 紅燈「站別來源不明」、run 拒絕選件；跑 gate 復位 ⇒ 回退至最後一次合法事件站別；刪光合法事件後再跑 ⇒ 落 `sc:awaiting-user` 並停手。
8. **站 5 雙審**：兩份報告分開留存未合併；輸入清單核對（軸 A 無 spec 原文、軸 B 無 smell 基線）；含隔離未實測標註（移除 ⇒ gate fail）；以 executor 本人當 verifier ⇒ gate fail；通過後該票被 gate 關閉。
9. **逃生口不死鎖**：在 DECISIONS.md 記一筆「本票升兩廠」⇒ gate fail 並提示二擇一；選降級並記 DECISIONS.md 後 ⇒ 可繼續推進。
10. **站別粒度**：一個 work 下三張票（兩張站 5、一張站 4）⇒ anchor 站別為站 4；關閉站 4 那張後重跑 gate ⇒ anchor 升為站 5。
11. **進度分列**：同 work ID 的 milestone 分散兩 repo ⇒ 字卡逐 repo 分列原生百分比、不出現合成單一數字；work ID 不同但 milestone 同名 ⇒ 不得合併。
12. **進線兩模式**：native 與 legacy 各跑一次 ⇒ 皆建出 milestone、primary anchor（body 含 repo 全集）、首個 label 由 gate 落；legacy 另有定站結論與缺件分類且字卡帶 `legacy` badge，補齊後 gate 通過 ⇒ badge 消失。
13. **開工、executor 與失敗回滾**：對站 4 票跑 run ⇒ 票 body 的 `executor` 欄位被寫入 agent 名、assignee 被指派為執行身分帳號、該票計入「在跑數量」；**字卡的 executor 顯示值須等於 body 欄位而非 assignee 帳號**；無 assignee 的 open 站 4 票不得計入；模擬 dispatch 失敗 ⇒ assignee 被移除並具名回報；造一張逾 24 小時無 timeline 事件的票 ⇒ 計入「停滯票數」。
14. **對帳三態**：`plans/` 無紀錄 ⇒「對帳範圍外」；run 觸發刷新 ⇒「本次未對帳，沿用 <時間> 結果」；`plans/` 不可用 ⇒「對帳未執行」。
15. **豁免有牙與 fail-closed**：參與 repo 之一放過期豁免 ⇒ gate fail 並落 `sc:gate-fail`；使某 repo 的 DECISIONS.md 讀取失敗 ⇒ gate fail；該檔不存在 ⇒ 不 fail。
16. **薄度**：run 在站 4 派工 ⇒ 實際執行者為 ak-engineer 的 agent／skill；四份 SKILL.md 行為皆不超出 §2 白名單。
17. **執行身分驗證**：以使用者本人 OAuth token 跑初始化 ⇒ **拒絕初始化**並具名輸出歸因失效理由；改配獨立 bot token ⇒ 初始化通過，且後續 gate 寫入的 `labeled` 事件 actor 為該 bot。
18. **完成態收尾**：一個 work 的最後一張票經站 5 gate 通過關閉 ⇒ anchor 落 `sc:station-done`、anchor 被關閉、全參與 repo 的 milestone 被關閉；另造一個「零 open 票但有一張人手關閉的票」的 work ⇒ 不判完成、落 `sc:awaiting-user`。
19. **站別推進原子性**：觀察 gate 推進站別的 API 呼叫 ⇒ 為單一次「設定完整 label 集合」；回驗比對的是完整集合；過程中不存在無站別或雙站別的中間態。
20. **站 5 修復復驗**：清完 finding 後直接結案 ⇒ gate 拒絕；補上 verifier 對修復後狀態的重驗（或兩軸補審）後 ⇒ 方可結案關票。
21. **legacy 舊票上限**：對一個帶舊格式票的既有專案跑 intake ⇒ 定站不得高於站 3；補齊七欄位（或具名記「不收編」並重拆 native 票）後 ⇒ 方得經 gate 進站 4。
22. **No-Hands**：任一站的 deliverable（spec 文字、票內容、程式、測試、審查報告）⇒ 追查其產出者必為 dispatch 的 executor，非主 session；以「主 session 直接寫出票內容」情境驗證 ⇒ 該 artifact 判無效並被重派（§5.0）。面板 HTML 由 board 現算 ⇒ **不觸發**違規（§2 邊界裁定）。

## 11. 風險

| # | 風險 | 影響 | 可能性 | 緩解 |
|---|---|---|---|---|
| 1 | **label 被人手動改** | 高——站序鎖失效 | 中 | §3.4 原生 timeline actor 歸因（無自建簿記可被繞過）：board 紅燈、run 拒絕選件、gate 復位模式；驗收 #7 |
| 2 | **執行身分沿用使用者 OAuth**（Cowork 預設）⇒ timeline 歸因整組靜默失效 | **高**——§3.4 的全部防護歸零且不會報錯 | 高（若不強制驗證） | §6.1⑤ 初始化硬性驗證 bot 身分 ≠ 使用者互動帳號，不過即拒絕安裝並具名；驗收 #17。殘餘：四 skill 共用同一 bot ⇒ 機器層仍證不了「哪個 skill 寫的」，由規範層人工審補足（SC#7） |
| 3 | **ak CLI 在 Cowork 為 ephemeral**（`ak-plan` 與對帳同時受影響） | 中 | 高 | 路由表標註前置需求；run 於 dispatch 前檢查並提示 `/ak-cli-setup`，提供純 agent 退路；對帳不可用時標「對帳未執行」而非綠燈 |
| 4 | **同環境雙審的共享盲點** | 中——雙審只覆蓋一種視角 | 中 | 輸入分離為主要防線；SC#6 強制標註直到實測條目落地；站 4 verifier 為獨立第二道防線 |
| 5 | **逃生口長期不可用**（外廠管道不存在） | 中 | 高 | 逃生口載體改為 DECISIONS.md（不製造無人可摘的 label）；降級須具名可稽核；接入路徑列入升 CI 階段必要項 |
| 6 | **search 最終一致性／結果上限** | 中——面板誤報 | 中 | 判定一律走 issues API 直讀＋timeline；search 只做聚合並附不完整示警 |
| 7 | **skill 膨脹** ⇒ 退化成第二個 fleet-command | 中 | 中 | SC#8 白名單＋硬上限 ≤5；新增 skill 須在 DECISIONS.md 具名說明「為何不能併入既有四個」 |
| 8 | **豁免累積成靜默技術債** | 中 | 中 | 條目強制含「本項【未】處理」與期限；gate 每次掃全參與 repo，過期即 fail；明細走 gate 文字輸出 |

## 12. 審查回應（第三輪，定稿）

**HARD**
軸1-01 → executor 與 assignee 解耦：executor 身分的唯一真相源＝**票 body 的 `executor` 欄位**（ak-engineer agent／skill 名），`assignee` 降級為「指派執行身分帳號」的**二元開工訊號**；面板 executor 欄改讀 body 欄位（開頭名詞段、§2 run、§3.3、§3.5、§4.1、驗收 #13）｜
軸1-02 → §3.2 新增**完成態唯一斷點**：零 open 票且全票經站 5 gate 關閉 ⇒ 寫 `sc:station-done`、關 anchor、關全參與 repo milestone；明寫「最小站公式在零票時無定義，完成態不由它推導」；有人手關閉的票 ⇒ 不判完成、落 `sc:awaiting-user`（§6 新增 done 列、驗收 #18）｜
軸1-03 → gate 白名單補「**讀 plugin repo 的 DECISIONS.md**」（SC#6 解除條目、gate 執行身分宣告）｜
軸1-04 → board 白名單補「**dispatch `project-manager`（僅完整模式對帳）**」｜
軸2-01 → 🔴 硬性要求 **gate 執行身分為獨立 bot token 且 ≠ 使用者人類互動帳號**；§6.1⑤ 於安裝／初始化實查驗證，不過即拒絕並具名說明；SC#7 標明此為機器層成立的前提；風險 2 改寫為此項（驗收 #17）。

**judgement（全數吸收，無留待站 3 項）**
軸1-05 → §3.1 改寫為「`sc:station-*` 僅存 anchor」，§3.3 表新增**合法載體**欄逐 label 標註（anchor／票／兩者）｜
軸1-06 → §4.3 明定分界：work 整個不在 `plans/`＝範圍外；work 有紀錄則其下票級差異一律算漂移｜
軸1-07 → §7.3 新增舊票收編條款：**legacy 定站上限站 3**，直到舊票補齊七欄位或具名記「不收編、重拆 native 票」；舊票格式屬次要工件可豁免，可執行驗收條件不得豁免（驗收 #21）｜
軸1-08 → §5 指明兩份基線正典位置：12 條 smell 基線**隨 plugin 出貨住 plugin assets**；repo 規範＝該 repo 內既有文件且 gate 須具名所用版本；衝突時 repo 規範優先｜
軸1-09 → §8 新增寫入路徑兩條：使用者手寫，或 dispatch `docs-manager`／`git-manager` 開 PR 經使用者確認合併；🚫 禁任何 skill 直接 push 寫入｜
軸1-10 → §4.4 零筆＋無基線時「無 active work」卡與「消失偵測不可用」橫幅**並列**，不得只顯示其一｜
軸2-02 → §3.4 明定站別推進＝**單一次「設定完整 label 集合」呼叫**，禁 remove＋add 兩步；回驗比對完整集合（驗收 #19）｜
軸2-03 → §2 run：dispatch 失敗 ⇒ **立即移除 assignee** 並具名回報（驗收 #13）｜
軸2-04 → §5 結案條件新增**修復必須復驗**：修復 commit 須經 verifier 重跑驗收條件，或兩軸就修復 diff 補審一輪（驗收 #20）。

**不採納**：無。本輪 5 HARD ＋ 9 judgement 全數採納。

## 未解問題

1. 舊 fleet-command「仍生效規則」盤點的**負責人與完成日**未定——依 §9d 為停用前置條件。
2. Cowork 平行 sub-agent 的 context 是否真互不可見——**未實測**；SC#6 強制標註，實測票須列站 3，結論寫 plugin repo DECISIONS.md。
3. **獨立 bot token 的取得方式**（GitHub App vs machine user）與其在 Cowork 的可用性——**本 spec 已把「≠ 使用者互動帳號」定為硬性前提（§6.1⑤），但取得路徑須在站 3 第一批票中實作驗證**；若實測不可行，整組 timeline 歸因需回站 1 重議。
4. 名詞表補「Commander」「gate 執行身分」「executor（≠ assignee）」三條目——本 spec 已自定義，待站 1 正典追認。
5. plugin 命名 `station-command` 是否定案。
