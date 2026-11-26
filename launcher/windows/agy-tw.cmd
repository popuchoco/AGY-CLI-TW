@echo off
setlocal
where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo [agy-tw] Windows PowerShell not found.
  exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0agy-tw.ps1" %*
exit /b %ERRORLEVEL%
