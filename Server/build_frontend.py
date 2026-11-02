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


def resolve_dependencies(flutter: str) -> bool:
    """解析依赖；网络不可用时允许复用已有的 package_config。"""
    log(" ".join([flutter, "pub", "get"]))
    if subprocess.run([flutter, "pub", "get"], cwd=FLUTTER_DIR).returncode == 0:
        return True
    package_config = ROOT_DIR / "DITING-Flutter" / ".dart_tool" / "package_config.json"
    if package_config.exists():
        log("flutter pub get 失败，但已有依赖解析缓存，继续构建")
        return True
    return False


def prune_unused_renderers(dist_dir: Path) -> None:
    """删除 Release 不需要的 CanvasKit 变体与调试符号文件。

    `web/flutter_bootstrap.js` 固定了 `canvasKitBaseUrl: "canvaskit/"` 与
    `canvasKitVariant: "full"`，因此运行时只会请求 `canvaskit/canvaskit.js` 和
    `canvaskit/canvaskit.wasm`；chromium/webparagraph/skwasm/wimp 与 .symbols 都不会被加载。
    """
    canvaskit = dist_dir / "canvaskit"
    if not canvaskit.is_dir():
        return
    removed = 0
    for variant in ("chromium", "webparagraph"):
        variant_dir = canvaskit / variant
        if variant_dir.is_dir():
            removed += sum(1 for path in variant_dir.rglob("*") if path.is_file())
            shutil.rmtree(variant_dir)
    for pattern in ("skwasm*", "wimp*", "*.symbols", "*.map"):
        for path in canvaskit.rglob(pattern):
            if path.is_file():
                path.unlink()
                removed += 1
    if removed:
        log(f"已移除 {removed} 个未使用的渲染器/调试文件")


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

    if not resolve_dependencies(flutter):
        return fail("flutter pub get 失败，且没有可用的依赖解析缓存")
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
                "--no-pub",
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
    prune_unused_renderers(DIST_DIR)
    log(f"Flutter Web 产物已写入 {DIST_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
