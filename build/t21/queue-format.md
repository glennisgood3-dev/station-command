# T-21 · 待寫佇列檔格式規格

依 `Spec_station-command_v1.8.md` §4.6（待寫佇列）定案。本檔是佇列檔的**唯一格式正典**；`apply-queue.ps1`／`reconcile-queue.ps1` 依此格式讀寫。

## 0. 非真相源聲明（§4.6，逐字承接）

佇列檔**不是真相源、不參與任何 gate 判定**。它的載體＝使用者本機的具名檔案，由套用腳本消費。

- **遺失後果＝降級，不是錯誤**：佇列檔遺失，只損失「尚未落地的待寫動作」；GitHub 上已存在的狀態完全不受影響。降級後果是「該批動作須由 loop 重新產生」，**不會造成站別或票狀態錯誤**——因為真相源永遠是 GitHub 現有的 label／issue／milestone 狀態，佇列只是「還沒寫到 GitHub 的動作清單」，不是「GitHub 現在是什麼狀態」的記錄。
- 佇列檔存在與否、內容是否完整，皆**不影響**任何 `/station-gate` 出口條件判定；gate 一律直接讀 GitHub。

## 1. 檔案位置慣例

佇列檔是**使用者本機的具名檔**，不進版控（不隨 plugin repo 走）。

- 預設路徑：與套用腳本同目錄的 `queue.json`（即 `apply-queue.ps1` 所在資料夾下的 `queue.json`），比照 T-07 `labels.json` 與腳本同目錄的慣例。
- 可由 `-QueuePath` 參數覆寫（例如使用者想把佇列檔與 PAT 放同一個掛載點：`G:\default mount\station-command-queue.json`）。
- 檔案格式：UTF-8（可含 BOM，讀取端兩者皆容忍）、JSON，最外層為**陣列**，陣列元素即下節四欄物件。陣列順序＝檔內順序，**不另設時間欄**（§4.6 原文）。
- 佇列檔不存在＝合法狀態（尚無待寫動作，或使用者已清空／遺失），不是錯誤（見 §4 冪等節）。

## 2. 佇列項四欄格式

依 §4.6：「佇列項欄位（四欄，各有消費者）：動作類型（決定套用方式）｜目標（repo ＋ issue／milestone 識別）｜payload（欲寫入的完整 label 集合／欄位值／開關狀態／留言內文）｜來源票號或 work ID（套用失敗時的回報與人工追查依據）。」

JSON 物件的四個鍵，**恰好四欄，不多不少**：

| 鍵 | 對應四欄 | 型別 | 消費者 |
|---|---|---|---|
| `action` | 動作類型 | string（見 §3 白名單） | `apply-queue.ps1`：決定用哪個 GitHub API 端點與比對邏輯；`reconcile-queue.ps1`：決定用哪個「現況比對」邏輯 |
| `target` | 目標 | object（見各型 schema） | 同上兩腳本：定位 API 呼叫對象（repo＋issue 號／milestone 號） |
| `payload` | payload | object（見各型 schema） | 同上兩腳本：欲達成的**完整**目標狀態，用於冪等比對與套用內容 |
| `source` | 來源票號或 work ID | string | 人工追查與失敗回報：套用失敗或回驗不符時，具名回報的依據；面板／loop 摘要亦可引用 |

範例骨架：

```json
[
  {
    "action": "set-labels",
    "target": { "repo": "owner/repo", "issue": 42 },
    "payload": { "labels": ["sc:ticket", "sc:red-proven"] },
    "source": "T-14"
  }
]
```

## 3. 支援的動作類型與 payload schema

**白名單（至少支援下列四型，順序無意義）**：`set-labels`｜`create-issue`｜`close-issue`｜`comment`。另擴充 `create-milestone`（intake 建 milestone 時所需，理由見 §5 產生權表）。

### 3.1 `set-labels`

用途：對單一 issue（票或 anchor）設定**完整**狀態 label 集合，對應 §3.4「站別推進＝單一動作」不變式——**一次 PUT 完整集合，不得拆 remove＋add 兩步**。

```json
{
  "action": "set-labels",
  "target": { "repo": "owner/repo", "issue": 42 },
  "payload": { "labels": ["sc:ticket", "sc:station-4"] },
  "source": "T-14"
}
```

