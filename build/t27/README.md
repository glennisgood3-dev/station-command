# T-27 · 廠商登錄表 asset（12 家）

> **本檔含站 4 REWORK 修訂（2026-08-08 第二輪）**：independent verifier（`code-reviewer`）實測到 rev-1 比對測試有假綠、README 三處不實陳述，coordinator 裁定 REWORK 並追加一項授權（asset 搬家）與一項自我否定修正。本檔為修訂後版本；rev-1 的錯誤與修法在下方對應章節逐項具名，不隱去。

## 交付檔案

| 檔案 | 用途 |
|---|---|
| `/home/claude/station-plugin/build/station-command/assets/vendor-registry.md` | **正式 asset**：12 家廠商登錄簿，隨 plugin 出貨（rev-2 起搬到此處，與 `routing-table.md` 同居 `assets/`；理由見下方「搬家」節） |
| `fixtures/endpoints-2026-08-08.txt` | **凍結 fixture**：2026-08-08 實測端點清單，**兩欄** `provider<TAB>端點`，12 列，外部既存事實，獨立於本票任何產出（rev-2 由單欄升級為兩欄，見下方「①核心缺陷修法」） |
| `tests/compare_endpoints.py` | 離線逐列配對比對測試（Python，無外部依賴、不連外網） |
| `tests/fixtures/vendor-registry-broken.md` | 與正式 asset**逐字相同、僅 DeepSeek 一列端點打錯**的變異版（單變數紅燈，僅供紅燈自證，不隨 plugin 出貨） |
| `tests/fixtures/vendor-registry-swapped.md` | 與正式 asset**逐字相同、僅 OpenAI／Cohere 兩列端點互換**的變異版（驗收①核心缺陷修法用，僅供紅燈自證，不隨 plugin 出貨） |
| `tests/evidence/green-all-pass.txt` | 綠燈證據：新版比對測試跑在正式 asset（新路徑）上 |
| `tests/evidence/red-assertion-failure.txt` | 紅燈證據：跑在 `vendor-registry-broken.md` 上 |
| `tests/evidence/red-swap-assertion-failure.txt` | **REWORK 追加**紅燈證據：跑在 `vendor-registry-swapped.md` 上，證明新比對法抓得到「provider 對到別家端點」這種假綠 |
| `tests/evidence/old-vs-new-comparator-note.txt` | **REWORK 追加**交叉確認：獨立重算 `sorted(real 端點) == sorted(swapped 端點)`，佐證舊版（多重集合比對）對這組變異版必為假綠 |
| `README.md` | 本檔 |

**另一項交付（就地修改，不在本目錄）**：`/home/claude/station-plugin/build/station-command/assets/routing-table.md`——見下方「⑤ 路由表 asset 修改內容」。

---

## ① 核心缺陷修法：端點比對改回逐列配對

### verifier 實證的問題
rev-1 的 `compare_endpoints.py` 用 `sorted(asset_endpoints) == sorted(expected_endpoints)`，只驗**多重集合**，不驗 provider↔端點的配對。verifier 把 OpenAI 與 Cohere 兩列的端點對調（多重集合不變）後跑同一支腳本，得到 `[OK]` / `ALL GREEN` / exit=0——一張把 OpenAI 指到 `api.cohere.com/v1` 的登錄表會通過 rev-1 測試，而 T-28 正是要拿這張表去組真實請求，後果是實際呼叫會打錯 provider。

### 修法
1. **fixture 升級為兩欄**（`fixtures/endpoints-2026-08-08.txt`）：`provider<TAB>端點`。provider 名稱／拼寫取自 `Spec_station-command_v1.11.md:203-214`（§5.1 原表 provider 欄，外部既存事實）；端點值（含完整路徑）取自票面驗收條件①原文 12 個字串（同樣外部既存事實）；兩者的配對關係以「端點主機」比對 spec 原表的「端點主機」欄確立（一對一無歧義，見下方核對），**不從 asset 反推**。
2. **`compare_endpoints.py` 改為逐列 `(provider, endpoint)` 配對比對**：對 fixture 內每一個 provider，取其在 asset 內的端點值，逐一比對是否與 fixture 該 provider 的端點值相同；任何一對不符即斷言失敗並具名列出「provider／預期端點／實得端點」。

provider↔主機的核對（spec §5.1 host-only 值 vs 票面 full-path 值，取 host 前綴比對，12 組皆一對一無歧義）：

