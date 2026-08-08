# 兩層 executor 路由表 v1

> 逐字轉錄自 `Spec_station-command_v1.11.md` §5.1（含表格、表後「防作弊主力的階段性位置」註記、及下方「provider 維度」段）；表格內容自 v1.5 至 v1.11 未變動，本次僅更新版本標註並補轉錄 provider 維度段落（T-27，2026-08-08）。第二層規則轉錄自同檔 §5.1 表後段。版本與 plugin 綁定；spec 修訂時本檔須同步更新，不得各自漂移。

## 第一層：站 → 預設 executor（Spec §5.1 原文表）

| 站 | 預設 executor | basis |
|---|---|---|
| 1 grill | `brainstormer`（產題）＋ `advisor`（挑戰取捨）；`ak-brainstorm` | 拷問需要「發散」與「逆向挑戰」兩種人格，同一顆腦袋兩者互相稀釋 |
| 2 spec | `planner` ＋ `ak-plan`（需 `/ak-cli-setup`） | spec 是結構化計畫產物，planner 產出格式穩定、可被站 3 直接消費 |
| 2 出口 gate | `kongming`（fresh context） | 缺口審要求最強推理且不得是產出者本人 |
| 3 tickets | `planner` 拆票 ＋ `kongming` 複核；`ak-project-management` | 垂直切片切錯要到站 4 才爆，複核成本遠低於返工 |
| 3 出口 gate | `code-reviewer`（票集完備性） | 判的是欄位完備與可執行性，屬規範型檢查 |
| 4 implement | `fullstack-developer` ＋ `ak-cook`／`ak-test`；卡關轉 `debugger`／`ak-debug` | 先紅後綠需要真的能跑測試的執行體 |
| 4 驗收 | `tester`（verifier，≠ executor） | 執行者自陳不能當驗收；`sc:red-proven` 依其實測結果落在票上 |
| 5 雙審 | 同環境、平行、fresh-context 的兩個 `general-purpose` sub-agent，各執一軸 | 依 **ADR-NP-007**：隔離靠輸入分離與平行不互通，不靠廠牌 |
| 全站 | `git-manager`｜`docs-manager`｜`Explore`／`ak-scout`｜`project-manager`（對帳） | 支援角色，不佔站別主線 |

**防作弊主力的階段性位置**（與名詞表一致）：手動階段在**站 4 verifier 實測**；升 CI 後回到**站 5 的 manifest 重放**。

## 第二層：每票覆寫（Spec §5.1 原文）

站 3 拆票時每張票必填 executor＋basis；覆寫預設須在 basis 說明理由。無 basis ⇒ `[INVALID]`。

## executor 欄語意擴充：provider 維度（依 ADR-NP-011，T-27 併同 T-11 asset 一併執行）

Spec §5.1「provider 維度」段逐字：

> "provider 維度（依 ADR-NP-011）：executor 由「agent 名」擴為「provider ＋ model」。上表未標 provider 者一律為內建 Claude sub-agent（AgentKit 16 agent 皆是，差別只在 system prompt 與模型層級）。"

適用到本檔：上表（第一層、第二層）**未標 provider 者一律為內建 Claude sub-agent**，可省略 provider 前綴；若票面 basis 選用異廠 provider，executor 欄改寫為 `provider＋model`（例：`Gemini＋gemini-2.5-flash`），並在 basis 具名理由（此為本節新增之適用說明，非逐字轉錄）。

異廠可登錄的 provider 清單、認證方式、格式家族與可用狀態，正典位置為**廠商登錄表**（隨 plugin 出貨的獨立 asset，`build/station-command/assets/vendor-registry.md`／T-27 產出、與本檔同居 `assets/` 出貨；不併入本檔，因兩表用途不同——本檔是「站對應誰執行」，廠商登錄表是「誰可被執行、缺什麼」）。

## 正典位置

本表正典＝ `Spec_station-command_v1.11.md` §5.1；本檔僅為隨 plugin 出貨的逐字轉錄版本，供 `/station-run` 等 skill 於 dispatch 時查閱，不另行修改語意。若兩者不一致，以 spec §5.1 為準。
