#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) Windows 端构建与安装包打包引擎
纯 Python 驱动，负责纯 Rust 特权服务与 NSIS / deb 安装包流水线编译及环境预检。
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from typing import Callable, Optional

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


_TOOLBOX_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DESKTOP_DIR = os.path.dirname(_TOOLBOX_DIR)
if _DESKTOP_DIR not in sys.path:
    sys.path.insert(0, _DESKTOP_DIR)

from toolbox.core.paths import BUILD_BIN_DIR, INSTALLER_DIR, ROOT_DIR, SERVICE_DIR
from toolbox.core.runner import stream_process_output
from toolbox.core.toolchain import check_toolchain


def get_root_dir() -> str:
    return ROOT_DIR


def get_current_project_version() -> str:
    """自动获取当前项目的核心最新版本号（消除硬编码）"""
    try:
        from toolbox.core.version_manager import get_current_version
        v = get_current_version()
        if v and v != "0.0.0":
            return v
    except Exception:
        pass
    return "0.0.0"


def stop_running_processes(on_log: Optional[Callable[[str, str], None]] = None):
    """构建前安全终止旧进程，防止文件占用锁导致编译或打包失败"""
    if sys.platform == "win32":
        for exe in ("diting-service.exe",):
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

    for name in ("diting-service",):
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


def build_windows_service(
    root: str,
    service_bin: str,
    build_type: str,
    on_log: Callable[[str, str], None],
    is_cancelled: Callable[[], bool],
) -> bool:
    """用 cargo 编译纯 Rust 的 Windows 特权服务并复制到暂存目录。

    版本号、构建时间与提交号由 `diting-desktop-api/build.rs` 从 `desktop/service/VERSION`
    与 git 注入，因此 cargo 构建本身就是版本真源，不再需要 `-ldflags`。
    """
    rust_dir = os.path.join(root, "rust")
    is_release = build_type.lower() == "release"
    on_log("info", f">>> 正在编译 Windows 特权服务 (cargo, {build_type})...")
    cmd = ["cargo", "build"]
    if is_release:
        cmd.append("--release")
    cmd += ["-p", "diting-desktop-service"]
    if not run_cmd_live(cmd, cwd=rust_dir, on_log=on_log, is_cancelled=is_cancelled):
        return False
    profile = "release" if is_release else "debug"
    built = os.path.join(rust_dir, "target", profile, "diting-service.exe")
    if not os.path.exists(built):
        on_log("error", f"未找到编译产物: {built}")
        return False
    os.makedirs(os.path.dirname(service_bin), exist_ok=True)
    shutil.copy2(built, service_bin)
    return True


def build_desktop_ui(
    root: str,
    on_log: Callable[[str, str], None],
    is_cancelled: Callable[[], bool],
    skip: bool = False,
) -> bool:
    """构建桌面管理端前端，供 diting-service 在编译期嵌入为 Web 管理页。"""
    if skip:
        on_log("warn", "已跳过桌面管理端构建，服务安装包将不包含 Web 管理页。")
        return True
    ui_dir = os.path.join(root, "desktop", "ui")
    if not os.path.isdir(ui_dir):
        on_log("warn", f"未找到桌面管理端目录，跳过 Web 管理页构建: {ui_dir}")
        return True
    npm = shutil.which("npm")
    if not npm:
        on_log("error", "未找到 npm。构建内嵌 Web 管理页需要 Node.js 20+，或使用 --skip-ui 跳过。")
        return False
    node_modules = os.path.join(ui_dir, "node_modules")
    if not os.path.isdir(node_modules):
        on_log("info", ">>> 正在安装桌面管理端依赖 (npm ci)...")
        if not run_cmd_live([npm, "ci"], cwd=ui_dir, on_log=on_log, is_cancelled=is_cancelled):
            return False
    on_log("info", ">>> 正在构建桌面管理端前端 (npm run build)...")
    return run_cmd_live([npm, "run", "build"], cwd=ui_dir, on_log=on_log, is_cancelled=is_cancelled)


