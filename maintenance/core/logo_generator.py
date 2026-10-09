#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 品牌 Logo 矢量化生成与多规格图标导出引擎
"""

import os
import sys
import xml.etree.ElementTree as ET
from typing import Callable, List, Optional, Tuple

try:
    from PIL import Image
    from PyQt6.QtCore import QByteArray
    from PyQt6.QtGui import QColor, QImage, QPainter
    from PyQt6.QtSvg import QSvgRenderer
    QT_AVAILABLE = True
except ImportError:
    QT_AVAILABLE = False


def get_android_xml_path() -> str:
    current_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.abspath(os.path.join(current_dir, "..", ".."))
    return os.path.join(root_dir, "Android", "app", "src", "main", "res", "drawable", "ic_splash_squircle_logo.xml")


def extract_paths_from_android(xml_path: Optional[str] = None) -> List[Tuple[Optional[str], Optional[str], str]]:
    if not xml_path:
        xml_path = get_android_xml_path()
    if not os.path.exists(xml_path):
        raise FileNotFoundError(f"未找到 Android Logo XML 矢量资源: {xml_path}")

    tree = ET.parse(xml_path)
    paths = []
    for p in tree.iter():
        if p.tag.endswith("path"):
            fill = p.attrib.get("{http://schemas.android.com/apk/res/android}fillColor")
            stroke = p.attrib.get("{http://schemas.android.com/apk/res/android}strokeColor")
            d = p.attrib.get("{http://schemas.android.com/apk/res/android}pathData", "")
            paths.append((fill, stroke, d))
    return paths


def generate_squircle_svg(
    bg_color: str = "#d4e3ff",
    totem_color: str = "#404a58",
    sphere_bg: Optional[str] = None,
    subtle_gradient: bool = False,
    xml_path: Optional[str] = None,
) -> str:
    paths = extract_paths_from_android(xml_path)
    squircle_d = paths[0][2]
    sphere_bg_d = paths[1][2]
    totem_ds = [p[2] for p in paths[2:]]

    if subtle_gradient:
        defs = """
  <defs>
    <linearGradient id="ditingBgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#039BE5" />
      <stop offset="50%" stop-color="#0288D1" />
      <stop offset="100%" stop-color="#0277BD" />
    </linearGradient>
    <radialGradient id="sphereGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.12" />
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0.02" />
    </radialGradient>
  </defs>"""
        fill_attr = "url(#ditingBgGrad)"
        sphere_fill = "url(#sphereGlow)" if sphere_bg else "none"
    else:
        defs = ""
        fill_attr = bg_color
        sphere_fill = sphere_bg if sphere_bg else "none"

    totem_paths_svg = "\n      ".join(f'<path fill="{totem_color}" d="{d}" />' for d in totem_ds)

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 144 144" width="1024" height="1024">{defs}
  <g transform="translate(-72, -72)">
    <!-- 1. Squircle (N=3 超椭圆) 容器 -->
    <path fill="{fill_attr}" d="{squircle_d}" />
    <!-- 2. 居中球体雷达图腾 (核心品牌资产) -->
    <g transform="translate(75.95, 76.54) scale(0.1328125)">
      <path fill="{sphere_fill}" d="{sphere_bg_d}" />
      {totem_paths_svg}
    </g>
  </g>
</svg>"""
    return svg


def render_svg_to_qimage(svg_content: str, width: int, height: int) -> "QImage":
    if not QT_AVAILABLE:
        raise RuntimeError("未安装 PyQt6 库，无法进行高精度矢量图形光栅化渲染。")
    renderer = QSvgRenderer(QByteArray(svg_content.encode("utf-8")))
    img = QImage(width, height, QImage.Format.Format_ARGB32_Premultiplied)
    img.fill(QColor(0, 0, 0, 0))
    painter = QPainter(img)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
    painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, True)
    renderer.render(painter)
    painter.end()
    return img


def qimage_to_pil(qimg: "QImage") -> "Image.Image":
    ptr = qimg.bits()
    ptr.setsize(qimg.sizeInBytes())
    arr = bytes(ptr)
    pil_img = Image.frombuffer("RGBA", (qimg.width(), qimg.height()), arr, "raw", "BGRA", 0, 1)
    return pil_img


