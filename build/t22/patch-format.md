# T-22 · 程式碼 patch 落地路徑規格

依 `Spec_station-command_v1.8.md` §4.6（程式碼落地路徑）與 `tickets-loop-draft.md` T-22 定案。本檔是 patch 落地的**唯一格式正典**；`apply-patch.ps1`／`patch-common.ps1` 依此格式讀寫。**地基**：`build/t21/queue-format.md`（四欄佇列格式）——本檔不重複定義四欄語意，只定義 `apply-patch` 這個新動作型別的專屬部分。

## 0. 非真相源聲明（承接 T-21 §0，逐字適用）

Patch 型佇列項與其對應的 `.patch` 檔**都不是真相源、不參與任何 gate 判定**。真相源＝目標 repo 工作區當下的實際檔案內容（由 `git apply --check --reverse` 直接讀出，見 §4）。遺失佇列項或 patch 檔，只損失「尚未落地的待寫程式碼」，已落地的工作區內容不受影響；降級後果＝該筆須由站 4 重新產生程式碼與 patch。

## 1. 落地路徑設計：新增 `apply-patch` 動作型別，走 T-21 同一份四欄佇列（非獨立通道）

**決定**：`apply-patch` 是白名單新增的第六種 `action`，沿用 T-21 `queue-format.md` §2 的四欄骨架（`action`｜`target`｜`payload`｜`source`），存進**同一份** `queue.json`；不另開一份「patch 專用佇列檔」、不另立傳輸通道。

**理由**：
1. **Spec 原文已定方向**：§4.6「站 4 的程式產出以 patch 檔形式**進佇列**，由同一支本機腳本套用」——「進佇列」三字已排除獨立通道選項，本票只需決定 payload 怎麼裝，不是決定要不要進佇列。
2. **佇列既有機制全部可直接沿用，不必重造**：對帳出列（reconcile）、遺失降級、面板「待寫 N 筆」揭露（T-09）都是佇列層級的機制，`apply-patch` 項混在同一份佇列裡即可自動享有——若另開通道，這四樣都得為 patch 型再做一次。
3. **四欄語意本來就夠用**：`target` 從「repo＋issue」換成「repo＋worktree」、`payload` 從「label 陣列」換成「patch 檔參照」，欄位角色不變（決定套用方式／定位套用對象／欲達成的完整目標狀態／失敗回追依據），不需要改四欄骨架本身。

**與 T-21 佇列共存的實務安排**（誠實聲明，不是理想設計，是務實安排）：`apply-queue.ps1`（T-21 owns）與 `apply-patch.ps1`（本票）是**兩支腳本**，共讀同一份 `queue.json`，各自只處理自己認得的 `action`：
- `apply-queue.ps1` 的 `Test-ItemSchema` 白名單不含 `apply-patch`，遇到會判 `FAILED-SCHEMA` 並把該項**原樣留在佇列**（不會遺失、不會誤套）；但每次跑都會印一行噪音且 exit code 變 1。
- `apply-patch.ps1`（本票）反過來：只處理 `action == "apply-patch"` 的項目，其餘項目**原樣通過、不觸碰、不重排順序**地寫回佇列檔，留給 `apply-queue.ps1` 處理。
- **建議操作順序**（寫進兩腳本的 `.EXAMPLE` 與使用說明）：先跑 `apply-patch.ps1` 清掉 patch 型項目，再跑 `apply-queue.ps1` 處理其餘 metadata 型項目，可避免上述噪音。這不是強制順序（兩腳本互不依賴、順序反過來也不會壞資料），只是體驗較乾淨。
- **為何不回頭修改 `apply-queue.ps1` 把 `apply-patch` 加進它的白名單**：那會修改 T-21 owns 的檔案，違反本票 file ownership 邊界；且套用機制本質不同（T-21 全部走 GitHub REST API，本票全程操作本機工作區、完全不連 GitHub），合併進同一支腳本反而會讓兩種完全不同的失敗模式（HTTP 4xx／5xx vs. git exit code／hunk 衝突）糾纏在一支腳本的錯誤處理裡，這正是 T-22 ticket basis 欄位「與 T-21 分開才裝得進單一 context」的理由，延伸到腳本層級同樣成立。

## 2. 序列化格式：unified diff（`git diff` 輸出），套用走 `git apply`，🚫 不用 `git format-patch` + `git am`

**決定**：patch 檔內容＝ `git diff`（或等效的 unified diff）輸出，**不是** `git format-patch` 產生的 mbox 格式，套用一律用 `git apply`，**不是** `git am`。

