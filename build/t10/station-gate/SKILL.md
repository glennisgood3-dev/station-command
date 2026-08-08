---
name: station-gate
description: 跑當前站出口條件（§6）逐條核對，全過才寫下一站狀態 label，未過具名缺項並拒絕推進；唯一寫狀態 label 者；含初始化路徑（T-08）與站別推進、寫後回驗、歸因復位（T-10）。當使用者要求「跑 gate」「站別檢查」「/station-gate」「能不能推進下一站」「復位」等語意時觸發。
user-invocable: true
---

# 動作白名單（Spec §2，逐字承接）

`/station-gate`：跑當前站出口條件（§6），逐條 ✓／✗；全過才寫下一站 label，未過具名缺項並拒絕推進；**唯一寫狀態 label 者**；站 5 通過後關票、工作全完成後收尾（§3.2）；含初始化路徑（§6.1）與復位模式（§3.4）。

允許動作：讀 GitHub＋timeline｜讀全參與 repo 的 DECISIONS.md｜**讀 plugin repo 的 DECISIONS.md**（SC#6 解除條目、gate 執行身分宣告）｜**寫狀態 label**｜**關／開 issue、關 milestone**｜寫人讀留言｜dispatch 審查／verifier／`docs-manager`／`git-manager` sub-agent｜呼叫 board 無對帳模式。

🚫 本 skill 不做：任何非狀態類的 GitHub 讀寫（票 body 的 executor／basis 欄位、assignee——皆屬 `/station-run`）；豁免掃描的深度邏輯（DECISIONS.md 過期判定，屬 T-19）；面板顯示（屬 T-16）；站 4／5 的專屬驗收邏輯（紅綠證據判斷、verifier 實測、雙審、修復復驗，屬 T-14／T-15a）。

**寫狀態 label 的指示**：本 skill 是四份 SKILL.md 中唯一得寫入狀態 label（`sc:station-1`…`sc:station-5`、`sc:station-done`、`sc:legacy`、`sc:red-proven`、`sc:blocked`、`sc:gate-fail`、`sc:awaiting-user`）者，依 SC#7 規範層判準：其餘三份（board／run／intake）明文禁止寫狀態 label。站別推進須以**單一次「設定完整 label 集合」**API 呼叫完成（§3.4），寫後須直讀 anchor 回驗（§4.4）。

# No-Hands 邊界（§5.0）

本 skill 的動作（讀 GitHub／timeline／DECISIONS.md、逐條判 ✓／✗、寫狀態 label、開關 issue／milestone、寫佇列項、dispatch）皆由既有資料機械性推導而得、無創作裁量，屬編排動作，不受 No-Hands 管轄。**例外**：§6 checklist 中屬「內容裁量項」者（名詞表完備性、spec 可驗證性、缺口審報告品質等，見下方 checklist 分類）不是「既有資料機械性推導」，本 skill 不越權自行判斷——這些項目的判定結果來自 Commander 已完成的「讀→驗」（可能含 dispatch `kongming`／`code-reviewer` 等 sub-agent 產出審查報告），gate 只負責核對「裁定是否已提供」並記錄，未提供 ⇒ fail-closed（§5.0「記」的邊界＝共識文件與裁示紀錄，不含替使用者下判斷）。

# 手動階段的寫入路徑（依 ADR-NP-009／Spec §4.6，🔴 核心約束，承接 T-08 既有設計）

本 skill 於執行期**不直接寫 GitHub**（`SC-DEC-BOT-001` 已實測：MCP 寫入端點 403、Bash 對 GitHub 被 proxy 攔截；讀取端點正常）。所有寫入一律先產生 T-21 格式佇列項（`../t21/queue-format.md`，四欄 `action`／`target`／`payload`／`source`，**執行前必讀，不得憑印象**），追加進使用者本機佇列檔，明確告知使用者需執行 `../t21/apply-queue.ps1` 落地。**產生權**（`../t21/enqueue-guard.md`）：`set-labels`／`close-issue` 兩型恆為 gate 專屬。

---

# 段落一：初始化路徑（§6.1，來自 T-08，本檔整合引用，非重寫）

**本段的完整規格與程式碼皆由 T-08 交付**，位於 `../../t08/station-gate/init-path.md`（規格）與 `../../t08/intake-native.ps1`（Stage C 段落，含五條判準函式 `Test-GateInitCriteria`）。由 `/station-intake` native 步驟 4 呼叫，逐條核對①milestone 已建②primary anchor 已宣告③work ID 全艦隊唯一④anchor 無既有站別 label（有 ⇒ 轉本檔段落三復位模式）⑤gate 執行身分具名回報（依 ADR-NP-009 不作 fail 條件）。全過 ⇒ 產生 `sc:station-1` 的單一 `set-labels` 佇列項。**本票（T-10）不重複實作，也不修改 T-08 交付的檔案**（file ownership 邊界）；此處僅作為完整 SKILL.md 敘事的銜接段落，供使用者從單一文件理解 gate 全貌。

---

# 段落二：站別推進、寫後回驗（§6／§3.4／§4.4，T-10 本票交付）

## 執行時機

