# T-22：程式碼 patch 落地路徑

依 `Spec_station-command_v1.8.md` §4.6（程式碼落地路徑）、`tickets-loop-draft.md` T-22。**地基**：`build/t21/`（四欄佇列格式、`apply-queue.ps1`、`queue-common.ps1`）。

## 與 T-21 的關鍵差異（對使用者最重要的一點）

**T-22 全程不連 GitHub**——patch 套用只操作本機 git 工作區。這代表：

- 不需要 PAT（`G:\default mount\station_command-key`）。
- 不需要先在 GitHub 開測試 issue。
- **所有驗收條件與紅→綠證明都已在沙盒用真實 git 2.43.0 完整跑過**（見 `t22-quality-gates.txt`），不像 T-21 需要使用者本機連線 GitHub 才能拿到動態證據。使用者仍可在本機重跑 `t22-test.ps1`／`t22-offline-test.ps1` 覆核，但沙盒證據本身已具備完整效力。

## 檔案

- `patch-format.md`：patch 落地規格正典——序列化格式（`git diff`／`git apply`，非 `git format-patch`／`git am`，理由見 §2）、`apply-patch` 動作型別的 payload schema、與 T-21 佇列共存的實務安排、冪等與回驗（借用 `git apply --check --reverse`）、多檔案／二進位檔邊界、衝突處理、**CRLF 行尾問題的實測結論**（§8，🚫 不用 `--ignore-whitespace`，理由與實測證據皆在文中）、交付判定（§6）。
- `patch-common.ps1`：共用函式庫（git 呼叫包裝、sha256、schema 驗證、冪等判準、交付判定 `Test-PatchDelivered` 等）。**刻意重複**（非引用）T-21 `queue-common.ps1` 的四個純 I/O 工具函式，理由見該檔檔頭註解（部署獨立性）。
- `apply-patch.ps1`：套用腳本。與 T-21 `apply-queue.ps1` **共讀同一份 `queue.json`**，只處理 `action == "apply-patch"` 的項目，其餘項目原樣通過。套用前乾跑 → 未過則具名回報不套用 → 套用後回驗 → 冪等跳過已套用項 → 失敗留佇列。`-SkipDryRunCheck` 為紅燈驗證專用開關，正式流程禁用。
- `t22-test.ps1`：紅→綠動態測試 + 驗收①②③④端對端證明。**兩段紅燈皆為斷言失敗型**（非「檔案不存在」型）：
  - 段落 A：對必然衝突 patch 用 `-SkipDryRunCheck` 強制套用（`git apply --reject`）⇒「工作區不得留下衝突標記／不得半套」斷言真的失敗（`.rej` 殘留），再用正常模式套用同一衝突 ⇒ 同斷言通過。
  - 段落 B：對照「naive self-report baseline」與真正 `Test-PatchDelivered` ⇒ 前者誤判已交付（斷言失敗），後者正確判定未交付（對應驗收條件③「未實作時 executor 自陳即被當成交付」的具體重現）。
- `t22-offline-test.ps1`：29 項函式級測試，**全部用真實 git（非 mock）**，涵蓋陣列安全性、schema 邊界、sha256、worktree 合法性、冪等判準、衝突偵測、多檔案原子性、二進位檔、交付判定。
- `fixtures/`：三組人造 patch fixture（`clean`／`conflict`／`already-applied`），各含 `base/`（起始工作區內容）、`.patch` 檔、`queue-*.json`。已於沙盒實測全部套用行為符合預期（見 `fixtures/README.md`）。
- `t22-quality-gates.txt`：出貨前三道關卡證據（BOM／ParseFile／離線測試）。

## 使用者本機驗證步驟（選用，沙盒已完整驗證過一輪）

```powershell
cd <本機 t22 資料夾>
.\t22-offline-test.ps1    # 29 項函式級測試，全綠
.\t22-test.ps1             # 紅→綠 + 驗收①②③④，全綠（含 2 個預期的 RED-CONFIRMED，不計入 FAIL）
```

若想手動覆核單一 fixture（例如 `clean/`）：

```powershell
cd <本機 t22 資料夾>
git init C:\temp\t22-demo-repo
Copy-Item fixtures\clean\base\greeting.txt C:\temp\t22-demo-repo\
cd C:\temp\t22-demo-repo
git add -A; git commit -m base -q
cd <本機 t22 資料夾>
$queueDir = New-Item -ItemType Directory -Path C:\temp\t22-queue -Force
Copy-Item fixtures\clean\T-14-0001.patch $queueDir
(Get-Content fixtures\clean\queue-clean.json -Raw) -replace '<WORKTREE>', 'C:\\temp\\t22-demo-repo' | Set-Content "$queueDir\queue.json"
.\apply-patch.ps1 -QueuePath "$queueDir\queue.json" -AppliedLogPath "$queueDir\applied-patches.log"
Get-Content C:\temp\t22-demo-repo\greeting.txt   # 預期：Hello, Universe / World
```

## 與 T-21 的操作順序建議

若 `queue.json` 同時混有 metadata 型（T-21）與 `apply-patch` 型（本票）項目，建議**先跑 `apply-patch.ps1`，再跑 `apply-queue.ps1`**——理由見 `patch-format.md` §1（`apply-queue.ps1` 遇到不認得的 `apply-patch` action 會印 `FAILED-SCHEMA` 噪音但不會遺失或誤套，此順序純粹避免噪音）。

## ⚠️ 誠實聲明

- CRLF 行尾處理已用沙盒真實實測驗證三種情況（正常情況成功、真衝突安全失敗、`--ignore-whitespace` 會產生行尾混用髒污），結論與理由見 `patch-format.md` §8；**尚未在真正的 Windows PowerShell 5.1 + Windows 版 git 上覆核**，使用者本機若遇到與沙盒結論不符的行為，請具名回報供進一步調整。
- `apply-patch.ps1` 呼叫外部 `git` 執行檔，假設其在 PATH 內可直接執行；找不到會在腳本開頭直接 `throw` 具名錯誤，不會靜默失敗。
- 交付判定 `Test-PatchDelivered` 目前只是函式庫函式，尚未接上 T-09 面板（面板揭露延伸見 `patch-format.md` §6 末段，屬 T-09 消費範圍，本票不重複實作）。
