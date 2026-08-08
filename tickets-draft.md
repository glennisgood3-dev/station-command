# station-command · 站 3 票集草案（未發布）

依據：Spec **v1.11（定稿）**｜規則：Pocock to-tickets 原文（tracer-bullet 垂直切片、blocking edges、prefactoring 先做、票內禁檔案路徑與程式碼片段）＋ 本專案**八欄位**（Spec §3.5，含第八欄「不可逆動作」）

> **狀態：草案，已經 `kongming` 複核並吸收全部修正，待使用者 quiz 核准。** 發布動作本身為 T-01 的後續（plugin repo 尚不存在）。
> REQ-ID 採「spec 章節／SC 編號」形式，確保每張票可回溯到定稿條文。
> **DECISIONS.md 寫入通則（§8）**：所有票對 DECISIONS.md 的寫入一律**經 PR 提出、由使用者確認合併**，不得直接推送。

---

## T-01 · 建立 plugin repo 與兩本 Log 種子
**Blocked by**：無（可立即開工）
**What it delivers**：plugin repo 存在，內含依 Spec §8 模板建立的 DECISIONS.md 與 CHANGELOG.md，各含首筆條目；DECISIONS.md 預留「gate 執行身分宣告」條目位（由 T-02 填值）。完成即可 demo：任何人 clone 後看得到兩本 Log 與其欄位結構。
- **REQ-ID**：REQ-§8
- **驗收條件（可執行）**：以文字比對確認兩檔存在，且 DECISIONS.md 首筆條目具備六欄（日期／ID／類型／裁示內容／依據／裁示人）、CHANGELOG.md 具備版本號與四類變更區塊。**紅燈設計**：先寫「兩檔存在且欄位齊全」的檢查清單並於建檔前執行 ⇒ 必紅（檔案不存在）。**紅燈獨立預期值來源**＝Spec §8 的欄位清單（人讀正典，非本票產物）。
- **depends_on**：[]
- **executor**：`docs-manager`｜**basis**：產出是兩份規範文件與其模板實例，文件結構一致性是該 agent 的本職
- **scope**：plugin repo 的 README 與兩本 Log；不含任何 skill 檔或 GitHub 自動化
- **測試先行**：先落檢查清單並跑出紅燈，再建檔轉綠

## T-02 · 獨立 bot token 可行性實測（翻盤前提）
**Blocked by**：T-01
**What it delivers**：一份**已落檔的結論**——Cowork 環境能否取得並使用「≠ 使用者人類互動帳號」的 bot／GitHub App token 寫 label，且 timeline 的 `labeled` 事件 actor 顯示為該 bot。結論以具名條目經 PR 寫入 plugin repo DECISIONS.md。
- **REQ-ID**：REQ-§6.1⑤、REQ-SC7、REQ-風險2
- **驗收條件（可執行）**：DECISIONS.md 中存在該具名條目，且條目內含 ① 實測時**讀到的 actor 值原文**（不是轉述）② **二擇一的明確結論**（可行／不可行）；若結論為不可行，條目必須含「**§3.4 timeline 歸因失效，須回站 1 重議**」字樣。⚠️ **本票的通過條件是結論落檔，不是結論為正**——不可行也算通過，只是觸發回站 1。**紅燈設計**：先以使用者 OAuth token 跑同一次 actor 讀取作為對照組 ⇒ 讀值必等於使用者帳號（紅，判定失效）。**獨立預期值來源**＝bot 與使用者兩個帳號名稱皆為實驗前已知的外部固定值。
- **depends_on**：[T-01]
- **executor**：`researcher`｜**basis**：這是外部平台能力的事實查核，不是實作題；查錯了會讓整組歸因白做
- **scope**：身分取得路徑、actor 讀值實測、結論落檔（經 PR）；不含任何 skill 實作
- **測試先行**：先跑使用者 OAuth 對照組取得紅燈讀值，再換 bot token 取得對照讀值，兩組讀值一併入條目

## T-03 · sub-agent context 隔離實測（SC#6 解除條件）
**Blocked by**：T-01
**What it delivers**：兩個 parallel fresh-context `general-purpose` sub-agent 是否互不可見的實測結論，以具名條目 `SC-DEC-ISO-001` 經 PR 寫入 plugin repo DECISIONS.md。結論為「隔離成立」時，SC#6 的強制標註方得解除。
- **REQ-ID**：REQ-SC6、REQ-§5.2
- **驗收條件（可執行）**：`SC-DEC-ISO-001` 條目存在，含 ① 實驗 protocol（canary 配置方式）② 兩個 sub-agent 的原始回覆節錄 ③ 二擇一結論。判定法：對兩個平行 sub-agent 各餵一個對方不知情的 canary 字串，兩者皆答「看不到另一組輸入」且輸出中無對方 canary ⇒ 隔離成立。**紅燈設計**：先跑刻意共用同一 context 的對照組 ⇒ canary 必外洩（紅）。**獨立預期值來源**＝實驗者事前自訂的兩組 canary 字串。
- **depends_on**：[T-01]
- **executor**：`researcher`｜**basis**：protocol 設計、回覆判讀與條目草擬皆為 deliverable，須由被派的 agent 產出；**平行 dispatch 的動作本身由 Commander 執行，屬 §5.0 的「派」，不是 deliverable**
- **scope**：隔離實驗、判讀與條目落檔（經 PR）；**不改任何 spec 條文**，SC#6 標註規則本身不受本票阻擋
- **測試先行**：先跑共用 context 對照組取得洩漏紅燈，再跑平行組取得對照結果

