#!/usr/bin/env bash
# T-11 紅燈檢查：routing-table.md 列數 == Spec §5.1 列數；fowler-smells.md 12 條標題與一級來源一致
set -uo pipefail

SPEC="/home/claude/station-plugin/Spec_station-command_v1.5.md"
RT="/home/claude/station-plugin/build/station-command/assets/routing-table.md"
FS="/home/claude/station-plugin/build/station-command/assets/fowler-smells.md"

fail=0

# --- 檢查 1：routing-table.md 資料列數 == Spec §5.1 表資料列數 ---
# Spec §5.1 表：抓「## 5.1 路由表」到下一個「###」之間的表格資料列（排除表頭與分隔線）
spec_rows=$(awk '/^### 5.1 路由表/{f=1;next} /^###/{f=0} f' "$SPEC" \
  | grep -E '^\|' | grep -vE '^\|---' | grep -v '^| 站 |' | wc -l)
echo "Spec §5.1 資料列數 = $spec_rows"

if [ ! -f "$RT" ]; then
  echo "[RED] routing-table.md 不存在"
  fail=1
else
  rt_rows=$(grep -E '^\|' "$RT" | grep -vE '^\|---' | grep -v '^| 站 |' | grep -E '^\| (1|2|3|4|5|全站)' | wc -l)
  echo "routing-table.md 資料列數 = $rt_rows"
  if [ "$rt_rows" != "$spec_rows" ]; then
    echo "[RED] 列數不符：routing-table=$rt_rows spec=$spec_rows"
    fail=1
  else
    echo "[GREEN] 列數相符"
  fi
fi

# --- 檢查 2：fowler-smells.md 12 條 smell 且標題與一級來源一致 ---
declare -a TITLES=(
  "Mysterious Name"
  "Duplicated Code"
  "Feature Envy"
  "Data Clumps"
  "Primitive Obsession"
  "Repeated Switches"
  "Shotgun Surgery"
  "Divergent Change"
  "Speculative Generality"
  "Message Chains"
  "Middle Man"
  "Refused Bequest"
)

if [ ! -f "$FS" ]; then
  echo "[RED] fowler-smells.md 不存在"
  fail=1
else
  count=0
  missing=""
  for t in "${TITLES[@]}"; do
    if grep -qF "$t" "$FS"; then
      count=$((count+1))
    else
      missing="$missing|$t"
    fi
  done
  echo "fowler-smells.md 找到標題數 = $count / 12"
  if [ "$count" != "12" ]; then
    echo "[RED] 缺少標題: $missing"
    fail=1
  else
    echo "[GREEN] 12 條標題全數一致"
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "=== ALL GREEN ==="
else
  echo "=== RED ==="
fi
exit $fail
