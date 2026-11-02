#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 轻量矢量路径光栅化引擎

不依赖 Qt / cairo / rsvg / 浏览器，仅用 Pillow 完成：
  * SVG path 数据解析（完整支持 M/L/H/V/C/S/Q/T/A/Z 与相对指令）
  * 仿射变换（等价于 Android VectorDrawable 的 group translate/scale）
  * non-zero winding 扫描线填充（与 VectorDrawable 默认 fillType 一致）
  * 超采样抗锯齿

品牌图标只有纯色路径，没有渐变 / 滤镜 / 蒙版，因此原生解析即可精确复现。
"""

import math
import re
from typing import Iterable, List, Optional, Sequence, Tuple

from PIL import Image, ImageDraw

Point = Tuple[float, float]
Contour = List[Point]
Matrix = Tuple[float, float, float, float, float, float]  # a b c d e f

IDENTITY: Matrix = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)

_TOKEN_RE = re.compile(
    r"([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)"
)

# 单个三次曲线的最大采样步数；步长由弦长与容差共同决定。
_MIN_CURVE_STEPS = 2
_MAX_CURVE_STEPS = 256


def _tokenize(path_data: str) -> List[Tuple[str, str]]:
    tokens: List[Tuple[str, str]] = []
    for match in _TOKEN_RE.finditer(path_data):
        if match.group(1):
            tokens.append(("cmd", match.group(1)))
        else:
            tokens.append(("num", match.group(2)))
    return tokens


def multiply(m1: Matrix, m2: Matrix) -> Matrix:
    """返回 m1 · m2：先应用 m2，再应用 m1。"""
    a1, b1, c1, d1, e1, f1 = m1
    a2, b2, c2, d2, e2, f2 = m2
    return (
        a1 * a2 + c1 * b2,
        b1 * a2 + d1 * b2,
        a1 * c2 + c1 * d2,
        b1 * c2 + d1 * d2,
        a1 * e2 + c1 * f2 + e1,
        b1 * e2 + d1 * f2 + f1,
    )


def translation(tx: float, ty: float) -> Matrix:
    return (1.0, 0.0, 0.0, 1.0, tx, ty)


def scaling(sx: float, sy: Optional[float] = None) -> Matrix:
    return (sx, 0.0, 0.0, sx if sy is None else sy, 0.0, 0.0)


def apply_matrix(matrix: Matrix, point: Point) -> Point:
    a, b, c, d, e, f = matrix
    x, y = point
    return (a * x + c * y + e, b * x + d * y + f)


def transform_contours(contours: Iterable[Contour], matrix: Matrix) -> List[Contour]:
    return [[apply_matrix(matrix, point) for point in contour] for contour in contours]


def fit_matrix(
    view_box: Tuple[float, float, float, float],
    width: int,
    height: int,
    supersample: int = 1,
) -> Matrix:
    """把 viewBox 等比居中铺满 width×height（再乘以超采样倍数）。"""
    vx, vy, vw, vh = view_box
    canvas_w = width * supersample
    canvas_h = height * supersample
    factor = min(canvas_w / vw, canvas_h / vh)
    tx = (canvas_w - vw * factor) / 2.0 - vx * factor
    ty = (canvas_h - vh * factor) / 2.0 - vy * factor
    return (factor, 0.0, 0.0, factor, tx, ty)


def _distance(p: Point, q: Point) -> float:
    return math.hypot(q[0] - p[0], q[1] - p[1])


def _polyline_length(points: Sequence[Point]) -> float:
    return sum(_distance(points[i - 1], points[i]) for i in range(1, len(points)))


def _cubic_points(p0: Point, p1: Point, p2: Point, p3: Point, steps: int) -> List[Point]:
    points: List[Point] = []
    for i in range(1, steps + 1):
        t = i / steps
        mt = 1.0 - t
        a = mt * mt * mt
        b = 3.0 * mt * mt * t
        c = 3.0 * mt * t * t
        d = t * t * t
        points.append(
            (
                a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1],
            )
        )
    return points


def _quad_points(p0: Point, p1: Point, p2: Point, steps: int) -> List[Point]:
    points: List[Point] = []
    for i in range(1, steps + 1):
        t = i / steps
        mt = 1.0 - t
        a = mt * mt
        b = 2.0 * mt * t
        c = t * t
        points.append(
            (a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1])
        )
    return points


def _curve_steps(control_polygon: Sequence[Point], tolerance: float) -> int:
    length = _polyline_length(control_polygon)
    steps = int(math.ceil(length / max(tolerance, 1e-6)))
    return max(_MIN_CURVE_STEPS, min(_MAX_CURVE_STEPS, steps))


def _arc_points(
    start: Point,
    rx: float,
    ry: float,
    rotation: float,
    large_arc: bool,
    sweep: bool,
    end: Point,
) -> List[Point]:
    """SVG 椭圆弧 → 折线（W3C SVG 1.1 附录 F.6 参数换算）。"""
    x1, y1 = start
    x2, y2 = end
    if abs(x1 - x2) < 1e-12 and abs(y1 - y2) < 1e-12:
        return []
    rx, ry = abs(rx), abs(ry)
    if rx < 1e-12 or ry < 1e-12:
        return [end]

    phi = math.radians(rotation % 360.0)
    cos_phi, sin_phi = math.cos(phi), math.sin(phi)
    dx2 = (x1 - x2) / 2.0
    dy2 = (y1 - y2) / 2.0
    x1p = cos_phi * dx2 + sin_phi * dy2
    y1p = -sin_phi * dx2 + cos_phi * dy2

    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1.0:
        factor = math.sqrt(lam)
        rx *= factor
        ry *= factor

    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = math.sqrt(max(0.0, num / den)) if den > 0 else 0.0
    if large_arc == sweep:
        coef = -coef
    cxp = coef * rx * y1p / ry
    cyp = -coef * ry * x1p / rx

    cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2.0
    cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2.0

    def signed_angle(ux: float, uy: float, vx: float, vy: float) -> float:
        norm = math.hypot(ux, uy) * math.hypot(vx, vy)
        if norm == 0:
            return 0.0
        cosine = max(-1.0, min(1.0, (ux * vx + uy * vy) / norm))
        sign = -1.0 if (ux * vy - uy * vx) < 0 else 1.0
        return sign * math.acos(cosine)

    theta1 = signed_angle(1.0, 0.0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    delta = signed_angle(
        (x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry
    )
    if not sweep and delta > 0:
        delta -= 2.0 * math.pi
    elif sweep and delta < 0:
        delta += 2.0 * math.pi

    segments = max(2, int(math.ceil(abs(delta) / (math.pi / 16.0))))
    alpha = 4.0 / 3.0 * math.tan(delta / (2.0 * segments))

    def point_at(angle: float, k: float) -> Point:
        cosine, sine = math.cos(angle), math.sin(angle)
        px = cosine - k * sine
        py = sine + k * cosine
        return (
            cx + rx * px * cos_phi - ry * py * sin_phi,
            cy + rx * px * sin_phi + ry * py * cos_phi,
        )

    points: List[Point] = []
    for index in range(segments):
        a1 = theta1 + index * delta / segments
        a2 = a1 + delta / segments
        p0 = point_at(a1, 0.0)
        p1 = point_at(a1, alpha)
        p2 = point_at(a2, -alpha)
        p3 = point_at(a2, 0.0)
        points.extend(_cubic_points(p0, p1, p2, p3, 6))
    if points:
        points[-1] = end
    return points


def parse_path(path_data: str, tolerance: float = 0.35) -> List[Contour]:
    """
    把 SVG path 展开成若干折线轮廓。

    每个子路径（M 开始的新轮廓）单独成一条，闭合轮廓首尾重合，
    供上层做 non-zero winding 判定，从而正确处理挖空（如圆环）。
    """
    tokens = _tokenize(path_data)
    contours: List[Contour] = []
    current: Contour = []

    cx = cy = 0.0
    start_x = start_y = 0.0
    prev_cmd = ""
    prev_cubic: Optional[Point] = None
    prev_quad: Optional[Point] = None
    cursor = 0

    def read(count: int) -> List[float]:
        nonlocal cursor
        values: List[float] = []
        for _ in range(count):
            while cursor < len(tokens) and tokens[cursor][0] != "num":
                cursor += 1
            if cursor >= len(tokens):
                raise ValueError(f"SVG path 参数不足: {path_data[:60]}…")
            values.append(float(tokens[cursor][1]))
            cursor += 1
        return values

    def flush() -> None:
        nonlocal current
        if len(current) >= 2:
            contours.append(current)
        current = []

    def add(point: Point) -> None:
        if not current or _distance(current[-1], point) > 1e-9:
            current.append(point)

    def extend(points: Sequence[Point]) -> None:
        for point in points:
            add(point)

    while cursor < len(tokens):
        kind, value = tokens[cursor]
        if kind == "cmd":
            cmd = value
            cursor += 1
        else:
            cmd = prev_cmd
            if not cmd:
                raise ValueError(f"SVG path 缺少起始指令: {path_data[:60]}…")

        relative = cmd.islower()
        op = cmd.upper()
        ox, oy = (cx, cy) if relative else (0.0, 0.0)

        if op == "M":
            x, y = read(2)
            flush()
            cx, cy = ox + x, oy + y
            start_x, start_y = cx, cy
            current = [(cx, cy)]
            prev_cubic = prev_quad = None
            prev_cmd = "l" if relative else "L"  # 隐式后续坐标按 lineto 处理
            continue
        if op == "L":
            x, y = read(2)
            cx, cy = ox + x, oy + y
            add((cx, cy))
            prev_cubic = prev_quad = None
        elif op == "H":
            (x,) = read(1)
            cx = (cx if relative else 0.0) + x
            add((cx, cy))
            prev_cubic = prev_quad = None
        elif op == "V":
            (y,) = read(1)
            cy = (cy if relative else 0.0) + y
            add((cx, cy))
            prev_cubic = prev_quad = None
        elif op in ("C", "S"):
            if op == "C":
                x1, y1, x2, y2, x, y = read(6)
                p1 = (ox + x1, oy + y1)
            else:
                x2, y2, x, y = read(4)
                p1 = (
                    (2.0 * cx - prev_cubic[0], 2.0 * cy - prev_cubic[1])
                    if prev_cubic
                    else (cx, cy)
                )
            p0 = (cx, cy)
            p2 = (ox + x2, oy + y2)
            p3 = (ox + x, oy + y)
            extend(
                _cubic_points(
                    p0, p1, p2, p3, _curve_steps([p0, p1, p2, p3], tolerance)
                )
            )
            cx, cy = p3
            prev_cubic, prev_quad = p2, None
        elif op in ("Q", "T"):
            if op == "Q":
                x1, y1, x, y = read(4)
                p1 = (ox + x1, oy + y1)
            else:
                x, y = read(2)
                p1 = (
                    (2.0 * cx - prev_quad[0], 2.0 * cy - prev_quad[1])
                    if prev_quad
                    else (cx, cy)
                )
            p0 = (cx, cy)
            p2 = (ox + x, oy + y)
            extend(_quad_points(p0, p1, p2, _curve_steps([p0, p1, p2], tolerance)))
            cx, cy = p2
            prev_quad, prev_cubic = p1, None
        elif op == "A":
            rx, ry, rotation, large_arc, sweep, x, y = read(7)
            end = (ox + x, oy + y)
            extend(
                _arc_points(
                    (cx, cy), rx, ry, rotation, bool(large_arc), bool(sweep), end
                )
            )
            add(end)
            cx, cy = end
            prev_cubic = prev_quad = None
        elif op == "Z":
            if current:
                first = current[0]
                add((start_x, start_y) if start_x != first[0] or start_y != first[1] else first)
            flush()
            cx, cy = start_x, start_y
            prev_cubic = prev_quad = None
        else:  # pragma: no cover - 正则已限制指令集合
            raise ValueError(f"不支持的 SVG path 指令: {cmd}")
        prev_cmd = cmd

    flush()
    return contours


def fill_mask(
    contours: Sequence[Contour],
    size: Tuple[int, int],
    matrix: Matrix = IDENTITY,
) -> "Image.Image":
    """non-zero winding 扫描线填充；返回单通道 L 蒙版（0 或 255）。"""
    width, height = size
    mask = Image.new("L", size, 0)
    if not contours:
        return mask

    edges: List[Tuple[float, float, float, float]] = []
    for contour in contours:
        points = transform_contours([contour], matrix)[0]
        count = len(points)
        if count < 2:
            continue
        for index in range(count):
            x0, y0 = points[index]
            x1, y1 = points[(index + 1) % count]
            if y0 == y1:
                continue
            edges.append((x0, y0, y1, (x1 - x0) / (y1 - y0)))
    if not edges:
        return mask

    min_y = max(0, int(math.floor(min(edge[1] for edge in edges))))
    max_y = min(height - 1, int(math.ceil(max(edge[2] for edge in edges))))
    draw = ImageDraw.Draw(mask)

    for y in range(min_y, max_y + 1):
        sample = y + 0.5
        crossings: List[Tuple[float, int]] = []
        for x0, y0, y1, slope in edges:
            if y0 <= sample < y1:
                crossings.append((x0 + (sample - y0) * slope, 1))
            elif y1 <= sample < y0:
                crossings.append((x0 + (sample - y0) * slope, -1))
        if len(crossings) < 2:
            continue
        crossings.sort()
        winding = 0
        span_start = 0.0
        for x, direction in crossings:
            if winding == 0:
                span_start = x
            winding += direction
            if winding == 0:
                # 向外取整，避免相邻跨段之间出现 1px 缝隙（超采样后再缩小几乎无影响）
                left = max(0, int(math.floor(span_start)))
                right = min(width - 1, int(math.ceil(x)) - 1)
                if right >= left:
                    draw.line([(left, y), (right, y)], fill=255)
    return mask


def parse_color(value: str) -> Tuple[int, int, int, int]:
    text = value.strip().lstrip("#")
    if len(text) == 3:
        text = "".join(char * 2 for char in text)
    elif len(text) == 4:
        text = "".join(char * 2 for char in text)
    if len(text) == 6:
        text += "FF"
    if len(text) != 8:
        raise ValueError(f"无法解析颜色: {value}")
    return (
        int(text[0:2], 16),
        int(text[2:4], 16),
        int(text[4:6], 16),
        int(text[6:8], 16),
    )


class Shape:
    """一条待绘制的路径：SVG path 数据 + 填充色 + 可选的局部变换。"""

    __slots__ = ("path_data", "color", "matrix")

    def __init__(self, path_data: str, color: str, matrix: Matrix = IDENTITY):
        self.path_data = path_data
        self.color = color
        self.matrix = matrix


def render(
    shapes: Sequence[Shape],
    width: int,
    height: int,
    view_box: Tuple[float, float, float, float],
    supersample: int = 4,
    tolerance: float = 0.25,
) -> "Image.Image":
    """按顺序叠加渲染所有形状，返回 RGBA 图像。"""
    canvas = Image.new("RGBA", (width * supersample, height * supersample), (0, 0, 0, 0))
    base = fit_matrix(view_box, width, height, supersample)
    # tolerance 以设备像素表示，换算回用户坐标系后再决定曲线细分密度
    user_tolerance = tolerance / max(base[0], 1e-9)

    for shape in shapes:
        contours = parse_path(shape.path_data, tolerance=user_tolerance)
        if not contours:
            continue
        mask = fill_mask(contours, canvas.size, multiply(base, shape.matrix))
        layer = Image.new("RGBA", canvas.size, parse_color(shape.color))
        canvas = Image.composite(layer, canvas, mask)

    if supersample > 1:
        canvas = canvas.resize((width, height), Image.LANCZOS)
    return canvas


def fit_canvas(
    image: "Image.Image", width: int, height: int, anchor: str = "center"
) -> "Image.Image":
    """把图像等比缩放到 width×height 的画布内（留透明边）。"""
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    factor = min(width / image.width, height / image.height)
    new_size = (max(1, round(image.width * factor)), max(1, round(image.height * factor)))
    resized = image.resize(new_size, Image.LANCZOS)
    if anchor == "center":
        offset = ((width - new_size[0]) // 2, (height - new_size[1]) // 2)
    else:
        offset = (0, 0)
    canvas.paste(resized, offset, resized)
    return canvas


def save_ico(image: "Image.Image", path: str, sizes: Sequence[int]) -> None:
    """写出多分辨率 Windows ICO（Pillow 会把各尺寸写进同一文件）。"""
    ordered = sorted(set(sizes))
    frames = [fit_canvas(image, size, size) for size in ordered]
    frames[-1].save(
        path,
        format="ICO",
        sizes=[(size, size) for size in ordered],
        append_images=frames[:-1],
    )
