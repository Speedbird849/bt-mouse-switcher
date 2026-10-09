@echo off
title Switch Logitech M337 to Windows
cd /d "%~dp0"
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Switch-Mouse.ps1"
if %ERRORLEVEL% NEQ 0 (
    timeout /t 5
)
