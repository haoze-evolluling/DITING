#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""DITING 跨平台轻量构建辅助脚本 (Windows / Linux / macOS).

精简保留核心工作流：Clean、Debug 编译、Release 编译以及 ADB 连接与安装。
Java 环境默认读取系统配置（JAVA_HOME 或 PATH），缺失时提示用户在终端中输入。
"""

import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
BUILD_TYPES = ("debug", "release")
OK, WARN, ERR, INFO = "[OK]  ", "[WARN]", "[ERROR]", "[INFO] "


def is_windows() -> bool:
    return os.name == "nt"


# ------------------------------------------------------------ toolchain detection --

def java_executable(home: Path) -> Path:
    return home / "bin" / ("java.exe" if is_windows() else "java")


def ensure_java_home() -> Path:
    """获取 Java 根目录路径。
    优先读取系统环境变量 JAVA_HOME 与 PATH，其次扫描常见安装位置；均未找到时提示用户输入。"""
    # 1. 优先检查系统环境变量 JAVA_HOME
    env_jh = os.environ.get("JAVA_HOME")
    if env_jh:
        p = Path(env_jh).resolve()
        if java_executable(p).exists():
            return p

    # 2. 检查系统 PATH 中的 java
    java_on_path = shutil.which("java")
    if java_on_path:
        p = Path(java_on_path).resolve().parent.parent
        if java_executable(p).exists():
            return p

    # 3. 兜底：扫描常见安装位置 (非交互 shell 可能不加载 ~/.bashrc，环境变量会缺失)
    home = Path.home()
    candidates = [
        home / "Applications" / "android-studio" / "jbr",
        home / ".local" / "share" / "JetBrains" / "Toolbox" / "apps" / "AndroidStudio" / "jbr",
        home / "snap" / "android-studio" / "current" / "android-studio" / "jbr",
        Path("/opt/android-studio/jbr"),
        Path("/usr/local/android-studio/jbr"),
    ]
    if sys.platform == "darwin":
        candidates.append(Path("/Applications/Android Studio.app/Contents/jbr/Contents/Home"))
    elif is_windows():
        program_files = os.environ.get("ProgramFiles", r"C:\Program Files")
        candidates.append(Path(program_files) / "Android" / "Android Studio" / "jbr")
        local_app = os.environ.get("LOCALAPPDATA")
        if local_app:
            # 按当前用户安装 (无管理员权限) 与 Toolbox 托管安装
            candidates.append(Path(local_app) / "Programs" / "Android Studio" / "jbr")
            candidates.append(Path(local_app) / "JetBrains" / "Toolbox" / "apps" / "AndroidStudio" / "jbr")
        jvm_root = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Java"
        if jvm_root.is_dir():
            candidates.extend(sorted(jvm_root.glob("*")))
        jvm_root_x86 = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Java"
        if jvm_root_x86.is_dir():
            candidates.extend(sorted(jvm_root_x86.glob("*")))
    else:
        candidates.extend(sorted(Path("/usr/lib/jvm").glob("*")))
    for cand in candidates:
        if java_executable(cand).exists():
            print(f"{INFO} 已自动定位 Java 环境: {cand}")
            return cand.resolve()

    # 4. 未找到系统 Java 环境，在控制台中提示用户手动输入
    print(f"{WARN} 未检测到系统默认 Java/JBR 环境 (环境变量 JAVA_HOME 未设置且 PATH 中无 java)。")
    while True:
        try:
            val = input("请输入 Java/JBR 根目录路径 ('q' 退出): ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            sys.exit(130)
        if not val or val.lower() in ("q", "quit", "exit"):
            sys.exit(1)
        cand = Path(val).expanduser().resolve()
        if java_executable(cand).exists():
            return cand
        # macOS App Bundle 兜底兼容 (Contents/Home)
        if (cand / "Contents" / "Home").is_dir() and java_executable(cand / "Contents" / "Home").exists():
            return cand / "Contents" / "Home"
        print(f"{ERR} 无效的 Java 路径，在该目录下未找到 bin/java: {cand}")


def parse_local_properties() -> dict:
    props = {}
    lp = PROJECT_ROOT / "local.properties"
    if lp.exists():
        for line in lp.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                props[k.strip()] = v.strip().replace("\\:", ":").replace("\\\\", "\\")
    return props


def is_sdk_dir(path: Path) -> bool:
    return path.is_dir() and any(
        (path / n).is_dir() for n in ("platforms", "build-tools", "platform-tools", "cmdline-tools", "ndk"))


def find_android_sdk():
    """Detect the SDK: ANDROID_HOME -> ANDROID_SDK_ROOT -> local.properties -> default locations."""
    candidates = []
    for var in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        v = os.environ.get(var)
        if v:
            candidates.append(Path(v))
    sdk_dir = parse_local_properties().get("sdk.dir")
    if sdk_dir:
        candidates.append(Path(sdk_dir))
    if is_windows():
        local_app = os.environ.get("LOCALAPPDATA")
        if local_app:
            candidates.append(Path(local_app) / "Android" / "Sdk")
    elif sys.platform == "darwin":
        candidates.append(Path.home() / "Library" / "Android" / "sdk")
    else:
        candidates.append(Path.home() / "Android" / "Sdk")

    for c in candidates:
        if is_sdk_dir(c):
            return c.resolve()
    return None


def find_adb(sdk: Path | None):
    if sdk:
        adb = sdk / "platform-tools" / ("adb.exe" if is_windows() else "adb")
        if adb.exists():
            return adb
    which = shutil.which("adb")
    if which:
        return Path(which)
    return None


def gradle_wrapper_command():
    return "gradlew.bat" if is_windows() else "./gradlew"


# ------------------------------------------------------------ build & process --

def run_process(exe, args, env, cwd=PROJECT_ROOT) -> int:
    if is_windows():
        cmd = subprocess.list2cmdline([str(exe)] + list(args))
        return subprocess.call(cmd, shell=True, env=env, cwd=cwd)
    return subprocess.call([str(exe)] + list(args), env=env, cwd=cwd)


def run_gradle(args) -> int:
    java_home = ensure_java_home()
    env = os.environ.copy()
    env["JAVA_HOME"] = str(java_home)
    env["PATH"] = str(java_home / "bin") + os.pathsep + env.get("PATH", "")

    wrapper = PROJECT_ROOT / gradle_wrapper_command()
    if not wrapper.exists():
        print(f"{ERR} 未找到 Gradle Wrapper: {wrapper}")
        return 1
    if not is_windows() and not os.access(wrapper, os.X_OK):
        try:
            os.chmod(wrapper, 0o755)
        except OSError as e:
            print(f"{WARN} 赋予 gradlew 执行权限失败: {e}")
    return run_process(wrapper, args, env)


def find_apk(build_type: str) -> Path | None:
    """查找对应构建类型的最新 APK 产物（按最后修改时间排序）。"""
    out = PROJECT_ROOT / "app" / "build" / "outputs" / "apk"
    candidates = []
    versioned = out / "versioned" / build_type
    if versioned.is_dir():
        candidates.extend(versioned.glob(f"DITING-{build_type}-v*.apk"))
    standard = out / build_type / f"app-{build_type}.apk"
    if standard.exists():
        candidates.append(standard)
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def do_clean() -> int:
    print(f"{INFO} 正在清理构建缓存: gradlew clean ...")
    code = run_gradle(["clean"])
    if code == 0:
        print(f"{OK} Clean 完成！")
    else:
        print(f"{ERR} Clean 失败，请查看上方日志。")
    return code


def do_build(build_type: str) -> int:
    if build_type not in BUILD_TYPES:
        print(f"{ERR} 未知的编译类型: {build_type} (支持: debug / release)")
        return 1
    task = f"assemble{build_type.capitalize()}"
    print(f"{INFO} 执行构建: {task} ...")
    code = run_gradle([task])
    if code != 0:
        print(f"{ERR} Gradle 构建失败，请查看上方日志。")
        return code
    apk = find_apk(build_type)
    print(f"{OK} {build_type.capitalize()} 构建完成！")
    if apk:
        print(f"{INFO} APK 产物路径: {apk}")
    else:
        print(f"{WARN} 未在输出目录中找到 APK 文件。")
    return 0


# ------------------------------------------------------------ ADB & install --

def adb_list_devices(adb: Path):
    try:
        r = subprocess.run([str(adb), "devices"], capture_output=True, text=True,
                           errors="replace", timeout=30)
    except (OSError, subprocess.SubprocessError):
        return []
    devices = []
    in_device_list = False
    for line in (r.stdout or "").splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("List of devices attached"):
            in_device_list = True
            continue
        if in_device_list or not line.startswith("*"):
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "device":
                devices.append(parts[0])
    return devices


_ADDRESS_RE = re.compile(
    r"^\d{1,3}(?:\.\d{1,3}){3}:(\d{1,5})$"
)


def normalize_address(raw: str) -> str:
    """归一化设备地址：全角冒号等统一为 ASCII 冒号，去除所有空白。"""
    cleaned = re.sub(r"\s+", "", raw)
    return cleaned.replace("：", ":").replace("：", ":").replace("：", ":")


def adb_connect_flow(adb: Path):
    """无线调试连接引导，连接指定 IP:PORT。"""
    while True:
        try:
            address = normalize_address(input("请输入无线调试设备地址 [IP:PORT, 'q' 取消]: "))
        except (EOFError, KeyboardInterrupt):
            print()
            return None
        if not address:
            print(f"{WARN} 输入不能为空，请重试。")
            continue
        if address.lower() in ("q", "quit", "exit"):
            return None
        m = _ADDRESS_RE.match(address)
        if not m:
            print(f"{WARN} 地址格式应为 IP:PORT (例如 192.168.1.10:37025)，当前输入: {address}")
            continue
        if not (1 <= int(m.group(1)) <= 65535):
            print(f"{WARN} 端口超出有效范围 (1-65535): {address}")
            continue
        print(f"{INFO} 正在连接 {address} ...")
        try:
            r = subprocess.run([str(adb), "connect", address], capture_output=True,
                               text=True, errors="replace", timeout=30)
            conn_out = (r.stdout or "") + (r.stderr or "")
            if "connected to" in conn_out.lower() and "cannot connect" not in conn_out.lower():
                time.sleep(1)
        except (subprocess.TimeoutExpired, subprocess.SubprocessError, OSError) as e:
            print(f"{ERR} 执行 adb connect 失败: {e}")
            continue

        devices = adb_list_devices(adb)
        if address in devices:
            print(f"{OK} 设备连接成功: {address}")
            return address
        print(f"{ERR} 无法连接到设备: {address}")
        print("  1. 请检查 IP 与端口是否正确 (Android 无线调试端口每次开启可能会变化)")
        print("  2. 请确保手机与电脑在同一局域网，且已在开发者选项中开启无线调试")
        print("  3. 若手机屏幕弹出调试授权弹窗，请点击允许")


def choose_device(adb: Path, target=None):
    devices = adb_list_devices(adb)
    if target:
        if target not in devices:
            print(f"{INFO} 设备 {target} 尚未就绪，尝试连接 ...")
            try:
                subprocess.run([str(adb), "connect", target], timeout=30)
                time.sleep(1)
            except (subprocess.TimeoutExpired, subprocess.SubprocessError, OSError):
                pass
            devices = adb_list_devices(adb)
        if target in devices:
            return target
        print(f"{ERR} 指定设备不可用: {target}")
        return None

    if len(devices) == 1:
        print(f"{INFO} 检测到在线设备: {devices[0]}")
        return devices[0]
    if len(devices) > 1:
        print(f"{INFO} 检测到 {len(devices)} 台在线设备:")
        for i, d in enumerate(devices, 1):
            print(f"  [{i}] {d}")
        while True:
            try:
                pick = input(f"请选择目标设备 [1-{len(devices)}, 'q' 取消, 默认 1]: ").strip()
            except (EOFError, KeyboardInterrupt):
                print()
                return None
            if not pick:
                return devices[0]
            if pick.lower() in ("q", "quit", "exit"):
                return None
            if pick.isdigit() and 1 <= int(pick) <= len(devices):
                return devices[int(pick) - 1]
            print(f"{WARN} 输入无效: {pick}。请输入 1 到 {len(devices)} 之间的数字。")

    return adb_connect_flow(adb)


def do_install(build_type: str = "debug", device=None) -> int:
    if build_type not in BUILD_TYPES:
        print(f"{ERR} 未知的编译类型: {build_type}")
        return 1
    sdk = find_android_sdk()
    adb = find_adb(sdk)
    if not adb:
        print(f"{ERR} 未找到 adb 命令。请配置 Android SDK Platform-Tools 或将其加入系统 PATH。")
        return 1

    apk = find_apk(build_type)
    if not apk:
        print(f"{ERR} 未找到 {build_type} APK，请先执行编译: python dev.py {build_type}")
        return 1

    serial = choose_device(adb, device)
    if not serial:
        print(f"{INFO} 已取消安装。APK 路径: {apk}")
        return 0

    print(f"{INFO} 正在安装 {apk.name} -> {serial} ...")
    r = subprocess.run([str(adb), "-s", serial, "install", "-r", str(apk)])
    if r.returncode != 0:
        print(f"{ERR} 安装失败 (常见原因: 存储不足、或已安装版本的签名不一致，需先卸载)。")
        return r.returncode
    print(f"{OK} 安装成功！")
    return 0


# ------------------------------------------------------------ interactive menu --

def ask(msg: str, default: str) -> str:
    try:
        v = input(msg).strip()
    except EOFError:
        return default
    return v or default


def open_in_new_terminal() -> bool:
    """无 TTY 附着时（如文件管理器双击），拉起新终端窗口执行本脚本。"""
    if os.environ.get("DEV_PY_RELAUNCHED"):
        return False
    env = {**os.environ, "DEV_PY_RELAUNCHED": "1"}
    script = str(PROJECT_ROOT / "dev.py")

    if is_windows():
        run = subprocess.list2cmdline([sys.executable, script])
        try:
            subprocess.Popen(["cmd", "/c", "start", "", "cmd", "/k", run],
                             cwd=PROJECT_ROOT, env=env)
            return True
        except OSError:
            return False

    if sys.platform == "darwin":
        run = ("cd " + shlex.quote(str(PROJECT_ROOT)) + " && "
               + " ".join(shlex.quote(x) for x in (sys.executable, script)))
        esc = run.replace("\\", "\\\\").replace('"', '\\"')
        try:
            subprocess.Popen(["osascript", "-e",
                              f'tell application "Terminal" to do script "{esc}"'],
                             env=env)
            return True
        except OSError:
            return False

    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        return False
    inner = ("cd " + shlex.quote(str(PROJECT_ROOT)) + " && "
             + " ".join(shlex.quote(x) for x in (sys.executable, script))
             + '; echo; echo "命令执行完成，按 Enter 键关闭窗口..."; read _')
    launchers = (
        ("ptyxis", ("--",)),
        ("alacritty", ("-e",)),
        ("kitty", ("--",)),
        ("wezterm", ("start", "--")),
        ("foot", ("-e",)),
        ("konsole", ("-e",)),
        ("qterminal", ("-e",)),
        ("gnome-terminal", ("--",)),
        ("mate-terminal", ("--",)),
        ("xfce4-terminal", ("-x",)),
        ("xterm", ("-e",)),
        ("x-terminal-emulator", ("-e",)),
    )
    sh = shutil.which("bash") or "/bin/sh"
    # 交互模式 (-i) 使新终端中的 bash 加载 ~/.bashrc，让用户配置的 JAVA_HOME 等环境变量生效
    sh_args = [sh, "-ic"] if sh.endswith("bash") else [sh, "-c"]
    for term, sep in launchers:
        if not shutil.which(term):
            continue
        try:
            subprocess.Popen([term, *sep, *sh_args, inner],
                             cwd=PROJECT_ROOT, env=env, start_new_session=True)
            return True
        except OSError:
            continue
    return False


def cmd_menu() -> int:
    while True:
        print("\n" + "=" * 62)
        print("     DITING Android Build & Install Tool (Cross-Platform)")
        print("=" * 62)
        print("  [1] Debug 编译   (assembleDebug)")
        print("  [2] Release 编译 (assembleRelease)")
        print("  [3] Clean        (清理构建缓存)")
        print("  [0] 退出")
        try:
            choice = ask("请选择 [1/2/3/0] (默认 1): ", "1")
        except (EOFError, KeyboardInterrupt):
            print()
            return 0

        if choice == "0":
            return 0
        elif choice == "1":
            if do_build("debug") == 0:
                if ask("是否安装 Debug APK 到设备？[Y/N] (默认 Y): ", "y").lower().startswith("y"):
                    do_install("debug")
        elif choice == "2":
            if do_build("release") == 0:
                if ask("是否安装 Release APK 到设备？[Y/N] (默认 Y): ", "y").lower().startswith("y"):
                    do_install("release")
        elif choice == "3":
            do_clean()
        else:
            print(f"{WARN} 无效选项: {choice}")
            continue

        cont = ask("\n操作完成，按回车返回主菜单，输入 0 退出: ", "")
        if cont.strip() == "0":
            return 0


USAGE = """DITING 跨平台轻量构建辅助脚本 (Windows / Linux / macOS)