## T-04 · 舊 fleet-command 仍生效規則盤點
**Blocked by**：T-01
**What it delivers**：一份逐條清單——舊 plugin 的規則哪些仍生效、哪些已被 Spec v1.5 吸收、哪些作廢；每條標明建議新家（本 spec 條文／某 repo 的 DECISIONS.md／作廢）與理由。清單含具名負責人與完成日。
- **REQ-ID**：REQ-§9d
- **驗收條件（可執行）**：**分母 fixture**——先從舊三份文件逐一列舉既有條目編號，凍結為固定清單（此後不因盤點過程改變）。驗收＝盤點清單對該 fixture 的**覆蓋率 100%** 且每條「新家」欄非空。**抽驗由 verifier（≠ 本票 executor）執行**：隨機抽 5 條，反查其在舊文件中的出處與所述內容相符。**紅燈設計**：盤點前先跑覆蓋率檢查 ⇒ 必紅（覆蓋率 0）。**獨立預期值來源**＝凍結的條目編號 fixture（外部既存事實，非盤點產物）。
- **depends_on**：[T-01]
- **executor**：`Explore`｜**basis**：這是「把散落規則找齊」的搜尋題，遺漏的成本遠高於判錯｜**verifier**：`code-reviewer`（≠ executor）
- **scope**：凍結分母 fixture、產清單與建議新家；**不動任何檔案**（搬移是 T-05）
- **測試先行**：先凍結 fixture 並跑覆蓋率檢查取得紅燈，再逐條補齊

## T-05 · 仍生效規則搬移落檔（停用前置條件）
**Blocked by**：T-04
**What it delivers**：T-04 清單中每一條「仍生效」規則，實際落到其指定新家；清單狀態全數轉為「已搬移」或「已具名作廢」。這是 §9d 停用舊 plugin 的**前置條件**。
- **REQ-ID**：REQ-§9d
- **驗收條件（可執行）**：對清單逐條反查新家，命中率 100%；作廢類條目在 DECISIONS.md 有具名作廢紀錄（含「本項不再生效」字樣）。**紅燈設計**：搬移前跑逐條反查 ⇒ 必紅（命中率 0）。**獨立預期值來源**＝T-04 凍結的 fixture 與其清單（上游票的固定輸出，非本票自產）。
- **depends_on**：[T-04]
- **executor**：`docs-manager`｜**basis**：搬移是把既有條文放進正確文件並保持格式一致，屬文件治理而非判斷
- **scope**：搬移與作廢紀錄；不含停用動作（T-20）
- **測試先行**：先寫逐條反查檢查取得紅燈，搬完轉綠

## T-06 · plugin 骨架與動作白名單宣告〔prefactor〕
**Blocked by**：T-01
**What it delivers**：可安裝的 plugin：manifest ＋ 四份 SKILL.md 骨架，各自於文件開頭宣告自己的 §2 白名單與 No-Hands 邊界，並回覆既定佔位訊息。完成即可 demo：安裝後四個 /指令在 Cowork 出現。
- **REQ-ID**：REQ-§2、REQ-SC8、REQ-§5.0
- **驗收條件（可執行）**：安裝後四個 /指令皆可觸發並回既定佔位訊息；人工審四份 SKILL.md ⇒ 只有 gate 含寫狀態 label 的指示，其餘三份含明文禁令。**紅燈設計**：先寫「四個指令存在且各回既定訊息」檢查於安裝前執行 ⇒ 必紅。**獨立預期值來源**＝Spec §2 的 skill 清單與白名單表。
- **depends_on**：[T-01]
- **executor**：`fullstack-developer`｜**basis**：需同時處理 plugin 封裝結構與四份 skill 的一致性，屬跨層裝配
- **scope**：manifest 與四份 SKILL.md 骨架；不含任何 GitHub 讀寫邏輯
- **測試先行**：先寫指令存在性檢查取得紅燈，再裝配骨架

## T-07 · label scheme 與 anchor／milestone 慣例落地〔prefactor〕
**Blocked by**：T-01（與 T-06 平行，不互相阻擋）
**What it delivers**：在測試 repo 建出 Spec §3.3 的全部 `sc:` label（名稱／描述含合法載體註記），以及 work ID、anchor body 宣告、milestone description 三種格式的可填模板。
- **REQ-ID**：REQ-§3.1、REQ-§3.3
- **驗收條件（可執行）**：以 API 列出該 repo 的 label 集合並與 Spec §3.3 表逐一比對（名稱與載體註記全中、無多餘 `sc:` label）。**紅燈設計**：建立前跑同一比對 ⇒ 必紅。**獨立預期值來源**＝Spec §3.3 表格（人讀正典）。
- **depends_on**：[T-01]
- **executor**：`fullstack-developer`｜**basis**：純機械性建置，對象是 GitHub 上的 label 與格式模板，不依賴 plugin 骨架是否就緒
- **scope**：label 與三種格式模板；不含任何 skill 行為
- **測試先行**：先寫 label 集合比對取得紅燈，建完轉綠

