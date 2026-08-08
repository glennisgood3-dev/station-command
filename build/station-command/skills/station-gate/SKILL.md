---
name: station-gate
description: 跑當前站出口條件（§6）逐條核對，全過才寫下一站狀態 label，未過具名缺項並拒絕推進；唯一寫狀態 label 者；站 5 通過後關票、工作全完成後收尾；含初始化路徑與復位模式。當使用者要求「跑 gate」「站別檢查」「/station-gate」「能不能推進下一站」等語意時觸發。
user-invocable: true
---

# 動作白名單（§2）

`/station-gate`：跑當前站出口條件（§6），逐條 ✓／✗；全過才寫下一站 label，未過具名缺項並拒絕推進；**唯一寫狀態 label 者**；站 5 通過後關票、工作全完成後收尾（§3.2）；含初始化路徑（§6.1）與復位模式（§3.4）。

允許動作：讀 GitHub＋timeline｜讀全參與 repo 的 DECISIONS.md｜**讀 plugin repo 的 DECISIONS.md**（SC#6 解除條目、gate 執行身分宣告）｜**寫狀態 label**｜**關／開 issue、關 milestone**｜寫人讀留言｜dispatch 審查／verifier／`docs-manager`／`git-manager` sub-agent｜呼叫 board 無對帳模式。

**寫狀態 label 的指示**：本 skill 是四份 SKILL.md 中唯一得寫入狀態 label（`sc:station-1`…`sc:station-5`、`sc:station-done`、`sc:legacy`、`sc:red-proven`、`sc:blocked`、`sc:gate-fail`、`sc:awaiting-user`）者，依 SC#7 規範層判準：其餘三份（board／run／intake）明文禁止寫狀態 label。站別推進須以單一次「設定完整 label 集合」API 呼叫完成（§3.4），寫後須直讀 anchor 回驗（§4.4）。

# No-Hands 邊界

依 §5.0：本 skill 的動作（讀 GitHub／timeline／DECISIONS.md、逐條判 ✓／✗、寫狀態 label、開關 issue／milestone、dispatch）皆由既有資料機械性推導而得、無創作裁量，屬編排動作，不受 No-Hands 管轄；審查報告、auditor 報告等 deliverable 一律 dispatch 給 sub-agent 產出，gate 本身不撰寫審查判斷內容。

# 佔位行為

目前回覆固定訊息：「station-gate 骨架就緒，行為待 T-08+ 實作（見 station-command#N）」
