param(
  [ValidateSet('debug', 'release')]
  [string]$Mode = 'debug',

  [int]$ServerPort = 3000,
  [int]$AdminPort = 5173,
  [int]$FlutterWebPort = 8088,
  [string]$EnvFile = '',
  [string]$DatabaseUrl = '',

  [switch]$SkipDbSchema,
  [switch]$SkipServer,
  [switch]$SkipAdmin,
  [switch]$SkipFlutterWindows,
  [switch]$SkipFlutterWebBuild,
  [switch]$SkipFlutterApk,
  [switch]$SkipRunFlutterWeb,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root = Split-Path -Parent $PSScriptRoot
$ServerDir = Join-Path $Root 'server'
$AdminDir = Join-Path $Root 'web_admin'
$FlutterDir = Join-Path $Root 'client_flutter'
$LogRoot = Join-Path $Root 'logs'
$RunId = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunLogDir = Join-Path $LogRoot $RunId
New-Item -ItemType Directory -Force -Path $RunLogDir | Out-Null

$SummaryLog = Join-Path $RunLogDir 'summary.log'
$TranscriptLog = Join-Path $RunLogDir 'launcher-transcript.log'

Start-Transcript -Path $TranscriptLog -Force | Out-Null

function Write-FlowLog {
  param(
    [string]$Message,
    [string]$Level = 'INFO'
  )
  $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  Write-Host $line
  Add-Content -Path $SummaryLog -Value $line -Encoding UTF8
}

function Resolve-CommandPath {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required command not found: $Name"
  }
  return $cmd.Source
}

function Test-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Directory not found: $Path"
  }
}

function Import-FlowEnvFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return $false
  }
  Write-FlowLog "Loading env file: $Path"
  $lines = Get-Content -LiteralPath $Path
  foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
      continue
    }
    $equals = $trimmed.IndexOf('=')
    if ($equals -le 0) {
      continue
    }
    $key = $trimmed.Substring(0, $equals).Trim()
    $value = $trimmed.Substring($equals + 1).Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    [Environment]::SetEnvironmentVariable($key, $value, 'Process')
  }
  return $true
}

function Wait-HttpReady {
  param(
    [string]$Url,
    [int]$TimeoutSeconds = 90,
    [string]$Name = 'service'
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $lastError = $null
  while ((Get-Date) -lt $deadline) {
    try {
      Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3 | Out-Null
      Write-FlowLog "$Name is ready: $Url"
      return $true
    } catch {
      $lastError = $_.Exception.Message
      Start-Sleep -Seconds 2
    }
  }
  Write-FlowLog "$Name did not become ready within ${TimeoutSeconds}s. Last error: $lastError" 'WARN'
  return $false
}

function Invoke-Step {
  param(
    [string]$Name,
    [string]$WorkingDirectory,
    [string]$FilePath,
    [string[]]$Arguments,
    [hashtable]$Environment = @{}
  )
  Test-Directory $WorkingDirectory
  $safeName = ($Name -replace '[^\w\-]+', '_').Trim('_')
  $log = Join-Path $RunLogDir "$safeName.log"
  Write-FlowLog "START $Name"
  Write-FlowLog "Log: $log"

  $oldLocation = Get-Location
  $oldEnv = @{}
  try {
    Set-Location -LiteralPath $WorkingDirectory
    foreach ($key in $Environment.Keys) {
      $oldEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
      [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], 'Process')
    }
    & $FilePath @Arguments 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) {
      throw "$Name failed with exit code $LASTEXITCODE. See $log"
    }
    Write-FlowLog "DONE $Name"
  } finally {
    foreach ($key in $Environment.Keys) {
      [Environment]::SetEnvironmentVariable($key, $oldEnv[$key], 'Process')
    }
    Set-Location $oldLocation
  }
}

