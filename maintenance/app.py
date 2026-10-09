#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 开发者桌面交互式工具箱
基于 Python + PyWebView 构建，提供直观、统一的可视化桌面交互界面。
"""

import argparse
import os
import sys
import webview

# 添加根目录至 sys.path，保证 maintenance 模块正常被识别
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)

from maintenance.api import ApiBridge


def main():
    parser = argparse.ArgumentParser(description="谛听 (DITING) 开发者桌面工具箱")
    parser.add_argument("--debug", action="store_true", help="开启 Web 开发者调试控制台")
    parser.add_argument("-W", "--width", type=int, default=1180, help="窗口宽度 (默认 1180)")
    parser.add_argument("-H", "--height", type=int, default=780, help="窗口高度 (默认 780)")
    args = parser.parse_args()

    current_dir = os.path.dirname(os.path.abspath(__file__))
    web_dir = os.path.join(current_dir, "web")
    html_entry = os.path.join(web_dir, "index.html")

    if not os.path.exists(html_entry):
        print(f"错误: 未找到前端入口文件: {html_entry}", file=sys.stderr)
        sys.exit(1)

    api = ApiBridge()

    # 应用窗口图标（优先选择 Windows 构建图标）
    icon_path = os.path.join(ROOT_DIR, "Windows", "build", "windows", "icon.ico")
    if not os.path.exists(icon_path):
        icon_path = None

    window = webview.create_window(
        title="谛听 (DITING) 开发者工具箱",
        url=html_entry,
        js_api=api,
        width=args.width,
        height=args.height,
        min_size=(980, 640),
        text_select=True,
    )
    api.set_window(window)

    # 启动 PyWebView 事件循环 (在 Windows 上默认使用 WebView2 引擎)
    webview.start(debug=args.debug)


if __name__ == "__main__":
    main()
