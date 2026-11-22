@echo off
cd /d "%~dp0"
start "" "http://localhost:5176"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause
