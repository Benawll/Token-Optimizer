@echo off
set "DASH_PATH=%~dp0..\dashboard.html"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0skills\token-report\scripts\serve-dashboard.ps1" -Port 4891 -Latest 20 -DashboardPath "%DASH_PATH%"