## T-08 · 進線：intake native ＋ gate 初始化路徑〔首個垂直切片｜🔒 不得增肥〕
**Blocked by**：T-02、T-06、T-07
**What it delivers**：使用者跑一次 `/station-intake` native ⇒ 建 milestone ＋ primary anchor（body 宣告 repo 全集）⇒ 經 gate 初始化路徑五條判準（含身分驗證）落 `sc:station-1`。完成即可獨立 demo：一個新工作真的上了生產線。
- **REQ-ID**：REQ-§7.1、REQ-§6.1、REQ-§2
- **驗收條件（可執行）**：跑一次後以 API 讀回：milestone description 含 work ID 與 anchor 指標；anchor 帶 `sc:work` 且 body 含 repo 全集；anchor 有 `sc:station-1` 且該 `labeled` 事件 actor 為 bot。另以使用者 OAuth 重跑 ⇒ 必須拒絕初始化並具名輸出失效理由。**紅燈設計**：先寫「anchor 存在且帶 station-1 且 actor 為 bot」斷言 ⇒ 未實作時必紅。**獨立預期值來源**＝使用者輸入的 work ID 與 repo 清單，以及 T-02 已確認的 bot 帳號名。
- **depends_on**：[T-02, T-06, T-07]
- **executor**：`fullstack-developer`｜**basis**：這張穿過 skill → GitHub 寫入 → 回驗三層，需要能實跑 API 的執行體
- **scope**：intake native 模式與 gate 初始化路徑；不含 legacy 模式、不含站別推進。🔒 **不得增肥**：quiz 後任何加料一律開新票
- **測試先行**：先寫初始化後狀態斷言與 OAuth 拒絕斷言，兩者皆紅後才實作

## T-09 · 面板最小可用（單 work 字卡＋四種異常狀態）
**Blocked by**：T-08
**What it delivers**：`/station-board` 產出常駐 artifact，單 work 字卡含 Spec §4.1 欄位；並實作空狀態、數據過期、資料可能不完整、面板寫入失敗四種顯示。完成即可 demo：側邊欄看得到工作與其異常。
- **REQ-ID**：REQ-§4.1、REQ-§4.4、REQ-SC4
- **驗收條件（可執行）**：四情境逐一觸發，**觸發手法明定**——① 數據過期：查詢清單混入一個不存在的 repo 名；② 資料可能不完整：把分頁上限調到低於實際筆數以模擬觸頂；③ 面板寫入失敗：以一個不存在的 artifact ID 發更新請求；④ 空狀態：對一個零筆結果的查詢條件執行。四者各自須出現規定文案、具名對象與上次成功時間；失敗情境不得顯示為「無工作」。**紅燈設計**：先寫四情境斷言 ⇒ 未實作時全紅。**獨立預期值來源**＝Spec §4.4 的文案與具名要求。
- **depends_on**：[T-08]
- **executor**：`fullstack-developer`｜**basis**：四種異常狀態的判定與觸發皆是資料與錯誤路徑處理；HTML 由既有資料機械 render，依 §2 裁定屬編排輸出、不違反 No-Hands｜**顧問**：`ui-ux-designer`（資訊層級與狀態可辨識度審視，不產出實作）
- **scope**：單 work 字卡與四種異常顯示；不含跨 repo 聚合與對帳
- **測試先行**：先寫四情境斷言取得紅燈，再實作 render

## T-10 · gate 推進、寫後回驗與歸因復位〔🔒 不得增肥〕
**Blocked by**：T-08
**What it delivers**：`/station-gate` 能判當前站出口條件、以**單一次「設定完整 label 集合」**推進、寫後以 issues API 直讀回驗、偵測不合法歸因並執行復位模式兩分支。完成即可 demo：一個工作被合法推進，被手動竄改後能被 gate 抓出並復位。
- **REQ-ID**：REQ-§3.4、REQ-§4.4、REQ-§6、REQ-SC2
- **驗收條件（可執行）**：① 1→3、2→4、3→5 三組跨站請求皆被拒且 label 未變；② **gate 側斷言**——以個人帳號手動改 anchor 站別後跑 gate ⇒ gate 判定歸因不合法、拒絕推進並要求先復位（面板顯示行為屬 T-16，本票不驗）；③ 跑復位 ⇒ 回退至最後一次合法事件所設站別；④ 刪光合法事件後跑復位 ⇒ 落 `sc:awaiting-user` 並停手；⑤ 觀察推進呼叫為單一次完整集合設定、過程無無站別／雙站別中間態。**紅燈設計**：先寫跨站拒絕與「不合法歸因必被 gate 擋下」兩條斷言 ⇒ 必紅。**獨立預期值來源**＝Spec §6 checklist 與 GitHub 原生 timeline 事件記錄。
- **depends_on**：[T-08]
- **executor**：`fullstack-developer`｜**basis**：狀態機核心，原子性與回驗都必須實跑 API 才驗得出來
- **scope**：出口條件判定、推進、回驗、歸因偵測與復位；不含豁免掃描（T-19）、不含面板顯示（T-16）。🔒 **不得增肥**：quiz 後任何加料一律開新票
- **測試先行**：先寫三組跨站拒絕斷言與歸因擋下斷言取得紅燈

## T-11 · 路由表與 12 條 smell 基線 asset〔prefactor〕
**Blocked by**：T-01（與 T-06 平行）
**What it delivers**：隨 plugin 出貨的兩份 asset——站→executor＋basis 路由表，以及 12 條 Fowler smell 基線；並落「站 5 報告須具名所用 repo 規範版本」的規則說明。
- **REQ-ID**：REQ-§5.1、REQ-§5.2
- **驗收條件（可執行）**：基線 asset 條目數為 12 且逐條與 Pocock 原文標題一致；路由表覆蓋 Spec §5.1 的每一列且每格 basis 非空。**紅燈設計**：先寫「12 條齊全且路由表列數相符」比對 ⇒ 必紅。**獨立預期值來源**＝Pocock `code-review` 原文與 Spec §5.1 表格。
- **depends_on**：[T-01]
- **executor**：`docs-manager`｜**basis**：屬正典文件落地，需與一級來源逐字對齊，判斷成分低、對齊成分高；內容不依賴 plugin 骨架
- **scope**：兩份 asset 與其引用規則；不含任何審查執行邏輯
- **測試先行**：先寫條目數與標題比對取得紅燈

