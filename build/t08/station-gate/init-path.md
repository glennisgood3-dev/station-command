# `/station-gate` 初始化路徑段（Spec §6.1，僅本段——站別推進留待 T-10）

依 `Spec_station-command_v1.8.md` §6.1 逐字承接，本檔是 `/station-gate` 完整 SKILL.md 的**其中一段**（初始化路徑），由 `/station-intake` native 步驟 4 呼叫。**站別推進、寫後回驗、歸因復位**三段屬 T-10 範圍，不在本檔。

## 動作白名單（本段適用範圍）

允許動作：讀 GitHub（含 issue／milestone／label／`GET /user`）｜**寫狀態 label**（僅本段限定為落首個 `sc:station-1`）｜寫人讀留言（本段可省略，改由回報字串承載）。

🚫 本段不做：站別推進判斷、寫後回驗（issues API 直讀比對）、歸因復位模式——皆屬 T-10。

**產生權**：本段是**唯一**能產生 `set-labels` 型佇列項的角色（依 `../t21/enqueue-guard.md`）；`/station-intake` 呼叫本段，但本段自己判定、自己產生佇列項，不把判定結果交還給 intake 代為產生。

## No-Hands 邊界

五條判準的核對（讀 GitHub、比對機讀欄位、身分實查）皆是既有資料機械性推導、無創作裁量，屬編排動作，不受 No-Hands 管轄。

## 執行步驟：逐條核對五條判準

輸入：work ID、primary repo、參與 repo 清單（由呼叫方 intake 傳入，或本段自行從 anchor body 讀出核對）。

### 判準①：milestone 已建且 description 含 work ID 與 primary anchor 指標

對每個參與 repo，用 `list_milestones` 找標題等於 work ID 的 milestone；讀其 `description` 首行，須逐字等於：

```
work-id: <work-id> | primary-anchor: <owner>/<primary-repo>#<anchor-issue-number>
```

任一參與 repo 缺 milestone 或首行格式不符 ⇒ 判準①不過，具名列出缺項 repo 與實際首行內容。

### 判準②：primary anchor 存在、帶 `sc:work`、body 已宣告 primary repo 與參與 repo 全集

讀 primary anchor issue：① label 含 `sc:work`；② body 首段可解析出 `work-id:`／`primary-repo:`／`participating-repos:` 三個鍵值，且 `work-id` 等於輸入值、`primary-repo` 等於輸入 primary repo、`participating-repos` 清單（去除順序後）與輸入的參與 repo 清單完全相等。任一不符 ⇒ 具名回報實際讀到的值 vs 期望值。

### 判準③：work ID 全艦隊唯一（聚合查無同 ID）

用 `search_issues`（`q=label:sc:work ... in:body "work-id: <work-id>"`）掃過**已知的 fleet repo 清單**（至少涵蓋本次 primary repo ＋ 參與 repo；若使用者另有指定更廣的艦隊範圍，一併掃描），排除本次正在初始化的這張 anchor 本身；找到**任何**其他帶相同 `work-id:` 行的 `sc:work` issue ⇒ 判準③不過，具名列出衝突的 repo＋issue 編號。

⚠️ **誠實聲明範圍限制**：本判準的「全艦隊」在手動階段是 best-effort，掃描範圍＝呼叫方明確給定的 repo 清單，不等於「GitHub 上所有存取得到的 repo」；若日後艦隊擴大，須在呼叫時擴大掃描清單。

### 判準④：anchor 上無任何既有 station label

讀 anchor 現有 label 集合，檢查是否含任何 `sc:station-*`。有 ⇒ 判準④不過，且**本段不處理**——具名回報「anchor 已有站別 label `<清單>`，須轉復位模式（Spec §3.4），復位模式屬 T-10 範圍，本次初始化到此停止」。無 ⇒ 判準④過。

### 判準⑤：gate 執行身分檢查與具名回報（依 ADR-NP-009，**不作 fail 條件**）

用 `get_me`（或等效讀身分端點）實查當前 identity，寫入初始化報告：「gate 執行身分實查：actor login=`<login>`」。

- 若身分即使用者本人（手動階段常態，已由 `SC-DEC-BOT-001` 實測確認 Cowork 手動階段無法取得獨立 bot 身分）⇒ 報告**必須**含固定字串：

  > **手動階段：無機器歸因，依 ADR-NP-009**

- CI 階段身分應為 `github-actions[bot]`，屆時 §3.4 全套機器歸因生效（本段手動階段不判斷此分支）。
- **無論身分為何，判準⑤都不影響整體通過與否**——只影響報告內容，不參與 ①②③④ 的 AND 判定。

## 通過與否的判定

**整體通過 ⇒ ①②③④ 全部✓**（判準⑤永遠不算入 AND 判定，只負責報告）。

### 全過：產生 `sc:station-1` 的 `set-labels` 佇列項

讀 anchor **現有完整 label 集合**（此刻應僅有 `sc:work`），加入 `sc:station-1`，組成**完整**目標集合（依 Spec §3.4「站別推進＝單一次設定完整 label 集合」不變式，即使初始化階段還沒有「移除舊 label」的問題，也要遵守「一次寫完整集合」的形式，供 T-10 沿用同一支 `apply-queue.ps1` 邏輯）：

```json
{
  "action": "set-labels",
  "target": { "repo": "<owner>/<primary-repo>", "issue": <anchor-issue-number> },
  "payload": { "labels": ["sc:work", "sc:station-1"] },
  "source": "<work-id>"
}
```

追加進佇列檔，回報使用者需執行 `apply-queue.ps1` 落地。

### 任一條不過：不落任何 label，具名缺項

依上方各判準段落的具名回報格式，逐條輸出 ✓／✗ 與細節；**不產生任何佇列項**；不重試、不繞過。

## 初始化報告固定結構（供 intake 步驟 5 轉述）

```
判準①：✓/✗ — <細節>
判準②：✓/✗ — <細節>
判準③：✓/✗ — <細節>
判準④：✓/✗ — <細節>
判準⑤（不作 fail 條件）：gate 執行身分實查：actor login=<login>。手動階段：無機器歸因，依 ADR-NP-009
整體：PASS/FAIL
```
