# T-07：label scheme 與 anchor／milestone 慣例落地

依 `Spec_station-command_v1.5.md` §3.1～§3.4。Cowork cloud 對 GitHub 寫入全部不通（MCP 403、Bash 被 proxy 攔），本票交付＝定義檔＋腳本，**實際套用須由使用者在本機執行** `apply-labels.ps1`（讀 PAT：`G:\default mount\station_command-key`）。

## 檔案

- `labels.json`：§3.3 全部 13 個 `sc:` label 定義（name／color／description，description 含合法載體註記）。不含「不引入的 label」（`sc:exec-*`／`sc:red-pending`／`sc:dual-vendor`）。
- `templates.md`：work ID（`W-<slug>`）、primary anchor body、milestone description 三種格式模板，逐字對齊 §3.1。
- `apply-labels.ps1`：本機 PowerShell 套用腳本，讀 `labels.json` 對 repo 建立／PATCH 對齊全部 label。
- `verify-labels.ps1`：比對腳本，列出 repo 現有 `sc:` label 與 `labels.json` 差異，GREEN／RED 判定。

## 紅燈聲明

驗收時**先跑** `verify-labels.ps1`（套用前，repo 尚無任何 `sc:` label 或不齊）**必為 RED**（缺漏清單＝labels.json 全部 13 個）；使用者於本機跑 `apply-labels.ps1` 套用後，再跑 `verify-labels.ps1` **必轉 GREEN**（無缺漏、無多餘、color/description 皆符）。
