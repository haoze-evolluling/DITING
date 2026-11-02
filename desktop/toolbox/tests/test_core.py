#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""工具箱核心回归测试：路径、扫描、版本与任务调度。"""

import os
import sys
import tempfile
import threading
import time
import unittest

_DESKTOP_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _DESKTOP_DIR not in sys.path:
    sys.path.insert(0, _DESKTOP_DIR)

from toolbox.core import paths
from toolbox.core.file_scanner import run_scan_analysis
from toolbox.core.logo_generator import brand_svgs
from toolbox.core.runner import TaskRunner
from toolbox.core.version_manager import inspect_versions


class PathsTest(unittest.TestCase):
    def test_root_markers(self):
        for name in ("android", "desktop", "shared"):
            self.assertTrue(os.path.isdir(os.path.join(paths.ROOT_DIR, name)), name)
        self.assertTrue(os.path.isfile(paths.BRAND_XML))
        self.assertEqual(paths.resolve("desktop/app"), os.path.join(paths.ROOT_DIR, "desktop", "app"))
        self.assertEqual(paths.resolve(""), paths.ROOT_DIR)


class ScannerTest(unittest.TestCase):
    def test_ignores_generated_files_and_dirs(self):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "lib"))
            os.makedirs(os.path.join(root, ".dart_tool"))
            normal = os.path.join(root, "lib", "main.dart")
            generated = os.path.join(root, "lib", "app_localizations.dart")
            cached = os.path.join(root, ".dart_tool", "cached.dart")
            for path in (normal, generated, cached):
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write("line\n" * 5)

            result = run_scan_analysis(root_dir=root, extensions=".dart", threshold=1)
            rel_paths = {item["rel_path"] for item in result["matched_files"]}
            self.assertEqual(rel_paths, {"lib/main.dart"})
            self.assertEqual(result["stats"]["generated_skipped"], 1)
            self.assertEqual(result["max_file"]["rel_path"], "lib/main.dart")

            all_files = run_scan_analysis(
                root_dir=root,
                extensions=".dart",
                threshold=1,
                ignore_generated=False,
            )
            self.assertEqual(all_files["stats"]["generated_skipped"], 0)
            self.assertIn("lib/app_localizations.dart", {item["rel_path"] for item in all_files["matched_files"]})


class VersionTest(unittest.TestCase):
    def test_groups(self):
        flutter = inspect_versions(["flutter"])
        common = inspect_versions(["common"])
        self.assertEqual(len(flutter), 2)
        self.assertGreaterEqual(len(common), 4)
        self.assertTrue(all(item["exists"] for item in flutter + common))
        self.assertTrue(all(item["version"] != "未知" for item in flutter + common))


class LogoTest(unittest.TestCase):
    def test_brand_svgs(self):
        palettes = brand_svgs()
        self.assertEqual(set(palettes), {"light", "dark", "source"})
        for mode in ("light", "dark"):
            self.assertIn("<svg", palettes[mode]["svg"])
            self.assertTrue(palettes[mode]["background"].startswith("#"))


class RunnerTest(unittest.TestCase):
    def test_rejects_concurrent_task(self):
        runner = TaskRunner()
        release = threading.Event()
        done = threading.Event()

        def task(_log, _cancel):
            release.wait(2)
            return {"success": True, "data": "ok"}

        self.assertTrue(runner.run_async(task, lambda _l, _m: None, lambda _r: done.set()))
        self.assertFalse(runner.run_async(task, lambda _l, _m: None, lambda _r: None))
        release.set()
        self.assertTrue(done.wait(3))
        for _ in range(50):
            if not runner.is_running:
                break
            time.sleep(0.02)
        self.assertFalse(runner.is_running)


if __name__ == "__main__":
    unittest.main(verbosity=2)
