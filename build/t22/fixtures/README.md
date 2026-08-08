# fixtures — T-22 patch 落地驗收用人造資料

三組 fixture，對應驗收條件①②④（乾淨可套用／已套用過／必然衝突）：

## 1. `clean/`

- `base/greeting.txt`：`"Hello\nWorld\n"`（套用前的工作區起始內容）。
- `T-14-0001.patch`：把 `greeting.txt` 第一行 `Hello` 改成 `Hello, Universe`（真實用 `git -c core.autocrlf=false diff --no-color --binary` 產生，已用沙盒 git 2.43.0 實測可乾淨套用）。
- `queue-clean.json`：一筆 `apply-patch` 型佇列項，`source="T-14"`。
- **獨立預期值來源**：套用後 `greeting.txt` 應逐字等於 `"Hello, Universe\nWorld\n"`（patch 檔本身宣告的目標內容，非任何腳本自陳）。

## 2. `conflict/`

- `base/greeting.txt`：`"Hello\nEveryone\n"`（**故意**與 `clean/` 的 base 不同——第二行是 `Everyone` 不是 `World`）。
- `T-15-0001.patch`：內容與 `clean/T-14-0001.patch` **逐位元組相同**（同一份 patch，sha256 相同），仍預期基準是 `"Hello\nWorld\n"`；套到 `conflict/base` 上必然因第二行 context 不吻合而衝突。`source="T-15"`（刻意換一個票號，避免與 `clean/` 混淆）。
- **已實測**：`git apply --check` 對此組合回傳非 0，訊息含 `patch does not apply`。
- **獨立預期值來源**：套用後 `greeting.txt` 必須**維持原樣** `"Hello\nEveryone\n"`（不得半套），佇列項必須仍留在 `queue.json` 內。

## 3. `already-applied/`

- `base/greeting.txt`：`"Hello, Universe\nWorld\n"`（**已經是** `clean/T-14-0001.patch` 套用後的目標內容）。
- `T-14-0001.patch`：與 `clean/` 完全相同的 patch 檔（複製過來，sha256 相同）。`source="T-14"`。
- **已實測**：`git apply --check --reverse` 對此組合成功（exit 0），代表冪等判準會判定「已達成」。
- **獨立預期值來源**：套用腳本應輸出 `SKIPPED-ALREADY-APPLIED`，不呼叫任何真正的寫入指令，`greeting.txt` 內容不變。

## ⚠️ 使用前必改：`"worktree": "<WORKTREE>"` 是佔位字串

**不要**直接把 fixture 的 `queue-*.json` 複製去套用真正的工作目錄。使用前：

1. 建立一個乾淨的 git 工作目錄（`git init` 一個新資料夾即可，不需要遠端），把對應 `base/` 內的檔案複製進去、`git add -A && git commit`。
2. 把 `queue-*.json` 內的 `"<WORKTREE>"` 改成該資料夾的**絕對路徑**。
3. 把改好的 `queue-*.json` 複製成 `queue.json`（或用 `-QueuePath` 指到它），與 `patches/` 內對應的 `.patch` 檔放進同一個佇列檔目錄結構（`payload.patchFile` 是相對於佇列檔所在目錄的路徑，見 `patch-format.md` §3）。
4. 執行 `.\apply-patch.ps1`。

`t22-test.ps1` 與 `t22-offline-test.ps1` 已把上述步驟自動化（在暫存目錄動態建立 worktree、動態改寫佇列項的 `worktree` 欄位），不需要手動操作即可在沙盒內驗證；本 README 供使用者在自己機器上手動覆核時參考。

## 產生權具名標註

三組 fixture 皆為**人造測試資料**，由 T-22 executor 直接寫入 `build/t22/fixtures/`（開發階段測試用，不經過任何 skill 的產生權路徑）。正式運作時 `apply-patch` 型佇列項的唯一合法產生者＝站 4 executor（`fullstack-developer`／`ak-cook`／`ak-test`），見 `patch-format.md` §10。
