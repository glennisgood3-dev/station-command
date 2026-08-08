# DECISIONS.md（人造 fixture · repo-alpha，供 T-19 離線測試使用）

依 Spec §8 模板：追加式表格，只追加不改寫。本檔為 T-19 測試用人造 fixture，非任何真實 repo 的
DECISIONS.md（不得與 build/t05/decisions-additions.md 混淆，該檔為 T-05 交付物，本票只讀不改）。

**情境**：含一筆已過期的豁免條目（期限 2026-08-01，早於測試基準日 2026-08-08）。

| 日期 | ID | 類型 | 裁示內容 | 依據 | 裁示人 | 狀態 |
|---|---|---|---|---|---|---|
| 2026-06-01 | SC-DEC-T19-001 | 拍板 | 一筆普通拍板條目，非豁免類，供驗證 Get-ExemptionRows 正確過濾 | t19-offline-test.ps1 | 測試者 | active |
| 2026-06-01 | EX-ALPHA-001 | 豁免 | 項目：舊票格式（缺 REQ-ID 欄位命名慣例）｜理由：legacy 收編案，八欄位已補齊但命名沿用舊制｜範圍：repo-alpha 全部舊票｜期限：2026-08-01｜本項【未】處理 | §7.4 補件／豁免規則 | 測試者 | active |
