@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title Local Anonymizer - Self Test

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-Anonymizer.ps1"
set "test_exit_code=%errorlevel%"

echo.
if "%test_exit_code%"=="0" (
    echo All tests passed.
) else (
    echo Tests failed. Send this window screenshot to the developer.
)
pause

endlocal & exit /b %test_exit_code%
