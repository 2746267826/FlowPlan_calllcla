param(
  [switch]$SkipInstall,
  [switch]$SkipWebE2E,
  [ValidateSet('chrome', 'edge', 'windows')]
  [string]$FlutterIntegrationDevice = 'windows',
  [switch]$SkipFlutterIntegration,
  [switch]$Completion,
  [switch]$GovernanceOnly,
  [ValidateRange(1, 86400)]
  [int]$GateTimeoutSeconds = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Completion -and $GovernanceOnly) {
  throw 'Completion mode must run the full root gate and cannot be combined with -GovernanceOnly.'
}

if ($Completion -and $SkipWebE2E) {
  throw 'Completion mode cannot skip Web Admin E2E tests. Remove -SkipWebE2E and run the full root gate.'
}

if ($Completion -and $SkipInstall) {
  throw 'Completion mode cannot skip dependency install checks. Remove -SkipInstall and run the full root gate.'
}

if ($Completion -and $SkipFlutterIntegration) {
  throw 'Completion mode cannot skip Flutter integration tests. Remove -SkipFlutterIntegration and run the full root gate.'
}

if ($Completion -and $FlutterIntegrationDevice -ne 'windows') {
  throw 'Completion mode requires -FlutterIntegrationDevice windows. Chrome and Edge runs are diagnostic only.'
}

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

function Resolve-GateCommand {
  param([string]$Command)

  if ([string]::IsNullOrWhiteSpace($Command)) {
    throw 'Gate command is blank.'
  }

  if ([System.IO.Path]::IsPathRooted($Command) -or $Command.Contains('\') -or $Command.Contains('/')) {
    return $Command
  }

  $pathExtensions = @($env:PATHEXT -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($pathExtensions.Count -eq 0) {
    $pathExtensions = @('.COM', '.EXE', '.BAT', '.CMD')
  }

  $candidateNames = New-Object System.Collections.Generic.List[string]
  if ([System.IO.Path]::HasExtension($Command)) {
    $candidateNames.Add($Command) | Out-Null
  } else {
    foreach ($extension in $pathExtensions) {
      $candidateNames.Add("$Command$extension") | Out-Null
    }
  }

  foreach ($pathEntry in @($env:PATH -split ';')) {
    if ([string]::IsNullOrWhiteSpace($pathEntry)) {
      continue
    }
    foreach ($candidateName in $candidateNames) {
      $candidatePath = Join-Path $pathEntry $candidateName
      if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
        return (Resolve-Path -LiteralPath $candidatePath).Path
      }
    }
  }

  $resolved = Get-Command $Command -ErrorAction Stop
  if ($resolved.CommandType -eq 'Application') {
    return $resolved.Source
  }
  throw "Gate command $Command resolved to $($resolved.CommandType), not an executable application."
}

function Invoke-Gate {
  param(
    [string]$Name,
    [string]$WorkingDirectory,
    [string]$Command,
    [string[]]$Arguments,
    [ValidateRange(1, 86400)]
    [int]$TimeoutSeconds = $GateTimeoutSeconds
  )

  Write-Host "== $Name =="
  $gateStart = Get-Date
  try {
    $quoteArgument = {
      param([string]$Argument)
      if ($null -eq $Argument -or $Argument -eq '') {
        return '""'
      }
      if ($Argument -notmatch '[\s"]') {
        return $Argument
      }
      return '"' + $Argument.Replace('"', '\"') + '"'
    }
    $argumentLine = ($Arguments | ForEach-Object { & $quoteArgument $_ }) -join ' '
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $resolvedCommand = Resolve-GateCommand -Command $Command
    $processInfo.FileName = $resolvedCommand
    $processInfo.Arguments = $argumentLine
    $processInfo.WorkingDirectory = $WorkingDirectory
    $processInfo.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::Start($processInfo)
    if ($null -eq $process) {
      throw "Failed to start $Command $($Arguments -join ' ')"
    }

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      $timeoutDetails = "$Command $($Arguments -join ' ') timed out after ${TimeoutSeconds}s"
      try {
        & taskkill /PID $process.Id /T /F *> $null
      } catch {
        # Fall back below if taskkill cannot terminate the process tree.
      }
      $process.Refresh()
      if (-not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit(1000) | Out-Null
      }
      throw $timeoutDetails
    }

    if ($process.ExitCode -ne 0) {
      throw "$Command $($Arguments -join ' ') exited with $($process.ExitCode)"
    }
    $elapsedSeconds = [math]::Round(((Get-Date) - $gateStart).TotalSeconds, 2)
    Add-Result -Name $Name -Status 'PASS' -Details "$Command $($Arguments -join ' ') (${elapsedSeconds}s)"
  } catch {
    Add-Result -Name $Name -Status 'FAIL' -Details $_.Exception.Message
    throw
  }
}