**理由**（實測見 `t22-offline-test.ps1`／`t22-test.ps1`）：
1. **不可逆動作聲明已排除自動 commit**：T-22 票面「不可逆動作：無（套用至工作區，未 commit 前可還原；🚫 腳本不得自動 commit 或 push）」。`git am` 的定義就是「套用 patch 並建立 commit」，天生違反此條；`git apply` 純粹改動工作區檔案（可選擇性動 index，本票**不**加 `--index`），完全落在允許範圍內。
2. **sandbox 產出不必是乾淨的 commit**：站 4 ephemeral container 產出程式碼變更時未必已經 `git commit`（也不該要求它必須先建立一個帶正確 author 身分的 commit——container 內的 git identity 若貿然拿來當 commit author，會重蹈 §3.4／ADR-NP-009「actor 歸因不成立」的同型問題，只是這次是 commit author 而非 GitHub API actor）。unified diff 只描述「內容從 A 變成 B」，不帶任何身分／時間戳語意，天然迴避這個問題。
3. **獨立預期值來源可直接對應**：驗收條件「patch 檔本身宣告的目標內容」——`git apply --check --reverse` 直接把 patch 檔本身當作「工作區應該長什麼樣」的獨立宣告來源做比對（見 §4），不需要額外解析 commit message 或 author trailer。

## 3. `apply-patch` payload schema

```json
{
  "action": "apply-patch",
  "target": { "repo": "owner/repo", "worktree": "C:\\dev\\owner-repo" },
  "payload": {
    "patchFile": "patches/T-14-0001.patch",
    "sha256": "1c9d1b402e6db9d0b36ed77b8f80784abe565f372008e2feda6dc13e1043bb9c",
    "files": ["greeting.txt"]
  },
  "source": "T-14"
}
```

| 欄位 | 必填 | 說明 |
|---|---|---|
| `target.repo` | 是 | `<owner>/<repo>`，**僅供人讀與 best-effort 核對**（腳本會 `git -C <worktree> remote get-url origin` 比對，不含 ⇒ 只警示不擋下）；本型套用全程**不呼叫任何 GitHub API**，此欄不用於定位套用對象。 |
| `target.worktree` | 是 | 使用者本機該 repo 的 git 工作目錄**絕對路徑**。腳本以 `git -C <worktree> rev-parse --is-inside-work-tree` 驗證合法性；不存在或非 git 工作區 ⇒ `FAILED-WORKTREE`。 |
| `payload.patchFile` | 是 | **相對於佇列檔所在目錄**的路徑（比照 T-21 `queue.json` 與腳本同目錄慣例），指向外部 `.patch` 檔——**patch 內容不內嵌進 JSON**（理由見 §3a）。 |
| `payload.sha256` | 是 | `patchFile` 內容的 SHA-256（十六進位小寫）。套用前腳本重算比對，不符 ⇒ `FAILED-INTEGRITY`，防止佇列項與實際 patch 檔案不同步（例如檔案被後續產出覆寫、傳輸過程被截斷）。 |
| `payload.files` | 是 | patch 宣告觸及的檔案清單（人讀＋供報告具名；不參與套用邏輯本身，套用結果以 `git apply` 實際處理的檔案為準）。 |
| `source` | 是 | 來源票號（T-21 四欄語意不變）——同時是 §6「交付判定」查詢鍵。 |

### 3a. 為何 patch 內容走外部檔案參照，不內嵌進 JSON payload

- **人工可審**：程式碼是「受管轄的 deliverable」（§5.0），寫入前應可被人類直接開啟 `.patch` 檔審閱，內嵌成 JSON 轉義字串會讓 diff 內容無法直接用一般 diff viewer 開啟。
- **多檔案／大檔案不撐爆佇列檔**：`queue.json` 承載大量 metadata 型項目時應保持精簡易讀；patch 內容可能達數十 KB 甚至更大（尤其含二進位變更時，見 §5），外部檔案不影響 `queue.json` 本身的可讀性。
- **`git apply` 本來就吃檔案路徑或 stdin**：外部檔案讓套用腳本可以直接把路徑丟給 `git apply`，不需要先把 JSON 字串還原寫成暫存檔案再套用（少一層轉換，少一層可能出錯的編碼往返）。

## 4. 冪等與回驗：借用 `git apply --check --reverse` 做「讀現況比對」，不設動作指紋

