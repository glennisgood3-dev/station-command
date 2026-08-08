# T-14 · 站 4 驗收與 red-proven

依 `Spec_station-command_v1.11.md` §6（站 4 出口條件）、§3.5 註 A／註 C、§3.3、§2 `station-gate` 白名單，`tickets-draft.md` T-14（GitHub issue #14）定案。**地基（直接重用，未重寫）**：`../t10/`（`gate-reset.ps1` cascade dot-source `gate-check.ps1` → `../t21/queue-common.ps1`，取得 `Get-CurrentIssue`／`Get-IssueTimelineEvents`／`ConvertTo-SafeArray`／`Read-PatToken`／`Get-GithubHeaders`／`Split-RepoString`／`Write-Utf8BomFile`／`Set-ConsoleUtf8`／`Read-QueueFile`／`Write-QueueFile`）、`../t21/`（`set-labels` 佇列動作型別與 `apply-queue.ps1` 落地邏輯，本票沿用不擴充）。

## 本票的核心兩條（來源不同、落點不同，兩條都要做）

- **① 紅燈型態**：每張票的紅須是**斷言失敗的紅**（非載入／collection 失敗）。來源＝使用者原話 S3「Always design Red light to prevent Ai cheating」（Pocock `tdd` 只規定「Red before green」，未定義紅燈型態，Spec §6 註 A 逐字標註此來源差異）。
- **④ 預期值出處**：verifier 須查斷言的預期值**非由被測程式自身產生**。逐字依據 Pocock `tdd`：「Expected values must come from an independent source of truth — a known-good literal, a worked example, the spec.」（Spec §3.5 註 C）。

⚠️ 兩條合起來才蓋滿 S3——只管型態擋不住自證式斷言（`load-failure-red.json` 若把紅燈換成合格的斷言失敗紅、但斷言本身仍自證，① 會放行、只有 ④ 擋得住），只管出處擋不住根本沒跑到斷言（反之亦然）。`station4-check.ps1` 的 `Invoke-Station4Check` 把兩條當**獨立的兩個判準**（各自具名缺項），不是合併成一條，正是為了不讓其中一條的通過掩蓋另一條的缺失。

另兩條驗收：**③ verifier≠executor**（執行者自陳不能當驗收，Spec §5.2）；**② 通過後票上出現 `sc:red-proven`，actor 為 bot**（actor 判準 deferred-to-CI，見下）。

## 目錄結構

```
build/t14/
  station4-check.ps1                核心查核器：①③④三項查核 + 落 sc:red-proven 佇列項 + Verify 模式
  station-gate-station4-addendum.md 說明本票掛在 ../t10/station-gate/SKILL.md 的哪個分支（4.deferred）
  fixtures/
    load-failure-red.json           驗收①：紅燈其實是載入失敗 ⇒ 拒絕
    valid-submission.json           驗收②＋④通過案例：合格交件 ⇒ 通過
    executor-is-verifier.json       驗收③：executor 本人充當 verifier ⇒ 拒絕
    self-referential-assertion.json 驗收④拒絕案例：自證式斷言 ⇒ 具名拒絕並指出該斷言
    README.md                       四份 fixture 與驗收條件的對應表、變因隔離設計說明、schema
  t14-offline-test.ps1              離線 mock 測試，55 項斷言，含【紅燈】RED-PROOF 段落
  t14-quality-gates.txt             出貨前三道關卡證據
  README.md                         本檔
```

## 三項查核怎麼做（皆為對靜態文本的字串／正則比對，🚫 不執行被測系統）

`station4-check.ps1` 的判讀對象是**人造交件所附的測試輸出原文**（JSON 格式，schema 見 `fixtures/README.md`），全程不 `import`、不 `eval`、不呼叫任何被測程式碼，第八欄「不執行被測系統」由此保證。

