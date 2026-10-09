#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 统一版本号管理引擎
支持跨模块、安装包、脚本与前端配置的版本号统一检测、同步、MD5 校验与 Git 提交。
"""

import argparse
import hashlib
import os
import re
import subprocess
import sys
from typing import Callable, Dict, List, Optional, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


def get_root_dir() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def get_file_targets() -> List[Dict[str, str]]:
    root = get_root_dir()
    windows = os.path.join(root, "Windows")
    frontend = os.path.join(windows, "frontend")
    return [
        {"name": "Windows 主程序", "path": os.path.join(windows, "main.go"), "type": "go"},
        {"name": "特权服务", "path": os.path.join(windows, "cmd", "service", "main.go"), "type": "go"},
        {"name": "GUI 调试入口", "path": os.path.join(windows, "cmd", "gui", "main.go"), "type": "go"},
        {"name": "NSIS 主配置", "path": os.path.join(windows, "build", "windows", "installer", "project.nsi"), "type": "nsi"},
        {"name": "NSIS 工具宏", "path": os.path.join(windows, "build", "windows", "installer", "wails_tools.nsh"), "type": "nsh"},
        {"name": "Wails 配置", "path": os.path.join(windows, "wails.json"), "type": "wails"},
        {"name": "前端 package.json", "path": os.path.join(frontend, "package.json"), "type": "pkg"},
        {"name": "前端 Mock 数据", "path": os.path.join(frontend, "src", "api", "mock.ts"), "type": "mock"},
    ]


def read_file(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def write_file(path: str, content: str):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


def extract_version(item: Dict[str, str]) -> str:
    path = item["path"]
    if not os.path.exists(path):
        return "文件不存在"
    content = read_file(path)
    ftype = item["type"]

    if ftype == "go":
        m = re.search(r'(?m)^\s*(?:ServiceVersion|AppVersion|Version)\s*=\s*"([^"]+)"', content)
        if m: return m.group(1)
    elif ftype in ("nsi", "nsh"):
        m = re.search(r'!define INFO_PRODUCTVERSION\s+"([^"]+)"', content)
        if m: return m.group(1)
    elif ftype == "wails":
        m = re.search(r'"productVersion":\s*"([^"]+)"', content)
        if m: return m.group(1)
    elif ftype == "pkg":
        m = re.search(r'"version":\s*"([^"]+)"', content)
        if m: return m.group(1)
    elif ftype == "mock":
        m = re.search(r"mockStatus:\s*StatusResponse\s*=\s*\{[\s\S]*?version:\s*'([^']+)'", content)
        if m: return m.group(1)

    return "未知"


def replace_version_content(content: str, ftype: str, new_ver: str) -> Tuple[str, bool]:
    changed = False
    if ftype == "go":
        new_content, n = re.subn(r'(?m)^(\s*(?:ServiceVersion|AppVersion|Version)\s*=\s*")[^"]+(")', rf'\g<1>{new_ver}\g<2>', content)
        if n > 0: return new_content, True
    elif ftype in ("nsi", "nsh"):
        new_content, n = re.subn(r'(!define INFO_PRODUCTVERSION\s+")[^"]+(")', rf'\g<1>{new_ver}\g<2>', content)
        if n > 0: return new_content, True
    elif ftype == "wails":
        new_content, n = re.subn(r'("productVersion":\s*")[^"]+(")', rf'\g<1>{new_ver}\g<2>', content)
        if n > 0: return new_content, True
    elif ftype == "pkg":
        new_content, n = re.subn(r'("version":\s*")[^"]+(")', rf'\g<1>{new_ver}\g<2>', content)
        if n > 0: return new_content, True
    elif ftype == "mock":
        pattern = r"(mockStatus:\s*StatusResponse\s*=\s*\{[\s\S]*?version:\s*')[^']+'"
        replacement = rf"\g<1>{new_ver}'"
        new_content, n = re.subn(pattern, replacement, content)
        if n > 0: return new_content, True

    return content, False


def inspect_versions() -> List[Dict[str, str]]:
    root = get_root_dir()
    targets = get_file_targets()
    results = []
    for item in targets:
        ver = extract_version(item)
        rel_path = os.path.relpath(item["path"], root).replace("\\", "/")
        results.append({
            "name": item["name"],
            "path": item["path"],
            "rel_path": rel_path,
            "type": item["type"],
            "version": ver,
            "exists": os.path.exists(item["path"]),
        })
    return results


def sync_version(
    target_version: str,
    dry_run: bool = False,
    verify: bool = False,
    commit: bool = False,
    on_log: Optional[Callable[[str, str], None]] = None,
) -> dict:
    target_ver = target_version.strip().lstrip("v")
    if not target_ver:
        return {"success": False, "message": "目标版本号不可为空"}

    root = get_root_dir()
    targets = get_file_targets()
    modified_files = []

    def _log(lvl, msg):
        if on_log:
            on_log(lvl, msg)
        else:
            print(f"[{lvl.upper()}] {msg}")

    _log("info", f"开始同步版本号至: v{target_ver} (DryRun={dry_run})")

    for item in targets:
        path = item["path"]
        rel = os.path.relpath(path, root).replace("\\", "/")
        if not os.path.exists(path):
            _log("warn", f"跳过不存在文件: {rel}")
            continue

        old_content = read_file(path)
        new_content, changed = replace_version_content(old_content, item["type"], target_ver)

        if changed:
            modified_files.append(rel)
            if dry_run:
                _log("info", f"[预览] 将修改 {item['name']}: {rel}")
            else:
                write_file(path, new_content)
                _log("info", f"[已更新] {item['name']}: {rel}")
        else:
            _log("warn", f"未匹配到版本标识或版本未变: {rel}")

    # 同步更新 package.json.md5
    pkg_path = os.path.join(root, "Windows", "frontend", "package.json")
    pkg_md5_path = os.path.join(root, "Windows", "frontend", "package.json.md5")
    if os.path.exists(pkg_path):
        with open(pkg_path, "rb") as f:
            h = hashlib.md5(f.read()).hexdigest()
        if not dry_run:
            with open(pkg_md5_path, "w", encoding="utf-8") as f:
                f.write(h)
            modified_files.append("Windows/frontend/package.json.md5")
            _log("info", f"[已更新] 前端 package.json MD5 哈希: {h[:8]}...")

    if verify and not dry_run:
        _log("info", "正在运行 Go 编译测试以验证版本语法...")
        cmd = ["go", "test", "./..."]
        p = subprocess.run(cmd, cwd=os.path.join(root, "Windows"), capture_output=True, text=True)
        if p.returncode != 0:
            _log("error", f"Go 测试失败:\n{p.stderr or p.stdout}")
            return {"success": False, "message": "Go 验证测试失败", "modified": modified_files}
        _log("info", "Go 测试校验通过!")

    if commit and not dry_run:
        _log("info", "正在将版本修改提交至 Git...")
        for mf in modified_files:
            subprocess.run(["git", "-C", root, "add", mf], capture_output=True)
        commit_msg = f"chore(release): bump version to v{target_ver}"
        p = subprocess.run(["git", "-C", root, "commit", "-m", commit_msg], capture_output=True, text=True)
        if p.returncode == 0:
            _log("info", f"Git 提交成功: {commit_msg}")
        else:
            _log("warn", f"Git 提交输出: {p.stdout.strip() or p.stderr.strip()}")

    _log("info", f"版本号同步完成！已影响 {len(modified_files)} 个文件。")
    return {
        "success": True,
        "target_version": target_ver,
        "modified_files": modified_files,
        "dry_run": dry_run,
    }


def main():
    parser = argparse.ArgumentParser(description="谛听统一版本号管理工具")
    parser.add_argument("version", nargs="?", default=None, help="目标版本号 (如 1.4.0)")
    parser.add_argument("-s", "--show", action="store_true", help="查看当前所有文件记录的版本号")
    parser.add_argument("-d", "--dry-run", action="store_true", help="试运行预览，不写入磁盘")
    parser.add_argument("-v", "--verify", action="store_true", help="同步后运行测试校验")
    parser.add_argument("-c", "--commit", action="store_true", help="同步后自动 Git 提交")
    args = parser.parse_args()

    if args.show or not args.version:
        records = inspect_versions()
        print("=" * 64)
        print("  谛听 (DITING) 各模块版本号概览")
        print("=" * 64)
        for r in records:
            print(f"  {r['name']:<16} : {r['version']:<10} ({r['rel_path']})")
        print("=" * 64)
        sys.exit(0)

    res = sync_version(args.version, dry_run=args.dry_run, verify=args.verify, commit=args.commit)
    sys.exit(0 if res["success"] else 1)


if __name__ == "__main__":
    main()
