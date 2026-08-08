# station-command CI 階段執行規格（T-26）

狀態：站 2 出口缺口審第三輪由獨立第三方（≠ executor）執行，結論 **FAIL**——前兩輪為自審，其 10 條 hard finding 經第三方複核確已結案，FAIL 原因是定稿後當日新增的兩條裁示（`SC-DEC-REACH-001`／`SC-DEC-ROUTE-001`）未收攏；本輪 rework 已依裁示收攏（見已裁示節與 DTC-030），待重審。待裁示項仍依本文件停手。

本文件只收攏既有 deferred-to-CI／CI 接線債，不新增產品規則。每個來源項目以固定 `DTC-NNN` 識別；下表同時是 `check_completeness.py` 的凍結 fixture。

機器可讀的獨立 fixture 位於 `deferred-sources.tsv`；本文件表格只是人讀投影。檢查器以獨立 fixture 為分母，逐筆回查來源檔案、行號與預期片段，再核對本表與對應章節；因此同時刪掉本表一列與章節不會假綠。24 個 build 目錄的 README 存在性與分類分母另凍結於 `readme-scan.tsv`。

## 來源對照表（凍結 fixture）

| ID | 既有要求 | 來源檔案與行號 | 差什麼才能驗完 | 對應執行包 |
|---|---|---|---|---|
| DTC-001 | 第一條完整生產線後升 CI；CI gate 身分固定為 `github-actions[bot]` | `Spec_station-command_v1.11.md:18,352,359`；`ADR.md:70-85` | 一條手動完整生產線的完成證據、Actions 身分可寫測試 repo | A |
| DTC-002 | §3.4 timeline 機器歸因、非法來源阻擋與復位全套在 CI 生效 | `Spec_station-command_v1.11.md:36,86-92` | bot／人手兩種真實 timeline 與 CI gate 接線 | A |
| DTC-003 | §4.6 待寫佇列升 CI 後廢止，GitHub 寫入改由 CI 身分直接執行 | `Spec_station-command_v1.11.md:146-156`；`ADR.md:112-116` | 可寫 GitHub 的 CI 身分與各唯一寫入者的直接寫入回驗 | B |
| DTC-004 | 防作弊主力由手動站 4 verifier 移回站 5 mutation manifest 重放 | `Spec_station-command_v1.11.md:195`；`GLOSSARY.md:14` | v0.28.0 mutation manifest 可在 CI 重放的真實證據 | D |
| DTC-005 | 跨 session 排程只在站 4／5依 GitHub 現況續派 | `Spec_station-command_v1.11.md:260-262`；`ADR.md:94-129` | assignee／`sc:gate-fail`／留言三訊號可由 CI 寫入與新 session 執行環境 | C |
| DTC-006 | 排程平日 09:00–22:00 Asia/Taipei 每小時；無活安靜；prompt 自足 | `Spec_station-command_v1.11.md:328-331`；`ADR.md:118-119` | scheduler、無記憶 session 與通知觀察面 | C |
| DTC-007 | 驗收 #7：人手竄改、board 紅燈、run 拒絕、復位兩分支 | `Spec_station-command_v1.11.md:381` | 真實 bot／human timeline 與可重建測試 fixture | A |
| DTC-008 | 驗收 #17：初始化及後續 label actor 為 `github-actions[bot]` | `Spec_station-command_v1.11.md:391` | Actions 身分真實初始化與 label timeline | A |
| DTC-009 | 驗收 #25：關閉舊 session 後只憑 GitHub 正確續派，清本機殘留不變 | `Spec_station-command_v1.11.md:403` | 兩次隔離 session、可清空 workspace 的排程測試 | C |
| DTC-010 | 風險 2 緩解由人工歸因轉為 bot 機器歸因，但規範層恆保留 | `Spec_station-command_v1.11.md:410` | #7、#17 綠燈及四份 SKILL 寫入權限複核 | A |
| DTC-011 | 風險 9 在 CI 以夜間不跑、無活安靜、批次摘要緩解 | `Spec_station-command_v1.11.md:418` | 排程時區／靜默／摘要動態證據 | C |
| DTC-012 | §9a 第二階段列 CI workflow、外廠接入與 `sc:dual-vendor` | `Spec_station-command_v1.11.md:27,84,352,413`；`ADR.md:50-59` | 外廠與 label 載體矛盾先裁示；CI 可達性與寫入者接線 | F |
| DTC-013 | T-10 歸因合法性判定待真實 CI bot 動態驗證 | `build/t10/README.md:43-48` | `-GateIdentityLogins github-actions[bot]` 對真實 timeline 執行 | A |
| DTC-014 | T-10 復位兩分支待真實 timeline 動態驗證 | `build/t10/README.md:43-50` | 最後合法事件與全無合法事件兩組真實 timeline | A |
| DTC-015 | T-12 run 的 actor 歸因在手動階段僅結構檢查，延至 CI | `build/t12/README.md:60-65` | run 選件前接入 T-10 完整歸因並以 bot／human fixture 驗證 | A |
| DTC-016 | T-14 `sc:red-proven` 最後 actor 為 bot 的動態驗證 | `build/t14/README.md:59-61,90-94` | 真實 CI 寫 label 後以 timeline 回驗 actor | A |
| DTC-017 | T-15a 站 5 關票 actor 為 bot 的動態驗證 | `build/t15a/README.md:64-73,135-140` | 真實 CI 關票事件與最後 `closed` actor 回驗 | A |
| DTC-018 | T-15b 完成態的真實 closed actor 歸因 | `build/t15b/README.md:137-143` | 獨立 gate bot、測試 repo、真實 close timeline | A |
| DTC-019 | T-15b 跨 2+ repo 關 milestone 的真實落地與逐 repo 回驗 | `build/t15b/README.md:137-143` | CI 對 2+ repo 的寫權與 GET→PATCH→GET 證據 | B |
| DTC-020 | T-19 DECISIONS 掃描尚未接入 T-10 每次 gate 的 blocking 項 | `build/t19/README.md:120-140` | gate 呼叫鏈接線及 404／403／過期／格式錯誤整合測試 | E |
| DTC-021 | T-19 CLI 真實 GitHub 端到端驗證 deferred | `build/t19/README.md:185-188` | 可讀多 repo Contents API 的 CI 測試身分與 fixture | E |
| DTC-022 | T-25 未做 §7.5 排程、頻率與無記憶 prompt | `build/t25/README.md:132-138` | T-26 規格、Actions bot 與排程執行環境 | C |
| DTC-023 | T-15a 空 gate 身分集合放行，T-15b 空集合 fail-closed；已裁示採 T-15b | `build/t15a/station5-check.ps1:453-464`；`build/t15b/work-complete.ps1:88,111-116`；本票使用者裁示 | T-15a CI 接線時改為空集合阻擋，並做空／bot／human 三態回歸 | A |
| DTC-024 | T-24 真實 dispatch／收件／判 gate provider 留給未來 CI 接入 | `build/t24/README.md:120-124` | CI 宿主提供真實 `GateResultProvider` 與多輪端到端執行 | C |
| DTC-025 | T-28 的 12 家動態可達性與真實外廠呼叫未實證 | `build/t28/README.md:5-11,65-75,128-132` | 可連外 CI 環境；不得在本票碰 key，真 key 語意驗證仍依既有後續票 | F |
| DTC-026 | T-16 聚合尚未接入 `/station-board` 呼叫鏈 | `build/t16/README.md:158-190` | 在既有 skill 呼叫鏈接入並跑跨 repo 動態聚合 | E |
| DTC-027 | T-17 對帳尚未接入 `/station-board` 完整模式 | `build/t17/README.md:263-301` | skill 接線、真實 plans 格式前提與完整模式動態驗證 | E |
| DTC-028 | T-17 `project-manager` 實際 dispatch 尚未接入 | `build/t17/README.md:290-301` | 完整模式能 dispatch 並消費既有對帳函式結果 | E |
| DTC-029 | T-13 CLI 整合層尚缺真實 PAT 的全過／未過票集動態驗證 | `build/t13/README.md:156-168` | CI 測試 repo 跑兩種票集並核對報告、override、queue/direct-write 結果 | E |
| DTC-030 | 站 4 實作 executor 依 `SC-DEC-ROUTE-001` 改由沙盒內 Codex CLI 承接；CI 宿主須解決 CLI 安裝、憑證供應與 T-29 記帳三項 runtime 前提 | `ADR.md:172-180`；`CHANGELOG.md:32` | CI 宿主的 CLI 自動化安裝、不與他處共用 refresh token 的憑證供應方案、T-29 ledger 接線 | C |

