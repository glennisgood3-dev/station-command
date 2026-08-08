# CHANGELOG.md（station-command plugin repo）

Keep a Changelog 形式；spec 與 ADR 不寫沿革，一律外移到此（依 Spec §8）。

## [0.1.0] - 2026-08-08

### Added
- `Spec_station-command_v1.11.md` 定稿（434 行）：§5.2 refactor 歸屬（refactor 屬站 5 review 階段，不屬站 4 red→green loop）、§5.1 站 1「事實自己查」紀律（查得到的事實 dispatch sub-agent 自查，只有決策問使用者；整輪 frontier 一次問完）、§3.5 註 B（測試 seam 須事前寫下並於拆票 quiz 經使用者確認）／註 C（斷言預期值須具名獨立真相源）、§6 註 A（站 4 紅燈型態的來源標註：「先紅後綠」＝Pocock 原文、「斷言失敗之紅」＝使用者 S3 本地增設）、§9.1 舊 fleet 條文作廢紀錄（SK-07／AM-10／AM-11、SK-18、AM-16 三族具名重判）
- 站 3 補票 T-27～T-31（`tickets-vendor-draft.md`，異廠 executor 路由五張票，已過使用者裁示定稿）
- 16 個 build 交付目錄：
  - `build/t13/`：站 3 拆票八欄位深度 gate（含註 B／註 C 具名檢查，缺 executor／basis 判 `[INVALID]`，fail-closed）
  - `build/t14/`：站 4 驗收——紅→綠兩段證據＋預期值獨立性查核，verifier 實測後落 `sc:red-proven`
  - `build/t15a/`：站 5 票級雙審、修復復驗與關票（兩軸輸入分離、SC#6 標註、gate 唯一關票者）
  - `build/t15b/`：work 級完成態收尾（`sc:station-done`、關 anchor 與全參與 repo milestone、人手關票不判完成）
  - `build/t16/`：面板跨 repo 聚合、work ID 分組、逐 repo 原生進度與 anchor 消失偵測
  - `build/t17/`：對帳三態（範圍外／未對帳／漂移；只報不修，修復方向逐案交使用者裁示）
  - `build/t18/`：legacy 收編（fresh-context auditor、定站上限站 3、`sc:legacy` badge 生命週期）
  - `build/t19/`：豁免有牙——全參與 repo DECISIONS.md 掃描，過期豁免與讀取失敗皆 gate fail（fail-closed）
  - `build/t24/`：session 內 loop 主體（選件三判準＋停止條件窮舉六條）
  - `build/t25/`：停因通知與收尾批次摘要（停因②③④⑥主動推播、①⑤安靜退出）
  - `build/t26/`：CI 階段 spec（收攏全部 deferred-to-CI 條目，含覆蓋率檢查與紅綠證據）
  - `build/t27/`：廠商登錄表 asset（12 家 provider／端點／認證／格式家族／狀態，隨 plugin 出貨）
  - `build/t28/`：異廠呼叫適配層（四格式家族最小適配、連接資料夾 key 路徑、逾時與至多一次重試、具名降級、key 四表面掃描、12 家兩層可達性檢查）
  - `build/t29/`：成本邊界（每票 token 上限、逐次記帳進 gate 紀錄、50／80／100% 三段告警接停止條件⑥）
  - `build/t30/`：站 5 A 軸異廠接線與分歧裁決（兩份 finding 原樣並列、重疊標 strongest-overlap、分歧具名交裁示、禁多數決）
  - `build/t31/`：Gemini 首發端到端實測交付（v1beta `generateContent` 腳本＋離線 mock；真實呼叫具名由 Commander 執行）

### Changed
- 停止條件五條→六條：新增⑥「外廠累計成本達上限 100%」（ADR-NP-010② 2026-08-08 增訂；Spec §5.3a／§7.6；50%／80% 僅告警不停手，理由具名「花下去拿不回來，與①不可逆同級」）
- 票欄位七欄→八欄：新增第八欄「不可逆動作：有／無＋說明」（Spec §3.5，供停止條件①的票級事前判定；八項任一缺漏即站 3 gate fail）
- 可達性判準改兩層（SC-DEC-REACH-001）：第一層可達性＝有無收到任何 HTTP 回應（僅網路層失敗與 421 proxy 攔截算不可達）；第二層探測品質＝狀態碼落 200／401／403／429 之外判 WARN 非 FAIL。原單層判準會把「伺服器有回應但路徑或方法不對」誤判成連不到。實測 REACHABILITY 12/12、PROBE 11/12（Perplexity WARN 為具名預期）
- executor 路由變更（SC-DEC-ROUTE-001，部分推翻 ADR-NP-011④）：站 4 實作 executor 改由 Codex CLI（gpt-5.6-sol，reasoning effort high）承接；Plan 與 Review 維持 Claude（fable）；Commander 職責不變。同日 ADR-NP-011① 否決範圍縮限為「跑在使用者本機的 CLI」（SC-DEC-CLI-001），兩處修正皆以後加具名段記於 ADR.md，原文照留

### Fixed
- T-12 與 T-13 的 CLI 參數作用域污染導致的靜默 no-op：dot-source cascade 下游同名變數覆蓋 CLI 參數，`run-select.ps1`／`run-dispatch.ps1` 帶齊參數執行卻 exit 0 零輸出、`run-apply.ps1` 的 `-PatPath` 被靜默換成下游預設值。修法＝**動態 AST 快照防火牆**（由各 CLI 自己的 `param()` AST 動態取全部宣告參數快照、dot-source 後還原，不硬寫變數名）＋**真子行程 smoke test**（`t12-scope-smoke.ps1`，以 `/opt/pwsh/pwsh` 子行程執行而非 dot-source，斷言失敗型紅燈）；T-13 `gate-station3.ps1` 套用同一修法
- T-27 端點比對由多重集合改逐列配對：原版 `sorted(端點) == sorted(預期)` 只驗多重集合，對調 OpenAI 與 Cohere 兩家端點後仍判 ALL GREEN（假綠）；rework 改為逐列 `(provider, endpoint)` 配對，對調變異版轉紅並附紅燈證據與舊法假綠交叉確認
- T-28 `key-leak-scan.ps1` 直接執行由零輸出 exit 0 改為輸出 usage banner（純函式庫具名自陳；SC-DEC-ADV-001，防 CLI 靜默 no-op 事故形狀重演）

### Deprecated
- SK-07／AM-10／AM-11（A-9 派工令獨立審核官族，含 R3 取證權）：不搬入 station-command，SP-11 不採納（SC-DEC-RETIRE-038；Spec §9.1——Pocock 原文派工前覆核零命中，角色分離已由 verifier ≠ executor 吸收）
- SK-18（站 3 出口 gate 兩廠×三軸深審）：不搬入，SP-12 不採納（SC-DEC-RETIRE-039；兩軸為 Pocock 原文寫死，「過度設計」已由 Standards 軸 Speculative Generality 涵蓋，站 3 出口是使用者核准）
- AM-16（A-14 忙碌不等於進展）：不搬入，SP-10 不採納（SC-DEC-RETIRE-040；Pocock 原文與 S1–S5 零命中，面板維持既有「停滯票數（24h 無事件）」欄位不加新指標）

## [0.0.0] - 2026-08-05

### Added
- repo 建立（station-command plugin repo 起始化）
- 共識文件進駐：`ADR.md`（ADR-NP-001～008）、`GLOSSARY.md`
- `Spec_station-command_v1.5.md` 定稿進駐
- 站 3 票集進駐：21 張票（`tickets-draft.md`，T-01～T-20，含 T-15a／T-15b）
