@echo off
setlocal EnableDelayedExpansion
title DITING Flutter APK Build Tool

:: APK build script.
::
:: Must go through `flutter build apk`; calling gradlew directly would produce an
:: APK with no Dart code inside.
::
:: Modes:
::   [1] Debug   + debug key   - cannot upgrade-install over a release build
::   [2] Debug   + release key - same signature as release, installable over it
::   [3] Release + arm64       - phones / tablets (default)
::   [4] Release + x86_64      - Android emulator only
::   [5] Clean                  - remove build cache and outputs
::
:: Tunnel engine ABI per mode: all modes ship the Rust engine
:: (libditing_engine.so) built by python rust\build_android.py, which this script
:: runs before every build: [1]/[2] build both ABIs (ARM devices AND the x86_64
:: emulator), [3] arm64 only, [4] x86_64 only. Installing [3]/[4] on the wrong
:: device fails with "app not installed / package incompatible".
:: All debug builds share one output name (app-debug.apk), so the artifact on
:: disk always comes from the LAST build - check the "ABIs in package" lines.
::
:: Release builds pass `--split-debug-info=build\symbols`, which moves the Dart
:: AOT symbol/debug metadata out of libapp.so into build\symbols\*.symbols: the
:: APK shrinks by ~1 MB with zero change to the compiled code. Keep those
:: .symbols files to symbolicate release crash reports; losing them only makes
:: stack traces unreadable, it does not change app behaviour.
::
:: NOTE: intentionally pure ASCII; cmd.exe parses batch files in the OEM code
:: page. Chinese docs live in docs/development/rust-engine-build.md.

cd /d "%~dp0"

if not exist "pubspec.yaml" goto ERR_NO_FLUTTER
where flutter >nul 2>&1
if errorlevel 1 goto ERR_NO_FLUTTER_BIN
where python >nul 2>&1
if errorlevel 1 goto ERR_NO_PYTHON

:: Version name comes from pubspec.yaml so the archive name always matches.
set "APP_VERSION_NAME=unknown"
for /f "tokens=2 delims=: " %%A in ('findstr /b "version:" pubspec.yaml') do set "APP_VERSION_NAME=%%A"
for /f "tokens=1 delims=+" %%B in ("!APP_VERSION_NAME!") do set "APP_VERSION_NAME=%%B"

:CHOOSE_BUILD_TYPE
cls
echo ================================================================
echo                  DITING Flutter APK Build Tool
echo ================================================================
echo.
echo   [1] Debug    / debug key    - Debuggable, not installable over release
echo   [2] Debug    / release key  - Debuggable, same signature as release
echo   [3] Release  / arm64        - Release key, phones and tablets   ^<- default
echo   [4] Release  / x86_64       - Release key, EMULATOR testing only
echo   [5] Clean                   - Remove build cache and artifacts
echo   [0] Exit
echo.
echo   Engine ABI: [1][2] dual-ABI (phones + emulator), [3] arm64, [4] x86_64.
echo.
set "BUILD_CHOICE="
set /p "BUILD_CHOICE=Enter choice [1/2/3/4/5/0] (default: 3): "

:: Default is Release: debug APKs start noticeably slower (JIT).
if "%BUILD_CHOICE%"=="" set "BUILD_CHOICE=3"
if "%BUILD_CHOICE%"=="1" goto SET_DEBUG_DEBUGKEY
if "%BUILD_CHOICE%"=="2" goto SET_DEBUG_RELEASEKEY
if "%BUILD_CHOICE%"=="3" goto SET_RELEASE_ARM64
if "%BUILD_CHOICE%"=="4" goto SET_RELEASE_X64
if "%BUILD_CHOICE%"=="5" goto DO_CLEAN
if "%BUILD_CHOICE%"=="0" goto EXIT_SCRIPT

echo.
echo [WARN] Invalid choice: "%BUILD_CHOICE%", please try again.
ping -n 3 127.0.0.1 >nul
goto CHOOSE_BUILD_TYPE

:DO_CLEAN
echo.
echo ================================================================
echo [INFO] Cleaning: flutter clean + gradlew clean
echo ================================================================
echo.
call flutter clean
call android\gradlew.bat -p android clean
if errorlevel 1 goto ERR_CLEAN_FAILED
echo.
echo [SUCCESS] Clean finished. Build cache and APK outputs removed.
pause
goto CHOOSE_BUILD_TYPE

