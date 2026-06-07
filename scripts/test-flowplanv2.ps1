param(
  [switch]$SkipInstall,
  [switch]$SkipWebE2E,
  [switch]$Completion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
  param(
    [string]$Name,
    [string]$Status,
    [string]$Details
  )
  $Results.Add([PSCustomObject]@{
    Name = $Name
    Status = $Status
    Details = $Details
  })
}

function Invoke-Gate {
  param(
    [string]$Name,
    [string]$WorkingDirectory,
    [string]$Command,
    [string[]]$Arguments
  )

  Write-Host "== $Name =="
  Push-Location $WorkingDirectory
  try {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "$Command $($Arguments -join ' ') exited with $LASTEXITCODE"
    }
    Add-Result -Name $Name -Status 'PASS' -Details "$Command $($Arguments -join ' ')"
  } catch {
    Add-Result -Name $Name -Status 'FAIL' -Details $_.Exception.Message
    throw
  } finally {
    Pop-Location
  }
}

function Assert-RequiredFile {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    throw "Required file missing: $Path"
  }
}

function Assert-MatrixShape {
  param(
    [string]$Path,
    [switch]$Completion
  )

  $rows = @(Import-Csv $Path)
  $requiredColumns = @(
    'test_id',
    'product_area',
    'module_or_route',
    'user_feature',
    'control_or_api',
    'happy_path_test',
    'failure_path_test',
    'data_integrity_assertion',
    'accessibility_or_layout_assertion',
    'automated_test_file',
    'manual_acceptance_id',
    'status',
    'notes'
  )
  foreach ($column in $requiredColumns) {
    if (-not ($rows | Get-Member -Name $column -MemberType NoteProperty)) {
      throw "Matrix missing column: $column"
    }
  }
  if ($Completion) {
    $openRows = @($rows | Where-Object { $_.status -in @('missing', 'planned') })
    if ($openRows.Count -gt 0) {
      throw "Completion mode found open matrix rows: $($openRows.Count)"
    }
  }
}

function Assert-NoFocusedOrSkippedTests {
  Write-Host '== focused/skipped test scan =='
  $pattern = '\b(describe|it|test)\.(only|skip)\s*\(|\b(fit|xit)\s*\('
  $targetPaths = @('server', 'web_admin', 'client_flutter')
  $includeGlobs = @(
    '*.spec.*',
    '*.test.*',
    '*_test.dart'
  )
  $excludeGlobs = @(
    '!**/node_modules/**',
    '!**/dist/**',
    '!**/coverage/**',
    '!**/build/**',
    '!**/.vite/**',
    '!**/out/**',
    '!**/.output/**',
    '!**/.dart_tool/**',
    '!**/.gradle/**',
    '!**/.pub-cache/**',
    '!**/.next/**',
    '!**/.firebase/**',
    '!**/playwright-report/**',
    '!**/test-results/**',
    '!**/reports/**',
    '!**/report/**',
    '!**/html-report/**',
    '!**/allure-results/**',
    '!**/allure-report/**',
    '!**/generated/**',
    '!**/gen/**',
    '!**/vendor/**',
    '!**/third_party/**',
    '!docs/test-governance/reports/generated/**',
    '!server/server_storage/**',
    '!server/server_storage_*/**',
    '!**/Users*AppDataLocalnpm-cache/**'
  )
  $arguments = @(
    '-n'
  )
  foreach ($glob in ($includeGlobs + $excludeGlobs)) {
    $arguments += @('--glob', $glob)
  }
  $arguments += @($pattern) + $targetPaths

  try {
    $matches = & rg @arguments 2>&1
    $exitCode = $LASTEXITCODE
  } catch {
    Add-Result -Name 'focused/skipped test scan' -Status 'FAIL' -Details $_.Exception.Message
    throw "Focused/skipped test scan command failed: $($_.Exception.Message)"
  }

  if ($exitCode -eq 0) {
    $details = ($matches | Out-String).Trim()
    Write-Host $details
    Add-Result -Name 'focused/skipped test scan' -Status 'FAIL' -Details 'matches found'
    throw 'Focused or skipped tests found. Record reviewed skips in docs/test-governance/feature-test-matrix.csv before committing.'
  }

  if ($exitCode -eq 1) {
    Add-Result -Name 'focused/skipped test scan' -Status 'PASS' -Details 'no matches'
    return
  }

  $errorDetails = ($matches | Out-String).Trim()
  if ([string]::IsNullOrWhiteSpace($errorDetails)) {
    $errorDetails = 'no output'
  }
  Add-Result -Name 'focused/skipped test scan' -Status 'FAIL' -Details "rg exited with $exitCode"
  throw "Focused/skipped test scan command failed with exit code $exitCode`: $errorDetails"
}

function Write-FlutterManualReminder {
  Write-Host ''
  Write-Host '[MANUAL] Flutter commands were not run by Codex.'
  Write-Host 'Run these commands manually:'
  Write-Host 'cd client_flutter'
  Write-Host 'flutter pub get'
  Write-Host 'dart run build_runner build --delete-conflicting-outputs'
  Write-Host 'flutter analyze'
  Write-Host 'flutter test --coverage'
  Write-Host 'flutter test test/goldens'
  Write-Host 'flutter test integration_test'
}

Write-Host '== FlowPlanV2 root quality gate =='

$MatrixPath = Join-Path $RepoRoot 'docs\test-governance\feature-test-matrix.csv'
Assert-RequiredFile $MatrixPath
Assert-MatrixShape -Path $MatrixPath -Completion:$Completion
Assert-NoFocusedOrSkippedTests

Invoke-Gate -Name 'boundary' -WorkingDirectory $RepoRoot -Command 'powershell' -Arguments @('-ExecutionPolicy', 'Bypass', '-File', 'scripts\check-client-server-boundary.ps1', '-FailOnViolation')

$ServerRoot = Join-Path $RepoRoot 'server'
if (-not $SkipInstall) {
  Invoke-Gate -Name 'server:install' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('ci')
}
Invoke-Gate -Name 'server:build' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('run', 'build')
Invoke-Gate -Name 'server:unit' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('run', 'test:unit')
Invoke-Gate -Name 'server:integration' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('run', 'test:integration')
Invoke-Gate -Name 'server:api' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('run', 'test:api')
Invoke-Gate -Name 'server:coverage' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('run', 'test:coverage')

$WebRoot = Join-Path $RepoRoot 'web_admin'
if (-not $SkipInstall) {
  Invoke-Gate -Name 'web:install' -WorkingDirectory $WebRoot -Command 'npm' -Arguments @('ci')
}
Invoke-Gate -Name 'web:build' -WorkingDirectory $WebRoot -Command 'npm' -Arguments @('run', 'build')
Invoke-Gate -Name 'web:unit' -WorkingDirectory $WebRoot -Command 'npm' -Arguments @('run', 'test')
Invoke-Gate -Name 'web:coverage' -WorkingDirectory $WebRoot -Command 'npm' -Arguments @('run', 'test:coverage')
if (-not $SkipWebE2E) {
  Invoke-Gate -Name 'web:e2e' -WorkingDirectory $WebRoot -Command 'npm' -Arguments @('run', 'test:e2e')
}

Write-FlutterManualReminder

Write-Host ''
Write-Host '== Gate Summary =='
$Results | ForEach-Object {
  Write-Host ("[{0}] {1} {2}" -f $_.Status, $_.Name, $_.Details)
}
Write-Host '[MANUAL] Flutter validation: PENDING USER RUN'
