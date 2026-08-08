# T-30 · 站 5 A 軸異廠接線與分歧裁決

本交付已把票級 `DECISIONS.md` 的「升兩廠雙審」裁示接到既有站 5：A 軸同時保留 Claude 與外廠兩份獨立審查，B 軸仍只由 Claude 執行。兩份 A 軸 finding 清單原樣並列；重疊只建立參照並標為 `strongest-overlap`，分歧逐筆具名交使用者裁示。每家 A 軸清單各自計算並報出一個軸內 worst issue，不產生跨廠單一 worst。

## 交付檔清單

| 檔案 | 用途 |
|---|---|
| `t30-core.ps1` | 核心純函式庫；複用 T-15a prompt 與 T-28 adapter，實作裁示解析、dispatch、廠別並列、重疊／分歧、各廠 worst 與四欄佇列項 |
| `t30-run.ps1` | 正式 dispatch CLI；留存兩份 A 軸 prompt／input list，執行外廠 A 軸，失敗則具名降級 |
| `t30-gate.ps1` | 正式 gate CLI；讀兩份 A 軸與一份 B 軸報告，寫 gate 結果與 T-21 格式的 comment 佇列檔 |
| `t30-offline-test.ps1` | 完整離線測試及兩個斷言紅燈開關 |
| `fixtures/` | 人造 DECISIONS、diff、spec canary、兩份 A 軸原始 finding、B 軸報告及獨立預期值 |
| `evidence/axis-a-*-input-list.json` | 驗收②要求的兩份實際 A 軸 prompt 輸入清單，可直接核對恰為三類 |
| `evidence/axis-a-*-prompt.txt` | 由 T-15a 組裝器實際產生的 Claude／Gemini A 軸完整 prompt |
| `evidence/gate-result.json` | 兩份廠別清單、重疊、分歧與各自 worst 的正式輸出樣本 |
| `evidence/dispute-queue-item.json` | 最外層陣列的 T-21 comment 佇列檔；陣列項恰四欄 |
| `evidence/red-assertion-failures.txt` | ③與⑤真的失敗的紅燈實錄 |
| `evidence/green-offline.txt` | 關閉紅燈開關後的完整綠燈實錄 |
| `evidence/verification.txt` | BOM、ParseFile、完整離線測試與 CLI smoke 實錄 |

只新增 `build/t30/`；沒有修改 `build/t15a/`、`build/t28/`、`build/station-command/`、Spec 或 tickets。

## 接線與資料界線

`t30-core.ps1` dot-source `../t15a/station5-dispatch-prep.ps1 -FunctionsOnly`，直接使用 `New-AxisAPrompt`／`New-AxisBPrompt`；外廠則直接使用 `../t28/vendor-adapter.ps1` 的 registry、key、四家族 request、逾時／5xx 重試與具名降級。T-30 不另寫第五種 adapter，也不改既有地基。

人造 `DECISIONS.md` 條目格式如下；同一 ticket 的 active 條目必須恰有一筆，否則 fail-closed：

```markdown
## SC-DEC-T30-FIXTURE
- ticket: `T-30-FIXTURE`
- decision: `升兩廠雙審`
- axis: `A`
- provider: `Gemini`
- model: `fixture-model`
- status: `active`
```

dispatch 計畫固定三路：`Claude/A`、`外廠/A`、`Claude/B`。外廠 transport 的離線 mock 實錄證明只被呼叫一次且收到完整 A 軸 prompt；B 軸 provider 的獨立斷言仍為 Claude。

## 驗收條件逐條對應

| 驗收 | 測試落點與獨立預期值 | 本環境實跑 |
|---|---|---|
| ① 裁示後 A 軸由外廠執行、B 軸維持 Claude | 離線測試 A、C；人造 DECISIONS 指定 Gemini；mock transport 呼叫次數固定 literal `1` | PASS |
| ② A 軸只有 diff＋規範清單＋12 smells，不含 spec 原文 | 離線測試 B；兩份 input list 的 kind 與手寫三值陣列比對；`T30-SPEC-CANARY-DO-NOT-SEND-TO-AXIS-A` 只存在 B 軸 | PASS；實際清單與 prompt 在 `evidence/axis-a-*` |
| ③ 兩份 finding 各自完整、順序未跨廠重排 | 離線測試 D；與兩份手寫原始 fixture 的 ID 順序及物件全文逐欄比對 | PASS |
| ④ 兩廠共同 finding 標為重疊 | 離線測試 D；手寫預期只有 `shared-null-check`，結果標為 `strongest-overlap` | PASS，1 個重疊 |
| ⑤ 單廠 finding 具名列為分歧並要求裁示；正式輸出禁兩種票面措辭 | 離線測試 D、F；三筆手寫預期逐筆比對，並掃描正式 gate JSON | PASS，3 個分歧；正式輸出命中 0 |
| ⑥ 外廠不可用則單廠雙軸、具名、gate 不阻塞 | 離線測試 G 與 `t30-run.ps1` CLI smoke；使用不存在的 repo 外連接資料夾，未送網路 | PASS；Gemini／缺少 key／Claude／`gateMayProceed=True` |
| ⑦ A 軸兩份廠別清單各報一個軸內 worst，無跨廠單一 worst | 離線測試 E；手寫預期 Claude=`C-A2`、Gemini=`G-A2`，並查禁止的跨廠 worst 欄位不存在 | PASS；兩個 worst 各屬其廠 |

獨立預期值來源是 `fixtures/claude-axis-a.json`、`fixtures/gemini-axis-a.json` 與 `fixtures/expected-dual-vendor.json` 的手寫 literal；測試不以被測函式輸出反推 expected。詳見 `fixtures/README.md`。