## T-12 · 派工：選件、executor 寫入、開工訊號與失敗回滾
**Blocked by**：T-10、T-11
**What it delivers**：`/station-run` 驗歸因 → 選出無 blocker 且 `depends_on` 已滿足的可動作項 → 依路由表定 executor＋basis 並寫入票 body → 指派 assignee 作二元開工訊號 → dispatch；dispatch 失敗即移除 assignee 並具名回報。
- **REQ-ID**：REQ-§2、REQ-§3.5、REQ-§4.1
- **驗收條件（可執行）**：① 對一張站 4 票跑 run ⇒ 票 body 的 executor 欄位有值、assignee 被指派、字卡 executor 顯示值等於 body 欄位而非帳號名；② **回滾以人造中間態 fixture 驗證**——預先造出「assignee 已指派 ＋ dispatch 回傳失敗」的狀態，跑回滾路徑 ⇒ assignee 被移除且輸出具名失敗（不依賴真實 dispatch 恰好失敗）；③ 站別歸因不合法時 ⇒ 拒絕選件。**紅燈設計**：先對該 fixture 跑「回滾後 assignee 為空」斷言 ⇒ 必紅（未實作時 assignee 殘留）。**獨立預期值來源**＝fixture 的預設狀態與 T-11 路由表 asset。
- **depends_on**：[T-10, T-11]
- **executor**：`fullstack-developer`｜**basis**：需實跑 dispatch 成功與失敗兩條路徑，回滾正確性只能實測
- **scope**：run 的選件、寫欄位、開工訊號、dispatch 與回滾；不含各站的專屬 gate 檢查
- **測試先行**：先造中間態 fixture 並跑回滾斷言取得紅燈

## T-13 · 站 3 拆票與八欄位 gate
**Blocked by**：T-12
**What it delivers**：run 在站 3 dispatch 拆票 executor；gate 對票集檢查 Spec §3.5 **八欄位**（含第八欄「不可逆動作：有／無＋說明」）與「切片可獨立驗收」；缺 executor／basis 判 `[INVALID]`。完成即可 demo：一份不合格票集被具名擋下。
- **REQ-ID**：REQ-§3.5、REQ-§6（站 3）、REQ-SC3
- **驗收條件（可執行）**：造**五張票**（缺 basis／缺 depends_on 欄位／缺測試先行／**缺第八欄「不可逆動作」**／完整）⇒ gate fail 並具名前四張與其缺項；補齊後重跑 pass。⚠️ **欄位總數為八**（§3.5），🚫 不得殘留「七欄位」判準。**另增兩項（依 Spec v1.11:95、99–112、286）**：⑤ 第七欄「測試先行」須具名 **① 本票測試打在哪個 seam ② 獨立預期值來源**——造兩張「有測試先行文字但未具名 seam」與「未具名獨立預期值來源」的票 ⇒ gate 各自 fail 並具名缺項；⑥ 站 3 出口條件須含「**seam 已於拆票 quiz 中經使用者確認**」——未確認即推站 ⇒ gate 拒絕並具名。⚠️ **兩項皆為第七欄的內容檢查，欄位總數仍為八**（註 B／註 C 不是新欄位）；⚠️ seam 確認**併入既有拆票 quiz**，🚫 **不新增獨立步驟或第二個人類 gate**。**紅燈設計**：先寫「三張問題票被具名」斷言 ⇒ 必紅（未實作時全數放行）。**獨立預期值來源**＝Spec §3.5 的欄位清單（含註 B／註 C）與人造票的缺項配置。
- **depends_on**：[T-12]
- **executor**：`fullstack-developer`｜**basis**：gate 檢查與 run dispatch 同層且共用票結構，分開派工要重載同一份欄位定義
- **scope**：站 3 的拆票 dispatch 與票集檢查；不含票內容本身的品質判斷
- **不可逆動作**：**無**——本票動作為 ① dispatch 拆票 executor ② gate 讀票判欄位 ③ 寫狀態 label（推站或落 `sc:gate-fail`）④ 驗收時建人造測試票。四者皆可逆：label 可由 gate 復位模式回退（§3.4），issue 建立後可關閉，無 deploy／刪資料／對外寄送／付費／開權限。⚠️ 具名殘留：拆票 executor 於 dispatch 後在其內部自行觸發的動作**不在本欄涵蓋範圍**（Spec §5.3a 已具名此邊界），由該 executor 自身權限邊界承接
- **測試先行**：先寫五票斷言取得紅燈

