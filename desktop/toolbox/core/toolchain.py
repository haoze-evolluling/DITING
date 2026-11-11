#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""谛听 (DITING) 构建工具链探测。

与 `desktop/build_installer.bat` 的预检保持同一口径：除了 Go / Flutter / NSIS / Rust（cargo，
特权服务的印章内核是 Rust 库），Windows 上打 EXE 还必须具备 MSVC C++ 工具链，打 DEB 则依赖 WSL。
结果带短时缓存，避免每次切换页面都重新执行 `flutter --version`（约 5-8 秒）。
"""

import copy
import os
import shutil
import subprocess
import sys
import time
from typing import Dict, List, Optional

_CACHE_TTL = 60.0
_cache: Dict[str, object] = {"timestamp": 0.0, "data": None}


def find_tool(name: str, extra_paths: Optional[List[str]] = None) -> Optional[str]:
    cmd = shutil.which(name)
    if cmd:
        return cmd
    if extra_paths:
        for base in extra_paths:
            candidate = os.path.join(base, f"{name}.exe" if sys.platform == "win32" else name)
            if os.path.exists(candidate):
                return candidate
    return None


def _probe_version(cmd: str, args: List[str], prefix: str = "") -> str:
    try:
        output = subprocess.check_output(
            [cmd, *args],
            text=True,
            encoding="utf-8",
            errors="replace",
            stderr=subprocess.STDOUT,
        ).strip()
    except Exception:
        return ""
    if not output:
        return ""
    first_line = output.splitlines()[0].strip()
    if prefix and first_line.startswith(prefix):
        return first_line[len(prefix):].strip()
    return first_line


def _detect_msvc() -> Dict[str, object]:
    """通过 vswhere 探测 Visual Studio 的 C++ 桌面开发工作负载。"""
    if sys.platform != "win32":
        return {"found": False, "version": "", "cmd": None}

    program_files_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    vswhere = os.path.join(program_files_x86, "Microsoft Visual Studio", "Installer", "vswhere.exe")
    if not os.path.exists(vswhere):
        return {"found": False, "version": "", "cmd": None}

    try:
        install_path = subprocess.check_output(
            [
                vswhere,
                "-latest",
                "-products",
                "*",
                "-requires",
                "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                "-property",
                "installationPath",
            ],
            text=True,
            encoding="utf-8",
            errors="replace",
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        install_path = ""

    if not install_path:
        fallback = os.environ.get("VSINSTALLDIR", "")
        install_path = fallback.strip()
    if not install_path:
        return {"found": False, "version": "", "cmd": vswhere}

    parts = install_path.replace("/", "\\").split("\\")
    label = install_path
    if "Microsoft Visual Studio" in parts:
        index = parts.index("Microsoft Visual Studio")
        label = "VS " + " ".join(part for part in parts[index + 1:] if part)
    return {"found": True, "version": label, "cmd": vswhere}


def _detect_wsl() -> Dict[str, object]:
    if sys.platform != "win32":
        return {"found": False, "version": "", "cmd": None}
    cmd = shutil.which("wsl")
    if not cmd:
        return {"found": False, "version": "", "cmd": None}
    return {"found": True, "version": "已安装", "cmd": cmd}


def check_toolchain(force: bool = False) -> Dict[str, dict]:
    """返回构建工具链状态；force=True 跳过缓存（重新检测按钮使用）。"""
    now = time.time()
    cached = _cache.get("data")
    if not force and cached is not None and now - float(_cache.get("timestamp", 0.0)) < _CACHE_TTL:
        return copy.deepcopy(cached)  # type: ignore[return-value]

    nsis_extra = ["C:\\Program Files (x86)\\NSIS", "C:\\Program Files\\NSIS"]
    tools: Dict[str, dict] = {
        "go": {"found": False, "version": "", "cmd": shutil.which("go")},
        "git": {"found": False, "version": "", "cmd": shutil.which("git")},
        "flutter": {"found": False, "version": "", "cmd": shutil.which("flutter")},
        "nsis": {"found": False, "version": "", "cmd": find_tool("makensis", nsis_extra)},
        "cargo": {"found": False, "version": "", "cmd": shutil.which("cargo")},
    }
    if sys.platform == "win32":
        tools["msvc"] = _detect_msvc()
        tools["wsl"] = _detect_wsl()

    if tools["go"]["cmd"]:
        version = _probe_version(tools["go"]["cmd"], ["version"], "go version ")
        if version:
            tools["go"].update(found=True, version=version)

    if tools["git"]["cmd"]:
        version = _probe_version(tools["git"]["cmd"], ["--version"])
        if version:
            tools["git"].update(found=True, version=version)

    if tools["flutter"]["cmd"]:
        version = _probe_version(tools["flutter"]["cmd"], ["--version"], "Flutter ")
        tools["flutter"].update(found=True, version=version or "已安装")

    if tools["cargo"]["cmd"]:
        version = _probe_version(tools["cargo"]["cmd"], ["--version"], "cargo ")
        if version:
            tools["cargo"].update(found=True, version=version)

    if tools["nsis"]["cmd"]:
        version = _probe_version(tools["nsis"]["cmd"], ["/VERSION"])
        if version:
            tools["nsis"].update(found=True, version=version if version.lower().startswith("v") else f"v{version}")
        else:
            tools["nsis"].update(found=True, version="已安装")

    _cache["timestamp"] = now
    _cache["data"] = copy.deepcopy(tools)
    return tools
