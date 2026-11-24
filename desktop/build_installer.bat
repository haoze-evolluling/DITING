@echo off
setlocal
title DITING Installer Build

:: Build the DITING desktop service installers (Windows EXE / Linux .deb / OpenWrt .ipk).
::
:: Usage:
::   build_installer.bat                    Windows EXE installer (default)
::   build_installer.bat exe                same as above
::   build_installer.bat deb                Linux .deb, assembled through WSL
::   build_installer.bat ipk                OpenWrt .ipk (musl static), assembled through WSL
::   build_installer.bat both               EXE + .deb
::   build_installer.bat all                EXE + .deb + OpenWrt .ipk
::   build_installer.bat exe -v 1.4.4 --clean
::   build_installer.bat deb -a arm64
::   build_installer.bat ipk -a both
::
:: Any argument after the optional target is forwarded to
:: desktop\toolbox\core\build_manager.py, which runs the whole pipeline:
::   desktop/ui (Vite/React) -> diting-service.exe (Rust) -> NSIS installer.
:: Only the final installers are kept, in desktop\service\build\bin.
:: Pass --skip-ui to skip the embedded web UI build.
::
:: Requirements:
::   - Python 3.10+ on PATH
::   - Node.js 20+ and npm on PATH (desktop/ui build; skip with --skip-ui)
::   - Rust (cargo) on PATH: diting-service is compiled from rust/diting-desktop-service
::     (the deb target needs cargo inside WSL as well)
::   - MSVC C++ build tools for the default Rust MSVC toolchain
::   - NSIS (makensis) for the EXE target
::   - WSL for the deb target when this runs on Windows
::
:: This script only builds; it never installs or launches anything. To run the
:: desktop service from source instead, use:
::   cd rust && cargo run -p diting-desktop-service -- -run
::
:: Intentionally pure ASCII: cmd.exe parses batch files in the OEM code page.
:: Chinese notes live in README.md.

pushd "%~dp0"

set "TARGET=exe"
set "PASS="

:PARSE_ARGS
if "%~1"=="" goto ARGS_READY
if /i "%~1"=="exe" goto TAKE_TARGET
if /i "%~1"=="deb" goto TAKE_TARGET
if /i "%~1"=="ipk" goto TAKE_TARGET
if /i "%~1"=="both" goto TAKE_TARGET
if /i "%~1"=="all" goto TAKE_TARGET
if /i "%~1"=="installer" goto TAKE_TARGET
:: "-t deb" / "--target deb" select a target too, so the tool checks match
:: what build_manager.py will really build.
if /i "%~1"=="-t" goto TAKE_TARGET_FLAG
if /i "%~1"=="--target" goto TAKE_TARGET_FLAG
set "PASS=%PASS% %1"
shift
goto PARSE_ARGS

:TAKE_TARGET
set "TARGET=%~1"
shift
goto PARSE_ARGS

:TAKE_TARGET_FLAG
shift
if not "%~1"=="" set "TARGET=%~1"
shift
goto PARSE_ARGS

:ARGS_READY

if not exist "..\rust\diting-desktop-service\Cargo.toml" goto ERR_NO_SERVICE
if not exist "toolbox\core\build_manager.py" goto ERR_NO_ENGINE

where python >nul 2>&1
if errorlevel 1 goto ERR_NO_PYTHON

:: Normalise the target into the two flags that drive the tool checks.
set "NEED_WIN="
set "NEED_WSL="
if /i "%TARGET%"=="deb" goto TGT_WSL
if /i "%TARGET%"=="ipk" goto TGT_WSL
if /i "%TARGET%"=="both" goto TGT_BOTH
if /i "%TARGET%"=="all" goto TGT_BOTH
set "NEED_WIN=1"
goto TGT_DONE
:TGT_BOTH
set "NEED_WIN=1"
:TGT_WSL
set "NEED_WSL=1"
:TGT_DONE

if not defined NEED_WIN goto CHECK_WSL

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

:CHECK_WSL
if not defined NEED_WSL goto PREFLIGHT_OK
if /i not "%OS%"=="Windows_NT" goto PREFLIGHT_OK
:: Linux .deb and OpenWrt .ipk are assembled inside WSL when run on Windows.
where wsl >nul 2>&1
if errorlevel 1 goto ERR_NO_WSL

:PREFLIGHT_OK
echo ================================================================
echo   DITING Installer Build
echo   target: %TARGET%
echo   args  :%PASS%
echo ================================================================
echo.

call python "toolbox\core\build_manager.py" -t %TARGET%%PASS%
if errorlevel 1 goto ERR_BUILD

echo.
echo [SUCCESS] Installer build finished.
echo [INFO] Artifacts: %CD%\service\build\bin
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
echo         Only the Windows EXE installer needs it; use "deb" to skip it.
goto FAIL
:ERR_NO_WSL
echo [ERROR] WSL was not found, so the .deb cannot be assembled.
echo         Install WSL (wsl --install) or build the deb on Linux directly.
goto FAIL
:ERR_BUILD
echo [ERROR] The installer build failed. Check the messages above.
goto FAIL

:FAIL
popd
echo.
echo [INFO] Press any key to exit...
pause >nul
exit /b 1
