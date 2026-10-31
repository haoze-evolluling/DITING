#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 品牌资产生成引擎

单一形状源：maintenance/assets/brand/ic_splash_squircle_logo.xml
（N=3 超椭圆容器 + 居中球体雷达图腾），配色由本模块统一定义：

  浅色模式  background #FAF8F9    foreground #007AFE
  深色模式  background #1F1F22    foreground #2E83FF

不依赖 Qt / cairo / rsvg —— 光栅化由 `core.vector_raster` 完成，仅需 Pillow。

用法：
    python -m maintenance.core.logo_generator            # 导出全部平台资源
    python -m maintenance.core.logo_generator --check    # 只校验源矢量可解析
"""

import os
import shutil
import sys
import xml.etree.ElementTree as ET
from typing import Callable, Dict, List, Optional, Sequence, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from PIL import Image

try:  # 作为包导入
    from . import vector_raster as vr
except ImportError:  # 直接脚本运行
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from core import vector_raster as vr  # type: ignore[no-redef]

AND = "{http://schemas.android.com/apk/res/android}"

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BRAND_XML = os.path.join(ROOT_DIR, "maintenance", "assets", "brand", "ic_splash_squircle_logo.xml")

# === 品牌调色板（唯一真源） ===
LIGHT = {"background": "#FAF8F9", "foreground": "#007AFE"}
DARK = {"background": "#1F1F22", "foreground": "#2E83FF"}

# Android 传统启动器位图规格（px）：mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi
ANDROID_DENSITIES: Sequence[Tuple[str, int]] = (
    ("mdpi", 48),
    ("hdpi", 72),
    ("xhdpi", 96),
    ("xxhdpi", 144),
    ("xxxhdpi", 192),
)

DESKTOP_SIZES = (1024, 512, 256)
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)

# Android 12+ splash icon. The brand card is authored on a 144dp artboard; the platform bounds
# the splash icon to a 192dp circle on a 288dp artboard, so the card is kept at 150dp — its
# rounded corners (radius 80.8 of 144, i.e. 84.2dp) stay inside that circle and never clip.
SPLASH_ARTBOARD = 288.0
SPLASH_CARD_SIDE = 150.0


def _log_default(level: str, message: str) -> None:
    print(f"[{level.upper()}] {message}")


# --------------------------------------------------------------------------- #
# 源矢量解析
# --------------------------------------------------------------------------- #
def load_shapes(palette: Dict[str, str], xml_path: Optional[str] = None) -> Tuple[List[vr.Shape], Tuple[float, float, float, float]]:
    """把 Android VectorDrawable 解析为可按任意配色渲染的形状序列。"""
    path = xml_path or BRAND_XML
    if not os.path.exists(path):
        raise FileNotFoundError(f"未找到品牌矢量源: {path}")

    root = ET.parse(path).getroot()
    view_w = float(root.get(AND + "viewportWidth"))
    view_h = float(root.get(AND + "viewportHeight"))
    color_map = {
        "@color/ic_launcher_background": palette["background"],
        "@color/ic_launcher_foreground": palette["foreground"],
    }
    shapes: List[vr.Shape] = []

    def walk(node: ET.Element, matrix: vr.Matrix) -> None:
        for child in node:
            tag = child.tag.split("}")[-1]
            if tag == "group":
                tx = float(child.get(AND + "translateX") or 0)
                ty = float(child.get(AND + "translateY") or 0)
                sx = float(child.get(AND + "scaleX") or 1)
                sy = float(child.get(AND + "scaleY") or 1)
                px = float(child.get(AND + "pivotX") or 0)
                py = float(child.get(AND + "pivotY") or 0)
                local = vr.multiply(
                    vr.translation(tx, ty),
                    vr.multiply(
                        vr.translation(px, py),
                        vr.multiply(vr.scaling(sx, sy), vr.translation(-px, -py)),
                    ),
                )
                walk(child, vr.multiply(matrix, local))
            elif tag == "path":
                data = child.get(AND + "pathData")
                fill = child.get(AND + "fillColor") or ""
                if not data or not fill:
                    continue
                color = color_map.get(fill, fill)
                if not color.startswith("#"):
                    continue
                shapes.append(vr.Shape(data, color, matrix))

    walk(root, vr.IDENTITY)
    if not shapes:
        raise ValueError(f"品牌矢量源中没有任何可渲染路径: {path}")
    return shapes, (0.0, 0.0, view_w, view_h)


_RENDER_CACHE: Dict[Tuple[str, int], Image.Image] = {}


def render_icon(palette: Dict[str, str], size: int, supersample: int = 4) -> Image.Image:
    """渲染正方形品牌图标（超椭圆底 + 球体雷达图腾），同配色同尺寸复用结果。"""
    key = (palette["background"] + palette["foreground"], size)
    cached = _RENDER_CACHE.get(key)
    if cached is not None:
        return cached.copy()
    shapes, view_box = load_shapes(palette)
    image = vr.render(shapes, size, size, view_box, supersample=supersample)
    _RENDER_CACHE[key] = image
    return image.copy()


def squircle_svg(palette: Dict[str, str]) -> str:
    """生成与位图完全等价的 SVG（供网页 / Linux pixmaps 使用）。"""
    shapes, (vx, vy, vw, vh) = load_shapes(palette)
    body = "\n  ".join(
        f'<path fill="{shape.color}" transform="matrix({",".join(f"{v:g}" for v in shape.matrix)})" '
        f'd="{shape.path_data}" />'
        for shape in shapes
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vx:g} {vy:g} {vw:g} {vh:g}" '
        f'width="{int(vw)}" height="{int(vh)}">\n'
        f"  <!-- 谛听 DITING 品牌图标：{palette['background']} / {palette['foreground']} -->\n"
        f"  {body}\n</svg>\n"
    )


def adaptive_svg() -> str:
    """随系统明暗自动切换的品牌 SVG（用于浏览器 favicon / 网页 logo）。"""
    light_svg = squircle_svg(LIGHT)
    dark_svg = squircle_svg(DARK)
    import re

    def body(svg: str) -> str:
        inner = svg.split(">", 1)[1].rsplit("</svg>", 1)[0]
        return re.sub(r"<!--.*?-->", "", inner, flags=re.S).strip()

    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 144 144" width="144" height="144">\n'
        "  <style>\n"
        "    .diting-brand--dark { display: none; }\n"
        "    @media (prefers-color-scheme: dark) {\n"
        "      .diting-brand--light { display: none; }\n"
        "      .diting-brand--dark { display: inline; }\n"
        "    }\n"
        "  </style>\n"
        f'  <g class="diting-brand--light">{body(light_svg)}</g>\n'
        f'  <g class="diting-brand--dark">{body(dark_svg)}</g>\n'
        "</svg>\n"
    )


# --------------------------------------------------------------------------- #
# 导出
# --------------------------------------------------------------------------- #
def _save_png(image: Image.Image, path: str, log: Callable[[str, str], None]) -> str:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, "PNG", optimize=True)
    log("info", f"PNG {image.width}x{image.height}: {path}")
    return path


def _save_ico(base: Image.Image, path: str, log: Callable[[str, str], None]) -> str:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames = [base.resize((s, s), Image.LANCZOS) for s in ICO_SIZES]
    frames[-1].save(path, format="ICO", sizes=[(s, s) for s in ICO_SIZES], append_images=frames[:-1])
    log("info", f"ICO {len(ICO_SIZES)} 规格: {path}")
    return path


def export_desktop(log: Callable[[str, str], None]) -> List[str]:
    """桌面端（Wails + Vue3）：Windows 图标、Linux pixmap、Web favicon 与前端资源。"""
    desktop = os.path.join(ROOT_DIR, "Desktop")
    files: List[str] = []

    light_1024 = render_icon(LIGHT, 1024)
    light_512 = light_1024.resize((512, 512), Image.LANCZOS)
    dark_512 = render_icon(DARK, 512)

    files.append(_save_png(light_1024, os.path.join(desktop, "build", "appicon.png"), log))
    files.append(_save_ico(light_512, os.path.join(desktop, "build", "windows", "icon.ico"), log))
    # Linux 桌面启动器 / 窗口管理器图标
    files.append(_save_png(light_512, os.path.join(desktop, "build", "linux", "diting.png"), log))

    assets = os.path.join(desktop, "frontend", "src", "assets", "images")
    files.append(_save_png(light_512, os.path.join(assets, "logo-universal.png"), log))
    files.append(_save_png(dark_512, os.path.join(assets, "logo-universal-dark.png"), log))

    public = os.path.join(desktop, "frontend", "public")
    files.append(_save_png(light_512, os.path.join(public, "appicon.png"), log))
    files.append(_save_ico(light_512, os.path.join(public, "favicon.ico"), log))
    files.append(_save_png(dark_512, os.path.join(public, "appicon-dark.png"), log))

    for path in (os.path.join(assets, "logo.svg"), os.path.join(public, "logo.svg")):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(adaptive_svg())
        log("info", f"SVG (随明暗切换): {path}")
        files.append(path)
    return files


def export_flutter_assets(log: Callable[[str, str], None]) -> List[str]:
    """Flutter 应用内展示用图标（关于页），浅色与深色各一份。"""
    images = os.path.join(ROOT_DIR, "DITING-Flutter", "assets", "images")
    files = [
        _save_png(render_icon(LIGHT, 512), os.path.join(images, "icon.png"), log),
        _save_png(render_icon(DARK, 512), os.path.join(images, "icon_dark.png"), log),
    ]
    return files


def splash_icon_xml(xml_path: Optional[str] = None) -> str:
    """由品牌方圆卡生成 Android 12+ 启动图标。

    输出是「卡片 + 细边线 + 图腾」的单张普通矢量，而非自适应图标：平台只会把自适应图标
    裁成圆形，自绘圆角才能在任何 OEM 皮肤（HyperOS / ColorOS / 原生）上都保持圆角矩形。
    `@color/` 名称原样保留，因此同一份文件同时服务浅色与深色模式。
    """
    source = xml_path or BRAND_XML
    root = ET.parse(source).getroot()
    # 元素名不带命名空间（只有 android:xxx 属性带），与 load_shapes 的遍历方式一致。
    card = next((n for n in root.iter("path") if n.get(AND + "strokeColor")), None)
    totem = next((n for n in root.iter("group") if n.get(AND + "scaleX")), None)
    if card is None or totem is None:
        raise ValueError(f"品牌矢量源缺少启动卡形状: {source}")

    scale = SPLASH_CARD_SIDE / float(root.get(AND + "viewportWidth"))
    offset = (SPLASH_ARTBOARD - SPLASH_CARD_SIDE) / 2.0

    def pad(depth: int) -> str:
        return "    " * depth

    out: List[str] = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<!-- Android 12+ splash icon: the brand card (rounded-square plate, hairline edge and',
        '     totem) as ONE plain vector rather than an adaptive icon. Android only masks',
        "     adaptive icons to a circle, so a self-contained vector keeps the card's own",
        '     rounded corners on every OEM skin (HyperOS, ColorOS, stock).',
        '',
        "     Generated by maintenance/core/logo_generator.py from the brand vector",
        "     `maintenance/assets/brand/ic_splash_squircle_logo.xml`, so the splash card",
        "     matches the launcher icon exactly. -->",
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
        f'{pad(1)}android:width="{SPLASH_ARTBOARD:g}dp"',
        f'{pad(1)}android:height="{SPLASH_ARTBOARD:g}dp"',
        f'{pad(1)}android:viewportWidth="{SPLASH_ARTBOARD:g}"',
        f'{pad(1)}android:viewportHeight="{SPLASH_ARTBOARD:g}">',
        f'{pad(1)}<!-- Brand 144dp card -> {SPLASH_CARD_SIDE:g}dp, centred on the artboard. -->',
        f'{pad(1)}<group',
        f'{pad(2)}android:scaleX="{scale:.8f}"',
        f'{pad(2)}android:scaleY="{scale:.8f}"',
        f'{pad(2)}android:translateX="{offset:g}"',
        f'{pad(2)}android:translateY="{offset:g}">',
        f'{pad(2)}<!-- Card space: the path below is authored at 72..216. -->',
        f'{pad(2)}<group',
        f'{pad(3)}android:translateX="-72"',
        f'{pad(3)}android:translateY="-72">',
        f'{pad(3)}<!-- 1. Rounded-square plate with its hairline edge. -->',
        f'{pad(3)}<path',
    ]
    for key in ("fillColor", "strokeColor", "strokeWidth", "pathData"):
        out.append(f'{pad(4)}android:{key}="{card.get(AND + key)}"')
    out[-1] += " />"
    out += [
        f'{pad(3)}<!-- 2. Totem at the scale, offset and colours the launcher icon uses. -->',
        f'{pad(3)}<group',
    ]
    for key in ("scaleX", "scaleY", "translateX", "translateY"):
        out.append(f'{pad(4)}android:{key}="{totem.get(AND + key)}"')
    out[-1] += ">"
    for node in totem.findall("path"):
        out.append(f'{pad(4)}<path')
        for key in ("fillColor", "pathData"):
            out.append(f'{pad(5)}android:{key}="{node.get(AND + key)}"')
        out[-1] += " />"
    out += [
        f'{pad(3)}</group>',
        f'{pad(2)}</group>',
        f'{pad(1)}</group>',
        '</vector>',
    ]
    return "\n".join(out) + "\n"


def export_android_launcher(res_dir: str, log: Callable[[str, str], None], label: str = "") -> List[str]:
    """
    生成传统启动器位图（API < 26 与部分第三方桌面使用）。

    只导出浅色一套：`values-night/colors.xml` 已经把自适应图标的颜色换成深色，而
    `mipmap-night-*` 变体在深色下会**压过** `mipmap-anydpi-v26`（uiMode 的匹配优先级
    高于 density 与 version），把图标降级成位图 —— 这正是 HyperOS / ColorOS 给它套上
    一层白色底板（图标外侧白边）的成因，因此绝不能生成。
    """
    if not os.path.isdir(res_dir):
        log("warn", f"跳过 {label or res_dir}：未找到 res 目录")
        return []

    files: List[str] = []
    base = render_icon(LIGHT, 192)
    for density, size in ANDROID_DENSITIES:
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            target = os.path.join(res_dir, f"mipmap-{density}", name)
            _save_png(base.resize((size, size), Image.LANCZOS), target, log)
            files.append(target)

    # 清掉早期版本留下的 mipmap-night-* 位图：它们会在深色模式下压过自适应图标，
    # 把图标降级成位图并招来桌面端的白色底板。目录空了就一并删掉。
    for density, _ in ANDROID_DENSITIES:
        stale = os.path.join(res_dir, f"mipmap-night-{density}")
        if os.path.isdir(stale):
            shutil.rmtree(stale)
            log("info", f"移除过期的深色位图目录: {stale}")
    return files


def export_android_splash(res_dir: str, log: Callable[[str, str], None], label: str = "") -> List[str]:
    """导出 Android 12+ 启动图标矢量（圆角矩形卡片，浅深通用）。"""
    if not os.path.isdir(res_dir):
        log("warn", f"跳过 {label or res_dir}：未找到 res 目录")
        return []
    target = os.path.join(res_dir, "drawable", "splash_icon.xml")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(splash_icon_xml())
    log("info", f"向量 {SPLASH_ARTBOARD:g}dp 启动卡: {target}")
    return [target]


def export_all(on_log: Optional[Callable[[str, str], None]] = None) -> Dict[str, object]:
    log = on_log or _log_default
    exported: List[str] = []
    exported += export_desktop(log)
    exported += export_flutter_assets(log)
    flutter_res = os.path.join(ROOT_DIR, "DITING-Flutter", "android", "app", "src", "main", "res")
    exported += export_android_launcher(flutter_res, log, "DITING-Flutter")
    # Flutter 是唯一在 v31 主题里声明了启动图标的工程。
    exported += export_android_splash(flutter_res, log, "DITING-Flutter")
    log("info", f"完成，共导出 {len(exported)} 个品牌资源文件")
    return {"success": True, "files": exported, "palettes": {"light": LIGHT, "dark": DARK}}


# --------------------------------------------------------------------------- #
# 维护工具箱兼容层（旧接口：自定义底色 / 图腾色）
# --------------------------------------------------------------------------- #
def generate_squircle_svg(
    bg_color: str = LIGHT["background"],
    totem_color: str = LIGHT["foreground"],
    subtle_gradient: bool = False,
    xml_path: Optional[str] = None,
) -> str:
    """兼容旧调用：返回单色 SVG。品牌规范已统一为纯色，渐变参数被忽略。"""
    palette = {"background": bg_color, "foreground": totem_color}
    shapes, (vx, vy, vw, vh) = load_shapes(palette, xml_path)
    body = "\n  ".join(
        f'<path fill="{shape.color}" transform="matrix({",".join(f"{v:g}" for v in shape.matrix)})" '
        f'd="{shape.path_data}" />'
        for shape in shapes
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vx:g} {vy:g} {vw:g} {vh:g}" '
        f'width="{int(vw)}" height="{int(vh)}">\n  {body}\n</svg>\n'
    )


def export_logo_assets(
    bg_color: Optional[str] = None,
    totem_color: Optional[str] = None,
    subtle_gradient: bool = False,
    output_dir: Optional[str] = None,
    on_log: Optional[Callable[[str, str], None]] = None,
) -> Dict[str, object]:
    """兼容旧调用：按品牌规范导出全部平台资源，并可额外输出到自定义目录。"""
    log = on_log or _log_default
    if subtle_gradient:
        log("warn", "品牌规范已统一为纯色图标，渐变参数被忽略")
    if bg_color or totem_color:
        log("warn", "自定义配色仅影响额外导出目录，仓库内资源始终使用品牌规范色")
    result = export_all(log)
    files = list(result["files"])  # type: ignore[arg-type]

    if output_dir and os.path.isdir(output_dir):
        custom_svg = os.path.join(output_dir, "diting_logo.svg")
        shake = {"background": bg_color or LIGHT["background"], "foreground": totem_color or LIGHT["foreground"]}
        with open(custom_svg, "w", encoding="utf-8") as handle:
            handle.write(squircle_svg(shake))
        files.append(custom_svg)
        files.append(
            _save_png(
                render_icon({"background": bg_color or LIGHT["background"], "foreground": totem_color or LIGHT["foreground"]}, 1024),
                os.path.join(output_dir, "diting_logo_1024.png"),
                log,
            )
        )
        log("info", f"已额外导出自选目录产物: {output_dir}")

    result["files"] = files
    return result


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="谛听品牌图标导出工具（无需 Qt）")
    parser.add_argument("--check", action="store_true", help="仅校验品牌矢量源可解析")
    parser.add_argument("--preview", default=None, help="输出一张浅/深色对照预览图到指定路径")
    args = parser.parse_args()

    if args.check:
        for name, palette in (("light", LIGHT), ("dark", DARK)):
            shapes, view_box = load_shapes(palette)
            print(f"{name}: {len(shapes)} 条路径, viewBox={view_box}")
        return 0

    if args.preview:
        light = render_icon(LIGHT, 512)
        dark = render_icon(DARK, 512)
        canvas = Image.new("RGB", (1024, 512), "#7F7F7F")
        canvas.paste(light, (0, 0), light)
        canvas.paste(dark, (512, 0), dark)
        canvas.save(args.preview, "PNG")
        print(f"预览已写入 {args.preview}")
        return 0

    export_all()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
