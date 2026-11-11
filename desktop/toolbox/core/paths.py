#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""谛听 (DITING) 项目路径单一真源。

工具箱的每个模块都从仓库根推导路径。历史上的实现散落在各文件里，仓库目录
（android/desktop/shared）调整后容易漂移，因此统一收敛到本模块。
"""

import os
from typing import Optional

_CORE_DIR = os.path.dirname(os.path.abspath(__file__))
TOOLBOX_DIR = os.path.dirname(_CORE_DIR)
DESKTOP_DIR = os.path.dirname(TOOLBOX_DIR)


def _detect_root(start: str) -> str:
    """向上查找同时包含 android/desktop/shared 的仓库根。"""
    current = os.path.abspath(start)
    while True:
        if all(os.path.isdir(os.path.join(current, name)) for name in ("android", "desktop", "shared")):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return os.path.dirname(DESKTOP_DIR)
        current = parent


ROOT_DIR = _detect_root(DESKTOP_DIR)

SERVICE_DIR = os.path.join(DESKTOP_DIR, "service")
DESKTOP_APP_DIR = os.path.join(DESKTOP_DIR, "app")
ANDROID_APP_DIR = os.path.join(ROOT_DIR, "android", "app")
SHARED_DIR = os.path.join(ROOT_DIR, "shared")

WEB_DIR = os.path.join(TOOLBOX_DIR, "web")
BRAND_DIR = os.path.join(TOOLBOX_DIR, "assets", "brand")
BRAND_XML = os.path.join(BRAND_DIR, "ic_splash_squircle_logo.xml")

BUILD_BIN_DIR = os.path.join(SERVICE_DIR, "build", "bin")
INSTALLER_DIR = os.path.join(SERVICE_DIR, "build", "windows", "installer")
FRONTEND_DIST_DIR = os.path.join(SERVICE_DIR, "frontend", "dist")
ANDROID_RES_DIR = os.path.join(ANDROID_APP_DIR, "android", "app", "src", "main", "res")


def resolve(path: Optional[str]) -> str:
    """把用户输入解析为绝对路径；相对路径一律以仓库根为基准。"""
    if not path:
        return ROOT_DIR
    expanded = os.path.expanduser(str(path).strip())
    if not os.path.isabs(expanded):
        expanded = os.path.join(ROOT_DIR, expanded)
    return os.path.abspath(expanded)


def relative(path: str) -> str:
    """返回相对仓库根、使用正斜杠的展示路径。"""
    return os.path.relpath(os.path.abspath(path), ROOT_DIR).replace("\\", "/")
