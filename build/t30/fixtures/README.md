# T-30 人造 fixture 與獨立預期值

這些 fixture 是 Spec §3.5 註 C 所要求的獨立真相源，不由 `t30-core.ps1` 的輸出產生。

- `DECISIONS-two-vendor.md`：人造的票級「升兩廠雙審」裁示，A 軸指定 Gemini，B 軸未覆寫。
- `sample.diff`／`spec-canary.txt`：prompt 分離用固定輸入；canary 若出現在任一 A 軸 prompt 或 input list 即失敗。
- `claude-axis-a.json`／`gemini-axis-a.json`：兩份手寫 finding 原文，順序就是獨立預期順序；一條重疊、三條分歧。
- `claude-axis-b.json`：B 軸固定由 Claude 產生的手寫報告。
- `expected-dual-vendor.json`：手寫的順序、重疊、分歧與三個軸內 worst 預期值，測試只讀它比對，不從被測輸出反推。

fixture 僅含虛構內容，不含 key、token 或個資。