- **① `Test-RedLightIsAssertionFailure`**：先查 `redOutput` 是否命中載入／collection 失敗特徵（`ModuleNotFoundError`／`ImportError`／`SyntaxError`／`CommandNotFoundException`／`Interrupted: N error during collection` 等），命中即拒絕具名；否則查是否命中斷言失敗特徵（`AssertionError`／`Expected:`／`But was:`／`Should-Be` 等）；兩者皆未命中 ⇒ **fail-closed 拒絕**（不默認為合格紅燈）。
- **③ `Test-VerifierIndependent`**：`executor` 與 `verifier` 欄位正規化（trim＋大小寫不敏感）後比對，相同 ⇒ 拒絕。
- **④ `Test-AssertionExpectedIndependent`**（逐條斷言）：兩層判準——
  1. **結構性偵測**：斷言文字若同時含 `expected = <運算式>` 與 `actual/result = <運算式>` 兩行賦值，且兩運算式去空白後逐字相同、外觀像函式呼叫（而非字面值）⇒ 判定為自證式斷言（tautological），具名拒絕並指出該斷言 id。
  2. **來源標記查核**（結構性偵測未觸發時的退路）：`expectedSourceNote` 為空 ⇒ fail-closed 拒絕；非空但未提及三種獨立真相源關鍵詞（`known-good literal`／`worked example`／`spec`／中文對應詞）之一 ⇒ 拒絕；皆滿足 ⇒ 通過。

全過 ⇒ 讀該票現有 label 集合，加項（不減項）產生**單一次** `set-labels` 佇列項（沿用 T-21 原五型，未新增動作型別，見 `station-gate-station4-addendum.md`），交由 `../t21/apply-queue.ps1` 落地——本檔全程無任何 PUT／PATCH／POST 呼叫。

## 紅燈設計（斷言失敗型，非載入失敗型）——真的失敗過一次

`Test-AssertionExpectedIndependent`／`Invoke-Station4Check` 皆帶 `-SkipProvenanceCheck` 開關：

> ⚠️⚠️⚠️ **`-SkipProvenanceCheck` 僅供紅燈驗證使用，正式流程與一般手動執行絕對不得使用。** 開啟後 ④ 的查核整段略過、一律視為通過（等同關掉「防自證」這道防線）。

`t14-offline-test.ps1` 群組 C 的 RED-PROOF 段落對 `fixtures/self-referential-assertion.json` 開啟此開關，實跑後**斷言「自證式交件必須被拒絕（`OverallPass=false`）」真的失敗**（`OverallPass` 真的變成 `true`）——這是**斷言失敗型**紅（一個原本該失敗的判定，因為開關被關掉而錯誤地成功了），不是檔案不存在或語法錯誤型的紅。輸出以 `[RED-CONFIRMED]` 標記存證（比照 `../t21/t21-dynamic-test.ps1`／`../t12/t12-offline-test.ps1` 的既有先例，刻意不計入 `FailCount`，因為這段本就預期「失敗」，計入會讓總結果失真）。隨後關閉開關重跑同一 fixture，`OverallPass=false` 且 `NamedGaps` 具名指出斷言 `A1`——綠燈存證，兩段輸出皆在 `t14-offline-test-report.txt` 與本次執行的主控台輸出中可查（見 `t14-quality-gates.txt` 群組 C）。

## 四份 fixture 與驗收條件的對應（變因隔離）

詳見 `fixtures/README.md`。核心設計：`executor-is-verifier.json` 與 `self-referential-assertion.json` 都刻意讓「另外兩項查核」維持合格，只留下該 fixture 要驗證的那一項失敗，`t14-offline-test.ps1` 群組 E 逐一斷言每份 fixture 的 `NamedGaps` **恰含 1 條**且是預期那條——證明是該項查核單獨在起作用，不是三項連坐誤判成通用「FAIL」。

## `sc:red-proven` 怎麼落標（接合 T-10、不改 T-10）

`sc:red-proven` **僅票**（Spec §3.3），與 anchor 的站別 label 是兩張不同 issue 上的兩件事。`station4-check.ps1` 對單一票通過即可產生該票的 `set-labels` 佇列項，不需等整個 work 的所有票皆過。anchor 的站別推進（`sc:station-4` → `sc:station-5`）仍由 `../t10/gate-advance.ps1` 負責，其判準（`Test-WorkStationConsistency`：未關閉票的最小站）已在 T-10 實作，本票不重複、不修改。兩者產生的佇列項可混在同一份 `queue.json`，由同一支 `../t21/apply-queue.ps1` 落地（`set-labels` 本就是既有型別，無需比照 T-12／T-22 另立套用腳本）。詳細接合點見 `station-gate-station4-addendum.md`。

