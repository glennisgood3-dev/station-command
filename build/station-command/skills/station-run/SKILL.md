---
name: station-run
description: 驗站別歸因合法後選出下一個可動作項，依路由表定 executor 與 basis 並寫入票 body 的 executor 欄位，經使用者確認後 dispatch 執行。當使用者要求「派工」「下一步做什麼」「/station-run」「開工」等語意時觸發。
user-invocable: true
---

# 動作白名單（§2）

`/station-run`：驗站別歸因合法（§3.4）→ 選出下一個可動作項（無 blocker、depends_on 已滿足）→ 依路由表定 executor＋basis 並**寫入票 body 的 executor 欄位** → 經使用者確認後 dispatch；**指派 assignee 為執行身分帳號，作為二元開工訊號**；dispatch 失敗 ⇒ **立即移除該 assignee** 並具名回報，不留下「已開工但沒人在做」的假象；結束時呼叫面板無對帳刷新。

允許動作：讀 GitHub｜**寫／移除 assignee**｜**寫票 body 的 executor／basis 欄位**｜寫人讀留言｜dispatch sub-agent｜呼叫 board 無對帳模式。

🚫 不寫任何 label、不開關 issue。

**明文禁令**：本 skill 禁止寫入或移除任何 GitHub label，包含狀態 label（`sc:station-*`／`sc:legacy`／`sc:red-proven`／`sc:blocked`／`sc:gate-fail`／`sc:awaiting-user`）與類型 label；亦禁止開啟或關閉任何 issue／milestone。狀態 label 的唯一寫入者是 `/station-gate`（SC#7）。

# No-Hands 邊界

依 §5.0：本 skill 的動作（讀 GitHub、驗歸因、選件、依路由表定 executor、寫 assignee／body 欄位、dispatch）皆由既有資料機械性推導而得、無創作裁量，屬編排動作，不受 No-Hands 管轄；票內容、程式、測試等 deliverable 一律由 dispatch 出去的 executor 產出，主 session 不親手撰寫。

# 佔位行為

目前回覆固定訊息：「station-run 骨架就緒，行為待 T-08+ 實作（見 station-command#N）」
