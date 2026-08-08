#!/usr/bin/env bash
# T-06 紅燈腳本：檢查 station-command plugin 骨架是否齊備
# 用法：bash check_skeleton.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/station-command"
PLUGIN_JSON="$ROOT/.claude-plugin/plugin.json"

declare -a SKILLS=(station-board station-run station-gate station-intake)
GATE_SKILL="station-gate"
GATE_MARKER="寫狀態 label"
PROHIBIT_MARKER="禁"

FAIL_LIST=()

# 1. plugin.json 存在
if [[ ! -f "$PLUGIN_JSON" ]]; then
  FAIL_LIST+=("plugin.json 不存在：$PLUGIN_JSON")
fi

# 2. 四個 SKILL.md 存在
for s in "${SKILLS[@]}"; do
  f="$ROOT/skills/$s/SKILL.md"
  if [[ ! -f "$f" ]]; then
    FAIL_LIST+=("SKILL.md 不存在：$f")
  fi
done

# 3. 只有 gate 的檔案含「寫狀態 label」字樣；其餘三份不得含此字樣
for s in "${SKILLS[@]}"; do
  f="$ROOT/skills/$s/SKILL.md"
  [[ -f "$f" ]] || continue
  if [[ "$s" == "$GATE_SKILL" ]]; then
    if ! grep -q "$GATE_MARKER" "$f"; then
      FAIL_LIST+=("$s/SKILL.md 缺少「$GATE_MARKER」字樣（gate 應含寫狀態 label 指示）")
    fi
  else
    if grep -q "$GATE_MARKER" "$f"; then
      FAIL_LIST+=("$s/SKILL.md 不應含「$GATE_MARKER」字樣（僅 gate 得含此指示）")
    fi
  fi
done

# 4. 其餘三份（非 gate）須含「禁」字樣的白名單宣告
for s in "${SKILLS[@]}"; do
  [[ "$s" == "$GATE_SKILL" ]] && continue
  f="$ROOT/skills/$s/SKILL.md"
  [[ -f "$f" ]] || continue
  if ! grep -q "$PROHIBIT_MARKER" "$f"; then
    FAIL_LIST+=("$s/SKILL.md 缺少「$PROHIBIT_MARKER」字樣的明文禁令宣告")
  fi
done

if [[ ${#FAIL_LIST[@]} -eq 0 ]]; then
  echo "PASS: 骨架檢查全數通過"
  exit 0
else
  echo "FAIL: 共 ${#FAIL_LIST[@]} 項未通過"
  for item in "${FAIL_LIST[@]}"; do
    echo "  - $item"
  done
  exit 1
fi
