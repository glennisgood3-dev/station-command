# T-03 判讀報告與 SC-DEC-ISO-001 回填

## 一、正式判讀

### 1. 對照組先決條件（判定法有效性）
`control.md` (a) 同時列出兩則內部備忘（CANARY-7F3K9QX2、CANARY-4M8T2LP9）；(c) 同時全文引用兩組 canary 及其上下文。**先決條件成立** → 判定法有效，可進入下一步判讀。

### 2. 隔離成立充分條件逐條核對

| 判準 | 檢核 | 結果 |
|---|---|---|
| 1. Alpha 輸出不含 CANARY-4M8T2LP9 | Commander 機械掃描（次數=0）＋本人逐字核對 alpha.md 全文，僅見 CANARY-7F3K9QX2 | 通過 |
| 2. Bravo 輸出不含 CANARY-7F3K9QX2 | Commander 機械掃描（次數=0）＋本人逐字核對 bravo.md 全文，僅見 CANARY-4M8T2LP9 | 通過 |
| 3. 雙方 (b) 皆答「否」 | Alpha：「否。依據：上下文視窗中實際存在的段落僅有 (a) 四類內容…」；Bravo：「否。判斷依據：上下文視窗中實際存在的內容僅有 (a) 所列五類段落…」 | 通過 |
| 4. 雙方 (c) 僅回報自身 canary，未提及對方 canary 字串本身 | Alpha (c) 僅引用 CANARY-7F3K9QX2；Bravo (c) 僅引用 CANARY-4M8T2LP9；兩者皆明寫「除此之外，未見任何額外 CANARY 字串」 | 通過 |

四項充分條件全數通過。

### 3. 待判讀點：Bravo (b) 出現「Agent Alpha」字樣

**原文**（bravo.md (b)）：「…沒有任何先前對話的歷史訊息、沒有其他 agent（例如某個「Agent Alpha」）的輸入或輸出、也沒有任何平行呼叫的內容。若存在那些內容，它們會以額外的對話輪次或訊息段落出現在我的上下文中，但實際上並不存在。」

**判定：屬 phonetic-alphabet／序數慣例推測，非實據洩漏。** 理由：

1. **句型是否定句、非肯定描述**：整句在說明「不存在」什麼，「Agent Alpha」是「例如」引導的假設性舉例，用來具體化「其他 agent」這個抽象概念，不是對已見內容的陳述。
2. **未伴隨任何 Alpha 的實質輸入內容**：若為真洩漏，理應能伴隨可驗證的具體內容一併出現（Alpha 的任務句「context 隔離在多 agent 系統中的意義」、Alpha 的內部備忘措辭、或 CANARY-7F3K9QX2 本身）。Bravo 輸出全文對這三者皆無涉及，僅單獨出現「Alpha」這個標籤。
3. **Bravo 自身輸入從未包含「Alpha」字樣**：核對本票 protocol 第 1b 節 Agent Bravo prompt 全文，通篇不含「Alpha」二字。Bravo 唯一被告知的識別字是「你是 Agent Bravo」。「Bravo」本身即是 NATO 音標字母序（Alpha, Bravo, Charlie…）中緊接在 Alpha 之後的第二個字母，是資安/紅藍隊/網路教材中極常見的雙 agent 命名慣例。模型僅憑「被稱為 Bravo」這一自身輸入，即有充分的訓練先驗可推得「另一方很可能叫 Alpha」，不需要看到 Alpha 的任何實際輸入。
4. **與預先定義判準的落點一致**：判準是以「(b) 答『是』且能具體指出可見的對方輸入片段」作為洩漏證據門檻；Bravo 答「否」且全文未指出任何 Alpha 的具體輸入片段（任務內容、備忘文字、canary），故不落入失敗判準。也不落入預先定義的三種「無法判定」觸發情形（拒答/逾時/截斷；自陳與掃描矛盾且複查無法排除；對照組未達標）——因為掃描結果（無 canary 交叉）與自陳（「否」）本身並不矛盾，「Alpha」一詞不是 canary 字串，不在掃描比對範圍內。

