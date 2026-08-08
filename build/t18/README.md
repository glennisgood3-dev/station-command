# T-18 · legacy 收編：auditor、定站上限站 3、badge 生命週期

依 `Spec_station-command_v1.11.md` §7.2（auditor）、§7.3（legacy 收編兩條路徑＋定站上限站 3）、
§7.4（badge 生命週期）、§6（出口條件 checklist——legacy 與 native 共用同一份，非另立寬鬆標準）、
§4.1（卡片 legacy badge）、§2（`/station-intake` 權限邊界）定案；`tickets-draft.md` T-18 全文
驗收條件逐字落實；佇列格式依 `../t21/queue-format.md`。**地基（直接重用，未重寫）**：`../t08/`
（intake native 建立步驟＋gate 初始化判準）、`../t10/`（gate、§6 checklist 正典）、`../t13/`
（站 3 八欄位深度 gate，已通過驗收）。**本票不修改** `build/t08`–`build/t27`、`build/station-command/`
任何檔案（file ownership 邊界）；亦不修改 Spec 或 tickets 檔。

## ⚠️ 唯一的安全邊界（本票全套交付內容的最高優先約束）

T-18 是全票集裡**唯一會對「既有真實 project repo」動作**的票——誤收編會在別人的 repo 留下
milestone／issue，需要人工善後。**本交付的所有驗收測試只跑在人造 fixture／離線 mock 上，
從未、也不會對任何真實 repo 執行收編動作**（見下「三道自檢」與「CLI smoke test」兩節的實跑
證據——CLI smoke test 故意用假 PAT 觸發沙盒層級的 GitHub 存取拒絕，證明整條路徑連讀都讀不到
真實 repo，更遑論寫）。

## 目錄結構

```
build/t18/
  legacy-intake.ps1                 淨新增：/station-intake legacy 模式 Stage A/B/C（重用 t08
                                     原子函式，非重用其整個 Invoke-IntakeNativeFlow，理由見下）、
                                     Get-AuditorCandidateStation、Test-LegacyStationCap（🔴 紅燈
                                     核心）、Test-LegacyRemediationComplete（§7.3 兩條路徑）、
                                     Test-LegacyTicketProtectionGuard（🔴 不改寫舊票守門）、
                                     Test-AuditorFindingsWellFormed、Format-AuditorReport
  gate-legacy-advance.ps1           淨新增：badge 生命週期摘除邏輯（New-LegacyAdvanceLabelSet、
                                     Get-LegacyBadgeStatus、Invoke-LegacyGateAdvanceProduce，重用
                                     T-10 Invoke-GateCheck 做站別推進合法性判定，不重寫）
  auditor-prompt.md                 §7.2 逐字承接＋輸出 schema＋與 t10 checklist 定義的關係聲明
  station-intake-legacy.md          掛在 ../t08/station-intake/SKILL.md 之下的 legacy 模式增補
                                     （比照 ../t13/station-gate-supplement.md 先例，不新建整份
                                     SKILL.md，避免兩份定義互相漂移）
  fixtures/                         人造 legacy 專案（見下「fixture 清單」），全部人工撰寫，非
                                     任何真實 repo 內容
  t18-offline-test.ps1              離線 mock 測試，73 項斷言＋1 項 RED-CONFIRMED 紅燈證據
  t18-quality-gates.txt             出貨前三道關卡證據（BOM／ParseFile／離線測試／黑箱CLI smoke）
  README.md                         本檔
```

## fixture 清單（人造，非真實 repo）

| Fixture | 情境 | 用途 |
|---|---|---|
| `fixtures/legacy-project-a/` | 站 1 就不過（名詞表未定義「FooWidget」「BarQueue」、無 ADR／確認紀錄） | 候選站別＝1 情境（群組 B1／C1） |
| `fixtures/legacy-project-b/` | 站 1-2 過、站 3 不過（舊格式票缺 §3.5 欄位） | legacy 收編最典型情境（候選＝3，群組 B2／C2／CLI smoke I3） |
| `fixtures/legacy-project-b/DECISIONS-path2-not-adopted.md` | 含「不收編、僅供查閱」 | §7.3 路徑②（群組 D2） |
| `fixtures/legacy-project-b/remediated-native-tickets/` | 兩張完整 §3.5 八欄位 native 票 | §7.3 路徑①（群組 D1，重用 T-13 `Test-Station3TicketSetDeep`） |
| `fixtures/artifact-inventory.md` | 人工手寫的「預期查核結果」，**寫於 auditor findings JSON 之前** | 獨立預期值來源（Spec §3.5 註 C），見下節 |
| `fixtures/auditor-findings-legacy-project-{a,b}.json` | 誠實 mock auditor 輸出 | 群組 A/B/C/G/CLI smoke |
| `fixtures/auditor-findings-legacy-project-b-optimistic.json` | **刻意造假**：3.fields／3.vertical 誤標 pass | 專供群組 C 紅燈情境使用 |
| `fixtures/protected-legacy-tickets.json` | `acme/legacy-repo#101`／`#102` | 不改寫舊票守門測試（群組 F） |

