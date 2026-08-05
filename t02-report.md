# T-02 研究報告：gate 執行身分可行性（Cowork 手動階段）

日期：2026-08-05　研究者：researcher（T-02 executor）

## 1. 各路徑判定表

| 路徑 | 判定 | 一句依據 | URL |
|---|---|---|---|
| a. 自建 GitHub App，Cowork 內跑 JWT→installation token | **不可行（現時）** | JWT/installation token exchange 走 `api.github.com`，Cowork session-level git-proxy 攔截「未在 session 授權清單」的**全部**流量（不分 Bash/PAT/內建 GITHUB_TOKEN），`add_repo` 在 Cowork 不存在——與今晚實測（既成事實#1）完全吻合，非單一事件 | [anthropics/claude-code #76248](https://github.com/anthropics/claude-code/issues/76248)；[GitHub Docs：Authenticating as a GitHub App installation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation)（installation token 1hr 效期、curl/SDK 才能生成，無 CLI 內建法） |
| b. Machine user PAT，Cowork 判定＋本機/排程執行寫入（混合架構） | **部分可行** | 技術路徑成立（本機 PAT 今晚已證實可用），但（1）需 Cowork↔本機非同步交接（queue/排程/人工觸發），非 session 內即時 gate；（2）第二人類帳號的 actor 只是普通 user login，**沒有 `[bot]` 徽章**，只滿足「≠ glennisgood3-dev」字面要求，不滿足「獨立 bot」的外觀要求 | 既成事實#3（本機 PAT 今晚已用於 21 issue＋push）；`[bot]` suffix 僅授予 GitHub App 型 actor，一般人類帳號無此機制（見下方 c/d 列的官方文件對照） |
| c. GitHub 官方 remote MCP server（api.githubcopilot.com/mcp）經 claude.ai OAuth 連接器 | **不可行（結構性，非單純 bug）** | 今晚 403「Resource not accessible by integration」與獨立回報的 issue 症狀、時間、無解狀態完全一致，非偶發；**且即使修好**，官方文件明示 user-to-server token 設計目的是「attribute app activity to **a user**」——寫入 actor 本質記為使用者本人，不是獨立 bot，歸因需求死路 | [anthropics/claude-code #80874](https://github.com/anthropics/claude-code/issues/80874)（同症狀、2.1.218、標記 regression、無 workaround）；[GitHub Docs：Generating a user access token for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)（"attribute app activity to a user"）；[support.claude.com/articles/10167454](https://support.claude.com/articles/10167454)（內建 GitHub Integration 唯讀，佐證 claude.ai 官方對 GitHub 寫入本就非一線支援場景） |
| d. GitHub Actions GITHUB_TOKEN 當寫入代理（CI 階段方案） | **可行** | GITHUB_TOKEN 是內建系統帳號（非一般 App），actor 固定顯示 `github-actions[bot]`（user id 41898282），天生獨立於任何人類帳號，timeline/audit log 一律以此身分記錄；不經過今晚已證實失效的 Cowork proxy 或 MCP OAuth 兩條路徑，是唯一有官方文件保證且未受今晚兩次失敗污染的管道 | [GitHub Docs：GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)；[github/community discussion #175332](https://github.com/orgs/community/discussions/175332)（username/email/user id 具體確認） |

## 2. 二擇一總結論

**Cowork 手動階段不能滿足「gate 執行身分 ≠ 使用者」的歸因要求。**

三條「手動階段內執行」的管道全滅：a／b 卡在 Cowork session-level proxy（非權限不足，是 session allowlist 機制性攔截，`add_repo` 不存在＝無解鎖手段）；c 卡在官方 remote MCP 的 user-to-server token 設計本質（即使 403 修好，actor 仍是使用者本人，不是 bug 是架構）。唯一站得住的 d（GitHub Actions GITHUB_TOKEN）需要把「判定」與「寫入」拆到 CI 階段執行，Cowork 手動階段做不到「當下即時判定+歸因寫入」一體化。

**§3.4 timeline 歸因在手動階段失效，須回站 1 重議（建議：歸因延至 CI 階段啟用；手動階段暫以使用者身分寫入 label，不做歸因主張，或延遲寫入等 CI trigger）。**

## 3. DECISIONS.md 條目草案

| 日期 | ID | 類型 | 裁示內容 | 依據 | 裁示人 | 狀態 |
|---|---|---|---|---|---|---|
| 2026-08-05 | SC-DEC-009 | 待裁（回站1重議） | gate 執行身分歸因在 Cowork 手動階段不可行：自建 GitHub App（Cowork proxy 攔截 api.github.com 全流量、add_repo 不存在）、machine user PAT 混合架構（需非同步交接、actor 無 bot 徽章）、官方 remote MCP OAuth（403 且 user-to-server token 設計上歸於使用者本人，非 bug）三路皆死；唯一可行管道為 GitHub Actions GITHUB_TOKEN（actor=github-actions[bot]），但須待歸因搬到 CI 階段才能啟用。建議：手動階段 label 寫入不做 timeline 歸因主張，歸因機制延至 CI 階段啟用 | T-02 研究報告 `t02-report.md`；既成事實#1-4；anthropics/claude-code #76248、#80874；docs.github.com（GitHub App installation/user token、GITHUB_TOKEN） | 待彥揚核 | 待核 |

## 4. 紅燈狀態說明

OAuth 對照組（使用者身分寫入、actor＝使用者）今晚已有等效實證：既成事實#3（本機 PAT 寫入 21 issue＋push，actor 皆為 glennisgood3-dev 本人），可直接引用作為「非歸因基準線」對照。正式紅燈重跑（驗證 CI 階段 GITHUB_TOKEN actor 確實顯示 github-actions[bot]）排在寫入管道打通（即 CI workflow 建置完成）後執行，本報告不涵蓋該次重跑的實測結果。

## 未解問題
- machine user 第二帳號若透過 GitHub App「app-linked user」機制能否取得 `[bot]` 徽章（非本次研究範圍，理論上不行，一般 free 帳號無此選項）——若站1有意保留路徑b，需再查證。
- Cowork `add_repo`／session repo allowlist 未來是否會開放給一般使用者（issue #76248 未見官方時程），影響路徑a的「現時」判定是否會轉為「可行」。
