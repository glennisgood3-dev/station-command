# T-10 · gate 推進、寫後回驗與歸因復位〔🔒 不得增肥〕

依 `Spec_station-command_v1.8.md` §3.4／§4.4／§6／SC#2 定案。重用地基：`../t21/`（四欄佇列 schema、`apply-queue.ps1`、`queue-common.ps1`）、`../t08/`（gate 初始化路徑 `init-path.md`、`intake-native.ps1` 的佇列產生器模式）。

## 目錄結構

```
build/t10/
  station-gate/SKILL.md   完整版 gate skill：段落一引用 T-08 初始化路徑（不重寫）、
                           段落二站別推進＋寫後回驗（本票）、段落三歸因復位（本票，deferred-to-CI）
  gate-check.ps1           出口條件檢查器：站序合法性＋§6 該站 checklist，跨站請求必拒
  gate-advance.ps1         推進器：產生單一 set-labels 佇列項；-VerifyAfterApply 模式做寫後回驗（重試一次）
  gate-reset.md            復位模式設計文件（deferred-to-CI，程式路徑已就緒）
  gate-reset.ps1           復位模式實作：兩分支（回退合法站別／落 sc:awaiting-user）
  t10-test.ps1              動態紅→綠測試（需真實 PAT，本沙盒無法實跑）
  t10-offline-test.ps1      離線 mock 測試（沙盒可跑）
  t10-quality-gates.txt     出貨前三道關卡證據
```

## 設計選擇：延續 T-08 的「佇列產生器」模式

三檔（`gate-check.ps1`／`gate-advance.ps1`／`gate-reset.ps1`）皆**只讀 GitHub、只寫本機佇列檔**，不直接呼叫 GitHub 寫入 API——理由與 T-08 README 相同（`SC-DEC-BOT-001`：Cowork 手動階段寫不進 GitHub；`apply-queue.ps1` 已把寫入／冪等／回驗這套邏輯做完，不重複造輪子）。三檔以 dot-source cascade 共用函式：`gate-advance.ps1`／`gate-reset.ps1` 各自 `. gate-check.ps1 -FunctionsOnly`，`gate-check.ps1` 再 `. ../t21/queue-common.ps1`。

## scope 邊界（誠實聲明，🔒 對應 ticket 的 scope 鎖）

**本票做**：站序合法性判定（§3.4「站序不可跳」，跨站請求一律拒絕並具名列出被跳過站的未滿足條件）、單一次「設定完整 label 集合」推進（原子性）、寫後回驗（issues API 直讀 anchor，不經 search，不符重試一次仍不符判失敗）、歸因偵測與復位模式（deferred-to-CI，程式路徑與離線測試已涵蓋）。

**本票不做**（明確排除，避免與其他票重工）：
- 豁免掃描（DECISIONS.md 過期判定，T-19）——`gate-check.ps1` 明確標「N/A（T-19 範圍）」，不計入 AND、不偽裝已檢查。
- 面板顯示（T-16）——本票不產生任何面板 artifact。
- 站 4／5 專屬驗收邏輯（紅綠證據判斷、verifier 實測、雙審、修復復驗，T-14／T-15a）——`gate-check.ps1` 對這兩站的 checklist 一律 fail-closed 具名「屬 T-14／T-15a 範圍」。

**§6 checklist 的兩層判定**：站 1／2（及站 3「切片可獨立驗收」、站 4／5 全部）屬「內容裁量項」——依 §5.0 No-Hands 邊界，gate 不越權替使用者／Commander 下判斷，而是透過 `-ChecklistOverrides` 讀取呼叫端（已完成讀驗或 dispatch 審查）的裁定結果；未提供 ⇒ fail-closed。站 3「§3.5 全八項欄位」為結構性存在檢查（欄位關鍵字是否出現在票 body），機械判定，本票實作。

## 紅燈設計（斷言失敗型，非檔案缺失型）

依 ticket 建議，對一個站 1 的 anchor 送出「跳到站 3」的推進請求：
- **紅**：用 `-BypassStationOrderCheck`（比照 T-08 `-BypassUniquenessGuardForRedTest` 先例）強制放行站序檢查 ⇒ 斷言「`Reason` 必須為 `station-order-violation`」**真的會失敗**（因 bypass 讓站序檢查形同虛設）——斷言失敗的紅，非檔案缺失／載入失敗的紅。
- **綠**：不開 bypass、同一組 fixture 重跑 ⇒ `Reason` 正確為 `station-order-violation`，且獨立 GET 確認 anchor 站別 label 未變。

三組（1→3、2→4、3→5）皆測，對應 SC#2「以 1→3、2→4、3→5 三組驗證，三組全拒」。輸出見 `t10-red-green.txt`（使用者本機執行 `t10-test.ps1` 後產生）。

## deferred-to-CI 項目（依 ADR-NP-009）

| 項目 | 狀態 |
|---|---|
| 站別歸因合法性判定（`all.attribution`／`all.identity`，`Get-CrossStationChecklist`） | 程式已實作（`-GateIdentityLogins` 空 ⇒ 手動階段不算入 AND，僅具名回報；提供後轉 CI 階段判定）；離線測試涵蓋兩模式；動態驗收（真實 CI bot 身分）延後 |
| 復位模式兩分支（`gate-reset.ps1`：`Find-LastLegalStationEvent`／`Invoke-GateReset`） | 程式已實作；離線測試涵蓋兩分支（含混合 actor 時間序、全人手 actor）；動態驗收（真實 timeline）延後，見 `gate-reset.md` |

以上為「已實作待 CI 動態驗證」，不是「未實作」——區別詳見各檔內的 🔴 標註與 `gate-reset.md`。

## 使用者要跑的指令（本機 Windows PowerShell 5.1）

```powershell
cd <plugin repo>\build\t10

# 出口條件檢查（不寫任何東西）
.\gate-check.ps1 -WorkId W-demo -PrimaryRepo <owner>/<repo> -AnchorIssue <N> -TargetStation sc:station-2

# 推進（產生佇列項）
.\gate-advance.ps1 -WorkId W-demo -PrimaryRepo <owner>/<repo> -AnchorIssue <N> -TargetStation sc:station-2 -ChecklistOverridesPath overrides.json
..\t21\apply-queue.ps1 -QueuePath .\queue.json

# 寫後回驗
.\gate-advance.ps1 -WorkId W-demo -PrimaryRepo <owner>/<repo> -AnchorIssue <N> -TargetStation sc:station-2 -VerifyAfterApply

# 復位（deferred-to-CI；手動階段未提供 -GateIdentityLogins 會具名拒絕執行）
.\gate-reset.ps1 -WorkId W-demo -PrimaryRepo <owner>/<repo> -AnchorIssue <N> -GateIdentityLogins 'github-actions[bot]'
```

離線測試（沙盒／CI 皆可跑，不連網）：

```
/opt/pwsh/pwsh -NoProfile -File t10-offline-test.ps1
```

動態測試（需本機真實 PAT，會在指定 repo 建立並清理測試用 issue）：

```powershell
.\t10-test.ps1 -Owner <owner> -Repo <repo>
```
