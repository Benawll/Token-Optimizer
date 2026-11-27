@echo off
set "DASH_PATH=%USERPROFILE%\.gemini\config\plugins\dashboard.html"
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.gemini\config\plugins\token-optimizer\skills\token-report\scripts\serve-dashboard.ps1" -Port 4891 -Latest 20 -DashboardPath "%DASH_PATH%"