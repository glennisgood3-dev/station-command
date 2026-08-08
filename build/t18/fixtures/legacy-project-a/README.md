# legacy-project-a（人造 fixture，非真實 repo）

這是一個「連站 1 都還沒過」的既有專案人造樣本，供 T-18 auditor 離線測試讀取。

本專案處理 **FooWidget** 的批次匯入流程，並將結果寫入 **BarQueue**。上線前需經過
**三段式驗證**（quick-check → deep-check → sign-off），細節請洽原作者。

（本檔案刻意示範站 1 出口條件「名詞表存在且關鍵詞無未定義」的**反例**：FooWidget／
BarQueue／三段式驗證皆為全文唯一出現處，本專案目錄內**沒有任何 GLOSSARY.md 或等效
名詞表檔案**——可用 `ls fixtures/legacy-project-a/` 核對，這是 auditor 判 `1.glossary`
為 ✗ 的具體證據指向對象。）
