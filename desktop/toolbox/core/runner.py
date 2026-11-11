import os
import re
import subprocess
import sys
import threading
import time
from typing import Callable, Optional

ANSI_ESCAPE_RE = re.compile(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


def decode_bytes(data: bytes) -> str:
    """智能多编码容错解码，杜绝 Windows 控制台与各类 CLI 工具的中文乱码"""
    for enc in ("utf-8", "gb18030", "cp936", "latin1"):
        try:
            return data.decode(enc)
        except (UnicodeDecodeError, LookupError):
            continue
    return data.decode("utf-8", errors="replace")


def clean_output_line(raw: bytes) -> str:
    """清理换行符、回车覆盖与 ANSI 彩色控制字符"""
    decoded = decode_bytes(raw)
    no_ansi = ANSI_ESCAPE_RE.sub("", decoded).strip("\r\n")
    if "\r" in no_ansi:
        parts = [p.strip() for p in no_ansi.split("\r") if p.strip()]
        return parts[-1] if parts else ""
    return no_ansi


def _terminate_process(proc: subprocess.Popen) -> None:
    """terminate 后短暂等待，仍未退出则 kill，避免留下孤儿进程。"""
    if proc.poll() is not None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=3)
        return
    except Exception:
        pass
    try:
        proc.kill()
        proc.wait(timeout=3)
    except Exception:
        pass


def stream_process_output(
    cmd: list,
    cwd: str,
    on_log: Callable[[str, str], None],
    is_cancelled: Optional[Callable[[], bool]] = None,
    env: Optional[dict] = None,
    on_proc_started: Optional[Callable[[subprocess.Popen], None]] = None,
) -> int:
    """通用的子进程流式输出执行器，按行实时回调输出并支持取消"""
    if not is_cancelled:
        is_cancelled = lambda: False

    run_env = os.environ.copy()
    if env:
        run_env.update(env)

    # 确保统一的 UTF-8 输入输出环境
    run_env["PYTHONIOENCODING"] = "utf-8"
    run_env["PYTHONUTF8"] = "1"

    creationflags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
    proc: Optional[subprocess.Popen] = None
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=run_env,
            creationflags=creationflags,
        )
        if on_proc_started:
            on_proc_started(proc)

        for line_bytes in iter(proc.stdout.readline, b""):
            if is_cancelled():
                _terminate_process(proc)
                on_log("warn", "[已终止] 用户主动取消了任务。")
                return -1
            clean_line = clean_output_line(line_bytes)
            if clean_line:
                on_log("info", clean_line)

        return proc.wait()
    except Exception as e:
        if proc is not None:
            _terminate_process(proc)
        on_log("error", f"命令启动失败: {e}")
        return -1
    finally:
        if proc is not None and proc.stdout is not None:
            try:
                proc.stdout.close()
            except Exception:
                pass


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
        with self._lock:
            return self._is_running

    def cancel(self):
        """取消当前正在运行的任务"""
        with self._lock:
            self._cancel_requested = True
            current = self._current_process
        if current and current.poll() is None:
            _terminate_process(current)

    def run_async(
        self,
        task_func: Callable[[Callable[[str, str], None], Callable[[], bool]], dict],
        on_log: Callable[[str, str], None],
        on_complete: Callable[[dict], None],
    ) -> bool:
        """在后台线程中启动任务；已有任务运行时返回 False，不排队。"""
        with self._lock:
            busy = self._is_running
            if not busy:
                self._is_running = True
                self._cancel_requested = False
        if busy:
            on_log("warn", "当前已有任务正在执行中，请等待其完成或先终止。")
            return False

        def _worker():
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
                with self._lock:
                    self._is_running = False
                    self._current_process = None
                if on_complete:
                    try:
                        on_complete(result)
                    except Exception as e:
                        on_log("error", f"任务完成回调异常: {e}")

        thread = threading.Thread(target=_worker, daemon=True)
        try:
            thread.start()
        except Exception as e:
            with self._lock:
                self._is_running = False
            on_log("error", f"无法启动后台任务: {e}")
            return False

        self._active_thread = thread
        return True

    def run_command_stream(
        self,
        cmd: list,
        cwd: str,
        on_log: Callable[[str, str], None],
        is_cancelled: Callable[[], bool],
        env: Optional[dict] = None,
    ) -> int:
        """流式执行子进程并逐行回调输出"""

        def _on_started(proc):
            with self._lock:
                self._current_process = proc

        try:
            return stream_process_output(
                cmd=cmd,
                cwd=cwd,
                on_log=on_log,
                is_cancelled=is_cancelled,
                env=env,
                on_proc_started=_on_started,
            )
        finally:
            with self._lock:
                self._current_process = None
