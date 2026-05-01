$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { $Host.UI.RawUI.WindowTitle = 'FlowPlan 鏈嶅姟绔?Server - Port 3000' } catch {}
Set-Location -LiteralPath 'C:\Users\a2746\Desktop\calll260426\server'
$env:DATABASE_URL = 'postgresql://postgres:060331@localhost:5432/flowplan'
$env:PORT = '3000'
Write-Host "================ FlowPlan 鏈嶅姟绔?Server ================"
Write-Host "妯″潡锛?ModuleDescription"
Write-Host "鐩綍锛?WorkingDirectory"
Write-Host "鍛戒护锛?Command"
Write-Host "璁块棶锛?Url"
Write-Host "鍋ュ悍妫€鏌ワ細http://localhost:3000/api/health"
Write-Host "鏃ュ織锛?log"
Write-Host "鍏抽棴鏂瑰紡锛氬湪鏈獥鍙ｆ寜 Ctrl+C锛涜嫢鍛戒护宸查€€鍑猴紝鎸?Enter 鍏抽棴绐楀彛."
Write-Host "璇存槑锛?CommonNote"
Write-Host "================================================="
npm run dev 2>&1 | Tee-Object -FilePath 'C:\Users\a2746\Desktop\calll260426\logs\20260429_142214\flowplan-server.log'
Write-Host ''
Write-Host "[FlowPlan 鏈嶅姟绔?Server] 宸查€€鍑? 鎸?Enter 鍏抽棴鏈獥鍙?"
Read-Host | Out-Null