## 紅燈：斷言原文與真實失敗證據

兩個開關均在 `t30-offline-test.ps1` 具名：

- `-SkipVendorSeparation`：**僅供紅燈驗證，正式流程禁用**。
- `-SkipDisputeLanguageGuard`：**僅供紅燈驗證，正式流程禁用**。

紅燈指令：

```powershell
& .\t30-offline-test.ps1 -SkipVendorSeparation -SkipDisputeLanguageGuard `
  -ReportPath .\evidence\red-assertion-failures.txt
```

實跑 exit 1，載入與所有 fixture 讀取均成功，程式確實跑到以下兩個斷言後才失敗：

> `[ASSERTION FAILED] ③ 兩份 finding 清單各自完整、原順序留存，輸出不得合併或跨廠重排`

> `[ASSERTION FAILED] ⑤ 分歧輸出不得含票面禁止的兩種裁決字樣`

摘要為 `PASS=0；FAIL=2`。這是斷言失敗的紅，不是檔案不存在、ParseFile、import 或 collection 失敗。關閉兩個開關後同一測試檔得到 `PASS=46；FAIL=0`、exit 0。

## 使用方式（Windows PowerShell 5.1）

```powershell
Set-StrictMode -Version Latest
cd <plugin repo>\build\t30

# 讀票級裁示、組三路 prompt、執行外廠 A 軸；缺 key 自動具名降級且 exit 0
& .\t30-run.ps1 `
  -Ticket 'T-XX' `
  -DecisionsPath '<repo>\DECISIONS.md' `
  -DiffPath '.\ticket.diff' `
  -SpecPath '.\ticket-spec.txt' `
  -ConnectionFolder 'G:\station-connections' `
  -StandardsRefs 'docs\STANDARDS.md @ commit-abc'

# 三份審查報告到齊後產生 gate 結果與待寫 comment 佇列
& .\t30-gate.ps1 `
  -ClaudeAxisAPath '.\claude-a.json' `
  -ExternalAxisAPath '.\vendor-a.json' `
  -ClaudeAxisBPath '.\claude-b.json' `
  -Repo 'owner/repo' -Issue 30 -Ticket 'T-XX'
```

`t30-core.ps1` 是唯一純函式庫；直接執行會印出三行 usage banner，不會出現 exit 0 零輸出的靜默 no-op。三支會 dot-source 的腳本都先把 CLI 參數保存成 `T30*` 獨有名稱，避開參數 cascade。

## BOM、ParseFile、離線測試與 CLI smoke

- UTF-8 BOM：4/4 支 `.ps1` 首三 bytes 均為 `EF BB BF`。
- ParseFile：4/4，errors=0。
- 完整離線測試：46/46 PASS，0 FAIL，exit 0；全程無網路。
- 紅燈實錄：2 個 assertion failures，exit 1；其餘載入／語法正常。
- CLI smoke 1（純函式庫直接執行）：exit 0 且輸出三行 usage，非零輸出 no-op。
- CLI smoke 2（dispatch 缺 key）：exit 0；具名 `provider=Gemini`、`失敗原因=缺少 key`、`承接者=Claude`、`gate 不阻塞=True`，未送網路。
- CLI smoke 3（gate）：exit 0；一行摘要列 Claude A=3／Gemini A=2／Claude B=1 及各自 worst；另列重疊=1、分歧=3、需裁示=True。
- 佇列實錄：JSON 最外層為陣列；第 1 項鍵恰為 `action,target,payload,source`。

上述驗證實際跑在題目指定的 `/opt/pwsh/pwsh`（PowerShell 7.4.6）；本環境沒有 Windows PowerShell 5.1 執行檔，因此不能誠稱在 5.1 runtime 真跑。四支腳本皆以 `#requires -Version 5.1`、PS 5.1 可用語法與 `Set-StrictMode -Version Latest` 實作，並完成真 PowerShell ParseFile／執行驗證。逐項機器實錄見 `evidence/verification.txt`。

## 誠實聲明與已知界線

- 依使用者明令，本環境沒有連外網、沒有呼叫真實 GitHub API、沒有讀取任何真 key。測試程式內唯一 key literal 是明顯假的 `FAKE-KEY-DO-NOT-USE`；執行時只把它寫入 repo 外暫存目錄，測試結束即刪除，且不寫入執行證據。
- 已實證的是 T-28 transport seam 確實執行、收到完整 prompt、能解析人造成功回應，以及缺 key 的真實降級路徑；未實證 Gemini 現網可用性或真實模型輸出品質。
- 實跑發現 T-28 的唯讀守門會因官方第 9 條 smell 內含英文 `delete` 而誤擋完整基線。因禁止修改已驗收地基，本票以安全佔位 prompt 讓 T-28 完成 request 結構檢查，再由 transport wrapper 只替換既有純文字 prompt 欄位；method、URI、headers、body 結構、key 防護、重試與降級仍全由 T-28 處理。離線測試逐字斷言 transport 所見 prompt 等於證據 prompt。這是具名 workaround，不冒稱 T-28 原守門能直接接受該基線。
- T-31 尚未交付時，外廠回應的業務 JSON schema 不合會明確 throw，不會被誤當作零 findings；錯誤體語意與 usage 記帳仍屬 T-31／T-29 範圍，本票不冒稱完成。
- `matchKey` 是兩份審查輸出的顯式對照鍵；本票不做語意近似比對。相同鍵才標重疊，不同鍵即具名分歧交人裁示。此限制避免 gate 自行猜測兩條 finding 是否相同。
