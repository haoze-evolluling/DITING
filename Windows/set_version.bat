@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\set-version.ps1" %*
if "%~1"=="" (
    if errorlevel 1 pause
)
