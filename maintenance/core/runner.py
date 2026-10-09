import os
import queue
import subprocess
import threading
import time
from typing import Callable, Optional


class TaskRunner:
    """统一异步任务调度与实时日志分发器"""

    def __init__(self):
        self._lock = threading.Lock()
        self._current_process: Optional[subprocess.Popen] = None
        self._is_running = False
        self._cancel_requested = False
        self._active_thread: Optional[threading.Thread] = None

    @property
    def is_running(self) -> bool:
        return self._is_running

    def cancel(self):
        """取消当前正在运行的任务"""
        with self._lock:
            self._cancel_requested = True
            if self._current_process and self._current_process.poll() is None:
                try:
                    self._current_process.terminate()
                except Exception:
                    pass

    def run_async(
        self,
        task_func: Callable[[Callable[[str, str], None], Callable[[], bool]], dict],
        on_log: Callable[[str, str], None],
        on_complete: Callable[[dict], None],
    ):
        """在后台线程中启动任务

        :param task_func: 接收 log_callback(level, text) 和 is_cancelled() 的执行函数
        :param on_log: 前端日志回调函数
        :param on_complete: 完成后的结果回调函数
        """
        if self._is_running:
            on_log("warn", "当前已有任务正在执行中，请等待其完成或先终止。")
            return

        def _worker():
            self._is_running = True
            self._cancel_requested = False
            start_time = time.time()
            result = {"success": False, "message": "", "data": None}
            try:
                result = task_func(on_log, lambda: self._cancel_requested)
            except Exception as e:
                on_log("error", f"任务执行发生未捕获异常: {e}")
                result = {"success": False, "message": str(e), "data": None}
            finally:
                elapsed = time.time() - start_time
                result["elapsed"] = round(elapsed, 2)
                self._is_running = False
                self._current_process = None
                if on_complete:
                    on_complete(result)

        self._active_thread = threading.Thread(target=_worker, daemon=True)
        self._active_thread.start()

    def run_command_stream(
        self,
        cmd: list,
        cwd: str,
        on_log: Callable[[str, str], None],
        is_cancelled: Callable[[], bool],
        env: Optional[dict] = None,
    ) -> int:
        """流式执行子进程并逐行回调输出"""
        run_env = os.environ.copy()
        if env:
            run_env.update(env)

        # 确保 UTF-8 编码
        run_env["PYTHONIOENCODING"] = "utf-8"
        run_env["PYTHONUTF8"] = "1"

        try:
            proc = subprocess.Popen(
                cmd,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                env=run_env,
                bufsize=1,
            )
            with self._lock:
                self._current_process = proc

            for line in iter(proc.stdout.readline, ""):
                if is_cancelled():
                    try:
                        proc.terminate()
                    except Exception:
                        pass
                    on_log("warn", "[已终止] 用户主动取消了任务。")
                    return -1
                clean_line = line.rstrip("\r\n")
                if clean_line:
                    on_log("info", clean_line)

            proc.stdout.close()
            return_code = proc.wait()
            return return_code
        except Exception as e:
            on_log("error", f"命令启动失败: {e}")
            return -1
        finally:
            with self._lock:
                self._current_process = None
