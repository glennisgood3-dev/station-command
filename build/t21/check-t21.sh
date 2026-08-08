#!/usr/bin/env bash
# T-21 紅燈先行：靜態檢查（沙盒可跑，不連 GitHub）。
# ⚠️ 誠實聲明：本腳本只做「檔案內容是否含正確設計元素」的靜態檢查，
#    不能替代實跑冪等驗證（Spec 驗收 ②③④⑥）——那些須使用者在本機以真實 GitHub API 跑過才算數。
#
# 檢查①【冪等】apply-queue.ps1／queue-common.ps1 是否含「套用前先讀現況比對」的邏輯段，
#           且未採用 §4.6 明文禁止的「動作指紋」比對方式。
# 檢查②【產生權】enqueue-guard.md 是否對四類動作（label／issue 建立／milestone 建立／comment）
#           各自具名唯一產生者。
#
# exit 0 = 全綠；exit 1 = 有紅燈項目。

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY="$DIR/apply-queue.ps1"
COMMON="$DIR/queue-common.ps1"
GUARD="$DIR/enqueue-guard.md"

fail=0
say() { printf '%s\n' "$*"; }

say "=== check-t21.sh 執行於 $(date '+%Y-%m-%d %H:%M:%S %z') ==="
say ""
say "--- 檢查① 冪等：套用前讀現況比對，且不用動作指紋 ---"

idempotent_ok=1

if [[ ! -f "$APPLY" ]]; then
  say "[RED] apply-queue.ps1 不存在：$APPLY"
  idempotent_ok=0
else
  # 合併 apply-queue.ps1 與其可能 dot-source 的 queue-common.ps1 一起找關鍵字
  # （冪等邏輯允許拆到共用檔，只要 apply-queue.ps1 有引用即算數）。
  combined=$(cat "$APPLY" 2>/dev/null; [[ -f "$COMMON" ]] && cat "$COMMON" 2>/dev/null)

  # 必須要有「先讀現況」的具名函式或段落標記
  if echo "$combined" | grep -qiE '已達成.*跳過|Test-.*Satisfied|Get-Current.*State|讀現況'; then
    say "[GREEN] 找到「讀現況比對」邏輯段（已達成 payload 狀態即跳過）"
  else
    say "[RED] 未找到「套用前讀現況比對」邏輯段（缺 Test-*Satisfied / Get-Current*State / 讀現況 關鍵字）"
    idempotent_ok=0
  fi

  # 必須在「讀現況」與實際寫入呼叫之間有先後關係佐證：readonly GET 呼叫需存在
  if echo "$combined" | grep -qiE '\-Method[[:space:]]+Get'; then
    say "[GREEN] 找到套用前的 GET 現況呼叫"
  else
    say "[RED] 未找到任何 -Method Get 的現況讀取呼叫"
    idempotent_ok=0
  fi

  # 必須有套用後回驗（再讀一次確認相符才出列）
  if echo "$combined" | grep -qiE '回驗|Verify|再讀'; then
    say "[GREEN] 找到「套用後回驗」邏輯段"
  else
    say "[RED] 未找到「套用後回驗」邏輯段"
    idempotent_ok=0
  fi

  # 🚫 不得使用動作指紋（hash/fingerprint）當冪等判準——§4.6 明文「不設動作指紋」
  # 只抓「真的在算雜湊當比對鍵」的程式碼型樣（ComputeHash/MD5/SHA/GetHashCode/actionFingerprint 變數），
  # 不誤判註解裡「不設動作指紋」這類否定敘述本身。
  if echo "$combined" | grep -qiE 'ComputeHash|MD5\.|SHA(1|256)\.|GetHashCode\(\)|actionfingerprint|action_fingerprint'; then
    say "[RED] 偵測到疑似「動作指紋」比對邏輯（雜湊函式呼叫）——§4.6 明文禁止，冪等只能靠讀現況比對"
    idempotent_ok=0
  elif echo "$combined" | grep -qiE '不設動作指紋'; then
    say "[GREEN] 明文聲明「不設動作指紋」且未偵測到雜湊型比對程式碼，符合規定"
  else
    say "[RED] 未見「不設動作指紋」的具名聲明，且無法確認未使用雜湊型比對"
    idempotent_ok=0
  fi

  # label description 長度守門（今日實測 114 字元回 422，需送出前擋下）
  if echo "$combined" | grep -qiE '100|description.*Length|Length.*description'; then
    say "[GREEN] 找到 label description 長度守門（≤100 字元）邏輯"
  else
    say "[RED] 未找到 label description 長度守門邏輯"
    idempotent_ok=0
  fi

  # 佇列檔不存在時具名回報且正常結束（非錯誤）
  if echo "$combined" | grep -qiE '待寫佇列不存在'; then
    say "[GREEN] 找到「待寫佇列不存在」具名回報字串"
  else
    say "[RED] 未找到「待寫佇列不存在，本批動作將重新產生」具名回報"
    idempotent_ok=0
  fi