:: Each mode sets BUILD_TYPE, BUILD_TYPE_NAME, FLUTTER_ARGS, APK_DIR, APK_NAME
:: and DEVICE_SCOPE; one shared code path does the build.

:SET_DEBUG_DEBUGKEY
:: Debug builds bundle both ABIs so one APK runs everywhere.
set "BUILD_TYPE=debug"
set "BUILD_TYPE_NAME=Debug (Debug Key)"
set "FLUTTER_ARGS=build apk --debug -PsignDebugWithRelease=false"
set "APK_DIR=build\app\outputs\flutter-apk"
set "APK_NAME=app-debug.apk"
set "IS_EMULATOR_BUILD="
set "RUST_ABI=all"
set "DEVICE_SCOPE=Dual-ABI Rust engine: runs on ARM phones/tablets AND the x86_64 emulator"
goto START_BUILD

:SET_DEBUG_RELEASEKEY
set "BUILD_TYPE=debug"
set "BUILD_TYPE_NAME=Debug (Release Key)"
set "FLUTTER_ARGS=build apk --debug -PsignDebugWithRelease=true"
set "APK_DIR=build\app\outputs\flutter-apk"
set "APK_NAME=app-debug.apk"
set "IS_EMULATOR_BUILD="
set "RUST_ABI=all"
set "DEVICE_SCOPE=Dual-ABI Rust engine: runs on ARM phones/tablets AND the x86_64 emulator"
goto START_BUILD

:SET_RELEASE_ARM64
if not exist "android\key.properties" goto ERR_NO_KEYSTORE
set "BUILD_TYPE=release"
set "BUILD_TYPE_NAME=Release (ARM64, Release Key)"
set "FLUTTER_ARGS=build apk --release --target-platform android-arm64 -PditingAbi=arm64 --split-debug-info=build\symbols\arm64"
set "APK_DIR=build\app\outputs\flutter-apk"
set "APK_NAME=app-release.apk"
set "IS_EMULATOR_BUILD="
set "RUST_ABI=arm64"
set "DEVICE_SCOPE=arm64-only: will NOT run on the x86_64 emulator"
goto START_BUILD

:SET_RELEASE_X64
:: -PditingAbi=x86_64 makes build.gradle.kts package the x86_64 libraries only.
if not exist "android\key.properties" goto ERR_NO_KEYSTORE
set "BUILD_TYPE=release"
set "BUILD_TYPE_NAME=Release (x86_64, Release Key, EMULATOR)"
set "FLUTTER_ARGS=build apk --release --target-platform android-x64 -PditingAbi=x86_64 --split-debug-info=build\symbols\x86_64"
set "APK_DIR=build\app\outputs\flutter-apk"
set "APK_NAME=app-release.apk"
set "IS_EMULATOR_BUILD=1"
set "RUST_ABI=x86_64"
set "DEVICE_SCOPE=x86_64 emulator only: will NOT run on ARM phones/tablets"
goto START_BUILD

:START_BUILD
echo.
echo ================================================================
echo [INFO] Building: %BUILD_TYPE_NAME%
echo [INFO] flutter %FLUTTER_ARGS%
echo ================================================================
echo.
if defined IS_EMULATOR_BUILD (
    echo [WARN] This APK targets the x86_64 emulator only. It will NOT run on
    echo        a physical ARM device. Use option [3] for real devices.
    echo.
)

rem The Rust libraries (libditing_engine.so + the Kotlin/Dart kernels) are what the app loads:
rem without them the APK builds but every mode fails at runtime, so build them first. The Gradle
rem build also checks jniLibs per variant; this is the convenience path.
echo [INFO] Building Rust libraries: python rust\build_android.py --abi %RUST_ABI%
echo.
call python "%~dp0..\..\rust\build_android.py" --abi %RUST_ABI%
if errorlevel 1 goto ERR_RUST_BUILD_FAILED
echo.

call flutter %FLUTTER_ARGS%
if errorlevel 1 goto ERR_BUILD_FAILED

set "FOUND_APK=%CD%\%APK_DIR%\%APK_NAME%"
if not exist "%FOUND_APK%" goto ERR_NO_APK