## 為何不直接呼叫 t08 的 `Invoke-IntakeNativeFlow` 整個函式（誠實聲明）

該函式內部用 `Join-Path $PSScriptRoot 'intake-native-report.txt'` 寫報告——PowerShell
`$PSScriptRoot` 為詞法作用域，綁定「函式定義所在的檔案」，dot-source 後仍指向 `../t08/`，
若直接呼叫會把報告寫進 `build/t08/`，**違反 file ownership**。且該函式跑完 Stage A/B 後會
自動接續 native 專屬的 Stage C（恆定 `sc:station-1`），legacy 情境下這是錯的（legacy 站別由
auditor 判定，非恆為站 1）。故 `legacy-intake.ps1` 只重用「原子」層級函式（`Find-AnchorByWorkId`
`Find-MilestoneByTitle`／`Get-AnchorDeclaration`／`Test-MilestoneDescriptionFormat`／
`Test-GateInitCriteria`／`Add-QueueItemIfAbsent`），自組 Stage A/B/C 迴圈——產生的佇列項與
native 模式**逐位元組相同的 body 模板**，只是呼叫序列由本檔驅動。詳見 `station-intake-legacy.md`。

同理，`gate-legacy-advance.ps1` 不修改 T-10 `gate-advance.ps1` 的 `New-StationAdvanceLabelSet`
（該函式只剝除 `^sc:station-*`，若重用會讓 `sc:legacy` 永久殘留），改建平行的
`New-LegacyAdvanceLabelSet`（同時剝除 `sc:legacy`），但仍重用 T-10 `Invoke-GateCheck` 做站別
推進合法性與 checklist 判定，不重寫該部分。

## 驗收條件①～③對照測試、實跑結果

| 驗收條件 | 對應測試 | 實跑結果 |
|---|---|---|
| ① legacy 定站上限＝站 3，且用真的紅燈證明 | 群組 C（`Test-LegacyStationCap`）＋ `-BypassCapForRedTest` 紅燈段落 | **RED-CONFIRMED**（見下節原文）；C-GREEN 起 5 項全 PASS |
| ② 獨立預期值來源（不採 auditor 自證） | `fixtures/artifact-inventory.md`（人工手寫，寫於 findings JSON 之前）＋ `Get-AuditorCandidateStation` 不採信 `AuditorSuggestedRetreatStation` 自報欄位，改重新從 `Findings` 逐條算 | 群組 B 全 PASS；`auditor-prompt.md`「輸出消費方式」節逐字聲明此設計 |
| ③ badge 生命週期三階段皆有測試 | 群組 E（E1 掛上／E2 存續中／E3-E5 摘除＋不誤加回） | 9 項全 PASS，見下「badge 三階段測試」節 |

（票面原始編號含更多細項，此處①～③對應票面最核心的三個「必須可驗證」要求；完整 73 項斷言與
群組對照見 `t18-quality-gates.txt`。）

## 紅燈設計（Spec §6 註 A：斷言失敗的紅，非載入失敗／語法錯誤）

**開關**：`Test-LegacyStationCap -BypassCapForRedTest`（⚠️ 僅供紅燈驗證使用，正式流程與一般
手動執行絕對禁止開啟；開啟時函式回傳的 `Detail` 欄位本身也印出三個警示符號字串）。

**斷言原文**（`t18-offline-test.ps1` 第 151-158 行）：
```powershell
$redCap = Test-LegacyStationCap -CandidateStation 4 -BypassCapForRedTest
$redCondition = ($redCap.DeterminedStation -le 3)
```

