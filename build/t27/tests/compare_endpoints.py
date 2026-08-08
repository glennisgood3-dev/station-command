#!/usr/bin/env python3
"""
T-27 離線比對測試：廠商登錄表 asset 的逐列比對。

比對四條驗收條件：
  ① 12 列，且逐列 (provider, 端點) 配對與凍結 fixture（2026-08-08 實測端點清單，
     provider 名稱取自 Spec §5.1 原表、端點值取自票面驗收條件①原文，兩者皆外部
     既存事實，非由被測 asset 反推）逐字相符——**逐列配對比對，非僅端點多重集合比對**
     （2026-08-08 站 4 verifier 實證：多重集合比對抓不到「provider 對到錯誤端點」
     這種假綠，例如 OpenAI／Cohere 兩列端點互換，多重集合不變但配對已錯）
  ② 「格式家族」欄位僅取四值之一：OpenAI-compatible／Gemini／Anthropic／Cohere
  ③ 「狀態」欄位基底值僅取 available／registered-no-key；Gemini 一列須為
     "available（首發；免費層，無需計費）"，其餘 11 家須為裸值 "registered-no-key"

設計原則（依 Spec §6 註 A）：本腳本的紅燈必須是「跑到斷言才失敗」（AssertionError），
🚫 不得是 import/找不到檔案這類載入失敗。asset 不存在時仍先斷言「12 列存在」而失敗，
不讓 Python 因 FileNotFoundError 直接中止 traceback。

用法：
    python3 compare_endpoints.py <asset.md 路徑> [--fixture <endpoints.txt 路徑>]

離線：全程只讀本機檔案，不連外網、不呼叫任何 API。
"""
import sys
import os
import re
import argparse

ALLOWED_FAMILIES = {"OpenAI-compatible", "Gemini", "Anthropic", "Cohere"}
GEMINI_STATUS = "available（首發；免費層，無需計費）"
OTHER_STATUS = "registered-no-key"


def extract_table_rows(md_text: str):
    """從 markdown 抓出資料列（provider|端點|認證|格式家族|狀態），排除表頭與分隔線。"""
    rows = []
    for line in md_text.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        if line.startswith("|---") or re.match(r"^\|[\s\-|]+\|$", line):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 5:
            continue
        if cells[0] in ("provider", ""):
            continue
        rows.append(
            {
                "provider": cells[0],
                "endpoint": cells[1],
                "auth": cells[2],
                "family": cells[3],
                "status": cells[4],
            }
        )
    return rows