function Assert-RequiredFile {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    throw "Required file missing: $Path"
  }
}

function Import-GovernanceCsv {
  param(
    [string]$Path,
    [string]$Name
  )

  Assert-RequiredFile $Path
  $rows = @(Import-Csv $Path)
  if ($rows.Count -eq 0) {
    throw "$Name matrix has no rows: $Path"
  }
  return $rows
}

function Assert-RequiredColumns {
  param(
    [object[]]$Rows,
    [string[]]$Columns,
    [string]$Name
  )

  $firstRow = $Rows[0]
  $actualColumns = @($firstRow.PSObject.Properties.Name)
  foreach ($column in $Columns) {
    if ($column -notin $actualColumns) {
      throw "$Name matrix missing column: $column"
    }
  }
}

function Assert-RequiredCells {
  param(
    [object[]]$Rows,
    [string[]]$Columns,
    [string]$Name,
    [string]$IdColumn
  )

  foreach ($row in $Rows) {
    $rowId = $row.$IdColumn
    if ([string]::IsNullOrWhiteSpace($rowId)) {
      $rowId = '<missing id>'
    }

    foreach ($column in $Columns) {
      if ([string]::IsNullOrWhiteSpace($row.$column)) {
        throw "$Name matrix row $rowId has blank required column: $column"
      }
    }
  }
}

function Assert-UniqueColumn {
  param(
    [object[]]$Rows,
    [string]$Column,
    [string]$Name
  )

  $duplicates = @(
    $Rows |
      Group-Object -Property $Column |
      Where-Object { $_.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($_.Name) } |
      Select-Object -ExpandProperty Name
  )
  if ($duplicates.Count -gt 0) {
    throw "$Name matrix has duplicate $Column values: $($duplicates -join ', ')"
  }
}

function Assert-AllowedStatuses {
  param(
    [object[]]$Rows,
    [string[]]$AllowedStatuses,
    [string]$Name,
    [string]$IdColumn
  )

  foreach ($row in $Rows) {
    if ($row.status -notin $AllowedStatuses) {
      throw "$Name matrix row $($row.$IdColumn) has unsupported status: $($row.status)"
    }
  }
}

function Get-RootGateExclusionPatterns {
  return @(
    '**/node_modules/**',
    '**/dist/**',
    '**/coverage/**',
    '**/coverage-*/**',
    '**/build/**',
    '**/.codex-tmp/**',
    '**/.cache/**',
    '**/.npm-cache/**',
    '**/.turbo/**',
    '**/.vite/**',
    '**/out/**',
    '**/.output/**',
    '**/.dart_tool/**',
    '**/.gradle/**',
    '**/.pub-cache/**',
    '**/.next/**',
    '**/.firebase/**',
    '**/playwright-report/**',
    '**/test-results/**',
    '**/html-report/**',
    '**/allure-results/**',
    '**/allure-report/**',
    '**/screenshots/**',
    '**/*screenshot*.png',
    '**/generated/**',
    '**/gen/**',
    '**/vendor/**',
    '**/third_party/**',
    'docs/test-governance/reports/generated/**',
    'server/server_storage/**',
    'server/server_storage_*/**',
    'server/uploads/**',
    'server/upload/**',
    'server/data/**',
    'server/logs/**',
    'server/log/**',
    '**/Users*AppDataLocalnpm-cache/**'
  )
}

function ConvertTo-GovernanceGlobRegex {
  param([string]$Pattern)

  $normalizedPattern = $Pattern.Replace('\', '/').Trim()
  if ($normalizedPattern.StartsWith('!')) {
    $normalizedPattern = $normalizedPattern.Substring(1)
  }
  $normalizedPattern = $normalizedPattern.TrimStart('/')

  $escaped = [regex]::Escape($normalizedPattern)
  $escaped = $escaped.Replace('\*\*', '___FLOWPLANV2_DOUBLE_STAR___')
  $escaped = $escaped.Replace('\*', '[^/]*')
  $escaped = $escaped.Replace('\?', '[^/]')
  $escaped = $escaped.Replace('___FLOWPLANV2_DOUBLE_STAR___', '.*')
  return '^' + $escaped + '$'
}

function Test-PathMatchesPattern {
  param(
    [string]$Path,
    [string]$Pattern
  )

  if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Pattern)) {
    return $false
  }

  $normalizedPath = $Path.Replace('\', '/').TrimStart('/')
  $regex = ConvertTo-GovernanceGlobRegex -Pattern $Pattern
  return $normalizedPath -match $regex
}

