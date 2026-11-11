#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""谛听 (DITING) 版本号单一真源管理。

`desktop/app/pubspec.yaml` 的 `version: X.Y.Z+构建号` 是桌面端唯一的版本字面量
（Flutter 工具链强制要求它存在），其余位置一律在构建期从它派生，不再各存一份：

  * `diting-service.exe` / Linux 二进制：`go build -X main.Version=<pubspec 版本名>`
  * Windows 安装包：`makensis -DINFO_PRODUCTVERSION=<pubspec 版本名>`
  * Linux `.deb`：`build_linux.sh` 自己从 pubspec 读

所以日常升级版本号只改这一行（或用 `set_version.bat` / 本工具写这一行），
派生位置一旦又被写回硬编码，`inspect_versions` / `-s` 会直接标出来。
Android 客户端（`android/app/pubspec.yaml`）属于独立产品线，按需单独维护。
"""

import argparse
import os
import re
import subprocess
import sys
from typing import Callable, Dict, List, Optional, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

try:  # 作为 toolbox.core 包导入
    from .paths import DESKTOP_APP_DIR, ANDROID_APP_DIR, SERVICE_DIR, INSTALLER_DIR, ROOT_DIR
    from .paths import relative as rel_path
except ImportError:  # 直接以脚本运行（python desktop/toolbox/core/version_manager.py）
    from paths import DESKTOP_APP_DIR, ANDROID_APP_DIR, SERVICE_DIR, INSTALLER_DIR, ROOT_DIR
    from paths import relative as rel_path

GROUP_DESKTOP = "desktop"
GROUP_ANDROID = "android"
ALL_GROUPS = (GROUP_DESKTOP, GROUP_ANDROID)
# 历史上的分组名（common 混装服务端与桌面端、flutter 混装两个 pubspec）仍可用，
# 保证旧脚本与旧文档里的命令不至于直接报错。
GROUP_ALIASES = {"common": GROUP_DESKTOP, "flutter": GROUP_ANDROID}

# 唯一真源：桌面端 pubspec.yaml
DESKTOP_PUBSPEC = os.path.join(DESKTOP_APP_DIR, "pubspec.yaml")
ANDROID_PUBSPEC = os.path.join(ANDROID_APP_DIR, "pubspec.yaml")

_PUBSPEC_VERSION_RE = re.compile(r"(?m)^(version:\s*)([^\s+#]+)(?:\+(\d+))?")
_SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def build_number(version: str) -> Optional[int]:
    """由语义化版本推导构建号：major*10000 + minor*100 + patch。"""
    m = _SEMVER_RE.match(version.strip())
    if not m:
        return None
    major, minor, patch = (int(part) for part in m.groups())
    return major * 10000 + minor * 100 + patch


def _normalize_groups(groups: Optional[List[str]]) -> List[str]:
    if not groups:
        return [GROUP_DESKTOP]
    wanted: List[str] = []
    for raw in groups:
        name = (raw or "").strip().lower()
        name = GROUP_ALIASES.get(name, name)
        if name in ALL_GROUPS and name not in wanted:
            wanted.append(name)
    return wanted or [GROUP_DESKTOP]


def source_targets() -> List[Dict[str, str]]:
    """存版本字面量、需要被写入的文件（每个分组一份）。"""
    return [
        {
            "group": GROUP_DESKTOP,
            "name": "桌面端（唯一真源）",
            "path": DESKTOP_PUBSPEC,
            "note": "go build / NSIS / deb 全部从这里派生",
        },
        {
            "group": GROUP_ANDROID,
            "name": "Android 客户端",
            "path": ANDROID_PUBSPEC,
            "note": "独立产品线，按需单独升级",
        },
    ]


def derived_targets() -> List[Dict[str, str]]:
    """不存版本字面量、由构建脚本注入版本号的位置。"""
    return [
        {
            "name": "Windows 特权服务",
            "path": os.path.join(SERVICE_DIR, "cmd", "service", "main.go"),
            "type": "go",
            "via": "go build -X main.Version",
        },
        {
            "name": "Windows 安装包",
            "path": os.path.join(INSTALLER_DIR, "project.nsi"),
            "type": "nsi",
            "via": "makensis -DINFO_PRODUCTVERSION",
        },
        {
            "name": "Linux 安装包",
            "path": os.path.join(SERVICE_DIR, "build_linux.sh"),
            "type": "sh",
            "via": "build_linux.sh 读 pubspec.yaml",
        },
    ]


def read_file(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def write_file(path: str, content: str) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


def parse_pubspec_version(content: str) -> Tuple[str, Optional[int]]:
    """从 pubspec 文本里取出 (版本名, 构建号)。"""
    m = _PUBSPEC_VERSION_RE.search(content)
    if not m:
        return "", None
    code = int(m.group(3)) if m.group(3) else None
    return m.group(2), code


def get_pubspec_version(path: str) -> Tuple[str, Optional[int]]:
    if not os.path.exists(path):
        return "", None
    return parse_pubspec_version(read_file(path))


def pubspec_with_version(content: str, version: str) -> Tuple[str, bool]:
    """把 pubspec 的 version 行改成 `version: <name>+<构建号>`。

    构建号按 major*10000+minor*100+patch 推导，并且只增不减，
    避免系统把新包当成降级包。
    """
    m = _PUBSPEC_VERSION_RE.search(content)
    if not m:
        return content, False
    derived = build_number(version) or 0
    old_code = int(m.group(3)) if m.group(3) else 0
    final_code = max(derived, old_code)
    suffix = f"+{final_code}" if final_code > 0 else ""
    new_content = content[: m.start()] + f"{m.group(1)}{version}{suffix}" + content[m.end():]
    return new_content, new_content != content


def _derived_literal(item: Dict[str, str]) -> Optional[str]:
    """派生位置里若还留着版本字面量，返回它，否则返回 None。"""
    path = item["path"]
    if not os.path.exists(path):
        return None
    content = read_file(path)
    ftype = item["type"]
    if ftype == "go":
        m = re.search(r'(?m)^\s*Version\s*=\s*"([^"]*)"', content)
        if m and m.group(1).strip().lower() not in ("", "dev"):
            return m.group(1)
        return None
    if ftype == "nsi":
        m = re.search(r'(?m)^\s*!define INFO_PRODUCTVERSION\s+"([^"]*)"', content)
        return m.group(1) if m else None
    if ftype == "sh":
        # 构建脚本本身不存版本，但它若回去 grep 源码字面量就说明派生链断了
        return None if "pubspec.yaml" in content else "cmd/service/main.go 里的 Version 字面量"
    return None


def inspect_versions(groups: Optional[List[str]] = None) -> List[Dict[str, object]]:
    """列出当前版本状态：真源各行 + 桌面端派生位置（含硬编码告警）。"""
    wanted = _normalize_groups(groups)
    desktop_version, desktop_code = get_pubspec_version(DESKTOP_PUBSPEC)
    items: List[Dict[str, object]] = []

    for target in source_targets():
        if target["group"] not in wanted:
            continue
        version, code = get_pubspec_version(target["path"])
        items.append(
            {
                "name": target["name"],
                "rel_path": rel_path(target["path"]),
                "version": version,
                "build_number": code,
                "kind": "source",
                "group": target["group"],
                "note": target["note"],
                "hardcoded": None,
                "exists": os.path.exists(target["path"]),
            }
        )

    if GROUP_DESKTOP in wanted:
        for target in derived_targets():
            literal = _derived_literal(target)
            items.append(
                {
                    "name": target["name"],
                    "rel_path": rel_path(target["path"]),
                    "version": desktop_version,
                    "build_number": desktop_code,
                    "kind": "derived",
                    "group": GROUP_DESKTOP,
                    "note": target["via"],
                    "hardcoded": literal,
                    "exists": os.path.exists(target["path"]),
                }
            )
    return items


def get_current_version(groups: Optional[List[str]] = None) -> str:
    """当前版本号：桌面端统一取唯一真源，Android 取自己的 pubspec。"""
    wanted = _normalize_groups(groups)
    if GROUP_ANDROID in wanted and GROUP_DESKTOP not in wanted:
        version, _ = get_pubspec_version(ANDROID_PUBSPEC)
        return version or "0.0.0"
    version, _ = get_pubspec_version(DESKTOP_PUBSPEC)
    return version or "0.0.0"


def drift_report(groups: Optional[List[str]] = None) -> List[Dict[str, str]]:
    """派生位置里残留的硬编码版本号，用于验证与提示。"""
    wanted = _normalize_groups(groups)
    if GROUP_DESKTOP not in wanted:
        return []
    drifts = []
    for target in derived_targets():
        literal = _derived_literal(target)
        if literal:
            drifts.append({"name": target["name"], "rel_path": rel_path(target["path"]), "literal": literal})
    return drifts


def sync_version(
    target_version: str,
    dry_run: bool = False,
    verify: bool = False,
    commit: bool = False,
    on_log: Optional[Callable[[str, str], None]] = None,
    groups: Optional[List[str]] = None,
) -> dict:
    """写入唯一真源（以及按需的 Android pubspec），并检查派生位置是否干净。"""
    target_ver = (target_version or "").strip().lstrip("v")
    if not _SEMVER_RE.match(target_ver):
        return {"success": False, "message": f"版本号需形如 2.2.11，收到: {target_version!r}"}

    def _log(level: str, message: str) -> None:
        if on_log:
            on_log(level, message)
        else:
            print(f"[{level.upper()}] {message}")

    wanted = _normalize_groups(groups)
    scope = "、".join(wanted)
    _log("info", f"开始同步版本号至 v{target_ver}，范围: {scope}（预览={dry_run}）")

    modified: List[str] = []
    for target in source_targets():
        if target["group"] not in wanted:
            continue
        path = target["path"]
        rel = rel_path(path)
        if not os.path.exists(path):
            _log("warn", f"跳过不存在的文件: {rel}")
            continue
        old_content = read_file(path)
        new_content, changed = pubspec_with_version(old_content, target_ver)
        if not changed:
            version, code = parse_pubspec_version(old_content)
            _log("info", f"{target['name']} 已是 v{version}（构建号 {code}），无需修改: {rel}")
            continue
        modified.append(rel)
        if dry_run:
            _log("info", f"[预览] 将修改 {target['name']}: {rel}")
            continue
        write_file(path, new_content)
        _log("info", f"[已更新] {target['name']}: {rel}")

    drifts = drift_report(wanted)
    for drift in drifts:
        _log("warn", f"{drift['name']} 仍硬编码 {drift['literal']}，应改为构建期注入: {drift['rel_path']}")

    if verify and not drifts:
        _log("info", "派生位置校验通过：服务端 / NSIS / deb 均不再硬编码版本号。")
    if verify and drifts:
        return {
            "success": False,
            "message": f"仍有 {len(drifts)} 处硬编码版本号，已中止",
            "target_version": target_ver,
            "modified_files": modified,
            "groups": wanted,
            "dry_run": dry_run,
            "drifts": drifts,
        }

    if commit and not dry_run and modified:
        root = ROOT_DIR
        for rel in modified:
            subprocess.run(["git", "-C", root, "add", "--", rel], capture_output=True)
        message = f"chore(release): 版本号更新至 v{target_ver}"
        p = subprocess.run(
            ["git", "-C", root, "commit", "-m", message],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if p.returncode == 0:
            _log("info", f"Git 提交成功: {message}")
        else:
            _log("warn", f"Git 提交输出: {p.stdout.strip() or p.stderr.strip()}")

    _log("info", f"版本号同步完成，共影响 {len(modified)} 个文件。")
    return {
        "success": True,
        "target_version": target_ver,
        "modified_files": modified,
        "groups": wanted,
        "dry_run": dry_run,
        "drifts": drifts,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="谛听版本号单一真源工具（真源: desktop/app/pubspec.yaml）")
    parser.add_argument("version", nargs="?", default=None, help="目标版本号 (如 2.2.11)")
    parser.add_argument("-s", "--show", action="store_true", help="查看真源与派生位置的版本状态")
    parser.add_argument("-d", "--dry-run", action="store_true", help="试运行：只打印将改动的文件，不落盘")
    parser.add_argument("-v", "--verify", action="store_true", help="校验派生位置没有残留硬编码版本号")
    parser.add_argument("-c", "--commit", action="store_true", help="同步后自动 Git 提交")
    parser.add_argument(
        "-g",
        "--group",
        action="append",
        choices=list(ALL_GROUPS) + list(GROUP_ALIASES),
        help="只处理指定分组（desktop / android），可重复；缺省只处理 desktop",
    )
    args = parser.parse_args()

    if args.show or not args.version:
        print("=" * 74)
        print("  谛听 (DITING) 版本号状态（真源: desktop/app/pubspec.yaml）")
        print("=" * 74)
        for item in inspect_versions(args.group):
            flag = "真源" if item["kind"] == "source" else "派生"
            line = f"  [{flag}] {item['name']:<14} : {item['version']:<8} ({item['rel_path']})"
            print(line)
            if item["kind"] == "derived":
                print(f"           └ {item['note']}")
            if item["hardcoded"]:
                print(f"           └ 警告: 仍硬编码 {item['hardcoded']}，应删除并改为构建期注入")
        print("=" * 74)
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
