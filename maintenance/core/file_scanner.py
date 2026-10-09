#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 大文件与源文件行数规模分析器
支持递归扫描源文件，按阈值过滤超长代码文件，提供结构化数据与格式化报告。
"""

import argparse
import os
import sys
import unicodedata
from typing import Dict, List, Optional, Set, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

DEFAULT_IGNORE_DIRS: Set[str] = {
    ".git",
    ".gradle",
    ".idea",
    ".kotlin",
    ".trae",
    "build",
    "bin",
    "out",
    "node_modules",
    "vendor",
    "__pycache__",
    ".venv",
    "venv",
}


def get_display_width(text: str) -> int:
    width = 0
    for char in text:
        east_asian = unicodedata.east_asian_width(char)
        if east_asian in ("F", "W"):
            width += 2
        else:
            width += 1
    return width


def pad_str(text: str, width: int, align: str = "left") -> str:
    curr_width = get_display_width(text)
    pad_len = max(0, width - curr_width)
    if align == "right":
        return " " * pad_len + text
    elif align == "center":
        left_pad = pad_len // 2
        right_pad = pad_len - left_pad
        return " " * left_pad + text + " " * right_pad
    return text + " " * pad_len


def count_lines(file_path: str) -> int:
    try:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            return sum(1 for _ in f)
    except Exception:
        with open(file_path, "rb") as f:
            return sum(1 for _ in f)


def scan_files(
    root_dir: str,
    target_exts: Set[str],
    threshold: int = 600,
    ignore_dirs: Optional[Set[str]] = None,
    show_all: bool = False,
) -> Tuple[List[dict], Dict]:
    if ignore_dirs is None:
        ignore_dirs = DEFAULT_IGNORE_DIRS

    matched_files: List[dict] = []
    stats = {
        "total_scanned": 0,
        "total_lines": 0,
        "by_ext": {ext: 0 for ext in target_exts},
        "lines_by_ext": {ext: 0 for ext in target_exts},
    }

    norm_root = os.path.abspath(root_dir)

    for dirpath, dirnames, filenames in os.walk(norm_root):
        dirnames[:] = [d for d in dirnames if d not in ignore_dirs]

        for filename in filenames:
            ext = os.path.splitext(filename)[1].lower()
            if ext in target_exts:
                full_path = os.path.join(dirpath, filename)
                rel_path = os.path.relpath(full_path, norm_root).replace("\\", "/")
                
                lines = count_lines(full_path)
                stats["total_scanned"] += 1
                stats["total_lines"] += lines
                stats["by_ext"][ext] = stats["by_ext"].get(ext, 0) + 1
                stats["lines_by_ext"][ext] = stats["lines_by_ext"].get(ext, 0) + lines

                if show_all or lines > threshold:
                    matched_files.append({
                        "rel_path": rel_path,
                        "full_path": full_path,
                        "line_count": lines,
                        "ext": ext,
                        "exceeded": lines > threshold,
                    })

    return matched_files, stats


def format_table(
    matched_files: List[dict],
    threshold: int,
    root_dir: str,
    stats: Dict,
    sort_by: str = "lines",
) -> str:
    if sort_by == "lines":
        matched_files.sort(key=lambda x: x["line_count"], reverse=True)
    elif sort_by == "path":
        matched_files.sort(key=lambda x: x["rel_path"].lower())

    col_idx_w = 6
    col_lines_w = 12
    col_type_w = 12
    total_w = 96

    lines: List[str] = [
        "=" * total_w,
        pad_str("项目大文件检测报告", total_w, align="center"),
        "=" * total_w,
        f"扫描根目录 : {root_dir}",
        f"检测扩展名 : {', '.join(sorted(stats['by_ext'].keys()))}",
        f"行数阈值   : > {threshold} 行",
        "-" * total_w,
    ]

    exceeded_count = sum(1 for f in matched_files if f["exceeded"])
    if exceeded_count == 0:
        lines.append(f"🎉 恭喜！未发现代码行数大于 {threshold} 行的目标文件。")
    else:
        header = (
            pad_str("序号", col_idx_w, align="left")
            + pad_str("行数", col_lines_w, align="left")
            + pad_str("类型", col_type_w, align="left")
            + "文件相对路径"
        )
        lines.append(header)
        lines.append("-" * total_w)

        for idx, item in enumerate(matched_files, start=1):
            if not item["exceeded"]:
                continue
            type_label = f"[{item['ext'].upper().lstrip('.')}]"
            row = (
                pad_str(str(idx), col_idx_w, align="left")
                + pad_str(f"{item['line_count']:,} 行", col_lines_w, align="left")
                + pad_str(type_label, col_type_w, align="left")
                + item["rel_path"]
            )
            lines.append(row)

    lines.append("=" * total_w)
    ext_summary = ", ".join([f"{ext}: {cnt}" for ext, cnt in sorted(stats["by_ext"].items())])
    lines.append(f"统计概览: 共扫描 {stats['total_scanned']} 个源文件 ({ext_summary})，总代码量: {stats['total_lines']:,} 行")
    lines.append(f"超标文件: 共发现 {exceeded_count} 个文件行数大于 {threshold} 行")
    lines.append("=" * total_w)

    return "\n".join(lines)


def run_scan_analysis(
    root_dir: Optional[str] = None,
    extensions: str = ".kt,.go,.ts,.vue,.py",
    threshold: int = 600,
    show_all: bool = False,
    sort_by: str = "lines",
) -> dict:
    if not root_dir:
        root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

    target_exts = {e.strip().lower() if e.strip().startswith(".") else f".{e.strip().lower()}" for e in extensions.split(",") if e.strip()}
    matched, stats = scan_files(root_dir, target_exts, threshold=threshold, show_all=show_all)
    
    if sort_by == "lines":
        matched.sort(key=lambda x: x["line_count"], reverse=True)
    else:
        matched.sort(key=lambda x: x["rel_path"].lower())

    exceeded_files = [f for f in matched if f["exceeded"]]
    max_file = matched[0] if matched else None
    report_text = format_table(matched, threshold, root_dir, stats, sort_by=sort_by)

    return {
        "success": True,
        "root_dir": root_dir,
        "threshold": threshold,
        "stats": stats,
        "matched_files": matched,
        "exceeded_count": len(exceeded_files),
        "max_file": max_file,
        "report_text": report_text,
    }


def main():
    parser = argparse.ArgumentParser(description="检测项目中大于指定行数的源文件")
    parser.add_argument("-t", "--threshold", type=int, default=600, help="行数阈值（默认: 600）")
    parser.add_argument("-d", "--dir", type=str, default=None, help="扫描根目录")
    parser.add_argument("-e", "--extensions", type=str, default=".kt,.go,.ts,.vue,.py", help="扩展名列表")
    parser.add_argument("-s", "--sort", choices=["lines", "path"], default="lines", help="排序规则")
    parser.add_argument("-a", "--all", action="store_true", help="显示所有文件")
    args = parser.parse_args()

    res = run_scan_analysis(root_dir=args.dir, extensions=args.extensions, threshold=args.threshold, show_all=args.all, sort_by=args.sort)
    print(res["report_text"])
    sys.exit(0 if res["exceeded_count"] == 0 else 1)


if __name__ == "__main__":
    main()
