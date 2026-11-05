#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""工具箱核心回归测试：路径、扫描、版本与任务调度。"""

import os
import sys
import tempfile
import threading
import time
import unittest
import unittest.mock

_DESKTOP_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _DESKTOP_DIR not in sys.path:
    sys.path.insert(0, _DESKTOP_DIR)

from toolbox.core import paths
from toolbox.core.file_scanner import run_scan_analysis
from toolbox.core.logo_generator import brand_svgs
from toolbox.core.runner import TaskRunner
from toolbox.core import version_manager
from toolbox.core.version_manager import get_current_version, inspect_versions


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
    def test_single_source_of_truth(self):
        desktop = inspect_versions(["desktop"])
        sources = [item for item in desktop if item["kind"] == "source"]
        derived = [item for item in desktop if item["kind"] == "derived"]
        self.assertEqual(len(sources), 1, "桌面端只应有一份版本字面量")
        self.assertIn("desktop/app/pubspec.yaml", sources[0]["rel_path"])
        self.assertGreaterEqual(len(derived), 3, "服务端 / NSIS / deb 都应列为派生位置")
        self.assertTrue(all(item["exists"] for item in desktop))
        self.assertEqual(get_current_version(), sources[0]["version"])

    def test_derived_places_hold_no_literal(self):
        drifts = version_manager.drift_report(["desktop"])
        self.assertEqual(drifts, [], f"这些位置又写回了版本字面量，应改为构建期注入: {drifts}")

    def test_android_stays_independent(self):
        android = inspect_versions(["android"])
        self.assertEqual(len(android), 1)
        self.assertEqual(android[0]["kind"], "source")
        self.assertEqual(get_current_version(["android"]), android[0]["version"])

    def test_build_number_is_monotonic(self):
        self.assertEqual(version_manager.build_number("2.2.11"), 20211)
        content = "name: x\nversion: 2.2.11+20211\n"
        new_content, changed = version_manager.pubspec_with_version(content, "2.2.10")
        self.assertTrue(changed)
        self.assertIn("version: 2.2.10+20211", new_content, "构建号只增不减")

    def test_dry_run_writes_nothing(self):
        with tempfile.TemporaryDirectory() as root:
            pubspec = os.path.join(root, "pubspec.yaml")
            with open(pubspec, "w", encoding="utf-8") as handle:
                handle.write("name: x\nversion: 2.2.11+20211\n")
            with unittest.mock.patch.object(version_manager, "DESKTOP_PUBSPEC", pubspec), \
                    unittest.mock.patch.object(version_manager, "derived_targets", lambda: []):
                preview = version_manager.sync_version("2.3.0", dry_run=True, groups=["desktop"])
                self.assertTrue(preview["success"])
                self.assertEqual(len(preview["modified_files"]), 1)
                with open(pubspec, encoding="utf-8") as handle:
                    self.assertIn("version: 2.2.11", handle.read(), "dry-run 不得修改文件")

                applied = version_manager.sync_version("2.3.0", groups=["desktop"])
                self.assertTrue(applied["success"])
                with open(pubspec, encoding="utf-8") as handle:
                    self.assertIn("version: 2.3.0+20300", handle.read())


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
