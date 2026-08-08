# T-15a · 站 5 票級雙審、修復復驗與關票

依 `Spec_station-command_v1.11.md` §5.2（站 5 雙審規則）、§6 站5 出口條件、§3.2／§3.3（gate 唯一寫入者、close-issue 可逆路徑）、SC#6（雙審輸入分離可證、隔離未證須具名）、`tickets-draft.md` T-15a（GitHub issue #15）定案。**地基（直接重用，未重寫）**：`../t10/`（`gate-reset.ps1` cascade dot-source `gate-check.ps1` → `../t21/queue-common.ps1`，取得 `Get-CurrentIssue`／`Get-IssueTimelineEvents`／`ConvertTo-SafeArray`／`Read-PatToken`／`Get-GithubHeaders`／`Split-RepoString`／`Write-Utf8BomFile`／`Set-ConsoleUtf8`／`Read-QueueFile`／`Write-QueueFile`）、`../t21/`（`close-issue` 佇列動作型別與 `apply-queue.ps1` 落地邏輯，本票沿用不擴充）、`../t14/`（站 4 `sc:red-proven` 是站 5 開始審查的前提，本票不重跑站 4 判斷）、`../station-command/assets/`（`fowler-smells.md` 12 條 smell 基線、`routing-table.md` 站 5 雙審 executor 定義，皆唯讀引用）。

## 本票三個容易做錯的點，具體怎麼做（逐一對應票面要求）

### 1. 兩軸不得合併重排（Pocock `code-review` 逐字）

> "Do **not** merge or rerank findings — the two axes are deliberately separate"

`station5-check.ps1` 的交件 schema 把 `axisA.findings` 與 `axisB.findings` 存成**兩個獨立欄位**（結構上的第一層保證），`Test-ReportsNotMerged` 再擋一層：頂層若出現 `mergedFindings`／`combinedFindings`／`allFindings`／`rankedFindings`／`overallWinner`／`singleWinner`／`crossAxisRanking` 任一欄位，一律拒絕（`fixtures/merged-findings.json` 為此情境的人造反例）。

### 2. 但收尾摘要要報軸內 worst issue（同一份原文，逐字）

> "End with a one-line summary: total findings per axis, and the worst issue _within each axis_ (if any). Don't pick a single winner across axes"

**禁的是跨軸挑贏家，不是禁軸內排序。** `Test-ClosingSummary` 拆成兩條獨立子檢查：
- **正面要求**（缺任一項 ⇒ fail）：`closingSummary.axisACount`／`axisBCount` 須等於各軸 `findings` 實際筆數；若該軸筆數 >0，`axisAWorst`／`axisBWorst` 須非空。
- **負面要求**（命中即 fail）：`closingSummary.text` 若命中「唯一贏家／唯一最嚴重／總體最嚴重／全站最嚴重／整體最嚴重／overall worst／跨軸…最嚴重」等樣式，判定為違規的跨軸單一贏家。

`fixtures/closing-summary-3-1-good.json`／`closing-summary-3-1-cross-winner.json` 兩份 fixture **逐字比照票面驗收⑥的範例**（軸 A 3 條、軸 B 1 條）：前者兩軸各自具名 worst 且無跨軸贏家 ⇒ 通過；後者同一 3/1 配置但摘要文字多了一句「本票整體最嚴重問題是 A1」⇒ 被擋下。`t15a-offline-test.ps1` 群組 H／J7／J8 對此逐字比照。

### 3. 輸入分離是否真的分離只能從實際 prompt 清單驗

**兩層防線**：
- **結構性（第一道，硬保證）**：`station5-dispatch-prep.ps1` 的 `New-AxisAPrompt` 函式**簽章裡沒有任何可傳入 spec 原文的參數**（`Ticket`／`DiffText`／`StandardsRefs`／`SmellBaselineText`）——不是「傳進來又被過濾」，是呼叫端物理上無法透過這個函式把 spec 原文塞進軸 A prompt。`New-AxisBPrompt` 同理，簽章沒有 `StandardsRefs`／`SmellBaselineText`。`t15a-offline-test.ps1` N1／N2 直接用 `Get-Command` 檢查參數清單佐證這條保證。交件驗證端 `Test-AxisInputSeparation` 也要求 `inputList` 每一項的 `kind` 落在各軸白名單內（軸 A：`diff`／`standards`／`smell-baseline`；軸 B：`diff`／`spec`），出現禁止類別 ⇒ 立即拒絕。
- **文字掃描（第二道，best-effort，防「把 spec 原文貼進 diff 本身」這種結構性防線防不了的情況）**：`Test-PromptTextMarkers` 用已知樣式庫掃描組出的 prompt 全文，**採門檻計數（≥2 個不同樣式命中才判定）**——理由見下方「rework」段：單一字樣命中（例如 smell 基線 asset 頁尾合法引用一次 spec 檔名、或 spec 條文合法提及一次 "Fowler"）不足以區分「合法提及」與「真的整段夾帶」。