承接 §4.6 硬規則「冪等（讀現況比對，不設動作指紋）」——本型的「現況」就是**工作區檔案的實際內容**，`git apply --check --reverse <patch>` 是拿來讀這個現況的工具，不是拿 patch 的 hash 當指紋做比對。

**已用沙盒真實 git 2.43 實測驗證下列全部語意**（證據見 `t22-offline-test.ps1` 與 `t22-test.ps1` 輸出）：

| 呼叫 | 語意 | 用途 |
|---|---|---|
| `git apply --check --reverse <patch>` 成功 | 若把 patch 反向套用會成功 ⇒ 工作區「現在」已經是 patch 描述的目標內容 | **冪等判準**：成功 ⇒ 已達成，`SKIPPED-ALREADY-APPLIED`，出列 |
| `git apply --check --reverse <patch>` 失敗（套用前的初始狀態） | 工作區尚未含有 patch 描述的變更 | 繼續往下走正向套用流程 |
| `git apply --check <patch>` 成功 | patch 可以乾淨套用到工作區目前狀態 | **套用前乾跑**：成功才允許真的寫 |
| `git apply --check <patch>` 失敗 | 工作區已被改動導致 hunk context 不符（或已套用過，但已被 §上一列排除） | `FAILED-CONFLICT`，🚫 不寫入，留在佇列並具名回報 |
| `git apply <patch>`（無 `--reject`／`--3way`／`--index`） | 真的套用；git 內建行為＝**整包成功或整包不動**，不會半套（已實測：多檔案 patch 其中一檔衝突時，另一檔案也不會被寫入，見 §7） | 通過乾跑後才執行 |
| 套用後再跑一次 `git apply --check --reverse <patch>` | **回驗**：成功 ⇒ 工作區內容確實等於 patch 宣告的目標內容 | 成功 ⇒ `APPLIED-VERIFIED`，出列；失敗 ⇒ `FAILED-VERIFY`，留在佇列（防禦性檢查，正常路徑理論上不會走到，因 `git apply` 本身已保證原子性） |

**套用前額外守門**（本型專屬，不是抄 T-21 的 description 長度守門）：
1. `payload.sha256` 與 `patchFile` 實際內容重算後不符 ⇒ `FAILED-INTEGRITY`，不送 `git apply`。
2. `target.worktree` 路徑不存在或非 git 工作區 ⇒ `FAILED-WORKTREE`。
3. `target.repo` 與 `git -C <worktree> remote get-url origin` 不含該 repo 名稱 ⇒ **僅警示**（best-effort，寫進 detail，不擋下套用）——避免真正的路徑打錯（例如套到別的 repo）被完全靜默放過，但不因為 `git remote` 讀不到（例如尚未設定 remote 的本機測試倉庫）就整個擋下。

## 5. 多檔案／二進位檔的邊界

- **多檔案**：一份 `.patch` 檔可含多檔案 diff，套用以**整份為單位**，對應驗收④「不得部分套用後宣稱成功」。git 預設（不加 `--reject`）就是「整包成功或整包不動」——已實測：三檔案 patch 中一檔衝突時，`git apply`（無 `--reject`）連未衝突的另一檔案也不會被寫入（`git status --porcelain` 全空）；只有刻意加 `--reject`（本票僅在 `-SkipDryRunCheck` 紅燈驗證路徑使用，正式流程禁用）才會出現「衝突檔案生成 `.rej`、未衝突檔案卻真的被改掉」的半套結果。
- **二進位檔**：`git diff --binary` 產生的 base64 編碼二進位 patch 段可被 `git apply --binary` 正確還原（已實測二進位 blob 逐位元組相符）。腳本呼叫 `git apply` 一律加 `--binary` 旗標（對純文字 diff 無副作用，向下相容）。
- **邊界聲明（YAGNI，誠實不過度設計）**：本票不對單一 patch 檔大小設強制上限。若 patch 內含大型二進位檔（編譯產物、模型權重等），建議站 4 executor 自律不把這類檔案塞進程式碼審查循環——這是產出紀律問題，不是本腳本要攔的邊界；若真的因檔案過大導致 `git apply` 逾時或記憶體異常，腳本具名回報 `FAILED-APPLY`（附 git 原始錯誤訊息），不靜默失敗、不裁剪錯誤內容。

## 6. 交付判定（驗收條件③：未套用前不得算交付）

`patch-common.ps1` 提供 `Test-PatchDelivered -Source <票號> -QueuePath <queue.json> -AppliedLogPath <applied-patches.log>`：