echo.
echo ================================================================
echo [SUCCESS] %BUILD_TYPE_NAME% build completed!
echo [INFO] APK: %FOUND_APK%
for %%F in ("%FOUND_APK%") do echo [INFO] Size: %%~zF bytes
echo [INFO] Target scope: %DEVICE_SCOPE%
echo [INFO] ABIs in package:
python -c "import zipfile,sys;z=zipfile.ZipFile(sys.argv[1]);L=sorted({n.split('/')[1] for n in z.namelist() if n.startswith('lib/')});E=sorted({n.split('/')[1] for n in z.namelist() if n.startswith('lib/') and n.endswith('libditing_engine.so')});print('       Native lib ABIs: '+', '.join(L));print('       Rust engine ABI: '+(', '.join(E) if E else 'MISSING'));print('       .so count: '+str(len([n for n in z.namelist() if n.startswith('lib/') and n.endswith('.so')])))" "%FOUND_APK%" 2>nul
rem Versioned archive from copy*ApkWithVersion in android/app/build.gradle.kts.
set "VERSIONED_APK=%CD%\build\app\outputs\apk\versioned\%BUILD_TYPE%\DITING-%BUILD_TYPE%-v%APP_VERSION_NAME%.apk"
if exist "!VERSIONED_APK!" echo [INFO] Versioned APK: !VERSIONED_APK!
echo ================================================================
echo.

:: Signer certificate fingerprint.
set "BUILD_TOOLS=%LOCALAPPDATA%\Android\Sdk\build-tools"
if exist "%BUILD_TOOLS%" (
    for /f "delims=" %%D in ('dir /b /o:-n "%BUILD_TOOLS%" 2^>nul') do (
        if exist "%BUILD_TOOLS%\%%D\apksigner.bat" (
            echo [INFO] Signer certificate:
            call "%BUILD_TOOLS%\%%D\apksigner.bat" verify --print-certs "%FOUND_APK%" 2>nul | findstr /i "Signer #1 certificate DN"
            goto SIGNED_SHOWN
        )
    )
)
:SIGNED_SHOWN
goto SUCCESS_EXIT

:: Error handlers
:ERR_NO_FLUTTER
echo.
echo [ERROR] Not a Flutter project root (pubspec.yaml not found).
echo         Run this script from android\app\.
goto ERROR_EXIT

:ERR_NO_FLUTTER_BIN
echo.
echo [ERROR] 'flutter' not found in PATH. Add your Flutter SDK bin
echo         directory to PATH and retry.
goto ERROR_EXIT

:ERR_NO_KEYSTORE
echo.
echo [ERROR] Release signing is not configured: android\key.properties
echo         is missing. Create it (see android\SIGNING.md) or use
echo         option [1] instead.
goto ERROR_EXIT

:ERR_NO_PYTHON
echo.
echo [ERROR] 'python' not found in PATH. The Rust libraries are built with
echo         python rust\build_android.py, so Python 3 is required.
goto ERROR_EXIT

:ERR_RUST_BUILD_FAILED
echo.
echo [ERROR] The Rust library build failed: python rust\build_android.py
echo         --abi %RUST_ABI%. Common causes:
echo           1. Android NDK missing (set ANDROID_NDK_HOME, or sdk.dir in
echo              android\local.properties)
echo           2. Rust target not installed (rustup target add aarch64-linux-android)
echo           3. cargo build error - scroll up for the compiler output
goto ERROR_EXIT

:ERR_CLEAN_FAILED
echo.
echo [ERROR] Clean failed ('flutter clean' or 'gradlew clean' returned
echo         an error). Close Android Studio / Gradle daemons and retry.
goto ERROR_EXIT

:ERR_BUILD_FAILED
echo.
echo [ERROR] Build failed: 'flutter build apk' returned a non-zero exit
echo         code. Troubleshooting:
echo           1. Run 'dart analyze lib test' and 'flutter test' first
echo           2. Check signing config: android/key.properties
echo           3. Gradle cache may be broken - try option [5] Clean
goto ERROR_EXIT

:ERR_NO_APK
echo.
echo [ERROR] Build finished but no APK found at: %FOUND_APK%
echo         Check whether the flutter build output path changed.
goto ERROR_EXIT

:SUCCESS_EXIT
echo.
echo [INFO] Done. Press any key to exit...
pause >nul
exit /b 0

:ERROR_EXIT
echo.
echo [INFO] Aborted due to errors. Press any key to exit...
pause >nul
exit /b 1

:EXIT_SCRIPT
echo.
echo [INFO] Cancelled by user. Exiting...
exit /b 0