**證據位置（供核對）**：`t15a-offline-test.ps1` 執行後在本目錄產生 `evidence-axisA-prompt.txt`／`evidence-axisB-prompt.txt`——**用真實內容**組出（軸 A 用 `../station-command/assets/fowler-smells.md` 全文；軸 B 用 `Spec_station-command_v1.11.md` §5.2 附近摘錄），非佔位文字。打開這兩個檔案即可肉眼核對「軸 A 檔案裡沒有 spec 條文正文、軸 B 檔案裡沒有 12 條 smell 清單本文」。`station5-dispatch-prep.ps1` 亦可獨立執行（見下方「使用者要跑的指令」）針對任一真實票的 diff 產生同樣的證據檔。

## 目錄結構

```
build/t15a/
  station5-dispatch-prep.ps1        軸A/軸B prompt 組裝（結構性輸入分離保證）＋ 第二道文字掃描
                                     防線＋ 證據檔輸出；不呼叫 Task、不派 sub-agent
  station5-check.ps1                核心查核器：①輸入分離②修復復驗③verifier獨立⑤SC#6標註
                                     ⑥收尾摘要＋報告不合併＋修法證據/裁決紀錄＋規範版本具名，
                                     全過才產生 close-issue 佇列項；另含 Verify 模式
  station-gate-station5-addendum.md 說明本票掛在 ../t10/station-gate/SKILL.md 的哪個分支
                                     （5.deferred）、與 T-14／T-15b 的分工邊界
  fixtures/
    valid-submission.json           全過的基準案例
    not-reverified.json             驗收②：未經復驗即結案 ⇒ 拒絕（本票紅燈設計標的）
    two-axis-supplement.json        驗收②的另一合法路徑（兩軸補審一輪）
    executor-is-verifier.json       驗收③：executor 本人當 verifier ⇒ 拒絕
    verifier-is-commander.json      驗收③：verifier=Commander ⇒ 拒絕
    missing-isolation-disclaimer.json  驗收⑤：未落檔且缺固定字串 ⇒ 拒絕
    isolation-decision-recorded.json   驗收⑤：已落檔 ⇒ 標註要求解除
    closing-summary-3-1-good.json      驗收⑥：逐字比照範例，兩軸各自具名 worst ⇒ 通過
    closing-summary-3-1-cross-winner.json  驗收⑥：同配置但出現跨軸單一贏家 ⇒ 拒絕
    closing-summary-missing-worst.json     驗收⑥：軸內 worst 缺項 ⇒ 拒絕
    spec-leak-axisA.json            驗收①：軸 A 出現 spec 原文 ⇒ 拒絕
    smell-leak-axisB.json           驗收①：軸 B 出現 smell 基線 ⇒ 拒絕
    standards-not-named.json        Spec §6 站5：規範版本未具名 ⇒ 拒絕
    merged-findings.json            Spec §5.2：兩軸被合併重排 ⇒ 拒絕
    hard-finding-no-evidence.json   Spec §6 站5：hard finding 缺修法證據 ⇒ 拒絕
    README.md                       十五份 fixture 與驗收條件的對應表、schema
  t15a-offline-test.ps1             離線 mock 測試，91 項斷言，含【紅燈】RED-PROOF 段落
  t15a-quality-gates.txt            出貨前三道關卡證據（含過程中抓到並修正的 2 個真實 bug）
  README.md                        本檔
```

## 驗收條件逐條對應

