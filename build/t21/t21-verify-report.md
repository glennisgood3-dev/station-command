# T-21 獨立驗收報告（Verifier）

**驗證日期**：2026-08-05 | **驗證者角色**：QA Lead（獨立驗證，不採信 executor 自陳）

---

## 逐條驗收判定（①～⑥）

| 項 | 驗收條件 | 判定 | 理由 |
|---|---------|------|------|
| ① | 三筆佇列項套用後 payload 相符 | **需本機實測** | 靜態：fixtures 與 apply-queue.ps1 邏輯完整 ✓；動態：需實連 GitHub API |
| ② | **冪等**：同一佇列連續套用兩次無重複 | **PASS（靜態）**<br>**需本機動態驗證** | apply-queue.ps1 L144-151 每筆套用前讀現況；L164-176 回驗不符留佇列；邏輯設計正確；動態需本機跑 |
| ③ | **回驗**：不符留佇列並具名回報 | **PASS（靜態）** | L171-176：FAILED-VERIFY 時將 $item 加回 remaining；具名回報格式正確 |
| ④ | **對帳出列**：GitHub 已落地項自動出列 | **需本機實測** | reconcile-queue.ps1 L79-104 邏輯完整（無寫 GitHub）；需實跑驗證出列邏輯 |
| ⑤ | **產生權**：run 嘗試產 label 類被拒並具名 | **N/A（待 T-24 接上）** | enqueue-guard.md §3 規格明確（拒絕＋具名）；實際強制點在 T-24 run 的 SKILL.md 邏輯 |
| ⑥ | **遺失降級**：佇列檔不存在具名回報＋exit 0 | **PASS（靜態）** | apply/reconcile 兩支 L47-50：具名回報「待寫佇列不存在，本批動作將重新產生」；exit 0；GitHub 無讀寫 |

---

## 紅燈真實性判定（**關鍵**）

### executor 的紅
```
[RED] apply-queue.ps1 不存在：檔案缺失
[RED] enqueue-guard.md 不存在：檔案缺失
```

### 獨立判定結論
**✗ FAIL** — 此紅**不符 Spec §6 站 4 出口條件**

**理由**：
- Spec §6 明文：「每張票有紅→綠兩段證據且紅是**斷言失敗的紅**（非載入／collection 失敗）」
- 同 §4.6：「載入失敗型的紅不算數」
- executor 的紅本質：**前置條件缺失**（檔案尚未產出），非**冪等／回驗邏輯本身的斷言失敗**
- 綠的達成方式：檔案產出後靜態檢查通過，不是「設計本身被驗證」

**結論**：紅→綠轉換**可視為 RED-PROVEN 條件未達成**，不能落 `sc:red-proven` label；本票**靜態檢查滿足、但紅燈質量不符出口條件**。

---

## 獨立靜態檢查（詳細）

### A 冪等邏輯（§4.6）
```
✓ apply-queue.ps1 L144：在 foreach $item 迴圈內呼叫 Test-ItemSatisfied
✓ L145-151：已達成 payload 狀態即跳過（SKIPPED-ALREADY-SATISFIED）
✓ L154-161：未達成才執行 API 寫入（switch 分支）
✓ L164：套用後立即回驗（再讀一次 GitHub 現況）
✓ L165-177：相符出列、不符留在 remaining（FAILED-VERIFY）
✓ 無動作指紋：未使用 hash/fingerprint，只靠 status 比對
✓ 判定：冪等邏輯**實現完整**
```

### B 回驗不符留佇列（§4.6）
```
✓ apply-queue.ps1 L170-177：post.Satisfied = false 時
  → Status = FAILED-VERIFY
  → remaining.Add($item)
  → 絕不標記為 APPLIED（出列）
✓ 具名回報：L172 detail 含「套用後回驗不符」
✓ 判定：**實現正確**
```

### C 100 字元守門（§4.6）
```
✓ queue-common.ps1 L94-118：Get-DescriptionLengthViolations 遞迴掃 payload
✓ apply-queue.ps1 L130-140：套用前檢查（逾 100 即 FAILED-VALIDATION 不送 API）
✓ 執行順序：驗証 → 描述檢查 → schema 檢查 → 冪等比對 → 套用
✓ 守門在 API 前：✓（L130-140 → L154-161 API 呼叫）
✓ 判定：**防護完整**
```

### D reconcile-queue.ps1 只讀 GitHub（§4.6）
```
✓ 全文只 dot-source queue-common.ps1（Get-Current* 函式）
✓ 無任何 Invoke-RestMethod -Method Put/Post/Patch 到 GitHub
✓ 只寫本機佇列檔 L104：Write-QueueFile
✓ 判定：**嚴格遵行「只讀不寫」**
```

### E 產生權表（§3.3 ↔ enqueue-guard.md）
```
✓ enqueue-guard.md §1 表格：
  | 佇列動作 | 產生者 |
  | set-labels | gate |
  | close-issue | gate |
  | create-issue | intake |
  | create-milestone | intake |
  | comment | 依原動作歸屬 |

✓ 逐字對照 Spec §3.3：一致
✓ 違反判定 §3 明確：拒絕並具名回報
✓ 判定：**產生權不變式規格完備**
```

