# station-command 格式模板（T-07）

依據 `Spec_station-command_v1.5.md` §3.1 逐字對齊。三種格式：work ID、primary anchor body、milestone description。

---

## 1. work ID

> §3.1：「**work**：以 **work ID**（`W-<slug>`，全艦隊唯一）識別。**work ID 是聚合唯一鍵；milestone 名稱僅供顯示**。」

規則：

- 前綴固定 `W-`，後接 `<slug>`。
- **全艦隊唯一**（跨所有 repo、所有 work 不得重複）；面板聚合（§4.2）以此鍵分組，milestone 名稱僅供顯示、不作鍵值。
- `<slug>` 組字慣例（spec 未逐字規定字元集，此為落地慣例，供 apply/verify 腳本與面板一致比對）：小寫英數字與連字號 `-`，不含空白／底線／大寫。

範例：`W-station-command-panel`

---

## 2. primary anchor body

> §3.1：「**primary anchor issue**：每工作**有且僅有一張**，住在具名的 **primary repo**；帶 `sc:work`，body 宣告 primary repo 與**參與 repo 全集**（此宣告即 repo 全集的真相源，面板不另猜）。」

Body 格式（首段為機讀宣告區，逐字鍵值）：

```
work-id: W-<slug>
primary-repo: <owner>/<repo>
participating-repos:
- <owner>/<repo>          # 含 primary repo 自身在內的參與 repo 全集
- <owner>/<repo-2>
- <owner>/<repo-n>

<以下為人讀敘述，工作描述、脈絡等>
```

- label：建立時寫 `sc:work`（型別 label，不可變，§3.3）。
- `participating-repos` 即 §3.1 所稱「參與 repo 全集」的**唯一真相源**；面板不另猜、不逐 repo 探測。
- `sc:station-*` 系列 label **只存在此 anchor 上**；其他 issue 上出現一律視為髒資料並具名示警（§3.1）。

---

## 3. milestone description

> §3.1：「**milestone**：每個參與 repo 各建一個同 work 的 milestone，description 首行帶 `work-id` 與 `primary-anchor`（repo#issue）。只負責分組與**原生進度百分比**。」

每個「參與 repo」各建一個同 work 的 milestone，description 首行格式：

```
work-id: W-<slug> | primary-anchor: <owner>/<repo>#<issue-number>
```

- 首行之後可接人讀補充說明（不影響機讀解析，僅首行參與聚合）。
- milestone 僅負責分組（依 work-id）與 GitHub 原生進度百分比；不承載狀態真相（狀態真相在 label／anchor body，§3.1、§4.1）。
