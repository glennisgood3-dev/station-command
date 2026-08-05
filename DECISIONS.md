# DECISIONS.md（station-command plugin repo）

本檔依 [`Spec_station-command_v1.5.md`](./Spec_station-command_v1.5.md) §8 模板：追加式表格，只追加不改寫；推翻舊條目須開新條目並具名「取代 <舊 ID>」；豁免類必含「本項【未】處理」。
寫入路徑：使用者手寫，或由 gate／intake dispatch `docs-manager`／`git-manager` 開 PR 經使用者確認合併；任何 skill 不得直接 push 寫入預設分支。
以下 8 條為種子條目，對應 ADR-NP-001～008 的裁示摘要；**全文正典見本 repo [`ADR.md`](./ADR.md)**，名詞定義正典見本 repo [`GLOSSARY.md`](./GLOSSARY.md)，本表不重述其論證與被否決方案。

| 日期 | ID | 類型 | 裁示內容 | 依據 | 裁示人 | 狀態 |
|---|---|---|---|---|---|---|
| 2026-08-05 | SC-DEC-001 | 拍板 | 薄編排層：plugin 只含五站狀態機＋面板＋executor 路由表，不複製 ak-engineer 現有 skills／agents，各站 dispatch 出去 | ADR-NP-001 | 彥揚 | active |
| 2026-08-05 | SC-DEC-002 | 拍板 | GitHub 為機器狀態唯一真相源：票＝Issues、站別用 label，面板由 API 現算聚合，不落第二份狀態檔 | ADR-NP-002 | 彥揚 | active |
| 2026-08-05 | SC-DEC-003 | 拍板 | 面板＝Cowork 常駐 HTML artifact，跨 session 存活、就地更新；否決 GitHub Projects board 與 ak-plans-kanban | ADR-NP-003 | 彥揚 | active |
| 2026-08-05 | SC-DEC-004 | 拍板 | DECISIONS.md／CHANGELOG.md 兩本 log 隨各專案 repo 版本控管、PR 可審；protocol 層跨專案正典仍放 Drive | ADR-NP-004 | 彥揚 | active |
| 2026-08-05 | SC-DEC-005 | 拍板 | 兩層 executor 路由：plugin 內建「站→預設 executor」表（含 basis），站 3 拆票可覆寫預設但須具理由，無 basis 即 `[INVALID]` | ADR-NP-005 | 彥揚 | active |
| 2026-08-05 | SC-DEC-006 | 拍板 | Legacy 收編走「審計定站＋關鍵補件」：字卡掛 `legacy` badge 直到過第一個 native gate；關鍵工件必補、次要工件可具名豁免 | ADR-NP-006 | 彥揚 | active |
| 2026-08-05 | SC-DEC-007 | 修改，取代 ADR-NP-005 站 5 格與 A-30「兩廠」條款 | 站 5 雙審回歸 Pocock 原版：兩軸同環境 parallel fresh-context `general-purpose` sub-agent；保留單票逃生口可裁示升兩廠 | ADR-NP-007 | 彥揚 | active |
| 2026-08-05 | SC-DEC-008 | 拍板 | Commander No-Hands：主 session 只做「讀→驗→決→派→記」，一切 deliverable 由 dispatch 的 executor 產生 | ADR-NP-008 | 彥揚 | active |
