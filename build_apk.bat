@echo off
setlocal EnableDelayedExpansion
title Android APK Build and Install Tool

:: Switch to the directory containing this script (project root)
cd /d "%~dp0"

:: Verify current directory is an Android Gradle project root
if not exist "gradlew.bat" goto ERR_NO_GRADLEW

:: ====================================================================
:: Step 1: Select Build Type (Debug / Release)
:: ====================================================================
:CHOOSE_BUILD_TYPE
cls
echo ================================================================
echo             Android APK Build and Install Tool
echo ================================================================
echo.
echo Select the build type:
echo   [1] Debug    (Development build, fast compilation)
echo   [2] Release  (Release build, optimized / obfuscated)
echo   [0] Exit
echo.
set "BUILD_CHOICE="
set /p "BUILD_CHOICE=Enter choice [1/2/0] (default: 1): "

if "%BUILD_CHOICE%"=="" set "BUILD_CHOICE=1"
if "%BUILD_CHOICE%"=="1" goto SET_DEBUG
if /i "%BUILD_CHOICE%"=="debug" goto SET_DEBUG
if /i "%BUILD_CHOICE%"=="d" goto SET_DEBUG
if "%BUILD_CHOICE%"=="2" goto SET_RELEASE
if /i "%BUILD_CHOICE%"=="release" goto SET_RELEASE
if /i "%BUILD_CHOICE%"=="r" goto SET_RELEASE
if "%BUILD_CHOICE%"=="0" goto EXIT_SCRIPT
if /i "%BUILD_CHOICE%"=="q" goto EXIT_SCRIPT
if /i "%BUILD_CHOICE%"=="exit" goto EXIT_SCRIPT

echo.
echo [WARN] Invalid choice: "%BUILD_CHOICE%", please try again.
timeout /t 2 >nul
goto CHOOSE_BUILD_TYPE

:SET_DEBUG
set "BUILD_TYPE=debug"
set "BUILD_TYPE_NAME=Debug"
set "GRADLE_TASK=assembleDebug"
goto START_BUILD

:SET_RELEASE
set "BUILD_TYPE=release"
set "BUILD_TYPE_NAME=Release"
set "GRADLE_TASK=assembleRelease"
goto START_BUILD

:: ====================================================================
:: Step 2: Run Gradle Build
:: ====================================================================
:START_BUILD
echo.
echo ================================================================
echo [INFO] Starting %BUILD_TYPE_NAME% build...
echo [INFO] Running task: gradlew.bat %GRADLE_TASK%
echo ================================================================
echo.

call gradlew.bat %GRADLE_TASK%
if errorlevel 1 goto ERR_BUILD_FAILED

:: ====================================================================
:: Locate Output APK File
:: ====================================================================
set "FOUND_APK="

REM 1. Check default standard path: app\build\outputs\apk\<buildType>\app-<buildType>.apk
if exist "app\build\outputs\apk\%BUILD_TYPE%\app-%BUILD_TYPE%.apk" (
    set "FOUND_APK=%CD%\app\build\outputs\apk\%BUILD_TYPE%\app-%BUILD_TYPE%.apk"
    goto APK_LOCATED
)

REM 2. Search for the latest matching APK in any build\outputs\apk directory
for /f "delims=" %%F in ('dir /b /s /o:-d *.apk 2^>nul') do (
    call :CHECK_APK_CANDIDATE "%%F"
    if defined FOUND_APK goto APK_LOCATED
)

:APK_LOCATED
if not defined FOUND_APK goto ERR_NO_APK

echo.
echo ================================================================
echo [SUCCESS] %BUILD_TYPE_NAME% build completed successfully!
echo [INFO] Located APK: %FOUND_APK%
echo ================================================================
echo.

:: ====================================================================
:: Step 3: Ask to Install APK
:: ====================================================================
:ASK_INSTALL
echo Do you want to install the generated %BUILD_TYPE_NAME% APK to a device?
echo   [Y] Yes - Check/Connect ADB device and install (default)
echo   [N] No  - Keep build output and exit
echo.
set "INSTALL_CHOICE="
set /p "INSTALL_CHOICE=Enter choice [Y/N] (default: Y): "

if "%INSTALL_CHOICE%"=="" set "INSTALL_CHOICE=Y"
if /i "%INSTALL_CHOICE%"=="y" goto PREPARE_ADB
if /i "%INSTALL_CHOICE%"=="yes" goto PREPARE_ADB
if /i "%INSTALL_CHOICE%"=="1" goto PREPARE_ADB
if /i "%INSTALL_CHOICE%"=="n" goto NO_INSTALL
if /i "%INSTALL_CHOICE%"=="no" goto NO_INSTALL
if /i "%INSTALL_CHOICE%"=="0" goto NO_INSTALL

