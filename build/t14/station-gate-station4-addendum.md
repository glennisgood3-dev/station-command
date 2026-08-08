# T-14 · `station-gate` 站 4 分支增補（掛在既有哪支：`../t10/station-gate/SKILL.md`）

依 file ownership 邊界，**本票不修改** `build/t10/station-gate/SKILL.md` 或 `build/t10/gate-check.ps1`。本檔只是敘事銜接文件，說明 T-14 交付的 `station4-check.ps1` 如何與 T-10 既有的 gate 骨架接合，比照 T-10 `gate-reset.md`／T-12 `run-queue-ext.md` 的既有先例（獨立文件補位，不動地基檔案）。

## 接合點：T-10 `gate-check.ps1` 的 `4.deferred` 項

T-10 `gate-check.ps1` 的 `Get-StationChecklistDefinition -Station 'sc:station-4'` 目前回傳單一項目：

```
Id = '4.deferred'; Text = '每張票紅→綠兩段證據、verifier≠executor 實測一致（🔒 深度驗收邏輯屬 T-14 範圍，本票不實作，fail-closed）'; Type = 'RequiresInput'
```

該項屬 `RequiresInput` 型，T-10 的設計本就是「由呼叫端（Commander）透過 `-ChecklistOverrides` 傳入裁定結果，未提供即 fail-closed」（`gate-check.ps1` 內 `Invoke-StationExitChecklist` 的既有分支邏輯，T-14 不改動、原樣沿用）。

**T-14 交付的正是這個裁定的真正產生者**：Commander 對每一張站 4 票各自執行 `station4-check.ps1`（Check 模式），全過 ⇒ 該票的三項查核（① 紅燈型態、③ verifier≠executor、④ 預期值出處）皆已由程式驗證，Commander 才可在呼叫 T-10 `gate-check.ps1`／`gate-advance.ps1` 時對 `4.deferred` 傳入：

```json
{ "4.deferred": { "Satisfied": true, "Detail": "T-14 station4-check.ps1 對票 <repo>#<issue> 三項查核全過，見 station4-check-report.txt" } }
```

若任一張站 4 票的 `station4-check.ps1` 未過，Commander **不得**對該 work 的 `4.deferred` 傳入 `Satisfied=true`（工作級站別推進以「未關閉票的最小站」判定，§3.2；單張票未過 `sc:red-proven` 即該票仍停留站 4，anchor 亦隨之維持站 4，不因其他票已過而誤推進）。

## 兩層寫入分工（皆走 `set-labels`，皆不直接呼叫寫入 API）

| 動作 | 負責檔案 | 目標 | label |
|---|---|---|---|
| anchor 站別推進（sc:station-4 → sc:station-5） | `../t10/gate-advance.ps1`（本票不改） | primary anchor issue | `sc:station-*`（互斥，單一） |
| 票級紅綠證明 | `station4-check.ps1`（本票） | **票本身**（非 anchor） | `sc:red-proven`（加項，不與其他 label 互斥，§3.3） |

`sc:red-proven` **僅票**（Spec §3.3），與 anchor 的站別 label 是兩張不同 issue 上的兩件事，寫入時機也不同——`station4-check.ps1` 對單一票通過即可產生該票的 `sc:red-proven` 佇列項，不需等所有票皆過才動作；anchor 的站別推進則要等「未關閉票的最小站」條件滿足（即全部票皆已 `sc:red-proven` 或已關閉）才由 `gate-advance.ps1` 觸發，此判定邏輯已在 T-10 `Test-WorkStationConsistency` 內，T-14 不重複實作。

## `set-labels` 佇列項共用同一份 `../t21/apply-queue.ps1`

`sc:red-proven` 的落標沿用 T-21 原五型之一 `set-labels`（見 `../t21/queue-format.md` §3.1），**不需要新增動作型別**——與 T-10 的站別推進、T-12 的產出方式完全相同，故 `station4-check.ps1` 產生的佇列項可與 T-10／T-12 產生的佇列項混在同一份 `queue.json` 內，一起交給 `../t21/apply-queue.ps1` 落地，不需比照 T-12／T-22 另立套用腳本。

## verifier ≠ executor 的雙重滿足（ticket 面已具名）

`tickets-draft.md` T-14 的 `executor` 欄為 `fullstack-developer`，`verifier` 欄為 `tester`——本票自身的驗收流程即滿足 Spec §5.2「verifier ≠ executor 且非 Commander」規則，此為 ticket 面既有具名，`station4-check.ps1` 的 `Test-VerifierIndependent` 函式是把這條規則落成程式碼、對**任意**站 4 交件通用查核，不只是自況。