### v1.8 `deferred-to-CI` 字面位置 fixture

對工作區 v1.8 實檔逐字掃描得到下列 5 個字面命中；檢查器會雙向比對實檔與 `deferred-sources.tsv` 的 `v1.8-literal` 列，新增或消失一處都會失敗。**P-04 已裁示：票面「9 處」指 `tickets-loop-draft.md:63` 的 9 條語意枚舉，不是 `deferred-to-CI` 字面字串計數；因此本表仍如實凍結字面 5/5，而 9 條語意涵蓋另見已裁示節的 DTC 對應。**

| v1.8 行 | 映射章節 | 原文識別 |
|---:|---|---|
| 197 | DTC-005 | §5.3b 跨 session 排程喚醒 |
| 241 | DTC-006 | §7.5 排程喚醒規格 |
| 276 | DTC-007 | 驗收 #7 站別歸因與復位 |
| 286 | DTC-008 | 驗收 #17 執行身分驗證 |
| 295 | DTC-009 | 驗收 #25 排程接續不靠記憶 |

## build README 掃描證明

| 目錄 | README 狀態 | CI-deferred | pre-CI 接線債 | 判讀摘要 |
|---|---:|---:|---:|---|
| t05 | **README 不存在**；改讀 3 份 Markdown | 0 | 0 | 無 CI 延後標記；另有 1 支 shell、1 份文字證據與隱藏 fixture，因非 README／Markdown 規格來源而未冒充逐字閱讀對象 |
| t07 | 已逐行讀 | 0 | 0 | 僅本機套用說明 |
| t08 | 已逐行讀 | 0 | 0 | best-effort 全艦隊掃描 |
| t09 | 已逐行讀 | 0 | 0 | 範圍分工 |
| t10 | 已逐行讀 | 2 | 0 | 歸因、復位 |
| t11 | **`build/t11/` 不存在，無 README 可讀** | 0 | 0 | T-11 產物位於 `build/station-command/assets/` |
| t12 | 已逐行讀 | 1 | 0 | timeline actor 歸因 |
| t13 | 已逐行讀 | 0 | 1 | CLI 動態整合是現行接線債，不延至 CI |
| t14 | 已逐行讀 | 1 | 0 | `sc:red-proven` actor |
| t15a | 已逐行讀 | 1 | 0 | close actor；另收空集合分歧 |
| t15b | 已逐行讀 | 2 | 0 | close actor、跨 repo milestone 寫入 |
| t16 | 已逐行讀 | 0 | 1 | `/station-board` 接線是現行債；真 REST 細項是其驗收子項 |
| t17 | 已逐行讀 | 0 | 2 | board 接線、`project-manager` dispatch 是現行債 |
| t18 | 已逐行讀 | 0 | 0 | auditor／CLI 屬本機或 scope 誠實聲明 |
| t19 | 已逐行讀 | 0 | 2 | T-10 接線與真連網 CLI 均是現行 gate 債，不得延後 |
| t21 | 已逐行讀 | 0 | 0 | 使用者本機動態驗收；queue 退場另見 DTC-003 |
| t22 | 已逐行讀 | 0 | 0 | Windows git／面板限制 |
| t24 | 已逐行讀 | 1 | 0 | 真實 provider 明指未來 CI 自動化 |
| t25 | 已逐行讀 | 1 | 0 | §7.5 排程 |
| t27 | 已逐行讀 | 0 | 0 | 無 deferred／CI 誠實聲明 |
| t28 | 已逐行讀 | 1 | 0 | 外廠動態可達性承接 §9a；判準已依 `SC-DEC-REACH-001` 裁定二層政策（見已裁示節） |
| t29 | 已逐行讀 | 0 | 0 | 誠實聲明無新的 deferred-to-CI；未實證項（真實 provider 呼叫、GitHub 寫入等）錨定於未關票 T-31 與既有 DTC-024／003，零新增 |
| t30 | 已逐行讀 | 0 | 0 | 誠實聲明無新的 deferred-to-CI；錯誤體語意與 usage 記帳殘留具名交 T-31／T-29，零新增 |
| t31 | 已逐行讀 | 0 | 0 | 誠實聲明無新的 deferred-to-CI；端到端驗收未過屬未關票 T-31 本身的殘留，非新 CI 延後項 |
| **合計** | **22 份 README＋t05 的 3 份 Markdown；t11 缺目錄** | **10** | **6** | t29／t30／t31 為本輪擴充的分母（原凍結 21 目錄已過期），三者皆零新增；另有 DTC-023 跨票已裁示分歧，不重複計數 |

## CI 階段執行包

### 0. 啟用總閘與執行順序

這不是另一套狀態機。CI 階段沿用 v1.11 的 GitHub 真相源、五站 gate、六條 loop 停止條件與唯一寫入者；只把已明文延後的能力啟用。

