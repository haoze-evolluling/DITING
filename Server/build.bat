@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
python "%~dp0..\maintenance\core\build_manager.py" %*

