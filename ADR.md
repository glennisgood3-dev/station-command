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

## ADR-NP-009 · timeline 歸因延至 CI 階段啟用

彥揚 2026-08-05 裁示，依 T-02 實測報告（翻盤點條款觸發）：
Cowork 手動階段無法取得「≠ 使用者」的 gate 執行身分。兩件**不同**的事，勿混：
① **【量測】Cowork 現在完全寫不了 GitHub**——MCP `push_files` 回 403
   `Resource not accessible by integration`（2026-08-05 實測 3 次，讀取同時正常）；
   Bash 對 api.github.com 被 session proxy 攔截。此為 §4.6 待寫佇列的存在理由。
② **【推論】即使 ① 日後修好**，官方 MCP 走 user-to-server token，架構上
   actor＝使用者本人 ⇒ 機器歸因仍不成立。此為本條延後歸因的理由。
① 修好則 §4.6 廢止，② 仍須等 CI。
⇒ **手動階段**：timeline 機器歸因不啟用，降級為規範層（SKILL.md 禁令）＋人工複查；
   §6.1⑤ 身分驗證改為「檢查並具名回報當前身分」，不作 fail 條件。
⇒ **CI 階段**（§9a 既定第二階段）：以 `github-actions[bot]`（原生滿足身分要求）啟用
   完整 timeline 歸因，§3.4 全套防線屆時生效。
凍結票（T-08 起）依此解凍。否決：混合架構（本機 machine-user PAT 代寫——非同步
交接、養第二帳號、actor 無 [bot] 徽章，成本高體驗差）。

## ADR-NP-010 · 站 4／5 自主派工循環（補站 1 漏採之需求）

彥揚 2026-08-05 裁示。**成因（誠實記錄）**：使用者原版 S4/S5 明寫「gives high
autonomy to Ai」，站 1 grill 五問未問到自主權；舊 fleet 的心跳／喚醒綁在
fleet_state.json 上，ADR-NP-002 廢掉狀態檔時，T-04 把整組心跳判作廢（SK-08、
PR-08），但**無人重新安置「S4/S5 要自主」這條需求**。本條補回。

**① 兩層喚醒**
- session 內：`/station-run` 進入 loop，持續派工至停止條件成立。
- 跨 session：Cowork 排程（cron）定時開新 session，讀 GitHub 現況後續派。
- 兩層共用同一套停止條件；狀態一律從 GitHub 現算，**不引入任何狀態檔**
  （這正是本設計優於舊心跳之處——舊心跳的 sync 陷阱源於 fleet_state.json）。

**② 停止條件（窮舉，其餘一律自動續跑）**
1. 不可逆動作前：deploy／刪資料／對外寄送／付費／開權限
2. gate 連續失敗：rework 2 次仍 fail
3. 站 1／2／3 的人類 gate：共識確認、spec 確認、拆票 quiz
4. scope 需變更
5. frontier 空（無可動作項）
6. **累計成本達上限 100%**（彥揚 2026-08-08 增訂，解 §7.6 與本條的對撞）
   ——理由：花下去拿不回來，與第①條「不可逆」同級。50%／80% 僅告警不停手。
   ⚠️ 本清單為**窮舉**，新增停止條件一律改本條並具名，不得散落他處。
⇒ **站 4／5 內部的 dispatch、驗收、雙審、merge 一律不問**（承接舊 v0.28.3
「merge 五條判準全過即合」常設授權，本條不推翻）。

**③ 寫入斷點：累積待寫佇列**
Cowork 現階段寫不了 GitHub（T-02、ADR-NP-009）。loop 照跑（讀狀態、派工、
收件、判 gate），把所有寫入動作（推站、發票、關票）累積成待寫清單＋一支本機
套用腳本，使用者有空跑一次全部落地。⇒ **自主權不因寫入斷點歸零**：實作、
審查、判定都真的在跑，只有「蓋章」延後。升 CI 後本條自然消失。

**④ 喚醒頻率**：平日 09:00–22:00（Asia/Taipei）每小時一次；有活就做、無活
安靜退出（不發通知）。夜間不跑。

**⑤ 修訂（同日，v1.7 缺口審 FAIL 11 HARD 後）**：**第二層（跨 session 排程
喚醒）延至 CI 階段啟用**，手動階段只啟用第一層（session 內 loop）。
成因：loop 賴以運作的三個訊號——在跑標記（assignee）、失敗計數
（`sc:gate-fail`）、稽核痕跡（留言）——全部需要寫 GitHub，手動階段寫不進去
⇒ 新 session 讀到的必然是過期視圖 ⇒ **同一票每小時被重派、多 executor 併行
改同一檔案且全程無聲**。session 內 loop 不受影響（Commander 自身即記憶）。
同時修正 ③ 的過度宣稱：**程式碼產出**同樣推不上 GitHub 且隨 ephemeral
container 蒸發，「只有蓋章延後」僅適用於 issue metadata，不適用 code；
手動階段 code 產出的留存另定（本機 patch 落地）。

## ADR-NP-011 · 異廠 executor 路由（補站 1 漏採之需求）

彥揚 2026-08-08 裁示。**成因（誠實記錄）**：站 1 grill 未問「executor 是否限
Claude」；T-11 路由表因此只列 AgentKit 的 16 個 agent——它們全是 Claude
sub-agent，差別僅在 system prompt 與模型層級（`kongming`＝fable，其餘＝session
模型）。⇒ **至今所有工作皆由單一廠牌完成，異廠交叉檢視一次都沒發生**，而
A-30「兩廠」條款想要的正是這個。本條補回。