啟用總閘只有既有 §9a 條件：**手動階段已走完第一條完整生產線**。執行者須先保存該 work 從站 1 到 `sc:station-done` 的可稽核證據，再建立 Actions 測試環境；若沒有此證據，不得宣稱已到 CI 第二階段。**E 是現行正典已要求、但 build 尚未接好的 pre-CI blocking backlog，不受 §9a 延後；須先結清。** 其後 CI 能力依序執行：A 身分與歸因 → B 直接寫入 → C 排程 → D manifest 重放 → F 外廠項。B 的 queue 退場又與 §9a 分離：只要原寫入者已能直接寫 GitHub，metadata queue 就應依 §4.6 廢止；若恰在 CI 環境，才再疊加 bot actor 要求。F 有具名矛盾，未裁示前不得自行啟用新 label 或改逃生口載體。

### A. `github-actions[bot]`、timeline 歸因與復位

#### DTC-001 第一條完整生產線與 CI 身分

- **CI 階段要做**：保存第一條完整手動生產線的完成證據；後續 gate 寫入一律由 GitHub Actions 原生身分執行，gate 執行身分宣告具名為 `github-actions[bot]`。
- **啟用條件**：該完成證據存在，且測試 workflow 對隔離測試 repo 具備既有規格所需寫權。
- **啟用後驗收**：Actions 內跑一次初始化與一次 gate 寫入；初始化成功，兩次報告皆具名身分，timeline 實得 actor 為 `github-actions[bot]`。
- **與手動階段差異**：手動階段 actor 是使用者本人、只回報不阻擋；CI 階段 actor 是原生 bot，歸因成為 blocking gate。
- **差什麼才能驗完**：完整手動 work 證據、隔離測試 repo 與 Actions 原生權限；不得以 PAT／第二帳號替代 bot 身分。

#### DTC-002 §3.4 全套機器歸因

- **CI 階段要做**：啟用所有狀態 label 最後一次 `labeled`／`unlabeled` 事件的 actor／時間判定。矩陣須涵蓋：anchor 的 `sc:station-1..5`／`sc:station-done`／`sc:legacy`，票的 `sc:red-proven`，以及 anchor 或票的 `sc:blocked`／`sc:gate-fail`／`sc:awaiting-user`；`sc:work`／`sc:ticket` 是類型 label，不混入狀態矩陣。**只有 station label** 已由 §3.4 定義非法時 board 紅燈、run 拒絕與 timeline 復位；其他狀態 label 目前只判 SC#7 驗收 FAIL，其 runtime 處置待 P-08，不能類推。站別變更仍是單次完整 label 集合寫入，留言仍不參與判定。
- **啟用條件**：DTC-001 綠燈，且非空 gate 身分集合已傳入 board／run／gate 的共同判定路徑。
- **啟用後驗收**：上述每一種合法載體／狀態 label 都各有 `labeled` 與 `unlabeled` 事件；bot 事件 PASS、human 事件使 SC#7 驗收 FAIL。station 類再核對 board 紅燈、run 拒絕、gate 復位；非 station 類在 P-08 前只保存 actor 違規證據，不主張已有 runtime 阻擋／修復輸出。API 觀察仍只有一次完整 label 集合設定。不得拿驗收 #7 的 station-only 案例冒充全矩陣。
- **與手動階段差異**：手動階段只有 SKILL 規範層與人工複查；CI 新增可機械阻擋的 actor 層，但規範層不得刪除。
- **差什麼才能驗完**：共用身分參數的 CI 接線、全狀態 label × 合法載體 × `labeled`/`unlabeled` × bot/human 的真實 timeline fixture、board／run／gate 三入口整合證據。

#### DTC-007 驗收 #7：竄改與復位

- **CI 階段要做**：執行 v1.11 驗收 #7 的三段鏈：人手改站別 → board／run 阻擋 → gate 復位。
- **啟用條件**：DTC-002 已在隔離測試 repo 生效。
- **啟用後驗收**：案例一先由 bot 留合法站別，再由人手改標，復位須退回最後合法事件並報事件時間；案例二使用一張從未有 bot 合法站別事件的新 fixture，須落 `sc:awaiting-user` 並停手。不得嘗試刪除 GitHub 不可刪的既有 timeline 事件來造案例。
- **與手動階段差異**：手動階段不跑 #7，改跑 #17a；CI 階段 #7 是 blocking acceptance。
- **差什麼才能驗完**：兩張可安全污染的 fixture anchor 與 board／run／gate 實際呼叫鏈。

#### DTC-008 驗收 #17：執行身分

- **CI 階段要做**：把初始化身分檢查從「回報、不 fail」切到 bot 身分前提下的機器歸因入口。
- **啟用條件**：Actions 原生身分可建／改測試 issue，且沒有以使用者 token 覆蓋 actor。
- **啟用後驗收**：CI 初始化通過；緊接的一次 station label 寫入，其最後 `labeled` actor 精確為 `github-actions[bot]`。
- **與手動階段差異**：不再以固定字串「手動階段：無機器歸因，依 ADR-NP-009」作替代驗收。
- **差什麼才能驗完**：真實 Actions run URL 或等價稽核指標與對應 timeline 證據。

#### DTC-010 風險 2 的緩解轉換

- **CI 階段要做**：以 DTC-002 全矩陣加上 #7／#17 的機器層取代「只能人工歸因」的暫時降級；同時保留只有 gate SKILL 可指示狀態 label 寫入的規範層。
- **啟用條件**：DTC-007、DTC-008 綠燈。
- **啟用後驗收**：四份 SKILL.md 人工複核仍只有 gate 含狀態 label 寫入指示；DTC-002 的任一非 bot 狀態事件皆使 SC#7 驗收 FAIL。#7 只證 station 竄改／復位，不再過度宣稱涵蓋所有狀態 label，也不替 P-08 尚未裁示的非 station runtime 處置選邊。
- **與手動階段差異**：人工複查從唯一歸因防線變為機器層之外仍保留的第二層。
- **差什麼才能驗完**：四份實際出貨 SKILL.md 與一次非 bot 反例。

#### DTC-013 T-10 歸因動態驗證

- **CI 階段要做**：以 `-GateIdentityLogins 'github-actions[bot]'` 跑 T-10 已有歸因程式路徑，不再只靠 mock。
- **啟用條件**：DTC-001 綠燈，且 T-10 呼叫入口可讀真實 issue timeline。
- **啟用後驗收**：`all.attribution`／`all.identity` 對 bot 為 blocking PASS，對人手 actor 為 blocking FAIL；空集合依 DTC-023 FAIL。
- **與手動階段差異**：手動階段身分項不算入 AND；CI 階段必算入 AND。
- **差什麼才能驗完**：三態 fixture（bot／human／empty identity）與 T-10 動態報告。

#### DTC-014 T-10 復位兩分支動態驗證