| 驗收 | 對應查核／函式 | fixture | 測項 |
|---|---|---|---|
| ①兩份報告分開留存、輸入清單核對 | `Test-AxisInputSeparation`（結構性＋文字掃描兩層） | `spec-leak-axisA.json`／`smell-leak-axisB.json` | 群組 A、J10、J11 |
| ②未經復驗即結案 ⇒ 拒絕 | `Test-RemediationVerified`（**本票紅燈設計標的**） | `not-reverified.json`／`two-axis-supplement.json` | 群組 F（含 RED-PROOF）、J1、J2 |
| ③executor 本人當 verifier ⇒ 拒絕 | `Test-Station5VerifierIndependent`（含「亦不得是 Commander」） | `executor-is-verifier.json`／`verifier-is-commander.json` | 群組 E、J3、J4 |
| ④通過後票被關閉，actor 為 bot | `New-CloseTicketQueueItem`＋Verify 模式 `Test-TicketClosed`／`Find-LastCloseEvent`／`Test-CloseActorLegit`（deferred-to-CI） | — | 群組 K、L |
| ⑤SC-DEC-ISO-001 落檔前缺隔離標註 ⇒ fail | `Test-IsolationDisclaimer` | `missing-isolation-disclaimer.json`／`isolation-decision-recorded.json` | 群組 G、J5、J6 |
| ⑥收尾摘要（軸內 worst、禁跨軸贏家） | `Test-ClosingSummary` | `closing-summary-3-1-good.json`／`closing-summary-3-1-cross-winner.json`／`closing-summary-missing-worst.json` | 群組 H、J7、J8、J9 |

另補齊 Spec §6 站5 出口條件其餘項（票面未逐條編號但屬同一出口 checklist）：規範版本具名（`standards-not-named.json`）、報告不合併（`merged-findings.json`）、hard violation 修法證據與 judgement call 裁決紀錄（`hard-finding-no-evidence.json`）。

## 紅燈設計（斷言失敗型，非載入失敗型）——真的失敗過一次

`Test-RemediationVerified`／`Invoke-Station5Check` 皆帶 `-SkipRemediationCheck` 開關：

> ⚠️⚠️⚠️ **`-SkipRemediationCheck` 僅供紅燈驗證使用，正式流程與一般手動執行絕對不得使用。** 開啟後②的修復復驗查核整段略過、一律視為已復驗（等同關掉「修復必須復驗」這道防線）。

`t15a-offline-test.ps1` 群組 F 的 RED-PROOF 段落對 `fixtures/not-reverified.json`（`remediation.verified=false`）開啟此開關，實跑後**斷言「未經復驗即結案必須被拒絕（`OverallPass=false`）」真的失敗**（`OverallPass` 真的變成 `true`）——這是**斷言失敗型**紅（一個原本該失敗的判定，因為開關被關掉而錯誤地成功了），不是檔案不存在或語法錯誤型的紅。輸出以 `[RED-CONFIRMED]` 標記存證（比照 `../t14/t14-offline-test.ps1`／`../t21/t21-dynamic-test.ps1` 的既有先例，刻意不計入 `FailCount`）。隨後關閉開關重跑同一 fixture，`OverallPass=false` 且 `NamedGaps` 恰含 1 條「② 修復復驗」——綠燈存證，兩段輸出皆在 `t15a-offline-test-report.txt` 與 `t15a-quality-gates.txt` 可查。

## `close-issue` 怎麼落標（接合 T-10／T-21，不改任一檔）

站 5 關票沿用 T-21 原五型之一 `close-issue`（`../t21/queue-format.md` §3.2），payload 固定 `{"state":"closed","state_reason":"completed"}`——**不新增動作型別**，`station5-check.ps1` 產生的佇列項可與 T-10／T-12／T-14 產生的佇列項混在同一份 `queue.json`，一起交給 `../t21/apply-queue.ps1` 落地。工作級收尾（`sc:station-done`、關 anchor、關 milestone）屬 T-15b 範圍，本票不做（scope 邊界，見下）。詳細接合點見 `station-gate-station5-addendum.md`。

## scope 邊界（誠實聲明）

**本票做**：票級雙審輸入分離準備與核對、報告不合併查核、修復復驗查核、verifier 獨立性查核、SC#6 隔離標註查核、收尾摘要查核、通過後產生 `close-issue` 佇列項、Verify 模式（票已關閉＋actor 合法性）。

**本票不做**（明確排除，避免與其他票重工）：
- **work 級完成態收尾**（`sc:station-done`、關 anchor、關 milestone）——T-15b 範圍。
- **merge**——scope 明文排除，本票不執行任何分支合併，第八欄「不可逆動作」判「無」的依據之一即在此（合併觸發 CI 部署的可能性不在本票發生）。
- **站 4 紅綠證據判斷**——T-14 範圍，`sc:red-proven` 是站 5 開始審查的前提，本票不重跑。
- **實際 Task 呼叫 sub-agent**——Commander 的動作，本票只組 prompt 與驗證報告（同 T-12 `run-dispatch.ps1` 先例：「本檔不代 Commander 呼叫 sub-agent」）。

