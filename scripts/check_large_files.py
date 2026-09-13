#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
大文件检测脚本 (KT & Go)：递归扫描项目中的 Kotlin (.kt) 和 Go (.go) 源文件，
筛选出行数大于指定阈值（默认 800 行）的文件，输出行数、文件类型与相对路径，
支持命令行参数自定义阈值、指定目录、扩展名、排序规则等。
"""

import argparse
import os
import sys
import unicodedata
from typing import Dict, List, Set, Tuple

# 确保在 Windows / 各类终端环境下 UTF-8 中文正常输出
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

# 构建产物、版本控制、IDE缓存等
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
    """计算字符串在终端中的显示宽度（兼容东亚宽字符/全角字符）。"""
    width = 0
    for char in text:
        east_asian = unicodedata.east_asian_width(char)
        if east_asian in ("F", "W"):
            width += 2
        else:
            width += 1
    return width


def pad_str(text: str, width: int, align: str = "left") -> str:
    """按终端显示宽度填充对齐字符串。"""
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
    """统计指定文件的总行数。
    
    使用迭代器逐行统计，避免大文件占用内存，并容错处理编码异常。
    """
    try:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            return sum(1 for _ in f)
    except Exception:
        # 二进制兜底统计
        with open(file_path, "rb") as f:
            return sum(1 for _ in f)


def scan_files(
    root_dir: str,
    target_exts: Set[str],
    threshold: int,
    ignore_dirs: Set[str],
    show_all: bool = False,
) -> Tuple[List[Tuple[str, int, str]], Dict]:
    """递归扫描目录并统计文件信息。
    
    Returns:
        matched_files: List of (rel_path, line_count, ext)
        stats: dict containing total scanned counts per ext
    """
    matched_files: List[Tuple[str, int, str]] = []
    stats = {
        "total_scanned": 0,
        "by_ext": {ext: 0 for ext in target_exts},
    }

    norm_root = os.path.abspath(root_dir)

    for dirpath, dirnames, filenames in os.walk(norm_root):
        # 原地修改 dirnames 避免深入无关目录
        dirnames[:] = [d for d in dirnames if d not in ignore_dirs]

        for filename in filenames:
            ext = os.path.splitext(filename)[1].lower()
            if ext in target_exts:
                full_path = os.path.join(dirpath, filename)
                rel_path = os.path.relpath(full_path, norm_root).replace("\\", "/")
                
                stats["total_scanned"] += 1
                stats["by_ext"][ext] = stats["by_ext"].get(ext, 0) + 1

                line_count = count_lines(full_path)

                if show_all or line_count > threshold:
                    matched_files.append((rel_path, line_count, ext))

    return matched_files, stats


def format_table(
    matched_files: List[Tuple[str, int, str]],
    threshold: int,
    root_dir: str,
    stats: Dict,
    sort_by: str = "lines",
) -> str:
    """格式化生成检测结果表格报告。"""
    if sort_by == "lines":
        matched_files.sort(key=lambda x: x[1], reverse=True)
    elif sort_by == "path":
        matched_files.sort(key=lambda x: x[0].lower())

    col_idx_w = 6
    col_lines_w = 12
    col_type_w = 12
    total_w = 96

    lines: List[str] = []
    lines.append("=" * total_w)
    lines.append(pad_str("项目大文件检测报告 (Kotlin & Go)", total_w, align="center"))
    lines.append("=" * total_w)
    lines.append(f"扫描根目录 : {root_dir}")
    lines.append(f"检测扩展名 : {', '.join(sorted(stats['by_ext'].keys()))}")
    lines.append(f"行数阈值   : > {threshold} 行")
    lines.append("-" * total_w)

    if not matched_files:
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
        
        type_labels = {
            ".kt": "[Kotlin]",
            ".go": "[Go]",
        }

        for idx, (rel_path, count, ext) in enumerate(matched_files, start=1):
            type_label = type_labels.get(ext, f"[{ext.upper().lstrip('.')}]")
            row = (
                pad_str(str(idx), col_idx_w, align="left")
                + pad_str(f"{count:,} 行", col_lines_w, align="left")
                + pad_str(type_label, col_type_w, align="left")
                + rel_path
            )
            lines.append(row)

    lines.append("=" * total_w)
    
    ext_summary = ", ".join([f"{ext}: {cnt}" for ext, cnt in sorted(stats["by_ext"].items())])
    lines.append(f"统计概览: 共扫描 {stats['total_scanned']} 个源文件 ({ext_summary})")
    lines.append(f"超标文件: 共发现 {len(matched_files)} 个文件行数大于 {threshold} 行")
    lines.append("=" * total_w)

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="检测项目中大于指定行数（默认 800 行）的 Kotlin (.kt) 和 Go (.go) 文件"
    )
    parser.add_argument(
        "-t",
        "--threshold",
        type=int,
        default=800,
        help="行数阈值（默认: 800）",
    )
    parser.add_argument(
        "-d",
        "--dir",
        type=str,
        default=None,
        help="指定要扫描的根目录（默认自动定位为项目根目录）",
    )
    parser.add_argument(
        "-e",
        "--extensions",
        type=str,
        default=".kt,.go",
        help="指定要检测的文件扩展名，逗号分隔（默认: .kt,.go）",
    )
    parser.add_argument(
        "-s",
        "--sort",
        choices=["lines", "path"],
        default="lines",
        help="排序规则: 'lines' (按行数降序) 或 'path' (按路径升序)，默认 'lines'",
    )
    parser.add_argument(
        "--include-build",
        action="store_true",
        help="是否包含构建产物和临时缓存目录（默认排除 build, .gradle 等）",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="列出所有扫描到的文件及行数（忽略阈值过滤）",
    )

    args = parser.parse_args()

    if args.dir:
        root_dir = os.path.abspath(args.dir)
    else:
        # 脚本位于 scripts/ 下，默认上级目录为项目根目录
        script_dir = os.path.dirname(os.path.abspath(__file__))
        root_dir = os.path.abspath(os.path.join(script_dir, ".."))

    target_exts = {
        ext.strip().lower() if ext.strip().startswith(".") else f".{ext.strip().lower()}"
        for ext in args.extensions.split(",")
        if ext.strip()
    }

    ignore_dirs = set() if args.include_build else DEFAULT_IGNORE_DIRS

    matched_files, stats = scan_files(
        root_dir=root_dir,
        target_exts=target_exts,
        threshold=args.threshold,
        ignore_dirs=ignore_dirs,
        show_all=args.all,
    )

    report = format_table(
        matched_files=matched_files,
        threshold=args.threshold,
        root_dir=root_dir,
        stats=stats,
        sort_by=args.sort,
    )

    print(report)


if __name__ == "__main__":
    main()
