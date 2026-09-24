@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0\1_APPLY_SERVER_RUNTIME_FIX_006D.ps1"
echo.
pause