function Start-LongRunningProcess {
  param(
    [string]$Name,
    [string]$WorkingDirectory,
    [string]$Command,
    [hashtable]$Environment = @{}
  )
  Test-Directory $WorkingDirectory
  $safeName = ($Name -replace '[^\w\-]+', '_').Trim('_')
  $log = Join-Path $RunLogDir "$safeName.log"
  $envLines = @()
  foreach ($key in $Environment.Keys) {
    $value = [string]$Environment[$key]
    $envLines += "`$env:$key = '$($value.Replace("'", "''"))'"
  }
  $script = @"
`$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath '$($WorkingDirectory.Replace("'", "''"))'
$($envLines -join "`r`n")
Write-Host '[$Name] working directory: $WorkingDirectory'
Write-Host '[$Name] log: $log'
Write-Host '[$Name] command: $Command'
$Command 2>&1 | Tee-Object -FilePath '$($log.Replace("'", "''"))'
Write-Host ''
Write-Host '[$Name] exited. Press Enter to close this window.'
Read-Host
"@
  $scriptPath = Join-Path $RunLogDir "$safeName.run.ps1"
  Set-Content -Path $scriptPath -Value $script -Encoding UTF8
  Write-FlowLog "START WINDOW $Name"
  Write-FlowLog "Log: $log"
  $process = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) `
    -WorkingDirectory $WorkingDirectory `
    -PassThru
  Write-FlowLog "$Name PID: $($process.Id)"
  return $process
}

try {
  Write-FlowLog "FlowPlan launcher started. Mode=$Mode"
  Write-FlowLog "Root: $Root"
  Write-FlowLog "Logs: $RunLogDir"

  if ($EnvFile.Trim().Length -gt 0) {
    if (-not (Import-FlowEnvFile -Path $EnvFile)) {
      throw "Env file not found: $EnvFile"
    }
  } else {
    $defaultEnvFiles = @(
      (Join-Path $Root 'flowplan.local.env'),
      (Join-Path $ServerDir 'flowplan.local.env'),
      (Join-Path $ServerDir '.env')
    )
    foreach ($candidate in $defaultEnvFiles) {
      if (Import-FlowEnvFile -Path $candidate) {
        break
      }
    }
  }

  if ($DatabaseUrl.Trim().Length -gt 0) {
    [Environment]::SetEnvironmentVariable('DATABASE_URL', $DatabaseUrl.Trim(), 'Process')
  }

  $npm = Resolve-CommandPath 'npm'
  $flutter = Resolve-CommandPath 'flutter'

  Test-Directory $ServerDir
  Test-Directory $AdminDir
  Test-Directory $FlutterDir

  if (-not $SkipServer) {
    if (-not $env:DATABASE_URL) {
      throw 'DATABASE_URL is required. Put it in flowplan.local.env, pass -DatabaseUrl "...", or set $env:DATABASE_URL before running this script.'
    }
    if (-not $SkipDbSchema) {
      Invoke-Step `
        -Name 'server-db-schema' `
        -WorkingDirectory $ServerDir `
        -FilePath $npm `
        -Arguments @('run', 'db:schema') `
        -Environment @{ DATABASE_URL = $env:DATABASE_URL }
    }
    Start-LongRunningProcess `
      -Name 'flowplan-server' `
      -WorkingDirectory $ServerDir `
      -Command 'npm run dev' `
      -Environment @{ PORT = $ServerPort; DATABASE_URL = $env:DATABASE_URL }
    $serverReady = Wait-HttpReady -Url "http://localhost:$ServerPort/api/health" -TimeoutSeconds 120 -Name 'FlowPlan server'
    if (-not $serverReady) {
      throw "FlowPlan server is not ready. Check $(Join-Path $RunLogDir 'flowplan-server.log')"
    }
  }

  if (-not $SkipAdmin) {
    Start-LongRunningProcess `
      -Name 'flowplan-web-admin' `
      -WorkingDirectory $AdminDir `
      -Command 'npm run dev' `
      -Environment @{ PORT = $AdminPort; VITE_PORT = $AdminPort; VITE_API_BASE_URL = "http://localhost:$ServerPort/api" }
    $adminReady = Wait-HttpReady -Url "http://localhost:$AdminPort" -TimeoutSeconds 60 -Name 'FlowPlan web_admin'
    if (-not $adminReady) {
      throw "FlowPlan web_admin is not ready. Check $(Join-Path $RunLogDir 'flowplan-web-admin.log')"
    }
  }

  $flutterModeArg = if ($Mode -eq 'release') { '--release' } else { '--debug' }

  if (-not $SkipFlutterWindows) {
    Invoke-Step `
      -Name "flutter-build-windows-$Mode" `
      -WorkingDirectory $FlutterDir `
      -FilePath $flutter `
      -Arguments @('build', 'windows', $flutterModeArg)
  }

  if (-not $SkipFlutterWebBuild) {
    Invoke-Step `
      -Name "flutter-build-web-$Mode" `
      -WorkingDirectory $FlutterDir `
      -FilePath $flutter `
      -Arguments @('build', 'web', $flutterModeArg)
  }

  if (-not $SkipFlutterApk) {
    Invoke-Step `
      -Name "flutter-build-apk-split-abi-$Mode" `
      -WorkingDirectory $FlutterDir `
      -FilePath $flutter `
      -Arguments @('build', 'apk', $flutterModeArg, '--split-per-abi')
  }

  if (-not $SkipRunFlutterWeb) {
    $runArgs = "flutter run -d chrome --web-port $FlutterWebPort $flutterModeArg"
    Start-LongRunningProcess `
      -Name "flowplan-flutter-web-$Mode" `
      -WorkingDirectory $FlutterDir `
      -Command $runArgs `
      -Environment @{ FLOWPLAN_API_BASE_URL = "http://localhost:$ServerPort/api" }
    Write-FlowLog "Flutter Web should open Chrome automatically. URL is usually http://localhost:$FlutterWebPort"
  }

  Write-FlowLog 'All requested steps finished or started.'
  Write-FlowLog "Summary log: $SummaryLog"
} catch {
  Write-FlowLog $_.Exception.Message 'ERROR'
  Write-FlowLog "Failed. Check logs under: $RunLogDir" 'ERROR'
  exit 1
} finally {
  Stop-Transcript | Out-Null
  if (-not $NoPause) {
    Write-Host ''
    Write-Host "Done. Logs: $RunLogDir"
    Read-Host 'Press Enter to close this launcher'
  }
}