- **CI 階段要做**：對真實 timeline 跑 `Find-LastLegalStationEvent`／`Invoke-GateReset` 既有兩分支。
- **啟用條件**：DTC-013 已證明 actor 判定有效。
- **啟用後驗收**：混合事件依時間順序回退最後合法站；無合法事件 fixture 落 `sc:awaiting-user`，且兩案回驗完整 label 集合。
- **與手動階段差異**：手動階段拒絕執行復位；CI 階段復位成為正式修復路徑。
- **差什麼才能驗完**：可重建的混合 timeline 與無合法事件 anchor。

#### DTC-015 T-12 run 選件前歸因

- **CI 階段要做**：run 在套用 frontier 三判準之前先消費 T-10 的完整 timeline 歸因結果；非法來源不得進選件。
- **啟用條件**：DTC-013 已接入共用呼叫鏈。
- **啟用後驗收**：同一張其他條件皆合格的票，合法 bot 站別可入 frontier；改成人手最後事件後不得入 frontier，理由具名為站別來源不明而非 blocker／depends_on。
- **與手動階段差異**：手動階段只查「恰一個 station label」結構；CI 加 actor blocking 判定。
- **差什麼才能驗完**：T-12 真實 CLI／宿主入口與同票單變因 fixture。

#### DTC-016 T-14 `sc:red-proven` actor

- **CI 階段要做**：站 4 通過後直接寫 `sc:red-proven`，再執行既有 `-VerifyRedProven` actor 檢查。
- **啟用條件**：DTC-003 的 gate 直接寫入可用，且 gate 身分集合非空。
- **啟用後驗收**：最後 `sc:red-proven` `labeled` actor 是 bot則 PASS；由人手補標的單變因反例 FAIL 且不得推進站 5。
- **與手動階段差異**：手動階段 actor 只具名回報、不 blocking；CI 階段 blocking。
- **差什麼才能驗完**：bot／human 各一張站 4 票與真實 timeline。

#### DTC-017 T-15a 關票 actor

- **CI 階段要做**：站 5 gate 通過後直接關票，並以既有 `Find-LastCloseEvent`／`Test-CloseActorLegit` 回驗最後關票 actor。
- **啟用條件**：DTC-003 的 gate 直接關票可用，且 DTC-023 空集合守門已對齊。
- **啟用後驗收**：bot 關票為 blocking PASS；人手關票為 blocking FAIL；空集合在讀 actor 前即 fail-closed。
- **與手動階段差異**：手動階段空集合會降級為非 blocking；CI 禁止此放行。
- **差什麼才能驗完**：T-15a 三態回歸與真實 closed timeline。

#### DTC-018 T-15b 完成態關票歸因

- **CI 階段要做**：完成態逐票確認最後 closed actor 皆屬非空 gate 身分集合，任一未證即走既有 `awaiting-user` 路徑。
- **啟用條件**：DTC-017 已證明票級關閉由 bot 落地。
- **啟用後驗收**：全票 bot 關閉才可 `complete`；混入一張人手關閉或空集合皆不得完成，且不得關 anchor／milestone。
- **與手動階段差異**：CI 有可區分 actor 的身分，不再因使用者與 gate 同 actor 而只能人工判讀。
- **差什麼才能驗完**：一個全 bot work 與一個混合 actor work。

#### DTC-023 gate 身分集合為空一律 fail-closed（已裁示）

- **CI 階段要做**：T-15a CI 接線須對齊 T-15b：gate 身分集合為空代表歸因未證，必須 blocking FAIL；不得沿用 T-15a 現行 `Blocking=false, Satisfied=null` 放行。
- **啟用條件**：此為本票使用者已裁示方向，無待裁示；在任何 actor-dependent CI gate 啟用前先完成對齊。
- **啟用後驗收**：空集合／bot／human 三態分別為 FAIL／PASS／FAIL；空集合情境不得產生 label、關票、關 milestone 或成功報告。
- **與手動階段差異**：手動階段依 ADR-NP-009 可降級回報；CI 階段聲稱有 bot 歸因卻未提供身分集合時不得降級。
- **差什麼才能驗完**：T-15a 與 T-15b 共用或等價的三態回歸證據；接線實作不在本票。

### B. 待寫佇列退場與直接寫入

#### DTC-003 §4.6 廢止

- **CI 階段要做**：停用 metadata 待寫佇列的產生、讀取、套用、對帳出列與面板揭露；intake／gate／run 仍依既有唯一產生權，改在各自權責內直接呼叫 GitHub。寫前讀現況、寫後直讀回驗、失敗具名的既有語意不得因去佇列而消失。若執行環境已是 CI，直接寫入 actor 再依 A 包要求為 bot。
- **啟用條件**：**唯一條件是各原寫入者已具直接寫入與回驗能力**；不綁第一條完整生產線，也不綁 actor 可區分。若寫入先恢復但尚未升 CI，metadata queue 仍應退場，§3.4 則繼續手動降級。
- **啟用後驗收**：分兩層。①直接寫入一恢復：native intake、station label、assignee／body／留言、票關閉各跑一例；GitHub 現況正確、actor 具名，workspace 不產生／消費 queue，面板不顯示 queue 警語；同動作重跑不重複，寫後不符不得宣稱成功。②進 CI 後：對同一矩陣再疊加 actor=`github-actions[bot]` 的 A 包驗收。
- **與手動階段差異**：三態而非二態。寫入不可用的手動階段走 queue；寫入已恢復但尚未升 CI 的手動階段直接寫、actor 仍按 ADR-NP-009 降級；CI 階段直接寫且 actor 機器歸因生效。
- **差什麼才能驗完**：metadata 直接寫入接線；CI 場景另需 DTC-001／008 actor 證據。§4.6 的 code patch 替代路徑未定，見待裁示 P-02。

#### DTC-019 T-15b 跨 repo milestone 直接落地

- **CI 階段要做**：以 bot 對 2 個以上參與 repo 執行既有 close-milestone GET→PATCH→GET 流程，不經 queue。
- **啟用條件**：DTC-003 metadata 直接寫入可用；跨 repo workflow／權限／actor 拓撲須先依 P-07 裁示並實證，不能只寫「有權限」。
- **啟用後驗收**：最後一票經 gate 關閉後，anchor 為 `sc:station-done` 且關閉；所有參與 repo milestone 逐一為 closed。任一 repo 回驗不符時整體不得宣稱收尾成功，失敗 repo 具名。
- **與手動階段差異**：寫入不可用時生成 `close-milestone` queue；若手動寫入先恢復則已可直接寫但 actor 仍降級；CI 直接寫入、逐 repo 回驗並另受 bot actor／P-07 約束。
- **差什麼才能驗完**：2+ repo 隔離 fixture、跨 repo Actions 權限與清理／重開方案。

