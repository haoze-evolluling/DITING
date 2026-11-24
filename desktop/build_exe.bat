@echo off
setlocal
title DITING EXE Build

:: Build the DITING Windows EXE installer (NSIS).
::
:: Usage:
::   build_exe.bat                    Release EXE installer (default)
::   build_exe.bat -v 1.4.4 --clean
::   build_exe.bat -b debug
::   build_exe.bat --skip-ui
::
:: All arguments are forwarded to desktop\toolbox\core\build_manager.py with
:: target "exe". The pipeline runs:
::   desktop/ui (Vite/React) -> diting-service.exe (Rust) -> NSIS installer.
:: Only the final installer is kept, in desktop\service\build\bin.
::
:: Requirements:
::   - Python 3.10+ on PATH
::   - Node.js 20+ and npm on PATH (desktop/ui build; skip with --skip-ui)
::   - Rust (cargo) on PATH: diting-service is compiled from rust/diting-desktop-service
::   - MSVC C++ build tools for the default Rust MSVC toolchain
::   - NSIS (makensis) for the EXE target
::
:: This script only builds; it never installs or launches anything. To run the
:: desktop service from source instead, use:
::   cd rust && cargo run -p diting-desktop-service -- -run
::
:: Intentionally pure ASCII: cmd.exe parses batch files in the OEM code page.
:: Chinese notes live in README.md.

pushd "%~dp0"

if not exist "..\rust\diting-desktop-service\Cargo.toml" goto ERR_NO_SERVICE
if not exist "toolbox\core\build_manager.py" goto ERR_NO_ENGINE

where python >nul 2>&1
if errorlevel 1 goto ERR_NO_PYTHON

where cargo >nul 2>&1
if errorlevel 1 goto ERR_NO_CARGO

:: Rust's default Windows toolchain links with MSVC, which ships with Visual
:: Studio (not just the Build Tools installer shell). vswhere is the supported probe.
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "HAS_MSVC="
if exist "%VSWHERE%" (
    for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set "HAS_MSVC=%%I"
)
if not defined HAS_MSVC if defined VSINSTALLDIR set "HAS_MSVC=%VSINSTALLDIR%"
if not defined HAS_MSVC goto ERR_NO_MSVC

:: NSIS is installed outside PATH by default, so probe the standard locations
:: here as a preflight; build_manager.py resolves makensis again on its own.
set "MAKENSIS="
for /f "delims=" %%I in ('where makensis 2^>nul') do if not defined MAKENSIS set "MAKENSIS=%%I"
if not defined MAKENSIS if exist "%ProgramFiles(x86)%\NSIS\makensis.exe" set "MAKENSIS=%ProgramFiles(x86)%\NSIS\makensis.exe"
if not defined MAKENSIS if exist "%ProgramFiles%\NSIS\makensis.exe" set "MAKENSIS=%ProgramFiles%\NSIS\makensis.exe"
if not defined MAKENSIS goto ERR_NO_NSIS

echo ================================================================
echo   DITING EXE Build
echo   args: %*
echo ================================================================
echo.

call python "toolbox\core\build_manager.py" %* -t exe
if errorlevel 1 goto ERR_BUILD

echo.
echo [SUCCESS] EXE installer build finished.
echo [INFO] Artifact: %CD%\service\build\bin
echo.
echo [INFO] The installer is ready to ship; nothing was installed or launched.
goto FINISH

:FINISH
popd
echo.
pause
exit /b 0

:ERR_NO_SERVICE
echo [ERROR] rust\diting-desktop-service\Cargo.toml not found.
echo         The installer bundles diting-service, so the Rust service crate must exist.
goto FAIL
:ERR_NO_ENGINE
echo [ERROR] toolbox\core\build_manager.py not found.
goto FAIL
:ERR_NO_PYTHON
echo [ERROR] 'python' not found on PATH. Install Python 3.10+ and retry.
goto FAIL
:ERR_NO_CARGO
echo [ERROR] 'cargo' not found on PATH.
echo         diting-service is a pure Rust binary (rust/diting-desktop-service).
echo         Install the Rust toolchain from https://rustup.rs and retry.
goto FAIL
:ERR_NO_MSVC
echo [ERROR] Visual Studio with "Desktop development with C++" was not found.
echo         Rust's default toolchain needs the MSVC linker.
echo         Install it from https://visualstudio.microsoft.com/downloads/
echo         and select that workload, then retry.
goto FAIL
:ERR_NO_NSIS
echo [ERROR] makensis (NSIS) was not found.
echo         Install it from https://nsis.sourceforge.io/Download
echo         (default path: C:\Program Files (x86)\NSIS), then retry.
goto FAIL
:ERR_BUILD
echo [ERROR] The EXE installer build failed. Check the messages above.
goto FAIL

:FAIL
popd
echo.
echo [INFO] Press any key to exit...
pause >nul
exit /b 1