## T-14 · 站 4 驗收與 red-proven
**Blocked by**：T-12
**What it delivers**：站 4 交件的兩段證據檢查（紅必須是斷言失敗的紅，非載入失敗）、verifier（≠ executor）實測、通過後由 gate 於**票上**落 `sc:red-proven`。
- **REQ-ID**：REQ-§6（站 4）、REQ-§3.3
- **驗收條件（可執行）**：① 造一份「紅燈其實是載入失敗」的交件 ⇒ gate 拒絕並具名原因；② 造合格交件 ⇒ 票上出現 `sc:red-proven` 且該事件 actor 為 bot；③ 以 executor 本人充當 verifier ⇒ 拒絕；④ **預期值出處查核（依 Spec v1.11:287、§3.5 註 C）**：造一份「斷言的預期值由被測程式自身產生」的交件（自證式斷言，如以被測函式的回傳值當作預期值）⇒ verifier 須具名拒絕並指出該斷言；造一份預期值來自獨立真相源（known-good literal／worked example／spec）的交件 ⇒ 通過。⚠️ 具名：本項與①**同源不同落點**——①管紅燈的**型態**（要斷言失敗、非載入失敗），④管斷言的**預期值出處**（不得自證），兩條合起來才蓋滿 S3「防 AI 作弊」。**紅燈設計**：先寫「載入失敗型紅燈被拒」斷言 ⇒ 必紅（未實作時會被當成合格紅燈放行）。**獨立預期值來源**＝人造交件所附的測試輸出原文與其預期值出處標記（人為配置，非由被測 gate 產生）。
- **depends_on**：[T-12]
- **executor**：`fullstack-developer`｜**basis**：本票要實作的是 gate 內的檢查與落標邏輯，屬實作題｜**verifier**：`tester`（≠ executor，正好由本票自身滿足 verifier ≠ executor 規則）
- **scope**：站 4 交件檢查與 red-proven 落標；不含站 5 審查
- **不可逆動作**：**無**——本票動作為 gate 內的交件檢查與寫 `sc:red-proven` label，判讀對象是**人造交件所附的測試輸出原文**（靜態文本），不執行被測系統；label 可摘除。⚠️ **具名殘留（本欄不承接）**：日後 verifier 若改為**實跑被測 repo 的測試套件**，該套件內部若含 deploy／刪資料型測試，屬「dispatch 之後 executor 內部自行觸發」的情形——Spec §5.3a 已具名該類不在票級事前宣告的涵蓋範圍，須由該 executor 的權限邊界與站 5 交件檢查承接，**不得**以本欄填「無」為由視為已排除
- **測試先行**：先寫三條拒絕／通過斷言取得紅燈（含④自證式斷言被拒）

## T-15a · 站 5 票級雙審、修復復驗與關票
**Blocked by**：T-11、T-14
**What it delivers**：兩軸 parallel fresh-context sub-agent 的 dispatch 與輸入分離、報告不合併不重排、修復 commit 復驗、通過後由 gate 關閉該票。
- **REQ-ID**：REQ-§5.2、REQ-§6（站 5）
- **驗收條件（可執行）**：① 兩份報告分開留存且輸入清單核對（軸 A 無 spec 原文、軸 B 無 smell 基線）；② 未經復驗即結案 ⇒ 拒絕；③ 以 executor 本人當 verifier ⇒ 拒絕；④ 通過後該票被關閉且關閉動作 actor 為 bot；⑤ 在 `SC-DEC-ISO-001` 落檔前，結案報告缺隔離未實測標註 ⇒ gate fail（此規則不需 T-03 完成即可實作與驗證，未實測是預設狀態）；⑥ **收尾摘要**：報告結尾的一行摘要須含 **(a) 各軸 findings 總數**、**(b) 該軸軸內的 worst issue（若有）**；缺任一項 ⇒ gate fail；且輸出中 **🚫 不得出現跨軸挑出的單一贏家**（人造「軸 A 3 條、軸 B 1 條」的案例，斷言摘要出現兩個軸內 worst、不出現單一總體 worst）——依 Spec v1.11:230–234。**紅燈設計**：先寫「未復驗即結案被拒」斷言 ⇒ 必紅。**獨立預期值來源**＝Spec §5.2 條文與人造的兩軸輸入清單（⑥另以人造 finding 清單的條數與嚴重度配置為預期值，非由被測報告產生器自身計算）。
- **depends_on**：[T-11, T-14]
- **executor**：`fullstack-developer`｜**basis**：兩軸 dispatch 編排與關票寫入需實跑，輸入分離是否真的分離只能從實際 prompt 清單驗
- **scope**：票級雙審、復驗、關票；**不含 work 級完成態收尾**（T-15b）；⚠️ **亦不含 merge**——本票不執行任何分支合併，merge 判準與合併動作不在本票 scope
- **不可逆動作**：**無**（逐項具名判定，🚫 非一律填無）——① **雙審 dispatch**：兩軸 sub-agent 只讀 diff／spec／規範，唯讀；② **修復復驗**：重跑該票驗收條件，不改碼；③ **關票**：close issue **可重開**，且 §3.2 已為「人手關閉的票」設有 `sc:awaiting-user` 回收路徑 ⇒ 可逆；④ **merge 不在本票 scope**（見上），故五類中的 deploy 不經本票發生。⚠️ **兩項具名殘留**：(a) 若日後把 merge 併入本票 scope，本欄須**重判為「有 ⇒ deploy」**（合併至預設分支可能觸發 CI 部署，revert 收不回已部署的副作用）——此為本欄的重判觸發條件；(b) 站 5 sub-agent 於其內部自行觸發的動作不在本欄涵蓋範圍（Spec §5.3a 已具名該邊界）
- **測試先行**：先寫復驗斷言取得紅燈