- `target.repo`：`<owner>/<repo>`（必填）。
- `target.issue`：issue 編號（必填，整數）。
- `payload.labels`：**該 issue 套用後應有的完整 label 名稱陣列**（不是「要加的」或「要減的」差量）。套用端以此陣列整批 `PUT .../issues/{n}/labels` 覆蓋，確保原子性。
- 冪等比對：讀現有 `.labels[].name`，排序後與 `payload.labels` 排序後比對，集合相等 ⇒ 已達成，跳過。
- ⚠️ **不含 label 定義變更**（color／description）——那是 T-07 `labels.json` 的職責（一次性套 scheme），本型只設定「哪些既有 label 掛在這個 issue 上」。若日後需要透過佇列調整既有 label 的 description／color（例如發現某 label description 逾 100 字元需修正），須另立 `update-label-def` 型並比照 §4 的長度守門邏輯——**本票暫不開放該型**（YAGNI；目前無該類佇列項的產生來源）。

### 3.2 `close-issue`（含開／關）

```json
{
  "action": "close-issue",
  "target": { "repo": "owner/repo", "issue": 42 },
  "payload": { "state": "closed", "state_reason": "completed" },
  "source": "T-14"
}
```

- `payload.state`：`"closed"` 或 `"open"`（兩者皆用本型，欄位語意即「issue 開關狀態」）。
- `payload.state_reason`：僅 `state="closed"` 時建議填，`"completed"` 或 `"not_planned"`（對齊 GitHub Issues API 需求「關閉須設 state_reason」，見 MCP 工具指引）。
- 冪等比對：讀現有 `.state`（與 `.state_reason`，若 payload 有提供則一併比對）；相符 ⇒ 跳過。

### 3.3 `comment`

```json
{
  "action": "comment",
  "target": { "repo": "owner/repo", "issue": 42 },
  "payload": { "body": "loop 批次摘要：本輪派了 T-14、T-15a；gate 判定：T-14 pass、T-15a rework" },
  "source": "T-24"
}
```

- `payload.body`：留言全文（人讀留言，§3.4「留言不參與任何判定」——本型只負責把文字寫上去，不影響任何 gate 邏輯）。
- 冪等比對：**留言沒有天然的「目前狀態」可比對**（不像 label／開關那樣是單值），故以「是否已存在完全相同 `body` 文字的既有留言」作為「已達成」判準——讀現有留言列表，逐則比對 `body` 全文字串相等；找到相同者 ⇒ 已達成，跳過（避免重複貼同一則摘要）。**限制（誠實聲明）**：若使用者事後手動編輯過該留言文字，本比對會判為「未達成」而重貼一則——這是留言型冪等的已知邊界，非 bug；佇列非真相源，重貼留言不影響任何站別判定。

### 3.4 `create-issue`

僅**產生權為 intake** 的動作（§5）；用於 legacy 收編或站 3 拆票等需要開票的情境經佇列落地時使用（正常站 3 拆票走 dispatch 直接建票，此型主要服務**手動階段 intake 建 primary anchor 或 legacy 建票時 API 寫不進去**的情況）。

```json
{
  "action": "create-issue",
  "target": { "repo": "owner/repo" },
  "payload": {
    "title": "W-demo-work · primary anchor",
    "body": "work-id: W-demo-work\nprimary-repo: owner/repo\nparticipating-repos:\n- owner/repo\n",
    "labels": ["sc:work"],
    "milestone": null
  },
  "source": "W-demo-work"
}
```

- `target.repo`：必填，無 `issue` 鍵（尚未存在）。
- `payload.title`／`payload.body`：必填。`payload.labels`：建立時即寫入的型別 label（`sc:work`／`sc:ticket`）。`payload.milestone`：里程碑編號或 `null`。
- 冪等比對（**best-effort，誠實聲明其限制**）：以 `search_issues`／`list_issues` 在目標 repo 內比對是否已存在**標題完全相同**的 issue；找到 ⇒ 視為已達成、跳過。此判準無法防止「標題相同但內容不同」的誤判，**佇列非真相源**，誤判的後果最壞是漏建一張標題重複的票，可由使用者事後人工複查、不影響已存在票的站別真相。

### 3.5 `create-milestone`（擴充型，服務 intake 建 milestone）