`/station-intake` 初始化完成、或 `/station-run` 完成一輪派工／收件後、或使用者直接要求「跑 gate」時觸發。

## 步驟 1：判定站序合法性與出口條件（`../gate-check.ps1`）

讀 primary anchor 現有站別 label（`Get-CurrentStation`）→ 驗證請求的目標站是否為**緊鄰下一站**（`Test-StationOrderValid`，§3.4「站序不可跳」）：
- **不合法**（含 1→3、2→4、3→5 等跳站）⇒ **立即拒絕**，且對每個「被跳過站」各跑一次其 §6 checklist，具名列出各自未滿足的出口條件（不是只說「跳站了」，而是連帶列出中間站本來就沒過的理由，貼近使用者對「為何不能跳」的直覺）。
- **合法**（緊鄰下一站）⇒ 對「現站」（即將離開的站）跑 §6 該站 checklist（`Invoke-StationExitChecklist`）：
  - **機械可判定項**（如站 3 的「§3.5 全八項欄位是否出現在票 body」）⇒ gate 直接讀 GitHub 判定。
  - **內容裁量項**（如站 1 名詞表完備性、站 2 spec 可驗證性）⇒ 讀取呼叫端傳入的 `-ChecklistOverrides`（Commander 已完成讀驗或 dispatch 審查後的裁定結果）；**未提供 ⇒ fail-closed**，不得默認通過。
  - **站 4／5 深度驗收邏輯**（紅綠證據、verifier、雙審、修復復驗）⇒ 🔒 本票 scope 鎖不實作，一律 fail-closed 並具名「屬 T-14／T-15a 範圍」，避免使用者誤以為本票已涵蓋。
- 全站列（§6「全站（每次 gate 均查）」，每次都查）：「work 站別＝未關閉票的最小站」（機械可判定，計入 AND）｜「全參與 repo DECISIONS.md 無過期豁免」（**N/A，屬 T-19，不計入 AND，明確標註不代為判定**）｜「站別歸因合法」「gate 執行身分」（依 ADR-NP-009，手動階段不算入 AND，僅具名回報供人工複查；deferred-to-CI，見 `../gate-reset.md`）。

全過 ⇒ 進步驟 2；未過 ⇒ 具名回報所有缺項（`NamedGaps`），**不產生任何佇列項**，拒絕推進。

## 步驟 2：產生單一次「設定完整 label 集合」佇列項（`../gate-advance.ps1`，產生模式）

讀 anchor 現有完整 label 集合，移除所有 `sc:station-*`，加入目標站別，組成**完整**集合，產生**恰好一筆** `set-labels` 佇列項（🚫 絕不拆 remove＋add 兩步，避免 anchor 出現無站別或雙站別的中間態）。告知使用者執行 `apply-queue.ps1` 落地。

## 步驟 3：寫後回驗（`../gate-advance.ps1 -VerifyAfterApply`）

使用者落地後，以 issues API **直讀** anchor（不經 search，§4.4）：比對現有站別 label 是否恰為「單一個目標站」（同時驗證原子性——無殘留舊站別、無雙站別）。不符 ⇒ 等待數秒後**重試一次**；仍不符 ⇒ **判寫入失敗、具名回報，不宣稱推進成功**（不論 `apply-queue-report.txt` 內容為何，此處以本次直讀為準）。

---

# 段落三：歸因復位模式（§3.4，T-10 本票交付，🔴 deferred-to-CI）

**手動階段不生效**（ADR-NP-009：執行身分即使用者本人，機器無從區分人手改動與 gate 改動）。**程式路徑與離線測試已完整涵蓋**，動態驗收（需真實 CI bot 身分與真實 timeline）延後至 CI 階段。完整設計見 `../gate-reset.md`；程式見 `../gate-reset.ps1`。

- 觸發：`gate-check.ps1` 的全站列「站別歸因合法」項判不合法時（CI 階段，`-GateIdentityLogins` 提供時才會真的判定）。
- 分支①：沿 timeline 回溯，找最後一次合法 `labeled` 事件所設站別 ⇒ 回退至該站，具名回報回退理由與事件時間。
- 分支②：整條 timeline 無任何合法事件 ⇒ 落 `sc:awaiting-user`、停止推進、交使用者裁示。
- 兩分支皆產生**單一次**完整 label 集合的佇列項（同段落二的原子性原則）。
- **手動階段呼叫本模式**：`gate-reset.ps1` 在未提供 `-GateIdentityLogins` 時直接具名拒絕執行（exit 3），不假裝完成復位。

---

# 已知限制與 scope 邊界（誠實聲明）

- 站 3 的「§3.5 全八項欄位」檢查是**結構性存在檢查**（欄位關鍵字是否出現在票 body），非內容品質判斷；更深的欄位品質邏輯（`[INVALID]` 判定細節）屬 T-13。
- 站 4／5 checklist 一律 fail-closed 具名「屬 T-14／T-15a 範圍」，本票不實作深度驗收邏輯（🔒 scope 鎖）。
- DECISIONS.md 過期豁免掃描不在本票範圍（T-19），gate-check 明確標「N/A（T-19 範圍）」，不偽裝成已檢查。
- 歸因與復位動態驗收 deferred-to-CI（見上）。