def load_fixture_pairs(fixture_path: str):
    """讀取兩欄 fixture（provider<TAB>endpoint），略過 # 開頭註解列與空行。"""
    if not os.path.isfile(fixture_path):
        return []
    pairs = []
    with open(fixture_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                # 容錯：允許多個空白替代 tab（避免編輯器誤存成空白）
                parts = re.split(r"\s{2,}|\t", line, maxsplit=1)
            if len(parts) != 2:
                continue
            pairs.append((parts[0].strip(), parts[1].strip()))
    return pairs


def load_asset(asset_path: str):
    if not os.path.isfile(asset_path):
        return ""
    with open(asset_path, "r", encoding="utf-8") as f:
        return f.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("asset", help="廠商登錄表 asset 路徑（markdown）")
    ap.add_argument(
        "--fixture",
        default=os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "fixtures",
            "endpoints-2026-08-08.txt",
        ),
        help="凍結端點 fixture 路徑（預設 ../fixtures/endpoints-2026-08-08.txt，兩欄 TSV）",
    )
    args = ap.parse_args()

    print(f"asset   = {args.asset}")
    print(f"fixture = {args.fixture}")

    md_text = load_asset(args.asset)
    rows = extract_table_rows(md_text)
    expected_pairs = load_fixture_pairs(args.fixture)
    expected_map = {p: e for p, e in expected_pairs}

    failures = []

    # --- 斷言 A：fixture 必須先備妥且恰為 12 筆、provider 皆唯一（外部既存事實，與被測 asset 無關） ---
    try:
        assert len(expected_pairs) == 12, f"fixture 筆數應為 12，實得 {len(expected_pairs)}"
        assert len(expected_map) == 12, "fixture 內 provider 名稱有重複，配對將失去唯一性"
        print(f"[OK] fixture (provider, 端點) 筆數 = {len(expected_pairs)}，provider 皆唯一")
    except AssertionError as e:
        failures.append(str(e))
        print(f"[FAIL] {e}")

    # --- 斷言 ①-a：asset 列數為 12 ---
    try:
        assert len(rows) == 12, f"asset 資料列數應為 12，實得 {len(rows)}"
        print(f"[OK] asset 資料列數 = {len(rows)}")
    except AssertionError as e:
        failures.append(str(e))
        print(f"[FAIL] {e}")

    # --- 斷言 ①-b：provider 集合須與 fixture 一致（且 asset 內 provider 不得重複） ---
    asset_providers = [r["provider"] for r in rows]
    asset_map = {}
    dup_providers = []
    for r in rows:
        if r["provider"] in asset_map:
            dup_providers.append(r["provider"])
        asset_map[r["provider"]] = r["endpoint"]
    try:
        assert not dup_providers, f"asset 內 provider 名稱重複: {dup_providers}"
        assert set(asset_providers) == set(expected_map.keys()), (
            "asset 的 provider 集合與 fixture 不符\n"
            f"  只在 asset 缺的 provider = {sorted(set(expected_map.keys()) - set(asset_providers))}\n"
            f"  只在 asset 多的 provider = {sorted(set(asset_providers) - set(expected_map.keys()))}"
        )
        print("[OK] provider 集合與 fixture 相符、asset 內無重複 provider")
    except AssertionError as e:
        failures.append(str(e))
        print(f"[FAIL] {e}")

    # --- 斷言 ①-c（核心）：逐列 (provider, 端點) 配對須與 fixture 逐字相符 ---
    # 🔴 此為逐列配對比對，非多重集合比對：即便端點集合不變，只要某 provider 被
    # 配到「別的 provider 的端點」（例如 OpenAI 列被填成 Cohere 的端點），本斷言必須抓到。
    mismatches = []
    for provider, expected_endpoint in expected_map.items():
        actual_endpoint = asset_map.get(provider)
        if actual_endpoint != expected_endpoint:
            mismatches.append((provider, expected_endpoint, actual_endpoint))
    try:
        assert not mismatches, (
            "以下 provider 的端點與 fixture 逐列配對不符（provider, 預期端點, 實得端點）:\n"
            + "\n".join(f"  {p!r}: 預期 {exp!r}，實得 {act!r}" for p, exp, act in mismatches)
        )
        print("[OK] 12 列 (provider, 端點) 逐列配對與 fixture 逐字相符")
    except AssertionError as e:
        failures.append(str(e))
        print(f"[FAIL] {e}")

    # --- 斷言 ②：格式家族僅取四值之一 ---
    bad_family = [(r["provider"], r["family"]) for r in rows if r["family"] not in ALLOWED_FAMILIES]
    try:
        assert not bad_family, f"格式家族出現允許值以外的字串: {bad_family}"
        print("[OK] 格式家族皆屬四值之一")
    except AssertionError as e:
        failures.append(str(e))
        print(f"[FAIL] {e}")

    # --- 斷言 ③：狀態僅 Gemini available（首發標註）、其餘 11 家 registered-no-key ---
    gemini_rows = [r for r in rows if r["provider"] == "Gemini"]
    other_rows = [r for r in rows if r["provider"] != "Gemini"]
    try:
        assert len(gemini_rows) == 1, f"Gemini 列數應為 1，實得 {len(gemini_rows)}"
        assert gemini_rows[0]["status"] == GEMINI_STATUS, (
            f"Gemini 狀態應為 {GEMINI_STATUS!r}，實得 {gemini_rows[0]['status']!r}"
        )
        bad_other = [(r["provider"], r["status"]) for r in other_rows if r["status"] != OTHER_STATUS]
        assert not bad_other, f"以下非 Gemini 列狀態不是裸值 {OTHER_STATUS!r}: {bad_other}"
        assert "待儲值" not in md_text, "asset 內殘留「待儲值」字串（v1.11 事實更正已禁止）"
        print("[OK] 狀態欄位符合 Gemini available（首發）／其餘 registered-no-key 規則")
    except AssertionError as e:
        failures.append(str(e))
        print(f"[FAIL] {e}")

    # --- 斷言 ④：兩句具名警語存在（登錄≠啟用；外廠計費，涵蓋金額／配額兩語意） ---
    try:
        assert "登錄 ≠ 啟用" in md_text or "登錄≠啟用" in md_text, "「登錄≠啟用」句未逐字出現"
        assert "金額" in md_text and "配額" in md_text, "計費警語未涵蓋「金額」與「配額」兩種語意"
        print("[OK] 兩句具名警語存在（登錄≠啟用；金額／配額兩語意計費警語）")
    except AssertionError as e:
        failures.append(str(e))
        print(f"[FAIL] {e}")

    print()
    if failures:
        print(f"=== RED（斷言失敗，共 {len(failures)} 條）===")
        sys.exit(1)
    else:
        print("=== ALL GREEN ===")
        sys.exit(0)


if __name__ == "__main__":
    main()
