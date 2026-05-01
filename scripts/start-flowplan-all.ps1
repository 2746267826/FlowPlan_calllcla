param(
  [ValidateSet('debug', 'release')]
  [string]$Mode = 'debug',

  [int]$ServerPort = 3200,
  [int]$AdminPort = 5173,
  [int]$FlutterWebPort = 0,
  [string]$EnvFile = '',
  [string]$DatabaseUrl = '',

  [switch]$SkipDbSchema,
  [switch]$SkipServer,
  [switch]$SkipAdmin,
  [switch]$SkipFlutterWindows,
  [switch]$SkipFlutterWebBuild,
  [switch]$SkipFlutterApk,
  [switch]$SkipRunFlutterWeb,
  [switch]$SuppressNodeWarnings,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

try {
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  $OutputEncoding = [System.Text.Encoding]::UTF8
  chcp 65001 | Out-Null
} catch {}

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

function New-FlowText {
  param([string]$Hex)
  $builder = New-Object System.Text.StringBuilder
  foreach ($part in ($Hex -split '\s+')) {
    if ($part.Trim().Length -eq 0) { continue }
    [void]$builder.Append([char][Convert]::ToInt32($part, 16))
  }
  return $builder.ToString()
}

function Join-FlowText {
  param([object[]]$Parts)
  return ($Parts | ForEach-Object { [string]$_ }) -join ''
}

function Quote-PsString {
  param([string]$Value)
  [string]("'{0}'" -f $Value.Replace("'", "''"))
}

function New-WindowWriteHostLine {
  param([string]$Text)
  [string]('Write-Host {0}' -f (Quote-PsString $Text))
}

function Quote-CmdValue {
  param([string]$Value)
  [string]('"{0}"' -f $Value.Replace('"', '""'))
}

function New-CmdSetLine {
  param(
    [string]$Name,
    [string]$Value
  )
  [string]('set "{0}={1}"' -f $Name, $Value.Replace('"', '""'))
}

function Quote-CmdArgument {
  param([string]$Value)
  [string]('"{0}"' -f $Value.Replace('"', '\"').Replace('%', '%%'))
}

function Join-CmdInvocation {
  param(
    [string]$FilePath,
    [string[]]$Arguments
  )
  $parts = @((Quote-CmdArgument $FilePath))
  foreach ($argument in $Arguments) {
    $parts += (Quote-CmdArgument $argument)
  }
  [string]($parts -join ' ')
}

$T = @{
  Module = New-FlowText '6A21 5757 FF1A'
  Directory = New-FlowText '76EE 5F55 FF1A'
  Command = New-FlowText '547D 4EE4 FF1A'
  Access = New-FlowText '8BBF 95EE FF1A'
  Health = New-FlowText '5065 5EB7 68C0 67E5 FF1A'
  Log = New-FlowText '65E5 5FD7 FF1A'
  CloseHow = New-FlowText '5173 95ED 65B9 5F0F FF1A'
  Note = New-FlowText '8BF4 660E FF1A'
  Server = New-FlowText '670D 52A1 7AEF'
  Admin = New-FlowText '7BA1 7406 7AEF'
  WebClient = New-FlowText '0057 0065 0062 0020 5BA2 6237 7AEF'
  ServerDesc = New-FlowText '670D 52A1 7AEF 0020 0041 0050 0049 0020 002F 0020 540C 6B65 0020 002F 0020 6570 636E 5E93 0020 002F 0020 6A21 578B'
  AdminDesc = New-FlowText '0057 0065 0062 0020 7BA1 7406 63A7 5236 53F0 0020 002F 0020 5168 5C40 6570 636E 0020 002F 0020 8BBE 7F6E 0020 002F 0020 65E5 5FD7 0020 002F 0020 8BBE 5907'
  WebDesc = New-FlowText '0046 006C 0075 0074 0074 0065 0072 0020 6D4F 89C8 5668 5BA2 6237 7AEF 0020 002F 0020 65E5 5E38 4EFB 52A1 65E5 7A0B 5165 53E3'
  CloseText = New-FlowText '5728 672C 7A97 53E3 6309 0020 0043 0074 0072 006C 002B 0043 FF1B 82E5 547D 4EE4 5DF2 9000 51FA FF0C 6309 0020 0045 006E 0074 0065 0072 0020 5173 95ED 7A97 53E3 3002'
  Exited = New-FlowText '5DF2 9000 51FA 3002 6309 0020 0045 006E 0074 0065 0072 0020 5173 95ED 672C 7A97 53E3 3002'
  ServerNote = New-FlowText '0044 0045 0050 0030 0031 0039 0030 0020 662F 0020 004E 006F 0064 0065 0020 0032 0034 0020 002B 0020 004E 0065 0073 0074 0020 0077 0061 0074 0063 0068 0020 6A21 5F0F 8B66 544A FF0C 4E0D 662F 81F4 547D 9519 8BEF FF1B 0020 002F 0061 0070 0069 002F 0068 0065 0061 006C 0074 0068 0020 53EF 8BBF 95EE 5373 6B63 5E38 3002'
  AdminNote = New-FlowText '8FD9 662F 0020 0077 0065 0062 005F 0061 0064 006D 0069 006E 0020 7BA1 7406 7AEF FF0C 4E0D 662F 670D 52A1 7AEF FF1B 0020 0045 0041 0044 0044 0052 0049 004E 0055 0053 0045 0020 8868 793A 7AEF 53E3 5DF2 88AB 5360 7528 3002'
  WebNote = New-FlowText '8FD9 662F 7528 6237 4FA7 0020 0046 006C 0075 0074 0074 0065 0072 0020 0057 0065 0062 FF0C 4E0D 662F 7BA1 7406 7AEF FF1B 4F1A 8C03 7528 670D 52A1 7AEF 0020 0041 0050 0049 FF0C 4E0D 91C7 96C6 672C 5730 8FFD 8E2A 3002'
  MissingDatabaseUrl = New-FlowText '7F3A 5C11 0020 0044 0041 0054 0041 0042 0041 0053 0045 005F 0055 0052 004C FF0C 670D 52A1 7AEF 4E0D 4F1A 542F 52A8 3002'
  OpenWindow = New-FlowText '6253 5F00 7A97 53E3 FF1A'
  ReuseService = New-FlowText '5DF2 68C0 6D4B 5230 73B0 6709 670D 52A1 FF0C 590D 7528 5E76 8DF3 8FC7 65B0 7A97 53E3 FF1A'
}

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

function Resolve-NpmCommandPath {
  if ($env:FLOWPLAN_NPM_CMD -and (Test-Path -LiteralPath $env:FLOWPLAN_NPM_CMD)) {
    return $env:FLOWPLAN_NPM_CMD
  }

  $cmd = Get-Command 'npm.cmd' -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  return Resolve-CommandPath 'npm'
}

function Join-PsInvocation {
  param(
    [string]$FilePath,
    [string[]]$Arguments
  )
  $parts = @('&', (Quote-PsString $FilePath))
  foreach ($argument in $Arguments) {
    $parts += (Quote-PsString $argument)
  }
  [string]($parts -join ' ')
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

function Test-HttpReadyNow {
  param([string]$Url)
  $oldErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3 | Out-Null
    return $true
  } catch {
    return $false
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
}

function Get-PortOwnerSummary {
  param([int]$Port)
  $oldErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'SilentlyContinue'
    $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $connections) {
      return ''
    }
    $items = @()
    foreach ($connection in $connections) {
      $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
      $processName = 'unknown'
      if ($process -and $process.ProcessName) {
        $processName = $process.ProcessName
      }
      $items += 'PID {0} / {1}' -f $connection.OwningProcess, $processName
    }
    return ($items | Select-Object -Unique) -join '; '
  } catch {
    return ''
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
}

function Test-PortBeforeStart {
  param(
    [string]$ModuleName,
    [int]$Port,
    [string]$Url,
    [string]$SwitchHint
  )
  if (Test-HttpReadyNow -Url $Url) {
    Write-FlowLog ((Join-FlowText @($T.ReuseService, $Url))) 'WARN'
    return 'ready'
  }
  $owner = Get-PortOwnerSummary -Port $Port
  if ($owner.Trim().Length -gt 0) {
    $message = @(
      "Port is occupied: module=$ModuleName, port=$Port, url=$Url, status=not-ready",
      "Owner process: $owner",
      "Actions:",
      "1. Close the old FlowPlan window",
      "2. Use $SwitchHint to choose another port",
      "3. Stop the owner process manually"
    ) -join "`n"
    throw $message
  }
  return 'free'
}

function Write-CommandBlock {
  param(
    [string]$Title,
    [string[]]$Lines
  )
  Write-Host ''
  Write-Host $Title
  Add-Content -Path $SummaryLog -Value '' -Encoding UTF8
  Add-Content -Path $SummaryLog -Value $Title -Encoding UTF8
  foreach ($line in $Lines) {
    Write-Host $line
    Add-Content -Path $SummaryLog -Value $line -Encoding UTF8
  }
}

function Write-CopyableCommands {
  param([string]$FlutterModeArg)
  Write-Host ''
  Write-Host '================ FlowPlan copyable commands ================'
  Add-Content -Path $SummaryLog -Value '' -Encoding UTF8
  Add-Content -Path $SummaryLog -Value '================ FlowPlan copyable commands ================' -Encoding UTF8

  Write-CommandBlock '# 1. database schema' @(
    ('cd /d ' + (Quote-CmdValue $ServerDir)),
    'npm run db:schema'
  )
  Write-CommandBlock '# 2. server' @(
    ('cd /d ' + (Quote-CmdValue $ServerDir)),
    (New-CmdSetLine -Name 'DATABASE_URL' -Value ([string]$env:DATABASE_URL)),
    (New-CmdSetLine -Name 'PORT' -Value ([string]$ServerPort)),
    'npm run dev'
  )
  Write-CommandBlock '# 3. web admin' @(
    ('cd /d ' + (Quote-CmdValue $AdminDir)),
    (New-CmdSetLine -Name 'PORT' -Value ([string]$AdminPort)),
    (New-CmdSetLine -Name 'VITE_PORT' -Value ([string]$AdminPort)),
    (New-CmdSetLine -Name 'VITE_API_BASE_URL' -Value "http://localhost:$ServerPort/api"),
    'npm run dev'
  )
  Write-CommandBlock '# 4. Flutter Windows build' @(
    ('cd /d ' + (Quote-CmdValue $FlutterDir)),
    "flutter build windows $FlutterModeArg"
  )
  Write-CommandBlock '# 5. Flutter Web build' @(
    ('cd /d ' + (Quote-CmdValue $FlutterDir)),
    "flutter build web $FlutterModeArg"
  )
  Write-CommandBlock '# 6. Flutter APK split ABI' @(
    ('cd /d ' + (Quote-CmdValue $FlutterDir)),
    "flutter build apk $FlutterModeArg --split-per-abi"
  )
  Write-CommandBlock '# 7. Flutter Web run' @(
    ('cd /d ' + (Quote-CmdValue $FlutterDir)),
    (New-CmdSetLine -Name 'FLOWPLAN_API_BASE_URL' -Value "http://localhost:$ServerPort/api"),
    "flutter run -d chrome --web-port $FlutterWebPort $FlutterModeArg"
  )
  Write-Host '============================================================='
  Add-Content -Path $SummaryLog -Value '=============================================================' -Encoding UTF8
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
    $oldErrorActionPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      $cmdInvocation = (Join-CmdInvocation -FilePath $FilePath -Arguments $Arguments) + ' 2>&1'
      & $env:ComSpec /d /c $cmdInvocation | Tee-Object -FilePath $log
      $exitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $oldErrorActionPreference
    }
    if ($exitCode -ne 0) {
      throw "$Name failed with exit code $exitCode. See $log"
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
    [string]$DisplayName,
    [string]$WindowTitle,
    [string]$ModuleDescription,
    [string]$Url,
    [string]$HealthUrl = '',
    [string]$CommonNote = '',
    [string]$WorkingDirectory,
    [string]$Command,
    [hashtable]$Environment = @{}
  )
  Test-Directory $WorkingDirectory
  $safeName = ($Name -replace '[^\w\-]+', '_').Trim('_')
  $log = Join-Path $RunLogDir "$safeName.log"
  $header = "================ $DisplayName ================"
  $footer = '================================================='

  $cmdParts = @(
    ('title ' + $WindowTitle),
    'chcp 65001 >nul',
    ('cd /d ' + (Quote-CmdValue $WorkingDirectory))
  )
  foreach ($key in $Environment.Keys) {
    $cmdParts += (New-CmdSetLine -Name $key -Value ([string]$Environment[$key]))
  }
  $cmdParts += @(
    ('echo ' + $header),
    ('echo ' + (Join-FlowText @($T.Module, $ModuleDescription))),
    ('echo ' + (Join-FlowText @($T.Directory, $WorkingDirectory))),
    ('echo ' + (Join-FlowText @($T.Command, $Command))),
    ('echo ' + (Join-FlowText @($T.Access, $Url))),
    ('echo ' + (Join-FlowText @($T.Health, $HealthUrl))),
    ('echo ' + (Join-FlowText @($T.Log, $log))),
    ('echo ' + (Join-FlowText @($T.CloseHow, $T.CloseText))),
    ('echo ' + (Join-FlowText @($T.Note, $CommonNote))),
    ('echo ' + $footer),
    ('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { $ErrorActionPreference = ''Continue''; ' + $Command + ' 2>&1 | Tee-Object -FilePath ' + (Quote-PsString $log) + '; exit $LASTEXITCODE }"'),
    'echo.',
    ('echo [' + $DisplayName + '] ' + $T.Exited)
  )

  Write-FlowLog (Join-FlowText @($T.OpenWindow, $DisplayName))
  Write-FlowLog "Log: $log"
  Write-FlowLog "Command: $Command"
  $process = Start-Process -FilePath 'cmd.exe' `
    -ArgumentList @('/k', ($cmdParts -join ' & ')) `
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

  if ($SuppressNodeWarnings) {
    [Environment]::SetEnvironmentVariable('NODE_NO_WARNINGS', '1', 'Process')
    Write-FlowLog 'SuppressNodeWarnings enabled: Node warnings will be hidden.' 'WARN'
  }

  $npm = Resolve-NpmCommandPath
  $flutter = Resolve-CommandPath 'flutter'
  $npmRunDev = Join-PsInvocation -FilePath $npm -Arguments @('run', 'dev')

  Test-Directory $ServerDir
  Test-Directory $AdminDir
  Test-Directory $FlutterDir

  $flutterModeArg = if ($Mode -eq 'release') { '--release' } else { '--debug' }
  Write-CopyableCommands -FlutterModeArg $flutterModeArg

  if (-not $SkipServer) {
    if (-not $env:DATABASE_URL) {
      throw (Join-FlowText @($T.MissingDatabaseUrl, ' flowplan.local.env / -DatabaseUrl / $env:DATABASE_URL'))
    }
    if (-not $SkipDbSchema) {
      Invoke-Step `
        -Name 'server-db-schema' `
        -WorkingDirectory $ServerDir `
        -FilePath $npm `
        -Arguments @('run', 'db:schema') `
        -Environment @{ DATABASE_URL = $env:DATABASE_URL }
    }
    $serverHealthUrl = "http://localhost:$ServerPort/api/health"
    $serverPrecheck = Test-PortBeforeStart `
      -ModuleName 'FlowPlan Server' `
      -Port $ServerPort `
      -Url $serverHealthUrl `
      -SwitchHint "-ServerPort $($ServerPort + 1)"
    if ($serverPrecheck -ne 'ready') {
      $serverEnv = @{ PORT = $ServerPort; DATABASE_URL = $env:DATABASE_URL }
      if ($SuppressNodeWarnings) { $serverEnv.NODE_NO_WARNINGS = '1' }
      $serverDisplay = Join-FlowText @('FlowPlan ', $T.Server)
      Start-LongRunningProcess `
        -Name 'flowplan-server' `
        -DisplayName $serverDisplay `
        -WindowTitle "$serverDisplay - Port $ServerPort" `
        -ModuleDescription $T.ServerDesc `
        -Url "http://localhost:$ServerPort/api" `
        -HealthUrl $serverHealthUrl `
        -CommonNote $T.ServerNote `
        -WorkingDirectory $ServerDir `
        -Command $npmRunDev `
        -Environment $serverEnv
      $serverReady = Wait-HttpReady -Url $serverHealthUrl -TimeoutSeconds 120 -Name 'FlowPlan Server'
      if (-not $serverReady) {
        throw "FlowPlan Server is not ready. Check log: $(Join-Path $RunLogDir 'flowplan-server.log')"
      }
    }
  }

  if (-not $SkipAdmin) {
    $adminUrl = "http://localhost:$AdminPort"
    $adminPrecheck = Test-PortBeforeStart `
      -ModuleName 'FlowPlan Admin' `
      -Port $AdminPort `
      -Url $adminUrl `
      -SwitchHint "-AdminPort $($AdminPort + 1)"
    if ($adminPrecheck -ne 'ready') {
      $adminEnv = @{ PORT = $AdminPort; VITE_PORT = $AdminPort; VITE_API_BASE_URL = "http://localhost:$ServerPort/api" }
      if ($SuppressNodeWarnings) { $adminEnv.NODE_NO_WARNINGS = '1' }
      $adminDisplay = Join-FlowText @('FlowPlan ', $T.Admin)
      Start-LongRunningProcess `
        -Name 'flowplan-web-admin' `
        -DisplayName $adminDisplay `
        -WindowTitle "$adminDisplay - Port $AdminPort" `
        -ModuleDescription $T.AdminDesc `
        -Url $adminUrl `
        -HealthUrl $adminUrl `
        -CommonNote $T.AdminNote `
        -WorkingDirectory $AdminDir `
        -Command $npmRunDev `
        -Environment $adminEnv
      $adminReady = Wait-HttpReady -Url $adminUrl -TimeoutSeconds 60 -Name 'FlowPlan Admin'
      if (-not $adminReady) {
        throw "FlowPlan Admin is not ready. Check log: $(Join-Path $RunLogDir 'flowplan-web-admin.log')"
      }
    }
  }

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
    $flutterWebUrl = "http://localhost:$FlutterWebPort"
    $flutterWebPrecheck = Test-PortBeforeStart `
      -ModuleName 'FlowPlan Flutter Web' `
      -Port $FlutterWebPort `
      -Url $flutterWebUrl `
      -SwitchHint "-FlutterWebPort $($FlutterWebPort + 1)"
    $runArgs = "flutter run -d chrome --web-port $FlutterWebPort $flutterModeArg"
    if ($flutterWebPrecheck -ne 'ready') {
      $webDisplay = Join-FlowText @('FlowPlan ', $T.WebClient)
      Start-LongRunningProcess `
        -Name "flowplan-flutter-web-$Mode" `
        -DisplayName $webDisplay `
        -WindowTitle "$webDisplay - Port $FlutterWebPort" `
        -ModuleDescription $T.WebDesc `
        -Url $flutterWebUrl `
        -HealthUrl $flutterWebUrl `
        -CommonNote $T.WebNote `
        -WorkingDirectory $FlutterDir `
        -Command $runArgs `
        -Environment @{ FLOWPLAN_API_BASE_URL = "http://localhost:$ServerPort/api" }
      Write-FlowLog "Flutter Web will try to open Chrome automatically. URL: $flutterWebUrl"
    }
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