### C. 跨 session 排程喚醒

#### DTC-005 只在站 4／5續派

- **CI 階段要做**：排程每次開全新 session，只讀 GitHub 現況建 frontier；站 4／5可進既有 loop，站 1／2／3須停在人類 gate。選件與六停止條件完全共用 §5.3a，不建立狀態檔。
- **啟用條件**：DTC-003 已讓 assignee、`sc:gate-fail`、留言三訊號可由 CI 當輪寫入並回驗；DTC-024 真實 provider 已接上；站 4 續派的 dispatch 對象依 `SC-DEC-ROUTE-001` 為沙盒內 Codex CLI executor，其 runtime 前提（安裝、憑證、記帳）依 DTC-030 先結清；P-05 的 assignee 生命週期與 rework 次數真相源已裁示。未裁示前不得宣稱跨 session 可端到端啟用。
- **啟用後驗收**：連續兩個隔離 session 對同一 work 執行；第二個 session只依 GitHub 看見第一個已落地訊號，不重派同票。另須涵蓋站 4 成功收件→站 5 handoff、成功收件後下一輪可重新入選、以及兩個 session 累積到第二次 fail 時觸發停因②；把 work 設於站 3 時不得代行人類 gate。
- **與手動階段差異**：手動階段只靠 Commander session 內記憶續跑；CI 可跨 session 重建。
- **差什麼才能驗完**：可啟動無記憶 session 的宿主、真實 dispatch callback、跨 session 測試 fixture。

#### DTC-006 頻率、安靜退出與 prompt 自足

- **CI 階段要做**：排程依既有 §7.5 在平日 09:00–22:00（Asia/Taipei）每小時觸發，夜間不跑；無活安靜退出。排程 prompt 必自帶 repo 清單、三選件條件、六停止條件與痕跡規則。
- **啟用條件**：DTC-005 loop 端到端綠燈，scheduler 能明確設定 Asia/Taipei 語意。
- **啟用後驗收**：以排程執行紀錄證明時窗內每小時、夜間零次；空 frontier 零推播；prompt 在清除前次 session 上下文後仍能選出相同下一項。停因②③④⑥仍各推播，①⑤安靜。
- **與手動階段差異**：手動由使用者叫起且可帶對話記憶；CI 定時開無記憶 session。
- **差什麼才能驗完**：實際 scheduler、執行紀錄、宿主推播 sink。

#### DTC-009 驗收 #25：不靠本機殘留

- **CI 階段要做**：在第一個 session 結束後清空第二個 session 的 workspace／本機殘留，再由排程續派。
- **啟用條件**：DTC-005、DTC-006 已接線。
- **啟用後驗收**：清空前後選出的下一個可動作項相同，且只在站 4／5；結果的所有判定輸入可追溯到 GitHub。另由第二個 session 讀出既有 rework 次數，在第二次 fail 時停手。CI 階段 queue 已依 DTC-003 消失，不把 queue 當例外殘留。
- **與手動階段差異**：手動階段 #25 不測；CI 必須跨隔離 session 實證。
- **差什麼才能驗完**：兩個互不共享 workspace 的 job/session 與同一 GitHub fixture。

#### DTC-011 風險 9 的緩解轉換

- **CI 階段要做**：把無活安靜、夜間不跑、停止後恰一則批次摘要套到排程 loop；不新增第七種停因。
- **啟用條件**：DTC-006 排程與 T-25 收尾入口都可由 CI 宿主呼叫。
- **啟用後驗收**：空 frontier 為零通知／零逐輪留言；有三輪工作的 run 只留一則摘要；夜間沒有 run。摘要須列本輪票與 gate 結果、具名六停因之一。
- **與手動階段差異**：規則內容不變，差別是 CI 排程擴大了空轉暴露面，故必須以實際排程紀錄驗證既有緩解。
- **差什麼才能驗完**：排程 log、comment timeline 與通知 sink 計數。

#### DTC-022 T-25 與 §7.5 接線

- **CI 階段要做**：scheduler 以 T-25 `Invoke-StationRunLoopWithFinalization` 等價入口收尾，沿用單一 `station-user-push` 管道與一則摘要語意。
- **啟用條件**：DTC-024 真實 provider 可回傳 loop 結果，且 CI 可直接寫 comment。
- **啟用後驗收**：排程跑三輪後 GitHub 只有一則摘要留言；停因②③④⑥各恰一則推播，①⑤零則；無記憶 prompt 不含上次對話內容。
- **與手動階段差異**：T-25 離線 callback／queue mock 改成真實宿主 callback 與 bot 直接留言。
- **差什麼才能驗完**：scheduler、真實 GitHub comment、宿主 UI 推播三個觀察面。

#### DTC-024 T-24 真實 provider

- **CI 階段要做**：由 CI 宿主提供 T-24 既有 `GateResultProvider` seam 的真實等價實作，串起 dispatch → 收件 → 判 gate → 續派；不得把離線 mock 當端到端完成。dispatch 對象依 `SC-DEC-ROUTE-001`：站 4 實作 executor 為沙盒內 Codex CLI（runtime 前提見 DTC-030），Plan 與 Review 維持 Claude（fable）。
- **啟用條件**：宿主具備既有路由表所需 dispatch 能力（站 4 實作路由含 DTC-030 的 CLI executor），且各輪 metadata 能依 DTC-003 直接寫入。
- **啟用後驗收**：真實多輪 work 至少完成一次 PASS 續派與一次 rework；輸出不含站 4／5 確認提問，六停因之外的值仍拒絕。
- **與手動階段差異**：手動階段站 4 實作本體已依 `SC-DEC-ROUTE-001` 由沙盒內 Codex CLI 承接，但 provider seam 的收件／判 gate 仍由 Commander 在對話層逐輪人工轉送；CI 由無記憶宿主 callback 承接，不再有人在中間傳遞。
- **差什麼才能驗完**：真實 executor dispatch／回件接口（站 4 為沙盒 CLI，前提見 DTC-030）；本 spec 不定義新接口 schema。

#### DTC-030 沙盒 CLI executor 的 CI runtime 前提（依 `SC-DEC-ROUTE-001`）

