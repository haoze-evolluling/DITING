"""
谛听 (DITING) 品牌 Logo 矢量化生成与多尺寸图标导出脚本
采用与安卓端完全同构的 Squircle（超椭圆圆角）徽标与核心球体雷达图腾，
主色调融合 Material Design 经典天蓝色 (#0288D1)。
"""

import os
import xml.etree.ElementTree as ET
from PIL import Image
from PyQt6.QtCore import QByteArray
from PyQt6.QtGui import QColor, QImage, QPainter
from PyQt6.QtSvg import QSvgRenderer

# Android 矢量资源绝对/相对路径
ANDROID_XML = os.path.join(os.path.dirname(__file__), "..", "Android", "app", "src", "main", "res", "drawable", "ic_splash_squircle_logo.xml")

def extract_paths_from_android():
    tree = ET.parse(os.path.abspath(ANDROID_XML))
    paths = []
    for p in tree.iter():
        if p.tag.endswith("path"):
            fill = p.attrib.get("{http://schemas.android.com/apk/res/android}fillColor")
            stroke = p.attrib.get("{http://schemas.android.com/apk/res/android}strokeColor")
            d = p.attrib.get("{http://schemas.android.com/apk/res/android}pathData", "")
            paths.append((fill, stroke, d))
    return paths

def generate_squircle_svg(bg_color="#0288D1", totem_color="#FFFFFF", sphere_bg="rgba(255,255,255,0.08)", subtle_gradient=True):
    """
    生成高精度 SVG 矢量字符串。
    Squircle (超椭圆) 曲线与球体雷达图腾完全同构于 Android 端。
    """
    paths = extract_paths_from_android()
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
        fill_attr = 'url(#ditingBgGrad)'
        sphere_fill = 'url(#sphereGlow)' if sphere_bg else 'none'
    else:
        defs = ""
        fill_attr = bg_color
        sphere_fill = sphere_bg if sphere_bg else 'none'

    totem_paths_svg = "\n      ".join(f'<path fill="{totem_color}" d="{d}" />' for d in totem_ds)

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 144 144" width="1024" height="1024">
{defs}
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

def render_svg_to_qimage(svg_content: str, width: int, height: int) -> QImage:
    renderer = QSvgRenderer(QByteArray(svg_content.encode("utf-8")))
    img = QImage(width, height, QImage.Format.Format_ARGB32_Premultiplied)
    img.fill(QColor(0, 0, 0, 0))
    painter = QPainter(img)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
    painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, True)
    renderer.render(painter)
    painter.end()
    return img

def qimage_to_pil(qimg: QImage) -> Image.Image:
    ptr = qimg.bits()
    ptr.setsize(qimg.sizeInBytes())
    arr = bytes(ptr)
    pil_img = Image.frombuffer("RGBA", (qimg.width(), qimg.height()), arr, "raw", "BGRA", 0, 1)
    return pil_img

def export_all_assets():
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    windows_dir = os.path.join(root_dir, "Windows")

    svg_content = generate_squircle_svg(subtle_gradient=True)

    # 1. 导出高清 SVG 至 Windows 资源目录备用
    svg_out_path = os.path.join(windows_dir, "frontend", "src", "assets", "images", "logo.svg")
    with open(svg_out_path, "w", encoding="utf-8") as f:
        f.write(svg_content)
    print(f"[OK] 导出 SVG 矢量图: {svg_out_path}")

    # 2. 导出 1024x1024 appicon.png (用于 Wails 构建和各类高分屏缩放)
    qimg_1024 = render_svg_to_qimage(svg_content, 1024, 1024)
    pil_1024 = qimage_to_pil(qimg_1024)
    
    build_appicon_path = os.path.join(windows_dir, "build", "appicon.png")
    pil_1024.save(build_appicon_path, "PNG")
    print(f"[OK] 导出应用主图标: {build_appicon_path}")

    # 3. 导出导航栏徽标 logo-universal.png (512x512)
    qimg_512 = render_svg_to_qimage(svg_content, 512, 512)
    pil_512 = qimage_to_pil(qimg_512)
    frontend_logo_path = os.path.join(windows_dir, "frontend", "src", "assets", "images", "logo-universal.png")
    pil_512.save(frontend_logo_path, "PNG")
    print(f"[OK] 导出前端导航栏图标: {frontend_logo_path}")

    # 4. 生成 Windows 多分辨率 ICO 文件 (含 16, 24, 32, 48, 64, 128, 256)
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    ico_images = []
    for s in ico_sizes:
        q_s = render_svg_to_qimage(svg_content, s, s)
        pil_s = qimage_to_pil(q_s)
        ico_images.append(pil_s)

    ico_out_path = os.path.join(windows_dir, "build", "windows", "icon.ico")
    # PIL save ico: first image + append_images
    ico_images[-1].save(ico_out_path, format="ICO", sizes=[(s, s) for s in ico_sizes], append_images=ico_images[:-1])
    print(f"[OK] 导出 Windows 多分辨率 ICO: {ico_out_path}")

if __name__ == "__main__":
    export_all_assets()