**真的失敗一次的證據**（實跑輸出）：
```
[RED-CONFIRMED] 斷言『legacy 定站不得高於站3（DeterminedStation -le 3）』如預期失敗：
-BypassCapForRedTest 開啟後，DeterminedStation=4（>3）。證明若無 cap 邏輯，未實作時 auditor
過度樂觀的候選站別（見群組B3，optimistic findings 候選=4）會被直接當成定站結果，站別因此跳過
站3直達站4——這正是 Spec §7.3『legacy 工作定站上限為站3』要防的事，不是紙上談兵。
```
這裡的「過度樂觀候選站別」不是憑空捏造：`fixtures/auditor-findings-legacy-project-b-optimistic.json`
是刻意把 `3.fields`／`3.vertical` 誤標為 `pass`（真實 fixture 內容明明未過）的假 auditor 輸出，
`Get-AuditorCandidateStation` 讀它算出候選＝4，若無 cap 這個假輸出就會直接變成定站結果。

**轉綠**：關閉 `-BypassCapForRedTest` 後（C-GREEN 起），同一份候選＝4／未收編情境 ⇒
`DeterminedStation=3 CapApplied=true`；另 4 項邊界情境（候選=1 不介入／候選=3 本身即上限不介入／
候選=4 但已收編完成則 cap 解除／候選=5 仍封頂 3）皆 PASS。

## 「不改寫舊票」的程式碼層守門（非文件宣告）

Spec §7.3 兩條路徑皆不得改寫舊票，本票用 `Test-LegacyTicketProtectionGuard` 在**每一筆佇列項
產生前**做檢查（非僅在文件上宣告）：

- 守門邏輯：讀 `fixtures/protected-legacy-tickets.json`（`[{repo, issue}, ...]`）作為「既有舊票
  清單」；任何佇列項的 `target.issue` 命中此清單，一律 `Blocked=true`，**不寫入佇列、不呼叫
  `Write-QueueFile`**（`action` 不限——涵蓋 `set-labels`／`close-issue`，`close-issue` 涵蓋「刪除
  語意」）。
- `Add-Station18QueueItemIfAbsent`（所有佇列寫入的唯一入口）在呼叫 t08 `Add-QueueItemIfAbsent`
  之前**必先過這道守門**，被擋下時函式提早 return，物理上不執行任何寫檔案的程式碼路徑。
- 對 `create-issue`／`create-milestone` 型佇列項（`target` 無 `issue` 欄位，尚未指向既有 issue）
  守門判定 `Blocked=false`（不誤擋合法的新建動作）。

**如何被證明**（`t18-offline-test.ps1` 群組 F，5 項）：
- F1：對受保護 `#101` 的 `set-labels` ⇒ `Blocked=true`
- F2／F2b：`Add-Station18QueueItemIfAbsent` 對受保護票 ⇒ `Added=false`，且**佇列檔案本身確認
  仍不存在**（不是「寫入後又復原」，是壓根沒呼叫寫檔案）
- F3：對受保護 `#102` 的 `close-issue` ⇒ `Blocked=true`
- F4／F4b：對非保護清單內 `#201` ⇒ `Blocked=false` 且確實成功寫入佇列（證明守門不誤擋合法動作）
- F5：`create-issue`（無 `issue` 欄位）⇒ `Blocked=false`（不適用本守門）

## badge 三階段測試

| 階段 | 函式 | 測試 | 結果 |
|---|---|---|---|
| ①掛上 | `Get-LegacyInitialLabelSet` | E1／E1b：初始 label 集合恰含 `sc:work`／determined station／`sc:legacy` 三項，不多不少 | PASS |
| ②存續中 | `Get-LegacyBadgeStatus` | E2：anchor 現有 `sc:legacy` ⇒ `HasLegacyBadge=true` | PASS |
| ③通過首個 native gate 後摘除 | `New-LegacyAdvanceLabelSet`／`Invoke-LegacyGateAdvanceProduce` | E3/E3b/E3c：推進後 label 集合不含 `sc:legacy`、`BadgeRemoved=true`、正確含新站別不含舊站別；E4/E4b：badge 已消失後再推進不會被誤加回；E5：native work 全程不出現 `sc:legacy` | PASS（6 項） |