def build_pipeline(
    target: str = "all",
    version: Optional[str] = None,
    build_type: str = "release",
    clean: bool = False,
    skip_check: bool = False,
    skip_ui: bool = False,
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

    def _fail(message: str) -> dict:
        if is_cancelled():
            on_log("warn", "构建已取消。")
            return {"success": False, "message": "构建已取消", "cancelled": True}
        return {"success": False, "message": message}

    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", version):
        on_log("error", f"非法的版本号: {version} (仅允许字母、数字与 . _ + - 且需以字母或数字开头)")
        return {"success": False, "message": f"非法版本号: {version}"}

    root = get_root_dir()
    server_dir = SERVICE_DIR
    bin_dir = BUILD_BIN_DIR
    service_bin = os.path.join(bin_dir, "diting-service.exe")

    on_log("info", "=" * 50)
    on_log("info", f"谛听 (DITING) 构建任务启动: Target={target}, Ver={version}, Type={build_type}")
    on_log("info", "=" * 50)

    tgt = target.lower().strip()
    if tgt == "installer":
        tgt = "exe"

    if tgt not in ("exe", "deb", "ipk", "both", "all"):
        on_log("error", f"未知的构建目标: {target} (支持: exe, deb, ipk, both, all)")
        return {"success": False, "message": f"不支持的构建目标: {target}"}

    stop_running_processes(on_log)

    tools = check_toolchain(force=True)
    need_win = tgt in ("exe", "both", "all")
    need_deb = tgt in ("deb", "both", "all")
    need_ipk = tgt in ("ipk", "all")

    if not skip_check:
        if need_win:
            if not tools["nsis"]["found"]:
                on_log("error", "未找到 makensis，无法打包 NSIS 安装包。")
                return {"success": False, "message": "缺少 NSIS"}
            if not tools["cargo"]["found"]:
                on_log("error", "未找到 Rust 工具链（cargo），纯 Rust 特权服务需要 cargo 编译。")
                return {"success": False, "message": "缺少 Rust 工具链"}
            if sys.platform == "win32" and not tools.get("msvc", {}).get("found"):
                on_log("error", "未找到 MSVC 链接器，Rust 默认工具链需要 Visual Studio C++ 生成工具。")
                return {"success": False, "message": "缺少 MSVC 链接器"}

        if need_deb or need_ipk:
            if sys.platform == "win32" and not tools.get("wsl", {}).get("found"):
                on_log("error", "未检测到 WSL 环境。在 Windows 上打包 deb / ipk 安装包需要 WSL 支持。")
                return {"success": False, "message": "缺少 WSL 环境"}
            if sys.platform == "win32":
                on_log("info", "提示: Linux deb / OpenWrt ipk 构建会在 WSL 内编译 Rust，WSL 需已安装 rustup。")

    if is_cancelled():
        on_log("warn", "构建已在启动前取消。")
        return {"success": False, "message": "构建已取消", "cancelled": True}

    if clean and os.path.exists(bin_dir):
        on_log("info", f"清理旧构建产物: {bin_dir}")
        shutil.rmtree(bin_dir, ignore_errors=True)
    os.makedirs(bin_dir, exist_ok=True)

    if not build_desktop_ui(root, on_log, is_cancelled, skip_ui):
        return _fail("桌面管理端构建失败")

    built_artifacts = []

    if need_win:
        on_log("info", ">>> [1/2] 正在编译 Windows 特权服务 (纯 Rust, diting-service.exe)...")
        if not build_windows_service(root, service_bin, build_type, on_log, is_cancelled):
            return _fail("特权服务编译失败")

        on_log("info", ">>> [2/2] 正在打包 NSIS 独立安装包...")
        installer_dir = INSTALLER_DIR
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
            f"-DARG_SERVICE_BINARY={service_bin}",
            f"-DPRODUCT_VERSION={version}",
            f"-DINFO_PRODUCTVERSION={version}",
            f"-DOUTPUT_FILENAME={installer_path}",
            nsi_script,
        ]
        ok = run_cmd_live(cmd_nsis, cwd=server_dir, on_log=on_log, is_cancelled=is_cancelled)
        if not ok:
            return _fail("NSIS 安装包打包失败")

        if not os.path.exists(installer_path) and os.path.exists(fallback_installer):
            try:
                shutil.move(fallback_installer, installer_path)
            except Exception:
                pass

        if not os.path.exists(installer_path):
            on_log("error", f"未找到生成的安装包文件: {installer_path}")
            return _fail("未生成预期的 EXE 安装包产物")

        for temp_path in (service_bin, fallback_installer):
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

    if need_deb:
        deb_arch = "amd64" if arch == "both" else arch
        if deb_arch not in ("amd64", "arm64", "arm"):
            return {"success": False, "message": f"不支持的 Linux 架构: {deb_arch}"}
        on_log("info", f">>> 正在打包 Linux 发行包 (.deb, linux/{deb_arch})...")
        if sys.platform == "win32":
            wsl_dir = server_dir.replace("\\", "/")
            cmd_pkg = ["wsl.exe", "-e", "bash", "-c", f"cd \"$(wslpath '{wsl_dir}')\" && exec bash ./build_linux.sh --package -a {deb_arch} -v {version} -b {build_type} --skip-ui"]
            ok = run_cmd_live(cmd_pkg, cwd=server_dir, on_log=on_log, is_cancelled=is_cancelled)
        else:
            cmd_pkg = ["bash", "./build_linux.sh", "--package", "-a", deb_arch, "-v", version, "-b", build_type, "--skip-ui"]
            ok = run_cmd_live(cmd_pkg, cwd=server_dir, on_log=on_log, is_cancelled=is_cancelled)

        if not ok:
            return _fail("Linux 发行包打包失败")

        deb_name = f"diting_{version}_linux_{deb_arch}.deb"
        deb_file = os.path.join(bin_dir, deb_name)
        if not os.path.exists(deb_file):
            return _fail("未找到生成的 DEB 安装包产物")

        raw_linux_bin = os.path.join(bin_dir, "diting-service")
        leftover_dir = os.path.join(bin_dir, f"diting_{version}_linux_{deb_arch}")
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

    if need_ipk:
        if arch not in ("amd64", "arm64", "x86_64", "aarch64", "both"):
            return {"success": False, "message": f"OpenWrt .ipk 仅支持 amd64 / arm64 / both，收到: {arch}"}
        on_log("info", f">>> 正在打包 OpenWrt 路由包 (.ipk, openwrt/{arch}, musl 静态链接)...")
        if sys.platform == "win32":
            wsl_dir = server_dir.replace("\\", "/")
            cmd_ipk = ["wsl.exe", "-e", "bash", "-c", f"cd \"$(wslpath '{wsl_dir}')\" && exec bash ./build_openwrt.sh --package -a {arch} -v {version} -b {build_type} --skip-ui"]
            ok = run_cmd_live(cmd_ipk, cwd=server_dir, on_log=on_log, is_cancelled=is_cancelled)
        else:
            cmd_ipk = ["bash", "./build_openwrt.sh", "--package", "-a", arch, "-v", version, "-b", build_type, "--skip-ui"]
            ok = run_cmd_live(cmd_ipk, cwd=server_dir, on_log=on_log, is_cancelled=is_cancelled)

        if not ok:
            return _fail("OpenWrt .ipk 打包失败")

        expected_arches = ["x86_64", "aarch64"] if arch == "both" else (["x86_64"] if arch in ("amd64", "x86_64") else ["aarch64"])
        for ipk_arch in expected_arches:
            ipk_file = os.path.join(bin_dir, f"diting_{version}_openwrt_{ipk_arch}.ipk")
            if not os.path.exists(ipk_file):
                return _fail(f"未找到生成的 OpenWrt IPK 产物: {ipk_file}")
            sz = os.path.getsize(ipk_file)
            on_log("info", f"[OK] OpenWrt 安装包生成成功: {ipk_file} ({format_size(sz)})")
            built_artifacts.append(ipk_file)

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
    parser.add_argument("-t", "--target", choices=["exe", "deb", "ipk", "both", "all", "installer"], default="exe", help="构建目标 (默认 exe)")
    parser.add_argument("-v", "--version", default=None, help="目标版本号 (默认自动读取)")
    parser.add_argument("-b", "--build-type", choices=["release", "debug"], default="release")
    parser.add_argument("-a", "--arch", choices=["amd64", "arm64", "arm", "both"], default="amd64", help="Linux / OpenWrt 目标架构")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--skip-check", action="store_true")
    parser.add_argument("--skip-ui", action="store_true", help="跳过桌面管理端前端构建（不嵌入 Web 管理页）")
    args = parser.parse_args()

    res = build_pipeline(target=args.target, version=args.version, build_type=args.build_type, clean=args.clean, skip_check=args.skip_check, skip_ui=args.skip_ui, arch=args.arch)
    sys.exit(0 if res["success"] else 1)


if __name__ == "__main__":
    main()

