@echo off
title SafeBoost
:: Ask for admin rights if we don't have them yet
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SafeBoost.ps1" %*
pause
