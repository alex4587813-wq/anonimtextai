@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title Local Anonymizer

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo Windows PowerShell was not found.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0LocalAnonymizer.ps1"
set "app_exit_code=%errorlevel%"

if not "%app_exit_code%"=="0" (
    echo.
    echo The application stopped with an error. See the messages above.
    pause
)

endlocal & exit /b %app_exit_code%