echo.
echo [WARN] Invalid choice: "%INSTALL_CHOICE%", please try again.
echo.
goto ASK_INSTALL

:NO_INSTALL
echo.
echo [INFO] Installation skipped. APK output preserved at:
echo        %FOUND_APK%
goto SUCCESS_EXIT

:: ====================================================================
:: Step 4: ADB Environment Check and Device Detection
:: ====================================================================
:PREPARE_ADB
echo.
echo ================================================================
echo [INFO] Checking ADB environment...
echo ================================================================
echo.

where adb >nul 2>&1
if errorlevel 1 goto ERR_NO_ADB

:CHECK_DEVICES
echo [INFO] Scanning for connected ADB devices...
set "DEVICE_COUNT=0"
set "TARGET_DEVICE="

for /f "skip=1 tokens=1,2" %%A in ('adb devices 2^>nul') do (
    if "%%B"=="device" (
        set /a DEVICE_COUNT+=1
        set "DEVICE_!DEVICE_COUNT!=%%A"
        set "TARGET_DEVICE=%%A"
    )
)

if %DEVICE_COUNT% EQU 0 goto PROMPT_CONNECT_ADB
if %DEVICE_COUNT% EQU 1 goto SINGLE_DEVICE_FOUND

:MULTI_DEVICES_FOUND
echo [INFO] Multiple ready devices detected. Select target device:
for /L %%i in (1,1,%DEVICE_COUNT%) do (
    call echo   [%%i] %%DEVICE_%%i%%
)
echo.
set "DEV_SEL="
set /p "DEV_SEL=Enter device number [1-%DEVICE_COUNT%] (default: 1): "
if "!DEV_SEL!"=="" set "DEV_SEL=1"

call set "SELECTED_DEV=%%DEVICE_!DEV_SEL!%%"
if "!SELECTED_DEV!"=="" (
    echo.
    echo [WARN] Invalid device number: "!DEV_SEL!", please try again.
    echo.
    goto CHECK_DEVICES
)
set "TARGET_DEVICE=!SELECTED_DEV!"
echo [INFO] Target device selected: !TARGET_DEVICE!
goto DO_INSTALL

:SINGLE_DEVICE_FOUND
echo [INFO] Target device detected: !TARGET_DEVICE!
goto DO_INSTALL

:: ====================================================================
:: Step 5: Connect Manual ADB Device (IP:Port)
:: ====================================================================
:PROMPT_CONNECT_ADB
echo [WARN] No ready ADB device currently detected.
echo.
echo ================================================================
echo Please enter the target ADB device IP and port (e.g. 192.168.1.1:6688)
echo Or enter 'Q' to cancel and exit:
echo ================================================================
set "ADB_ADDRESS="
set /p "ADB_ADDRESS=ADB Device Address [IP:PORT / Q]: "

if "%ADB_ADDRESS%"=="" (
    echo.
    echo [WARN] Input cannot be empty, please try again.
    echo.
    goto PROMPT_CONNECT_ADB
)
if /i "%ADB_ADDRESS%"=="q" goto EXIT_SCRIPT
if /i "%ADB_ADDRESS%"=="exit" goto EXIT_SCRIPT

echo.
echo [INFO] Connecting to %ADB_ADDRESS% ...
adb connect %ADB_ADDRESS%

REM Wait for ADB daemon status refresh
timeout /t 2 >nul

REM Verify if the device is connected and in 'device' state
set "CONNECT_SUCCESS=0"
for /f "skip=1 tokens=1,2" %%A in ('adb devices 2^>nul') do (
    if "%%A"=="%ADB_ADDRESS%" (
        if "%%B"=="device" (
            set "CONNECT_SUCCESS=1"
            set "TARGET_DEVICE=%%A"
        )
    )
)

if "!CONNECT_SUCCESS!"=="0" (
    for /f "skip=1 tokens=1,2" %%A in ('adb devices 2^>nul') do (
        if "%%B"=="device" (
            set "CONNECT_SUCCESS=1"
            set "TARGET_DEVICE=%%A"
        )
    )
)

if "!CONNECT_SUCCESS!"=="0" goto ERR_ADB_CONNECT_FAILED

echo.
echo [SUCCESS] Successfully connected to device: !TARGET_DEVICE!
goto DO_INSTALL

