# CHANGELOG.md（station-command plugin repo）

Keep a Changelog 形式；spec 與 ADR 不寫沿革，一律外移到此（依 Spec §8）。

## [0.1.1] - 2026-08-08

### Added
- `tickets-t20-split.md`：T-20 拆票結果（T-20a／T-20b 兩張完整八欄位票 ＋ 14 項承接對照表），依 `SC-DEC-SPLIT-001`
- DECISIONS Part E 四條：`SC-DEC-CARRIER-001`（正典載體更正：protocol 正典在 Drive，非 GitHub repo）、`SC-DEC-RO-001`（停用＝唯讀化保留，禁刪除）、`SC-DEC-SPLIT-001`（T-20 依不可逆動作邊界拆票）、`SC-DEC-LOG-001`（log 落檔流程缺陷登記）

### Changed
- 站 3 票集：原 T-20 單票由 T-20a／T-20b 取代；原 issue #21 以 `not_planned` 關閉並留拆票說明。T-20a 第八欄「無」⇒ 解除 §5.3a 停止條件①之阻擋，可由 loop 自動派工；T-20b 第八欄「有（開權限）」⇒ 仍停在使用者裁示
- T-20a executor 由 `git-manager` 覆寫為 `code-reviewer`，理由具名於票面 basis 欄（依 SC-DEC-005 無 basis 即 `[INVALID]`）

### Known Issues
- **T-20b 有兩項未定項未釐清，缺一不得 dispatch**：①Drive 正典的具體唯讀化做法（權限轉唯讀 vs 移入 archive 資料夾）與目標檔案清單 ②`glennisgood3-dev/fleet-ci` 是否在停用範圍內
- `Spec_station-command_v1.11.md:400` 驗收 #26 仍寫舊的單層四碼可達性判準，與 `SC-DEC-REACH-001` 不一致；歸屬無主，未開票
- `SC-DEC-NOOP-002`（靜默 no-op 升為 Spec 常設檢查項）與 `SC-DEC-LOG-001` 兩項改法之具體條文**待安置**——v1.11 已定稿，不在本次修改權內
- `build/t21/queue-common.ps1:83` 相對路徑寫回缺陷未修（T-21 已關票；GitHub 側 33 筆佇列全數套用成功，僅本機寫回空佇列檔失敗），需另開票
- `build/t26/ci-stage-spec.md:3` 狀態行仍停在第三輪，未隨第六輪 PASS 更新

## [0.1.0] - 2026-08-08

