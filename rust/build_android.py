#!/usr/bin/env python3
"""Cross-compile the Rust libraries for Android and drop them into the Flutter app's jniLibs.

Two libraries are built: `libditing_engine.so` (the tunnel data plane, unchanged) plus
`libditing_kernels.so` — the sixteen kernels Dart and Kotlin call directly, linked into one cdylib
by the `diting-kernels` umbrella crate. The engine stays its own `.so` on purpose: it has no
duplicated std/dependency bytes to share and is kept isolated from the UI-side kernels.

* `libditing_engine.so` - the tunnel engine behind all three modes: standalone DNS server, express
  tunnel and normal tunnel. Lifecycle and JNI facade, the DNS pipeline with its four upstream
  transports, the standalone server, TUN + transparent netstack, the direct / SOCKS5 / HTTP CONNECT
  egress and the MITM relay. It **links** the engine-side kernels statically (policy, DNS cache and
  messages, resolver scheduling, upstream transport, bootstrap, gate, connlog, proxy, cert, MITM
  filter, cosmetic injection, sniffer, request rules, config, telemetry), so none of them ships as
  its own `.so` any more - they are regular Rust dependencies instead of `dlopen`'d libraries.

The sixteen kernels below are the components of `libditing_kernels.so` (the `diting-kernels`
umbrella cdylib links them into one library; the names below are their former per-kernel `.so`
names). Each keeps its own C ABI / JNI entry points, and Dart/Kotlin now load every one of them from
that single `.so`.

* `diting-rule-core` - rule parsing, rule search, the DTRI writer and the
  `applyRuleSnapshot` document builder (Dart/Kotlin callers).
* `libditing_probe_core.so` - the network-diagnostics kernel the app's JNI probes call (host text
  cleanup, the A/AAAA query wire, the answer walk over the shared wire reader, `ping` /
  `traceroute` output parsing and the latency arithmetic).
* `libditing_log_core.so` - the log and statistics kernel the app's JNI `LogNative` calls (the
  `dns_log` / `http_request_log` / `dns_race_log` / `bootstrap_log` row classification with its
  log-mode filter, the retention windows, the notification counters and transfer rates, the
  per-UID traffic buckets, the write-health counters, the crash-buffer selection, the two
  attribution LRUs and the writer queues with their flush/overflow/backoff policy).
* `libditing_agent_core.so` - the AI-assistant kernel the Flutter app loads over `dart:ffi` (the
  four-step clipboard recogniser, the legacy key masks, the two analysis prompts, the log-table
  traffic summary with its rendered section, and the OpenAI-compatible endpoint / request /
  response layer).
* `libditing_dns_config_core.so` - the DNS configuration kernel the Flutter app loads over
  `dart:ffi` (the two engine documents with their mode selection, provider pick, cache presets,
  block/dynamic clamps and bootstrap rows, plus `user_providers_json`, `custom_upstreams` and
  `bootstrap_custom_json`).
* `libditing_backup_core.so` - the backup kernel the Flutter app loads over `dart:ffi` (the
  fifteen groups, the document envelope, every merge / dedupe / counter of an import, and the plan
  the app then stores).
* `libditing_rule_store_core.so` - the rule-table kernel the Flutter app loads over `dart:ffi` (row
  to rule mapping, every unique-key predicate, the per-app scope comparisons, the import statement
  plan and the orphan sweep).
* `libditing_subscription_core.so` - the subscription kernel the Flutter app loads over `dart:ffi`
  (URL/mirror rules with the Java `URLEncoder` spelling, row defaults and the two edit forms, the
  download attempt/fallback/response policy, and the auto-update schedule).
* `libditing_log_query_core.so` - the log-query kernel the Flutter app loads over `dart:ffi` (the
  SQL plans for every dashboard/statistics/traffic read, row mapping, classification and
  aggregation, and the full overview snapshot).
* `libditing_cleanup_core.so` - the data-cleanup catalog the Flutter app loads over `dart:ffi`
  (every table, source table, WHERE clause, preference key and the `allData` action order).
* `libditing_app_update_core.so` - the release-checking kernel the Flutter app loads over
  `dart:ffi` (version comparison, `releases/latest` parsing, APK asset preference and HTTP status
  classification).
* `libditing_recognition_core.so` - the member-list kernel the Flutter app loads over `dart:ffi`
  (document validation, cache keys/endpoints/limits and avatar acceptance).
* `libditing_ip_quality_core.so` - the IP-quality kernel the Flutter app loads over `dart:ffi`
  (egress-IP probe bodies, the three public source replies, the type classifier and the report
  summary).
* `libditing_outbound_proxy_core.so` - the outbound-proxy configuration kernel the Flutter app
  loads over `dart:ffi` and Kotlin calls through JNI (engine validation rules, the app package /
  installed / target checks, the engine JSON, stored-field normalization and `packages` → `uids`).
* `libditing_vpn_config_core.so` - the VPN plan and watchdog kernel Kotlin calls through JNI
  (normal/express TUN addresses, DNS, bypass-LAN and resolver-hijack routes, IPv6 decision,
  MTU/blocking, the excluded-package union, the start defaults, and the onRevoke confirmation /
  occupied / release phases with their debounce and reconnect decision).
* `libditing_notification_core.so` - the foreground-notification kernel Kotlin calls through JNI
  (the ordered detail items with their legacy speed fallback, the custom/default/fallback running
  text, the localized label lookup, US-grouped counts and the `↑ 1.5 MB/s` rate text).

Each of these is the only implementation of its decisions: a missing library is a hard error, not a
second code path. Without the engine nothing starts at all. Without the rule index a rule import
throws and the tunnel refuses to start; without the log kernel the request log tables stay empty
(the writers refuse to guess a row) and the notification counters read zero; without the probe
kernel every Ping / traceroute / custom-resolver / DNS-latency panel reports the kernel as
unavailable; without the AI kernel, the DNS-config kernel, the backup kernel, the rule-store
kernel, the subscription kernel, the log-query kernel, the cleanup kernel, the update-check kernel,
the recognition kernel, the IP-quality kernel, the outbound-proxy config kernel, the VPN plan
kernel or the notification kernel the matching screen throws instead of drifting from the format
the native side writes. Answers and the tunnel stay untouched in those cases. `diting-allowlist-core`
and `diting-ipcache-core` have no consumer left (the strict allowlist and the IP → domain hint are
not wired from Kotlin yet), so they are built by `cargo test` only and are not shipped.

Run this before every APK build (build_apk.bat does it for you):

    python rust/build_android.py              # arm64-v8a + x86_64, release
    python rust/build_android.py --abi arm64  # phones only
    python rust/build_android.py --debug      # quicker build, slower at runtime

The NDK is located from ANDROID_NDK_HOME / ANDROID_NDK_ROOT, else from `sdk.dir` in
`android/local.properties` plus the newest installed `ndk/<version>`. The linker is the NDK's
API-level clang wrapper for Android API 28, which matches `minSdk` in the app's build.gradle.kts.
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
# Two artifacts ship per ABI: the engine (data plane) and the merged UI-kernel library. Each is
# copied into `lib/<abi>/` (on the loader search path for the app). The engine-side kernels are
# statically linked into `libditing_engine.so`; the sixteen UI kernels are statically linked into
# `libditing_kernels.so`. The desktop-only kernels are not part of the APK and are built by their
# own `cargo test`/desktop steps.
LIB_NAMES = (
    "libditing_engine.so",
    "libditing_kernels.so",
)
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

    llvm_ar = ndk / "toolchains" / "llvm" / "prebuilt" / host / "bin" / "llvm-ar"
    if sys.platform.startswith("win"):
        llvm_ar = llvm_ar.with_suffix(".exe")

    environment = dict(os.environ)
    environment[f"CARGO_TARGET_{triple.upper().replace('-', '_')}_LINKER"] = str(clang)
    # `ring` (pulled in by rustls/quinn for the encrypted DNS transports) compiles C and per-arch
    # assembly through `cc`, which looks up `CC_<target>`/`AR_<target>` and otherwise guesses a bare
    # `clang`. The target-prefixed NDK wrapper is what actually carries the sysroot.
    environment[f"CC_{triple.replace('-', '_')}"] = str(clang)
    environment[f"AR_{triple.replace('-', '_')}"] = str(llvm_ar)
    command = [
        "cargo",
        "build",
        "-p",
        "diting-engine",
        "-p",
        "diting-kernels",
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
    # Libraries from an earlier (34-library) layout would otherwise linger in `jniLibs` and be
    # packaged again, so the engine-side kernels are removed on the way out.
    for stale in destination.glob("libditing_*_core.so"):
        if stale.name not in LIB_NAMES:
            stale.unlink()
            log(f"删除过期库 {stale}")
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description="为 Android 构建 Rust 隧道引擎与合并后的 UI 内核库（2 个 .so）")
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
