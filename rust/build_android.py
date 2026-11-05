#!/usr/bin/env python3
"""Cross-compile the Rust cores for Android and drop them into the Flutter app's jniLibs.

Two libraries are built:

* `libditing_rule_core.so` - rule parsing, rule search and the DTRI writer (Dart/Kotlin callers).
* `libditing_policy_core.so` - the policy kernel the Go tunnel engine dlopen()s (rule tables,
  wildcard index, DTRI reader and the seven-level priority walk).

Both are optional at runtime: without the first the app keeps the Dart parser, without the second
the Go engine keeps its own policy walk. Run this before an APK build that should ship the native
paths:

    python rust/build_android.py              # arm64-v8a + x86_64, release
    python rust/build_android.py --abi arm64  # phones only
    python rust/build_android.py --debug      # quicker build, slower at runtime

The NDK is located from ANDROID_NDK_HOME / ANDROID_NDK_ROOT, else from `sdk.dir` in
`android/local.properties` plus the newest installed `ndk/<version>`. The linker is the NDK's
API-level clang wrapper for Android API 28, which matches `minSdk` in the app's build.gradle.kts
and the Go engine AAR.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

RUST_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = RUST_DIR.parent
JNI_LIBS_DIR = PROJECT_ROOT / "android" / "app" / "android" / "app" / "src" / "main" / "jniLibs"
# Both crates build with one cargo invocation; each artifact is copied next to the others so the
# APK ships them in `lib/<abi>/` (which is on the loader search path for the app).
LIB_NAMES = ("libditing_rule_core.so", "libditing_policy_core.so")
ANDROID_API = 28

# Gradle ABI name -> Rust target triple.
TARGETS = {
    "arm64": ("arm64-v8a", "aarch64-linux-android"),
    "x86_64": ("x86_64", "x86_64-linux-android"),
}


def log(message: str) -> None:
    print(f"[rust-native] {message}", flush=True)


def fail(message: str) -> int:
    print(f"[rust-native] 错误: {message}", file=sys.stderr, flush=True)
    return 1


def find_ndk() -> Path | None:
    for variable in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"):
        value = os.environ.get(variable)
        if value and Path(value).is_dir():
            return Path(value)

    local_properties = PROJECT_ROOT / "android" / "local.properties"
    sdk_dir: Path | None = None
    if local_properties.is_file():
        for line in local_properties.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("sdk.dir="):
                sdk_dir = Path(line.split("=", 1)[1].replace("\\\\", "\\").strip())
    if sdk_dir is None:
        sdk_dir = Path(os.environ.get("ANDROID_SDK_ROOT", "")) or None
    if sdk_dir is None or not sdk_dir.is_dir():
        return None

    versions = sorted((sdk_dir / "ndk").glob("*"), key=lambda path: path.name)
    return versions[-1] if versions else None


def host_tag() -> str | None:
    if sys.platform.startswith("win"):
        return "windows-x86_64"
    if sys.platform.startswith("darwin"):
        return "darwin-x86_64"
    if sys.platform.startswith("linux"):
        return "linux-x86_64"
    return None


def ensure_target(triple: str) -> bool:
    installed = subprocess.run(
        ["rustup", "target", "list", "--installed"],
        capture_output=True,
        text=True,
        check=False,
    )
    if triple in installed.stdout.split():
        return True
    log(f"安装 Rust 目标 {triple}")
    added = subprocess.run(["rustup", "target", "add", triple], check=False)
    return added.returncode == 0


def build(abi: str, ndk: Path, profile: str) -> Path | None:
    abi_dir, triple = TARGETS[abi]
    if not ensure_target(triple):
        log(f"无法安装目标 {triple}，跳过 {abi}")
        return None

    host = host_tag()
    if host is None:
        log("不支持的主机平台")
        return None
    clang = ndk / "toolchains" / "llvm" / "prebuilt" / host / "bin" / f"{triple}{ANDROID_API}-clang"
    if sys.platform.startswith("win"):
        clang = clang.with_suffix(".cmd")
    if not clang.is_file():
        log(f"找不到 NDK 链接器 {clang}")
        return None

    environment = dict(os.environ)
    environment[f"CARGO_TARGET_{triple.upper().replace('-', '_')}_LINKER"] = str(clang)
    command = [
        "cargo",
        "build",
        "--manifest-path",
        str(RUST_DIR / "Cargo.toml"),
        "--target",
        triple,
    ]
    if profile == "release":
        command.append("--release")

    log(f"编译 {abi} ({triple}, {profile})")
    built = subprocess.run(command, env=environment, check=False)
    if built.returncode != 0:
        return None

    destination = JNI_LIBS_DIR / abi_dir
    destination.mkdir(parents=True, exist_ok=True)
    for library in LIB_NAMES:
        artifact = RUST_DIR / "target" / triple / profile / library
        if not artifact.is_file():
            log(f"构建产物缺失: {artifact}")
            return None
        shutil.copy2(artifact, destination / library)
        log(f"{artifact.name} -> {destination / library}")
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description="为 Android 构建 Rust 规则内核与策略内核")
    parser.add_argument(
        "--abi",
        choices=["all", "arm64", "x86_64"],
        default="all",
        help="目标 ABI，默认 all（arm64-v8a + x86_64）",
    )
    parser.add_argument("--debug", action="store_true", help="构建 debug 版本")
    arguments = parser.parse_args()

    ndk = find_ndk()
    if ndk is None:
        return fail("找不到 Android NDK：设置 ANDROID_NDK_HOME，或在 android/local.properties 写 sdk.dir")

    profile = "debug" if arguments.debug else "release"
    selected = list(TARGETS) if arguments.abi == "all" else [arguments.abi]
    log(f"NDK: {ndk}")

    failed = [abi for abi in selected if build(abi, ndk, profile) is None]
    if failed:
        return fail(f"以下 ABI 构建失败: {', '.join(failed)}")
    log("完成")
    return 0


if __name__ == "__main__":
    sys.exit(main())