---

## 獨立發現的風險（executor 未提及）

### 【HIGH】comment 冪等邊界風險
**問題**：queue-common.ps1 L199 — 以字串完全相等判「已達成」
```powershell
$found = $comments | Where-Object { $_.body -eq $Item.payload.body }
```

**風險**：
- GitHub API 未公開承諾 comment body 的行尾正規化策略
- 若 PowerShell 送出時用 CRLF 但 GitHub 存儲為 LF，下次讀回時字串不等 → 重複貼留言
- 反向亦可能：本機 LF，GitHub 正規化為 CRLF → 同樣不匹配

**來源**：GitHub Actions runner #1462 有先例；queue-format.md §3.3 本身標註「已知邊界」但未測

**建議**：
1. 使用者本機實測時，檢查同一則留言是否被重複貼
2. 若出現重複，需補充「body 先正規化為 LF 再比對」邏輯（或 trim 尾空白）
3. 長期：向 GitHub 確認 API 正規化行為

---

### 【MEDIUM】PowerShell 5.1 UTF-8 編碼邊界
**現狀**：
- 腳本頭 `#requires -Version 5.1` ✓
- queue-common.ps1 L17：明確用 `System.Text.UTF8Encoding($true)` ✓
- Invoke-RestMethod 在 5.1 對 UTF-8 回應的解析：**未明確驗證**

**邊界**：
- PowerShell 5.1 對 JSON 回應是否自動偵測 Content-Type charset？（GitHub 若返回 charset=utf-8 是否正確解析？）
- 繁中字符在 5.1 的往返傳遞：佇列檔 JSON 與 GitHub API 請求體中文是否完整

**建議**：
1. 實測環境在 Windows 上以繁中字符（如 source 欄位「組件編號」）跑一次
2. 檢查報告檔的繁中是否亂碼（已用 UTF8BOM，應無虞）
3. 若 API 回應有繁中也驗證讀取正確

---

### 【LOW】queue.json 並發讀寫
**現狀**：無 lock 機制，但風險低
- 使用者手動依序執行，不會同時跑兩個 PowerShell 進程
- 佇列檔 JSON 單次寫入（一個 ConvertTo-Json 呼叫）原子性足夠

**建議**：無需改動（使用者手動操作的前提下安全）

---

## 靜態滿足 vs. 動態待驗

| 面向 | 狀態 | 備註 |
|------|------|------|
| 冪等邏輯設計 | ✓ PASS | apply-queue 程式碼驗證無誤 |
| 回驗機制 | ✓ PASS | 不符時確實留佇列 |
| 對帳邏輯 | ✓ PASS（靜態） | 程式碼正確；需本機實跑驗證行為 |
| 產生權規格 | ✓ PASS | enqueue-guard.md 明確；T-24 待接上實施 |
| 遺失降級 | ✓ PASS | 具名回報+exit 0；需本機驗證 GitHub 不受影響 |
| **紅燈質量** | ✗ FAIL | 不符 Spec §6 站 4 斷言失敗要求 |

---

## 總判定：站 4 出口條件可否滿足？

### 現狀
- ✓ 驗收①②③④⑤⑥：靜態設計完整、規格完備
- ✗ 紅燈質量：**檔案缺失型，不算斷言失敗的紅**
- ⏳ 動態驗收：需使用者本機以真實 GitHub PAT 實跑

### Spec §6 要求
> 「每張票有紅→綠兩段證據且紅是**斷言失敗的紅**（非載入／collection 失敗）」

### 結論
**❌ `sc:red-proven` 現在不能落**

**理由**：
1. executor 的紅是「檔案不存在」（載入失敗），不符定義
2. 綠的成立方式也是「檔案產出後通過靜態檢查」，非「冪等邏輯驗證」
3. 實際冪等／回驗的斷言失敗紅，需使用者本機跑過才產生

**可否進行下一輪**：
- 靜態面：✓ 可視為就緒（代碼設計＋規格文件無缺）
- gate 審核面：需補一份「動態驗收計畫」或「已知限制」說明：
  - 手動階段無法在沙盒跑動態測試（GitHub API 不可達）
  - 紅燈轉換形式不符原預期（改以「靜態檢查 GREEN」替代）
  - 建議落 label 時註記「靜態驗收通過，動態待使用者本機實施」

**未來使用者本機實測後**：可重新產生符合「斷言失敗」的紅，再補齋驗收條件④

---

## 推薦立即行動

| 優先 | 項目 | 執行者 | 期限 |
|------|------|--------|------|
| P0 | 補充「紅燈質量說明」：解釋為何採靜態檢查綠，不符原「斷言失敗」定義 | executor | 同步 |
| P1 | 提供「動態驗收檢查清單」供使用者本機跑（已在 README.md 有步驟） | executor | 已有 ✓ |
| P2 | comment 冪等测試：本機跑一次並驗證是否重複貼留言 | 使用者 | 進行驗收① |
| P3 | UTF-8 邊界驗證：繁中字符往返確認 | 使用者 | 同步驗收 |

---

**簽核**：驗收報告已獨立完成，無採信 executor 自陳。