function ConvertTo-RepoRelativePath {
  param(
    [string]$Path,
    [string]$BaseRoot,
    [string]$RepoRoot
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ''
  }

  $rawPath = $Path.Trim()
  if ([System.IO.Path]::IsPathRooted($rawPath)) {
    $fullPath = [System.IO.Path]::GetFullPath($rawPath)
  } else {
    $normalizedRaw = $rawPath.Replace('\', '/').TrimStart('/')
    $baseLeaf = (Split-Path -Leaf $BaseRoot)
    if (
      $normalizedRaw -eq $baseLeaf -or
      $normalizedRaw.StartsWith("$baseLeaf/", [System.StringComparison]::OrdinalIgnoreCase) -or
      $normalizedRaw -match '^(server|web_admin|client_flutter|docs|scripts)/'
    ) {
      $fullPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $rawPath))
    } else {
      $fullPath = [System.IO.Path]::GetFullPath((Join-Path $BaseRoot $rawPath))
    }
  }

  $normalizedFullPath = $fullPath.Replace('\', '/')
  $normalizedRepoRoot = ([System.IO.Path]::GetFullPath($RepoRoot)).Replace('\', '/').TrimEnd('/')
  if ($normalizedFullPath.StartsWith("$normalizedRepoRoot/", [System.StringComparison]::OrdinalIgnoreCase)) {
    return $normalizedFullPath.Substring($normalizedRepoRoot.Length + 1)
  }
  return $normalizedFullPath
}

function Get-ReviewedCoverageExclusionPattern {
  param(
    [object[]]$Rows,
    [string]$Path
  )

  foreach ($row in $Rows) {
    if ($row.status -eq 'reviewed' -and (Test-PathMatchesPattern -Path $Path -Pattern $row.pattern)) {
      return $row.pattern
    }
  }
  return $null
}

function Test-ReviewedCoverageExclusionPath {
  param(
    [object[]]$Rows,
    [string]$Path
  )

  return $null -ne (Get-ReviewedCoverageExclusionPattern -Rows $Rows -Path $Path)
}

function Assert-ReviewedCoverageExclusionPatterns {
  param(
    [object[]]$Rows,
    [string[]]$Patterns
  )

  $reviewedPatterns = @{}
  $knownPatterns = @{}
  foreach ($row in $Rows) {
    $pattern = $row.pattern.Replace('\', '/').Trim()
    if ([string]::IsNullOrWhiteSpace($pattern)) {
      continue
    }
    $knownPatterns[$pattern] = $row.status
    if ($row.status -eq 'reviewed') {
      $reviewedPatterns[$pattern] = $true
    }
  }

  $missing = New-Object System.Collections.Generic.List[string]
  $notReviewed = New-Object System.Collections.Generic.List[string]
  foreach ($pattern in $Patterns) {
    $normalizedPattern = $pattern.Replace('\', '/').Trim()
    if ($normalizedPattern.StartsWith('!')) {
      $normalizedPattern = $normalizedPattern.Substring(1)
    }

    if (-not $knownPatterns.ContainsKey($normalizedPattern)) {
      $missing.Add($normalizedPattern) | Out-Null
    } elseif (-not $reviewedPatterns.ContainsKey($normalizedPattern)) {
      $notReviewed.Add($normalizedPattern) | Out-Null
    }
  }

  if ($missing.Count -gt 0 -or $notReviewed.Count -gt 0) {
    $parts = New-Object System.Collections.Generic.List[string]
    if ($missing.Count -gt 0) {
      $parts.Add("missing: $($missing -join ', ')") | Out-Null
    }
    if ($notReviewed.Count -gt 0) {
      $parts.Add("not reviewed: $($notReviewed -join ', ')") | Out-Null
    }
    throw "coverage-exclusions.csv is not aligned with actual gate exclusions; $($parts -join '; ')"
  }
}

function Get-DartLcovSummary {
  param(
    [string]$LcovPath,
    [string]$FlutterRoot,
    [string]$RepoRoot,
    [object[]]$CoverageRows
  )

  Assert-RequiredFile $LcovPath

  $records = New-Object System.Collections.Generic.List[object]
  $sourceFile = $null
  $relativeSourceFile = $null
  $daTotal = 0
  $daCovered = 0
  $hasDa = $false
  $lfTotal = $null
  $lhCovered = $null

  $addCurrentRecord = {
    if ([string]::IsNullOrWhiteSpace($sourceFile)) {
      return
    }

    if ($hasDa) {
      $recordTotal = $daTotal
      $recordCovered = $daCovered
    } elseif ($null -ne $lfTotal) {
      $recordTotal = [int]$lfTotal
      if ($null -ne $lhCovered) {
        $recordCovered = [int]$lhCovered
      } else {
        $recordCovered = 0
      }
    } else {
      $recordTotal = 0
      $recordCovered = 0
    }

    if ($recordTotal -le 0) {
      return
    }

    $exclusionPattern = Get-ReviewedCoverageExclusionPattern -Rows $CoverageRows -Path $relativeSourceFile
    $records.Add([PSCustomObject]@{
      SourceFile = $relativeSourceFile
      TotalLines = $recordTotal
      CoveredLines = $recordCovered
      IsExcluded = $null -ne $exclusionPattern
      ExclusionPattern = $exclusionPattern
    }) | Out-Null
  }

  foreach ($line in (Get-Content -Path $LcovPath)) {
    if ($line.StartsWith('SF:')) {
      & $addCurrentRecord
      $sourceFile = $line.Substring(3).Trim()
      $relativeSourceFile = ConvertTo-RepoRelativePath -Path $sourceFile -BaseRoot $FlutterRoot -RepoRoot $RepoRoot
      $daTotal = 0
      $daCovered = 0
      $hasDa = $false
      $lfTotal = $null
      $lhCovered = $null
      continue
    }

    if ($line.StartsWith('DA:')) {
      $parts = $line.Substring(3).Split(',')
      if ($parts.Count -ge 2) {
        [long]$hitCount = 0
        if ([long]::TryParse($parts[1], [ref]$hitCount)) {
          $hasDa = $true
          $daTotal += 1
          if ($hitCount -gt 0) {
            $daCovered += 1
          }
        }
      }
      continue
    }

    if ($line.StartsWith('LF:')) {
      [int]$lineCount = 0
      if ([int]::TryParse($line.Substring(3).Trim(), [ref]$lineCount)) {
        $lfTotal = $lineCount
      }
      continue
    }

    if ($line.StartsWith('LH:')) {
      [int]$lineHits = 0
      if ([int]::TryParse($line.Substring(3).Trim(), [ref]$lineHits)) {
        $lhCovered = $lineHits
      }
      continue
    }

    if ($line -eq 'end_of_record') {
      & $addCurrentRecord
      $sourceFile = $null
      $relativeSourceFile = $null
      $daTotal = 0
      $daCovered = 0
      $hasDa = $false
      $lfTotal = $null
      $lhCovered = $null
    }
  }
  & $addCurrentRecord

  $includedRecords = @($records | Where-Object { -not $_.IsExcluded })
  $excludedRecords = @($records | Where-Object { $_.IsExcluded })
  $totalLines = 0
  $coveredLines = 0
  $excludedLines = 0
  foreach ($record in $includedRecords) {
    $totalLines += [int]$record.TotalLines
    $coveredLines += [int]$record.CoveredLines
  }
  foreach ($record in $excludedRecords) {
    $excludedLines += [int]$record.TotalLines
  }

  $lineCoveragePercent = 0.0
  if ($totalLines -gt 0) {
    $lineCoveragePercent = [math]::Round(($coveredLines / $totalLines) * 100, 2)
  }

  return [PSCustomObject]@{
    TotalLines = $totalLines
    CoveredLines = $coveredLines
    LineCoveragePercent = $lineCoveragePercent
    IncludedRecordCount = $includedRecords.Count
    ExcludedRecordCount = $excludedRecords.Count
    ExcludedLines = $excludedLines
    Records = @($records.ToArray())
  }
}

function Assert-DartLcovCoverage {
  param(
    [string]$FlutterRoot,
    [string]$RepoRoot,
    [object[]]$CoverageRows,
    [double]$MinimumLineCoveragePercent = 100.0
  )

  Write-Host '== flutter:lcov threshold =='
  $lcovPath = Join-Path $FlutterRoot 'coverage\lcov.info'

  try {
    $flutterCoverageRows = @($CoverageRows | Where-Object { $_.owner_or_module -eq 'client_flutter' })
    $summary = Get-DartLcovSummary -LcovPath $lcovPath -FlutterRoot $FlutterRoot -RepoRoot $RepoRoot -CoverageRows $flutterCoverageRows
    if ($summary.TotalLines -le 0) {
      throw "Dart LCOV has no included executable lines after reviewed exclusions: $lcovPath"
    }

    if ($summary.LineCoveragePercent -lt $MinimumLineCoveragePercent) {
      throw ("Dart LCOV line coverage {0:N2}% ({1}/{2}) is below required {3:N2}%: {4}" -f `
        $summary.LineCoveragePercent,
        $summary.CoveredLines,
        $summary.TotalLines,
        $MinimumLineCoveragePercent,
        $lcovPath)
    }

    Add-Result `
      -Name 'flutter:lcov threshold' `
      -Status 'PASS' `
      -Details ("{0:N2}% ({1}/{2}); excluded {3} records/{4} lines" -f `
        $summary.LineCoveragePercent,
        $summary.CoveredLines,
        $summary.TotalLines,
        $summary.ExcludedRecordCount,
        $summary.ExcludedLines)
  } catch {
    Add-Result -Name 'flutter:lcov threshold' -Status 'FAIL' -Details $_.Exception.Message
    throw
  }
}

function Assert-FeatureMatrix {
  param(
    [object[]]$Rows,
    [object[]]$ManualRows,
    [switch]$Completion
  )

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
  Assert-RequiredColumns -Rows $Rows -Columns $requiredColumns -Name 'feature-test'
  Assert-RequiredCells -Rows $Rows -Columns @(
    'test_id',
    'product_area',
    'module_or_route',
    'user_feature',
    'control_or_api',
    'happy_path_test',
    'failure_path_test',
    'data_integrity_assertion',
    'accessibility_or_layout_assertion',
    'status',
    'notes'
  ) -Name 'feature-test' -IdColumn 'test_id'
  Assert-UniqueColumn -Rows $Rows -Column 'test_id' -Name 'feature-test'
  Assert-AllowedStatuses -Rows $Rows -AllowedStatuses @(
    'verified',
    'implemented',
    'partial',
    'planned',
    'missing',
    'pending-user',
    'blocked-environment'
  ) -Name 'feature-test' -IdColumn 'test_id'

  $manualIds = @{}
  foreach ($manualRow in $ManualRows) {
    $manualIds[$manualRow.manual_id] = $manualRow
  }
  foreach ($row in $Rows) {
    if (-not [string]::IsNullOrWhiteSpace($row.manual_acceptance_id) -and -not $manualIds.ContainsKey($row.manual_acceptance_id)) {
      throw "feature-test matrix row $($row.test_id) references unknown manual_acceptance_id: $($row.manual_acceptance_id)"
    }

    if (-not [string]::IsNullOrWhiteSpace($row.manual_acceptance_id) -and $manualIds.ContainsKey($row.manual_acceptance_id)) {
      $manualRow = $manualIds[$row.manual_acceptance_id]
      if ($manualRow.status -ne 'passing' -and $row.status -in @('verified', 'implemented')) {
        throw "feature-test matrix row $($row.test_id) is $($row.status) but manual acceptance $($row.manual_acceptance_id) is $($manualRow.status); use partial, planned, pending-user, or blocked-environment until manual evidence passes"
      }
    }
  }

  if ($Completion) {
    $openRows = @($Rows | Where-Object { $_.status -in @('missing', 'planned', 'pending-user', 'blocked-environment', 'partial') })
    if ($openRows.Count -gt 0) {
      $openIds = @($openRows | Select-Object -ExpandProperty test_id)
      throw "Completion mode found open feature-test matrix rows: $($openIds -join ', ')"
    }
  }
}

function Assert-ManualAcceptanceMatrix {
  param(
    [object[]]$Rows,
    [switch]$Completion
  )

  $requiredColumns = @(
    'manual_id',
    'area',
    'scenario',
    'required_environment',
    'buttons_controls',
    'status_states',
    'error_paths',
    'side_effects',
    'steps',
    'evidence',
    'status'
  )
  Assert-RequiredColumns -Rows $Rows -Columns $requiredColumns -Name 'manual-acceptance'
  Assert-RequiredCells -Rows $Rows -Columns $requiredColumns -Name 'manual-acceptance' -IdColumn 'manual_id'
  Assert-UniqueColumn -Rows $Rows -Column 'manual_id' -Name 'manual-acceptance'
  Assert-AllowedStatuses -Rows $Rows -AllowedStatuses @(
    'pending-user',
    'passing',
    'failed',
    'blocked',
    'blocked-environment'
  ) -Name 'manual-acceptance' -IdColumn 'manual_id'

  foreach ($row in $Rows) {
    if ($row.status -eq 'passing' -and $row.evidence -notmatch '\b20\d{2}-\d{2}-\d{2}\b') {
      throw "manual-acceptance matrix row $($row.manual_id) is passing but evidence does not include a dated evidence note."
    }
  }

  if ($Completion) {
    $openRows = @($Rows | Where-Object { $_.status -ne 'passing' })
    if ($openRows.Count -gt 0) {
      $openIds = @($openRows | Select-Object -ExpandProperty manual_id)
      throw "Completion mode found open manual-acceptance matrix rows: $($openIds -join ', ')"
    }
  }
}

function Assert-CoverageExclusionMatrix {
  param(
    [object[]]$Rows,
    [switch]$Completion
  )

  $requiredColumns = @(
    'pattern',
    'reason',
    'replacement_verification',
    'owner_or_module',
    'review_condition',
    'status'
  )
  Assert-RequiredColumns -Rows $Rows -Columns $requiredColumns -Name 'coverage-exclusions'
  Assert-RequiredCells -Rows $Rows -Columns $requiredColumns -Name 'coverage-exclusions' -IdColumn 'pattern'
  Assert-UniqueColumn -Rows $Rows -Column 'pattern' -Name 'coverage-exclusions'
  Assert-AllowedStatuses -Rows $Rows -AllowedStatuses @(
    'reviewed',
    'pending-review',
    'planned',
    'missing'
  ) -Name 'coverage-exclusions' -IdColumn 'pattern'
  Assert-ReviewedCoverageExclusionPatterns -Rows $Rows -Patterns @(Get-RootGateExclusionPatterns)

  if ($Completion) {
    $openRows = @($Rows | Where-Object { $_.status -ne 'reviewed' })
    if ($openRows.Count -gt 0) {
      $openIds = @($openRows | Select-Object -ExpandProperty pattern)
      throw "Completion mode found open coverage-exclusions matrix rows: $($openIds -join ', ')"
    }
  }
}

function Assert-GovernanceMatrices {
  param(
    [string]$RepoRoot,
    [switch]$Completion
  )

  Write-Host '== governance matrix validation =='
  $featureMatrixPath = Join-Path $RepoRoot 'docs\test-governance\feature-test-matrix.csv'
  $manualMatrixPath = Join-Path $RepoRoot 'docs\test-governance\manual-acceptance.csv'
  $coverageMatrixPath = Join-Path $RepoRoot 'docs\test-governance\coverage-exclusions.csv'

  try {
    $manualRows = @(Import-GovernanceCsv -Path $manualMatrixPath -Name 'manual-acceptance')
    $featureRows = @(Import-GovernanceCsv -Path $featureMatrixPath -Name 'feature-test')
    $coverageRows = @(Import-GovernanceCsv -Path $coverageMatrixPath -Name 'coverage-exclusions')

    Assert-ManualAcceptanceMatrix -Rows $manualRows -Completion:$Completion
    Assert-FeatureMatrix -Rows $featureRows -ManualRows $manualRows -Completion:$Completion
    Assert-CoverageExclusionMatrix -Rows $coverageRows -Completion:$Completion
    Add-Result -Name 'governance matrix validation' -Status 'PASS' -Details 'feature-test, manual-acceptance, coverage-exclusions, actual gate exclusions'
  } catch {
    Add-Result -Name 'governance matrix validation' -Status 'FAIL' -Details $_.Exception.Message
    throw
  }
}

function Assert-NoFocusedOrSkippedTests {
  Write-Host '== focused/skipped test scan =='
  $pattern = '\b(describe|it|test)\.(only|skip)\s*\(|\b(fit|xit)\s*\(|@Skip\s*\(|\bmarkTestSkipped\s*\(|\bskip\s*:\s*(true|["''])|\bsolo(Test|Group|Widget)?\s*\('
  $targetPaths = @('server', 'web_admin', 'client_flutter')
  $includeGlobs = @(
    '*.spec.*',
    '*.test.*',
    '*_test.dart'
  )
  $excludeGlobs = @(Get-RootGateExclusionPatterns | ForEach-Object { "!$_" })
  $arguments = @(
    '--no-ignore',
    '-n'
  )
  foreach ($glob in ($includeGlobs + $excludeGlobs)) {
    $arguments += @('--glob', $glob)
  }
  $arguments += @($pattern) + $targetPaths

  $quoteArgument = {
    param([string]$Argument)
    if ($null -eq $Argument -or $Argument -eq '') {
      return '""'
    }
    if ($Argument -notmatch '[\s"]') {
      return $Argument
    }
    return '"' + $Argument.Replace('"', '\"') + '"'
  }

  try {
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = Resolve-GateCommand -Command 'rg'
    $processInfo.Arguments = ($arguments | ForEach-Object { & $quoteArgument $_ }) -join ' '
    $processInfo.WorkingDirectory = $RepoRoot
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($processInfo)
    if ($null -eq $process) {
      throw 'Failed to start rg focused/skipped scan.'
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($GateTimeoutSeconds * 1000)) {
      try {
        & taskkill /PID $process.Id /T /F *> $null
      } catch {
        # Fall back below if taskkill cannot terminate the process tree.
      }
      $process.Refresh()
      if (-not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit(1000) | Out-Null
      }
      Add-Result -Name 'focused/skipped test scan' -Status 'FAIL' -Details "rg timed out after ${GateTimeoutSeconds}s"
      throw "Focused/skipped test scan timed out after ${GateTimeoutSeconds}s."
    }
    $process.WaitForExit()
    $matches = @($stdoutTask.Result, $stderrTask.Result | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $exitCode = $process.ExitCode
  } catch {
    Add-Result -Name 'focused/skipped test scan' -Status 'FAIL' -Details $_.Exception.Message
    throw "Focused/skipped test scan command failed: $($_.Exception.Message)"
  }

  if ($exitCode -eq 0) {
    $details = ($matches | Out-String).Trim()
    Write-Host $details
    Add-Result -Name 'focused/skipped test scan' -Status 'FAIL' -Details 'matches found'
    throw 'Focused or skipped tests found. Remove the focus or skip marker before completion.'
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

function Skip-Gate {
  param(
    [string]$Name,
    [string]$Details
  )

  Write-Host "== $Name =="
  Write-Host "[SKIP] $Details"
  Add-Result -Name $Name -Status 'SKIP' -Details $Details
}

function Write-GateSummary {
  Write-Host ''
  Write-Host '== Gate Summary =='
  $Results | ForEach-Object {
    Write-Host ("[{0}] {1} {2}" -f $_.Status, $_.Name, $_.Details)
  }
}

function Invoke-FlutterGates {
  param(
    [string]$FlutterRoot,
    [string]$RepoRoot,
    [switch]$SkipInstall,
    [string]$IntegrationDevice,
    [switch]$SkipIntegration,
    [switch]$Completion
  )

  $oldEnvironment = @{
    APPDATA = $env:APPDATA
    LOCALAPPDATA = $env:LOCALAPPDATA
    PUB_CACHE = $env:PUB_CACHE
    FLUTTER_SUPPRESS_ANALYTICS = $env:FLUTTER_SUPPRESS_ANALYTICS
    CI = $env:CI
    GIT_CONFIG_COUNT = $env:GIT_CONFIG_COUNT
    GIT_CONFIG_KEY_0 = $env:GIT_CONFIG_KEY_0
    GIT_CONFIG_VALUE_0 = $env:GIT_CONFIG_VALUE_0
  }

  try {
    $tempRoot = Join-Path $FlutterRoot '.codex-tmp'
    $flutterAppData = Join-Path $tempRoot 'flutter-appdata'
    $flutterLocalAppData = Join-Path $tempRoot 'flutter-localappdata'
    $pubCache = Join-Path $tempRoot 'pub-cache'
    New-Item -ItemType Directory -Force -Path $flutterAppData, $flutterLocalAppData, $pubCache | Out-Null
    $flutterCommand = Resolve-GateCommand -Command 'flutter'
    $flutterSdkRoot = (Split-Path -Parent (Split-Path -Parent $flutterCommand)).Replace('\', '/')

    $env:APPDATA = $flutterAppData
    $env:LOCALAPPDATA = $flutterLocalAppData
    $env:PUB_CACHE = $pubCache
    $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
    $env:CI = 'true'
    $env:GIT_CONFIG_COUNT = '1'
    $env:GIT_CONFIG_KEY_0 = 'safe.directory'
    $env:GIT_CONFIG_VALUE_0 = $flutterSdkRoot

    if (-not $SkipInstall) {
      Invoke-Gate -Name 'flutter:pub get' -WorkingDirectory $FlutterRoot -Command 'flutter' -Arguments @('pub', 'get')
    }

    Invoke-Gate -Name 'flutter:build_runner' -WorkingDirectory $FlutterRoot -Command 'dart' -Arguments @('run', 'build_runner', 'build', '--delete-conflicting-outputs')
    Invoke-Gate -Name 'flutter:analyze' -WorkingDirectory $FlutterRoot -Command 'flutter' -Arguments @('analyze')
    Invoke-Gate -Name 'flutter:unit widget coverage' -WorkingDirectory $FlutterRoot -Command 'flutter' -Arguments @('test', '--no-pub', '--coverage', '-x', 'golden', '--concurrency=1')
    $coverageRows = @(Import-GovernanceCsv -Path (Join-Path $RepoRoot 'docs\test-governance\coverage-exclusions.csv') -Name 'coverage-exclusions')
    Assert-DartLcovCoverage -FlutterRoot $FlutterRoot -RepoRoot $RepoRoot -CoverageRows $coverageRows -MinimumLineCoveragePercent 100

    $goldenTests = @(
      Get-ChildItem -Path (Join-Path $FlutterRoot 'test\goldens') -Filter '*_golden_test.dart' |
        Sort-Object Name
    )
    if ($goldenTests.Count -eq 0) {
      throw 'No Flutter golden test files found under client_flutter/test/goldens.'
    }
    foreach ($testFile in $goldenTests) {
      $relativeTestPath = "test/goldens/$($testFile.Name)"
      Invoke-Gate -Name "flutter:golden:$($testFile.BaseName)" -WorkingDirectory $FlutterRoot -Command 'flutter' -Arguments @('test', '--no-pub', $relativeTestPath, '-r', 'expanded', '--concurrency=1')
    }

    if ($SkipIntegration) {
      $details = 'Flutter integration tests skipped by -SkipFlutterIntegration; run with -FlutterIntegrationDevice windows|chrome|edge for deterministic device selection.'
      if ($Completion) {
        Add-Result -Name 'flutter:integration' -Status 'FAIL' -Details $details
        throw "Completion mode cannot skip Flutter integration tests. $details"
      }
      Skip-Gate -Name 'flutter:integration' -Details $details
      return
    }

    $integrationTests = @(
      Get-ChildItem -Path (Join-Path $FlutterRoot 'integration_test') -Filter '*_test.dart' |
        Sort-Object Name
    )
    if ($integrationTests.Count -eq 0) {
      throw 'No Flutter integration test files found under client_flutter/integration_test.'
    }
    foreach ($testFile in $integrationTests) {
      $relativeTestPath = "integration_test/$($testFile.Name)"
      Invoke-Gate -Name "flutter:integration:$($testFile.BaseName) ($IntegrationDevice)" -WorkingDirectory $FlutterRoot -Command 'flutter' -Arguments @('test', '--no-pub', '-d', $IntegrationDevice, $relativeTestPath, '--concurrency=1')
    }
  } finally {
    foreach ($key in $oldEnvironment.Keys) {
      if ($null -eq $oldEnvironment[$key]) {
        Remove-Item -Path "env:$key" -ErrorAction SilentlyContinue
      } else {
        Set-Item -Path "env:$key" -Value $oldEnvironment[$key]
      }
    }
  }
}

try {
  Write-Host '== FlowPlanV2 root quality gate =='

  Assert-GovernanceMatrices -RepoRoot $RepoRoot -Completion:$Completion
  Assert-NoFocusedOrSkippedTests

  Invoke-Gate -Name 'root:gate timeout unit' -WorkingDirectory $RepoRoot -Command 'powershell' -Arguments @('-ExecutionPolicy', 'Bypass', '-File', 'scripts\test-flowplanv2-timeout.unit.ps1') -TimeoutSeconds 30

  if ($GovernanceOnly) {
    return
  }

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
  } else {
    Skip-Gate -Name 'web:e2e' -Details 'Web Admin E2E skipped by -SkipWebE2E.'
  }

  $FlutterRoot = Join-Path $RepoRoot 'client_flutter'
  Invoke-FlutterGates -FlutterRoot $FlutterRoot -RepoRoot $RepoRoot -SkipInstall:$SkipInstall -IntegrationDevice $FlutterIntegrationDevice -SkipIntegration:$SkipFlutterIntegration -Completion:$Completion
} finally {
  Write-GateSummary
}