1. 掃 `queue.json`：若仍有 `action == "apply-patch" -and source == <票號>` 的項目 ⇒ **未交付**（該項目還沒出列，代表還沒套用成功）。
2. 若佇列裡已經找不到該 `source` 的 `apply-patch` 項目，再查 `applied-patches.log`（`apply-patch.ps1` 每次 `APPLIED-VERIFIED` 或 `SKIPPED-ALREADY-APPLIED` 都會 append 一行，格式見 `patch-common.ps1` 內 `Add-AppliedPatchLogEntry`）：找到該 `source` 的落地紀錄 ⇒ **已交付**。
3. 兩者皆無（佇列找不到、log 也沒有紀錄）⇒ **安全預設未交付**——這種情況代表「該票的 patch 從未進過本佇列」或「log 遺失」，寧可保守回報未交付，也不能把「查無證據」誤判成「已交付」（呼應 §5.0「親手產出的 deliverable 無效」的精神：沒有落地證據就不算數）。

🚫 **本函式不讀 executor 自陳的完成訊息**——executor 說「我做完了」不算交付判定輸入，交付判定只認佇列現況與 `applied-patches.log` 這兩個實際落地證據來源，這正是驗收條件③要防的「executor 自陳即被當成交付」。

**面板揭露延伸**：`apply-patch` 型佇列項一併計入 T-09「待寫 N 筆」（沿用 T-21 `queue-format.md` §6 精神，本票不重複實作面板邏輯，只確保 `queue.json` 內容對 T-09 而言是可被同一套讀取邏輯掃到的——`apply-patch` 項目依然是四欄 JSON 物件，落在同一個陣列裡）。

## 7. 衝突處理

**衝突＝ `git apply --check <patch>`（正向、已排除「已套用」情況後）失敗**。處理原則：

1. 🚫 **不自動裁決**——不猜測「應該用哪個版本」、不自動 3-way merge（不加 `--3way`）、不自動 `--reject` 留殘局。留給人工：使用者可自行選擇① 重新請站 4 針對目前工作區現況重新產生 patch，或② 自行以 `git apply --3way` 手動處理並自負沖突解決責任（腳本文件具名指出此選項存在，但**預設路徑絕不自動執行**）。
2. **具名回報**：`FAILED-CONFLICT` 的 detail 內含 `git apply --check` 的原始 stderr（逐檔逐 hunk 訊息），保留 `payload.files` 供人工比對是哪些檔案受影響。
3. **CRLF／行尾差異的診斷提示（不自動套用）**：若正向乾跑失敗，腳本會**另外**唯讀地跑一次 `git apply --check --ignore-whitespace --binary <patch>`（**只是診斷，不寫入任何東西**）；若這次成功，detail 會加註「⚠️ 可能為行尾（CRLF/LF）差異導致，而非實質內容衝突」（見 §8 完整說明與為何不直接採用 `--ignore-whitespace` 當正式套用手段）。

## 8. CRLF／行尾問題：正面處理（使用者具名要求，已實測驗證）

**問題**：沙盒（Linux，本票驗證環境＝Ubuntu + git 2.43.0）產生的 patch 天然是 LF 換行；使用者環境是 Windows，工作區檔案的實際位元組換行可能是 CRLF（依該 repo／該使用者機器的 `core.autocrlf` 設定而定）。若處理不當，`git apply` 會因為 context 行的 `\r` 不吻合而報 `patch does not apply`，或更糟——若用 `--ignore-whitespace` 硬套，會產生**同一檔案內行尾混用**的髒污（已實測重現，見下）。

**已實測驗證的三種情況**（沙盒 git 2.43.0，真實指令，非臆測）：

1. **不覆寫 `core.autocrlf`，讓 git 用該 repo 既有設定**（`core.autocrlf=true`，Windows git-for-windows 安裝時的常見建議值）：LF 版 patch 套用到 CRLF 工作區檔案 ⇒ **成功**，套用後檔案維持一致 CRLF（git 內部自動用 CRLF 版本做比對、用 CRLF 版本寫回，不混用）。
2. **不覆寫 `core.autocrlf`，該 repo 完全未設定（預設 `false`）且檔案在磁碟上確實是 CRLF**（例如經非 git 管道產生的檔案）：LF 版 patch 套用 ⇒ **正確地失敗**（`patch does not apply`）——這是**安全的失敗**，不是 bug；此時是真正的位元組不吻合，強行套用才是危險的（見下一點）。
3. **用 `--ignore-whitespace` 硬套過這種失敗**：套用**成功**，但結果檔案變成「被改動的那幾行是 LF、其餘既有行仍是 CRLF」的混用髒檔（已實測 `od -c` 逐位元組確認）。

