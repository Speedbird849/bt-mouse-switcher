@echo off
title Switch Bluetooth Mouse M336/M337/M535 to Windows
cd /d "%~dp0"
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Switch-Mouse.ps1"
if %ERRORLEVEL% NEQ 0 (
    timeout /t 5
)