| provider（spec §5.1） | spec 端點主機 | 票面①端點全路徑（host 前綴相符） |
|---|---|---|
| Gemini | generativelanguage.googleapis.com | generativelanguage.googleapis.com/v1beta |
| OpenRouter | openrouter.ai | openrouter.ai/api/v1 |
| OpenAI | api.openai.com | api.openai.com/v1 |
| xAI Grok | api.x.ai | api.x.ai/v1 |
| DeepSeek | api.deepseek.com | api.deepseek.com |
| Mistral | api.mistral.ai | api.mistral.ai/v1 |
| Groq | api.groq.com | api.groq.com/openai/v1 |
| Together | api.together.xyz | api.together.xyz/v1 |
| Perplexity | api.perplexity.ai | api.perplexity.ai |
| Fireworks | api.fireworks.ai | api.fireworks.ai/inference/v1 |
| Cerebras | api.cerebras.ai | api.cerebras.ai/v1 |
| Cohere | api.cohere.com | api.cohere.com/v1 |

### 自證：OpenAI↔Cohere 對調變異版必須轉紅
建立 `tests/fixtures/vendor-registry-swapped.md`——與正式 asset **逐字相同，僅 OpenAI 與 Cohere 兩列的端點值互換**（其餘 10 列、兩句警語、欄位說明完全不動；`diff` 只顯示 2 行差異，已存證於下方指令輸出）。

```
$ diff build/station-command/assets/vendor-registry.md build/t27/tests/fixtures/vendor-registry-swapped.md
14c14
< | OpenAI | api.openai.com/v1 | Bearer | OpenAI-compatible | registered-no-key |
---
> | OpenAI | api.cohere.com/v1 | Bearer | OpenAI-compatible | registered-no-key |
23c23
< | Cohere | api.cohere.com/v1 | Bearer | Cohere | registered-no-key |
---
> | Cohere | api.openai.com/v1 | Bearer | Cohere | registered-no-key |
```

跑新版比對測試（`tests/evidence/red-swap-assertion-failure.txt` 全文）：
```
asset   = tests/fixtures/vendor-registry-swapped.md
fixture = /home/claude/station-plugin/build/t27/fixtures/endpoints-2026-08-08.txt
[OK] fixture (provider, 端點) 筆數 = 12，provider 皆唯一
[OK] asset 資料列數 = 12
[OK] provider 集合與 fixture 相符、asset 內無重複 provider
[FAIL] 以下 provider 的端點與 fixture 逐列配對不符（provider, 預期端點, 實得端點）:
  'OpenAI': 預期 'api.openai.com/v1'，實得 'api.cohere.com/v1'
  'Cohere': 預期 'api.cohere.com/v1'，實得 'api.openai.com/v1'
[OK] 格式家族皆屬四值之一
[OK] 狀態欄位符合 Gemini available（首發）／其餘 registered-no-key 規則
[OK] 兩句具名警語存在（登錄≠啟用；金額／配額兩語意計費警語）

=== RED（斷言失敗，共 1 條）===
exit_code=1
```

交叉確認舊法確實會假綠（`tests/evidence/old-vs-new-comparator-note.txt`，獨立重算）：`sorted(real 端點) == sorted(swapped 端點)` → `True`——多重集合完全相同，證明 rev-1 的比對法對這組變異版必為 `ALL GREEN`（假綠）；新版逐列配對比對已在上方證實為 `RED`。**新比對抓得到舊比對抓不到的東西，已具體驗證。**

正式 asset（未變異）跑新版測試仍全線 `[OK]`（`tests/evidence/green-all-pass.txt`，exit=0）；DeepSeek 單變數打錯版（`vendor-registry-broken.md`）跑新版測試仍正確轉紅（`tests/evidence/red-assertion-failure.txt`，exit=1）——新比對法對「端點打錯」與「provider 配對錯」兩種錯誤模式皆能抓到。

---

## ② 驗收條件①～④逐條實跑結果（新版測試）

跑法：
```
cd /home/claude/station-plugin/build/t27
python3 tests/compare_endpoints.py /home/claude/station-plugin/build/station-command/assets/vendor-registry.md
```
完整輸出見 `tests/evidence/green-all-pass.txt`（exit_code=0）。逐條對照：

