@echo off
setlocal
cd /d "%~dp0"
python "%~dp0..\maintenance\core\build_manager.py" %*

