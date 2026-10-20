@echo off
title SafeBoost (console)
:: Text-menu version of SafeBoost, also supports command-line options (see README)
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SafeBoost.ps1" %*
pause
