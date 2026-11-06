#!/usr/bin/env python3
"""Verify the Rust cores end to end.

Default: formatting, clippy (warnings are errors) and the Rust test suite of every crate,
including the DTRI fixtures that are byte-compared with the Kotlin/JVM reference writer.

    python rust/verify.py
    python rust/verify.py --android   # also cross-compile the three .so files for arm64-v8a
    python rust/verify.py --go        # also prove the Go engine agrees with the Rust policy, cache and MITM kernels
    python rust/verify.py --desktop   # also run the desktop service (Go) suite against all three desktop kernels
    python rust/verify.py --dart      # also run the Dart side of the native fast paths
    python rust/verify.py --bench     # also time the DTRI compile, the rule search and the walk
    python rust/verify.py --all

The Go checks exist because the Go engine is the real consumer: it mmaps the DTRI files and it calls
the policy kernel through the same C ABI production uses, so it is the only thing that can prove the
boundary. `--go` needs `cgo` plus a C compiler (mingw on Windows, gcc/clang elsewhere); the release
library is built first because the Go loader probes `rust/target/release/`. `--desktop` needs neither:
that module loads its three kernels (stamps, the rule index and the rewrite engine/records) through pure Go
dynamic loading, so `CGO_ENABLED=0` is enough. `--dart` runs the Dart
side against the same library: the importer and the rules page have no second implementation left,
so those tests are fixed expectations on the native output.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

RUST_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = RUST_DIR.parent
GO_ENGINE_DIR = PROJECT_ROOT / "android" / "engine"
GO_DESKTOP_DIR = PROJECT_ROOT / "desktop" / "service"
APP_DIR = PROJECT_ROOT / "android" / "app"


def run(label: str, command: list[str], cwd: Path) -> bool:
    print(f"[verify] {label}: {' '.join(command)}", flush=True)
    result = subprocess.run(command, cwd=cwd)
    if result.returncode != 0:
        print(f"[verify] {label}: 失败 (exit {result.returncode})", file=sys.stderr, flush=True)
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Rust 内核验证")
    parser.add_argument("--android", action="store_true", help="交叉编译 arm64-v8a 并拷入 jniLibs")
    parser.add_argument("--go", action="store_true", help="跑 Go 读取 Rust DTRI 产物的兼容测试")
    parser.add_argument("--desktop", action="store_true", help="跑桌面服务（Go）对三个 Rust 内核的用例")
    parser.add_argument("--dart", action="store_true", help="跑 Dart 侧规则解析与入库用例")
    parser.add_argument("--bench", action="store_true", help="跑 DTRI 编译与规则检索基准")
    parser.add_argument("--all", action="store_true", help="等于 --android --go --desktop --dart --bench")
    args = parser.parse_args()
    if args.all:
        args.android = args.go = args.desktop = args.dart = args.bench = True

    steps: list[tuple[str, list[str], Path]] = [
        ("fmt", ["cargo", "fmt", "--all", "--check"], RUST_DIR),
        ("clippy", ["cargo", "clippy", "--all-targets", "--", "-D", "warnings"], RUST_DIR),
        ("test", ["cargo", "test"], RUST_DIR),
    ]
    if args.go:
        steps.append(("release", ["cargo", "build", "--release"], RUST_DIR))
        # The policy, DNS cache and MITM filter tests need the kernels: the engine has no second
        # implementation to fall back to.
        steps.append(
            (
                "go",
                [
                    "go",
                    "test",
                    "-run",
                    "TestNativePolicy|TestPolicy|TestNativeDNSCache|TestDNSCache|TestWireFormat|TestNegativeCaching|TestQuestionKey|TestSingleFlight|TestSharded|TestDisablingCache|TestEngineGetDNSCacheEntries|TestMitm",
                    ".",
                ],
                GO_ENGINE_DIR,
            )
        )
    if args.desktop:
        # The kernels are loaded at runtime (pure Go dlopen), so `go test` only needs the release
        # artifacts next to the source tree -- no cgo, no installed library.
        steps.append(("stamp-release", ["cargo", "build", "--release", "-p", "diting-stamp-core"], RUST_DIR))
        steps.append(("filter-release", ["cargo", "build", "--release", "-p", "diting-filter-core"], RUST_DIR))
        steps.append(("rewrite-release", ["cargo", "build", "--release", "-p", "diting-rewrite-core"], RUST_DIR))
        # -count=1: the kernel is an external file, invisible to Go's test cache.
        steps.append(("desktop-service", ["go", "test", "-count=1", "./..."], GO_DESKTOP_DIR))
    if args.dart:
        flutter = shutil.which("flutter")
        if flutter is None:
            print("[verify] dart: 找不到 flutter，跳过", file=sys.stderr)
        else:
            steps.append(("dart", [flutter, "test", "test/rule_parse_test.dart"], APP_DIR))
    if args.android:
        steps.append(
            ("android", [sys.executable, str(RUST_DIR / "build_android.py"), "--abi", "arm64"], RUST_DIR)
        )
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
