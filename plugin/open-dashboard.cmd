@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0skills\token-report\scripts\generate-dashboard.ps1" -Latest 15 -Open
