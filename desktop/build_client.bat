@echo off
setlocal
title DITING Desktop Client Build

:: Build the Tauri desktop client from desktop\ui.
::
:: Usage:
::   build_client.bat              release build + platform installers
::   build_client.bat --debug      debug build without bundling
::
:: Requirements:
::   - Node.js 20+ and npm on PATH
::   - Rust (cargo) on PATH with the MSVC toolchain
::   - Windows 11 (WebView2 built in) or installed WebView2 Runtime
::
:: The client connects to an installed/running diting-service over loopback.
:: Build the service installer separately with build_installer.bat.

pushd "%~dp0ui"

where npm >nul 2>&1
if errorlevel 1 goto ERR_NO_NPM

if not exist "node_modules" (
    echo [INFO] Installing desktop client dependencies...
    call npm ci
    if errorlevel 1 goto ERR_INSTALL
)

if /i "%~1"=="--debug" (
    call npm run tauri -- build --debug --no-bundle
) else (
    call npm run tauri:build
)
if errorlevel 1 goto ERR_BUILD

echo.
echo [SUCCESS] Desktop client build finished.
echo [INFO] Tauri artifacts are under desktop\ui\src-tauri\target.
goto FINISH

:ERR_NO_NPM
echo [ERROR] 'npm' was not found on PATH. Install Node.js 20+ and retry.
goto FAIL
:ERR_INSTALL
echo [ERROR] Failed to install desktop client dependencies.
goto FAIL
:ERR_BUILD
echo [ERROR] Desktop client build failed. Check the messages above.
goto FAIL

:FAIL
popd
echo.
echo [INFO] Press any key to exit...
pause >nul
exit /b 1

:FINISH
popd
echo.
pause
exit /b 0
