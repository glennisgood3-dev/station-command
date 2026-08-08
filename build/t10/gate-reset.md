# gate 復位模式（Spec §3.4）— 設計文件

🔴 **deferred-to-CI**（ADR-NP-009／驗收 #7）：本節機器歸因判準與復位模式為 **CI 階段規格**。手動階段不生效（執行身分即使用者本人，actor 無從區分人手與 gate 改動）。**本檔與 `gate-reset.ps1` 已完整實作程式路徑並以離線 mock 測試（`t10-offline-test.ps1`）涵蓋兩分支**——動態驗收（真實 CI bot 身分 ＋ 真實 timeline）延後，不是「未實作」。

## 觸發時機

依 §3.4：`/station-gate` 於**每次執行**先跑「歸因判準」（`gate-check.ps1` 的 `all.attribution` 全站列項）；不合法時：
- board 紅燈標「站別來源不明」（面板顯示，屬 T-16，本票不驗）。
- `/station-run` 拒絕選件（屬 T-12，本票不驗）。
- **`/station-gate` 要求先跑 `gate-reset.ps1`**（本票範圍）。

## 判準（`gate-check.ps1` 的 `Get-CrossStationChecklist`）

讀 primary anchor 的 issue **timeline**（原生記錄，非自建簿記），取當前 station label 最後一次 `labeled` 事件的 **actor 與時間**。`actor ∈ gate 執行身分集合`（`-GateIdentityLogins`，CI 階段＝`github-actions[bot]`）⇒ 合法；否則人手直接改。

**手動階段**：呼叫 `gate-check.ps1` 不帶 `-GateIdentityLogins`（預設空陣列）⇒ 此項降級為「規範層＋人工複查」，`Blocking=$false`、`Satisfied=$null`，**不算入 AND 判定**，僅具名回報 `ObservedActorLogin` 供人工複查（比照 T-08 `init-path.md` 判準⑤既有先例）。

## 復位模式兩分支（`gate-reset.ps1` 的 `Invoke-GateReset`）

**復位只讀 timeline、不採信當前 label 值**（§3.4），故不循環。

### 分支①：沿 timeline 回溯，找最後一次合法 labeled 事件所設站別

`Find-LastLegalStationEvent`：篩出 timeline 中所有 `event == 'labeled'` 且 `label.name` 符合 `^sc:station-` 的事件；timeline API 本身即依時間正序回傳，故由**尾端往前**找第一筆 `actor.login ∈ GateIdentityLogins` 者，即「時間上最後一次合法事件」。

命中 ⇒ 回退至該站別，**具名回報回退理由與事件時間**（actor、created_at）；產生**單一次**完整 label 集合的 `set-labels` 佇列項（保留所有非站別 label，只替換站別 label）。

### 分支②：整條 timeline 無任何合法事件

⇒ 落 `sc:awaiting-user`（移除所有 `sc:station-*`，加入 `sc:awaiting-user`，其餘 label 不變）、停止推進、交使用者裁示。同樣是**單一次**完整集合 `set-labels` 佇列項。

## 原子性（§3.4「站別推進＝單一動作」，本設計亦適用於復位）

兩分支皆只產生**一筆** `set-labels` 佇列項，`payload.labels` 是套用後應有的**完整**集合（不是要加/要減的差量），對應 `apply-queue.ps1` 的 `PUT .../labels` 整批覆蓋語意——不存在「先 remove 舊站別再 add 新站別」的兩步中間態。

## 已知限制（誠實聲明，非規避）

- `-GateIdentityLogins` 未提供時，`gate-reset.ps1` CLI 主流程直接具名拒絕執行（exit code 3），不假裝完成復位；此為手動階段的正確行為，不是 bug。
- timeline API 分頁上限 `-MaxPages 5`（500 筆事件）；逾此上限的極端情境本票不處理（無已知案例，YAGNI）。
- 復位不驗證「回退後的站別是否仍與現有票集一致」（§3.2 的 work-station-consistency）——復位是「回到 timeline 曾經合法設定過的狀態」，後續是否需要再依票集重算，交回下一次 `gate-check.ps1` 的 `all.work-station` 全站列處理，兩者職責分離。

## 對應驗收（Spec 驗收 #7，本票標 deferred-to-CI）

| 分支 | 驗收方式 | 本票狀態 |
|---|---|---|
| 手動竄改 label 後跑 gate ⇒ 判定歸因不合法、拒絕推進 | 動態：需真實 CI bot 身分 vs 人手改動對照 | deferred-to-CI；離線 mock 已測 `all.attribution` 兩種身分集合（空／CI）分支 |
| 復位分支①：回退至最後合法事件站別 | 動態：需真實 timeline | deferred-to-CI；離線 mock 已測 `Find-LastLegalStationEvent` 命中與時間排序 |
| 復位分支②：無合法事件 ⇒ `sc:awaiting-user` | 動態：需真實 timeline（清空合法事件） | deferred-to-CI；離線 mock 已測全為人手 actor 情境 |
