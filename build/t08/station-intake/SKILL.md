---
name: station-intake
description: 進線入口，native 模式建 milestone 與 primary anchor issue 並產「定站站 1」結論；legacy 模式非本票範圍。當使用者要求「新建工作」「/station-intake」「開一個新 work」等語意時觸發（native 模式）。
user-invocable: true
---

# 動作白名單（Spec §2，逐字承接）

`/station-intake`：**native**：建 milestone ＋ primary anchor issue，產「定站站 1」結論。兩模式皆不自己落狀態 label，改呼叫 gate 初始化路徑。

允許動作：讀 GitHub｜**建 milestone**｜**建 issue 並附類型 label `sc:work`**｜dispatch auditor（legacy 專用，本票不實作）｜呼叫 gate 初始化路徑。

🚫 不寫任何狀態 label（`sc:station-*`／`sc:legacy`／`sc:red-proven`／`sc:blocked`／`sc:gate-fail`／`sc:awaiting-user`）——狀態 label 的唯一寫入者是 `/station-gate`（SC#7、Spec §3.3）。

🔒 **本檔案範圍鎖（T-08）**：只實作 native 模式。legacy 模式（fresh-context auditor、定站退回、補件清單、豁免草案）不在本票範圍，留待後續票。

# No-Hands 邊界（§5.0）

本 skill 的動作（讀 GitHub、建 milestone／issue、附類型 label、呼叫 gate 初始化路徑）皆由既有資料機械性推導而得、無創作裁量，屬編排動作，不受 No-Hands 管轄。work 描述文字若由使用者口述給定即直接採用；若需要「撰寫」工作描述（非使用者原話的摘要／潤飾），該段文字屬 deliverable，不得由 Commander 代筆，須向使用者確認原話或請使用者提供。

# 手動階段的寫入路徑（依 ADR-NP-009 ／ Spec §4.6，🔴 核心約束）

**已實測結論（`SC-DEC-BOT-001`）：Cowork 對 GitHub 寫不進去**——MCP 寫入端點回 403 `Resource not accessible by integration`，Bash 對 GitHub 的請求被 session proxy 攔截；**讀取端點正常**。因此本 skill 於執行期：

- **讀**一律用 GithubMCP 的讀工具（`search_issues`／`list_issues`／`get_issue`／`list_milestones`／`get_me` 等），**不呼叫任何 GithubMCP 寫工具**（`create_issue`／`create_milestone`／`update_issue` 等一律禁用，呼叫了也會 403，且違反產生權不變式——見下）。
- **寫**一律改為「**產生佇列項並寫入使用者本機的佇列檔**」——這是一次普通的本機檔案寫入（用 Write／Edit 工具編輯 `queue.json`），不是 GitHub API 呼叫，因此不受 403 影響。佇列檔格式**唯一正典**為 `../t21/queue-format.md`（**執行前必讀，不得憑印象**，四欄恰好 `action`／`target`／`payload`／`source`）。
- 佇列項寫好後，**明確告知使用者**：需執行本機 `apply-queue.ps1`（T-21 交付，位於 `../t21/apply-queue.ps1`）才會真正落地到 GitHub；並提示下一步（重跑本 skill 以繼續下一階段，或直接呼叫 gate 初始化路徑）。

**產生權（`../t21/enqueue-guard.md`）**：本 skill 只能產生 `create-issue`（primary anchor）與 `create-milestone` 兩型佇列項；`set-labels` 型（含 `sc:station-1`）**一律屬 gate 產生權**，本 skill 不得產生，只能呼叫 gate 初始化路徑（見下）由 gate 自行產生。

# 執行步驟（native 模式）

## 步驟 0：收集輸入

向使用者收集三項（可一次問齊，也可分次確認）：

1. **work ID**：格式 `W-<slug>`（小寫英數字與連字號，全艦隊唯一，依 `../t07/templates.md` §1 慣例）。
2. **primary repo**：`<owner>/<repo>`，anchor 將建於此。
3. **參與 repo 清單**：`<owner>/<repo>` 陣列，**須含 primary repo 自身**（Spec §3.1：「參與 repo 全集」含 primary repo）。若使用者漏列 primary repo，自動補入並告知。

