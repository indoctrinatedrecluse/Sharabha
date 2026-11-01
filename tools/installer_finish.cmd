@echo off
set SCRIPT_DIR=%~dp0
powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%installer_finish.ps1" -LaunchFlag "%~1"
