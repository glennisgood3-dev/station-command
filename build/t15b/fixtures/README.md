# T-15b 人造 fixture

四份 fixture 的 `expected` 區塊由實驗者依票面與 Spec §3.2 預先寫定，`work-complete.ps1`
完全不讀這個區塊；只有離線測試拿它當獨立預期值來源，避免用被測程式自己的輸出自證。

| fixture | 人造條件 | 獨立預期 |
|---|---|---|
| `all-gate-closed.json` | 3 張票皆 closed，最後關票 actor 均為 `station-gate-bot`，跨 2 repo | `complete`；1 筆 set-labels、1 筆 close-issue、2 筆 close-milestone |
| `human-closed.json` | 零 open，但其中 1 張最後由 `human-user` 關閉 | `awaiting-user`；只准 1 筆 set-labels，不准關 anchor／milestone |
| `no-tickets.json` | tickets 是真正空陣列 | `no-tickets`；最小站公式不適用、0 筆佇列 |
| `open-ticket.json` | 恰 1 張 open 票 | `incomplete`；不進完成態、0 筆佇列 |
