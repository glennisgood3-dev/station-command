---
name: station-intake
description: 進線入口，native 模式建 milestone 與 primary anchor issue 並產「定站站 1」結論；legacy 模式共用同一套建立步驟並起 fresh-context auditor 定站退回、產補件清單與豁免草案。兩模式皆呼叫 gate 初始化路徑落首個 label。當使用者要求「新建工作」「收編既有專案」「/station-intake」「開一個新 work」等語意時觸發。
user-invocable: true
---

# 動作白名單（§2）

`/station-intake`：**native**：建 milestone ＋ primary anchor issue，產「定站站 1」結論。**legacy**：**共用同一套建立步驟**，再起 fresh-context auditor 定站退回、產補件清單與豁免草案。兩模式皆不自己落狀態 label，改呼叫 gate 初始化路徑。

允許動作：讀 GitHub｜**建 milestone**｜**建 issue 並附類型 label `sc:work`**｜dispatch auditor｜呼叫 gate 初始化路徑。

🚫 不寫任何狀態 label。

**明文禁令**：本 skill 禁止自行寫入任何狀態 label（`sc:station-*`／`sc:legacy`／`sc:red-proven`／`sc:blocked`／`sc:gate-fail`／`sc:awaiting-user`），僅能建立時寫入不可變的類型 label `sc:work`；首個狀態 label 一律改呼叫 `/station-gate` 的初始化路徑落下。狀態 label 的唯一寫入者是 `/station-gate`（SC#7）。

# No-Hands 邊界

依 §5.0：本 skill 的動作（讀 GitHub、建 milestone／issue、附類型 label、呼叫 gate 初始化路徑）皆由既有資料機械性推導而得、無創作裁量，屬編排動作，不受 No-Hands 管轄；auditor 定站報告、補件清單分析等 deliverable 一律 dispatch 給 fresh-context auditor 產出，主 session 不親手撰寫。

# 佔位行為

目前回覆固定訊息：「station-intake 骨架就緒，行為待 T-08+ 實作（見 station-command#N）」
