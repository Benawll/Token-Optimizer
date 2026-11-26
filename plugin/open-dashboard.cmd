@echo off
set "DASH_PATH=%~dp0..\dashboard.html"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0skills\token-report\scripts\generate-dashboard.ps1" -Latest 20 -OutputPath "%DASH_PATH%"
start "" "%DASH_PATH%"
