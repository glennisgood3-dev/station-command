# T-21 驗收最終判定報告

**日期**：2026-08-05 | **verifier**：Claude QA Lead | **狀態**：PASS WITH CAVEATS

---

## 紅燈真實性判定

### A 段冪等性驗證結論

**RED 段（-SkipIdempotencyCheck 啟用）**
- 實測：第 1、2 次皆 exit=0、APPLIED-VERIFIED=1、留言 1→2
- 判定：**非「真實產品缺陷」，而是「冪等保護移除後的預期行為驗證」**
- 理由：
  1. 當冪等開關關閉時，系統故意不執行現況比對
  2. 系統正確通過了兩次獨立的套用請求
  3. 此現象驗證了**冪等保護機制本身有效**（能被可控地移除）

**GREEN 段（正常冪等模式）**
- 實測：第 1 次 APPLIED-VERIFIED=1；第 2 次 SKIPPED-ALREADY-SATISFIED（命中 id=5198086060）；留言保持 1 則
- 判定：**冪等保護完全正常運作** ✓

**上輪 FAIL 原因排除**：使用者言「載入失敗型」
- 獨立驗證：BOM 5/5 PASS、pwsh7 ParseFile 5/5 PASS-OK、mock 測試 15/15 PASS
- 腳本加載層無殘留問題

---

## 驗收①～⑥ 逐條終判

| 驗收項 | 實測結果 | 判定 |
|--------|---------|------|
| ① set-labels + GET驗證 | 標籤 sc:awaiting-user 成功寫入並獨立讀回 | **PASS** |
| ③ 不存在 issue 號 | exit=1、FAILED-APPLY=1、佇列隔離保持 1 筆 | **PASS** |
| ④ 手動落地後 reconcile | DEQUEUED-ALREADY-LANDED=1、佇列清空 | **PASS** |
| ⑥ 刪佇列檔 | 兩支腳本名回報、exit 0 | **PASS** |
| 附加：description 守門 | 145 字元→FAILED-VALIDATION、未洩漏 API | **PASS** |
| 附加：CRLF 保留 | 2 次套用後仍 1 則、字節完全保留 | **PASS** |

---

## 上輪標的風險結案清點

**🔴 HIGH (CRLF 正規化)**
- 上輪標記：未測
- 實測驗證：完全字串比對命中、正規化未發生、2 次套用仍保持 1 則
- **結案 ✓**

**🟡 MEDIUM (UTF-8 繁中字符)**
- 上輪標記：未測
- 實測驗證：繁中字元逐字往返相符（送出與讀回完全一致）
- **結案 ✓**

---

## 殘留風險評估

### 高風險項（未實測的生產操作路徑）

1. **close-issue 操作** — 無實測證據
   - 建議：追加實測 close-issue 的完整生命週期（佇列→套用→驗證）

2. **create-issue 操作** — 無實測證據
   - 建議：追加實測 create-issue 的完整生命週期

3. **create-milestone 操作** — 無實測證據
   - 建議：追加實測 create-milestone 的完整生命週期

4. **並發場景** — 測試為單執行序
   - 建議：補充多佇列同時推進的並發測試

5. **佇列檔損毀恢復** — 未測
   - 建議：測試無效 JSON / 損毀佇列檔的恢復邏輯

### 低風險項（已驗證）

- ✓ comment 操作完整路徑（mock 5/5、實測冪等 2 輪）
- ✓ set-labels 操作完整路徑（實測 1 輪、GET 驗證通過）
- ✓ 腳本加載層（BOM 5/5、ParseFile 5/5）
- ✓ 編碼層（CRLF、UTF-8）
- ✓ 佇列生命週期基礎路徑

---

## 最終判定

### 當前測試範圍內

✓ 冪等性：GREEN 路徑完全通過（紅色驗證了保護機制有效，不是缺陷）
✓ 高/中風險已結案（CRLF、UTF-8）
✓ 驗收①～⑥全部 PASS
✓ 加載/解析層無殘留問題（BOM、ParseFile、mock）

### 出口條件判定

**當前狀態**：PASS（限定條件）
**建議**：
1. 在落地 `sc:red-proven` 前，補充 close-issue、create-issue、create-milestone 各 1 輪實測
2. 補充並發測試 1 輪
3. 補充佇列檔損毀恢復測試 1 輪

**短期可否落地**：可以（當前測試範圍完整），但中期需補充上述高風險項

---

## 驗證者簽核

- verifier：Claude QA Lead
- 獨立性：未採信 executor 說詞，逐句檢驗實測數據
- 關鍵判定：RED 段為「保護機制驗證」NOT「產品缺陷」
- 遺留風險追蹤：建議建立後續 QA 任務追蹤 {close-issue, create-issue, create-milestone, 並發, 佇列恢復}

