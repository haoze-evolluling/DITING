@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0\..\.."

where python >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 python 命令，请先安装 Python 3.8+ 并加入 PATH。
    pause
    exit /b 1
)

python -c "import webview, PIL" >nul 2>nul
if errorlevel 1 (
    echo [提示] 检测到维护工具箱依赖缺失，正在安装...
    python -m pip install -r "%~dp0requirements.txt"
    if errorlevel 1 (
        echo.
        echo [错误] 依赖安装失败，请检查网络后重试，或手动执行：
        echo   python -m pip install -r "%~dp0requirements.txt"
        pause
        exit /b 1
    )
)

python "%~dp0app.py" %*
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" (
    echo.
    echo [错误] 维护工具箱异常退出，错误码: %EXIT_CODE%
    pause
)
exit /b %EXIT_CODE%
