# T-08 · 進線：intake native ＋ gate 初始化路徑〔首個垂直切片｜🔒 不得增肥〕

## 設計選擇：`intake-native.ps1` 是「佇列產生器」，不是直接寫 GitHub 的端到端腳本

ticket 給了兩個選項，本票選**第二種**（佇列產生器 ＋ 沿用 `../t21/apply-queue.ps1` 落地），理由：

1. **Cowork 手動階段寫不進 GitHub 是實測事實**（`SC-DEC-BOT-001`：MCP 寫入端點 403、Bash 對 GitHub 被 proxy 攔截，讀取正常）。`/station-intake`、`/station-gate` 這兩份 SKILL.md 描述的是 Claude 在**真實 Cowork session** 裡的行為——那個環境本來就不能直接寫 GitHub，所以 SKILL.md 的「正確行為」本來就只能是「產生佇列項」，不可能是「直接呼叫 GitHub 寫入 API」。若 `intake-native.ps1` 設計成直接寫 GitHub，它就會是一支**與 SKILL.md 實際行為脫節**的平行工具，用來 demo 沒問題，但不是「native 模式的真正實作」。
2. **T-21 已經把寫入／冪等／回驗／`description` 長度守門這一整套邏輯做完並測過**（`apply-queue.ps1` ＋ `queue-common.ps1`）。若 `intake-native.ps1` 自己再寫一份直接呼叫 GitHub 寫入 API 的邏輯，就是重複造輪子，且兩份邏輯遲早會分岔（例如 100 字元守門只在一邊做、冪等比對規則兩邊不一致）。違反 DRY。
3. **產生權不變式**（`../t21/enqueue-guard.md`）已經明訂：`create-issue`／`create-milestone` 屬 intake，`set-labels` 屬 gate。把 `intake-native.ps1` 設計成「組出正確的佇列項」，剛好就是把這條不變式直接體現在程式碼結構裡（函式命名與段落標題都標「intake 產生權」／「gate 產生權」）。

**因此 `intake-native.ps1` 的角色是**：讀 GitHub 現況（讀端點正常，不受限）→ 組出格式正確的 T-21 佇列項 → 寫進使用者本機的 `queue.json`（純檔案 I/O，不是 GitHub API 呼叫）→ 提示使用者跑 `apply-queue.ps1` 落地 → 重跑本腳本繼續下一階段。**可重複執行、每次只推進尚未完成的那一段**（Stage A 建 anchor → Stage B 建 milestone → Stage C 判五條準則並落 `sc:station-1` → 冪等終態）。

## 目錄結構

```
build/t08/
  station-intake/SKILL.md      native 模式完整可執行指示（給 Claude 在 Cowork session 內遵循）
  station-gate/init-path.md    §6.1 初始化路徑段（只做這段，站別推進留給 T-10）
  intake-native.ps1            佇列產生器（本機可跑，讀 GitHub＋寫佇列檔＋五條判準）
  t08-test.ps1                 動態紅→綠測試（需真實 PAT，本沙盒無法實跑）
  t08-offline-test.ps1         離線 mock 測試（沙盒可跑，33 項斷言全綠）
  t08-quality-gates.txt        出貨前三道關卡證據
```

## 使用者要跑的指令（本機 Windows PowerShell 5.1）

```powershell
cd <plugin repo>\build\t08

# 建一個新工作（單一 repo 最簡情境；多參與 repo 就把它們都列進 -ParticipatingRepos）
.\intake-native.ps1 -WorkId W-demo-work -PrimaryRepo <owner>/<repo> -ParticipatingRepos <owner>/<repo>
# 依提示執行：
..\t21\apply-queue.ps1 -QueuePath .\queue.json
# 重跑 intake-native.ps1（同一行指令）推進到下一階段，重複「跑腳本→落地→重跑」直到看到「已完成初始化」
```

離線測試（沙盒／CI 皆可跑，不連網）：

```
/opt/pwsh/pwsh -NoProfile -File t08-offline-test.ps1
```

動態測試（需本機真實 PAT，會在指定 repo 建立並清理測試用 issue／milestone）：

```powershell
.\t08-test.ps1 -Owner <owner> -Repo <repo>
```

## 紅燈設計（斷言失敗型，非檔案缺失型）

依 ticket 建議：核心斷言＝「判準③（work ID 全艦隊唯一）偵測到重複 work-id 時，gate 初始化整體必須拒絕」。

- **紅**：用 `-BypassUniquenessGuardForRedTest`（比照 T-21 `-SkipIdempotencyCheck` 先例）對一組**真實構造的重複 work-id fixture**（兩張真實 anchor issue，body 皆宣告同一個 work-id）呼叫 `Test-GateInitCriteria` ⇒ 斷言「`OverallPass` 必須為 `false`」**真的會失敗**（因為 bypass 讓判準③被強制視為通過）——這是斷言失敗的紅，不是檔案不存在或載入失敗的紅。
- **綠**：不開 bypass、對同一組 fixture 重跑 ⇒ 判準③正確偵測到重複、`OverallPass=false` ⇒ 斷言通過。

兩段輸出見 `t08-red-green.txt`（使用者本機執行 `t08-test.ps1` 後產生）。

## 已知限制（誠實聲明，非本票規避）

- 判準③「全艦隊唯一」在手動階段是 **best-effort**：掃描範圍＝呼叫時明確給定的 `-FleetRepos`（未指定則降級為本次參與 repo 集合），不是「GitHub 上所有存取得到的 repo」。與 T-21 `create-issue` 冪等比對的「best-effort，僅掃最近 100 筆」屬同一類已知限制。
- legacy 模式、站別推進（T-10）、面板揭露（T-09）不在本票範圍，`init-path.md` 與 `intake-native.ps1` 皆只做到「判準④偵測到既有站別 label ⇒ 具名停手，指向 T-10 復位模式」為止，不代 T-10 實作復位。