## T-15b · work 級完成態收尾
**Blocked by**：T-15a
**What it delivers**：該 work 全票關閉後，gate 寫 `sc:station-done` 並關閉 anchor 與全參與 repo 的 milestone；存在人手關閉的票時不判完成、改落 `sc:awaiting-user`。
- **REQ-ID**：REQ-§3.2、REQ-§6（done 列）
- **驗收條件（可執行）**：① 最後一張票經站 5 gate 通過關閉 ⇒ anchor 落 `sc:station-done`、anchor 與全部參與 repo 的 milestone 皆被關閉；② 造「零 open 票但其中一張是人手關閉」的 work ⇒ 不判完成、落 `sc:awaiting-user`；③ 零票時不得套用「最小站」公式（以無錯誤發生驗證）。**紅燈設計**：先寫「人手關閉票的 work 不得判完成」斷言 ⇒ 必紅（未實作時零 open 票即被誤判完成）。**獨立預期值來源**＝人造的兩種 work 收尾狀態（關閉方式為實驗者指定）。
- **depends_on**：[T-15a]
- **executor**：`fullstack-developer`｜**basis**：純 GitHub 收尾寫入與判定，與 T-15a 的 dispatch 編排是兩種活，分開才裝得進單一 context
- **scope**：完成態判定與收尾寫入；不含站 5 審查流程
- **不可逆動作**：**無**——動作為寫 `sc:station-done`／`sc:awaiting-user`、**關閉** anchor issue、**關閉**全參與 repo 的 milestone。三者皆可逆：label 可摘、issue 可重開、**milestone 可 reopen**；五類皆不沾。⚠️ **具名殘留**：本票是全票集中**作用面最廣**的一張（一次動到多個 repo 的 milestone），誤判會**批次**誤關——但**廣度不等於不可逆**，防線為 §3.2 完成態判定＋驗收②（存在人手關閉的票 ⇒ 不判完成），🚫 不以第八欄代替。**重判觸發條件**：若收尾動作日後由「關閉 milestone」擴為「**刪除** milestone」⇒ 須重判為「**有 ⇒ 刪資料**」（GitHub 刪 milestone 不可復原，且會從所有 issue 上抹除歸屬）
- **測試先行**：先寫人手關閉斷言取得紅燈

## T-16 · 跨 repo 聚合、work ID 分組、逐 repo 進度與消失偵測
**Blocked by**：T-09
**What it delivers**：一次跨 repo search 聚合並按 work ID 分組、逐 repo 分列 milestone 原生百分比（不加權）、anchor 消失偵測、無基線橫幅（含零筆＋無基線並列）、以及站別來源不明的字卡紅燈顯示。
- **REQ-ID**：REQ-§4.2、REQ-§4.4、REQ-SC1
- **驗收條件（可執行）**：① 同 work ID 的 milestone 分散兩 repo ⇒ 合併為一張字卡並分列兩組百分比、不出現合成單一數字；② milestone 同名但 work ID 不同 ⇒ 不得合併；③ 關掉一個站 3 的 anchor ⇒ 出現「工作消失」＋work ID＋上次所見站別；④ 刪除面板 artifact 後首刷 ⇒ 出現「消失偵測不可用（無基線）」且字卡內容與刪除前一致；⑤ 零筆＋無基線 ⇒ 兩訊息並列；⑥ 手動竄改過站別的工作 ⇒ 字卡紅燈標「站別來源不明」。**紅燈設計**：先寫「不同 work ID 不得合併」斷言 ⇒ 必紅（未實作時以名稱分組會誤併）。**獨立預期值來源**＝測試資料中人為指定的 work ID 與 repo 對應表。
- **depends_on**：[T-09]
- **executor**：`fullstack-developer`｜**basis**：這是資料正確性與查詢邊界題，聚合誤併只能靠人造對應表反證
- **scope**：聚合、分組、進度分列、消失偵測、站別來源不明顯示；不含對帳
- **不可逆動作**：**無**——GitHub 側**全唯讀**（search／issues／timeline），唯一寫入是面板 artifact，而面板依 §4.2 是**顯示快取非真相源**，刪除或重建只降級消失偵測、不損任何站別真相。⚠️ **具名殘留（驗收步驟本身）**：驗收③要求「關掉一個站 3 的 anchor」、④要求「刪除面板 artifact」——兩者皆可逆（issue 可重開、artifact 可重建），但**須在測試 repo／人造 fixture work 上執行**，🚫 不得對真實生產 work 執行關 anchor 步驟
- **測試先行**：先寫誤併斷言與無基線斷言取得紅燈

