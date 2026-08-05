# station-command

Cowork plugin：五站生產線的薄編排層。狀態機 gate、GitHub 為真相源、常駐面板、兩層 executor 路由——本身不做任何實作，deliverable 一律 dispatch 給 ak-engineer。

## 正典文件
- 完整規格：[`Spec_station-command_v1.5.md`](./Spec_station-command_v1.5.md)
- 早期共識裁示（全文）：[`ADR.md`](./ADR.md)
- 逐條裁示紀錄（追加式）：[`DECISIONS.md`](./DECISIONS.md)
- 名詞定義：[`GLOSSARY.md`](./GLOSSARY.md)
- 版本沿革：[`CHANGELOG.md`](./CHANGELOG.md)

## 五站
1. grill——共識拷問，產名詞表與 ADR
2. spec——結構化計畫，第三方缺口審把關
3. tickets——垂直切片拆票，含 executor／basis／驗收條件
4. implement——先紅後綠，verifier 實測後標 `sc:red-proven`
5. 雙審——兩軸 parallel fresh-context 審查，通過後關票
