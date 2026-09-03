#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Material Design 图标批量导出工具：扫描项目中使用的 androidx.compose.material.icons 图标
（或通过参数指定），从本地 Gradle 缓存或 Google Maven 仓库获取 material-icons-extended/core
源码，将 Compose ImageVector 矢量路径精确无损转换为 Android VectorDrawable XML 导出到
res/drawable，避免在 Debug 模式下引入数万个图标类导致 DEX 膨胀；（可选）生成缺失 Extended
图标的 Kotlin 兼容文件，实现业务代码零修改编译。
"""

import argparse
import os
import re
import sys
import urllib.request
import zipfile
from typing import Dict, List, Optional, Set, Tuple


def camel_to_snake(name: str) -> str:
    """将驼峰命名转为下划线蛇形命名，如 WiFiOff -> wifi_off, DeleteSweep -> delete_sweep"""
    s1 = re.sub(r'(.)([A-Z][a-z]+)', r'\1_\2', name)
    s2 = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s1)
    return s2.lower()


def clean_num(n_str: str) -> str:
    """清理 Kotlin 浮点数字面量，如 12.0f -> 12, 12.5f -> 12.5"""
    n_str = n_str.strip().rstrip('fF')
    try:
        val = float(n_str)
        if val.is_integer():
            return str(int(val))
        return f"{val:g}"
    except ValueError:
        return n_str


def find_gradle_sources_jars() -> List[str]:
    """在 Gradle 缓存中查找 material-icons-extended 和 core 的 sources.jar"""
    cache_base = os.path.expanduser("~/.gradle/caches/modules-2/files-2.1/androidx.compose.material")
    if not os.path.exists(cache_base):
        return []

    jars = []
    for root, _, files in os.walk(cache_base):
        for f in files:
            if f.endswith("-sources.jar") and "material-icons" in f:
                jars.append(os.path.join(root, f))

    # 优先使用 extended
    jars.sort(key=lambda x: ("extended" not in x, x))
    return jars


def download_sources_jar(version: str = "1.7.8", target_dir: str = ".gradle_cache") -> str:
    """从 Google Maven 仓库下载 material-icons-extended sources.jar"""
    os.makedirs(target_dir, exist_ok=True)
    jar_name = f"material-icons-extended-android-{version}-sources.jar"
    target_path = os.path.join(target_dir, jar_name)
    if os.path.exists(target_path) and os.path.getsize(target_path) > 1024:
        return target_path

    url = (
        f"https://dl.google.com/dl/android/maven2/androidx/compose/material/"
        f"material-icons-extended-android/{version}/{jar_name}"
    )
    print(f"正在从 Google Maven 下载源码包: {url} ...")
    try:
        urllib.request.urlretrieve(url, target_path)
        print(f"下载完成: {target_path}")
        return target_path
    except Exception as e:
        print(f"下载失败: {e}", file=sys.stderr)
        raise


def scan_project_icons(scan_dir: str) -> Set[Tuple[str, str, str]]:
    """
    扫描项目 Kotlin 文件中的图标使用情况
    返回集合元素: (group, style, icon_name)
    例如: ('', 'filled', 'Dns'), ('automirrored', 'filled', 'AltRoute')
    """
    found_icons = set()

    # 匹配模式 1: Icons.Filled.X / Icons.Default.X / Icons.AutoMirrored.Filled.X 等
    pattern_usage = re.compile(
        r'Icons\.(?:(AutoMirrored)\.)?(Default|Filled|Outlined|Rounded|Sharp|TwoTone)\.([A-Za-z0-9_]+)'
    )

    # 匹配模式 2: import androidx.compose.material.icons.automirrored.filled.X
    pattern_import = re.compile(
        r'import\s+androidx\.compose\.material\.icons\.(?:(automirrored)\.)?(filled|outlined|rounded|sharp|twotone)\.([A-Za-z0-9_]+)'
    )

    for root, _, files in os.walk(scan_dir):
        for file in files:
            if file.endswith(".kt"):
                fpath = os.path.join(root, file)
                # 跳过自身生成的兼容文件以防循环引用
                if "ExtendedIcons" in file:
                    continue
                try:
                    with open(fpath, "r", encoding="utf-8") as f:
                        content = f.read()
                        for m in pattern_usage.finditer(content):
                            group = "automirrored" if m.group(1) else ""
                            style_raw = m.group(2).lower()
                            style = "filled" if style_raw == "default" else style_raw
                            name = m.group(3)
                            found_icons.add((group, style, name))
                        for m in pattern_import.finditer(content):
                            group = "automirrored" if m.group(1) else ""
                            style = m.group(2).lower()
                            name = m.group(3)
                            found_icons.add((group, style, name))
                except Exception as e:
                    print(f"读取文件 {fpath} 失败: {e}", file=sys.stderr)

    return found_icons


def parse_material_icon_kt(kt_code: str) -> Tuple[bool, List[Dict[str, Optional[str]]]]:
    """
    解析 Kotlin 文件中的 materialIcon DSL
    返回 (auto_mirror, paths)
    """
    auto_mirror = "autoMirror = true" in kt_code
    paths = []

    for m in re.finditer(r'\bmaterialPath\s*(\([^)]*\))?\s*\{', kt_code):
        args_str = m.group(1) or ""
        if args_str.startswith("(") and args_str.endswith(")"):
            args_str = args_str[1:-1]

        fill_alpha = None
        stroke_alpha = None
        fill_type = None

        for arg in args_str.split(","):
            arg = arg.strip()
            if not arg:
                continue
            if "fillAlpha" in arg:
                fill_alpha = clean_num(arg.split("=")[1].strip())
            elif "strokeAlpha" in arg:
                stroke_alpha = clean_num(arg.split("=")[1].strip())
            elif "pathFillType" in arg:
                if "EvenOdd" in arg:
                    fill_type = "evenOdd"
                elif "NonZero" in arg:
                    fill_type = "nonZero"

        open_brace = m.end() - 1
        depth = 0
        close_brace = -1
        for i in range(open_brace, len(kt_code)):
            if kt_code[i] == "{":
                depth += 1
            elif kt_code[i] == "}":
                depth -= 1
                if depth == 0:
                    close_brace = i
                    break

        if close_brace == -1:
            continue

        body = kt_code[open_brace + 1:close_brace]
        path_cmds = []
        cmd_matches = re.finditer(r'([a-zA-Z0-9_]+)\s*\((.*?)\)', body, re.DOTALL)
        for cm in cmd_matches:
            cmd = cm.group(1)
            raw_args = cm.group(2).strip()
            args = [clean_num(a) for a in raw_args.split(",") if a.strip()] if raw_args else []

            if cmd == "moveTo":
                path_cmds.append(f"M{args[0]},{args[1]}")
            elif cmd == "moveToRelative":
                path_cmds.append(f"m{args[0]},{args[1]}")
            elif cmd == "lineTo":
                path_cmds.append(f"L{args[0]},{args[1]}")
            elif cmd == "lineToRelative":
                path_cmds.append(f"l{args[0]},{args[1]}")
            elif cmd == "horizontalLineTo":
                path_cmds.append(f"H{args[0]}")
            elif cmd == "horizontalLineToRelative":
                path_cmds.append(f"h{args[0]}")
            elif cmd == "verticalLineTo":
                path_cmds.append(f"V{args[0]}")
            elif cmd == "verticalLineToRelative":
                path_cmds.append(f"v{args[0]}")
            elif cmd == "curveTo":
                path_cmds.append(f"C{args[0]},{args[1]},{args[2]},{args[3]},{args[4]},{args[5]}")
            elif cmd == "curveToRelative":
                path_cmds.append(f"c{args[0]},{args[1]},{args[2]},{args[3]},{args[4]},{args[5]}")
            elif cmd == "reflectiveCurveTo":
                path_cmds.append(f"S{args[0]},{args[1]},{args[2]},{args[3]}")
            elif cmd == "reflectiveCurveToRelative":
                path_cmds.append(f"s{args[0]},{args[1]},{args[2]},{args[3]}")
            elif cmd == "arcTo":
                large_arc = "1" if "true" in args[3].lower() else "0"
                sweep = "1" if "true" in args[4].lower() else "0"
                path_cmds.append(f"A{args[0]},{args[1]},{args[2]},{large_arc},{sweep},{args[5]},{args[6]}")
            elif cmd == "arcToRelative":
                large_arc = "1" if "true" in args[3].lower() else "0"
                sweep = "1" if "true" in args[4].lower() else "0"
                path_cmds.append(f"a{args[0]},{args[1]},{args[2]},{large_arc},{sweep},{args[5]},{args[6]}")
            elif cmd == "close":
                path_cmds.append("z")

        paths.append({
            "pathData": "".join(path_cmds),
            "fillAlpha": fill_alpha,
            "strokeAlpha": stroke_alpha,
            "fillType": fill_type
        })

    return auto_mirror, paths


def generate_vector_drawable_xml(auto_mirror: bool, paths: List[Dict[str, Optional[str]]]) -> str:
    """生成标准 Android VectorDrawable XML 内容"""
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
        '    android:width="24dp"',
        '    android:height="24dp"',
        '    android:viewportWidth="24"',
        '    android:viewportHeight="24"'
    ]
    if auto_mirror:
        lines.append('    android:autoMirrored="true"')
    lines[-1] += '>'

    for p in paths:
        path_attrs = ['    <path', '        android:fillColor="#FFFFFFFF"']
        if p.get("fillAlpha"):
            path_attrs.append(f'        android:fillAlpha="{p["fillAlpha"]}"')
        if p.get("strokeAlpha"):
            path_attrs.append(f'        android:strokeAlpha="{p["strokeAlpha"]}"')
        if p.get("fillType"):
            path_attrs.append(f'        android:fillType="{p["fillType"]}"')
        path_attrs.append(f'        android:pathData="{p["pathData"]}" />')
        lines.extend(path_attrs)

    lines.append('</vector>')
    return "\n".join(lines) + "\n"


class IconJarIndex:
    """对 sources.jar 中的图标文件建立索引"""

    def __init__(self, jar_paths: List[str]):
        self.jar_paths = jar_paths
        self.entries: Dict[str, Tuple[str, str]] = {}
        self.core_icons: Set[Tuple[str, str, str]] = set()
        self._build_index()

    def _build_index(self):
        for jar_path in self.jar_paths:
            if not os.path.exists(jar_path):
                continue
            is_core = "material-icons-core" in jar_path
            with zipfile.ZipFile(jar_path, 'r') as z:
                for name in z.namelist():
                    if name.endswith(".kt") and not name.endswith("package-info.kt"):
                        parts = name.replace("\\", "/").split("/")
                        file_name = parts[-1][:-3]
                        if len(parts) >= 3:
                            style = parts[-2].lower()
                            is_automirrored = "automirrored" in parts
                            group = "automirrored" if is_automirrored else ""

                            key_exact = f"{group}:{style}:{file_name.lower()}"
                            self.entries[key_exact] = (jar_path, name)

                            key_style = f"{style}:{file_name.lower()}"
                            if key_style not in self.entries:
                                self.entries[key_style] = (jar_path, name)

                            key_name = file_name.lower()
                            if key_name not in self.entries:
                                self.entries[key_name] = (jar_path, name)

                            if is_core:
                                self.core_icons.add((group, style, file_name))

    def find_icon(self, group: str, style: str, icon_name: str) -> Optional[Tuple[str, str]]:
        """查找图标源码位置"""
        name_lower = icon_name.lower()
        key_exact = f"{group.lower()}:{style.lower()}:{name_lower}"
        if key_exact in self.entries:
            return self.entries[key_exact]

        key_style = f"{style.lower()}:{name_lower}"
        if key_style in self.entries:
            return self.entries[key_style]

        if name_lower in self.entries:
            return self.entries[name_lower]

        return None

    def is_in_core(self, group: str, style: str, icon_name: str) -> bool:
        """判断图标是否已包含在 material-icons-core 中"""
        return (
            (group.lower(), style.lower(), icon_name) in self.core_icons or
            ("", style.lower(), icon_name) in self.core_icons
        )

    def read_icon_code(self, jar_path: str, entry_name: str) -> str:
        with zipfile.ZipFile(jar_path, 'r') as z:
            return z.read(entry_name).decode('utf-8')


def export_icons(
    icons_to_export: Set[Tuple[str, str, str]],
    jar_index: IconJarIndex,
    output_dir: str,
    prefix: str = "ic_",
    force: bool = False,
    dry_run: bool = False
) -> List[Tuple[str, str, str]]:
    """
    批量导出图标
    返回成功导出的列表 [(icon_name, file_name, file_path), ...]
    """
    os.makedirs(output_dir, exist_ok=True)
    exported = []
    failed = []

    for group, style, icon_name in sorted(icons_to_export):
        target_name = f"{prefix}{camel_to_snake(icon_name)}.xml"
        target_path = os.path.join(output_dir, target_name)

        if os.path.exists(target_path) and not force:
            print(f"[已存在跳过] {icon_name} -> {target_name}")
            exported.append((icon_name, target_name, target_path))
            continue

        loc = jar_index.find_icon(group, style, icon_name)
        if not loc:
            failed.append((group, style, icon_name))
            continue

        jar_path, entry_name = loc
        kt_code = jar_index.read_icon_code(jar_path, entry_name)
        auto_mirror, paths = parse_material_icon_kt(kt_code)

        if not paths:
            print(f"[解析异常] {icon_name} 在 {entry_name} 中未找到路径数据", file=sys.stderr)
            failed.append((group, style, icon_name))
            continue

        xml_content = generate_vector_drawable_xml(auto_mirror, paths)

        if dry_run:
            print(f"[预览导出] {icon_name} -> {target_name} ({len(paths)} 路径)")
        else:
            with open(target_path, "w", encoding="utf-8") as f:
                f.write(xml_content)
            print(f"[成功导出] {icon_name:<25} -> {target_name} (AutoMirror: {auto_mirror}, 路径数: {len(paths)})")

        exported.append((icon_name, target_name, target_path))

    if failed:
        print("\n以下图标在源码包中未找到:")
        for group, style, name in failed:
            print(f"  - group='{group}', style='{style}', name='{name}'")

    return exported


def generate_kotlin_compat_files(
    icons_to_export: Set[Tuple[str, str, str]],
    jar_index: IconJarIndex,
    target_dir: str
):
    """
    为缺失的 Extended 图标生成 Kotlin 扩展兼容文件（按官方 package 分组）。
    这样即使移除 icons.extended 依赖，项目现有的 import 和调用也无需修改。
    """
    os.makedirs(target_dir, exist_ok=True)

    packages: Dict[str, Tuple[str, List[str]]] = {
        "androidx.compose.material.icons.filled": ("ExtendedIconsFilled.kt", []),
        "androidx.compose.material.icons.automirrored.filled": ("ExtendedIconsAutoMirrored.kt", []),
        "androidx.compose.material.icons.outlined": ("ExtendedIconsOutlined.kt", []),
    }

    total_extended_icons = 0

    for group, style, name in sorted(icons_to_export):
        if jar_index.is_in_core(group, style, name):
            continue

        loc = jar_index.find_icon(group, style, name)
        if not loc:
            continue

        jar_path, entry_name = loc
        code = jar_index.read_icon_code(jar_path, entry_name)
        pos = code.find("public val Icons.")
        if pos == -1:
            continue

        val_code = code[pos:].strip()

        pkg = "androidx.compose.material.icons." + (f"{group}." if group else "") + style
        if pkg not in packages:
            filename = f"ExtendedIcons{style.capitalize()}.kt"
            packages[pkg] = (filename, [])

        packages[pkg][1].append(val_code)
        total_extended_icons += 1

    for pkg, (filename, blocks) in packages.items():
        if not blocks:
            continue
        file_path = os.path.join(target_dir, filename)
        content = f"""/*
 * Auto-generated Material Icons compatibility file.
 * Contains only the extended icons actually referenced by this project.
 */