### Added
- `Spec_station-command_v1.11.md` 定稿（434 行）：§5.2 refactor 歸屬（refactor 屬站 5 review 階段，不屬站 4 red→green loop）、§5.1 站 1「事實自己查」紀律（查得到的事實 dispatch sub-agent 自查，只有決策問使用者；整輪 frontier 一次問完）、§3.5 註 B（測試 seam 須事前寫下並於拆票 quiz 經使用者確認）／註 C（斷言預期值須具名獨立真相源）、§6 註 A（站 4 紅燈型態的來源標註：「先紅後綠」＝Pocock 原文、「斷言失敗之紅」＝使用者 S3 本地增設）、§9.1 舊 fleet 條文作廢紀錄（SK-07／AM-10／AM-11、SK-18、AM-16 三族具名重判）
- 站 3 補票 T-27～T-31（`tickets-vendor-draft.md`，異廠 executor 路由五張票，已過使用者裁示定稿）
- 18 個 build 交付目錄：
  - `build/t09/`：面板最小可用（單 work 字卡、§4.1 全部欄位、§4.4 四種錯誤狀態、待寫佇列揭露，已併入原 T-23）
  - `build/t12/`：派工——選件三判準（無 blocker／`depends_on` 已滿足／尚無在跑 executor）、依路由表寫入票 body 的 `executor` 欄位、assignee 二元開工訊號、dispatch 失敗立即回滾（今晨初版＋今日 rework 修復 CLI 參數作用域污染，見 Fixed）
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
- CI 階段 spec（`build/t26/ci-stage-spec.md`）新增 `DTC-030`（29 條→30 條）：收攏站 2 第三方缺口審 H-2 指出的 `SC-DEC-ROUTE-001` 未收攏缺口——站 4 CI 階段實作 executor 改沙盒內 Codex CLI 的三項 runtime 前提（CLI 安裝、憑證供應——手動階段實錄以 ChatGPT 登入憑證共用 refresh token 會發生 `refresh_token_invalidated` 輪替衝突、成本併入 T-29 記帳）
- 可達性判準改兩層（SC-DEC-REACH-001）：第一層可達性＝有無收到任何 HTTP 回應（僅網路層失敗與 421 proxy 攔截算不可達）；第二層探測品質＝狀態碼落 200／401／403／429 之外判 WARN 非 FAIL。原單層判準會把「伺服器有回應但路徑或方法不對」誤判成連不到。實測 REACHABILITY 12/12、PROBE 11/12（Perplexity WARN 為具名預期）
- executor 路由變更（SC-DEC-ROUTE-001，部分推翻 ADR-NP-011④）：站 4 實作 executor 改由 Codex CLI（gpt-5.6-sol，reasoning effort high）承接；Plan 與 Review 維持 Claude（fable）；Commander 職責不變。同日 ADR-NP-011① 否決範圍縮限為「跑在使用者本機的 CLI」（SC-DEC-CLI-001），兩處修正皆以後加具名段記於 ADR.md，原文照留
- Codex CLI 憑證供應方式定案（SC-DEC-CLI-002）：延續 `SC-DEC-ROUTE-001` 之後的憑證前提，實錄以 ChatGPT 登入憑證（`auth.json`）快照供應時發生 refresh token 一次性輪替衝突（同一把 token 本機／沙盒兩處使用，任一方刷新即令另一方作廢，本輪實際命中 `refresh_token_invalidated`）。裁示：維持 ChatGPT 登入憑證，改採「後登入者贏」操作紀律（沙盒使用期間使用者不得執行本機 codex，含背景常駐 `codex app-server`／`codex remote-control`；收工後使用者重新 `codex login` 取回本機憑證）。⚠️ 本裁示取代本輪稍早未落檔的「改用 API key」暫定方向；OpenAI API key 為長期根治方案，本輪因剩餘工作量不足支撐額度儲值而未採用，日後長期沿用沙盒 CLI executor 應改採 API key
- T-26 完備性 fixture 錨定方式改判（SC-DEC-ANCHOR-001）：`build/t26/deferred-sources.tsv` 原以行號錨定活的正典檔（`CHANGELOG.md:31`），Commander 交件後編輯 CHANGELOG 插入兩行導致行號漂移、第四輪站 2 gate 誤判 FAIL；裁示改為以 needle 字串為主、行號為輔錨定，另定 gate 紀律：green 證據重跑時間須晚於最後一次正典編輯，否則綠燈只反映歷史狀態
- 「靜默 no-op」升為 Spec 層級常設檢查項（SC-DEC-NOOP-002）：本輪累計四例同型缺陷（登記見 SC-DEC-NOOP-001）促成此裁示；具體條文歸屬待安置，本次不逕行寫入已定稿之 `Spec_station-command_v1.11.md`

