---
name: station-board
description: 跨 repo 聚合五站生產線的工作進度、建立或就地更新常駐面板 artifact、輸出文字摘要；完整模式並起 project-manager 對帳。當使用者要求「看面板」「查進度」「/station-board」「工作現況」等語意時觸發。
user-invocable: true
---

# 動作白名單（§2）

`/station-board`：跨 repo 聚合（按 work ID）、建立／就地更新面板 artifact、輸出文字摘要；完整模式並起 `project-manager` 對帳。**唯一寫面板的實作點**（無對帳模式供 run／gate 呼叫，§4.5）。

允許動作：讀 GitHub（search／issues／timeline／issue body 欄位）｜讀本機 `plans/`｜**dispatch `project-manager`（僅完整模式對帳）**｜寫面板 artifact｜文字輸出。

🚫 不寫 GitHub 任何欄位。

**明文禁令**：本 skill 全面禁止寫入任何 GitHub 欄位，包含但不限於狀態 label（`sc:station-*`／`sc:legacy`／`sc:red-proven`／`sc:blocked`／`sc:gate-fail`／`sc:awaiting-user`）、assignee、issue body、milestone。狀態 label 的唯一寫入者是 `/station-gate`（SC#7）。本 skill 亦不得開關 issue 或 milestone。

# No-Hands 邊界

依 §5.0：本 skill 的動作（讀 GitHub、聚合、機械性 render 面板、文字輸出）皆由既有資料機械性推導而得、無創作裁量，屬編排動作，不受 No-Hands 管轄；若面板日後加入由 AI 撰寫的摘要／建議文字，該部分即為 deliverable，一律 dispatch，不得由主 session 親手產出。

# 佔位行為

目前回覆固定訊息：「station-board 骨架就緒，行為待 T-08+ 實作（見 station-command#N）」
