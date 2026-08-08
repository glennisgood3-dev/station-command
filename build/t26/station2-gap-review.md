FAIL

# T-26 站 2 fresh-context 缺口審紀錄

審查者：第一～三輪為 executor 側 fresh-context 自審紀錄；末節為獨立第三方（≠ executor）審查  
輸入：T-26 票面、Spec v1.11、ADR、T-26 spec／checker／fixture 與來源抽查  
狀態：第四輪獨立第三方審查結論 FAIL；H-3 行號漂移已完成 rework，出口待第五輪複審

## 第一輪

FAIL

### HARD findings 與處置

| # | HARD finding | 處置 |
|---:|---|---|
| 1 | 原 checker 只比同文件表格與章節；v1.8 票面稱 9 處、實檔僅 5 個字面命中未揭露 | 新增獨立 `deferred-sources.tsv`、`readme-scan.tsv`；checker 逐筆回查來源行與片段，並雙向掃 v1.8；新增 P-04，禁止宣稱 9/9 |
| 2 | DTC-020、026～029 把現行接線債擅自延至 CI | E 包改為 pre-CI blocking backlog；DTC-020／021／026～029 明文不等 §9a，CI 只做回歸 |
| 3 | SC#7 未蓋所有狀態 label 與 `unlabeled` | DTC-002 擴為全狀態 label × 合法載體 × labeled/unlabeled × bot/human 矩陣；DTC-010 不再拿 #7 過度宣稱 |
| 4 | assignee 生命週期與跨 session rework 次數無真相源 | 新增 P-05；DTC-005／009 補 handoff、成功收件、跨 session 第二次 fail 驗收，裁示前不得啟用 |
| 5 | metadata queue 退場誤綁完整生產線與 bot 歸因 | DTC-003 啟用條件改為直接寫入＋回驗能力；明文寫入先恢復時 queue 先退、歸因仍可手動降級 |
| 6 | Spec #26 四碼與 T-28 rework 二層可達性政策衝突未列 | 新增 P-06；DTC-025 裁示前只收原始狀態，不固定 PASS 集合 |
| 7 | 跨 repo `github-actions[bot]` 權限／actor 拓撲未定 | 新增 P-07；DTC-019 以拓撲裁示與逐 repo actor 實證為前提，禁 PAT／第二帳號靜默替代 |

### 第一輪 judgement

- P-01～P-03 的停手方向正確。
- T-15a／T-15b 空集合採 CI fail-closed 的處置正確。
- 原結構檢查只證欄位存在，不證來源完備；已依 HARD #1 改成獨立 fixture。
- 原目錄掃描敘述對 t05 不夠精確；已補 README 缺席、3 份 Markdown 的閱讀範圍與其餘檔案排除理由。

## 第二輪

FAIL

### HARD findings 與處置

| # | HARD finding | 處置 |
|---:|---|---|
| 1 | DTC-002 把 station 專屬的 board／run／復位行為擴張到非 station 狀態 label | DTC-002 改為：全狀態矩陣只共同判 SC#7；station 類才驗 board／run／復位。新增 P-08，非 station runtime 語意裁示前不得類推 |
| 2 | DTC-003／019 的驗收或手動差異仍把 queue 退場硬綁 CI bot | 兩節均改成三態：寫入不可用時 queue；手動寫入恢復後 queue 先退但 actor 仍降級；升 CI 後才加 bot actor 實證 |
| 3 | DTC-029 pre-CI 驗收硬寫成直接寫 `sc:gate-fail`，忽略 §4.6 queue 仍可能有效 | 改為依接線當時能力核對 queue 或直接寫；CI bot 直寫只列升 CI 後回歸 |

### 第二輪 judgement

- 第一輪 7 項 HARD 均已結案。
- 獨立來源 fixture 與 checker 已可回查 34 個來源 occurrence、29 個 DTC。
- README 分類表屬人工凍結的語意盤點；checker 能驗證表格與 spec 對齊，但不能自行理解自然語言，交付時須誠實揭露此邊界。
- T-15a／T-15b fail-closed 方向與 P-01～P-07 的停手點無新增問題。

## 第三輪（自審收斂紀錄；非出口審查，出口以下方獨立第三方審查為準）

PASS

### HARD findings

無。

### 第三輪 judgement

- 第二輪三項 HARD 均已結案：DTC-002 已分開 station 與非 station runtime 語意；DTC-003／019 已採三態；DTC-029 已允許 pre-CI 依 §4.6 現況驗 queue 或 direct write。
- 29 個 DTC 均存在且各有五項必要欄位；實跑為 34 筆來源 occurrence、29 個來源 ID、29 個章節、29 個覆蓋，`RESULT=GREEN`。
- v1.8 五個實際字面位置已雙向檢查；票面 9 與實檔 5 的矛盾由 P-04 限制宣稱範圍。
- 21 個指定 build 目錄皆列入掃描 fixture；分類為 10 個 CI-deferred、6 個 pre-CI 接線債。
- P-01～P-08 已涵蓋目前可見的矛盾／缺口，且各有停手邊界。