## T-17 · 對帳三態（範圍外／未對帳／漂移）
**Blocked by**：T-16
**What it delivers**：完整模式 dispatch `project-manager` 比對 GitHub 與本機 `plans/`；實作「對帳範圍外／本次未對帳／對帳未執行」三種標示與漂移三類；只報不修，修復方向逐案由使用者裁示並記 DECISIONS.md。
- **REQ-ID**：REQ-§4.3
- **驗收條件（可執行）**：**正向斷言**——① `plans/` 整個查無此 work ⇒ 字卡上「對帳範圍外」標示**存在**且該卡非綠燈；② `plans/` 有此 work 但票缺 ⇒ 回報的**漂移筆數等於人造差異集的筆數**，且逐筆票號與差異集相符；③ 由 run 觸發的刷新 ⇒ 標示為「本次未對帳，沿用 <時間> 結果」；④ `plans/` 不可用 ⇒ 標示為「對帳未執行」。**守恆檢查（非紅燈）**：對帳前後兩側內容摘要不變，作為「只報不修」的回歸檢查。**紅燈設計**：先對人造差異集跑「漂移筆數＝差異集筆數」與「範圍外標示存在且非綠燈」兩條正向斷言 ⇒ 必紅（未實作時筆數為 0、標示不存在）。**獨立預期值來源**＝人為構造的 `plans/` 與 GitHub 差異集（筆數與票號皆為實驗者預設值）。
- **depends_on**：[T-16]
- **executor**：`fullstack-developer`｜**basis**：三態判定與筆數比對是實作題；`project-manager` 於執行期被 dispatch 負責比對本身
- **scope**：對帳三態、漂移筆數回報與守恆檢查；不含任何自動修復
- **不可逆動作**：**無**——GitHub 側與 `plans/` 側**皆唯讀**，本票**只報不修**（§4.3 A-10：修復方向逐案由使用者裁示），輸出僅為字卡標示與文字摘要。🔴 **「只報不修」正是本票判無的唯一理由**，故 **重判觸發條件**寫死：若日後加入**任何自動修復**（改寫 `plans/` 檔案或改 GitHub 票狀態）⇒ 須重判為「**有 ⇒ 刪資料**」（覆寫既有 `plans/` 內容即資料損失，且 `plans/` 是計畫敘事 durable source）。守恆檢查（對帳前後兩側內容摘要不變）即本條的機器化保險
- **測試先行**：先寫兩條正向斷言取得紅燈

## T-18 · legacy 收編：auditor、定站上限站 3、badge 生命週期
**Blocked by**：T-10、T-13
**What it delivers**：`/station-intake` legacy 模式共用 native 建立步驟；起 fresh-context auditor 逐條對照 §6 checklist 定站；舊票未收編前定站上限站 3；`sc:legacy` badge 至通過第一個 native gate 才摘除。
- **REQ-ID**：REQ-§7.2、REQ-§7.3、REQ-SC5
- **驗收條件（可執行）**：① 對一個帶舊格式票的既有專案跑 legacy ⇒ 定站不高於站 3、字卡帶 legacy badge、auditor 報告逐條有 ✓／✗ 與證據指向；② 補齊**八欄位**（§3.5，含第八欄「不可逆動作」）（或具名記「不收編、重拆 native 票」）後跑 gate ⇒ 方得進站 4；③ 通過第一個 native gate ⇒ badge 消失。**紅燈設計**：先寫「定站不得高於站 3」斷言 ⇒ 必紅（未實作時 auditor 可能直接判在站 4）。**獨立預期值來源**＝Spec §6 checklist 與該既有專案的實際工件清單。
- **depends_on**：[T-10, T-13]
- **executor**：`fullstack-developer`｜**basis**：需編排 auditor dispatch 並寫 GitHub 狀態，跨編排與寫入兩層
- **scope**：legacy 模式全流程；auditor 報告內容由被 dispatch 的 agent 產生
- **不可逆動作**：**無**——動作為建 milestone、建 anchor issue、寫狀態 label 與 `sc:legacy`、dispatch auditor（唯讀讀工件）。建立類與 label 類皆可逆（issue／milestone 可關閉，label 可摘），五類皆不沾。⚠️ **具名殘留（本票獨有）**：本票是全票集中**唯一作用於「既有真實專案 repo」**的一張——誤收編會在他人 repo 留下 milestone 與 issue，清理需人工。屬**外溢非不可逆**，處置：驗收須在測試 repo 或已取得該 repo 擁有者確認的專案上執行。**重判觸發條件**：若 legacy 模式日後擴為「**改寫或刪除既有舊票**」（而非只新增 native 票）⇒ 須重判為「**有 ⇒ 刪資料**」；現行 §7.3 的兩條路徑（補齊八欄位／不收編另拆 native 票）皆不改寫舊票，故現況判無成立
- **測試先行**：先寫定站上限斷言取得紅燈

## T-19 · 豁免有牙與 DECISIONS.md 掃描 fail-closed
**Blocked by**：T-10
**What it delivers**：gate 每次執行掃描**全參與 repo** 的 DECISIONS.md；過期豁免 ⇒ 本次 gate fail 並落 `sc:gate-fail`；讀取失敗 ⇒ fail-closed；檔案不存在 ⇒ 視為無豁免不 fail。
- **REQ-ID**：REQ-§7.4、REQ-§6（全站列）
- **驗收條件（可執行）**：三情境各跑一次 ⇒ 過期豁免必 fail 且落 `sc:gate-fail`；讀取失敗必 fail；檔案不存在必 pass。另驗證掃描涵蓋 anchor body 宣告的全部參與 repo（缺一 repo 未掃即算失敗）。**紅燈設計**：先寫「過期豁免必 fail」與「讀取失敗必 fail」兩斷言 ⇒ 必紅（未實作時皆 pass，屬 fail-open）。**獨立預期值來源**＝人為構造的豁免條目日期與參與 repo 清單。
- **depends_on**：[T-10]
- **executor**：`fullstack-developer`｜**basis**：屬 gate 內判定邏輯，失敗語意（open/closed）只能實跑三情境驗證
- **scope**：豁免掃描與失敗語意；不含豁免條目的撰寫
- **不可逆動作**：**無**——動作為讀全參與 repo 的 DECISIONS.md（唯讀）與落 `sc:gate-fail` label（可摘）；本票明文**不撰寫、不修改、不移除任何豁免條目**（scope 已排除）。⚠️ **具名（風險方向相反）**：本票是 **fail-closed** 型，其誤判方向是**過度阻擋**（把本可推進的 work 擋下），不是造成不可回復的損害——擋錯了補一次豁免條目即解，故不觸及第八欄。**重判觸發條件**：若 gate 日後對過期豁免改為**自動移除條目**或**自動關票** ⇒ 須重判（移除 DECISIONS.md 條目違反 §8「只追加不改寫」，屬刪資料形狀）
- **測試先行**：先寫兩條 fail 斷言取得紅燈