## 不可逆動作：無（逐項具名，依票面既有判定，本檔不重複裁決只重申落地方式）

三個動作皆可逆：① 雙審 dispatch（唯讀）；② 修復復驗（重跑驗收條件，不改碼）；③ 關票（`close-issue` 可重開，`../t10/gate-reset.ps1` 與 §3.2 已為人手關閉的票設有 `sc:awaiting-user` 回收路徑）。本票 scope 不含 merge，故五類不可逆動作中的 deploy 不經本票發生。

## 使用者要跑的指令（本機 Windows PowerShell 5.1）

```powershell
cd <plugin repo>\build\t15a

# ① 組兩軸 prompt（讀真實 diff／真實 T-11 smell 基線／真實 spec 摘錄，寫證據檔）
.\station5-dispatch-prep.ps1 -Ticket 'T-XX' -DiffPath .\my-ticket.diff -OutDir .
# Commander 拿 evidence-axisA-prompt.txt／evidence-axisB-prompt.txt 全文分別餵給兩個平行
# fresh-context general-purpose sub-agent，取回兩份報告後組成本票交件 schema（見 fixtures/README.md）

# ② 對交件跑十項查核（全過才產生佇列項）
.\station5-check.ps1 -SubmissionPath .\my-submission.json -Repo <owner>/<repo> -Issue <N>
..\t21\apply-queue.ps1 -QueuePath .\queue.json    # 落地 close-issue

# ③ 落地後確認票真的被關閉（actor=bot 部分 deferred-to-CI，見上）
.\station5-check.ps1 -VerifyClosed -VerifyRepoArg <owner>/<repo> -VerifyIssueArg <N> -GateIdentityLogins 'github-actions[bot]'
```

離線測試（沙盒／CI 皆可跑，不連網，不執行任何被測系統）：

```
/opt/pwsh/pwsh -NoProfile -File t15a-offline-test.ps1
```

## 三道自檢結果（沙盒執行，PowerShell 7.4.6；詳見 `t15a-quality-gates.txt`）

| 關卡 | 結果 |
|---|---|
| UTF-8 BOM（三支 .ps1） | 皆 BOM-OK |
| `[System.Management.Automation.Language.Parser]::ParseFile` | 皆 PARSE-OK |
| `t15a-offline-test.ps1` | 91 項，FAIL=0（含 1 條 RED-CONFIRMED；過程中另抓到並修正 2 個真實 bug，見 `t15a-quality-gates.txt`——① CLI 層級的 `$FunctionsOnly` 跨檔參數同名覆蓋 bug，② 文字掃描第二道防線的誤傷率過高，皆已修正並重跑驗證） |

## 已知限制（誠實聲明，非規避）

- 輸入分離第二道文字掃描（`Test-PromptTextMarkers`）與規範版本具名查核皆為 **best-effort 正則／門檻比對**，非完整語意分析——第一道結構性保證（`kind` 白名單、函式簽章無禁止參數）才是真正的硬保證；第二道防線「抓得到就多一層防線，抓不到不代表乾淨」。已用真實內容（T-11 smell 基線 asset、真實 Spec §5.2 摘錄）與人為污染樣本雙向驗證過（群組 N），仍可能有涵蓋不到的夾帶手法（例如刻意拆散關鍵詞）。
- `isolationDecisionRecorded`（SC-DEC-ISO-001 是否已落檔）由交件欄位表示，本檔不直接讀取 plugin repo DECISIONS.md——理由是避免與 `../t10/` 既有的 DECISIONS.md 讀取職責重複實作（DRY）；Commander 應在呼叫本檔前先查過並填入交件。
- 驗收④「actor 為 bot」的動態驗證 deferred-to-CI（見上），程式路徑與離線 mock 已完整涵蓋兩模式，本沙盒無法連真實 GitHub 實跑。
- 未附獨立動態 GitHub 測試腳本（如 `../t10/t10-test.ps1`）：ticket 面交付清單為「實作腳本、離線測試、README」，未列動態測試；`station5-check.ps1` 的 Check／Verify 兩模式本身即為可直接對真實 GitHub 執行的生產程式碼（已用 CLI smoke test 驗證邏輯正確跑到 PAT 讀取為止，見 `t15a-quality-gates.txt` bug①），此為刻意的 scope 收斂，非遺漏。