package {pkg}

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.materialIcon
import androidx.compose.material.icons.materialPath
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.PathFillType

""" + "\n\n".join(blocks) + "\n"

        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"[生成 Kotlin 兼容文件] {filename:<30} ({len(blocks)} 个图标) -> {file_path}")

    print(f"共生成 {total_extended_icons} 个 Extended 图标兼容定义。")


def main():
    parser = argparse.ArgumentParser(description="Material Design 图标批量导出至 res/drawable 工具")
    parser.add_argument("--scan-dir", default="app/src/main/java", help="扫描源码目录以自动提取用到的图标")
    parser.add_argument("--output-dir", default="app/src/main/res/drawable", help="VectorDrawable XML 输出目录")
    parser.add_argument("--icons", nargs="*", default=None, help="手动指定需要导出的图标名称（如 Dns Lan Rule）")
    parser.add_argument("--style", default="filled", help="指定图标风格（默认: filled）")
    parser.add_argument("--prefix", default="ic_", help="生成 drawable 文件的前缀（默认: ic_）")
    parser.add_argument("--jar", default=None, help="自定义 material-icons sources.jar 文件路径")
    parser.add_argument("--version", default="1.7.8", help="若本地缺少缓存时下载的 Compose 图标库版本（默认: 1.7.8）")
    parser.add_argument("--generate-kt-dir", default="app/src/main/java/com/haoze/dnssr/ui/icons", help="生成 Kotlin 兼容文件的输出目录")
    parser.add_argument("--skip-kt", action="store_true", help="跳过生成 Kotlin 兼容文件")
    parser.add_argument("--force", action="store_true", help="强制覆盖已存在的 XML 文件")
    parser.add_argument("--dry-run", action="store_true", help="仅预览要导出的图标，不实际写入文件")

    args = parser.parse_args()

    # 1. 查找或下载 sources.jar
    jar_paths = []
    if args.jar:
        if os.path.exists(args.jar):
            jar_paths.append(args.jar)
        else:
            print(f"指定的 jar 文件不存在: {args.jar}", file=sys.stderr)
            sys.exit(1)
    else:
        jar_paths = find_gradle_sources_jars()
        if not jar_paths:
            print("在本地 Gradle 缓存中未找到 material-icons sources.jar，尝试自动下载...")
            downloaded = download_sources_jar(args.version)
            jar_paths.append(downloaded)

    print(f"正在建立图标库索引 (共 {len(jar_paths)} 个源文件)...")
    jar_index = IconJarIndex(jar_paths)
    print(f"索引建立完毕，包含 {len(jar_index.entries)} 条索引项。")

    # 2. 收集需要导出的图标
    icons_to_export: Set[Tuple[str, str, str]] = set()

    if args.icons:
        for name in args.icons:
            icons_to_export.add(("", args.style.lower(), name))
    else:
        if os.path.exists(args.scan_dir):
            print(f"正在扫描源码目录 {args.scan_dir} ...")
            scanned = scan_project_icons(args.scan_dir)
            icons_to_export.update(scanned)
            print(f"扫描发现 {len(scanned)} 个图标引用。")
        else:
            print(f"扫描目录不存在: {args.scan_dir}", file=sys.stderr)
            sys.exit(1)

    if not icons_to_export:
        print("未发现任何需要导出的图标。")
        return

    print(f"\n准备导出 {len(icons_to_export)} 个图标到: {args.output_dir}\n" + "=" * 50)
    exported = export_icons(
        icons_to_export=icons_to_export,
        jar_index=jar_index,
        output_dir=args.output_dir,
        prefix=args.prefix,
        force=args.force,
        dry_run=args.dry_run
    )

    print("=" * 50)
    print(f"处理完成！成功导出/确认 {len(exported)} 个 XML 图标。")

    # 3. 生成 Kotlin 兼容文件
    if not args.skip_kt and not args.dry_run:
        print("\n正在生成 Kotlin Extended 图标兼容文件...")
        generate_kotlin_compat_files(icons_to_export, jar_index, args.generate_kt_dir)


if __name__ == "__main__":
    main()