CLI 整合層再驗證一次（`t18-offline-test.ps1` 群組 I4）：`Invoke-LegacyGateAdvanceProduce` 對
legacy-project-b 情境（推進前 `HasLegacyBadge=true`）跑一次完整推進，產生的 `set-labels` 佇列項
`payload.labels=[sc:work, sc:station-2]`（不含 `sc:legacy`），且佇列檔內容與函式回傳一致（真的
寫入，非僅記憶體物件）。

## permission 邊界（intake 不寫狀態 label）

`legacy-intake.ps1` Stage A/B 只產生 `create-issue`／`create-milestone` 佇列項，`payload.labels`
恰含 `sc:work`（群組 I1c 明確驗證：**不含任何站別或 `sc:legacy`**——建立當下還不知道定站結果）。
`sc:station-N` 與 `sc:legacy` 的寫入一律在 Stage C（扮演「呼叫 gate 初始化路徑」的角色，比照
native 模式），且是**單一筆** `set-labels` 佇列項一次寫完整集合（Spec §3.4 原子性不變式，非
先移除再加入兩步）。所有寫入皆為佇列項，**未在任何地方直接呼叫 GitHub 寫入 API**（`Invoke-RestMethod`
只用於讀取，寫入一律交給 `../t21/apply-queue.ps1`）。

## 三道自檢數字

見 `t18-quality-gates.txt` 完整輸出，摘要：

| 關卡 | 對象 | 結果 |
|---|---|---|
| ① UTF-8 BOM | `legacy-intake.ps1`／`gate-legacy-advance.ps1`／`t18-offline-test.ps1` | 3/3 BOM-OK |
| ② ParseFile 語法 | 同上 | 3/3 PARSE-OK |
| ③ 離線 mock 測試 | `t18-offline-test.ps1` | **73 項斷言，FAIL=0**；另 1 項 RED-CONFIRMED（不計入 FailCount） |

沙盒執行環境：`/opt/pwsh/pwsh`，PowerShell 7.4.6；使用者實際環境為 Windows PowerShell 5.1。

## CLI smoke test 結果（票面點 9：變數 cascade 陷阱防呆）

除 `t18-offline-test.ps1` 群組 I 的 in-process 函式級整合測試外，另外**真的以子行程呼叫一次**
`legacy-intake.ps1`（黑箱驗證非 no-op）：

```
/opt/pwsh/pwsh -NoProfile -File ./legacy-intake.ps1 `
  -WorkId 'W-smoke-cli-test' -PrimaryRepo 'acme/legacy-repo' `
  -ParticipatingRepos 'acme/legacy-repo' `
  -PatPath '/tmp/t18-smoke/fake-pat.txt' -QueuePath '/tmp/t18-smoke/queue.json' `
  -AuditorFindingsPath './fixtures/auditor-findings-legacy-project-b.json' `
  -ProtectedLegacyTicketsPath './fixtures/protected-legacy-tickets.json'