### Fixed
- T-12 與 T-13 的 CLI 參數作用域污染導致的靜默 no-op：dot-source cascade 下游同名變數覆蓋 CLI 參數，`run-select.ps1`／`run-dispatch.ps1` 帶齊參數執行卻 exit 0 零輸出、`run-apply.ps1` 的 `-PatPath` 被靜默換成下游預設值。修法＝**動態 AST 快照防火牆**（由各 CLI 自己的 `param()` AST 動態取全部宣告參數快照、dot-source 後還原，不硬寫變數名）＋**真子行程 smoke test**（`t12-scope-smoke.ps1`，以 `/opt/pwsh/pwsh` 子行程執行而非 dot-source，斷言失敗型紅燈）；T-13 `gate-station3.ps1` 套用同一修法
- T-27 端點比對由多重集合改逐列配對：原版 `sorted(端點) == sorted(預期)` 只驗多重集合，對調 OpenAI 與 Cohere 兩家端點後仍判 ALL GREEN（假綠）；rework 改為逐列 `(provider, endpoint)` 配對，對調變異版轉紅並附紅燈證據與舊法假綠交叉確認
- T-28 `key-leak-scan.ps1` 直接執行由零輸出 exit 0 改為輸出 usage banner（純函式庫具名自陳；SC-DEC-ADV-001，防 CLI 靜默 no-op 事故形狀重演）
- T-30 禁語守門（分歧輸出不得含「多數決」／「以 Claude 為準」兩種票面措辭）在 Windows PowerShell 5.1 上靜默失效：原寫法對 `ConvertTo-Json` 序列化後的字串跑 regex，5.1 底層 `JavaScriptSerializer` 會把非 ASCII 字元逐字轉成小寫 `\uXXXX`，逸出後的字串不再命中中文 regex，生產守門因此變成靜默 no-op、指定紅燈紅不起來。修法＝`Test-T30ContainsForbiddenDecisionLanguage`（`t30-core.ps1`）改為遞迴走訪物件的原生字串欄位、不經序列化比對，production 與 `t30-offline-test.ps1` 共用同一支函式。附可執行自證 `self-proof-m1-escape.ps1`（模擬 5.1 逸出規則：修前不命中／修後命中，見 `evidence/m1-escape-self-proof.txt`）
- 跨票 key 字面值污染：測試假 key 字串 `FAKE-KEY-DO-NOT-USE` 原以字面形式寫在 `build/t30` 的離線測試與 README；T-28 `t28-offline-test.ps1` 群組 E 的正式 repo 全域 key 掃描（掃描範圍為整個 repo 樹，不限 `build/t28`）會對此類字面值命中。已改為執行期以片段陣列組合產生（`t30-offline-test.ps1:133-134`：`@('FAKE','-KEY','-DO','-NOT','-USE') -join ''`），完整值不以字面形式落入 repo（作法已具名於 `build/t30/README.md:118`）

### Known Issues
- **尚未修復**：T-21 `queue-common.ps1:83`（`Write-QueueFile` 內 `[System.IO.File]::WriteAllText`）以相對路徑寫回佇列檔；PowerShell 的 `Push-Location`／`Set-Location` 不會同步 .NET 的 `Environment.CurrentDirectory`，呼叫端若先 `Push-Location` 切目錄再以相對路徑呼叫，寫入會依行程啟動時的工作目錄解析。`publish10/publish-all.ps1` 實跑即命中此陷阱，解析目標落在 `C:\WINDOWS\system32\close-queue.json` 而遭拒（`publish10/publish-phase3.ps1` 檔頭已具名記錄此次事故）。`apply-queue.ps1` 對 33 筆佇列項逐筆的 GitHub 套用與回驗（:195-216）皆先於最終寫回步驟（:219）完成，故該次故障只影響「已出列項目未能寫回本機空佇列檔」，GitHub 側狀態無損失。T-21 已關票；此缺陷本身尚未提修復票，目前僅由呼叫端規避（後續 `publish-phase3.ps1` 改用絕對路徑並顯式同步 `[Environment]::CurrentDirectory`），`queue-common.ps1` 本體未改
- T-30 一次 Codex CLI 派工因憑證於本輪使用期間失效（`refresh_token_invalidated`，見 Changed 段 SC-DEC-CLI-002）而中斷；工作隨即改派 Claude executor（`fullstack-developer`）承接並完成（key 字面值修正使全樹 `FAKE-KEY-DO-NOT-USE` 由 67/1 轉 68/0 零命中；其後獨立 verifier 判 REWORK 之 M-1 禁語守門 PS 5.1 逸出問題亦已修復並驗證，離線測試 46/46）；T-30 已驗收關票（GitHub issue #35，`sc:red-proven`），無未完成交付物。憑證失效造成的唯一實際損失是該次 Codex 派工中斷；供應紀律已定案，見 SC-DEC-CLI-002
- 四例「靜默 no-op」家族缺陷已登記（SC-DEC-NOOP-001，見 `build/t05/decisions-additions.md` Part D）：T-12／T-13、T-28、T-30 三例已修（見上方 Fixed 段），T-21（見本段上一則）尚未修；已裁示升為 Spec 層級常設檢查項（SC-DEC-NOOP-002），條文位置待安置

