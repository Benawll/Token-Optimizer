@echo off
set "DASH_PATH=%~dp0dashboard.html"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0plugin\skills\token-report\scripts\serve-dashboard.ps1" -Port 4891 -Latest 20 -DashboardPath "%DASH_PATH%"
