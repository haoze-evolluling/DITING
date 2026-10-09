#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) Windows 端构建与安装包打包引擎
纯 Python 驱动，支持特权服务、Wails 前端与 NSIS 安装包流水线编译及环境预检。
"""

import argparse
import datetime
import os
import shutil
import subprocess
import sys
from typing import Callable, Dict, List, Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)

from maintenance.core.runner import stream_process_output


def get_root_dir() -> str:
    return ROOT_DIR


def find_tool(name: str, extra_paths: Optional[List[str]] = None) -> Optional[str]:
    cmd = shutil.which(name)
    if cmd:
        return cmd
    if extra_paths:
        for p in extra_paths:
            candidate = os.path.join(p, f"{name}.exe" if sys.platform == "win32" else name)
            if os.path.exists(candidate):
                return candidate
    return None


def check_toolchain() -> Dict[str, dict]:
    nsis_extra = ["C:\\Program Files (x86)\\NSIS", "C:\\Program Files\\NSIS"]
    tools = {
        "go": {"found": False, "version": "", "cmd": shutil.which("go")},
        "git": {"found": False, "version": "", "cmd": shutil.which("git")},
        "wails": {"found": False, "version": "", "cmd": shutil.which("wails")},
        "node": {"found": False, "version": "", "cmd": shutil.which("node")},
        "nsis": {"found": False, "version": "", "cmd": find_tool("makensis", nsis_extra)},
    }

    if tools["go"]["cmd"]:
        try:
            out = subprocess.check_output([tools["go"]["cmd"], "version"], text=True).strip()
            tools["go"]["found"] = True
            tools["go"]["version"] = out.replace("go version ", "")
        except Exception:
            pass

    if tools["git"]["cmd"]:
        try:
            out = subprocess.check_output([tools["git"]["cmd"], "--version"], text=True).strip()
            tools["git"]["found"] = True
            tools["git"]["version"] = out
        except Exception:
            pass

    if tools["wails"]["cmd"]:
        try:
            out = subprocess.check_output([tools["wails"]["cmd"], "version"], text=True, stderr=subprocess.STDOUT).splitlines()
            tools["wails"]["found"] = True
            tools["wails"]["version"] = out[0] if out else "已安装"
        except Exception:
            tools["wails"]["found"] = True
            tools["wails"]["version"] = "已安装"

    if tools["node"]["cmd"]:
        try:
            out = subprocess.check_output([tools["node"]["cmd"], "-v"], text=True).strip()
            tools["node"]["found"] = True
            tools["node"]["version"] = out
        except Exception:
            pass

    if tools["nsis"]["cmd"]:
        try:
            out = subprocess.check_output([tools["nsis"]["cmd"], "/VERSION"], text=True).strip()
            tools["nsis"]["found"] = True
            tools["nsis"]["version"] = f"v{out}"
        except Exception:
            tools["nsis"]["found"] = True
            tools["nsis"]["version"] = "已安装"

    return tools


def format_size(bytes_num: int) -> str:
    if bytes_num >= 1024 * 1024 * 1024:
        return f"{bytes_num / (1024**3):.2f} GB"
    elif bytes_num >= 1024 * 1024:
        return f"{bytes_num / (1024**2):.2f} MB"
    elif bytes_num >= 1024:
        return f"{bytes_num / 1024:.2f} KB"
    return f"{bytes_num} B"


def run_cmd_live(cmd: list, cwd: str, on_log: Callable[[str, str], None], is_cancelled: Callable[[], bool], env: Optional[dict] = None) -> bool:
    return stream_process_output(cmd=cmd, cwd=cwd, on_log=on_log, is_cancelled=is_cancelled, env=env) == 0


def build_pipeline(
    target: str = "all",
    version: str = "1.3.1",
    build_type: str = "release",
    clean: bool = False,
    skip_check: bool = False,
    on_log: Optional[Callable[[str, str], None]] = None,
    is_cancelled: Optional[Callable[[], bool]] = None,
) -> dict:
    if not on_log:
        on_log = lambda lvl, msg: print(f"[{lvl.upper()}] {msg}")
    if not is_cancelled:
        is_cancelled = lambda: False

    root = get_root_dir()
    windows_dir = os.path.join(root, "Windows")
    bin_dir = os.path.join(windows_dir, "build", "bin")

    on_log("info", "=" * 50)
    on_log("info", f"谛听 (DITING) 构建任务启动: Target={target}, Ver={version}, Type={build_type}")
    on_log("info", "=" * 50)

    # 1. 前置依赖检查
    tools = check_toolchain()
    if not skip_check:
        if not tools["go"]["found"]:
            on_log("error", "未找到 Go 环境，无法继续编译。")
            return {"success": False, "message": "缺少 Go 环境"}
        if target in ("all", "gui", "installer") and not tools["wails"]["found"]:
            on_log("error", "未找到 Wails CLI，请执行: go install github.com/wailsapp/wails/v2/cmd/wails@latest")
            return {"success": False, "message": "缺少 Wails CLI"}
        if target in ("all", "gui", "installer") and not tools["node"]["found"]:
            on_log("error", "未找到 Node.js，前端客户端编译需要 Node.js。")
            return {"success": False, "message": "缺少 Node.js"}
        if target in ("all", "installer") and not tools["nsis"]["found"]:
            on_log("error", "未找到 makensis，无法打包 NSIS 安装包。")
            return {"success": False, "message": "缺少 NSIS"}

    # 2. 清理
    if clean and os.path.exists(bin_dir):
        on_log("info", f"清理旧构建产物: {bin_dir}")
        shutil.rmtree(bin_dir, ignore_errors=True)
    os.makedirs(bin_dir, exist_ok=True)

    git_commit = "unknown"
    try:
        git_commit = subprocess.check_output(["git", "-C", root, "rev-parse", "--short", "HEAD"], text=True).strip()
    except Exception:
        pass
    build_time = datetime.datetime.now().astimezone().isoformat()

    is_rel = build_type.lower() == "release"
    ldflags = f"-s -w -X 'main.Version={version}' -X 'main.GitCommit={git_commit}' -X 'main.BuildTime={build_time}'" if is_rel else f"-X 'main.Version={version}' -X 'main.GitCommit={git_commit}' -X 'main.BuildTime={build_time}'"

    built_artifacts = []

    # 3. 编译特权服务
    if target in ("all", "service"):
        on_log("info", ">>> 正在编译 Windows 特权服务 (diting-service.exe)...")
        service_bin = os.path.join(bin_dir, "diting-service.exe")
        cmd_svc = ["go", "build", "-ldflags", f"-s -w -H windowsgui -X main.Version={version}", "-o", service_bin, "./cmd/service"]
        ok = run_cmd_live(cmd_svc, cwd=windows_dir, on_log=on_log, is_cancelled=is_cancelled)
        if not ok:
            return {"success": False, "message": "特权服务编译失败"}
        if os.path.exists(service_bin):
            sz = os.path.getsize(service_bin)
            on_log("info", f"[OK] 特权服务编译成功: {service_bin} ({format_size(sz)})")
            built_artifacts.append(service_bin)

    # 4. 编译 Wails GUI
    if target in ("all", "gui"):
        on_log("info", ">>> 正在使用 Wails 编译 GUI 客户端 (diting-gui.exe)...")
        wails_cmd = [tools["wails"]["cmd"] or "wails", "build", "-platform", "windows/amd64", "-o", "diting-gui.exe", "-ldflags", ldflags]
        if not is_rel:
            wails_cmd.append("-debug")
        ok = run_cmd_live(wails_cmd, cwd=windows_dir, on_log=on_log, is_cancelled=is_cancelled)
        if not ok:
            return {"success": False, "message": "GUI 客户端编译失败"}
        gui_bin = os.path.join(bin_dir, "diting-gui.exe")
        if os.path.exists(gui_bin):
            sz = os.path.getsize(gui_bin)
            on_log("info", f"[OK] GUI 客户端编译成功: {gui_bin} ({format_size(sz)})")
            built_artifacts.append(gui_bin)

    # 5. 打包 NSIS 安装包
    if target in ("all", "installer"):
        on_log("info", ">>> 正在打包 NSIS 独立安装包...")
        nsis_exe = tools["nsis"]["cmd"] or "makensis"
        nsi_script = os.path.join(windows_dir, "build", "windows", "installer", "project.nsi")
        installer_name = f"DITING-{build_type.lower()}-v{version}.exe"
        installer_path = os.path.join(bin_dir, installer_name)
        cmd_nsis = [nsis_exe, f"-DPRODUCT_VERSION={version}", f"-DOUTPUT_FILENAME={installer_path}", nsi_script]
        ok = run_cmd_live(cmd_nsis, cwd=windows_dir, on_log=on_log, is_cancelled=is_cancelled)
        if not ok:
            return {"success": False, "message": "NSIS 安装包打包失败"}
        if os.path.exists(installer_path):
            sz = os.path.getsize(installer_path)
            on_log("info", f"[OK] 安装包打包成功: {installer_path} ({format_size(sz)})")
            built_artifacts.append(installer_path)

    on_log("info", f"=== 全部构建流水线执行完毕，生成 {len(built_artifacts)} 个产物 ===")
    return {
        "success": True,
        "bin_dir": bin_dir,
        "artifacts": built_artifacts,
        "target": target,
        "version": version,
    }


def main():
    parser = argparse.ArgumentParser(description="谛听 Windows 构建工具")
    parser.add_argument("-t", "--target", choices=["all", "service", "gui", "installer"], default="all")
    parser.add_argument("-v", "--version", default="1.3.1")
    parser.add_argument("-b", "--build-type", choices=["release", "debug"], default="release")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--skip-check", action="store_true")
    args = parser.parse_args()

    res = build_pipeline(target=args.target, version=args.version, build_type=args.build_type, clean=args.clean, skip_check=args.skip_check)
    sys.exit(0 if res["success"] else 1)


if __name__ == "__main__":
    main()