### Deprecated
- SK-07／AM-10／AM-11（A-9 派工令獨立審核官族，含 R3 取證權）：不搬入 station-command，SP-11 不採納（SC-DEC-RETIRE-038；Spec §9.1——Pocock 原文派工前覆核零命中，角色分離已由 verifier ≠ executor 吸收）
- SK-18（站 3 出口 gate 兩廠×三軸深審）：不搬入，SP-12 不採納（SC-DEC-RETIRE-039；兩軸為 Pocock 原文寫死，「過度設計」已由 Standards 軸 Speculative Generality 涵蓋，站 3 出口是使用者核准）
- AM-16（A-14 忙碌不等於進展）：不搬入，SP-10 不採納（SC-DEC-RETIRE-040；Pocock 原文與 S1–S5 零命中，面板維持既有「停滯票數（24h 無事件）」欄位不加新指標）

## [0.0.1] - 2026-08-06

### Added
- DECISIONS.md 追加二筆種子條目（`build/decisions-update/DECISIONS.md`）：`SC-DEC-BOT-001`（Cowork 手動階段無法取得獨立於使用者的 gate 執行身分——實測 3 次，MCP `push_files` 回 403 `Resource not accessible by integration`、Bash 對 `api.github.com` 被 session proxy 攔截，讀取端點正常；對照組本機 PAT 寫入之 actor 讀值原文為使用者本人 login；status: active）、`SC-DEC-ISO-001`（sub-agent context 隔離實測：對照組同時引用兩則 canary 先驗證判定法有效，兩個 sub-agent 雙向 canary 零交叉、皆答「看不到對方」，判定「隔離成立」；適用範圍聲明明文僅限本 protocol 所測之單次同輪平行 dispatch 場景，不得逕自援引至其他情境；status: draft，待使用者 PR 確認合併）
- 站 3 補票 T-21～T-26 定稿（`tickets-loop-draft.md`，已過使用者 quiz；T-23 依裁示併入 T-09，票號保留空號不重排後續票）
- 兩批站 4 出口驗收報告：`batch-verify-report.md`（六張票 T-02／T-03／T-04／T-06／T-07／T-11；T-02／T-03 因 DECISIONS.md 具名條目僅存 draft、未落檔 plugin repo 而判 **FAIL**，其餘四票 PASS）、`batch-verify-2.md`（三張票 T-05／T-08／T-22，皆判 **PASS**；點名 T-08 動態紅→綠證據「最弱」，因沙盒無 GitHub 連線僅能依文檔設計與離線測試做間接確認）
- 5 個 build 交付目錄：
  - `build/t07/`：label scheme 與 anchor／milestone 慣例（§3.3 全部 13 個 `sc:` label 定義、work ID／anchor body／milestone description 三種格式模板、`apply-labels.ps1`／`verify-labels.ps1`；實際套用須使用者本機執行）
  - `build/t08/`：進線 intake native ＋ gate 初始化路徑（設計為「佇列產生器」而非直接寫 GitHub 的端到端腳本，理由：手動階段本來就寫不進 GitHub、且重用 T-21 既有落地邏輯；涵蓋五條初始化判準，可重複執行、每次只推進尚未完成的階段）
  - `build/t10/`：gate 推進、寫後回驗與歸因復位（站序合法性判定——跨站請求一律拒絕並具名未滿足條件、單一次「設定完整 label 集合」推進、寫後回驗、復位模式；歸因合法性動態驗收與復位模式的真實 timeline 驗收 deferred-to-CI）
  - `build/t21/`：待寫佇列基礎設施（手動階段唯一寫入路徑——四欄佇列格式、產生權不變式、`apply-queue.ps1`／`reconcile-queue.ps1`；冪等靠套用前讀現況比對，不設動作指紋）
  - `build/t22/`：程式碼 patch 落地路徑（`git diff`／`git apply` 序列化格式、與 T-21 佇列共讀共存、CRLF 行尾實測結論、交付判定 `Test-PatchDelivered` 只認佇列現況與落地日誌、不信 executor 自陳）

