@echo off
chcp 65001 >nul
setlocal
set "PS1=%~dp0scripts\collect-crash-info.ps1"
if not exist "%PS1%" set "PS1=%~dp0collect-crash-info.ps1"
if not exist "%PS1%" (
  echo Cannot find collect-crash-info.ps1 - unzip the whole patch folder first.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
endlocal
