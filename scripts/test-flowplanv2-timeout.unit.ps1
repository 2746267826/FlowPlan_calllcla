$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'test-flowplanv2.ps1'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$scriptText = Get-Content -Path $scriptPath -Raw
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
  throw "Failed to parse test-flowplanv2.ps1: $($parseErrors[0].Message)"
}

if ($scriptText -notlike '*Completion mode cannot skip dependency install checks*') {
  throw 'Completion mode does not reject -SkipInstall.'
}

if ($scriptText -notlike '*Completion mode requires -FlutterIntegrationDevice windows*') {
  throw 'Completion mode does not require the Windows Flutter integration device.'
}

if ($scriptText -notlike '*--no-ignore*') {
  throw 'Focused/skipped scan must not rely on repository ignore rules for artifact exclusions.'
}

if ($scriptText -notlike '*markTestSkipped*') {
  throw 'Focused/skipped scan does not detect Dart runtime skipped tests.'
}

$workflowPath = Join-Path $repoRoot '.github\workflows\root-quality-gate.yml'
if (-not (Test-Path -LiteralPath $workflowPath)) {
  throw 'Root quality gate workflow is missing.'
}
$workflowText = Get-Content -Path $workflowPath -Raw
if ($workflowText -notmatch '(?m)^\s*completion:\s*$') {
  throw 'Root quality gate workflow does not define a completion job.'
}
if ($workflowText -notlike '*scripts/test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows*') {
  throw 'Root quality gate workflow does not run the completion gate with the Windows Flutter integration device.'
}
if ($workflowText -match 'scripts/test-flowplanv2\.ps1[^\r\n]*-Completion[^\r\n]*-(SkipInstall|SkipWebE2E|SkipFlutterIntegration|GovernanceOnly)') {
  throw 'Root quality gate workflow passes a skip or governance-only flag to the completion gate invocation.'
}

$timeoutGateIndex = $scriptText.IndexOf("Invoke-Gate -Name 'root:gate timeout unit'")
if ($timeoutGateIndex -lt 0) {
  throw 'root:gate timeout unit invocation not found.'
}

$governanceOnlyReturn = [regex]::Match($scriptText, '(?s)if\s*\(\$GovernanceOnly\)\s*\{.*?\breturn\b.*?\}')
if (-not $governanceOnlyReturn.Success) {
  throw 'GovernanceOnly return block not found.'
}

if ($timeoutGateIndex -gt $governanceOnlyReturn.Index) {
  throw 'GovernanceOnly returns before root:gate timeout unit runs.'
}

$invokeGateAst = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Gate'
}, $true)

if ($null -eq $invokeGateAst) {
  throw 'Invoke-Gate function not found.'
}

function Import-ScriptFunction {
  param([string]$Name)

  $functionAst = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
  }, $true)

  if ($null -eq $functionAst) {
    throw "$Name function not found."
  }

  Invoke-Expression "function global:$Name $($functionAst.Body.Extent.Text)"
}

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

Invoke-Expression "function global:Invoke-Gate $($invokeGateAst.Body.Extent.Text)"
Import-ScriptFunction -Name 'Resolve-GateCommand'
Import-ScriptFunction -Name 'Assert-RequiredFile'
Import-ScriptFunction -Name 'Assert-RequiredColumns'
Import-ScriptFunction -Name 'Assert-RequiredCells'
Import-ScriptFunction -Name 'Assert-UniqueColumn'
Import-ScriptFunction -Name 'Assert-AllowedStatuses'
Import-ScriptFunction -Name 'Assert-FeatureMatrix'
Import-ScriptFunction -Name 'Assert-ManualAcceptanceMatrix'
Import-ScriptFunction -Name 'Get-RootGateExclusionPatterns'
Import-ScriptFunction -Name 'Assert-ReviewedCoverageExclusionPatterns'
Import-ScriptFunction -Name 'ConvertTo-GovernanceGlobRegex'
Import-ScriptFunction -Name 'Test-PathMatchesPattern'
Import-ScriptFunction -Name 'ConvertTo-RepoRelativePath'
Import-ScriptFunction -Name 'Get-ReviewedCoverageExclusionPattern'
Import-ScriptFunction -Name 'Test-ReviewedCoverageExclusionPath'
Import-ScriptFunction -Name 'Get-DartLcovSummary'
Import-ScriptFunction -Name 'Assert-DartLcovCoverage'