- **①（12 列 ＋ 逐列端點字串逐字相符）**：`asset 資料列數 = 12`；provider 集合與 fixture 相符、無重複；**12 列 (provider, 端點) 逐列配對**與兩欄 fixture 逐字相符（非僅端點多重集合，見上方①核心缺陷修法）。
- **②（格式家族僅四值之一）**：12 列格式家族實際用到 `OpenAI-compatible`（10 家）／`Gemini`（1 家）／`Cohere`（1 家），皆屬四值白名單；`Anthropic` 值本表未使用（12 家皆非 Anthropic 系 provider），驗收條件不要求四值全出現。
- **③（狀態僅 available／registered-no-key，Gemini 首發 available、其餘 11 家 registered-no-key）**：Gemini 恰 1 列，狀態字串精確等於 `available（首發；免費層，無需計費）`（對齊 Spec v1.11:203 與 T-31 驗收條件④要求字串）；其餘 11 列狀態精確等於裸值 `registered-no-key`；全檔無「待儲值」殘留。
- **④（含「登錄≠啟用」與外廠計費兩句具名警語）**：「登錄 ≠ 啟用」逐字存在（第 8 行）；計費警語同時涵蓋「金額」與「配額」兩詞（見下方③措辭修正說明）。

---

## ③ 措辭修正說明（授權出處更正）

**rev-1 錯誤**：README 寫「依票面『⚠️ 措辭需修正』段授權」，但 repo 全檔 grep「措辭需修正」命中 0——這段字出現在 coordinator 的 dispatch prompt 裡，不在票面（`tickets-vendor-draft.md`）原文。授權本身成立，出處引錯。

**更正**：票面驗收條件④原文只要求「外廠按量計費」一句警語。但 Gemini 首發走免費層、不需開啟計費（`Spec_station-command_v1.11.md:218`），若警語逕寫「外廠按量計費」會與 Gemini 首發列矛盾。**Commander 裁示授權**改寫警語為涵蓋兩種語意——付費層＝金額、免費層＝配額；**spec 依據＝`Spec_station-command_v1.11.md:338`**（§7.6「上限的兩種語意須具名」段）。這是本票被授權對票面原文的唯一調整，其餘驗收條件（①②③與紅燈設計本身）均逐字照票面執行。

---

## ④ 紅燈斷言原文與「真的失敗」的證據摘要

### 為何原票面紅燈設計不算數
票面原文：「先寫『12 列且端點逐字相符』比對 ⇒ 必紅（asset 不存在）」。這是**載入失敗型紅燈**——asset 不存在時，比對邏輯根本沒東西可比，而非「真的跑到斷言、拿真資料比對後才發現不符」。依 Spec §6 註 A：「須為斷言失敗的紅」，載入／collection 失敗不算數（`Spec_station-command_v1.11.md:294-301`）。

### 改法
先建立 `tests/fixtures/vendor-registry-broken.md`——**與正式 `vendor-registry.md` 逐字相同，僅 DeepSeek 一列端點打錯**（`api.deepseek.com` → `api.deepseek.co`，短少一個字母），其餘 11 列、兩句警語、欄位說明**完全不動**（單變數診斷，`diff` 只顯示 1 行差異，見下方；**rev-1 曾誤稱「修正該列後即為正式 asset」，但檔頭有兩處額外 prose 差異，已在 rev-2 修正為程式化生成、確保單變數**）：

```
$ diff build/station-command/assets/vendor-registry.md build/t27/tests/fixtures/vendor-registry-broken.md
18c18
< | DeepSeek | api.deepseek.com | Bearer | OpenAI-compatible | registered-no-key |
---
> | DeepSeek | api.deepseek.co | Bearer | OpenAI-compatible | registered-no-key |
```

### 斷言原文（`tests/compare_endpoints.py`，逐列配對版）
```python
mismatches = []
for provider, expected_endpoint in expected_map.items():
    actual_endpoint = asset_map.get(provider)
    if actual_endpoint != expected_endpoint:
        mismatches.append((provider, expected_endpoint, actual_endpoint))
assert not mismatches, (
    "以下 provider 的端點與 fixture 逐列配對不符（provider, 預期端點, 實得端點）:\n"
    + "\n".join(f"  {p!r}: 預期 {exp!r}，實得 {act!r}" for p, exp, act in mismatches)
)
```

### 真的失敗的證據（`tests/evidence/red-assertion-failure.txt` 全文）
```
asset   = tests/fixtures/vendor-registry-broken.md
fixture = /home/claude/station-plugin/build/t27/fixtures/endpoints-2026-08-08.txt
[OK] fixture (provider, 端點) 筆數 = 12，provider 皆唯一
[OK] asset 資料列數 = 12
[OK] provider 集合與 fixture 相符、asset 內無重複 provider
[FAIL] 以下 provider 的端點與 fixture 逐列配對不符（provider, 預期端點, 實得端點）:
  'DeepSeek': 預期 'api.deepseek.com'，實得 'api.deepseek.co'
[OK] 格式家族皆屬四值之一
[OK] 狀態欄位符合 Gemini available（首發）／其餘 registered-no-key 規則
[OK] 兩句具名警語存在（登錄≠啟用；金額／配額兩語意計費警語）

=== RED（斷言失敗，共 1 條）===
exit_code=1
```
關鍵：前三條斷言（fixture 備妥、資料列數=12、provider 集合相符）先通過——證明測試**確實載入、解析了 12 列**（非載入失敗），接著逐列配對比對這一條斷言**真的比對後失敗**（具名列出 provider／預期值／實得值）。其餘 4 條（②③④＋provider 集合）在這份幾乎正確的 asset 上仍為 OK，證明失敗確實精準定位在①這一條，非全盤崩潰或例外中止。

