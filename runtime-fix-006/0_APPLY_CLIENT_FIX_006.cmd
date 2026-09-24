@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0\1_APPLY_VOSTOK_CLIENT_RUNTIME_FIX_006.ps1"
echo.
pause
