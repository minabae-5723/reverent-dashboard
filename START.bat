@echo off
chcp 65001 >nul
title Reverent Partners Dashboard
cd /d "%~dp0"

:loop
echo [%date% %time%] Starting server...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
echo.
echo [%date% %time%] Server stopped. Restarting in 3 seconds... (Ctrl+C to exit)
timeout /t 3 /nobreak >nul
goto loop
