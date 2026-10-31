#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 统一版本号管理引擎
支持跨桌面端、Android、安装包、脚本与前端配置的版本号统一检测、同步、MD5 校验与 Git 提交。
"""

import argparse
import hashlib
import json
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


# 版本号分组：Flutter 主力工程独立维护（版本号与桌面端早已分叉），
# 桌面端等其余模块合并在折叠区里，平时不展开。
GROUP_FLUTTER = "flutter"
GROUP_COMMON = "common"
ALL_GROUPS = (GROUP_FLUTTER, GROUP_COMMON)


def get_file_targets(groups: Optional[List[str]] = None) -> List[Dict[str, str]]:
    """按分组返回待维护的文件清单；groups 为空表示全部。"""
    root = get_root_dir()
    desktop = os.path.join(root, "Desktop")
    frontend = os.path.join(desktop, "frontend")
    flutter = os.path.join(root, "DITING-Flutter")
    targets = [
        {"name": "桌面端主程序", "path": os.path.join(desktop, "main.go"), "type": "go", "group": GROUP_COMMON},
        {"name": "Linux 端主程序", "path": os.path.join(desktop, "main_linux.go"), "type": "go", "group": GROUP_COMMON},
        {"name": "Linux 构建脚本", "path": os.path.join(desktop, "build_linux.sh"), "type": "sh", "group": GROUP_COMMON},
        {"name": "特权服务", "path": os.path.join(desktop, "cmd", "service", "main.go"), "type": "go", "group": GROUP_COMMON},
        {"name": "NSIS 主配置", "path": os.path.join(desktop, "build", "windows", "installer", "project.nsi"), "type": "nsi", "group": GROUP_COMMON},
        {"name": "NSIS 工具模板", "path": os.path.join(desktop, "build", "windows", "installer", "wails_tools.nsh"), "type": "nsi", "group": GROUP_COMMON},
        {"name": "Wails 配置", "path": os.path.join(desktop, "wails.json"), "type": "wails", "group": GROUP_COMMON},
        {"name": "前端 package.json", "path": os.path.join(frontend, "package.json"), "type": "pkg", "group": GROUP_COMMON},
        {"name": "前端锁文件", "path": os.path.join(frontend, "package-lock.json"), "type": "pkg-lock", "group": GROUP_COMMON},
        {"name": "Flutter 客户端版本（DITING-Flutter）", "path": os.path.join(flutter, "pubspec.yaml"), "type": "pubspec", "group": GROUP_FLUTTER},
        {"name": "README 版本示例", "path": os.path.join(root, "README.md"), "type": "readme", "group": GROUP_COMMON},
    ]
    if not groups:
        return targets
    wanted = {g for g in groups if g}
    return [t for t in targets if t["group"] in wanted]



def read_file(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def write_file(path: str, content: str):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


def _android_version_code(version: str) -> Optional[int]:
    """由语义化版本推导 Android versionCode，保证单调递增且可重复执行。"""
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)", version)
    if not m:
        return None
    major, minor, patch = (int(part) for part in m.groups())
    return major * 10000 + minor * 100 + patch


def _replace_lock_version(content: str, new_ver: str) -> Tuple[str, bool]:
    """仅更新 package-lock.json 根节点与 packages[""] 的版本，保持其余结构不变。"""
    try:
        data = json.loads(content)
    except (ValueError, TypeError):
        return content, False

    changed = False
    if isinstance(data.get("version"), str) and data["version"] != new_ver:
        data["version"] = new_ver
        changed = True

    packages = data.get("packages")
    root_pkg = packages.get("") if isinstance(packages, dict) else None
    if isinstance(root_pkg, dict) and isinstance(root_pkg.get("version"), str) and root_pkg["version"] != new_ver:
        root_pkg["version"] = new_ver
        changed = True

    if not changed:
        return content, False
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n", True


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
    elif ftype == "pkg-lock":
        try:
            data = json.loads(content)
        except (ValueError, TypeError):
            return "解析失败"
        packages = data.get("packages")
        root_pkg = packages.get("") if isinstance(packages, dict) else None
        ver = None
        if isinstance(root_pkg, dict):
            ver = root_pkg.get("version")
        ver = ver or data.get("version")
        if ver: return str(ver)
    elif ftype == "pubspec":
        m = re.search(r'(?m)^version:\s*([^\s+#]+)(?:\+(\d+))?', content)
        if m:
            return m.group(1)
    elif ftype == "readme":
        m = re.search(r'set_version\.bat\s+(\d+\.\d+\.\d+)', content)
        if m: return m.group(1)
    elif ftype == "sh":
        m = re.search(r'build_linux\.sh\s+-v\s+(\d+\.\d+\.\d+)', content)
        if m: return m.group(1)

    return "未知"


def replace_version_content(content: str, ftype: str, new_ver: str) -> Tuple[str, bool]:
    if ftype == "go":
        new_content, n = re.subn(r'(?m)^(\s*(?:ServiceVersion|AppVersion|Version)\s*=\s*")[^"]+(")', rf'\g<1>{new_ver}\g<2>', content)
        if n > 0 and new_content != content: return new_content, True
    elif ftype in ("nsi", "nsh"):
        new_content, n = re.subn(r'(!define INFO_PRODUCTVERSION\s+")[^"]+(")', rf'\g<1>{new_ver}\g<2>', content)
        if n > 0 and new_content != content: return new_content, True
    elif ftype == "wails":
        new_content, n = re.subn(r'("productVersion":\s*")[^"]+(")', rf'\g<1>{new_ver}\g<2>', content)
        if n > 0 and new_content != content: return new_content, True
    elif ftype == "pkg":
        new_content, n = re.subn(r'("version":\s*")[^"]+(")', rf'\g<1>{new_ver}\g<2>', content)
        if n > 0 and new_content != content: return new_content, True
    elif ftype == "pkg-lock":
        return _replace_lock_version(content, new_ver)
    elif ftype == "readme":
        new_content, n = re.subn(r'(set_version\.bat\s+)\d+\.\d+\.\d+', rf'\g<1>{new_ver}', content)
        if n > 0 and new_content != content: return new_content, True
    elif ftype == "pubspec":
        # pubspec.yaml 的 `version: <name>+<code>`：版本名跟随目标，构建号按
        # major*10000 + minor*100 + patch 推导，且只增不减（避免被当作降级包）。
        m = re.search(r'(?m)^(version:\s*)([^\s+#]+)(?:\+(\d+))?', content)
        if m:
            code = _android_version_code(new_ver)
            old_code = int(m.group(3)) if m.group(3) else 0
            final_code = max(code or 0, old_code)
            suffix = f"+{final_code}" if final_code > 0 else ""
            new_content = content[:m.start()] + f"{m.group(1)}{new_ver}{suffix}" + content[m.end():]
            if new_content != content:
                return new_content, True
    elif ftype == "sh":
        new_content, n = re.subn(r'(build_linux\.sh\s+-v\s+)\d+\.\d+\.\d+', rf'\g<1>{new_ver}', content)
        if n > 0 and new_content != content: return new_content, True

    return content, False


def inspect_versions(groups: Optional[List[str]] = None) -> List[Dict[str, str]]:
    root = get_root_dir()
    targets = get_file_targets(groups)
    results = []
    for item in targets:
        ver = extract_version(item)
        rel_path = os.path.relpath(item["path"], root).replace("\\", "/")
        results.append({
            "name": item["name"],
            "path": item["path"],
            "rel_path": rel_path,
            "type": item["type"],
            "group": item.get("group", GROUP_COMMON),
            "version": ver,
            "exists": os.path.exists(item["path"]),
        })
    return results


def get_current_version(groups: Optional[List[str]] = None) -> str:
    """动态读取并返回当前代码库核心配置中的最新有效版本号"""
    if groups is None:
        # 默认只读桌面端/共用分组：Flutter 工程的版本号已独立演进，
        # 混进来会让桌面端构建脚本取到错误的默认版本。
        groups = [GROUP_COMMON]
    targets = get_file_targets(groups)
    for item in targets:
        ver = extract_version(item)
        if ver and ver not in ("未知", "文件不存在", "解析失败"):
            return ver
    return "0.0.0"


def sync_version(
    target_version: str,
    dry_run: bool = False,
    verify: bool = False,
    commit: bool = False,
    on_log: Optional[Callable[[str, str], None]] = None,
    groups: Optional[List[str]] = None,
) -> dict:
    target_ver = target_version.strip().lstrip("v")
    if not target_ver:
        return {"success": False, "message": "目标版本号不可为空"}

    root = get_root_dir()
    targets = get_file_targets(groups)
    modified_files = []

    def _log(lvl, msg):
        if on_log:
            on_log(lvl, msg)
        else:
            print(f"[{lvl.upper()}] {msg}")

    scope = "全部模块" if not groups else "、".join(groups)
    _log("info", f"开始同步版本号至: v{target_ver}，范围: {scope} (DryRun={dry_run})")

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

    # 同步更新本地 package.json.md5 校验文件 (已在 .gitignore 中，不纳入 Git 跟踪)
    pkg_path = os.path.join(root, "Desktop", "frontend", "package.json")
    pkg_md5_path = os.path.join(root, "Desktop", "frontend", "package.json.md5")
    if os.path.exists(pkg_path):
        with open(pkg_path, "rb") as f:
            h = hashlib.md5(f.read()).hexdigest()
        if not dry_run:
            with open(pkg_md5_path, "w", encoding="utf-8") as f:
                f.write(h)
            _log("info", f"[已更新本地缓存] 前端 package.json MD5 哈希: {h[:8]}...")

    if verify and not dry_run:
        _log("info", "正在运行 Go 编译测试以验证版本语法...")
        cmd = ["go", "test", "./..."]
        p = subprocess.run(cmd, cwd=os.path.join(root, "Desktop"), capture_output=True, text=True)
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
    parser.add_argument(
        "-g",
        "--group",
        action="append",
        choices=list(ALL_GROUPS),
        help="只处理指定分组（flutter / common），可重复；缺省为全部",
    )
    args = parser.parse_args()

    if args.show or not args.version:
        records = inspect_versions(args.group)
        print("=" * 64)
        print("  谛听 (DITING) 各模块版本号概览")
        print("=" * 64)
        for r in records:
            print(f"  {r['name']:<16} : {r['version']:<10} ({r['rel_path']})")
        print("=" * 64)
        sys.exit(0)

    res = sync_version(
        args.version,
        dry_run=args.dry_run,
        verify=args.verify,
        commit=args.commit,
        groups=args.group,
    )
    sys.exit(0 if res["success"] else 1)


if __name__ == "__main__":
    main()