### 轉綠
修正該列（改回 `api.deepseek.com`）後即為正式 `vendor-registry.md`（DeepSeek 這一支變異版現在確保除該列外逐字相同，故修正後 diff 為零），重跑同一支測試 ⇒ 全部斷言 `[OK]`，`=== ALL GREEN ===`，exit_code=0（見 `tests/evidence/green-all-pass.txt`）。

---

## ⑤ 路由表 asset：實際改了哪一份、改了什麼

**改的檔案**：`/home/claude/station-plugin/build/station-command/assets/routing-table.md`（T-06 骨架 ＋ T-11 assets 既有產物，票面已具名授權本票就地修改）。

**改了什麼**（皆為新增段落／更新指向，未刪動既有兩層路由表格內容，`check-t11.sh` 每次改動後皆重跑確認迴歸 GREEN）：
1. 檔頭版本標註由 `Spec_station-command_v1.5.md` 更新為 `Spec_station-command_v1.11.md`（並註記表格內容自 v1.5 至 v1.11 未變動，僅新增 provider 維度段落）。
2. 新增一節「executor 欄語意擴充：provider 維度」——逐字引用 Spec §5.1「provider 維度」段（`executor 由「agent 名」擴為「provider ＋ model」`），並加註（明確標示**非逐字轉錄**）適用說明與 `provider＋model` 範例。
3. 該節指向廠商登錄表為 provider 清單的正典位置；**rev-2 更正指向路徑**為 `build/station-command/assets/vendor-registry.md`（asset 搬家後的新址，見下節），rev-1 原指向 `build/t27/vendor-registry.md` 已作廢。

**未改動**：第一層「站 → 預設 executor」9 列表格、第二層規則段落、`fowler-smells.md`、`check-t11.sh`、`t11-red-green.txt`——本票不重跑 T-11 的紅綠證據鏈，只做迴歸確認。

---

## ⑥ 出貨路徑修正：asset 搬家

**問題**：票面 What it delivers 首句是「**隨 plugin 出貨**的廠商登錄簿 asset」，而 `routing-table.md`（同為出貨 asset）原以 `build/t27/vendor-registry.md` 指涉它——出貨時 `build/t27/` 不隨 plugin 走，這條指向會斷。

**處置（coordinator 採納 verifier 建議、明確授權）**：`vendor-registry.md` 搬到 `/home/claude/station-plugin/build/station-command/assets/vendor-registry.md`，與 `routing-table.md`、`fowler-smells.md` 同居 `assets/` 出貨。原 `build/t27/vendor-registry.md` 已刪除（非重複留存）。同步更新：
- `routing-table.md` 內指向路徑（見上節③）。
- 本目錄所有測試呼叫改用新路徑作為 `asset` 參數（見上方②③④的跑法區塊）。
- `fixtures/`、`tests/` 兩個測試用目錄**留在 `build/t27/`**——這兩者是驗收基礎設施，不是出貨 asset 本身，不隨 plugin 走；`vendor-registry.md` 內對 fixture 的路徑引用（`build/t27/fixtures/endpoints-2026-08-08.txt`）維持不變、仍有效。

---

## ⑦ 自我否定修正：權威分工聲明

**問題**：`vendor-registry.md` 檔頭原寫「若兩者不一致，以 spec §5.1 為準」，但本檔刻意偏離 spec §5.1 原表兩處：(a) 端點欄用完整路徑、spec 欄名是「端點**主機**」且值無路徑（rev-1 已具名）；(b) OpenRouter 狀態 spec 為 `registered-no-key｜建議擴充路徑`、本檔取裸值 `registered-no-key`（**rev-1 未具名，遺漏**）。若不釐清，T-28 讀表時會遇到「規則說以 spec 為準、但實際值又跟 spec 不同」的自我否定。

**修正**（見 `vendor-registry.md` 檔頭第 3–6 行）：改為「provider 名稱集合、認證方式、格式家族——以 spec §5.1 為準；端點完整路徑與狀態欄裸值化——兩處刻意偏離、以本檔（T-27 驗收條件）為準」，並具名列出兩處偏離的內容與依據（端點路徑依驗收條件①；OpenRouter 附註省略依驗收條件③，明確寫出「具名放棄『建議擴充路徑』這則導覽性文字，不影響登錄狀態本身」）。

