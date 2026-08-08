# T-21 · 佇列項產生權不變式規格

依 `Spec_station-command_v1.8.md` §4.6：「**產生權**：佇列項的產生權＝該動作原本的唯一寫入者——label／開關 issue 類只能由 gate 產生，issue 與 milestone 建立只能由 intake 產生，assignee 與留言由 run 產生。🚫 不得因為『只是寫檔』就繞過 §3.3 的寫入者不變式。」

本檔是**規格文件**——它定義「哪個 skill 能產生哪類佇列項」的不變式與違反時的判定行為。**實際強制點在各 SKILL.md**（於 T-24 各 skill 落地 loop 邏輯時接上：每個 skill 在自己準備寫入佇列檔前，先依本規格自查動作類型是否屬於自己的產生權範圍）。T-21 本身只交付規格與套用／對帳腳本，**不修改任何 SKILL.md**（不在 T-21 file ownership 內）。

## 1. 不變式核心

> **佇列只是「原本要寫 GitHub 的動作」延後到本機腳本執行，寫入者的身分規則不因此改變。**

`queue-format.md` §3 定義的五種動作類型，其產生權**逐一對應 §3.3 的合法寫入者**：

| 佇列動作類型 | 對應 §3.3 的合法寫入者 | 唯一產生者（skill） |
|---|---|---|
| `set-labels` | 所有狀態 label（`sc:station-*`、`sc:legacy`、`sc:red-proven`、`sc:blocked`、`sc:gate-fail`、`sc:awaiting-user`）的寫入者＝gate | **`/station-gate`** |
| `close-issue`（含開／關 issue、關 milestone 的等價動作） | §3.2「gate 寫 `sc:station-done`、關閉 primary anchor、關閉全參與 repo 的對應 milestone」；§6「站 5 通過後關票」 | **`/station-gate`** |
| `create-issue` | §2 intake 白名單「建 issue 並附類型 label `sc:work`」；§3.3 `sc:ticket` 由「建立者（站 3 拆票 dispatch）」建立——但**開票動作本身**（產生 issue 這個節點）在 native／legacy 進線與 legacy 收編情境下歸 intake；站 3 拆票走 dispatch 直接建票、不進佇列（見 §3 附註） | **`/station-intake`** |
| `create-milestone` | §2 intake 白名單「建 milestone」 | **`/station-intake`** |
| `comment` | §3.4「gate 得留人讀留言」；§2 run 白名單「寫人讀留言」；§5.3a「痕跡與通知...屬留言類寫入」 | **依原動作歸屬**（見 §2 本檔） |

**關鍵不變式**：`set-labels` 與 `close-issue` 兩型**恆為 gate 專屬**——即便某個 label 動作「看起來只是加個 `sc:blocked`」或「看起來只是關個票」，只要動作類型是這兩型，產生者只能是 gate。**run 不得產生這兩型**（run 的白名單明文「🚫 不寫任何 label、不開關 issue、不產生 label 類佇列項」）。

## 2. `comment` 型的「依原動作歸屬」判準

`comment` 不像 label／issue 建立那樣單一寫入者，而是**跟著發起該次留言的原動作走**：

- `/station-run` 產生的 comment：派工通知、收件摘要、loop 停因通知、批次摘要（§5.3a／§5.3b 相關留言）。
- `/station-gate` 產生的 comment：gate 判定結果留言、初始化報告（§6.1⑤ 身分具名回報）、復位模式回報（§3.4）。
- `/station-intake` 產生的 comment：定站結論、legacy 缺件清單。

判準：**看是哪個 skill 的白名單動作觸發了這則留言**，而不是看留言掛在哪張票上。同一張票上可以同時有 run 產的留言與 gate 產的留言，彼此互不干涉、互不需要一致性。

## 3. 違反時的判定行為

任一 skill 嘗試產生**不屬於自己產生權範圍**的佇列項（例如 run 嘗試寫入一筆 `action: "set-labels"` 的佇列項）：

1. **拒絕**：該筆佇列項**不得被寫入佇列檔**——不是「寫入後再由套用腳本擋下」，而是產生階段就擋（因為套用腳本無法回溯「這筆到底是誰產生的」，佇列四欄本身不記產生者，見 `queue-format.md` §2 的欄位設計）。
2. **具名回報**：該 skill 的執行報告須具名回報「拒絕產生：動作類型 `<action>` 不在本 skill 產生權範圍內（唯一產生者：`<正確 skill>`），本次未寫入佇列」。
3. **不得降級處理**：🚫 不得「改成留言型繞過」（例如 run 想推站別就改成留一則『建議推進到站 N』的留言而非真的產生 `set-labels`）——那樣會製造「留言看起來像已推進但其實沒有」的混淆，違反 §3.4「留言不參與任何判定」的邊界，也違反 §5.0 No-Hands 的產出邊界。正確做法是 run 完成自己的白名單動作（派工、寫 executor／basis、寫 assignee）後**呼叫 gate**，由 gate 依 §6 判定並自行產生 `set-labels` 佇列項。

## 4. 為何佇列四欄不記「產生者」欄位

`queue-format.md` §2 明文四欄為「動作類型｜目標｜payload｜來源票號或 work ID」，**恰好四欄**，不多一欄記產生者。理由：

- 產生權是**產生階段**的不變式（誰有資格把這筆動作放進佇列），不是**套用階段**要消費的資訊——套用腳本（`apply-queue.ps1`）只管把佇列裡已經存在的項目套到 GitHub，不負責回頭稽核「這筆當初是誰產生的」。
- 若佇列項本身可帶假的「產生者」欄位（例如任何 skill 都能在自己產生的 JSON 裡填 `"producer": "gate"` 冒充），這個欄位反而是**可被繞過的假保障**——真正的不變式必須在**產生階段**、由產生者自己的 SKILL.md 邏輯把關（T-24 落地時，每個 skill 在組裝佇列項前先過本檔 §1 表格的自查），而不是靠佇列檔裡一個可以隨便填的字串欄位。

## 5. 本票（T-21）與強制點的邊界

- **T-21 交付**：本規格文件本身，以及 `fixtures/` 中人造佇列項的產生權標註（供未來 SKILL.md 開發者參照）。
- **T-24 交付**（依 `tickets-loop-draft.md`）：`/station-run` 的 loop 主體落地時，須依本檔 §1 表格在「產生佇列項」的程式路徑上加上自查邏輯（拒絕產生越權動作類型並具名回報，見 §3）。
- **T-21 驗收條件⑤**（「以 run 的身分嘗試產生 label 類佇列項 ⇒ 被拒並具名」）的驗證方式：**本票只驗證規格文件本身的完備性**（本檔是否對四類動作各自具名唯一產生者、違反行為是否具名判定，見 `check-t21.sh` 檢查②）；**實際跑 run 嘗試越權並觀察被拒**，須待 T-24 `/station-run` 落地本檔 §3 的自查邏輯後才能動態驗證——此為誠實聲明，非本票規避。
