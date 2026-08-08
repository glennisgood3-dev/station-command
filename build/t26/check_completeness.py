#!/usr/bin/env python3
"""T-26 source-table-to-section completeness check (stdlib only)."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path


SPEC_PATH = Path(__file__).with_name("ci-stage-spec.md")
SOURCE_FIXTURE_PATH = Path(__file__).with_name("deferred-sources.tsv")
SCAN_FIXTURE_PATH = Path(__file__).with_name("readme-scan.tsv")
REPO_ROOT = Path(__file__).resolve().parents[2]
ROW_RE = re.compile(r"^\| (DTC-\d{3}) \|", re.MULTILINE)
HEADING_RE = re.compile(r"^#{3,6} (DTC-\d{3})(?:\s|$)", re.MULTILINE)
SCAN_ROW_RE = re.compile(
    r"^\| (t(?:\d+[a-z]?)) \|.*?\| (\d+) \| (\d+) \|", re.MULTILINE
)
REQUIRED_FIELDS = (
    "**CI 階段要做**",
    "**啟用條件**",
    "**啟用後驗收**",
    "**與手動階段差異**",
    "**差什麼才能驗完**",
)
NEEDLE_PRIMARY_CLASS_SUFFIX = "-needle-primary"


def duplicates(values: list[str]) -> list[str]:
    return sorted({value for value in values if values.count(value) > 1})


def main() -> int:
    text = SPEC_PATH.read_text(encoding="utf-8")
    table_ids = ROW_RE.findall(text)
    section_ids = HEADING_RE.findall(text)

    with SOURCE_FIXTURE_PATH.open(encoding="utf-8", newline="") as handle:
        fixture_rows = list(csv.DictReader(handle, delimiter="\t"))
    with SCAN_FIXTURE_PATH.open(encoding="utf-8", newline="") as handle:
        scan_rows = list(csv.DictReader(handle, delimiter="\t"))

    source_ids = sorted({row["section_id"] for row in fixture_rows})

    problems: list[str] = []
    if not source_ids:
        problems.append("獨立來源 fixture 沒有任何 DTC 項目")

    duplicate_table_ids = duplicates(table_ids)
    duplicate_sections = duplicates(section_ids)
    missing_table = sorted(set(source_ids) - set(table_ids))
    extra_table = sorted(set(table_ids) - set(source_ids))
    missing = sorted(set(source_ids) - set(section_ids))
    orphan_sections = sorted(set(section_ids) - set(source_ids))
    incomplete_sections: list[str] = []
    bad_source_refs: list[str] = []

    heading_matches = list(HEADING_RE.finditer(text))
    for index, match in enumerate(heading_matches):
        body_start = match.end()
        body_end = heading_matches[index + 1].start() if index + 1 < len(heading_matches) else len(text)
        body = text[body_start:body_end]
        missing_fields = [field for field in REQUIRED_FIELDS if field not in body]
        if missing_fields:
            incomplete_sections.append(f"{match.group(1)} 缺 {', '.join(missing_fields)}")

    if duplicate_table_ids:
        problems.append(f"來源對照表 ID 重複：{', '.join(duplicate_table_ids)}")
    if duplicate_sections:
        problems.append(f"對應章節重複：{', '.join(duplicate_sections)}")
    if missing_table:
        problems.append(f"來源對照表漏 fixture ID（{len(missing_table)}）：{', '.join(missing_table)}")
    if extra_table:
        problems.append(f"來源對照表有 fixture 外 ID（{len(extra_table)}）：{', '.join(extra_table)}")
    if missing:
        problems.append(f"缺對應章節（{len(missing)}）：{', '.join(missing)}")
    if orphan_sections:
        problems.append(f"無來源的孤兒章節（{len(orphan_sections)}）：{', '.join(orphan_sections)}")
    if incomplete_sections:
        problems.append("章節必要欄位不全：" + "；".join(incomplete_sections))

    for row in fixture_rows:
        source_path = REPO_ROOT / row["path"]
        try:
            lines = source_path.read_text(encoding="utf-8-sig").splitlines()
            line_no = int(row["line"])
            if line_no < 1:
                raise ValueError("line 必須是正整數")
            needle = row["needle"]
            if not needle:
                raise ValueError("needle 不得為空")
            if row["class"].endswith(NEEDLE_PRIMARY_CLASS_SUFFIX):
                if not any(needle in line for line in lines):
                    bad_source_refs.append(
                        f"{row['occurrence_id']} {row['path']} 全檔不含 {needle!r}"
                        f"（行號提示：{line_no}）"
                    )
            elif needle not in lines[line_no - 1]:
                bad_source_refs.append(
                    f"{row['occurrence_id']} {row['path']}:{line_no} 不含 {needle!r}"
                )
        except (OSError, ValueError, IndexError) as error:
            bad_source_refs.append(f"{row['occurrence_id']} 無法驗證：{error}")
    if bad_source_refs:
        problems.append("來源 fixture 漂移：" + "；".join(bad_source_refs))

    expected_v18_lines = {
        int(row["line"]) for row in fixture_rows if row["class"] == "v1.8-literal"
    }
    v18_lines = (REPO_ROOT / "Spec_station-command_v1.8.md").read_text(encoding="utf-8-sig").splitlines()
    actual_v18_lines = {index for index, line in enumerate(v18_lines, 1) if "deferred-to-CI" in line}
    if expected_v18_lines != actual_v18_lines:
        problems.append(
            "v1.8 deferred-to-CI 字面位置與 fixture 不符："
            f"expected={sorted(expected_v18_lines)} actual={sorted(actual_v18_lines)}"
        )

    scan_table = {
        name: (int(deferred), int(pre_ci))
        for name, deferred, pre_ci in SCAN_ROW_RE.findall(text)
    }
    for row in scan_rows:
        directory = row["directory"]
        expected_counts = (int(row["deferred_count"]), int(row["pre_ci_count"]))
        build_dir = REPO_ROOT / "build" / directory
        readme = build_dir / "README.md"
        state = row["readme_state"]
        state_ok = {
            "exists": build_dir.is_dir() and readme.is_file(),
            "missing-readme": build_dir.is_dir() and not readme.exists(),
            "missing-directory": not build_dir.exists(),
        }.get(state, False)
        if not state_ok:
            problems.append(f"README 掃描 fixture 狀態漂移：{directory} expected={state}")
        if scan_table.get(directory) != expected_counts:
            problems.append(
                f"README 掃描表計數不符：{directory} expected={expected_counts} actual={scan_table.get(directory)}"
            )

    print(f"SOURCE_FIXTURE_ROWS={len(fixture_rows)}")
    print(f"SOURCE_COUNT={len(source_ids)}")
    print(f"SECTION_COUNT={len(section_ids)}")
    print(f"COVERED_COUNT={len(set(source_ids) & set(section_ids))}")

    if problems:
        for problem in problems:
            print(f"[FAIL] {problem}")
        print("RESULT=RED")
        return 1

    print("[PASS] 來源對照表每一條皆有且只有一個對應章節")
    print("RESULT=GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