### 非阻擋觀察與處置

- reviewer 建議 DTC-010 不寫「非 bot 事件皆被擋下」，避免誤讀為 P-08 尚未裁示的 runtime 規則；已改成「使 SC#7 驗收 FAIL」。
- reviewer 提醒保存最終綠燈證據；已列為交付必要檔。

## 獨立第三方缺口審（第三輪出口審；≠ executor）

FAIL

前三輪為 executor 側自審。第三方逐條複核確認：前兩輪自審所列 10 條 hard finding **確已全部結案**，文件本體品質合格；FAIL 唯一原因是文件定稿後當日新增的兩條裁示未收進本 spec。其餘 6 條待裁示（P-01／P-02／P-03／P-05／P-07／P-08）經逐條複核均為真矛盾／真缺口，維持待裁示。

### HARD findings 與處置

| # | HARD finding | 處置 |
|---:|---|---|
| H-1 | `SC-DEC-REACH-001` 已裁示可達性二層判準，但 P-06 仍列待裁示、DTC-025 仍寫「裁示前沒有固定 PASS code 集合」，照文件執行會停在已不存在的裁示點 | P-06 移入已裁示節並具名 `SC-DEC-REACH-001`；DTC-025 改依二層政策定義 CI 驗收（含 REACHABILITY 12/12、PROBE 11/12 基線與 Perplexity 404 WARN 具名預期）；另具名 Spec v1.11:400 驗收 #26 仍為舊單層四碼判準、其重新安置歸屬未定 |
| H-2 | `SC-DEC-ROUTE-001`（站 4 實作 executor 改沙盒內 Codex CLI，部分推翻 ADR-NP-011④）完全未收；C 包無任何條目涵蓋 CI 宿主起沙盒 CLI executor 的 runtime 前提（安裝、憑證、記帳） | 依 Commander 裁示落點新增 DTC-030（C 包）：CLI 安裝（實測 `@openai/codex` 0.147.0 沙盒可行）、憑證供應（§5.4 未涵蓋 CLI executor；實錄 `refresh_token_invalidated` 輪替衝突為 CI 必解前提）、token 成本併入 T-29 記帳；DTC-005／DTC-024 的 dispatch 對象與手動階段描述同步更新；不開新待裁示項 |

### SOFT findings 與處置

- S-1：掃描分母凍結在 21 個目錄、實際已 24。已擴為 24 目錄（t29／t30／t31），三者誠實聲明節皆無新的 deferred-to-CI 條目，具名零新增。
- S-2：`SC-DEC-CLI-001`（ADR-NP-011①-修正，否決範圍縮限為使用者本機 CLI）未反映。已補入 P-01 方案空間與 DTC-012（沙盒內 CLI 載體候選），不另立 DTC。
- S-3：spec 狀態行仍寫自審 PASS。已改寫為反映本輪第三方審查實際狀態。

### 處置後驗證

`check_completeness.py` 重跑 GREEN（36 筆來源 occurrence／30 個 DTC／30 個章節／30 個覆蓋，exit 0）；紅燈另於 fixture 先行、spec 未加列狀態下如實取得，記於 `red-evidence.txt` 第二段。本輪 rework 之出口仍待第三方重審，重審前本檔首行維持 FAIL。

## 第四輪獨立第三方缺口審

FAIL

第三方確認第三輪出口審的 H-1（`SC-DEC-REACH-001`）與 H-2（`SC-DEC-ROUTE-001`）在內容面均已結案；本輪 FAIL 的唯一原因是交件後活正典 `CHANGELOG.md` 新增兩行 Changed 條目，使 `SC-DEC-REACH-001` 由原第 31 行移至第 33 行，而 SRC-031 與 P-06 引用仍停在第 31 行，導致交付物自身驗收轉紅。其餘 6 條待裁示（P-01／P-02／P-03／P-05／P-07／P-08）維持未選邊。

### HARD findings 與處置

| # | HARD finding | 處置 |
|---:|---|---|
| H-3 | SRC-031 對活正典 `CHANGELOG.md` 使用易漂移的精確行號錨定；條目仍存在，但插入兩行即誤判為來源缺漏 | 依正典現況把 SRC-031 與 P-06 引用重釘至第 33 行；SRC-031 class 改為 `resolved-conflict-needle-primary`，檢查器對此 class 以 needle 全檔存在為通過條件、行號只作診斷提示，其他 fixture 列仍維持精確行號驗證。隔離 mutation 副本實際移除 `SC-DEC-REACH-001` 條目後，完整檢查器實跑 exit 1／`RESULT=RED`，確保真缺漏仍會被抓到。 |

### 處置後狀態

H-3 已完成窄範圍 rework；`red-evidence.txt` 原文保留不動，最新正常態綠燈更新於 `green-evidence.txt`。站 2 出口仍不得放行，待第五輪獨立第三方複審。