fi

say ""
say "--- 檢查② 產生權：enqueue-guard.md 四類動作各自具名唯一產生者 ---"

guard_ok=1
if [[ ! -f "$GUARD" ]]; then
  say "[RED] enqueue-guard.md 不存在：$GUARD"
  guard_ok=0
else
  content=$(cat "$GUARD")

  # label 類（含 set-labels／開關 issue）只能 gate 產生
  if echo "$content" | grep -qiE 'label.*gate|gate.*label' \
     && echo "$content" | grep -qiE '(開|關).*issue.*gate|gate.*(開|關).*issue'; then
    say "[GREEN] label／開關 issue 類的唯一產生者具名為 gate"
  else
    say "[RED] 未明確具名「label／開關 issue 類唯一由 gate 產生」"
    guard_ok=0
  fi

  # issue／milestone 建立只能 intake 產生
  if echo "$content" | grep -qiE 'issue.*intake|intake.*issue' \
     && echo "$content" | grep -qiE 'milestone.*intake|intake.*milestone'; then
    say "[GREEN] issue／milestone 建立的唯一產生者具名為 intake"
  else
    say "[RED] 未明確具名「issue／milestone 建立唯一由 intake 產生」"
    guard_ok=0
  fi

  # comment 依原動作歸屬（run 或 gate，視情境）
  if echo "$content" | grep -qiE '(留言|comment).*(run|gate)' \
     && echo "$content" | grep -qiE '原動作歸屬|依歸屬|視情境'; then
    say "[GREEN] comment 類的產生權規則（依原動作歸屬）具名"
  else
    say "[RED] 未明確具名「comment 依原動作歸屬」規則"
    guard_ok=0
  fi

  # 違反時的判定行為：拒絕並具名
  if echo "$content" | grep -qiE '拒絕.*具名|具名.*拒絕'; then
    say "[GREEN] 找到「違反產生權 ⇒ 拒絕並具名」判定行為"
  else
    say "[RED] 未找到「違反產生權 ⇒ 拒絕並具名」判定行為"
    guard_ok=0
  fi
fi

say ""
if [[ $idempotent_ok -eq 1 && $guard_ok -eq 1 ]]; then
  say "=== 總結：GREEN（①冪等設計、②產生權規格 兩項靜態檢查皆通過） ==="
  fail=0
else
  idem_label=$([[ $idempotent_ok -eq 1 ]] && echo pass || echo FAIL)
  guard_label=$([[ $guard_ok -eq 1 ]] && echo pass || echo FAIL)
  say "=== 總結：RED（①冪等=${idem_label}、②產生權=${guard_label}） ==="
  fail=1
fi

say ""
say "⚠️ 本檢查僅涵蓋靜態面（檔案是否含正確設計元素／具名條文）。"
say "   動態驗收（Spec 驗收②③④⑥：真實連線 GitHub 跑冪等、回驗、對帳出列、遺失降級）"
say "   須由使用者於本機以 PowerShell + PAT 實跑，本沙盒無法執行。"

exit $fail
