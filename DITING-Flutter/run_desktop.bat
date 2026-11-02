@echo off
setlocal EnableDelayedExpansion
title DITING Flutter Desktop

:: Launch the Flutter Windows desktop app in apps\diting_desktop.
::
:: Requirements:
::   - Flutter SDK on PATH (flutter doctor must list the "Windows (desktop)" device)
::   - Visual Studio with the "Desktop development with C++" workload
::     (flutter doctor -v -> Visual Studio - develop Windows apps [OK])
::   - Windows Developer Mode on, so pub can create the plugin symlinks
::     (settings: start ms-settings:developers)
::
:: Usage:
::   run_desktop.bat            debug run with hot reload (default)
::   run_desktop.bat release    build a release EXE and launch it
::
:: The Flutter window is only a client: every figure comes from the local
:: DITING service (Desktop/cmd/service), which listens on 127.0.0.1:15353 by
:: default. This script probes that port and, when the privileged service
:: binary is already built, starts it elevated before launching the window.
:: Override the port with DITING_IPC_PORT if the service was configured
:: differently.
::
:: Intentionally pure ASCII: cmd.exe parses batch files in the OEM code page.
:: Chinese notes live in README.md.

cd /d "%~dp0"

if not exist "apps\diting_desktop\pubspec.yaml" goto ERR_NO_PROJECT
where flutter >nul 2>&1
if errorlevel 1 goto ERR_NO_FLUTTER

set "IPC_HOST=127.0.0.1"
set "IPC_PORT=15353"
if defined DITING_IPC_PORT set "IPC_PORT=%DITING_IPC_PORT%"

:: Flutter's windows build needs the MSVC C++ toolchain, which ships with Visual
:: Studio (not just the Build Tools installer shell). vswhere is the supported probe.
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "HAS_MSVC="
if exist "%VSWHERE%" (
    for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set "HAS_MSVC=%%I"
)
if not defined HAS_MSVC if defined VSINSTALLDIR set "HAS_MSVC=%VSINSTALLDIR%"
if not defined HAS_MSVC goto ERR_NO_MSVC

:: Plugin symlinks (shared_preferences, url_launcher, ...) need Developer Mode.
set "DEV_MODE="
for /f "tokens=3" %%V in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense 2^>nul ^| findstr /i "AllowDevelopmentWithoutDevLicense"') do set "DEV_MODE=%%V"
if not "%DEV_MODE%"=="0x1" (
    echo [WARN] Windows Developer Mode is off. Plugin symlinks may fail to build.
    echo        Enable it with: start ms-settings:developers
    echo.
)

echo ================================================================
echo   DITING Flutter Desktop
echo   project: apps\diting_desktop
echo ================================================================
echo.

pushd "apps\diting_desktop"
set "PUSHED=1"

call flutter pub get
if errorlevel 1 goto ERR_PUB_GET

:: Start the core service first, otherwise the window can only show "cannot reach
:: the local service": it has no mock backend and never invents state.
call :PROBE_IPC
if defined IPC_SEEN goto SERVICE_READY
echo [INFO] Nothing answers on %IPC_HOST%:%IPC_PORT%.
echo        The desktop window is only a client of the local DITING service,
set "SVC_EXE=%~dp0..\Desktop\build\bin\diting-service.exe"
if not exist "%SVC_EXE%" goto SERVICE_MISSING
echo        so it is started first (a UAC prompt is expected):
for %%I in ("%SVC_EXE%") do echo            %%~fI -run
powershell -NoProfile -Command "Start-Process -FilePath '%SVC_EXE%' -ArgumentList '-run' -Verb RunAs" >nul 2>&1
if errorlevel 1 goto SERVICE_MISSING
for /l %%I in (1,1,10) do (
    call :PROBE_IPC
    if defined IPC_SEEN goto SERVICE_READY
    timeout /t 1 /nobreak >nul 2>&1
)
echo [WARN] The service did not open %IPC_HOST%:%IPC_PORT% within 10s.
echo        The window will report the service as unreachable until it does.
goto SERVICE_READY

:SERVICE_MISSING
echo        without it the window shows "cannot reach the local service".
echo        build and start it once with:
echo            cd Desktop
echo            go build -o build\bin\diting-service.exe ./cmd/service
echo            build\bin\diting-service.exe -run     (as Administrator)
echo.

:SERVICE_READY

if /i "%~1"=="release" goto RELEASE_RUN

echo [INFO] flutter run -d windows  (hot reload; Ctrl+C to stop)
echo.
call flutter run -d windows
if errorlevel 1 goto ERR_RUN
goto FINISH

:RELEASE_RUN
echo [INFO] flutter build windows --release
echo.
call flutter build windows --release
if errorlevel 1 goto ERR_BUILD

set "EXE=%CD%\build\windows\x64\runner\Release\diting_desktop.exe"
if not exist "%EXE%" set "EXE=%CD%\build\windows\runner\Release\diting_desktop.exe"
if not exist "%EXE%" goto ERR_NO_EXE

echo.
echo [SUCCESS] Release build finished.
echo [INFO] EXE: %EXE%
start "" "%EXE%"
goto FINISH

:FINISH
popd
echo.
echo [INFO] Done.
pause
exit /b 0

:ERR_NO_PROJECT
echo [ERROR] apps\diting_desktop\pubspec.yaml not found.
echo         Run this script from the DITING-Flutter directory.
goto FAIL
:ERR_NO_FLUTTER
echo [ERROR] 'flutter' not found on PATH. Add your Flutter SDK bin directory to PATH.
goto FAIL
:ERR_NO_MSVC
echo [ERROR] Visual Studio with "Desktop development with C++" was not found.
echo         Install it from https://visualstudio.microsoft.com/downloads/
echo         and select that workload, then run: flutter doctor -v
echo.
echo         Without it, Flutter cannot build any Windows app.
goto FAIL
:ERR_PUB_GET
echo [ERROR] flutter pub get failed. Fix the dependency error above and retry.
goto FAIL
:ERR_RUN
echo [ERROR] flutter run failed. Check the messages above.
goto FAIL
:ERR_BUILD
echo [ERROR] flutter build windows failed. Check the messages above.
goto FAIL
:ERR_NO_EXE
echo [ERROR] Build reported success but no EXE was found under build\windows.
goto FAIL

:FAIL
if defined PUSHED popd
echo.
echo [INFO] Press any key to exit...
pause >nul
exit /b 1

:: Sets IPC_SEEN when the local service answers on the IPC port, so a running
:: service is never started twice. A TCP connect is the honest probe: it asks the
:: same question the window will ask, and it does not depend on parsing netstat.
:PROBE_IPC
set "IPC_SEEN="
powershell -NoProfile -Command "try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('%IPC_HOST%', %IPC_PORT%); $c.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 set "IPC_SEEN=1"
exit /b 0
