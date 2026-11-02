#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 大文件与源文件行数规模分析器
支持递归扫描源文件，按阈值过滤超长代码文件，提供结构化数据与格式化报告。
"""

import argparse
import fnmatch
import os
import sys
import unicodedata
from typing import Dict, List, Optional, Set, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

try:  # 作为 toolbox.core 包导入
    from .paths import ROOT_DIR, resolve as resolve_path
except ImportError:  # 直接以脚本运行
    from paths import ROOT_DIR, resolve as resolve_path

DEFAULT_EXTENSIONS = ".dart,.go,.py,.kt,.java,.js,.ts,.vue,.sh"

# 构建缓存、依赖目录与第三方参考代码不参与规模统计。
DEFAULT_IGNORE_DIRS: Set[str] = {
    ".git",
    ".gradle",
    ".idea",
    ".kotlin",
    ".trae",
    ".vs",
    ".vscode",
    ".dart_tool",
    ".pub-cache",
    ".plugin_symlinks",
    ".venv",
    ".tox",
    ".cache",
    ".next",
    ".turbo",
    "build",
    "bin",
    "out",
    "dist",
    "coverage",
    "node_modules",
    "vendor",
    "target",
    "obj",
    "Pods",
    "ephemeral",
    "LearningObjects",
    "__pycache__",
    "venv",
    "cmake-build-debug",
    "cmake-build-release",
}

# 生成代码通常由工具维护，不应按 AGENTS 的 600 行规则要求人工拆分。
DEFAULT_GENERATED_PATTERNS: Tuple[str, ...] = (
    "*.g.dart",
    "*.freezed.dart",
    "*.gr.dart",
    "*.mocks.dart",
    "*.pb.go",
    "*_generated.go",
    "zz_generated*.go",
    "app_localizations*.dart",
    "*.min.js",
    "*.bundle.js",
    "*.designer.cs",
)


def get_display_width(text: str) -> int:
    width = 0
    for char in text:
        east_asian = unicodedata.east_asian_width(char)
        width += 2 if east_asian in ("F", "W") else 1
    return width


def pad_str(text: str, width: int, align: str = "left") -> str:
    curr_width = get_display_width(text)
    pad_len = max(0, width - curr_width)
    if align == "right":
        return " " * pad_len + text
    if align == "center":
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


def is_generated_file(filename: str) -> bool:
    lower = filename.lower()
    return any(fnmatch.fnmatch(lower, pattern.lower()) for pattern in DEFAULT_GENERATED_PATTERNS)


def scan_files(
    root_dir: str,
    target_exts: Set[str],
    threshold: int = 600,
    ignore_dirs: Optional[Set[str]] = None,
    show_all: bool = False,
    ignore_generated: bool = True,
) -> Tuple[List[dict], Dict]:
    if ignore_dirs is None:
        ignore_dirs = DEFAULT_IGNORE_DIRS

    matched_files: List[dict] = []
    stats = {
        "total_scanned": 0,
        "total_lines": 0,
        "generated_skipped": 0,
        "by_ext": {ext: 0 for ext in sorted(target_exts)},
        "lines_by_ext": {ext: 0 for ext in sorted(target_exts)},
        "max_file": None,
    }

    norm_root = os.path.abspath(root_dir)

    for dirpath, dirnames, filenames in os.walk(norm_root):
        dirnames[:] = sorted(d for d in dirnames if d not in ignore_dirs)

        for filename in sorted(filenames):
            ext = os.path.splitext(filename)[1].lower()
            if ext not in target_exts:
                continue
            if ignore_generated and is_generated_file(filename):
                stats["generated_skipped"] += 1
                continue

            full_path = os.path.join(dirpath, filename)
            rel_path = os.path.relpath(full_path, norm_root).replace("\\", "/")
            lines = count_lines(full_path)

            stats["total_scanned"] += 1
            stats["total_lines"] += lines
            stats["by_ext"][ext] = stats["by_ext"].get(ext, 0) + 1
            stats["lines_by_ext"][ext] = stats["lines_by_ext"].get(ext, 0) + lines

            info = {
                "rel_path": rel_path,
                "full_path": full_path,
                "line_count": lines,
                "ext": ext,
                "exceeded": lines > threshold,
            }
            current_max = stats.get("max_file")
            if current_max is None or lines > current_max["line_count"]:
                stats["max_file"] = info

            if show_all or lines > threshold:
                matched_files.append(info)

    return matched_files, stats


def format_table(
    matched_files: List[dict],
    threshold: int,
    root_dir: str,
    stats: Dict,
    sort_by: str = "lines",
    show_all: bool = False,
    ignore_generated: bool = True,
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
        f"生成文件   : {'已忽略' if ignore_generated else '计入统计'}",
        "-" * total_w,
    ]

    exceeded_count = sum(1 for f in matched_files if f["exceeded"])
    if not matched_files:
        lines.append("未找到符合条件的目标源文件。")
    elif exceeded_count == 0 and not show_all:
        lines.append(f"🎉 恭喜！未发现代码行数大于 {threshold} 行的目标文件。")
    else:
        if exceeded_count == 0:
            lines.append(f"🎉 恭喜！未发现代码行数大于 {threshold} 行的目标文件（已列出全部源文件清单）。")
            lines.append("-" * total_w)
        header = (
            pad_str("序号", col_idx_w, align="left")
            + pad_str("行数", col_lines_w, align="left")
            + pad_str("类型", col_type_w, align="left")
            + "文件相对路径"
        )
        lines.append(header)
        lines.append("-" * total_w)

        for idx, item in enumerate(matched_files, start=1):
            if not show_all and not item["exceeded"]:
                continue
            type_label = f"[{item['ext'].upper().lstrip('.')}]"
            tag = " [超标!]" if item["exceeded"] else ""
            row = (
                pad_str(str(idx), col_idx_w, align="left")
                + pad_str(f"{item['line_count']:,} 行", col_lines_w, align="left")
                + pad_str(type_label, col_type_w, align="left")
                + item["rel_path"] + tag
            )
            lines.append(row)

    lines.append("=" * total_w)
    ext_summary = ", ".join([f"{ext}: {cnt}" for ext, cnt in sorted(stats["by_ext"].items())])
    lines.append(f"统计概览: 共扫描 {stats['total_scanned']} 个源文件 ({ext_summary})，总代码量: {stats['total_lines']:,} 行")
    if ignore_generated and stats.get("generated_skipped"):
        lines.append(f"已忽略生成文件: {stats['generated_skipped']} 个")
    lines.append(f"超标文件: 共发现 {exceeded_count} 个文件行数大于 {threshold} 行")
    lines.append("=" * total_w)

    return "\n".join(lines)


def run_scan_analysis(
    root_dir: Optional[str] = None,
    extensions: str = DEFAULT_EXTENSIONS,
    threshold: int = 600,
    show_all: bool = False,
    sort_by: str = "lines",
    ignore_generated: bool = True,
) -> dict:
    scan_root = resolve_path(root_dir) if root_dir else ROOT_DIR
    target_exts = {
        e.strip().lower() if e.strip().startswith(".") else f".{e.strip().lower()}"
        for e in extensions.split(",")
        if e.strip()
    }

    matched, stats = scan_files(
        scan_root,
        target_exts,
        threshold=threshold,
        show_all=show_all,
        ignore_generated=ignore_generated,
    )

    if sort_by == "lines":
        matched.sort(key=lambda x: x["line_count"], reverse=True)
    else:
        matched.sort(key=lambda x: x["rel_path"].lower())

    exceeded_files = [f for f in matched if f["exceeded"]]
    max_file = stats.get("max_file") or (matched[0] if matched else None)
    report_text = format_table(
        matched,
        threshold,
        scan_root,
        stats,
        sort_by=sort_by,
        show_all=show_all,
        ignore_generated=ignore_generated,
    )

    return {
        "success": True,
        "root_dir": scan_root,
        "threshold": threshold,
        "ignore_generated": ignore_generated,
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
    parser.add_argument("-e", "--extensions", type=str, default=DEFAULT_EXTENSIONS, help="扩展名列表")
    parser.add_argument("-s", "--sort", choices=["lines", "path"], default="lines", help="排序规则")
    parser.add_argument("-a", "--all", action="store_true", help="显示所有文件")
    parser.add_argument("--include-generated", action="store_true", help="把生成代码也纳入统计")
    args = parser.parse_args()

    res = run_scan_analysis(
        root_dir=args.dir,
        extensions=args.extensions,
        threshold=args.threshold,
        show_all=args.all,
        sort_by=args.sort,
        ignore_generated=not args.include_generated,
    )
    print(res["report_text"])
    sys.exit(0 if res["exceeded_count"] == 0 else 1)


if __name__ == "__main__":
    main()