- **CI 階段要做**：讓 CI 宿主能在沙盒內起 OpenAI Codex CLI（gpt-5.6-sol）作站 4 實作 executor；Plan 與 Review 維持 Claude（fable）。此為已裁示的 CI 階段實作債，不是待裁示項。須結清三項 runtime 前提：① **CLI 安裝**——手動階段已實測 `npm install -g @openai/codex`（0.147.0）於沙盒內可行，CI 宿主須重現等價安裝並具名版本；② **憑證供應**——§5.4「連接資料夾讀 key」規則是寫給 API adapter 的，未涵蓋 CLI executor；手動階段實錄：以 ChatGPT 登入憑證（`auth.json` 快照）供應會發生 refresh token 輪替衝突，同一把 refresh token 在兩處使用會互相踢掉，實際遇 `refresh_token_invalidated` 導致 CLI 中途失效——CI 必須採不與他處共用同一把 refresh token 的憑證供應方式，並沿用 key 不進對話／repo／log／queue 的既有邊界；具體方案（API key 或獨立憑證）由既有 key 管理權責決定，本 spec 不發明新機制；③ **成本記帳**——該 executor 的 token 成本（手動階段實測每張票約 180k tokens，計於 OpenAI 帳）須併入 T-29 的 ledger 記帳與既有邊界告警。
- **啟用條件**：DTC-024 的真實 dispatch 接口能把站 4 實作票路由到 CLI executor；憑證供應方案已解決輪替衝突並經實測；T-29 ledger 可登錄該 executor 用量。
- **啟用後驗收**：CI job 內完成至少一張真實站 4 實作票：CLI 安裝成功並具名版本；全程無 `refresh_token_invalidated` 等憑證失效中斷；憑證不落 repo／log／對話／queue；該票 token 用量寫入 T-29 ledger 並可觸發既有 50%／80%／100% 邊界；verifier 仍為 Claude，verifier ≠ executor 的異廠交叉檢視成立。
- **與手動階段差異**：手動階段由使用者手動在沙盒安裝 CLI、以登入憑證代供並人工承受輪替衝突；CI 須由宿主自動化安裝與憑證供應，且不得與使用者本機共用同一把 refresh token。
- **差什麼才能驗完**：CI 宿主的沙盒與 CLI 安裝能力、不衝突的憑證供應方案、T-29 ledger 接線與一張真實站 4 票的端到端證據。

### D. 站 5 mutation manifest 重放

#### DTC-004 紅燈重放移回站 5

- **CI 階段要做**：保留站 4 red→green 與 verifier≠executor；另把 v0.28.0 既有 mutation manifest 的重放放回站 5 CI，作為防作弊主力。不得把「移回站 5」解讀成刪除站 4 既有出口條件。
- **啟用條件**：能取得既有 v0.28.0 manifest 正典、runner 與預期結果；來源未定前不得自創 schema。
- **啟用後驗收**：對一個已通過站 4 的 fixture 在站 5 重放 manifest；原始正常版全綠，至少一個既有 mutation 造成對應斷言失敗；兩段皆由 CI 留存，站 5 gate 可查。manifest 未跑／結果缺失時不得結案。
- **與手動階段差異**：手動防作弊主力在站 4 verifier；CI 主力移回站 5 manifest 重放，但站 4 red→green 證據仍在。
- **差什麼才能驗完**：repo 內目前只找到對 v0.28.0 manifest 的文字指向，未找到其位置／schema／runner，見待裁示 P-03。

### E. pre-CI blocking backlog：既有模組接線與真實動態驗證

本包五項**不是 deferred-to-CI**。它們是 README 誠實聲明揭露、但 v1.11 現行入口已要求的接線／動態驗證債；必須在 §9a CI 總閘之前結清，不能因收進 T-26 就取得延後授權。

#### DTC-020 T-19 接入每次 gate

- **CI 階段要做**：**無新增 CI 行為；這是 pre-CI 必修。** 把 T-10 的 `all.decisions-exemption` 從非 blocking N/A 改為消費 T-19 既有掃描結果的 blocking 項；每次 gate 掃 anchor 宣告的所有參與 repo。
- **啟用條件**：立即依現行 Spec §6 接線；讀取端可存取所有參與 repo。不等 DTC-001 或 §9a。
- **啟用後驗收**：在手動／pre-CI 階段先證 404＝pass-no-file；403／500、解析失敗、格式不合、過期＝fail；缺掃一 repo＝fail；過期時依當前寫入能力直接寫或產既有 queue 項落 `sc:gate-fail` 並回驗。CI 只重跑回歸。
- **與手動階段差異**：沒有規則差異；手動階段現在就必須是 gate AND 的 blocking 項。CI 只把寫入載體與 actor 換成 B/A 包。
- **差什麼才能驗完**：T-10/T-19 接線與多 repo Contents API fixture。

#### DTC-021 T-19 真 GitHub CLI

- **CI 階段要做**：**無新增 CI 規則；這是 pre-CI 動態驗證。** 在隔離測試 repo 對 T-19 CLI／等價生產入口跑真實 Contents API，補完離線 mock 沒覆蓋的端到端層。
- **啟用條件**：DTC-020 接線完成，測試 repo 可安全配置四種 DECISIONS 狀態；不等 §9a。
- **啟用後驗收**：動態結果與 DTC-020 的五種預期完全一致，報告具名每個 repo；不得把網路錯誤顯示為 404。
- **與手動階段差異**：手動／pre-CI 即須完成真實讀取驗證；CI 只以 bot 身分重跑相同回歸。
- **差什麼才能驗完**：測試 fixture repo 與只讀 Contents 權限。

#### DTC-026 T-16 接入 board

- **CI 階段要做**：**無新增 CI 規則；這是 pre-CI 必修。** 讓 `/station-board` 的實際呼叫鏈消費 T-16 已有跨 repo 聚合／分組／消失偵測，而非停在單 work T-09 路徑；不新增字卡欄位。
- **啟用條件**：立即接線；至少兩個測試 repo 與可讀 GitHub search/milestone API，不等 §9a。
- **啟用後驗收**：同 work ID 跨 repo 合一張卡、同名不同 work ID 不合併、anchor 消失告警與無基線告警皆從實際 skill 入口可見；同時補跑 T-16 誠實聲明中的 search 語法、milestone 回應形狀、分頁／HitPageCap 子項。
- **與手動階段差異**：手動現行入口就應完成接線；CI 只重跑真實入口回歸。
- **差什麼才能驗完**：skill 接線、真實 PAT 等價的 Actions 讀權與跨 repo fixture。

#### DTC-027 T-17 接入 board 完整模式

- **CI 階段要做**：**無新增 CI 規則；這是 pre-CI 必修。** `/station-board` 完整模式在 T-16 聚合後消費 T-17 對帳三態；run／gate 無對帳模式仍沿用「本次未對帳」語意。
- **啟用條件**：DTC-026 綠燈，且已取得 `ak-project-management plans/` 的真實格式事實；立即處理，不等 §9a。若與現有假設不符，先停下，不得在本 spec 發明格式。
- **啟用後驗收**：從實際 skill 入口觀察「對帳範圍外／漂移／對帳未執行／本次未對帳」互不塌縮；對帳前後 GitHub snapshot 與 plans 內容守恆。
- **與手動階段差異**：沒有行為規則差異；手動現行入口先完成，CI 僅重現真實資料形狀回歸。
- **差什麼才能驗完**：真實 plans 樣本／格式文件、skill 接線與多 repo fixture。

