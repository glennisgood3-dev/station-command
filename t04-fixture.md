# T-04 Fixture — 舊 fleet-command 規則盤點・凍結分母（2026-08-05）

**用途**：本檔為盤點的分母清單，凍結後不得改動。覆蓋率檢查以本檔條目 ID 為準。
**來源**（Google Drive 下載，落地 `/home/claude/t04-sources/`）：
- `SKILL.md`（fleet-command 執行層，fileId 18yMkVeU8bjsDwIw5l5nzMAOMTE2vHcD5，84,462 B）
- `protocol.md`（COMET BRAIN §R v1.7.2，fileId 1K_9t_UkbbIV2RF58Kr2S5k3i5T3QRxtE，34,585 B）
- `protocol-amendments.md`（本地生效層 v0.9.0，fileId 1RzOzSrqIl01S6nUoV4Y-5CDcIEWZ_7bT，109,800 B）

⚠️ 票面寫「A-1～A-35」，實物檔案存在至 **A-37**（另含「永不動」「A-9 R3」「A-9 R8」三個獨立節、A-31/A-32 為具名跳號說明節）。fixture 以實物為準，逐 `##` 節列入。

## 分母：78 條

### protocol.md（16 節，PR-01～PR-16）
| ID | 節名 |
|---|---|
| PR-01 | ROLE & EXECUTION |
| PR-02 | 5 LAWS |
| PR-03 | PIPELINE |
| PR-04 | RED LINES |
| PR-05 | §Q.0 REQUIREMENTS LOCK |
| PR-06 | §Q CHARTER + DUAL/TRI-AGENT + TRACKING |
| PR-07 | §A SUPERVISED AUTONOMY（含 §A.0 NO-HANDS） |
| PR-08 | §F FLEET LIVE |
| PR-09 | §K CODING BEHAVIOR |
| PR-10 | PCR FORMAT |
| PR-11 | HANDOFF FORMAT |
| PR-12 | CHECKPOINT |
| PR-13 | ANTI-DILUTION PROTOCOL |
| PR-14 | USER QUICK COMMANDS |
| PR-15 | PROJECT SIZE ROUTER |
| PR-16 | ON-DEMAND REFERENCE（含「動手前要跑什麼」表） |

### SKILL.md（23 節，SK-01～SK-23）
| ID | 節名 |
|---|---|
| SK-01 | 為什麼獨立成一層 |
| SK-02 | 第一原則：不寫死任何 specific case |
| SK-03 | 四層地圖（0.4.0） |
| SK-04 | 摩擦遙測（0.3.0） |
| SK-05 | 一級來源（context 紀律，0.2.0・A-7） |
| SK-06 | lint（0.2.1・A-7 的程式強制層） |
| SK-07 | A-9 審核官（0.4.1・三段流程） |
| SK-08 | 心跳迴圈（含 0～5 步與 blocker 紀律） |
| SK-09 | 不可逆動作前的強制檢查（指標節，本體 A-5） |
| SK-10 | 看板必須由 state 導出 |
| SK-11 | 相關檔案 |
| SK-12 | v0.5.0 機器規則層（lint）現況（L1–L13/M1–M8） |
| SK-13 | v0.6.0 L14 blocker 複查強制 |
| SK-14 | v0.7.0 收據綁定與派工信封（Turn-end 五支/決策指紋/喚醒協定/常設裁決） |
| SK-15 | 站序鎖（Pocock 五站） |
| SK-16 | 站 4/5 自閉環（v0.28.0，含安裝狀態閘、merge 授權五判準、守衛 G1–G5） |
| SK-17 | 一體性修訂：v0.28.0 七處衝突 |
| SK-18 | 站 3 出口 gate — 兩廠 × 三軸（v0.9.0/v0.10.0） |
| SK-19 | 腳本真相源鐵則 |
| SK-20 | 打包前檢查（v0.8.1） |
| SK-21 | Subagent 上限的執行層（v0.12.0） |
| SK-22 | spec 層機械檢查 spec_lint.py（v0.12.1） |
| SK-23 | 防重複改的四個機制（v0.13.0，含決策索引、agent 兩道閘） |

### protocol-amendments.md（39 節，AM-01～AM-39）
| ID | 條號/節名 |
|---|---|
| AM-01 | A-1 rework 換手分級 |
| AM-02 | A-2 gate 轉 AUTO 的前提 |
| AM-03 | A-3 [S] 專案 batch gate |
| AM-04 | A-4 executor transport 偏好 |
| AM-05 | A-5 §A.6 不可逆動作前的強制檢查 |
| AM-06 | A-6 升級格式 — 決策就緒包 |
| AM-07 | 永不動（四條不得放寬） |
| AM-08 | A-7 一級來源紀律（含 A-7.5 引述紀律） |
| AM-09 | A-8 registry 廢止・執行時狀態統一 |
| AM-10 | A-9 獨立審核官 |
| AM-11 | A-9 R3 審核官取證權 |
| AM-12 | A-10 專案儲存紀律（兩界必備＋runtime 宣告） |
| AM-13 | A-11 共識觸發點界定（＋Charter 未完成禁花費） |
| AM-14 | A-12 時間紀律 |
| AM-15 | A-13 授權邊界不可外推 |
| AM-16 | A-14 忙碌不等於進展 |
| AM-17 | A-15 執行層機器規則必須入文 |
| AM-18 | A-9 R8 審核官成本方案 |
| AM-19 | A-16 blocker 複查 |
| AM-20 | A-17 預先授權清單（雙層落點） |
| AM-21 | A-18 §A.5 升級後的判例回寫 |
| AM-22 | A-19 升級包的 A-6 執行合規自查 |
| AM-23 | A-20 兩條操作面教訓 |
| AM-24 | A-21 自主性提升包（A-21.1～A-21.5） |
| AM-25 | A-22 兩廠共識 FAIL＝自動修正迴圈入口 |
| AM-26 | A-23 executor session 輪替紀律（含⑧⑨） |
| AM-27 | A-24 五站裝配線（A-24.1～A-24.5.1） |
| AM-28 | A-25 writing-great-skills 三心法 |
| AM-29 | A-26 名詞表制度 |
| AM-30 | A-27 ADR 制度 |
| AM-31 | A-28 Pocock Workflow 至上條款 |
| AM-32 | A-29 兩個結構性缺口的堵法（A-29.1～A-29.4） |
| AM-33 | A-30 站 5 審查：兩軸 × 兩廠、廢除信心分數 |
| AM-34 | A-34 行為準則一律進「必定讀取」層 |
| AM-35 | A-31・A-32 編號說明（跳號佔位，兩條不存在） |
| AM-36 | A-33 根因鐵律＋決策不得默默翻案 |
| AM-37 | A-35 必讀層補完＋同一條規則只准有一個家 |
| AM-38 | A-36 全域矛盾稽核 |
| AM-39 | A-37 「不矛盾但完全錯誤」稽核 |
