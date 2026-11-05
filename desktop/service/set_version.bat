@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
:: 版本号唯一真源是 desktop\app\pubspec.yaml，其余位置由构建脚本自动派生。
python "%~dp0..\toolbox\core\version_manager.py" %*
if "%~1"=="" (
    if errorlevel 1 pause
)
