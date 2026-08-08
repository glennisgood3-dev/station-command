# T-26 交付說明

本目錄只包含 CI 階段 spec、完備性檢查與紅綠證據，不含任何 workflow 或產品實作。

交付檔：

- `ci-stage-spec.md`：CI 階段可執行規格、來源對照、目錄掃描表與待／已裁示。
- `deferred-sources.tsv`：34 筆獨立來源 occurrence，去重對應 29 個 DTC。
- `readme-scan.tsv`：21 個指定 build 目錄的 README 存在狀態與人工分類計數。
- `check_completeness.py`：可執行的完備性檢查器。
- `red-evidence.txt`／`green-evidence.txt`：同一檢查器的紅、綠實跑證據。
- `station2-gap-review.md`：fresh-context 第三方缺口審及兩輪 rework 處置。

完備性檢查使用 Python，而不使用 PowerShell：檢查內容只是 UTF-8 Markdown 的固定 ID／標題比對，Python 標準函式庫即可完成；如此不引入 PowerShell BOM 與版本差異，腳本本身也不連網、不讀 key、不修改來源檔。

執行：

```bash
./check_completeness.py
```

紅綠證據將分別保存在 `red-evidence.txt` 與 `green-evidence.txt`。

檢查邊界：腳本會回查凍結來源的檔案、行號與字串，雙向核對 v1.8 的字面標記，並驗證每個 DTC 只有一個含五項必要欄位的章節。README 自然語言的「CI-deferred／pre-CI」分類仍是人工盤點後凍結的 fixture；腳本能偵測目錄狀態與表格計數漂移，不能自行理解自然語言並證明人工分類絕無遺漏。
