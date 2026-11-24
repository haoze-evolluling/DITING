@echo off
setlocal
title DITING IPK Build

:: Build the DITING OpenWrt .ipk package (musl static), assembled through WSL
:: when run on Windows.
::
:: Usage:
::   build_ipk.bat                    Release .ipk for amd64 (x86_64) (default)
::   build_ipk.bat -a arm64
::   build_ipk.bat -a both
::   build_ipk.bat -v 1.4.4 --clean
::   build_ipk.bat --skip-ui
::
:: All arguments are forwarded to desktop\toolbox\core\build_manager.py with
:: target "ipk". The pipeline runs:
::   desktop/ui (Vite/React) -> diting-service (Rust, musl static) -> .ipk package.
:: Only the final packages are kept, in desktop\service\build\bin.
::
:: Requirements:
::   - Python 3.10+ on PATH
::   - Node.js 20+ and npm on PATH (skip with --skip-ui)
::   - WSL when this runs on Windows; the Rust service is compiled inside WSL,
::     so WSL needs rustup and the musl target installed as well
::
:: This script only builds; it never installs anything.

pushd "%~dp0"

if not exist "..\rust\diting-desktop-service\Cargo.toml" goto ERR_NO_SERVICE
if not exist "toolbox\core\build_manager.py" goto ERR_NO_ENGINE

where python >nul 2>&1
if errorlevel 1 goto ERR_NO_PYTHON

:: OpenWrt .ipk is assembled inside WSL when run on Windows.
if /i not "%OS%"=="Windows_NT" goto PREFLIGHT_OK
where wsl >nul 2>&1
if errorlevel 1 goto ERR_NO_WSL

:PREFLIGHT_OK
echo ================================================================
echo   DITING IPK Build
echo   args: %*
echo ================================================================
echo.

call python "toolbox\core\build_manager.py" %* -t ipk
if errorlevel 1 goto ERR_BUILD

echo.
echo [SUCCESS] OpenWrt IPK package build finished.
echo [INFO] Artifact: %CD%\service\build\bin
echo.
echo [INFO] The package is ready to ship; nothing was installed.
goto FINISH

:FINISH
popd
echo.
pause
exit /b 0

:ERR_NO_SERVICE
echo [ERROR] rust\diting-desktop-service\Cargo.toml not found.
echo         The package bundles diting-service, so the Rust service crate must exist.
goto FAIL
:ERR_NO_ENGINE
echo [ERROR] toolbox\core\build_manager.py not found.
goto FAIL
:ERR_NO_PYTHON
echo [ERROR] 'python' not found on PATH. Install Python 3.10+ and retry.
goto FAIL
:ERR_NO_WSL
echo [ERROR] WSL was not found, so the .ipk cannot be assembled.
echo         Install WSL (wsl --install) or build the ipk on Linux directly.
goto FAIL
:ERR_BUILD
echo [ERROR] The OpenWrt IPK package build failed. Check the messages above.
goto FAIL

:FAIL
popd
echo.
echo [INFO] Press any key to exit...
pause >nul
exit /b 1