可選：work 描述（使用者原話，供 anchor body 人讀段落）。

## 步驟 1：work ID 唯一性初步檢查（讀，非強制卡關——最終判準在 gate 初始化路徑）

用 `search_issues` 在每個參與 repo 搜尋 `label:sc:work`，檢查 body 是否已有相同 `work-id: <輸入的 ID>` 那一行。若找到 ⇒ 提前告知使用者「work ID 已存在於 <repo>#<issue>，是否要換一個 ID 或改用既有 anchor 繼續」，**不強行擋下**（最終仍由 gate 初始化路徑判準③做出具名判定）。

## 步驟 2：產生 primary anchor 的 `create-issue` 佇列項

先用 `search_issues`／`list_issues`（`label:sc:work`）確認 primary repo 內**尚無**帶相同 work-id 的 anchor（避免重複產生佇列項）。若已存在 ⇒ 跳過本步驟，直接進步驟 4 使用既有 anchor 編號。

若不存在，組出 body（逐字依 `../t07/templates.md` §2 格式，機讀段在前）：

```
work-id: <work-id>
primary-repo: <owner>/<repo>
participating-repos:
- <owner>/<repo>          # 含 primary repo 自身
- <owner>/<repo-2>

<使用者提供的工作描述原話，若有>
```

寫入佇列項（依 `../t21/queue-format.md` §3.4）：

```json
{
  "action": "create-issue",
  "target": { "repo": "<owner>/<primary-repo>" },
  "payload": {
    "title": "<work-id> · primary anchor",
    "body": "<上述 body 全文>",
    "labels": ["sc:work"],
    "milestone": null
  },
  "source": "<work-id>"
}
```

追加進使用者本機佇列檔（若檔案已存在，讀出既有陣列後追加，維持 JSON 陣列型態；若不存在，建立僅含本筆的陣列）。

**告知使用者**：「已產生 primary anchor 的建立佇列項，請執行 `apply-queue.ps1` 落地；落地後回報 anchor 的 issue 編號（或重新觸發本 skill，我會自動讀到）以便繼續建 milestone。」

## 步驟 3：（anchor 落地後）產生各參與 repo 的 `create-milestone` 佇列項

用 `list_milestones` 或 `search_issues` 確認每個參與 repo 是否已有標題等於 work ID 的 milestone；沒有的逐一產生佇列項（依 `../t07/templates.md` §3 格式）：

```json
{
  "action": "create-milestone",
  "target": { "repo": "<owner>/<repo>" },
  "payload": {
    "title": "<work-id>",
    "description": "work-id: <work-id> | primary-anchor: <owner>/<primary-repo>#<anchor-issue-number>"
  },
  "source": "<work-id>"
}
```

⚠️ **送出前自查 description 長度 ≤100 字元**（`apply-queue.ps1` 會擋，但提早發現可省一輪來回；今日實測 114 字元回 422）。逾長 ⇒ 告知使用者需縮短 work ID slug。

追加進佇列檔，告知使用者執行 `apply-queue.ps1` 落地。

## 步驟 4：（milestone 全部落地後）呼叫 gate 初始化路徑

milestone 與 anchor 皆確認存在於 GitHub 後，**呼叫 `/station-gate` 的初始化路徑**（見 `../station-gate/init-path.md`）。本 skill 到此為止不再自行判定或寫任何狀態 label——五條判準的核對與 `sc:station-1` 佇列項的產生，完全是 gate 的職責與產生權。

## 步驟 5：回報「定站站 1」結論

gate 初始化路徑回報通過並產生 `set-labels` 佇列項後，向使用者輸出：work ID、anchor 位置（repo#issue）、參與 repo 清單、milestone 清單、gate 五條判準逐條 ✓（含判準⑤的身分具名回報字串）、以及「請執行 apply-queue.ps1 落地 sc:station-1，落地後即完成定站站 1」。

若 gate 初始化路徑未過，逐字轉述 gate 具名的缺項，不代 gate 下判斷、不自行重試繞過。
