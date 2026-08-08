# T-15a · `station-gate` 站 5 分支增補（掛在既有哪支：`../t10/station-gate/SKILL.md`）

依 file ownership 邊界，**本票不修改** `build/t10/station-gate/SKILL.md` 或 `build/t10/gate-check.ps1`。本檔只是敘事銜接文件，說明 T-15a 交付的 `station5-check.ps1`／`station5-dispatch-prep.ps1` 如何與 T-10 既有的 gate 骨架接合，比照 T-10 `gate-reset.md`／T-12 `run-queue-ext.md`／T-14 `station-gate-station4-addendum.md` 的既有先例（獨立文件補位，不動地基檔案）。

## 接合點：T-10 `gate-check.ps1` 的 `5.deferred` 項

T-10 `gate-check.ps1` 的 `Get-StationChecklistDefinition -Station 'sc:station-5'` 目前回傳單一項目：

```
Id = '5.deferred'; Text = '兩軸雙審、修復復驗、關票（🔒 深度驗收邏輯屬 T-15a 範圍，本票不實作，fail-closed）'; Type = 'RequiresInput'
```

該項屬 `RequiresInput` 型，T-10 的設計本就是「由呼叫端（Commander）透過 `-ChecklistOverrides` 傳入裁定結果，未提供即 fail-closed」，T-15a 不改動、原樣沿用。

**T-15a 交付的正是這個裁定的真正產生者**：Commander 對每一張站 5 票各自執行 `station5-check.ps1`（Check 模式），全過 ⇒ 該票的十項查核（①a 兩軸輸入分離、①b 規範版本具名、報告不合併、修法證據/裁決紀錄、③ verifier 獨立、② 修復復驗、⑤ SC#6 隔離標註、⑥ 收尾摘要）皆已由程式驗證，Commander 才可在呼叫 T-10 `gate-check.ps1`／`gate-advance.ps1` 時對 `5.deferred` 傳入：

```json
{ "5.deferred": { "Satisfied": true, "Detail": "T-15a station5-check.ps1 對票 <repo>#<issue> 十項查核全過，見 station5-check-report.txt；票本身已由 close-issue 佇列項關閉（非 gate-advance 推進 anchor 站別）" } }
```

若任一張站 5 票的 `station5-check.ps1` 未過，Commander **不得**對該 work 的 `5.deferred` 傳入 `Satisfied=true`（工作級站別推進以「未關閉票的最小站」判定，§3.2；單張票未過即該票仍停留站 5，見 T-10 `Test-WorkStationConsistency`——票有 `sc:red-proven` 且 open ⇒ 計為站 5，本票通過後票被**關閉**，不再計入 open 票，該票即從最小站計算中移除，與其他仍 open 的站 4／5 票分別判定）。

## 兩層寫入分工（皆走既有 T-21 動作型別，皆不直接呼叫寫入 API）

| 動作 | 負責檔案 | 目標 | 佇列動作型別 |
|---|---|---|---|
| anchor 站別推進（含降回站 4 需要重派、或升 `sc:station-done`） | `../t10/gate-advance.ps1`（本票不改）／`T-15b`（完成態收尾，本票不做） | primary anchor issue | `set-labels` |
| 站 5 票級關票 | `station5-check.ps1`（本票） | **票本身**（非 anchor） | `close-issue`（沿用 T-21 原五型，🚫 不新增動作型別） |

站 5 的關票是**票級**動作（Spec §5.2「結案後由 gate 關閉該票」），與 anchor 的站別推進是兩件不同 issue 上的兩件事，寫入時機也不同——`station5-check.ps1` 對單一票通過即可產生該票的 `close-issue` 佇列項，不需等整個 work 的所有票皆過。該 work 全票關閉後的收尾（`sc:station-done`、關 anchor、關 milestone）屬 T-15b 範圍，本票不實作、不重複。

## `close-issue` 佇列項共用同一份 `../t21/apply-queue.ps1`

站 5 關票沿用 T-21 原五型之一 `close-issue`（見 `../t21/queue-format.md` §3.2），payload 固定 `{ "state": "closed", "state_reason": "completed" }`——**不需要新增動作型別**，`station5-check.ps1` 產生的佇列項可與 T-10／T-12／T-14 產生的佇列項混在同一份 `queue.json` 內，一起交給 `../t21/apply-queue.ps1` 落地，不需比照 T-12／T-22 另立套用腳本。

## verifier ≠ executor 且非 Commander（Spec §5.2 hard rule，非僅 ticket 面具名）

與 T-14 的做法一致：`Test-Station5VerifierIndependent` 把這條規則落成程式碼、對**任意**站 5 交件通用查核，涵蓋 executor-is-verifier 與 verifier=Commander 兩種違規情境（`tickets-draft.md` T-15a 的 `executor` 欄為 `fullstack-developer`，本票自身流程另有其他角色把關，不依賴自況滿足）。

## 與 T-14（站 4）的分工邊界

`station5-check.ps1` **不重跑站 4 的紅綠證據判斷**（那是 T-14 `station4-check.ps1` 的職責，其產物 `sc:red-proven` 是站 5 開始審查的前提）；`station5-check.ps1` 的 `remediation`（修復復驗）針對的是**站 5 審查過程中**為清除 finding 而產生的修復 commit，與站 4 的原始紅→綠證據是不同階段的兩件事，不重複判定。
