@echo off
set SCRIPT_DIR=%~dp0
powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%installer_logic.ps1" -SourcePath "%SCRIPT_DIR%.." -TargetPath "%~1" -DesktopFlag "%~2" -StartMenuFlag "%~3" -LaunchFlag "%~4"
