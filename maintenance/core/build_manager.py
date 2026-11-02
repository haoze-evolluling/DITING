#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) Windows 端构建与安装包打包引擎
纯 Python 驱动，支持 Flutter 桌面端 Web 控制台产物、特权服务与 NSIS 安装包流水线编译及环境预检。
"""

import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys
from typing import Callable, Dict, List, Optional

if hasattr(sys.stdout, "reconfigure"):
    try:
        if sys.stdout.isatty():
            sys.stdout.reconfigure(errors="replace")
        else:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
if hasattr(sys.stderr, "reconfigure"):
    try:
        if sys.stderr.isatty():
            sys.stderr.reconfigure(errors="replace")
        else:
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)

from maintenance.core.runner import stream_process_output


def get_root_dir() -> str:
    return ROOT_DIR


def get_current_project_version() -> str:
    """自动获取当前项目的核心最新版本号（消除硬编码）"""
    try:
        from maintenance.core.version_manager import get_current_version
        v = get_current_version()
        if v and v != "0.0.0":
            return v
    except Exception:
        pass
    return "0.0.0"


def stop_running_processes(on_log: Optional[Callable[[str, str], None]] = None):
    """构建前安全终止旧进程，防止文件占用锁导致编译或打包失败"""
    if sys.platform == "win32":
        for exe in ("diting_desktop.exe", "diting-service.exe"):
            try:
                res = subprocess.run(
                    ["taskkill", "/F", "/T", "/IM", exe],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
                if res.returncode == 0 and on_log:
                    on_log("info", f"已安全终止正在运行的旧进程: {exe}")
            except Exception:
                pass
        return

    # 类 Unix（Linux/macOS）：以 pkill 结束同名进程，未运行时 pkill 返回非零属正常
    for name in ("diting_desktop", "diting-service"):
        if not shutil.which("pkill"):
            break
        try:
            res = subprocess.run(
                ["pkill", "-x", name],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if res.returncode == 0 and on_log:
                on_log("info", f"已安全终止正在运行的旧进程: {name}")
        except Exception:
            pass


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
        "flutter": {"found": False, "version": "", "cmd": shutil.which("flutter")},
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

    if tools["flutter"]["cmd"]:
        try:
            out = subprocess.check_output([tools["flutter"]["cmd"], "--version"], text=True, stderr=subprocess.STDOUT).splitlines()
            tools["flutter"]["found"] = True
            tools["flutter"]["version"] = out[0].replace("Flutter ", "") if out else "已安装"
        except Exception:
            tools["flutter"]["found"] = True
            tools["flutter"]["version"] = "已安装"

    if tools["nsis"]["cmd"]:
        try:
            out = subprocess.check_output([tools["nsis"]["cmd"], "/VERSION"], text=True).strip()
            tools["nsis"]["found"] = True
            # makensis /VERSION 自身已带前缀 v（如 v3.12），避免重复显示为 vv3.12
            tools["nsis"]["version"] = out if out.lower().startswith("v") else f"v{out}"
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


def cross_compile_linux_binary(
    server_dir: str,
    bin_dir: str,
    arch: str,
    version: str,
    build_type: str,
    git_commit: str,
    build_time: str,
    on_log: Callable[[str, str], None],
    is_cancelled: Callable[[], bool],
) -> Optional[str]:
    """用本机 Go 交叉编译 Linux 服务二进制，供 WSL 仅做 deb 组装。

    WSL 内不必安装 Go，避免 Windows 与 WSL 两套工具链版本漂移。
    """
    bin_path = os.path.join(bin_dir, "diting-service")
    ldflags = []
    if build_type.lower() == "release":
        ldflags += ["-s", "-w"]
    ldflags += [
        "-X", f"main.Version={version}",
        "-X", f"main.GitCommit={git_commit}",
        "-X", f"main.BuildTime={build_time}",
    ]
    env = os.environ.copy()
    env.update({"GOOS": "linux", "GOARCH": arch, "CGO_ENABLED": "0"})
    on_log("info", f">>> 正在使用本机 Go 交叉编译 Linux 二进制 (linux/{arch})...")
    cmd = ["go", "build", "-trimpath", "-ldflags", " ".join(ldflags), "-o", bin_path, "./cmd/service"]
    if not run_cmd_live(cmd, cwd=server_dir, on_log=on_log, is_cancelled=is_cancelled, env=env):
        return None
    if not os.path.exists(bin_path):
        on_log("error", f"交叉编译未生成二进制: {bin_path}")
        return None
    try:
        with open(bin_path, "rb") as f:
            if f.read(4) != b"\x7fELF":
                on_log("error", f"交叉编译产物不是 Linux ELF 文件: {bin_path}")
                return None
    except OSError as e:
        on_log("error", f"无法校验交叉编译产物: {e}")
        return None
    return bin_path


def build_web_console_assets(
    server_dir: str,
    on_log: Optional[Callable[[str, str], None]] = None,
    is_cancelled: Optional[Callable[[], bool]] = None,
) -> bool:
    """把 Flutter 桌面端构建为 Web 控制台产物，供 Go 服务 embed。"""
    script = os.path.join(server_dir, "build_frontend.py")
    if not os.path.exists(script):
        if on_log:
            on_log("error", f"未找到 Web 控制台构建脚本: {script}")
        return False
    if on_log:
        on_log("info", ">>> 正在构建 Flutter Web 控制台产物 (frontend/dist)...")
    return run_cmd_live(
        [sys.executable, script],
        cwd=server_dir,
        on_log=on_log or (lambda lvl, msg: None),
        is_cancelled=is_cancelled or (lambda: False),
    )


def find_flutter_release_dir(flutter_project: str, build_type: str) -> Optional[str]:
    """定位 `flutter build windows` 的输出目录（新老 Flutter 版本路径不同）。"""
    config = "Release" if build_type.lower() == "release" else "Debug"
    for relative in (
        os.path.join("build", "windows", "x64", "runner", config),
        os.path.join("build", "windows", "runner", config),
    ):
        candidate = os.path.join(flutter_project, relative)
        if os.path.exists(os.path.join(candidate, "diting_desktop.exe")):
            return candidate
    return None


def build_pipeline(
    target: str = "all",
    version: Optional[str] = None,
    build_type: str = "release",
    clean: bool = False,
    skip_check: bool = False,
    on_log: Optional[Callable[[str, str], None]] = None,
    is_cancelled: Optional[Callable[[], bool]] = None,
    arch: str = "amd64",
) -> dict:
    if not on_log:
        on_log = lambda lvl, msg: print(f"[{lvl.upper()}] {msg}")
    if not is_cancelled:
        is_cancelled = lambda: False
    if not version:
        version = get_current_project_version()

    # 版本号会拼入 WSL 命令行与产物文件名，限制字符集以防注入或非法路径
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", version):
        on_log("error", f"非法的版本号: {version} (仅允许字母、数字与 . _ + - 且需以字母或数字开头)")
        return {"success": False, "message": f"非法版本号: {version}"}

    root = get_root_dir()
    server_dir = os.path.join(root, "Server")
    flutter_project = os.path.join(root, "DITING-Flutter", "apps", "diting_desktop")
    bin_dir = os.path.join(server_dir, "build", "bin")
    service_bin = os.path.join(bin_dir, "diting-service.exe")
    app_stage = os.path.join(server_dir, "build", "windows", "app")

    on_log("info", "=" * 50)
    on_log("info", f"谛听 (DITING) 构建任务启动: Target={target}, Ver={version}, Type={build_type}")
    on_log("info", "=" * 50)

    # 1. 终止可能正在运行的实例，防止文件写锁
    stop_running_processes(on_log)

    # 规范化构建目标
    tgt = target.lower().strip()
    if tgt in ("all", "installer"):
        tgt = "exe"

    if tgt not in ("exe", "deb", "both"):
        on_log("error", f"未知的构建目标: {target} (支持: exe, deb, both)")
        return {"success": False, "message": f"不支持的构建目标: {target}"}

    # 2. 前置依赖检查
    tools = check_toolchain()
    need_win = tgt in ("exe", "both")
    need_deb = tgt in ("deb", "both")

    if not skip_check:
        if need_win:
            if not tools["go"]["found"]:
                on_log("error", "未找到 Go 环境，无法继续编译。")
                return {"success": False, "message": "缺少 Go 环境"}
            if not tools["flutter"]["found"]:
                on_log("error", "未找到 Flutter SDK，请把 flutter 加入 PATH。")
                return {"success": False, "message": "缺少 Flutter SDK"}
            if not tools["nsis"]["found"]:
                on_log("error", "未找到 makensis，无法打包 NSIS 安装包。")
                return {"success": False, "message": "缺少 NSIS"}

        if need_deb:
            if not tools["go"]["found"]:
                on_log("error", "未找到 Go 环境，无法交叉编译 Linux 服务。")
                return {"success": False, "message": "缺少 Go 环境"}
            if not tools["flutter"]["found"]:
                on_log("error", "未找到 Flutter SDK，无法构建内嵌 Web 控制台。")
                return {"success": False, "message": "缺少 Flutter SDK"}
            if sys.platform == "win32" and not shutil.which("wsl"):
                on_log("error", "未检测到 WSL 环境。在 Windows 上打包 deb 安装包需要 WSL 支持。")
                return {"success": False, "message": "缺少 WSL 环境"}

    # 3. 清理旧产物
    if clean and os.path.exists(bin_dir):
        on_log("info", f"清理旧构建产物: {bin_dir}")
        shutil.rmtree(bin_dir, ignore_errors=True)
    os.makedirs(bin_dir, exist_ok=True)

    if not build_web_console_assets(server_dir, on_log=on_log, is_cancelled=is_cancelled):
        return {"success": False, "message": "Web 控制台构建失败"}

    git_commit = "unknown"
    try:
        git_commit = subprocess.check_output(["git", "-C", root, "rev-parse", "--short", "HEAD"], text=True).strip()
    except Exception:
        pass
    build_time = datetime.datetime.now().astimezone().isoformat()

    is_rel = build_type.lower() == "release"

    built_artifacts = []

    # 4. 构建 Windows EXE 安装包
    if need_win:
        on_log("info", ">>> [1/3] 正在构建 Flutter Windows 桌面端...")
        # Flutter 的共享资源目录会把调试构建留下的 kernel_blob.bin 一路复制进 Release，
        # 而 Release 用 app.so AOT 运行，不需要这份 ~96MB 的 JIT 内核。
        if is_rel:
            stale_kernel = os.path.join(flutter_project, "build", "flutter_assets", "kernel_blob.bin")
            if os.path.exists(stale_kernel):
                os.remove(stale_kernel)
                on_log("info", "已清理 Flutter 调试构建残留的 kernel_blob.bin")
        flutter_cmd = [tools["flutter"]["cmd"] or "flutter", "build", "windows"]
        flutter_cmd.append("--release" if is_rel else "--debug")
        ok = run_cmd_live(flutter_cmd, cwd=flutter_project, on_log=on_log, is_cancelled=is_cancelled)
        if not ok:
            return {"success": False, "message": "Flutter 桌面端编译失败"}

        release_dir = find_flutter_release_dir(flutter_project, build_type)
        if not release_dir:
            return {"success": False, "message": "未找到 Flutter Windows 产物目录"}

        if is_rel:
            output_kernel = os.path.join(release_dir, "data", "flutter_assets", "kernel_blob.bin")
            if os.path.exists(output_kernel):
                os.remove(output_kernel)
                on_log("info", "已从 Release 产物中移除 kernel_blob.bin")

        if os.path.isdir(app_stage):
            shutil.rmtree(app_stage, ignore_errors=True)
        os.makedirs(os.path.dirname(app_stage), exist_ok=True)
        shutil.copytree(release_dir, app_stage)
        on_log("info", f"     Flutter 产物已暂存: {app_stage}")

        on_log("info", ">>> [2/3] 正在编译 Windows 特权服务 (diting-service.exe)...")
        svc_ldflags = f"{'-s -w ' if is_rel else ''}-H windowsgui -X 'main.Version={version}' -X 'main.GitCommit={git_commit}' -X 'main.BuildTime={build_time}'"
        cmd_svc = ["go", "build", "-ldflags", svc_ldflags, "-o", service_bin, "./cmd/service"]
        ok = run_cmd_live(cmd_svc, cwd=server_dir, on_log=on_log, is_cancelled=is_cancelled)
        if not ok or not os.path.exists(service_bin):
            return {"success": False, "message": "特权服务编译失败"}

        on_log("info", ">>> [3/3] 正在打包 NSIS 独立安装包...")
        installer_dir = os.path.join(server_dir, "build", "windows", "installer")
        nsi_script = os.path.join(installer_dir, "project.nsi")
        if not os.path.exists(nsi_script):
            on_log("error", f"未找到 NSIS 安装脚本: {nsi_script}")
            return {"success": False, "message": "缺少 project.nsi"}

        nsis_exe = tools["nsis"]["cmd"] or "makensis"
        installer_name = f"DITING-{build_type.lower()}-v{version}.exe"
        installer_path = os.path.join(bin_dir, installer_name)
        fallback_installer = os.path.join(bin_dir, "diting-desktop-installer.exe")

        cmd_nsis = [
            nsis_exe,
            "/INPUTCHARSET",
            "UTF8",
            f"-DARG_APP_DIR={app_stage}",
            f"-DARG_SERVICE_BINARY={service_bin}",
            f"-DPRODUCT_VERSION={version}",
            f"-DINFO_PRODUCTVERSION={version}",
            f"-DOUTPUT_FILENAME={installer_path}",
            nsi_script,
        ]
        ok = run_cmd_live(cmd_nsis, cwd=server_dir, on_log=on_log, is_cancelled=is_cancelled)
        if not ok:
            return {"success": False, "message": "NSIS 安装包打包失败"}

        if not os.path.exists(installer_path) and os.path.exists(fallback_installer):
            try:
                shutil.move(fallback_installer, installer_path)
            except Exception:
                pass

        if not os.path.exists(installer_path):
            on_log("error", f"未找到生成的安装包文件: {installer_path}")
            return {"success": False, "message": "未生成预期的 EXE 安装包产物"}

        # 仅保留最终安装包，清理所有中间编译产物
        for temp_path in (service_bin, app_stage, fallback_installer):
            if os.path.isdir(temp_path):
                shutil.rmtree(temp_path, ignore_errors=True)
            elif os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except Exception:
                    pass

        sz = os.path.getsize(installer_path)
        on_log("info", f"[OK] Windows 安装包生成成功 (仅输出安装包): {installer_path} ({format_size(sz)})")
        built_artifacts.append(installer_path)

    # 5. 构建 Linux DEB 安装包
    if need_deb:
        if arch not in ("amd64", "arm64", "arm"):
            return {"success": False, "message": f"不支持的 Linux 架构: {arch}"}
        on_log("info", f">>> 正在打包 Linux 发行包 (.deb, linux/{arch})...")
        # 始终以 bash 显式执行，避免脚本缺失可执行位（如 Windows 克隆检出）导致失败
        if sys.platform == "win32":
            bin_path = cross_compile_linux_binary(
                server_dir, bin_dir, arch, version, build_type, git_commit, build_time,
                on_log=on_log, is_cancelled=is_cancelled,
            )
            if not bin_path:
                return {"success": False, "message": "Linux 二进制交叉编译失败"}
            wsl_dir = server_dir.replace("\\", "/")
            cmd_pkg = ["wsl.exe", "-e", "bash", "-c", f"cd \"$(wslpath '{wsl_dir}')\" && exec bash ./build_linux.sh --package --prebuilt -a {arch} -v {version} -b {build_type}"]
            ok = run_cmd_live(cmd_pkg, cwd=server_dir, on_log=on_log, is_cancelled=is_cancelled)
        else:
            cmd_pkg = ["bash", "./build_linux.sh", "--package", "-a", arch, "-v", version, "-b", build_type]
            ok = run_cmd_live(cmd_pkg, cwd=server_dir, on_log=on_log, is_cancelled=is_cancelled)

        if not ok:
            return {"success": False, "message": "Linux 发行包打包失败"}

        deb_name = f"diting_{version}_linux_{arch}.deb"
        deb_file = os.path.join(bin_dir, deb_name)
        if not os.path.exists(deb_file):
            return {"success": False, "message": "未找到生成的 DEB 安装包产物"}

        # 确保产物目录纯净：清理可能残留的 Linux 单二进制及临时目录
        raw_linux_bin = os.path.join(bin_dir, "diting-service")
        leftover_dir = os.path.join(bin_dir, f"diting_{version}_linux_{arch}")
        if os.path.exists(raw_linux_bin):
            try:
                os.remove(raw_linux_bin)
            except Exception:
                pass
        if os.path.isdir(leftover_dir):
            try:
                shutil.rmtree(leftover_dir, ignore_errors=True)
            except Exception:
                pass

        sz = os.path.getsize(deb_file)
        on_log("info", f"[OK] Debian 安装包生成成功 (仅输出安装包): {deb_file} ({format_size(sz)})")
        built_artifacts.append(deb_file)

    on_log("info", f"=== 全部构建完成，共保留 {len(built_artifacts)} 个纯净安装包 ===")
    for art in built_artifacts:
        on_log("info", f"  * {os.path.basename(art)} ({format_size(os.path.getsize(art))})")

    return {
        "success": True,
        "bin_dir": bin_dir,
        "artifacts": built_artifacts,
        "target": tgt,
        "version": version,
    }


def main():
    parser = argparse.ArgumentParser(description="谛听 (DITING) 纯净安装包构建工具")
    parser.add_argument("-t", "--target", choices=["exe", "deb", "both", "all", "installer"], default="exe", help="构建目标 (默认 exe)")
    parser.add_argument("-v", "--version", default=None, help="目标版本号 (默认自动读取)")
    parser.add_argument("-b", "--build-type", choices=["release", "debug"], default="release")
    parser.add_argument("-a", "--arch", choices=["amd64", "arm64", "arm"], default="amd64", help="Linux 目标架构")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--skip-check", action="store_true")
    args = parser.parse_args()

    res = build_pipeline(target=args.target, version=args.version, build_type=args.build_type, clean=args.clean, skip_check=args.skip_check, arch=args.arch)
    sys.exit(0 if res["success"] else 1)


if __name__ == "__main__":
    main()