```

輸出前兩行證明呼叫端傳入的真實值（`W-smoke-cli-test`）在 dot-source t08 之後仍未被其內部佔位值
（`W-t18-dotsource-placeholder`）覆蓋：
```
[T18-SMOKE] 已收參數（dot-source 前存證，證明非 no-op）：WorkId='W-smoke-cli-test' PrimaryRepo='acme/legacy-repo' ParticipatingRepos=[acme/legacy-repo]
[T18-SMOKE] dot-source 完成後 $T18WorkId 仍為 'W-smoke-cli-test'（未被 t08 佔位值 'W-t18-dotsource-placeholder' 覆蓋——證明 $T18* 命名隔離有效）
```
隨後 Stage A 嘗試讀取 GitHub anchor 現況，因沙盒 session 本身未授權存取任何 GitHub repo 而失敗
（`GitHub access to this repository is not enabled for this session`），`$ErrorActionPreference='Stop'`
使腳本以非零結束碼終止（`REAL_EXIT_CODE=1`），且 `/tmp/t18-smoke/queue.json` 確認**未被建立**——
同時證明：①CLI 真的執行到會接觸 GitHub 的那一步（非 no-op，參數確實流通到底），②全程未也不會
對任何真實 repo 產生任何寫入（票面安全邊界，即使意外連到網路也是讀失敗，寫入路徑在讀取失敗前
就已終止，從未到達）。

## PS 5.1／StrictMode 陷阱（票面三項＋本票過程中新發現兩項變體）

票面列出的三項（①單一物件無 `.Count`／②`,@()` 於直接賦值是「含空陣列的單元素陣列」／
③`@(函式呼叫)` 對已保護回傳值再包一層）全數遵守：內部賦值一律先賦值變數再 `@()` 包裝，
不在 `@()` 內直接呼叫函式；`return` 陳述式的陣列保護只用 `return ,@(...)`。

過程中另外發現兩個更隱蔽的變體（已修正，見下「開發過程中實際抓到的 bug」）：
- **物件字面值屬性賦值中的前導逗號**：`[pscustomobject]@{ Prop = ,@($x); ... }` 會多包一層
  （與獨立 `return ,@($x)` 陳述式行為不同）。修正原則：物件字面值屬性一律用 `@(...)`，不加
  前導逗號。
- **`@(函式呼叫)` 對「已用逗號保護的回傳值」二次包裝**：即使被呼叫函式的 `return` 本身已正確用
  `,@(...)` 保護，呼叫端若再包一層 `@(函式呼叫本身)` 仍會二次包裝成 1 筆。修正原則：一律先賦值
  給變數，再對該變數呼叫 `@()`（呼叫端與被呼叫端分兩個獨立陳述式）。

`t18-offline-test.ps1` 群組 H（H1-H4）為這些陷阱的哨兵測試。

## 開發過程中實際抓到的 bug（誠實記錄）

1. `Where-Object` 零筆匹配結果為 `$null`，直接 `.Count` 會拋 `property 'Count' cannot be found`
   （`legacy-intake.ps1` Stage C 的既有 label 過濾、測試檔 D-setup／G2b 段落皆曾踩到）。修正：
   一律先 `@(Where-Object ...)` 賦值再取 `.Count`。
2. 群組 G2 最初要求「every ✗ 項的 Evidence 皆須指向真實 fixture 檔名」，但 legacy-project-a
   有 3 項 ✗（`2.confirm`/`2.gapreview`/`3.fields`）描述的是「檔案根本不存在」（因站 1 就已
   退回，這些屬陪同呈報的下游項），其證據本就無法引用真實檔名。修正：G2 只檢查真正驅動候選
   站別判定的 `UnmetItems`（1.glossary/1.adr/1.confirm，皆指向真實存在的 README.md/NOTES.md），
   另加 G2b 驗證「描述缺席」型證據仍非空字串（非空泛留白，只是無法比對真實檔名）。
3. 上述「PS 5.1 陷阱兩項變體」（物件字面值前導逗號、`@(函式呼叫)` 二次包裝）皆為實跑後才發現，
   透過逐一 `pwsh -Command` 微測試確認行為並修正全部相關位置。

## 誠實聲明：deferred / best-effort 項目

- **auditor 為 mock，非真的 dispatch fresh-context sub-agent**：本票交付 `auditor-prompt.md`
  定義完整的 dispatch 規格與輸出 schema，`legacy-intake.ps1` 消費端（`Get-AuditorCandidateStation`
  等）已 100% 函式級別驗證；但實際「dispatch 一個 fresh-context sub-agent 去讀 repo 工件」這個
  動作本身，依票面安全邊界（不得對真實 repo 動作）與 §5.0 No-Hands（Commander 不得自己扮演
  auditor），**不在本次離線交付範圍內驗證**，只用人工撰寫的誠實 mock JSON（`fixtures/auditor-
  findings-*.json`）模擬其輸出格式。差什麼才能驗完：需在使用者本機對一個真實 legacy repo 實際
  dispatch 一次 auditor sub-agent，核對其輸出是否符合 `auditor-prompt.md` schema。
- **CLI 整合層（`Invoke-LegacyIntakeFlow`／`Invoke-LegacyGateAdvanceCli`）未在離線測試中以獨立
  子行程「跑到 exit」方式驗證**（同 T-08／T-10／T-13 既有先例：CLI 主流程含 `exit`，會中斷測試
  行程，故各票 offline test 皆只測到函式層）；本交付**額外多做一步**——本節上方「CLI smoke test
  結果」用真正的子行程呼叫黑箱驗證了 Stage A 的網路呼叫路徑確實被觸達（非 no-op），這超出
  t08/t10/t13 既有先例的驗證深度。
- **`Test-GateInitCriteria` 判準⑤（身分回報）**：依 T-08 既有設計不作 fail 條件，本票沿用不
  改變此行為。