用法: python dev.py <command> [args]

命令:
  (无参数)                  打开终端交互式菜单
  clean                     清理构建缓存 (gradlew clean)
  debug / build debug       编译 Debug APK
  release / build release   编译 Release APK
  install [debug|release]   安装 APK 到设备 (支持无线/有线 ADB 连接)
  help                      显示此帮助信息
"""


def main(argv) -> int:
    try:
        sys.stdout.reconfigure(errors="replace")
        sys.stderr.reconfigure(errors="replace")
    except Exception:
        pass

    try:
        if not argv:
            if sys.stdin.isatty():
                return cmd_menu()
            if open_in_new_terminal():
                return 0
            print(f"{ERR} 未检测到交互式终端且无法拉起新终端窗口。")
            print(f"{INFO} 请在终端中运行: python dev.py 或执行: python dev.py debug")
            return 1

        cmd = argv[0].lower()
        rest = argv[1:]

        if cmd in ("help", "--help", "-h", "/?"):
            print(USAGE)
            return 0

        if cmd == "clean":
            return do_clean()

        if cmd in ("debug", "release"):
            return do_build(cmd)

        if cmd == "build":
            btype = rest[0].lower() if rest and rest[0].lower() in BUILD_TYPES else None
            if not btype:
                print("用法: dev.py build <debug|release>")
                return 1
            return do_build(btype)

        if cmd == "install":
            btype = "debug"
            device = None
            for i, a in enumerate(rest):
                if a.lower() in BUILD_TYPES:
                    btype = a.lower()
                elif a.startswith("--device="):
                    device = a.split("=", 1)[1]
                elif a in ("--device", "-d") and i + 1 < len(rest):
                    device = rest[i + 1]
            return do_install(btype, device)

        print(f"{ERR} 未知命令: {argv[0]}\n")
        print(USAGE)
        return 1
    except KeyboardInterrupt:
        print(f"\n{INFO} 用户已中止操作。")
        return 130


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
