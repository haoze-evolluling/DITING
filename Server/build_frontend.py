#!/usr/bin/env python3
"""Build the Flutter web console (DITING-Flutter/apps/diting_desktop) into `Server/frontend/dist`.

The Go service embeds `frontend/dist` (`frontend/embed.go`), so the same Flutter desktop UI is also
served to browsers as the LAN web console. Run this before `go build ./cmd/service`.

The build is what lands in `dist`: the script wipes it first so a stale bundle can never be served.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

DESKTOP_DIR = Path(__file__).resolve().parent
ROOT_DIR = DESKTOP_DIR.parent
FLUTTER_DIR = ROOT_DIR / "DITING-Flutter" / "apps" / "diting_desktop"
DIST_DIR = DESKTOP_DIR / "frontend" / "dist"
ENTRY = "lib/main.dart"


def log(message: str) -> None:
    print(f"[frontend] {message}", flush=True)


def fail(message: str) -> int:
    print(f"[frontend] 错误: {message}", file=sys.stderr, flush=True)
    return 1


def run(command: list[str]) -> None:
    log(" ".join(command))
    subprocess.run(command, cwd=FLUTTER_DIR, check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--deps-only",
        action="store_true",
        help="只解析 Flutter 依赖，不构建 Web 产物",
    )
    args = parser.parse_args()

    if not (FLUTTER_DIR / "pubspec.yaml").exists():
        return fail(f"找不到 Flutter 工程: {FLUTTER_DIR}")
    flutter = shutil.which("flutter")
    if flutter is None:
        return fail("未找到 flutter 命令，请先安装 Flutter SDK 并加入 PATH")

    run([flutter, "pub", "get"])
    if args.deps_only:
        return 0

    # 清空 dist，避免上一版产物残留。
    if DIST_DIR.exists():
        shutil.rmtree(DIST_DIR)
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    try:
        run(
            [
                flutter,
                "build",
                "web",
                "--release",
                "-t",
                ENTRY,
                "--output",
                str(DIST_DIR),
            ]
        )
    except subprocess.CalledProcessError as error:
        return fail(f"flutter build web 失败（退出码 {error.returncode}）")

    index = DIST_DIR / "index.html"
    if not index.exists():
        return fail(f"构建完成但缺少 {index}")
    log(f"Flutter Web 产物已写入 {DIST_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