#### DTC-028 T-17 `project-manager` dispatch

- **CI 階段要做**：**無新增 CI 規則；這是 pre-CI 必修。** 完整模式依既有白名單實際 dispatch `project-manager`，把其結果送入既有對帳函式；不得由 Commander 親手產生對帳分析結論。
- **啟用條件**：DTC-027 的 plans 格式前提已收斂，手動宿主可 dispatch 路由表 executor；不等 CI。
- **啟用後驗收**：prompt／dispatch 紀錄可證 executor 是 `project-manager`；結果被完整模式消費，無對帳模式沒有 dispatch；兩模式都不寫 plans 或 GitHub 狀態。
- **與手動階段差異**：手動階段先補實際編排接線；CI 只接到無記憶宿主並做回歸。
- **差什麼才能驗完**：宿主 dispatch 能力與真實 plans fixture。

#### DTC-029 T-13 CLI 動態整合

- **CI 階段要做**：**無新增 CI 規則；動態整合在 pre-CI 先完成，CI 再重跑。** 對真實測試 repo 分別跑一組全過票集與一組未過票集，驗證 T-13 CLI 報告與 T-10 gate 串接。
- **啟用條件**：DTC-020 gate 全站項已可用；pre-CI 依當時寫入能力核對 queue 或直接寫入，不等 DTC-003／§9a。
- **啟用後驗收**：全過票集產生正確 report／override 並可推站；未過票集具名缺項，依當時 §4.6 狀態產生正確 `sc:gate-fail` queue 項或直接落 GitHub，兩者皆不得推站。CI 回歸則必核對 bot 直接寫入。報告、override 與對應 queue／GitHub 現況相符。
- **與手動階段差異**：手動／pre-CI 依當時 §4.6 狀態核對 queue 或直接寫入；CI 核對 bot 直接寫入。八欄/seam 規則不變。
- **差什麼才能驗完**：真實 CLI／宿主入口、兩組票集與直接寫入接線。

### F. 外廠第二階段項

#### DTC-012 外廠接入與 `sc:dual-vendor`

- **CI 階段要做**：在裁示前只盤點並驗證既有 T-27/T-28 adapter；不得自行決定是否新增 `sc:dual-vendor`、不得把 DECISIONS.md 逃生口換回 label、不得宣稱外廠接入仍不存在或已常設化。
- **啟用條件**：待裁示 P-01 解決「§1/§3.3/風險5 延後」與「§5.1/§5.4/ADR-NP-011 已有 API 實體」矛盾，並決定 `sc:dual-vendor` 載體去留。
- **啟用後驗收**：依裁示選定的既有路徑執行；共同不變的驗收只有：外廠不可用時具名降級、不阻塞、finding 不合併不投票、key 不進對話/repo/log/queue。任何 label 驗收須等 P-01 明確採 label 才存在。
- **與手動階段差異**：手動現況以 DECISIONS.md 單票裁示與既有 adapter 為載體；CI 是否改載體尚未定。另依 `SC-DEC-CLI-001`（ADR-NP-011①-修正），外廠接入的技術載體候選除 API adapter 外新增「沙盒內 CLI」（否決範圍已縮限為使用者本機的 CLI）；採何載體仍屬 P-01 待裁示，本項不選邊。
- **差什麼才能驗完**：P-01 裁示、外廠可達環境與既有後續票所要求的語意驗證；本票不碰 key。

#### DTC-025 T-28 動態可達性（判準已依 `SC-DEC-REACH-001` 裁定）

- **CI 階段要做**：在允許連外、但不帶 key 的 CI job 跑既有 12 家最小可達性檢查，依已裁示的 `SC-DEC-REACH-001` 二層判準執行：第一層 `Reachability`＝有無收到 provider 的任何 HTTP 回應（只有網路層失敗與 421 proxy 攔截判不可達 FAIL）；第二層 `ProbeQuality`＝狀態碼落 200／401／403／429 為 PASS，落區間外判 **WARN 而非 FAIL**。只驗網路可達，不冒充模型語意或真 key 驗證。
- **啟用條件**：P-01 至少裁示外廠 adapter 繼續作為 CI 階段候選路徑，且執行環境允許外網。可達性政策不再是啟用前提（原 P-06 已裁示結案，見已裁示節）。
- **啟用後驗收**：固定逐家一次，共 12 次，結果與 T-27 registry 逐列配對；報告必分 `Reachability` 與 `ProbeQuality` 兩層。比對基線＝手動階段實測 REACHABILITY 12/12、PROBE 11/12：Perplexity `GET /models` 回 404 判 WARN，該家無此端點，屬具名預期而非缺陷、亦非迴歸。任一家 `Reachability` FAIL 才使本項 FAIL；`ProbeQuality` 落區間外只 WARN 並具名，不得改判 FAIL。另具名落差：**Spec v1.11:400 的驗收 #26 字面仍是舊的單層四碼判準（200／401／403／429＝連得到），與 `SC-DEC-REACH-001` 不一致；Spec 已定稿、不在 T-26 修改權內，該條文的重新安置歸屬未定**——CI 報告依本裁示執行，不得引用舊判準改判，也不得宣稱 Spec #26 已同步。
- **與手動階段差異**：本票環境禁網，只完成 fixture／offline；CI 補動態網路觀察，不讀任何 key。
- **差什麼才能驗完**：可連外 CI runner；真 key 呼叫與業務語意仍屬既有 T-31 等後續範圍，不能在此偷加。

## 待裁示

### P-01 外廠接入與 `sc:dual-vendor` 的正典互撞

- `Spec_station-command_v1.11.md:27,84,413` 說外廠接入路徑不存在／延至 CI，`sc:dual-vendor` 也延至 CI。
- 同檔 `:197-218,240,264-276` 與 `ADR.md:131-181` 已登錄 12 家、定義四家族 API、key 路徑、降級與分歧規則，並明說 DECISIONS.md 逃生口「自 ADR-NP-011 起有實體」。T-27/T-28 又已有 asset 與 adapter。
- `ADR.md:50-59` 只說升 CI 後再議「常設化」，不等於已裁定要恢復 `sc:dual-vendor` label。
- `SC-DEC-CLI-001`（`ADR.md:149-155`，ADR-NP-011①-修正）已把「否決本機 CLI 路線」的範圍縮限為**使用者本機的 CLI**，沙盒內 CLI 解禁；因此本項的外廠路徑方案空間除既有 API adapter 外，另有「沙盒內 CLI 載體」候選。此裁示只擴充候選集，不決定 P-01 的選邊。

