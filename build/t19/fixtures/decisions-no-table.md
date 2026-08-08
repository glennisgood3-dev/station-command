# DECISIONS.md（人造 fixture · repo-delta，供 T-19 離線測試使用）

**情境**：內容存在（GitHub contents API 讀取成功），但完全不是 §8 定義的追加式表格格式
（例如檔案被誤放成純文字筆記，或表格標頭遭破壞）。此為「解析失敗」情境，須判 fail-closed
——讀得到位元組不代表讀得懂內容，🚫 不得因「檔案存在且讀取成功」就當作無豁免放行。

這只是一段普通文字，沒有任何 markdown 表格，也沒有「日期｜ID｜類型｜裁示內容｜依據｜裁示人」
這些欄位關鍵字同時出現在同一行。ConvertFrom-DecisionsTable 應回報 ParseOk=false。
