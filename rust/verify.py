#!/usr/bin/env python3
"""Verify the Rust rule core end to end.

Default: formatting, clippy (warnings are errors) and the Rust test suite, including the DTRI
fixtures that are byte-compared with the Kotlin/JVM reference writer.

    python rust/verify.py
    python rust/verify.py --android   # also cross-compile the .so for arm64-v8a
    python rust/verify.py --go        # also prove the Go engine reads the Rust DTRI fixtures
    python rust/verify.py --bench     # also time a 100k-rule DTRI compile
    python rust/verify.py --all

The Go check exists because the Go engine is the real consumer of the DTRI file: it is the one
format step that no amount of Rust-side testing can cover.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

RUST_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = RUST_DIR.parent
GO_ENGINE_DIR = PROJECT_ROOT / "android" / "engine"


def run(label: str, command: list[str], cwd: Path) -> bool:
    print(f"[verify] {label}: {' '.join(command)}", flush=True)
    result = subprocess.run(command, cwd=cwd)
    if result.returncode != 0:
        print(f"[verify] {label}: 失败 (exit {result.returncode})", file=sys.stderr, flush=True)
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Rust 规则内核验证")
    parser.add_argument("--android", action="store_true", help="交叉编译 arm64-v8a 并拷入 jniLibs")
    parser.add_argument("--go", action="store_true", help="跑 Go 读取 Rust DTRI 产物的兼容测试")
    parser.add_argument("--bench", action="store_true", help="跑 10 万条规则的 DTRI 编译基准")
    parser.add_argument("--all", action="store_true", help="等于 --android --go --bench")
    args = parser.parse_args()
    if args.all:
        args.android = args.go = args.bench = True

    steps: list[tuple[str, list[str], Path]] = [
        ("fmt", ["cargo", "fmt", "--all", "--check"], RUST_DIR),
        ("clippy", ["cargo", "clippy", "--all-targets", "--", "-D", "warnings"], RUST_DIR),
        ("test", ["cargo", "test"], RUST_DIR),
    ]
    if args.go:
        steps.append(("go", ["go", "test", "-run", "TestRustDTRI", "."], GO_ENGINE_DIR))
    if args.android:
        steps.append(
            ("android", [sys.executable, str(RUST_DIR / "build_android.py"), "--abi", "arm64"], RUST_DIR)
        )
    if args.bench:
        steps.append(
            ("bench", ["cargo", "run", "--release", "--example", "dtri_bench"], RUST_DIR)
        )

    failed = [label for label, command, cwd in steps if not run(label, command, cwd)]
    if failed:
        print(f"[verify] 失败步骤: {', '.join(failed)}", file=sys.stderr)
        return 1
    print(f"[verify] 全部通过（{len(steps)} 步）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
