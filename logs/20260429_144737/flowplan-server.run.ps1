$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 | Out-Null } catch {}
try { $Host.UI.RawUI.WindowTitle = 
'FlowPlan 服务端 - Port 3000'
 } catch {}
Set-Location -LiteralPath 
'C:\Users\a2746\Desktop\calll260426\server'
$env:DATABASE_URL = 'postgresql://postgres:060331@localhost:5432/flowplan'
$env:PORT = '3000'
Write-Host '================ FlowPlan 服务端 ================'
Write-Host '模块：服务端 API / 同步 / 数据库 / 模型'
Write-Host '目录：C:\Users\a2746\Desktop\calll260426\server'
Write-Host '命令：npm run dev'
Write-Host '访问：http://localhost:3000/api'
Write-Host '健康检查：http://localhost:3000/api/health'
Write-Host '日志：C:\Users\a2746\Desktop\calll260426\logs\20260429_144737\flowplan-server.log'
Write-Host '关闭方式：在本窗口按 Ctrl+C；若命令已退出，按 Enter 关闭窗口。'
Write-Host '说明：DEP0190 是 Node 24 + Nest watch 模式警告，不是致命错误； /api/health 可访问即正常。'
Write-Host '================================================='
npm run dev 2>&1 | Tee-Object -FilePath 
'C:\Users\a2746\Desktop\calll260426\logs\20260429_144737\flowplan-server.log'
Write-Host ''
Write-Host '[FlowPlan 服务端] 已退出。按 Enter 关闭本窗口。'
Read-Host | Out-Null
