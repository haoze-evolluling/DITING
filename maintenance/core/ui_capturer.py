#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 界面截图自动化生成引擎
支持深浅色双主题、多标签页与自定义分辨率截图导出。
"""

import argparse
import os
import shutil
import socket
import subprocess
import sys
import time
from typing import Callable, List, Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


def get_root_dir() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def find_edge_path() -> Optional[str]:
    candidates = [
        "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
        "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
        os.path.expanduser("~\\AppData\\Local\\Microsoft\\Edge\\Application\\msedge.exe"),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return shutil.which("msedge")


def is_port_in_use(port: int = 5173, host: str = "127.0.0.1") -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.5)
        return s.connect_ex((host, port)) == 0


def capture_screenshots(
    tab: str = "all",
    theme: str = "both",
    width: int = 1280,
    height: int = 720,
    output_dir: Optional[str] = None,
    on_log: Optional[Callable[[str, str], None]] = None,
    is_cancelled: Optional[Callable[[], bool]] = None,
) -> dict:
    def _log(lvl, msg):
        if on_log:
            on_log(lvl, msg)
        else:
            print(f"[{lvl.upper()}] {msg}")

    if not is_cancelled:
        is_cancelled = lambda: False

    root = get_root_dir()
    if not output_dir:
        output_dir = os.path.join(root, "screenshots")
    os.makedirs(output_dir, exist_ok=True)

    edge_exe = find_edge_path()
    if not edge_exe:
        _log("error", "未在系统中找到 Microsoft Edge 浏览器 (msedge.exe)，无法执行无头截图。")
        return {"success": False, "message": "未找到 Edge 浏览器"}

    port = 5173
    base_url = f"http://127.0.0.1:{port}"
    temp_vite_proc = None

    if not is_port_in_use(port):
        _log("warn", f"检测到 Vite 前端未在端口 {port} 运行，正在尝试启动临时前端服务...")
        frontend_dir = os.path.join(root, "Windows", "frontend")
        npx_cmd = shutil.which("npx.cmd") or shutil.which("npx") or "npx"
        try:
            temp_vite_proc = subprocess.Popen(
                [npx_cmd, "vite", "--host", "127.0.0.1", "--port", str(port)],
                cwd=frontend_dir,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                shell=(sys.platform == "win32"),
            )
            time.sleep(3)
        except Exception as e:
            _log("warn", f"启动临时 Vite 服务失败: {e}，请手动确保前端开发服务已运行。")

    # 五大类信息架构；多段类别用 "大类/子页签" 表示
    all_tabs = [
        "overview/status",
        "overview/queries",
        "network/adapters",
        "network/upstream",
        "network/lan",
        "accel",
        "rules/lists",
        "rules/custom",
        "rules/test",
        "rules/config",
        "system",
    ]
    target_tabs = all_tabs + ["modal-alert"] if tab == "all" else [tab]
    target_themes = ["dark", "light"] if theme == "both" else [theme]

    _log("info", f"开始自动化界面截图: 分辨率 {width}x{height}, 目标标签: {len(target_tabs)} 个")

    captured_files = []

    try:
        for t in target_themes:
            for item in target_tabs:
                if is_cancelled():
                    _log("warn", "截图任务已被用户中止。")
                    break

                slug = item.replace("/", "-")
                file_name = f"{t}_modal_alert.png" if item == "modal-alert" else f"{t}_tab_{slug}.png"
                out_path = os.path.join(output_dir, file_name)
                if item == "modal-alert":
                    target_url = f"{base_url}/?modal=alert&theme={t}"
                elif "/" in item:
                    tab_id, sub_id = item.split("/", 1)
                    target_url = f"{base_url}/?noalert=1&theme={t}#/{tab_id}/{sub_id}"
                else:
                    target_url = f"{base_url}/?noalert=1&theme={t}#/{item}"

                _log("info", f"截取界面 [{t}] -> {item}...")

                args_list = [
                    edge_exe,
                    "--headless",
                    "--disable-gpu",
                    f"--screenshot={out_path}",
                    f"--window-size={width},{height}",
                    target_url,
                ]

                subprocess.run(args_list, capture_output=True, timeout=30)

                if os.path.exists(out_path):
                    sz_kb = round(os.path.getsize(out_path) / 1024, 1)
                    _log("info", f"[OK] 生成截图: {file_name} ({sz_kb} KB)")
                    captured_files.append({
                        "name": file_name,
                        "path": out_path,
                        "tab": item,
                        "theme": t,
                        "size_kb": sz_kb,
                    })
                else:
                    _log("warn", f"截图未生成: {file_name}")
    finally:
        if temp_vite_proc:
            try:
                temp_vite_proc.terminate()
            except Exception:
                pass

    _log("info", f"截图任务完成，共生成 {len(captured_files)} 张截图，保存在: {output_dir}")
    return {
        "success": True,
        "output_dir": output_dir,
        "files": captured_files,
    }


def main():
    parser = argparse.ArgumentParser(description="谛听自动化界面截图工具")
    parser.add_argument("-t", "--tab", choices=["all", "overview/status", "overview/queries", "network/adapters", "network/upstream", "network/lan", "accel", "rules/lists", "rules/custom", "rules/test", "rules/config", "system", "modal-alert"], default="all")
    parser.add_argument("-m", "--theme", choices=["both", "dark", "light"], default="both")
    parser.add_argument("-o", "--output", default=None)
    parser.add_argument("-W", "--width", type=int, default=1280)
    parser.add_argument("-H", "--height", type=int, default=720)
    args = parser.parse_args()

    res = capture_screenshots(tab=args.tab, theme=args.theme, width=args.width, height=args.height, output_dir=args.output)
    sys.exit(0 if res["success"] else 1)


if __name__ == "__main__":
    main()
