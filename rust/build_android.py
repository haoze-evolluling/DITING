#!/usr/bin/env python3
"""Cross-compile the Rust cores for Android and drop them into the Flutter app's jniLibs.

Sixteen libraries are built:

* `libditing_rule_core.so` - rule parsing, rule search and the DTRI writer (Dart/Kotlin callers).
* `libditing_policy_core.so` - the policy kernel the Go tunnel engine dlopen()s (rule tables,
  wildcard index, DTRI reader and the seven-level priority walk).
* `libditing_dns_cache_core.so` - the DNS cache container and wire kernel the same engine
  dlopen()s (sharded LRU, TTL policy, sweeper, snapshot, cache key, response metadata and the
  ID/TTL patch).
* `libditing_mitm_core.so` - the MITM filter the same engine dlopen()s (allow list, `path.Match`
  bypass patterns, sensitive-host heuristics, the blacklist with its failure streaks and the
  persistent blacklist file).
* `libditing_cosmetic_core.so` - the cosmetic injection kernel the same engine dlopen()s (the
  streaming `<head>` scanner, the hostname normalization and the injected `<link>` tag).
* `libditing_resolver_core.so` - the upstream statistics kernel the same engine dlopen()s (the
  SRTT/RTTVAR estimator, the EWMA failure ratio, the consecutive-failure penalty and the circuit
  breaker behind the four scheduling strategies).
* `libditing_dns_core.so` - the DNS answer kernel the same engine dlopen()s (the null-block verdict
  on a forwarded answer, the logged address list and the dynamic block escalation).
* `libditing_sniffer_core.so` - the flow sniffer the same engine dlopen()s (the TLS ClientHello
  SNI walk, the plaintext HTTP request gate and its `Host` header).
* `libditing_bootstrap_core.so` - the encrypted-DNS bootstrap scoring kernel the same engine
  dlopen()s (endpoint health with half-life decay, the weighted primary pick and fallback order,
  and the one-minute host cache).
* `libditing_allowlist_core.so` - the strict app-allowlist kernel the same engine dlopen()s
  (normalized domain sets, the suffix walk, TTL-bounded IP grants and the answer fan-out).
* `libditing_connlog_core.so` - the connection-log dedupe kernel the same engine dlopen()s (the
  bounded key set, the overflow reset and the `connLogKey` builder).
* `libditing_ipcache_core.so` - the IP → domain LRU kernel the same engine dlopen()s (in-place
  update, move-to-front, eviction and the default capacity).
* `libditing_proxy_core.so` - the outbound proxy kernel the same engine dlopen()s (the SOCKS5
  greeting / method / auth / request / reply codec, the address and UDP datagram framing, the HTTP
  CONNECT request bytes and the proxy config normalization).
* `libditing_cert_core.so` - the MITM certificate kernel the same engine dlopen()s (root CA
  generation and validation, the SEC1 key encoding, leaf minting with its SAN rule and the EV
  policy table).
* `libditing_config_core.so` - the configuration kernel the same engine dlopen()s (the DNS mode
  aliases, the dynamic-block defaults, the provider endpoint rules, the protocol / block-response
  name tables, the rewrite-target classification and the domain key fold).
* `libditing_request_core.so` - the request filter the same engine dlopen()s (the URL rule table and
  the per-request decision: host fold, default-port strip, longest prefix with allow winning ties).

All sixteen are shipped and used at runtime: without the first a rule import throws, without the
second the tunnel refuses to start, without the third the DNS cache stores nothing (answers go
straight to the resolver), without the fourth MITM cannot start (the tunnel runs without
interception), without the fifth the same MITM start fails rather than serving pages without the
cosmetic stylesheet, without the sixth every upstream is scheduled with cold values (default score,
cold delays, every attempt allowed), without the seventh a null-block upstream answer is logged
as normal and every block keeps the configured mode, without the eighth MITM cannot start and the
passthrough relay loses its SNI hostname hint, without the ninth bootstrap resolution is
reported as disabled so encrypted provider hostnames go through the normal system path, and without
the tenth a configured strict allowlist fails closed for its selected UIDs (DNS and connections
denied) instead of silently allowing everything, without the eleventh connection logs are no
longer deduplicated (more lines, same events), without the twelfth direct-IP flows lose their
hostname hint, without the thirteenth the outbound proxy cannot be configured or used (proxied
flows fail, direct flows are untouched), and without the fourteenth MITM cannot start at all (no
CA to trust, no leaf to serve; the tunnel itself is unaffected), and without the fifteenth a pushed
DNS config is rejected (the previous snapshot stays) while the name tables fall back to their defaults
and rewrite targets are dropped, and without the sixteenth the URL rules never match (every request
falls through to the domain rules). The sixth, seventh, ninth, eleventh and twelfth never
change an answer. Run this before every APK build:

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
# All Android crates build with one cargo invocation; each artifact is copied next to the others so
# the APK ships them in `lib/<abi>/` (which is on the loader search path for the app). The desktop
# kernels are selected out on purpose: they are not part of the APK.
LIB_NAMES = (
    "libditing_rule_core.so",
    "libditing_policy_core.so",
    "libditing_dns_cache_core.so",
    "libditing_mitm_core.so",
    "libditing_cosmetic_core.so",
    "libditing_resolver_core.so",
    "libditing_dns_core.so",
    "libditing_sniffer_core.so",
    "libditing_bootstrap_core.so",
    "libditing_allowlist_core.so",
    "libditing_connlog_core.so",
    "libditing_ipcache_core.so",
    "libditing_proxy_core.so",
    "libditing_cert_core.so",
    "libditing_config_core.so",
    "libditing_request_core.so",
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

    environment = dict(os.environ)
    environment[f"CARGO_TARGET_{triple.upper().replace('-', '_')}_LINKER"] = str(clang)
    command = [
        "cargo",
        "build",
        "-p",
        "diting-rule-core",
        "-p",
        "diting-policy-core",
        "-p",
        "diting-dns-cache-core",
        "-p",
        "diting-mitm-core",
        "-p",
        "diting-cosmetic-core",
        "-p",
        "diting-resolver-core",
        "-p",
        "diting-dns-core",
        "-p",
        "diting-sniffer-core",
        "-p",
        "diting-bootstrap-core",
        "-p",
        "diting-allowlist-core",
        "-p",
        "diting-connlog-core",
        "-p",
        "diting-ipcache-core",
        "-p",
        "diting-proxy-core",
        "-p",
        "diting-cert-core",
        "-p",
        "diting-config-core",
        "-p",
        "diting-request-core",
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
    parser = argparse.ArgumentParser(description="为 Android 构建 Rust 规则内核、策略内核、DNS 缓存内核、MITM 过滤内核、装饰注入内核、解析器统计内核、DNS 应答内核、流量嗅探内核、引导解析内核、应用白名单内核、连接日志去重内核、IP→域名缓存内核与出站代理内核")
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