### Changed
- `Spec_station-command_v1.6.md`：gate 執行身分改依 ADR-NP-009 分兩階段生效（① 手動階段——現行身分即使用者本人，不成立機器歸因，安裝與每次 gate 只具名回報當前身分、不作 fail 條件；② CI 階段——`github-actions[bot]`，§3.4 全套歸因生效），落地 `SC-DEC-BOT-001` 的實測結論；§3.4 機器歸因判準與復位模式標為「CI 階段生效、手動階段不生效」；驗收 #7／#17 改標 deferred-to-CI 並新增 #17a 手動階段替代測項（初始化報告須含固定字串「手動階段：無機器歸因，依 ADR-NP-009」）
- `Spec_station-command_v1.7.md`：新增 §4.6 待寫佇列首版規格（依 ADR-NP-009／010③，手動階段寫入動作累積成佇列＋本機套用腳本，loop 照跑不因寫入斷點歸零自主權）、§5.3 自主派工循環＋§7.5 排程喚醒規格（依 ADR-NP-010，兩層喚醒——session 內／跨 session 排程——共用同一套停止條件，狀態一律從 GitHub 現算不落狀態檔）、停止條件窮舉五條（不可逆動作前／gate 連續失敗 2 次仍 fail／站 1-3 人類 gate／scope 變更／frontier 空）、驗收 #23～25
- `Spec_station-command_v1.8.md`：§4.6 待寫佇列 rework（產生權不變式——佇列項的產生權＝該動作原本的唯一寫入者、四欄格式、每輪 loop 開頭對帳出列已落地項）；§3.5 票欄位七→八，新增第八欄「不可逆動作：有／無＋說明」（供停止條件①票級事前判定，八項任一缺漏即站 3 gate fail）；§5.3 拆分為 §5.3a session 內 loop（手動階段生效）與 §5.3b 跨 session 排程喚醒（依 ADR-NP-010⑤ 整節 deferred-to-CI——loop 賴以跨 session 運作的三個訊號〔assignee、`sc:gate-fail`、留言〕皆需寫 GitHub，手動階段開等於保證同票每小時重派且多 executor 併行互蓋）

### Fixed
- T-21 PowerShell 5.1 陣列解卷：0 或 1 筆的集合被 PowerShell 解卷成 `$null`／純量，導致 `.Count`／`foreach`／屬性存取在 `Set-StrictMode -Version Latest` 下拋錯（`The property 'Count' cannot be found on this object`，使用者本機實跑撞見）。修法＝`queue-common.ps1` 全面改用「函式內以逗號運算子 `,` 保住陣列型別 ＋ 呼叫端對已賦值變數額外包一層 `@()`」兩步模式（🚫 不可直接 `@(函式呼叫本身)`——已實測證實會把 0 筆結果誤包成「1 筆、內容是空陣列」）；新增 `t21-offline-test.ps1` 涵蓋 API 回傳 1 筆／0 筆／多筆／`issue.labels` 為 `$null` 四種形狀，15 項斷言全綠
- T-21 紅燈型態不合格重工：verifier 判定初版紅燈（「兩檔不存在」）為載入失敗型，不符 Spec §6「紅是斷言失敗的紅」；新增 `t21-dynamic-test.ps1` 補上斷言失敗型紅燈（`-SkipIdempotencyCheck` 連跑兩次同一則留言 ⇒ 斷言「留言數不得增加」真的失敗，實測變 2；正常模式重跑同一斷言通過，實測仍 1）

## [0.0.0] - 2026-08-05

### Added
- repo 建立（station-command plugin repo 起始化）
- 共識文件進駐：`ADR.md`（ADR-NP-001～008）、`GLOSSARY.md`
- `Spec_station-command_v1.5.md` 定稿進駐
- 站 3 票集進駐：21 張票（`tickets-draft.md`，T-01～T-20，含 T-15a／T-15b）
