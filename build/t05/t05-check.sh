#!/usr/bin/env bash
# T-05 驗收：逐條反查 t04-fixture.md 的 78 條在 migration-map.md 是否有對應且「新家」欄非空。
# 用法：
#   ./t05-check.sh                          # 用預設路徑（本檔同層 migration-map.md、上兩層 t04-fixture.md）
#   ./t05-check.sh /path/to/migration-map.md /path/to/t04-fixture.md   # 指定路徑（供紅燈示範用）
#
# 退出碼：0＝78/78 全數命中且新家欄非空（GREEN）；1＝命中率不足（RED，斷言失敗型，非檔案不存在）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP_FILE="${1:-$SCRIPT_DIR/migration-map.md}"
FIXTURE_FILE="${2:-$SCRIPT_DIR/../../t04-fixture.md}"

if [[ ! -f "$FIXTURE_FILE" ]]; then
  echo "FATAL: fixture 檔不存在：$FIXTURE_FILE（這是環境錯誤，不是覆蓋率斷言）" >&2
  exit 2
fi
if [[ ! -f "$MAP_FILE" ]]; then
  echo "FATAL: migration-map 檔不存在：$MAP_FILE（這是環境錯誤，不是覆蓋率斷言）" >&2
  exit 2
fi

python3 - "$MAP_FILE" "$FIXTURE_FILE" <<'PYEOF'
import re, sys

map_file, fixture_file = sys.argv[1], sys.argv[2]
id_re = re.compile(r'^\|\s*([A-Z]{2}-\d{2})\s*\|')

# 1) 從 fixture 抽出分母 78 條 ID（依出現順序，保留重複檢查用 set 即可，fixture 本身不應重複）
fixture_ids = []
with open(fixture_file, encoding='utf-8') as f:
    for line in f:
        m = id_re.match(line)
        if m:
            fixture_ids.append(m.group(1))

if len(fixture_ids) != len(set(fixture_ids)):
    dupes = [x for x in set(fixture_ids) if fixture_ids.count(x) > 1]
    print(f"FATAL: fixture 本身含重複 ID：{dupes}（fixture 已凍結，不應發生）", file=sys.stderr)
    sys.exit(2)

total = len(fixture_ids)

# 2) 從 migration-map 抽出「ID -> 新家欄」對照（5 欄表格：ID|摘要|新家|新條目ID或位置|狀態）
homes = {}
with open(map_file, encoding='utf-8') as f:
    for line in f:
        m = id_re.match(line)
        if not m:
            continue
        rid = m.group(1)
        parts = line.strip().split('|')
        # parts[0] 為開頭空字串；parts[1]=ID, parts[2]=摘要, parts[3]=新家 ...
        home_val = parts[3].strip() if len(parts) > 3 else ''
        homes[rid] = home_val

# 3) 逐條反查
missing = []      # migration-map 完全查無此 ID
empty_home = []   # 有此 ID 但新家欄空白
hit = []

for rid in fixture_ids:
    if rid not in homes:
        missing.append(rid)
    elif homes[rid] == '' or homes[rid] == '-':
        empty_home.append(rid)
    else:
        hit.append(rid)

hit_count = len(hit)
coverage_pct = (hit_count / total * 100) if total else 0.0

print(f"=== T-05 覆蓋率檢查 ===")
print(f"fixture 分母：{total} 條（來源：{fixture_file}）")
print(f"migration-map：{map_file}")
print(f"命中（有對應且新家非空）：{hit_count}/{total}（{coverage_pct:.1f}%）")

if missing:
    print(f"缺對照（migration-map 查無此 ID，共 {len(missing)} 條）：{', '.join(missing)}")
if empty_home:
    print(f"新家欄空白（共 {len(empty_home)} 條）：{', '.join(empty_home)}")

if hit_count != total:
    print(f"ASSERTION FAILED: coverage {hit_count}/{total} != {total}/{total}", file=sys.stderr)
    sys.exit(1)

print(f"ASSERTION PASSED: coverage {hit_count}/{total} == {total}/{total} — GREEN")
sys.exit(0)
PYEOF
