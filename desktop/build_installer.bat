@echo off
setlocal
title DITING Installer Build

:: Build the DITING desktop installer packages (Windows EXE / Linux .deb).
::
:: Usage:
::   build_installer.bat                    Windows EXE installer (default)
::   build_installer.bat exe                same as above
::   build_installer.bat deb                Linux .deb, assembled through WSL
::   build_installer.bat both               EXE + .deb
::   build_installer.bat exe -v 1.4.4 --clean
::   build_installer.bat deb -a arm64
::
:: Any argument after the optional target is forwarded to
:: desktop\toolbox\core\build_manager.py, which runs the whole pipeline:
::   Flutter Web console (frontend/dist) -> Flutter Windows app ->
::   diting-service.exe -> NSIS installer.
:: Only the final installers are kept, in desktop\service\build\bin.
::
:: Requirements:
::   - Python 3.10+ on PATH
::   - Flutter SDK on PATH (the "Windows (desktop)" device must work)
::   - Go 1.25+ on PATH
::   - NSIS (makensis) for the EXE target
::   - Visual Studio "Desktop development with C++" + Windows Developer Mode
::   - WSL for the deb target when this runs on Windows
::
:: This script only builds; it never installs or launches anything. To run the
:: desktop window from source instead, see "flutter run -d windows" in README.md.
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

if not exist "app\pubspec.yaml" goto ERR_NO_PROJECT
if not exist "service\go.mod" goto ERR_NO_SERVICE
if not exist "toolbox\core\build_manager.py" goto ERR_NO_ENGINE

where python >nul 2>&1
if errorlevel 1 goto ERR_NO_PYTHON

:: Normalise the target into the two flags that drive the tool checks.
set "NEED_WIN="
set "NEED_DEB="
if /i "%TARGET%"=="deb" goto TGT_DEB
if /i "%TARGET%"=="both" goto TGT_BOTH
set "NEED_WIN=1"
goto TGT_DONE
:TGT_BOTH
set "NEED_WIN=1"
:TGT_DEB
set "NEED_DEB=1"
:TGT_DONE

if not defined NEED_WIN goto CHECK_DEB

where flutter >nul 2>&1
if errorlevel 1 goto ERR_NO_FLUTTER
where go >nul 2>&1
if errorlevel 1 goto ERR_NO_GO

:: Flutter's windows build needs the MSVC C++ toolchain, which ships with Visual
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

:CHECK_DEB
if not defined NEED_DEB goto PREFLIGHT_OK
if not defined NEED_WIN (
    where flutter >nul 2>&1
    if errorlevel 1 goto ERR_NO_FLUTTER
    where go >nul 2>&1
    if errorlevel 1 goto ERR_NO_GO
)
if /i not "%OS%"=="Windows_NT" goto PREFLIGHT_OK
:: The deb is assembled by WSL so the Windows host needs no extra Linux toolchain.
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

:ERR_NO_PROJECT
echo [ERROR] app\pubspec.yaml not found.
echo         Run this script from the desktop directory.
goto FAIL
:ERR_NO_SERVICE
echo [ERROR] service\go.mod not found.
echo         The installer bundles diting-service, so the service module must exist.
goto FAIL
:ERR_NO_ENGINE
echo [ERROR] toolbox\core\build_manager.py not found.
goto FAIL
:ERR_NO_PYTHON
echo [ERROR] 'python' not found on PATH. Install Python 3.10+ and retry.
goto FAIL
:ERR_NO_FLUTTER
echo [ERROR] 'flutter' not found on PATH. Add your Flutter SDK bin directory to PATH.
goto FAIL
:ERR_NO_GO
echo [ERROR] 'go' not found on PATH. Install Go 1.25+ and retry.
goto FAIL
:ERR_NO_MSVC
echo [ERROR] Visual Studio with "Desktop development with C++" was not found.
echo         Install it from https://visualstudio.microsoft.com/downloads/
echo         and select that workload, then run: flutter doctor -v
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
