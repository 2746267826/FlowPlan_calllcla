@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "FLOWPLAN_NPM_CMD="
for %%I in (npm.cmd) do set "FLOWPLAN_NPM_CMD=%%~$PATH:I"
if not defined FLOWPLAN_NPM_CMD (
  echo [FlowPlan] npm.cmd not found in PATH.
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-flowplan-all.ps1" %*
endlocal
