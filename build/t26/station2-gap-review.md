PASS

# T-26 站 2 fresh-context 第三方缺口審

審查者：fresh-context 第三方 reviewer（非 spec 產出者）  
輸入：T-26 票面、Spec v1.11、ADR、T-26 spec／checker／fixture 與來源抽查  
狀態：PASS；兩輪 HARD findings 均已結案

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

## 第三輪

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