---

## 為何用 Python 而非 PowerShell

票面要求「比對測試若用 PowerShell：所有 .ps1 帶 UTF-8 BOM…用 Python 寫也可以，但要說明理由」。本票選 Python，理由：
- 比對邏輯是純離線字串／表格解析與逐列配對比對，無任何 Windows 專屬依賴。
- 環境是 Linux 容器，`python3`（3.11.15）為原生可用工具鏈；引入 PowerShell 反而多一層跨平台轉譯風險（尤其中文字元與 BOM 處理）。
- 既有的 T-11 紅綠腳本（`check-t11.sh`）與其產物本身也是 bash／純文字風格，Python 與既有交付物風格一致。

---

## ⑧ 自檢數字（rev-2）

| 項目 | 數值 |
|---|---|
| `vendor-registry.md`（新路徑）資料列數 | 12 |
| fixture (provider, 端點) 筆數 | 12，provider 皆唯一 |
| 正式 asset 跑新版測試 | 全部 7 條斷言 `[OK]`，exit_code=0 |
| DeepSeek 單變數打錯版跑新版測試 | 1／7 斷言失敗（①逐列配對），exit_code=1 |
| OpenAI↔Cohere 互換版跑新版測試 | 1／7 斷言失敗（①逐列配對，具名列出兩個 provider 的錯誤配對），exit_code=1 |
| 獨立交叉確認：`sorted(real)==sorted(swapped)` | `True`（證明舊多重集合比對法對此變異版必為假綠） |
| `routing-table.md`（T-11 舊 asset）列數迴歸檢查（`check-t11.sh`） | 9／9，`ALL GREEN`（本票兩輪修改後皆重跑確認未破壞既有紅綠基線） |

---

## ⑨ 誠實聲明（rev-2，含 rev-1 錯誤具名）

- **rev-1 的三項具名錯誤與修正狀態**：
  1. 端點比對用多重集合而非逐列配對，導致 provider↔端點配對錯誤時假綠——**已修正**（見上方①）。
  2. README 聲稱「本表列序改採 spec §5.1 原表的 provider 排序」與「Gemini 因首發置頂例外」——**兩項宣稱皆為虛構、已核實不實**（實際列序恰為票面條列順序，非 spec 順序），rev-2 予以**刪除**、不再以任何列序理由解釋比對方式的選擇（比對方式選擇的真正理由是逐列配對比對，與列序無關，見①）。
  3. README 聲稱測試授權出處為票面「⚠️ 措辭需修正」段，該字串在 repo 全檔 grep 命中 0——**已更正**出處為 Commander 裁示 ＋ `Spec_station-command_v1.11.md:338`（見③）。
  4. README 聲稱 broken 版「與正式 asset 逐字相同，僅 DeepSeek 一列端點故意打錯」但實際有 2 處額外 prose 差異——**已改用程式化生成**確保單變數，現已對照 `diff` 輸出證實僅 1 行差異（見④）。
- 本票（rev-1、rev-2 皆同）**未呼叫任何外部 API**、未連外網；fixture 的 provider 名稱取自 `Spec_station-command_v1.11.md:203-214`、端點字串取自票面驗收條件①原文，兩者皆外部既存事實，**未從 `vendor-registry.md` 反推**——已用「host 前綴比對」表格具體列出配對依據（見①），非憑印象手動配對。
- 認證方式欄（`Bearer`／`API key`）取自 `Spec_station-command_v1.11.md` §5.1 原表，非本票獨立查證；若 spec 該表日後修訂，本 asset 須同步更新（權威分工聲明已寫在 `vendor-registry.md` 檔頭，見⑦）。
- 格式家族「Anthropic」值本票**未實際使用**（12 家廠商登錄無一屬此類）；保留該枚舉值僅因驗收條件②明列四值。
- 未觸碰任何 key／token；`vendor-registry.md` 與所有測試檔已重新 grep 排查常見 key 樣式（`sk-`／`api_key=`／`Bearer <長字串>`／`AIza...`），確認不含金鑰值或金鑰檔路徑。
- 未修改 `build/t05`～`build/t26` 任何檔案；本輪唯二寫入點為 `build/station-command/assets/vendor-registry.md`（新家）與 `build/station-command/assets/routing-table.md`（就地修改），皆為 coordinator 明確授權範圍。
- 未改動 Spec 或任何 tickets 檔。
