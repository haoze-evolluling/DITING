#!/usr/bin/env python3
"""Verify the Rust cores end to end.

Default: formatting, clippy (warnings are errors) and the Rust test suite of every crate,
including the DTRI fixtures that are byte-compared with the Kotlin/JVM reference writer.

    python rust/verify.py
    python rust/verify.py --android   # also cross-compile the engine and the merged kernel library for arm64-v8a (2 .so files)
    python rust/verify.py --desktop   # also run the desktop service (Go) suite against every desktop kernel
    python rust/verify.py --engine    # also run the tunnel engine's own suite (DNS pipeline, transports, JNI contract)
    python rust/verify.py --smoke     # also load the log, rule-index, outbound-proxy, VPN-plan, VPN-watchdog, engine and notification kernels in a JVM
    python rust/verify.py --dart      # also run the Dart side of the native fast paths
    python rust/verify.py --bench     # also time the DTRI compile, the rule search and the walk
    python rust/verify.py --all

The Android engine is `libditing_engine.so`: it links the engine-side kernels statically, so there
is no Go side left to compare against and no `--go` step. `--desktop` is the only Go check that
remains, and it belongs to the desktop service, not to Android: that module loads its seven kernels
(stamps, the rule index, the rewrite engine/records, the safe-browsing hash prefixes, hosts, DNS64
and the client rate limiter) through pure Go dynamic loading, so `CGO_ENABLED=0` is enough.
`--dart` runs the Dart side against the same libraries: the importer, the rules page, the AI
analysis assistant, the two DNS configuration documents, the backup plan, the subscription
URL/fetch/schedule rules and the IP quality sources, the outbound-proxy app configuration, the VPN
route/start plans and the revoke watchdog have no second implementation left, so those tests are
fixed expectations on the native output.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

RUST_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = RUST_DIR.parent
GO_DESKTOP_DIR = PROJECT_ROOT / "desktop" / "service"
APP_DIR = PROJECT_ROOT / "android" / "app"


def run(label: str, command: list[str], cwd: Path) -> bool:
    print(f"[verify] {label}: {' '.join(command)}", flush=True)
    result = subprocess.run(command, cwd=cwd)
    if result.returncode != 0:
        print(f"[verify] {label}: 失败 (exit {result.returncode})", file=sys.stderr, flush=True)
        return False
    return True


def smoke_case(name: str, crate: str, library: str, mains: list[str]) -> bool:
    """Build one host library, compile its JVM declarations, then run the smoke main(s).

    `cargo test` cannot see the `Java_...` symbol names, so a renamed entry point or a swapped
    argument would only fail on the device. Each `tools/*-smoke` directory declares the same
    methods as its Kotlin `*Native.kt`, in the Kotlin package, and asserts one round trip per entry.
    """
    javac = shutil.which("javac")
    java = shutil.which("java")
    if javac is None or java is None:
        print("[verify] smoke: 找不到 javac/java，跳过", file=sys.stderr)
        return True
    if not run(f"smoke-build:{name}", ["cargo", "build", "-p", crate], RUST_DIR):
        return False
    source_dir = RUST_DIR / "tools" / f"{name}-smoke"
    out_dir = source_dir / "out"
    out_dir.mkdir(exist_ok=True)
    sources = sorted(str(path) for path in source_dir.rglob("*.java"))
    if not run(f"smoke-javac:{name}", [javac, "-d", str(out_dir), *sources], source_dir):
        return False
    artifact = next(
        (
            candidate
            for candidate in (
                RUST_DIR / "target" / "debug" / f"{library}.dll",
                RUST_DIR / "target" / "debug" / f"lib{library}.so",
                RUST_DIR / "target" / "debug" / f"lib{library}.dylib",
            )
            if candidate.exists()
        ),
        None,
    )
    if artifact is None:
        print(f"[verify] smoke: 找不到宿主 {library} 产物", file=sys.stderr)
        return False
    return all(
        run(
            f"smoke-jvm:{name}:{main}",
            [java, "--enable-native-access=ALL-UNNAMED", "-cp", str(out_dir), main, str(artifact)],
            source_dir,
        )
        for main in mains
    )


def smoke() -> bool:
    """Every JVM boundary check: log, rule-index, outbound-proxy, VPN, engine, tun spike and notification."""
    return (
        smoke_case("log", "diting-log-core", "diting_log_core", ["LogSmoke"])
        and smoke_case(
            "rule-index",
            "diting-rule-core",
            "diting_rule_core",
            ["RuleIndexSmoke"],
        )
        and smoke_case(
            "outbound-proxy",
            "diting-outbound-proxy-core",
            "diting_outbound_proxy_core",
            ["com.haoze.diting.proxy.OutboundProxyNative"],
        )
        and smoke_case(
            "vpn-plan",
            "diting-vpn-config-core",
            "diting_vpn_config_core",
            ["com.haoze.diting.vpn.VpnPlanNative", "com.haoze.diting.watchdog.VpnWatchdogNative"],
        )
        and smoke_case("engine", "diting-engine", "diting_engine", ["EngineSmoke"])
        and smoke_case("tun-spike", "diting-tun-spike", "diting_tun_spike", ["TunSmoke"])
        and smoke_case(
            "notification",
            "diting-notification-core",
            "diting_notification_core",
            ["com.haoze.diting.platform.NotificationNative"],
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Rust 内核验证")
    parser.add_argument("--android", action="store_true", help="交叉编译 arm64-v8a 并拷入 jniLibs（2 个 .so：engine + 合并内核库）")
    parser.add_argument("--desktop", action="store_true", help="跑桌面服务（Go）对七个 Rust 内核的用例")
    parser.add_argument("--engine", action="store_true", help="跑隧道引擎的全部用例（DNS 管道、四种上游传输、JNI 契约）")
    parser.add_argument("--smoke", action="store_true", help="在 JVM 里加载日志、规则索引、出站代理、VPN 路由/看门狗、引擎与通知内核并走一遍 JNI 入口")
    parser.add_argument("--dart", action="store_true", help="跑 Dart 侧规则解析、入库、AI 助手、DNS 配置、备份、订阅、IP 质量与出站代理配置用例")
    parser.add_argument("--bench", action="store_true", help="跑 DTRI 编译与规则检索基准")
    parser.add_argument("--all", action="store_true", help="等于 --engine --android --desktop --dart --bench")
    args = parser.parse_args()
    if args.all:
        args.engine = args.android = args.desktop = args.dart = args.bench = True

    steps: list[tuple[str, list[str], Path]] = [
        ("fmt", ["cargo", "fmt", "--all", "--check"], RUST_DIR),
        ("clippy", ["cargo", "clippy", "--all-targets", "--", "-D", "warnings"], RUST_DIR),
        ("test", ["cargo", "test"], RUST_DIR),
    ]
    if args.engine:
        # The engine is where the DNS transports live, so its integration cases (real loopback
        # UDP/TCP/TLS/HTTP2/QUIC servers) are worth running on their own and not only inside the
        # workspace suite.
        steps.append(
            ("engine", ["cargo", "test", "-p", "diting-engine", "--all-targets"], RUST_DIR)
        )
    if args.desktop:
        # The kernels are loaded at runtime (pure Go dlopen), so `go test` only needs the release
        # artifacts next to the source tree -- no cgo, no installed library.
        steps.append(("stamp-release", ["cargo", "build", "--release", "-p", "diting-stamp-core"], RUST_DIR))
        steps.append(("filter-release", ["cargo", "build", "--release", "-p", "diting-filter-core"], RUST_DIR))
        steps.append(("rewrite-release", ["cargo", "build", "--release", "-p", "diting-rewrite-core"], RUST_DIR))
        steps.append(
            ("safebrowsing-release", ["cargo", "build", "--release", "-p", "diting-safebrowsing-core"], RUST_DIR)
        )
        steps.append(("hosts-release", ["cargo", "build", "--release", "-p", "diting-hosts-core"], RUST_DIR))
        steps.append(("dns64-release", ["cargo", "build", "--release", "-p", "diting-dns64-core"], RUST_DIR))
        steps.append(("ratelimit-release", ["cargo", "build", "--release", "-p", "diting-ratelimit-core"], RUST_DIR))
        # -count=1: the kernel is an external file, invisible to Go's test cache.
        steps.append(("desktop-service", ["go", "test", "-count=1", "./..."], GO_DESKTOP_DIR))
    if args.dart:
        flutter = shutil.which("flutter")
        if flutter is None:
            print("[verify] dart: 找不到 flutter，跳过", file=sys.stderr)
        else:
            steps.append(
                (
                    "dart",
                    [
                        flutter,
                        "test",
                        "test/rule_parse_test.dart",
                        "test/agent_test.dart",
                        "test/agent_render_test.dart",
                        "test/engine_config_test.dart",
                        "test/server_mode_test.dart",
                        "test/backup_test.dart",
                        "test/rule_repository_test.dart",
                        "test/subscription_test.dart",
                        "test/subscription_update_test.dart",
                        "test/global_mirror_test.dart",
                        "test/app_update_test.dart",
                        "test/dashboard_data_test.dart",
                        "test/real_data_wiring_test.dart",
                        "test/app_requests_test.dart",
                        "test/legacy_database_test.dart",
                        "test/log_query_test.dart",
                        "test/data_cleanup_test.dart",
                        "test/recognition_members_test.dart",
                        "test/network_tools_test.dart",
                        "test/native_bridge_test.dart",
                    ],
                    APP_DIR,
                )
            )
    if args.android:
        steps.append(
            ("android", [sys.executable, str(RUST_DIR / "build_android.py"), "--abi", "arm64"], RUST_DIR)
        )
    if args.smoke and not smoke():
        print("[verify] smoke: 失败", file=sys.stderr)
        return 1
    if args.bench:
        steps.append(
            ("bench", ["cargo", "run", "--release", "--example", "dtri_bench"], RUST_DIR)
        )
        steps.append(
            ("search-bench", ["cargo", "run", "--release", "--example", "search_bench"], RUST_DIR)
        )
        steps.append(
            (
                "policy-bench",
                [
                    "cargo",
                    "run",
                    "--release",
                    "-p",
                    "diting-policy-core",
                    "--example",
                    "policy_bench",
                    "--",
                    "--synthetic",
                    "50000",
                    "20000",
                ],
                RUST_DIR,
            )
        )

    failed = [label for label, command, cwd in steps if not run(label, command, cwd)]
    if failed:
        print(f"[verify] 失败步骤: {', '.join(failed)}", file=sys.stderr)
        return 1
    print(f"[verify] 全部通过（{len(steps)} 步）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