**① 管道：API 直呼，不走本機 CLI**
【量測，2026-08-08 沙盒實測】12 家 AI API **全部可從 Cowork 沙盒直達**，
無一被 proxy 攔截（401/403/429＝連得到僅缺 key；OpenRouter 回 200 直通）：
OpenAI｜Gemini｜OpenRouter｜xAI Grok｜DeepSeek｜Mistral｜Groq｜Together｜
Perplexity｜Cohere｜Fireworks｜Cerebras。
另【量測】以使用者現有 Gemini key 實呼 `gemini-2.0-flash` 得 **429 配額不足**
——證明 key 驗證通過、請求確實送達 Google，非網路阻擋。
⇒ **否決本機 CLI 路線**（Codex CLI 等）：沙盒碰不到本機，每票需使用者當人肉
管道，非同步交接成本高於收益。API 直呼無此問題。

**①-修正（2026-08-08，彥揚裁示，SC-DEC-CLI-001；原文照留不刪）**：
上段否決理由「沙盒碰不到本機」**已被實測推翻**——【量測，2026-08-08】`@openai/codex`
0.147.0 可直接以 npm 安裝於 **Cowork 沙盒內**，具備檔案系統與 shell、可自行執行
`/opt/pwsh/pwsh` 測試並迭代；`api.openai.com` 自沙盒回 401（可達，僅缺 key）。
⇒ **否決範圍縮限為「跑在使用者本機的 CLI」；跑在沙盒內的 CLI 不在否決之列。**
量測依據具名：Codex CLI 於沙盒內完成 T-15b／T-25／T-28／T-29／T-30／T-31 六張票的
executor 工作，每張約 180k tokens 計於 OpenAI 帳，未消耗主 session context。

**② 名單策略：先寫上，保留可能**
路由表新增 `provider` 維度，**一次登錄上列 12 家全部**（含端點、認證方式、
呼叫格式家族：OpenAI-compatible／Gemini／Anthropic／Cohere）。有 key 者標
`available`，無 key 者標 `registered-no-key`——**登錄不等於啟用**，日後補 key
即可用，不必回頭改架構。新廠商加入只是表格加一列。

**③ 首發：Gemini（使用者現有 key，待儲值）**
其餘 11 家保持 `registered-no-key`。OpenRouter 列為**建議的擴充路徑**（一把 key
覆蓋多廠、格式統一、換模型只改字串），待使用者需要第二家時啟用。

**④ 適用站別（先寫上，逐步啟用）**
站 5 雙審 A 軸（規範審，脈絡依賴低、只需 diff＋規範清單，最適合外包）｜
站 2 出口缺口審｜站 3 拆票複核。**站 4 實作維持 Claude**（需完整 repo 脈絡與
工具鏈）。ADR-NP-007 的「單票裁示升兩廠」逃生口，本條為其實體。

**④-部分推翻（2026-08-08，彥揚裁示，SC-DEC-ROUTE-001；原文照留不刪）**：
上段「站 4 實作維持 Claude」**部分推翻**——站 4 實作的 executor 改由
**Codex CLI（gpt-5.6-sol，reasoning effort high）**承接；Plan 與 Review 維持
Claude（fable）；Commander 職責不變（ADR-NP-008 只指派不自己做）。理由具名：
① verifier ≠ executor 同時成為**真正的異廠交叉檢視**，本條④想要的盲點互補
由此達成；② 三方分工實測有效——executor（無網路）、Commander（有網路）、
verifier（對抗性）各補一塊，T-28 可達性缺陷即由此鏈抓出。前提變更與①-修正
同源：沙盒內 CLI 具完整檔案系統與工具鏈，「純 API 給不了工具鏈」對沙盒內
CLI 不成立。

**⑤ 分歧裁決：不合併、不投票、兩份並列**
承接 A-30 R1（報告不得合併、不得跨軸重排）：兩廠各自的 finding **各自完整存在**，
重疊處是最強訊號，分歧處由 gate **具名列出交使用者裁示**。
🚫 **禁多數決**——多數決會把「只有一家看到的真問題」投掉，而那正是異廠的價值
所在（承接 §Q.9.1a「禁 2vs1 多數決」）。🚫 亦不得以「Claude 為準、外廠僅供參考」
降級外廠 finding——那等於抛棄盲點互補這個唯一理由。

**⑥ 成本邊界：每票上限＋累計告警**
承接舊 protocol §7：每張票的外廠呼叫設 **token 上限**，超過即停手並具名回報，
不得靜默截斷；每次呼叫記 token 與估算成本至該票 gate 紀錄。累計花費達使用者
設定門檻的 **50%／80%／100%** 三段告警（100% 強停、輸出已有結果）。
⚠️ 外廠為**按量計費**（非包月），與 Claude session 的成本模型不同——此差異須在
路由表具名，避免下一個人誤以為換 executor 是零成本決定。

**⑦ 降級**
外廠不可用（無 key／配額不足／API 錯誤／逾時）⇒ **降級回單廠並具名記錄**，
不得靜默跳過、不得阻塞生產線。key 一律走連接資料夾檔案，不進對話、不進 repo、
不寫 log。

## 承接不變（非本次裁示，列出供對照）

站序不可跳｜站 2 出口第三方審｜站 4 先紅後綠｜站 5 兩軸平行、報告不合併（兩廠條款已由 NP-007 supersede）｜
merge 判準五條｜Pocock 至上條款（A-28）衝突裁決順序照舊。