$start = Get-Date
$failedAsExpected = $false
try {
  Invoke-Gate `
    -Name 'timeout probe' `
    -WorkingDirectory $PSScriptRoot `
    -Command 'powershell' `
    -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 5') `
    -TimeoutSeconds 1
} catch {
  $failedAsExpected = $_.Exception.Message -like '*timed out*'
}
$elapsed = ((Get-Date) - $start).TotalSeconds

if (-not $failedAsExpected) {
  throw 'Invoke-Gate did not fail with a timeout error.'
}

if ($elapsed -gt 3) {
  throw "Invoke-Gate timeout took too long: $([math]::Round($elapsed, 2)) seconds."
}

$failure = @($Results | Where-Object { $_.Name -eq 'timeout probe' -and $_.Status -eq 'FAIL' })
if ($failure.Count -ne 1) {
  throw 'Invoke-Gate did not record one failed timeout result.'
}

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "flowplanv2-lcov-unit-$([System.Guid]::NewGuid().ToString('N'))"
$flutterRoot = Join-Path $tmpRoot 'client_flutter'
$coverageDir = Join-Path $flutterRoot 'coverage'
New-Item -ItemType Directory -Force -Path $coverageDir | Out-Null
$lcovPath = Join-Path $coverageDir 'lcov.info'
Set-Content -Path $lcovPath -Value @(
  'TN:'
  'SF:lib/covered.dart'
  'DA:1,1'
  'DA:2,0'
  'end_of_record'
  'TN:'
  'SF:lib/features/reports/report_repository.dart'
  'DA:1,0'
  'end_of_record'
  'TN:'
  'SF:lib/generated.g.dart'
  'DA:1,0'
  'end_of_record'
) -Encoding UTF8

$coverageRows = @(
  [PSCustomObject]@{
    pattern = 'client_flutter/**.g.dart'
    owner_or_module = 'client_flutter'
    status = 'reviewed'
  },
  [PSCustomObject]@{
    pattern = '**/reports/**'
    owner_or_module = 'root_gate'
    status = 'reviewed'
  }
)

