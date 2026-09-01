@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if exist "%SCRIPT_DIR%chinese-patch\tools\Apply-Asar-Patch.ps1" (
    set "PATCH_ROOT=%SCRIPT_DIR%chinese-patch"
) else if exist "%SCRIPT_DIR%tools\Apply-Asar-Patch.ps1" (
    set "PATCH_ROOT=%SCRIPT_DIR%"
) else (
    echo 未找到 chinese-patch\tools\Apply-Asar-Patch.ps1。
    pause
    exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PATCH_ROOT%\tools\Apply-Asar-Patch.ps1" -Mode Uninstall -PatchRoot "%PATCH_ROOT%"
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