```json
{
  "action": "create-milestone",
  "target": { "repo": "owner/repo" },
  "payload": { "title": "W-demo-work", "description": "work-id: W-demo-work | primary-anchor: owner/repo#1" },
  "source": "W-demo-work"
}
```

- 冪等比對：以 `title` 精確比對現有 milestone 清單；找到 ⇒ 跳過。

## 4. 冪等與回驗（§4.6 硬規則，逐字承接）

> 「冪等（讀現況比對，不設動作指紋）：套用前先讀目標現況，已達成 payload 所述狀態者跳過 ⇒ 同一佇列重跑兩次結果相同。套用後回驗：逐筆以 issues API 直讀目標，比對完整 label 集合與開關狀態；不符者留在佇列並具名回報，🚫 不得標記為已套用。」

- **不設動作指紋**：不對佇列項算 hash／簽章當作「是否已套用過」的記號。唯一判準＝**目標在 GitHub 上現在的實際狀態**是否已等於 `payload` 所述狀態。
- 每筆套用流程：① 讀現況 → ② 已達成 ⇒ 標記 SKIPPED、出列；未達成 ⇒ 套用 → ③ 回驗（再讀一次，issues API 直讀，非 search）→ ④ 相符 ⇒ 標記 APPLIED、出列；不符 ⇒ 標記 FAILED-VERIFY，**留在佇列**，具名回報（source＋target＋差異）。
- **GitHub 限制守門**：套用前逐筆檢查 payload 中任何 `description` 欄位長度 ≤100 字元（今日實測 114 字元回 422）；超過 ⇒ 具名擋下（不送出 API 呼叫），標記 FAILED-VALIDATION，留在佇列並回報「description 長度 N 超過 100 字元上限，來源 <source>」。

## 5. 產生權對照（摘要，詳見 `enqueue-guard.md`）

| 動作類型 | 唯一產生者 |
|---|---|
| `set-labels`、`close-issue`（label／開關 issue 類） | `/station-gate` |
| `create-issue`、`create-milestone` | `/station-intake` |
| `comment` | 依原動作歸屬（`/station-run` 產派工／收件／loop 摘要類留言；`/station-gate` 產 gate 判定類留言） |

## 5a. `-SkipIdempotencyCheck`（rework：紅燈驗證專用實驗開關，⚠️ 正式流程禁用）

站 4 verifier 判定 T-21 初版紅燈為「載入失敗型」不符 Spec §6「紅是斷言失敗的紅」，rework 因此為 `apply-queue.ps1` 加一個**僅供紅燈驗證使用**的開關：

- 開啟後，套用前的「讀現況比對」（本檔 §4）**整段跳過**，每筆一律直接呼叫寫入 API，即使目標早已達成 payload 所述狀態。
- **用途僅限**：`t21-dynamic-test.ps1` 的 A 段，用來讓「同一佇列連續套用兩次 ⇒ 留言數不得增加」這條斷言**真的失敗一次**，取得符合 Spec §6 定義的斷言失敗紅；隨後以正常模式（不開此開關）重跑同一斷言取得綠，兩段皆存真實輸出。
- **🚫 正式流程與一般手動套用絕對不得開啟**：開啟後 `comment` 型會真的重複貼留言（POST 沒有天然去重）；`set-labels`／`close-issue` 因寫入本身是覆蓋式操作（PUT 整包／PATCH 設值）不會產生資料錯誤，但仍違反 §4.6「套用前先讀現況比對」硬規則，且會讓每次套用都對 GitHub 發出不必要的寫入 API 呼叫。
- 開啟時腳本會在主控台印出 `Write-Warning` 三行式樣的醒目提示，且 `apply-queue-report.txt` 逐筆 detail 中會標注「已略過套用前現況比對」。

## 6. 面板揭露（§4.6，供 T-09 消費，本票不實作）

佇列非空時字卡顯示「待寫 N 筆」；佇列非空時「在跑數量」與「停滯票數」加註「寫入斷點期間不可信」；佇列檔不存在時顯示「待寫佇列不存在」而非 0（不得把「查無佇列」誤顯示成「零筆待寫」）。本節欄位由 T-09 讀取消費，T-21 只負責讓佇列檔的**存在性與內容**可被穩定讀取。