**需裁示**：CI 階段究竟是（a）保留 DECISIONS.md 單票載體，只把既有 adapter 接入 CI；（b）新增 `sc:dual-vendor` 並定義合法載體／唯一寫入者／生命週期；或（c）其他已具名方案（含 `SC-DEC-CLI-001` 解禁後的沙盒內 CLI 載體）。在裁示前，本 spec 不選邊，DTC-012 只允許離線與無 key 可達性驗證。

### P-02 §4.6 整節廢止後，站 4 code patch 的 CI 留存路徑未定

- `Spec_station-command_v1.11.md:146` 明說升 CI 後 §4.6 整節廢止；`:155` 的 code patch 佇列因此也在被廢止範圍。
- 既有來源只明確說 GitHub metadata 由 CI 身分直接寫，沒有定義站 4 程式碼產出在 CI workspace 如何持久化、提交或交給後續站。

**需裁示**：code patch 在 CI 的既有替代落地路徑。未裁示前，DTC-003 可完成 metadata queue 退場，但不得宣稱 §4.6 全部已驗完，也不得自行發明 commit／artifact／branch 新規則。

### P-03 v0.28.0 mutation manifest 的位置／schema／runner 在本 repo 未具名

`Spec_station-command_v1.11.md:195` 與 `GLOSSARY.md:14` 只規定階段位置；本次以 `rg` 掃描現有 workspace，只找到文字指向，未找到可直接執行的 mutation manifest 正典或 runner。這不是條文方向矛盾，但會阻塞 DTC-004 的可執行落地。

**需提供／裁示**：既有 manifest 正典位置與重放入口。下一位不得為了讓 CI 有東西可跑而自創格式。

### P-05 跨 session 的 assignee 生命週期與 rework 次數真相源未定

- §5.3a 以 assignee 判定「尚無在跑 executor」，但既有來源只定義 dispatch 前設置與 dispatch 失敗移除；沒有定義成功收件、站 4→5 handoff、rework 或站 5 結束時何時清除／改派。
- `sc:gate-fail` 只表示最近一次 gate fail，單一 label 無法自行表示「同票 rework 2 次仍 fail」的次數；跨 session 又不得靠 Commander 記憶或新狀態檔。

**需裁示**：① assignee 的完整生命週期；② rework 次數從哪個既有 GitHub 原生資料推導。未裁示前 DTC-005／009／024 不得宣稱端到端可啟用；不得自行加計數 label、留言協定或狀態檔。

### P-07 跨 repo `github-actions[bot]` 的 workflow／權限／actor 拓撲未定

DTC-019 要跨 2+ repo 關 milestone，DTC-001／002 又要求最終寫入 actor 為 `github-actions[bot]`；現有來源沒有指定 workflow 放置位置、跨 repo 觸發方式或權限來源，也沒有證據顯示跨 repo 寫入後 actor 仍符合 gate 身分。這不是一句「有寫權」即可略過的部署細節。

**需裁示／實證**：每個參與 repo 的 workflow 拓撲、觸發與權限來源，並逐 repo 回驗最終 actor。不得以 PAT 或第二帳號靜默替代 `github-actions[bot]`；若平台事實做不到，須回到 ADR 層裁示，不由本 spec 改身分規則。

### P-08 非 station 狀態 label 的非法 actor runtime 處置未定

`Spec_station-command_v1.11.md:86-92` 只為 `sc:station-*`／`sc:station-done` 定義非法 actor 時的 board 紅燈、run 拒絕與 timeline 復位；SC#7 的 actor 原則卻涵蓋所有狀態 label。現有來源沒有說 `sc:legacy`、`sc:red-proven`、`sc:blocked`、`sc:gate-fail`、`sc:awaiting-user` 遭非法 actor 寫入後，runtime 應採 gate fail、重算、移除、等待使用者，或其他既有動作。

**需裁示**：上述非 station 狀態 label 各自的 runtime 阻擋與修復語意。裁示前，DTC-002 只把其 human `labeled`／`unlabeled` 事件判為 SC#7 驗收 FAIL 並保存證據；不得套用 station 專屬復位，也不得自行新增修復動作。

## 已裁示

### P-04 票面「9 處」的分母

Commander 已裁示：`tickets-loop-draft.md:63` 的 What-it-delivers 本身恰好枚舉 9 條語意條目，因此「9 處」指該枚舉，不是 v1.8 中 `deferred-to-CI` 的字面字串計數。這 9 條均已涵蓋：§3.4 → DTC-002；§5.3b → DTC-005；§7.5 → DTC-006（另有 build 接線來源 DTC-022）；驗收 #7 → DTC-007；#17 → DTC-008；#25 → DTC-009；風險 2 → DTC-010；風險 9 → DTC-011；§9a → DTC-001、DTC-012。故字面 fixture 維持實檔 5/5，語意枚舉則為 9/9；兩者分母不同，不再構成矛盾。P-04 結案，不屬待裁示。

### P-06 可達性二層政策（已裁示 `SC-DEC-REACH-001`）

Commander 已裁示（`CHANGELOG.md:33`、`build/t28/README.md:70-73`、`reachability-policy.ps1`）：可達性採**兩層判準**。第一層「可達性」＝有無收到 provider 的任何 HTTP 回應——只有網路層失敗（DNS、連線被拒、逾時）與 421 proxy 攔截判不可達；第二層「探測品質」＝狀態碼是否落在 200／401／403／429，落區間外判 **WARN 而非 FAIL**。實測結果 REACHABILITY 12/12、PROBE 11/12：Perplexity `GET /models` 回 404 判 WARN，該家無此端點，屬具名預期非缺陷。原「Spec #26 四碼 vs T-28 rework 二層」的判準衝突以此結案；CI 階段驗收依 DTC-025 執行。

**具名遺留（歸屬未定，非本票修改權）**：`Spec_station-command_v1.11.md:400` 的驗收 #26 字面仍是舊的單層四碼判準，與本裁示不一致。Spec v1.11 已定稿、不在 T-26 修改權內；該條文由誰、在哪一版重新安置**目前無主**。此落差在此具名以免重演 ADR-NP-010「需求無人重新安置」的成因；在被安置前，執行端一律以 `SC-DEC-REACH-001` 為準。

### T-15a／T-15b 空身分集合（不得重開）

本票使用者已裁示採 T-15b 的 fail-closed 方向：CI 階段 gate 身分集合為空必須阻擋；T-15a 接線時對齊。此項已落 DTC-023，不屬待裁示。

## 站 2 出口 gate

依 Spec §6，T-26 文件須經 fresh-context 第三方缺口審；審查輸入只包含本文件、T-26 票面、v1.11 主規格、ADR 與本次凍結來源清單。出口條件：第三方報告存在、首行為 `PASS` 或 `FAIL`、所有 hard finding 結案。審查結果與處置紀錄將寫在本目錄 `station2-gap-review.md`，不修改任何既有 build 檔。
