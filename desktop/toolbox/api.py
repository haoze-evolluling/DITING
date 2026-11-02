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
from typing import List, Optional

from toolbox.core import paths
from toolbox.core.build_manager import build_pipeline, check_toolchain, get_current_project_version
from toolbox.core.dns_engine import execute_benchmark, execute_dns_query
from toolbox.core.file_scanner import DEFAULT_EXTENSIONS, run_scan_analysis
from toolbox.core.logo_generator import brand_svgs, export_logo_assets
from toolbox.core.runner import TaskRunner
from toolbox.core.version_manager import inspect_versions, sync_version


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

    def _start_task(self, task_func, done_event: str):
        started = self.runner.run_async(task_func, self._log, lambda res: self._emit(done_event, res))
        if not started:
            return {"started": False, "message": "已有任务正在执行，请等待完成或先中断"}
        return {"started": True}

    def cancel_current_task(self) -> dict:
        self.runner.cancel()
        return {"success": True, "message": "已发送取消信号"}

    def open_explorer(self, target_path: str) -> dict:
        try:
            path = paths.resolve(target_path)
            if not os.path.exists(path):
                return {"success": False, "message": f"路径不存在: {path}"}

            if sys.platform == "win32":
                if os.path.isfile(path):
                    subprocess.Popen(["explorer.exe", f"/select,{path}"])
                else:
                    subprocess.Popen(["explorer.exe", path])
            elif sys.platform == "darwin":
                if os.path.isfile(path):
                    subprocess.Popen(["open", "-R", path])
                else:
                    subprocess.Popen(["open", path])
            else:
                target = os.path.dirname(path) if os.path.isfile(path) else path
                subprocess.Popen(["xdg-open", target])
            return {"success": True, "path": path}
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
                is_cancelled=is_cancelled,
            )
            if res.get("cancelled"):
                log_cb("warn", f"压测已取消，完成 {res['completed']}/{res['count']} 次")
                return {"success": False, "message": res.get("message", "已取消"), "data": res}
            log_cb(
                "info",
                f"压测完成: 响应 {res['success_count']}/{res['count']}, "
                f"平均耗时: {res['avg_ms']}ms, 丢包率: {res['loss_rate']}%",
            )
            return {"success": True, "data": res}

        return self._start_task(_task, "dns_benchmark_done")

    # === 2. 代码扫描模块 ===
    def scan_files(
        self,
        root_dir: str,
        extensions: str,
        threshold: int,
        show_all: bool,
        sort_by: str = "lines",
        ignore_generated: bool = True,
    ):
        def _task(log_cb, is_cancelled):
            ext_display = extensions or DEFAULT_EXTENSIONS
            log_cb(
                "info",
                f"开始递归扫描源文件: 目录={root_dir or '项目根目录'}, 扩展名={ext_display}, "
                f"阈值={threshold}, 忽略生成文件={bool(ignore_generated)}",
            )
            res = run_scan_analysis(
                root_dir=root_dir,
                extensions=ext_display,
                threshold=int(threshold),
                show_all=bool(show_all),
                sort_by=sort_by,
                ignore_generated=bool(ignore_generated),
            )
            skipped = res.get("stats", {}).get("generated_skipped", 0)
            log_cb(
                "info",
                f"扫描完毕: 发现 {res['exceeded_count']} 个超标文件，共 {res['stats']['total_scanned']} 个源文件"
                + (f"，已忽略 {skipped} 个生成文件。" if skipped else "。"),
            )
            return {"success": True, "data": res}

        return self._start_task(_task, "scan_done")

    # === 3. Logo 渲染模块 ===
    def logo_preview(self) -> dict:
        try:
            return {"success": True, "palettes": brand_svgs()}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def logo_export(self):
        def _task(log_cb, is_cancelled):
            log_cb("info", "开始导出品牌 Logo 各规格高精度图像与 ICO 资源...")
            res = export_logo_assets(on_log=log_cb)
            log_cb("info", f"导出完成，已生成 {len(res['files'])} 个目标文件。")
            return {"success": True, "data": res}

        return self._start_task(_task, "logo_export_done")

    # === 4. 构建打包模块 ===
    def build_get_toolchain(self, force: bool = False) -> dict:
        return {
            "tools": check_toolchain(force=bool(force)),
            "default_version": get_current_project_version(),
        }

    def build_get_default_version(self) -> str:
        return get_current_project_version()

    def build_start(self, target: str, version: str, build_type: str, clean: bool, skip_check: bool, arch: str = "amd64"):
        def _task(log_cb, is_cancelled):
            return build_pipeline(
                target=target,
                version=version,
                build_type=build_type,
                clean=clean,
                skip_check=skip_check,
                on_log=log_cb,
                is_cancelled=is_cancelled,
                arch=arch,
            )

        return self._start_task(_task, "build_done")

    # === 5. 版本管理模块 ===
    def version_inspect(self, groups: Optional[List[str]] = None) -> dict:
        try:
            return {"success": True, "items": inspect_versions(groups)}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def version_sync(self, target_version: str, dry_run: bool, verify: bool, commit: bool, groups: Optional[List[str]] = None):
        def _task(log_cb, is_cancelled):
            return sync_version(
                target_version=target_version,
                dry_run=dry_run,
                verify=verify,
                commit=commit,
                on_log=log_cb,
                groups=groups,
            )

        return self._start_task(_task, "version_sync_done")