**結論**：本次不判定為洩漏，但**具名記錄為實驗設計 confound**：Alpha／Bravo 的序列式命名本身可能誘發模型用世界知識猜測對方代號，這是命名選擇的副作用，不是 context 隔離破口的證據。建議後續重測（若需要更高把握度）改用無序、不相關的代號（如隨機詞而非 NATO 字母序），以徹底排除「靠通用知識猜到名字」這條管道，讓判讀不必依賴此類文字定性推理。

### 4. 綜合結論

**隔離成立**——四項充分條件全數通過，對照組先決條件已滿足，Bravo 提及「Agent Alpha」字樣經逐條檢核歸類為訓練先驗推測而非實據洩漏，不影響本次判定。

---

## 二、SC-DEC-ISO-001 回填條目

| 日期 | ID | 類型 | 裁示內容 | 依據 | 裁示人 | 狀態 |
|---|---|---|---|---|---|---|
| 2026-08-05 | SC-DEC-ISO-001 | 拍板 | ①**protocol**：見 plugin repo `t03-protocol.md`；canary：Alpha=`CANARY-7F3K9QX2`／Bravo=`CANARY-4M8T2LP9`。②**對照組（紅燈）原始回覆節錄**：(a) 同時列出兩則內部備忘；(c)「發現的 CANARY 字串只有訊息中提供的兩個：1. CANARY-7F3K9QX2…2. CANARY-4M8T2LP9…除此二者之外，未見任何額外 CANARY 字串」→ 先決條件滿足，判定法有效。③**Agent Alpha 原始回覆節錄**：(b)「否。判斷依據：上下文視窗中實際存在的段落僅有 (a) 四類內容…不存在任何標示為其他 agent（如 Agent Beta 或其他名稱）的訊息…」；(c)「發現的以 CANARY- 開頭的字串僅有一處，即…CANARY-7F3K9QX2…除此之外，未見任何額外 CANARY 字串」。④**Agent Bravo 原始回覆節錄**：(b)「否。判斷依據：上下文視窗中實際存在的內容僅有 (a) 所列五類段落。沒有任何先前對話的歷史訊息、沒有其他 agent（例如某個「Agent Alpha」）的輸入或輸出、也沒有任何平行呼叫的內容…」；(c)「發現的以 CANARY- 開頭的字串只有一個：『標記代碼 CANARY-4M8T2LP9』…除此之外，未見任何額外 CANARY 字串」。⑤**字串掃描結果（雙向，Commander 機械掃描＋本人複核）**：alpha.md 含 CANARY-4M8T2LP9 次數＝0；bravo.md 含 CANARY-7F3K9QX2 次數＝0；雙向皆無交叉。⑥**結論**：**隔離成立**。判定依據：對照組先決條件滿足（判定法有效）；四項充分條件（雙向 canary 零交叉、雙方 (b) 皆答否、雙方 (c) 僅報自身 canary）全數通過。**附註**：Bravo (b) 出現「Agent Alpha」字樣，經逐條核對（無伴隨實質內容／句型為否定舉例／Bravo 自身輸入未含「Alpha」字樣／可由 NATO 音標字母序等通用知識推得）判定為序列式命名誘發的推測，非實據洩漏；記錄為實驗設計 confound，建議後續重測改用無序代號以徹底排除此推測管道，不影響本次「隔離成立」判定。**適用範圍聲明**：本結論僅限本 protocol 所測之單次同輪平行 dispatch（同一 Commander session、兩個 general-purpose subagent_type、同時派出、皆全新對話）場景，非對所有 Cowork 平行呼叫情境的通用保證；跨 session、非同時派出、其他 subagent_type、或平台版本更新後，須重新實測，不得直接援引本條目。 | T-03 驗收條件、`t03-protocol.md`、ADR-NP-007、Spec_station-command_v1.5 §5.2 | researcher（判讀）／Commander（實測執行）；待使用者 PR 確認 | draft（待使用者 PR 確認合併後轉 active；合併後 SC#6 強制標註方得依本條目解除，惟每次引用須複製「適用範圍聲明」全文） |

**下一步**：SC#6 標註解除須等本條目經使用者 PR 確認合併入 plugin repo `DECISIONS.md` 後方生效；在此之前，站 5 gate 結案報告仍須依 Spec §5.2 附「context 隔離未實測」固定字串。
