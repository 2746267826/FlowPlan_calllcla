@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "FLOWPLANV2_NPM_CMD="
for %%I in (npm.cmd) do set "FLOWPLANV2_NPM_CMD=%%~$PATH:I"
if not defined FLOWPLANV2_NPM_CMD (
  echo [FlowPlanV2] npm.cmd not found in PATH.
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-flowplanv2-all.ps1" %*
endlocal
