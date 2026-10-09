#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 开发者工具箱 PyWebView API 桥接层
负责将前端 JS 请求映射到后台 Python 服务，并向前端分发实时日志与进度。
"""

import json
import os
import subprocess
import sys
from typing import Optional

from maintenance.core.build_manager import build_pipeline, check_toolchain
from maintenance.core.dns_engine import (
    execute_benchmark,
    execute_dns_query,
    execute_phase1_verification,
)
from maintenance.core.file_scanner import run_scan_analysis
from maintenance.core.logo_generator import export_logo_assets, generate_squircle_svg
from maintenance.core.runner import TaskRunner
from maintenance.core.ui_capturer import capture_screenshots
from maintenance.core.version_manager import inspect_versions, sync_version


class ApiBridge:
    def __init__(self):
        self._window = None
        self.runner = TaskRunner()

    def set_window(self, window):
        self._window = window

    def _emit(self, event_type: str, data: dict):
        if not self._window:
            return
        payload = json.dumps({"type": event_type, "data": data}, ensure_ascii=False)
        try:
            self._window.evaluate_js(f"window.onBackendEvent({payload});")
        except Exception:
            pass

    def _log(self, level: str, message: str):
        self._emit("log", {"level": level, "message": message})

    def cancel_current_task(self) -> dict:
        self.runner.cancel()
        return {"success": True, "message": "已发送取消信号"}

    def open_explorer(self, target_path: str) -> dict:
        try:
            abs_p = os.path.abspath(target_path)
            if os.path.isfile(abs_p):
                subprocess.Popen(["explorer.exe", f"/select,{abs_p}"])
            elif os.path.isdir(abs_p):
                subprocess.Popen(["explorer.exe", abs_p])
            else:
                return {"success": False, "message": "路径不存在"}
            return {"success": True}
        except Exception as e:
            return {"success": False, "message": str(e)}

    # === 1. DNS 模块 ===
    def dns_query(self, domain: str, server: str, port: int, qtype: str, use_tcp: bool, timeout: float = 3.0) -> dict:
        return execute_dns_query(domain, server, int(port), qtype, bool(use_tcp), float(timeout))

    def dns_benchmark(self, domain: str, server: str, port: int, qtype: str, count: int, use_tcp: bool):
        def _task(log_cb, is_cancelled):
            log_cb("info", f"开始执行 DNS 批量压测: {domain} ({qtype}) -> {server}:{port}, 次数: {count}")
            res = execute_benchmark(
                server=server,
                port=int(port),
                domain=domain,
                qtype_str=qtype,
                count=int(count),
                use_tcp=bool(use_tcp),
                on_progress=lambda msg: log_cb("info", msg),
            )
            log_cb("info", f"压测完成: 成功 {res['success_count']}/{res['count']}, 平均耗时: {res['avg_ms']}ms, 丢包率: {res['loss_rate']}%")
            return {"success": True, "data": res}

        self.runner.run_async(_task, self._log, lambda res: self._emit("dns_benchmark_done", res))
        return {"started": True}

    def dns_verify_phase1(self, server: str, port: int):
        def _task(log_cb, is_cancelled):
            log_cb("info", f"启动阶段 1 核心 DNS 自动化验证套件: {server}:{port}")
            res = execute_phase1_verification(server=server, port=int(port), on_log=log_cb)
            return {"success": True, "data": res}

        self.runner.run_async(_task, self._log, lambda res: self._emit("dns_verify_done", res))
        return {"started": True}

    # === 2. 代码扫描模块 ===
    def scan_files(self, root_dir: str, extensions: str, threshold: int, show_all: bool, sort_by: str = "lines"):
        def _task(log_cb, is_cancelled):
            log_cb("info", f"开始递归扫描源文件: 目录={root_dir or '项目根目录'}, 扩展名={extensions}, 阈值={threshold}")
            res = run_scan_analysis(root_dir=root_dir, extensions=extensions, threshold=int(threshold), show_all=bool(show_all), sort_by=sort_by)
            log_cb("info", f"扫描完毕: 发现 {res['exceeded_count']} 个超标文件，共 {res['stats']['total_scanned']} 个源文件。")
            return {"success": True, "data": res}

        self.runner.run_async(_task, self._log, lambda res: self._emit("scan_done", res))
        return {"started": True}

    # === 3. Logo 渲染模块 ===
    def logo_preview(self, bg_color: str, totem_color: str, gradient: bool) -> dict:
        try:
            svg = generate_squircle_svg(bg_color=bg_color, totem_color=totem_color, subtle_gradient=gradient)
            return {"success": True, "svg": svg}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def logo_export(self, bg_color: str, totem_color: str, gradient: bool, output_dir: Optional[str] = None):
        def _task(log_cb, is_cancelled):
            log_cb("info", "开始导出品牌 Logo 各规格高精度图像与 ICO 资源...")
            res = export_logo_assets(bg_color=bg_color, totem_color=totem_color, subtle_gradient=gradient, output_dir=output_dir, on_log=log_cb)
            log_cb("info", f"导出完成，已生成 {len(res['files'])} 个目标文件。")
            return {"success": True, "data": res}

        self.runner.run_async(_task, self._log, lambda res: self._emit("logo_export_done", res))
        return {"started": True}

    # === 4. 构建打包模块 ===
    def build_get_toolchain(self) -> dict:
        return check_toolchain()

    def build_start(self, target: str, version: str, build_type: str, clean: bool, skip_check: bool):
        def _task(log_cb, is_cancelled):
            res = build_pipeline(target=target, version=version, build_type=build_type, clean=clean, skip_check=skip_check, on_log=log_cb, is_cancelled=is_cancelled)
            return res

        self.runner.run_async(_task, self._log, lambda res: self._emit("build_done", res))
        return {"started": True}

    # === 5. 版本管理模块 ===
    def version_inspect(self) -> dict:
        try:
            items = inspect_versions()
            return {"success": True, "items": items}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def version_sync(self, target_version: str, dry_run: bool, verify: bool, commit: bool):
        def _task(log_cb, is_cancelled):
            res = sync_version(target_version=target_version, dry_run=dry_run, verify=verify, commit=commit, on_log=log_cb)
            return res

        self.runner.run_async(_task, self._log, lambda res: self._emit("version_sync_done", res))
        return {"started": True}

    # === 6. 界面截图模块 ===
    def capture_start(self, tab: str, theme: str, width: int, height: int, output_dir: Optional[str] = None):
        def _task(log_cb, is_cancelled):
            res = capture_screenshots(tab=tab, theme=theme, width=int(width), height=int(height), output_dir=output_dir, on_log=log_cb, is_cancelled=is_cancelled)
            return res

        self.runner.run_async(_task, self._log, lambda res: self._emit("capture_done", res))
        return {"started": True}