try {
  $summary = Get-DartLcovSummary -LcovPath $lcovPath -FlutterRoot $flutterRoot -RepoRoot $tmpRoot -CoverageRows $coverageRows
  if ($summary.TotalLines -ne 2 -or $summary.CoveredLines -ne 1) {
    throw "Expected raw LCOV summary to apply all reviewed rows and count 1/2 included lines, got $($summary.CoveredLines)/$($summary.TotalLines)."
  }
  if ([math]::Round($summary.LineCoveragePercent, 2) -ne 50.00) {
    throw "Expected LCOV summary to report 50.00%, got $($summary.LineCoveragePercent)%."
  }

  $lcovFailedAsExpected = $false
  try {
    Assert-DartLcovCoverage `
      -FlutterRoot $flutterRoot `
      -RepoRoot $tmpRoot `
      -CoverageRows $coverageRows `
      -MinimumLineCoveragePercent 100
  } catch {
    $lcovFailedAsExpected = $_.Exception.Message -like '*33.33%*' -and $_.Exception.Message -like '*1/3*'
  }
  if (-not $lcovFailedAsExpected) {
    throw 'Assert-DartLcovCoverage did not fail with client_flutter-only exclusions and the real low LCOV percentage.'
  }

  $rootExclusions = @(Get-RootGateExclusionPatterns)
  if ($rootExclusions.Count -eq 0) {
    throw 'Root gate exclusion pattern list is empty.'
  }

  if ('**/reports/**' -in $rootExclusions -or '**/report/**' -in $rootExclusions) {
    throw 'Root gate exclusions must not exclude broad reports directories because they match client Flutter product code.'
  }

  if (-not ('**/.codex-tmp/**' -in $rootExclusions) -or -not ('**/coverage-*/**' -in $rootExclusions)) {
    throw 'Root gate exclusions must include explicit reviewed temp and coverage shard artifact patterns.'
  }

  if (-not (Test-PathMatchesPattern -Path 'client_flutter/lib/generated.g.dart' -Pattern 'client_flutter/**.g.dart')) {
    throw 'Dart generated-file exclusion pattern did not match a generated file.'
  }

  if (Test-ReviewedCoverageExclusionPath -Rows @($coverageRows | Where-Object { $_.owner_or_module -eq 'client_flutter' }) -Path 'client_flutter/lib/features/reports/report_repository.dart') {
    throw 'client_flutter LCOV exclusions must not exclude reports product code.'
  }

  $alignmentRows = @(
    [PSCustomObject]@{
      pattern = '**/coverage/**'
      status = 'reviewed'
    },
    [PSCustomObject]@{
      pattern = '**/build/**'
      status = 'planned'
    }
  )
  $alignmentFailedAsExpected = $false
  try {
    Assert-ReviewedCoverageExclusionPatterns -Rows $alignmentRows -Patterns @('**/coverage/**', '**/build/**', '**/dist/**')
  } catch {
    $alignmentFailedAsExpected = $_.Exception.Message -like '*not reviewed: **/build/***' -and $_.Exception.Message -like '*missing: **/dist/***'
  }
  if (-not $alignmentFailedAsExpected) {
    throw 'Coverage exclusion alignment did not fail for planned or missing actual exclusions.'
  }

  $manualRows = @(
    [PSCustomObject]@{
      manual_id = 'MANUAL-PENDING-001'
      status = 'pending-user'
    }
  )
  $featureRows = @(
    [PSCustomObject]@{
      test_id = 'FEATURE-MANUAL-001'
      product_area = 'client_flutter'
      module_or_route = 'manual'
      user_feature = 'Manual pending workflow'
      control_or_api = 'manual evidence'
      happy_path_test = 'automated skeleton exists'
      failure_path_test = 'manual failure still pending'
      data_integrity_assertion = 'manual data check pending'
      accessibility_or_layout_assertion = 'manual layout check pending'
      automated_test_file = 'client_flutter/test/example_test.dart'
      manual_acceptance_id = 'MANUAL-PENDING-001'
      status = 'verified'
      notes = 'This row must not be verified while manual acceptance is pending-user.'
    }
  )
  $manualPendingFailedAsExpected = $false
  try {
    Assert-FeatureMatrix -Rows $featureRows -ManualRows $manualRows
  } catch {
    $manualPendingFailedAsExpected = $_.Exception.Message -like '*manual acceptance MANUAL-PENDING-001 is pending-user*'
  }
  if (-not $manualPendingFailedAsExpected) {
    throw 'Feature matrix did not reject a verified row with pending manual acceptance.'
  }

  $manualRowsMissingDate = @(
    [PSCustomObject]@{
      manual_id = 'MANUAL-PASSING-NODATE-001'
      area = 'client_flutter'
      scenario = 'Passing evidence without date'
      required_environment = 'Windows desktop'
      buttons_controls = 'save button'
      status_states = 'success state'
      error_paths = 'validation failure'
      side_effects = 'audit row'
      steps = 'Run the acceptance steps'
      evidence = 'command output attached without a date'
      status = 'passing'
    }
  )
  $manualDateFailedAsExpected = $false
  try {
    Assert-ManualAcceptanceMatrix -Rows $manualRowsMissingDate
  } catch {
    $manualDateFailedAsExpected = $_.Exception.Message -like '*dated evidence note*'
  }
  if (-not $manualDateFailedAsExpected) {
    throw 'Manual acceptance matrix did not reject passing evidence without a date.'
  }
} finally {
  Remove-Item -Path $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Invoke-Gate timeout, CI workflow, Dart LCOV, exclusion alignment, manual evidence, and manual-pending matrix behavior passed.'
