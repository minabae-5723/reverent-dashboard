@echo off
chcp 65001 >nul
title Reverent Partners Dashboard
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
echo.
echo Server stopped.
pause