## 驗收②後段「actor 為 bot」——deferred-to-CI（比照 T-10 既有先例）

`Test-RedProvenActorLegit`／`Find-LastRedProvenLabelEvent` 程式路徑已完整實作，`t14-offline-test.ps1` 群組 H 以 mock timeline 涵蓋手動階段（`Blocking=false`，僅具名回報 actor）與 CI 階段（`Blocking=true`，判定 actor 是否屬於 `-GateIdentityLogins` 集合）兩種模式。真實 GitHub 連線的動態驗收（CI 階段 `github-actions[bot]` 寫入 timeline）待 CI 階段以 `-VerifyRedProven -GateIdentityLogins 'github-actions[bot]'` 執行，本沙盒無法連線實跑（誠實聲明，非規避——理由與 T-10 `gate-reset.md` 相同：手動階段執行身分即使用者本人，機器無從區分人手改動與 gate 改動，見 ADR-NP-009）。

## 使用者要跑的指令（本機 Windows PowerShell 5.1）

```powershell
cd <plugin repo>\build\t14

# 對單一站 4 票的交件跑三項查核（全過才產生佇列項）
.\station4-check.ps1 -SubmissionPath .\fixtures\valid-submission.json -Repo <owner>/<repo> -Issue <N>
..\t21\apply-queue.ps1 -QueuePath .\queue.json    # 落地 sc:red-proven

# 落地後確認票上真的出現 sc:red-proven（actor=bot 部分 deferred-to-CI，見上）
.\station4-check.ps1 -VerifyRedProven -VerifyRepoArg <owner>/<repo> -VerifyIssueArg <N> -GateIdentityLogins 'github-actions[bot]'
```

離線測試（沙盒／CI 皆可跑，不連網，不執行任何被測系統）：

```
/opt/pwsh/pwsh -NoProfile -File t14-offline-test.ps1
```

## 三道自檢結果（沙盒執行，PowerShell 7.4.6；詳見 `t14-quality-gates.txt`）

| 關卡 | 結果 |
|---|---|
| UTF-8 BOM（`station4-check.ps1`／`t14-offline-test.ps1`） | 皆 BOM-OK |
| `[System.Management.Automation.Language.Parser]::ParseFile` | 皆 PARSE-OK |
| `t14-offline-test.ps1` | 55 項，FAIL=0（含 1 個實跑抓到並修正的 bug：Jasmine 風格分行 `Expected:`／`But was:` 輸出原本誤判為 `unknown`，已補樣式修正，見 `t14-quality-gates.txt`） |

## 已知限制（誠實聲明，非規避）

- ① 紅燈型態與 ④ 自證結構偵測皆為 **best-effort 正則／字串比對**，非完整語法分析器；已涵蓋 pytest／Jasmine／PowerShell 等常見輸出樣式與若干邊界情況，但無法涵蓋所有框架格式或更隱晦的自證寫法（例如透過中介變數間接呼叫同一函式）。本票 scope 明文「不執行被測系統」，故無法用「真的跑一次」消除歧義；未命中任何已知特徵時一律 fail-closed 拒絕，把邊界情況導向人工複查而非誤判通過。
- 驗收②「actor 為 bot」的動態驗證 deferred-to-CI（見上），程式路徑與離線 mock 已完整涵蓋兩模式。
- 未附獨立動態 GitHub 測試腳本（如 `../t10/t10-test.ps1`）：ticket 面交付清單為「實作腳本、SKILL 增補、離線測試、README」，未列動態測試；`station4-check.ps1` 的 Check／Verify 兩模式本身即為可直接對真實 GitHub 執行的生產程式碼，此為刻意的 scope 收斂。
- 站 4 深度證據判斷之外的其他站別出口邏輯（站 3 拆票 gate、站 5 雙審）不在本票範圍（T-13／T-15a），本票不重複實作。