def export_logo_assets(
    bg_color: str = "#d4e3ff",
    totem_color: str = "#404a58",
    subtle_gradient: bool = False,
    output_dir: Optional[str] = None,
    on_log: Optional[Callable[[str, str], None]] = None,
) -> dict:
    current_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.abspath(os.path.join(current_dir, "..", ".."))
    windows_dir = os.path.join(root_dir, "Windows")

    def _log(lvl, msg):
        if on_log:
            on_log(lvl, msg)
        else:
            print(f"[{lvl.upper()}] {msg}")

    svg_content = generate_squircle_svg(
        bg_color=bg_color,
        totem_color=totem_color,
        sphere_bg=None,
        subtle_gradient=subtle_gradient,
    )

    exported_files = []

    # 1. 默认 Windows 项目目录导出
    svg_out_path = os.path.join(windows_dir, "frontend", "src", "assets", "images", "logo.svg")
    os.makedirs(os.path.dirname(svg_out_path), exist_ok=True)
    with open(svg_out_path, "w", encoding="utf-8") as f:
        f.write(svg_content)
    _log("info", f"导出 SVG 矢量图: {svg_out_path}")
    exported_files.append(svg_out_path)

    # 2. 导出 1024x1024 appicon.png
    qimg_1024 = render_svg_to_qimage(svg_content, 1024, 1024)
    pil_1024 = qimage_to_pil(qimg_1024)
    build_appicon_path = os.path.join(windows_dir, "build", "appicon.png")
    os.makedirs(os.path.dirname(build_appicon_path), exist_ok=True)
    pil_1024.save(build_appicon_path, "PNG")
    _log("info", f"导出应用主图标: {build_appicon_path}")
    exported_files.append(build_appicon_path)

    # 3. 导出导航栏徽标 logo-universal.png (512x512)
    qimg_512 = render_svg_to_qimage(svg_content, 512, 512)
    pil_512 = qimage_to_pil(qimg_512)
    frontend_logo_path = os.path.join(windows_dir, "frontend", "src", "assets", "images", "logo-universal.png")
    pil_512.save(frontend_logo_path, "PNG")
    _log("info", f"导出前端导航栏图标: {frontend_logo_path}")
    exported_files.append(frontend_logo_path)

    # 4. 生成 Windows 多分辨率 ICO (16, 24, 32, 48, 64, 128, 256)
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    ico_images = []
    for s in ico_sizes:
        q_s = render_svg_to_qimage(svg_content, s, s)
        pil_s = qimage_to_pil(q_s)
        ico_images.append(pil_s)

    ico_out_path = os.path.join(windows_dir, "build", "windows", "icon.ico")
    os.makedirs(os.path.dirname(ico_out_path), exist_ok=True)
    ico_images[-1].save(ico_out_path, format="ICO", sizes=[(s, s) for s in ico_sizes], append_images=ico_images[:-1])
    _log("info", f"导出 Windows 多分辨率 ICO: {ico_out_path}")
    exported_files.append(ico_out_path)

    # 5. 若指定了外部 output_dir，同时输出一份到指定目录
    if output_dir and os.path.isdir(output_dir):
        custom_svg = os.path.join(output_dir, "diting_logo.svg")
        with open(custom_svg, "w", encoding="utf-8") as f:
            f.write(svg_content)
        custom_png = os.path.join(output_dir, "diting_logo_1024.png")
        pil_1024.save(custom_png, "PNG")
        custom_ico = os.path.join(output_dir, "diting_logo.ico")
        ico_images[-1].save(custom_ico, format="ICO", sizes=[(s, s) for s in ico_sizes], append_images=ico_images[:-1])
        _log("info", f"导出自选目录产物至: {output_dir}")
        exported_files.extend([custom_svg, custom_png, custom_ico])

    return {
        "success": True,
        "files": exported_files,
        "svg_content": svg_content,
    }


def main():
    import argparse
    parser = argparse.ArgumentParser(description="谛听品牌 Logo 渲染导出工具")
    parser.add_argument("--bg", default="#d4e3ff", help="背景底色 hex")
    parser.add_argument("--totem", default="#404a58", help="图腾颜色 hex")
    parser.add_argument("--gradient", action="store_true", help="启用渐变质感")
    parser.add_argument("-o", "--out", default=None, help="自定义导出目录")
    args = parser.parse_args()

    res = export_logo_assets(bg_color=args.bg, totem_color=args.totem, subtle_gradient=args.gradient, output_dir=args.out)
    print(f"导出完成，共生成 {len(res['files'])} 个目标文件。")


if __name__ == "__main__":
    main()