**決定與理由**：
- `apply-patch.ps1` 呼叫 `git apply` 時**一律不覆寫 `core.autocrlf`／`core.eol`**——讓 git 使用目標 repo 當下已生效的設定（本機 repo 設定或使用者全域設定的合併結果）。理由：那正是使用者機器上「這個 repo 平常怎麼 checkout／commit」所依循的同一套規則，讓 patch 套用結果與該 repo 平常的行尾慣例保持一致（情況 1 已證實這樣做最理想）。
- **🚫 正式套用路徑絕對不用 `--ignore-whitespace`**——它會製造「同檔案內行尾混用」的髒污（情況 3 已實測重現），這比「誠實地回報衝突、留給人工」更糟：髒污是靜默的，使用者可能根本不會注意到，事後 diff review／CI 行尾檢查才會爆炸，而且爆炸點離真正原因（本次套用）已經很遠。
- 情況 2（真正的位元組不吻合）就讓它誠實地變成 `FAILED-CONFLICT`——這不是本票要修的 bug，是正確的保守行為；§7 已加上「診斷提示」（唯讀跑一次 `--ignore-whitespace --check` 純粹判斷「是不是行尾問題」，把訊息寫進報告，**不會自動套用**），讓使用者能快速判斷這筆衝突是不是行尾造成、決定要不要人工介入。
- **產生端建議**（供 T-24／站 4 dispatch 日後接上時參考，不在本票程式碼範圍內強制）：沙盒產生 patch 時建議固定 `git -c core.autocrlf=false diff --no-color --binary`，確保 patch 內容一律是 LF，不受沙盒任何全域設定汙染——這是本票 fixtures 與測試腳本產生 patch 時實際採用的作法（見 `t22-offline-test.ps1`）。

## 9. `-SkipDryRunCheck`（紅燈驗證專用實驗開關，⚠️ 正式流程禁用）

比照 T-21 `apply-queue.ps1` 的 `-SkipIdempotencyCheck` 先例（rework 後才符合 Spec §6「紅是斷言失敗的紅」的教訓，T-22 直接在初版就採用同一手法，不重蹈覆轍）：

- 開啟後，`apply-patch.ps1` **跳過套用前乾跑**（§4 的 `git apply --check`），且改用 `git apply --binary --reject <patch>`（而非安全預設的無 `--reject` 呼叫）直接嘗試套用。
- **後果（已實測）**：對一個必然衝突的 patch，`--reject` 會讓「不衝突的檔案被真的改掉、衝突的檔案產生 `.rej` 殘留檔」——這正是「半套」的具體樣貌。腳本套用後會做 `Test-WorktreeHasRejectArtifacts` 與 `Test-WorktreeHasConflictMarkers` 兩項檢查，若命中則標記 `FAILED-PARTIAL-APPLY` 並**仍然**留在佇列（不因為「已經寫了一部分」就出列）——但工作區木已成舟，殘留的部分套用內容**不會被自動復原**（🚫 腳本不做自動 `git checkout --` 復原，那已經超出「套用」腳本的職責，且貿然復原可能誤刪使用者自己另外做的修改；只具名回報，復原由人工執行）。
- **🚫 正式流程與一般手動套用絕對不得開啟**。用途僅限 `t22-test.ps1` 的紅燈段落，用來讓「工作區不得留下衝突標記／不得半套」這條斷言**真的失敗一次**，取得符合 Spec §6 定義的斷言失敗紅；隨後以正常模式（不開此開關）重跑同一斷言取得綠。

## 10. 產生權

| 動作類型 | 唯一產生者 |
|---|---|
| `apply-patch` | 站 4 executor（`fullstack-developer`／`ak-cook`／`ak-test`）——依 §4.6「佇列項的產生權＝該動作原本的唯一寫入者」，站 4 的程式產出唯一來源就是該 executor；`/station-gate`／`/station-run` 皆不得產生本型項目（它們的產生權僅限 metadata 型，見 T-21 `queue-format.md` §5）。 |

本票不強制實作產生權檢查點（比照 T-21：規格具名，動態強制點留給 T-24 `/station-run` loop 落地時接上）。