## T-20 · 舊 fleet-command 停用〔expand–contract 的 contract 段〕
**Blocked by**：T-05、T-08
**What it delivers**：**停用前置檢查通過、文件轉唯讀正典、停用後驗證**——⚠️ **本票不代使用者執行停用動作本身**（與 scope 及 executor basis 一致；停用為使用者手動步驟，本票只驗證「指令不再可觸發」）。
🔴 **本票明定**：「T-08 之 gate 初始化路徑成功落 `sc:station-1`」**即算首個 native gate 通過**，作為停用的第二個前置條件；不另外依賴 T-10。
- **REQ-ID**：REQ-§9d
- **驗收條件（可執行）**：① **防呆以人造 fixture 驗證**——餵一份命中率不足的假搬移清單給前置檢查 ⇒ 必須中止且具名缺項（不依賴真實時序）；② 餵完整清單 ＋ 一筆 `sc:station-1` 落標紀錄 ⇒ 前置檢查通過；③ 停用後隨機抽 5 條仍生效規則，皆可在新家查得；④ 舊 plugin 指令不再可觸發。**紅燈設計**：先以假清單 fixture 跑前置檢查 ⇒ 必須紅（中止），證明防呆有效。**獨立預期值來源**＝人造假清單的預設缺項與 T-04 凍結的 fixture。
- **depends_on**：[T-05, T-08]
- **executor**：`git-manager`｜**basis**：負責的是前置檢查與文件唯讀化，屬版本控管操作；**停用動作本身為使用者手動步驟**，本票只驗證「指令不再可觸發」
- **scope**：前置檢查、文件唯讀化、停用後驗證；不含規則搬移本身，不含代替使用者執行停用
- **不可逆動作**：🔴 **有 ⇒ 開權限（權限撤銷側）**——本票三個動作逐一判定：**(a) 前置檢查**＝唯讀比對搬移清單命中率 ⇒ 無；**(b) 文件唯讀化**＝對既有 repo 的**權限狀態變更**（archive repo／branch protection／撤銷寫入權，實作路徑未定，見下）⇒ **有**；**(c) 停用後抽驗**＝唯讀查證 ⇒ 無。判「有」的理由具名：權限一經撤銷，**回復需另一個持有更高權限的身分再動一次手，loop 自己收不回來**——「開權限」類涵蓋權限狀態的授予**與撤銷**，判準是回滾權不在執行者手上，不是技術上能不能改回去。
  ⚠️ **條件性升級**：若「唯讀化」的實作含**移除舊 plugin 檔案或目錄**、且該內容不在版本控管內 ⇒ 本欄升為「**有 ⇒ 刪資料**」。票面現未界定唯讀化的實作路徑，**此為必須在 dispatch 前釐清的缺口**。
  🔴 **loop 停手點**：依 §5.3a 停止條件①，run 於 **dispatch 本票之前**讀取本欄，宣告為「有」即停手待使用者裁示，🚫 不得由 loop 自動觸發。與 §9d 一致（停用須具名負責人與完成日、且「仍生效規則盤點搬移完成」為前置條件）。
  ⚠️ **粒度限制具名**：第八欄是**票級**宣告，攔不到「只在 (b) 之前停、讓 (a) 自動跑」。若要那種粒度，**正確做法是拆票**（前置檢查一張、唯讀化一張），🚫 **不是把本欄改寫成「無」**——那會讓停止條件①失去唯一的事前訊號。本輪不拆票（🚫 不新增票），列為待裁示。
- **測試先行**：先以假清單 fixture 取得中止紅燈，再以完整清單轉綠
> 📌 **待辦（已裁示：現在不拆，記為待辦）**：**T-05 落檔關票後，重新評估是否把 T-20 拆為「前置檢查」與「唯讀化＋驗證」兩張，以取得 dispatch 粒度。** **觸發條件＝T-05 關票。** 現在不拆的理由具名：(a) 前置檢查 blocked by T-05，而 T-05 的三條分歧甫裁定、尚未落檔 ⇒ 此刻拆票等於拆在浮動的依賴上。⚠️ 在拆票完成前，本票第八欄維持「**有**」、整票走 §5.3a 停止條件①，🚫 **不得**為了讓 (a) 自動跑而把第八欄改寫成「無」。

---

## 依賴序（發布順序）

```
T-01 ─┬─ T-02 ──────────────┐
      ├─ T-03（獨立，不阻擋任何票）
      ├─ T-04 → T-05 ───────┼──────────────→ T-20
      ├─ T-06 ──────────────┤
      ├─ T-07 ──────────────┴→ T-08 ─┬───────↑
      └─ T-11 ──┐                    ├─ T-09 → T-16 → T-17
                │                    └─ T-10 ─┬─ T-12 ─┬─ T-13 ─┐
                │                             │        └─ T-14 ─┴→ T-15a → T-15b
                └─────────────────────────────┤                 ↑
                                              └─ T-19          （T-11）
                                       T-10 + T-13 ──────────→ T-18
```

**無 blocker、可立即開工**：T-01
**T-01 完成後可六路平行**：T-02、T-03、T-04、T-06、T-07、T-11
