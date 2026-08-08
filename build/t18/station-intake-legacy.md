# `/station-intake` legacy 模式增補（掛在 `../t08/station-intake/SKILL.md` 之下）

依票面「legacy 模式共用 native 建立步驟」——本票**不新建**一份 `station-intake/SKILL.md`（那會
造成兩份互相漂移的 intake skill 定義，違反 SC#8 薄度與 DRY），比照 `../t13/station-gate-
supplement.md` 對 `../t10/station-gate/SKILL.md` 的既有先例：另立補充文件，**不修改**
`../t08/station-intake/SKILL.md`（file ownership 邊界）。

`../t08/station-intake/SKILL.md` 目前明文範圍鎖：「🔒 本檔案範圍鎖（T-08）：只實作 native 模式。
legacy 模式（fresh-context auditor、定站退回、補件清單、豁免草案）不在本票範圍，留待後續票。」
本檔正是把那段留白補上。

## 動作白名單（延續母檔宣告，未新增動作類型）

母檔已宣告的白名單為：「讀 GitHub｜建 milestone｜建 issue 並附類型 label `sc:work`｜dispatch
auditor（legacy 專用，本票不實作）｜呼叫 gate 初始化路徑。🚫 不寫任何狀態 label」。本增補**不
新增任何動作類型**——`dispatch auditor` 母檔已預留位置，本檔把它填上；legacy 模式產生的
`create-issue`／`create-milestone` 佇列項與 native 模式同形狀（見下）；legacy 模式**依然不寫任何
狀態 label**——`sc:station-N` 與 `sc:legacy` 兩者的寫入者仍是 gate（`/station-intake` 只負責呼叫
gate 初始化路徑，見 §6.1 與本檔「Stage C」段）。

## §7.1 建立步驟（native 與 legacy 共用）如何在程式碼層體現

Spec §7.1：「legacy 模式**不得跳過本步驟**——否則首個 label 無載體。」`legacy-intake.ps1` 的
Stage A（primary anchor）／Stage B（milestones）**直接重用 `../t08/intake-native.ps1` 的既有
函式**（`Find-AnchorByWorkId`／`Find-MilestoneByTitle`／`Get-AnchorDeclaration`／
`Test-MilestoneDescriptionFormat`／`Add-QueueItemIfAbsent`，dot-source `-FunctionsOnly` 取得，
不重寫）——產生的 `create-issue`／`create-milestone` 佇列項與 native 模式**逐位元組相同的 body
模板**（依 `../t07/templates.md`）。

⚠️ **為何不直接呼叫 t08 的 `Invoke-IntakeNativeFlow` 整個函式**（誠實聲明，非偷懶）：該函式內部
用 `Join-Path $PSScriptRoot 'intake-native-report.txt'` 寫報告檔——**dot-source 後 `$PSScriptRoot`
仍綁定 t08 檔案自身的目錄**（PowerShell 對 `$PSScriptRoot` 採詞法作用域，由函式「定義所在的檔
案」決定，不是呼叫端目錄），若直接呼叫該函式，會把報告檔寫進 `../t08/`，**違反 file ownership**
（本票不得修改 `build/t08` 任何檔案，寫入新檔一樣算違反）。且該函式跑完 Stage A／B 後只要偵測到
anchor＋milestone 皆存在就會**接著執行 native 專屬的 Stage C**（永遠往 anchor 加
`sc:station-1`）——legacy 情境下這是錯的（legacy 的站別由 auditor 判定，不是恆為站 1）。故本檔
只重用「原子」層級的函式（讀 anchor／讀 milestone／組 body／寫佇列項），自己組裝 Stage A／B 的
迴圈邏輯（讀 `legacy-intake.ps1` 內 `Invoke-LegacyIntakeFlow` 的 Stage A／B 段），**函式呼叫序列
與產生的佇列項內容與 t08 native 模式完全一致**，只是呼叫序列由本檔的迴圈驅動而非 t08 自己的
`Invoke-IntakeNativeFlow`——這就是「共用同一套建立步驟」在避開 file-ownership 陷阱後唯一站得住
的實作方式。

## 步驟（legacy 模式，接續母檔步驟 0-2 之後）

沿用母檔步驟 0（收集 work ID／primary repo／參與 repo 清單）與步驟 1（work ID 唯一性初步檢查）。
步驟 2-3（建 anchor／建 milestone）**改呼叫 `legacy-intake.ps1`**（見上，非母檔步驟 2-3 的 native
版本，但佇列項形狀相同）。

## 步驟 4（legacy 專屬）：dispatch fresh-context auditor

Stage A／B 完成（anchor＋全部 milestone 皆已落地於 GitHub）後，dispatch 一個 fresh-context
sub-agent 執行 `auditor-prompt.md` 定義的稽核（**Commander 不得自己讀 repo 工件後代 auditor
下判斷**——那會讓「審查者」與「產出者」混為一談，違反 §5.0 No-Hands；也不得把 Commander 自己
之前與使用者討論 legacy 收編這件事的過程對話餵給 auditor，見 `auditor-prompt.md` 禁餵清單）。
auditor 回報 `auditor-prompt.md` 定義的 JSON 結構，存成檔案（例如
`auditor-findings.json`）供 `legacy-intake.ps1 -AuditorFindingsPath` 消費。

## 步驟 5（legacy 專屬）：定站封頂＋`sc:legacy` 標記

呼叫 `legacy-intake.ps1`（Stage C）：內部 dot-source `../t08/intake-native.ps1 -FunctionsOnly`
重用 `Test-GateInitCriteria` 的判準①②③④（milestone／anchor 宣告／work ID 唯一性／anchor 無既有
站別 label，**與 native 模式完全相同的判準，不另立一套**，對應 §6.1「本段的完整規格與程式碼
皆由 T-08 交付」）；判準⑤（身分回報，不作 fail 條件，同 native）。①②③④全過後，**不像 native
模式恆定 `sc:station-1`**，改呼叫 `Get-AuditorCandidateStation`（讀 auditor findings）＋
`Test-LegacyStationCap`（定站上限站 3，見 `README.md`「紅燈設計」）算出最終站別，產生
**單一筆** `set-labels` 佇列項，`payload.labels` 含 `sc:work`／determined station／`sc:legacy`
三者（一次寫完整集合，依 §3.4 原子性不變式，與 native／T-10 既有作法一致）。

## 步驟 6：回報「定站」結論（比照母檔步驟 5）

向使用者輸出：auditor 逐條 ✓／✗／N/A 與證據指向（`Format-AuditorReport`）、定站結果與 cap 是否
介入、缺件分類（關鍵／次要）、若定站＝3 且尚未補齊 §3.5 八欄位，提示 §7.3 兩條路徑（補齊八欄位
掛 `sc:ticket`／不收編改記 DECISIONS.md）。

## 產生權（`../t21/enqueue-guard.md`，未新增機制）

`create-issue`／`create-milestone`＝intake 產生權（Stage A／B，重用 t08 判準與函式）；
`set-labels`（`sc:legacy` ＋ determined station）＝gate 產生權（Stage C，本檔的 Stage C 扮演的
正是「呼叫 gate 初始化路徑」這件事，比照 native 模式母檔步驟 4 的定位——**不是** intake 自己越權
寫狀態 label）。

## 🔴 「不改寫舊票」守門在本流程的落點

Stage A／B／C 全程**只對 anchor 與 milestone 做動作**，從不對既有舊票（`tickets/` 目錄下那些
自由格式票對應的 GitHub issue）產生任何 `set-labels`／`close-issue`／`comment` 佇列項。
`legacy-intake.ps1` 的 `Test-LegacyTicketProtectionGuard`（經 `Add-Station18QueueItemIfAbsent`
包裹後成為所有佇列寫入的必經路徑）是這條不變式的**程式碼層守門**（不是只有本文件宣告），見
`README.md`「不改寫舊票的程式碼層守門」一節與 `t18-offline-test.ps1` 群組 F 的守門測試
（F1-F5：對受保護舊票的 `set-labels`／`close-issue` 一律 `Blocked=true` 且確認佇列檔未落地；
對非保護清單內目標與無 `issue` 欄位的 `create-issue`/`create-milestone` 型佇列項則不誤擋）。
