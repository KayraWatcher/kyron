@echo off
REM KYRON Release Build Wrapper - ASCII workspace for OneDrive non-ASCII path workaround
REM Usage: scripts\build_release.bat [--dart-define=KEY=VALUE ...]

set PROJECT_ROOT=%~dp0..
set BUILD_WORKSPACE=C:\flutter_build\kyron_release
set OUTPUT_DIR=%PROJECT_ROOT%\build\app\outputs\apk\release

echo [%time%] Preparing ASCII build workspace: %BUILD_WORKSPACE%
if not exist "%BUILD_WORKSPACE%" mkdir "%BUILD_WORKSPACE%"

echo [%time%] Cleaning previous build artifacts...
for /d %%d in ("%BUILD_WORKSPACE%\build" "%BUILD_WORKSPACE%\.dart_tool" "%BUILD_WORKSPACE%\android\app\build" "%BUILD_WORKSPACE%\android\.gradle") do (
    if exist "%%d" rmdir /s /q "%%d" 2>nul
)

echo [%time%] Syncing source to workspace (robocopy)...
robocopy "%PROJECT_ROOT%" "%BUILD_WORKSPACE%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /XJ /COPY:DAT /MT:8 ^
 /XD .git .github .idea .vscode build .dart_tool .flutter-plugins node_modules dist android\app\build android\.gradle web\node_modules web\dist web\.vite ^
 /XF *.log *.iml *.iws *.local .env *.env.* *.tsbuildinfo
REM robocopy exit codes 0-7 are success, 8+ error
if %errorlevel% GEQ 8 (
    echo [%time%] ERROR: robocopy failed with exit code %errorlevel%
    exit /b %errorlevel%
)

echo [%time%] Starting Flutter release build in workspace...
cd /d "%BUILD_WORKSPACE%"
flutter build apk --release %*
if errorlevel 1 (
    echo [%time%] ERROR: flutter build failed with exit code %errorlevel%
    exit /b %errorlevel%
)

echo [%time%] Copying release APKs back to project...
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
for %%f in ("%BUILD_WORKSPACE%\build\app\outputs\flutter-apk\*.apk") do (
    copy /y "%%f" "%OUTPUT_DIR%\" >nul
    for %%a in ("%%f") do set APK_SIZE=%%~za
    set /a APK_SIZE_MB=%APK_SIZE% / 1024 / 1024
    echo [%time%] OK: Copied %%~nxf (%APK_SIZE_MB% MB) -> %OUTPUT_DIR%
)

if not exist "%OUTPUT_DIR%\app-release.apk" (
    echo [%time%] ERROR: app-release.apk not found in output
    exit /b 1
)

echo [%time%] Release build completed successfully.
for %%a in ("%OUTPUT_DIR%\app-release.apk") do set FINAL_SIZE=%%~za
set /a FINAL_MB=%FINAL_SIZE% / 1024 / 1024
echo [%time%] Output: %OUTPUT_DIR%\app-release.apk (%FINAL_MB% MB)
exit /b 0