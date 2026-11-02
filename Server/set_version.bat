@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
python "%~dp0..\maintenance\core\version_manager.py" %*
if "%~1"=="" (
    if errorlevel 1 pause
)
