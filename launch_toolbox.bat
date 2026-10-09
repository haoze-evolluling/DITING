@echo off
setlocal
cd /d "%~dp0"
python maintenance\app.py %*