:: ====================================================================
:: Step 6: Install APK
:: ====================================================================
:DO_INSTALL
echo.
echo ================================================================
echo [INFO] Installing %BUILD_TYPE_NAME% APK onto device [!TARGET_DEVICE!] ...
echo [INFO] APK file: %FOUND_APK%
echo ================================================================
echo.

adb -s !TARGET_DEVICE! install -r "%FOUND_APK%"
if errorlevel 1 goto ERR_INSTALL_FAILED

echo.
echo ================================================================
echo [SUCCESS] %BUILD_TYPE_NAME% APK installed successfully!
echo ================================================================
goto SUCCESS_EXIT

:: ====================================================================
:: Helper: Validate candidate APK file
:: ====================================================================
:CHECK_APK_CANDIDATE
set "CURRENT_FILE=%~1"
echo "%CURRENT_FILE%" | findstr /i "\\build\\outputs\\apk\\" >nul || exit /b
echo "%CURRENT_FILE%" | findstr /i "%BUILD_TYPE%" >nul || exit /b
echo "%CURRENT_FILE%" | findstr /i "androidTest unaligned -test" >nul && exit /b
set "FOUND_APK=%CURRENT_FILE%"
exit /b

:: ====================================================================
:: Error Handlers
:: ====================================================================
:ERR_NO_GRADLEW
echo.
echo ================================================================
echo [ERROR] gradlew.bat not found in the current directory!
echo Cause:  Current directory is not a valid Android Gradle project root.
echo Action: Place and run this script in the root directory containing gradlew.bat.
echo ================================================================
goto ERROR_EXIT

:ERR_BUILD_FAILED
echo.
echo ================================================================
echo [ERROR] Gradle build failed!
echo Cause:  Build task terminated with errors. Check the logs above.
echo ================================================================
goto ERROR_EXIT

:ERR_NO_APK
echo.
echo ================================================================
echo [ERROR] Build completed, but no %BUILD_TYPE_NAME% APK file was found!
echo Action: Check build.gradle output directories and naming configuration.
echo ================================================================
goto ERROR_EXIT

:ERR_NO_ADB
echo.
echo ================================================================
echo [ERROR] 'adb' command not found in system PATH!
echo Cause:  Android Debug Bridge is not installed or not in PATH.
echo Action: Install Android SDK Platform-Tools and add its path to the PATH environment variable.
echo ================================================================
goto ERROR_EXIT

:ERR_ADB_CONNECT_FAILED
echo.
echo ================================================================
echo [ERROR] Failed to connect to ADB device or device is not ready!
echo Cause:  Unable to establish connection to %ADB_ADDRESS%.
echo Troubleshooting steps:
echo   1. Verify the target IP address and port number.
echo   2. Ensure the Android device and PC are on the same local network (Wi-Fi / Hotspot).
echo   3. Ensure 'Wireless Debugging' or ADB network debugging is enabled in Developer Options.
echo   4. Check device screen for 'Allow USB/Wireless debugging' prompt and confirm authorization.
echo ================================================================
echo.
echo Retry connection?
echo   [1] Re-enter IP:Port (default)
echo   [0] Exit script
set "RETRY_CHOICE="
set /p "RETRY_CHOICE=Enter choice [1/0] (default: 1): "
if "!RETRY_CHOICE!"=="" set "RETRY_CHOICE=1"
if "!RETRY_CHOICE!"=="1" (
    echo.
    goto PROMPT_CONNECT_ADB
)
goto ERROR_EXIT

:ERR_INSTALL_FAILED
echo.
echo ================================================================
echo [ERROR] APK installation failed!
echo Cause:  'adb install' returned an error.
echo Common troubleshooting steps:
echo   1. Insufficient device storage space.
echo   2. Signature mismatch with existing app (uninstall previous version from device first).
echo   3. Device system policy blocked installation (check device screen for permission prompts).
echo ================================================================
goto ERROR_EXIT

:: ====================================================================
:: Exit Handlers
:: ====================================================================
:SUCCESS_EXIT
echo.
echo ================================================================
echo [INFO] Done. Press any key to exit...
echo ================================================================
pause >nul
exit /b 0

:ERROR_EXIT
echo.
echo ================================================================
echo [INFO] Execution aborted due to errors. Press any key to exit...
echo ================================================================
pause >nul
exit /b 1

:EXIT_SCRIPT
echo.
echo [INFO] Operation cancelled by user. Exiting...
exit /b 0
