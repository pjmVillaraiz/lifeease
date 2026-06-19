@echo off
setlocal enabledelayedexpansion

echo ==============================================
echo  LifeEase Release APK Installer for Windows
echo ==============================================
echo.

:: 1. Attempt to find ADB in System PATH
set ADB_PATH=adb
where adb >nul 2>nul
if %ERRORLEVEL% equ 0 (
    goto :found_adb
)

:: 2. Try parsing android/local.properties
if exist "android\local.properties" (
    for /f "tokens=2 delims==" %%i in ('findstr "sdk.dir" "android\local.properties"') do (
        set SDK_DIR=%%i
        :: Replace double backslashes with single backslashes
        set SDK_DIR=!SDK_DIR:\\=\!
        set ADB_PATH=!SDK_DIR!\platform-tools\adb.exe
        if exist "!ADB_PATH!" goto :found_adb
    )
)

:: 3. Try standard AppData location as fallback
set ADB_PATH=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if exist "%ADB_PATH%" goto :found_adb

echo [ERROR] Could not locate Android SDK or adb.exe.
echo Please ensure Android Studio is installed and has downloaded the Command Line Tools.
echo.
pause
exit /b 1

:found_adb
echo ADB Tool: "%ADB_PATH%"
echo Checking for connected devices...
echo.

:: Scan for active devices
"%ADB_PATH%" devices > temp_devices.txt
set DEVICE_COUNT=0
for /f "skip=1 tokens=1,2" %%a in (temp_devices.txt) do (
    if "%%b"=="device" (
        set /a DEVICE_COUNT+=1
        set DEVICE_!DEVICE_COUNT!=%%a
    )
)
del temp_devices.txt

if %DEVICE_COUNT% equ 0 (
    echo [ERROR] No connected Android devices or running emulators found.
    echo.
    echo Please:
    echo  1. Connect your physical phone via USB (with USB Debugging turned ON).
    echo  2. Or make sure your Android emulator is running.
    echo.
    pause
    exit /b 1
)

echo Found %DEVICE_COUNT% active device(s).
echo.
echo Package to install: "build\app\outputs\flutter-apk\app-release.apk"
echo.

set SUCCESS_COUNT=0
for /l %%i in (1,1,%DEVICE_COUNT%) do (
    set DEV=!DEVICE_%%i!
    echo ----------------------------------------------
    echo Installing on device [!DEV!]...
    "%ADB_PATH%" -s !DEV! install -r "build\app\outputs\flutter-apk\app-release.apk"
    if %ERRORLEVEL% equ 0 (
        echo [SUCCESS] Installed successfully on !DEV!
        set /a SUCCESS_COUNT+=1
    ) else (
        echo [ERROR] Installation failed on !DEV!
    )
)

echo.
echo ==============================================
echo Summary: !SUCCESS_COUNT! of %DEVICE_COUNT% device(s) successfully updated.
echo ==============================================
echo.
pause
