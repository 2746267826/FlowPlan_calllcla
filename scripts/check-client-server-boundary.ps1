param(
  [switch]$FailOnViolation
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$clientRoot = Join-Path $root 'client_flutter\lib'

$allowedPathFragments = @(
  '\core\sync\',
  '\core\offline_queue\',
  '\core\database\',
  '\core\server_first\',
  '\shared\providers\app_providers.dart'
)

$waiverRules = @(
  @{ Fragment = '\features\calendar\presentation\'; Reason = 'task_event_ui_cache_transition' },
  @{ Fragment = '\features\task\presentation\'; Reason = 'task_event_ui_cache_transition' },
  @{ Fragment = '\features\data_management\presentation\'; Reason = 'bulk_data_cache_transition' },
  @{ Fragment = '\features\files\presentation\'; Reason = 'cloud_drive_ui_cache_transition' },
  @{ Fragment = '\features\ical\'; Reason = 'import_export_device_tool_transition' },
  @{ Fragment = '\features\sync\outlook_'; Reason = 'external_integration_device_cache' },
  @{ Fragment = '\features\scheduler\scheduler_engine.dart'; Reason = 'legacy_offline_preview_model' },
  @{ Fragment = '\features\scheduler\plan_feedback_service.dart'; Reason = 'legacy_feedback_cache_bridge' },
  @{ Fragment = '\features\tracker\services\activity_fusion_service.dart'; Reason = 'legacy_offline_preview_model' },
  @{ Fragment = '\shared\providers\tracker_providers.dart'; Reason = 'tracking_raw_buffer_and_legacy_fusion_bridge' }
)

$patterns = @(
  'taskRepositoryProvider',
  'eventRepositoryProvider',
  'actualActivityLogRepositoryProvider',
  'reportGenerationServiceProvider',
  'fileContextRepositoryProvider',
  'SchedulerEngine(',
  'ActivityFusionService('
)

$taskEventUiWriteFiles = @(
  '\features\calendar\presentation\',
  '\features\task\presentation\',
  '\features\data_management\presentation\'
)

$taskEventUiWritePatterns = @(
  'taskRepositoryProvider).create',
  'taskRepositoryProvider).update',
  'taskRepositoryProvider).delete',
  'taskRepositoryProvider).markCompleted',
  'taskRepositoryProvider).clearDtstart',
  'taskRepositoryProvider).updateDtstart',
  'taskRepositoryProvider).updateDuration',
  'eventRepositoryProvider).create',
  'eventRepositoryProvider).update',
  'eventRepositoryProvider).delete',
  'eventRepositoryProvider).updateTime',
  'eventRepositoryProvider).updateDuration',
  'TaskItemsCompanion.insert',
  'CalendarEventsCompanion.insert'
)

$trackerPresentationFiles = @(
  '\features\tracker\presentation\'
)

$trackerProcessedDataFiles = @(
  '\features\tracker\presentation\',
  '\shared\providers\tracker_providers.dart'
)

$trackerServerFirstPatterns = @(
  'activityRecordRepositoryProvider',
  'trackerRepositoryProvider',
  'activityFusionServiceProvider',
  'activityFusionRepositoryProvider',
  'inputActivityEventServiceProvider'
)

$trackerProcessedDataPatterns = @(
  'ActivityInsights.fromRecords',
  'WorkSessionGrouper.fromRecords',
  'activityRecords(',
  'inputEvents(limit: 500'
)

Write-Host 'FlowPlanV2 client/server boundary scan'
Write-Host "Root: $clientRoot"
Write-Host 'Rule: UI and feature providers should use server-first APIs; local repositories are cache/legacy only.'
Write-Host ''

$files = Get-ChildItem -Path $clientRoot -Recurse -Filter '*.dart'
$violations = @()
$waived = @()
$writeViolations = @()

foreach ($file in $files) {
  $path = $file.FullName
  $relative = $path.Substring($clientRoot.Length)

  $isTaskEventUiFile = $false
  foreach ($fragment in $taskEventUiWriteFiles) {
    if ($relative.Contains($fragment)) {
      $isTaskEventUiFile = $true
      break
    }
  }
  if ($isTaskEventUiFile) {
    $writeMatches = Select-String -Path $path -Pattern $taskEventUiWritePatterns -SimpleMatch -ErrorAction SilentlyContinue
    foreach ($match in $writeMatches) {
      $writeViolations += [PSCustomObject]@{
        File = $relative.TrimStart('\')
        Line = $match.LineNumber
        Text = $match.Line.Trim()
      }
    }
  }

  $isTrackerPresentationFile = $false
  foreach ($fragment in $trackerPresentationFiles) {
    if ($relative.Contains($fragment)) {
      $isTrackerPresentationFile = $true
      break
    }
  }
  if ($isTrackerPresentationFile) {
    $trackerMatches = Select-String -Path $path -Pattern $trackerServerFirstPatterns -SimpleMatch -ErrorAction SilentlyContinue
    foreach ($match in $trackerMatches) {
      $writeViolations += [PSCustomObject]@{
        File = $relative.TrimStart('\')
        Line = $match.LineNumber
        Text = $match.Line.Trim()
      }
    }
  }

  $isTrackerProcessedDataFile = $false
  foreach ($fragment in $trackerProcessedDataFiles) {
    if ($relative.Contains($fragment)) {
      $isTrackerProcessedDataFile = $true
      break
    }
  }
  if ($isTrackerProcessedDataFile) {
    $trackerProcessedMatches = Select-String -Path $path -Pattern $trackerProcessedDataPatterns -SimpleMatch -ErrorAction SilentlyContinue
    foreach ($match in $trackerProcessedMatches) {
      $writeViolations += [PSCustomObject]@{
        File = $relative.TrimStart('\')
        Line = $match.LineNumber
        Text = $match.Line.Trim()
      }
    }
  }

  $isAllowed = $false
  foreach ($fragment in $allowedPathFragments) {
    if ($relative.Contains($fragment)) {
      $isAllowed = $true
      break
    }
  }
  if ($isAllowed) {
    continue
  }

  $waiverReason = $null
  foreach ($rule in $waiverRules) {
    if ($relative.Contains([string]$rule.Fragment)) {
      $waiverReason = [string]$rule.Reason
      break
    }
  }

  $matches = Select-String -Path $path -Pattern $patterns -SimpleMatch -ErrorAction SilentlyContinue
  foreach ($match in $matches) {
    $record = [PSCustomObject]@{
      File = $relative.TrimStart('\')
      Line = $match.LineNumber
      Text = $match.Line.Trim()
      Reason = $waiverReason
    }
    if ($waiverReason) {
      $waived += $record
    } else {
      $violations += $record
    }
  }
}

if ($violations.Count -eq 0 -and $waived.Count -eq 0) {
  Write-Host 'OK: no direct local fact repository usage found outside allowlist.'
  exit 0
}

if ($violations.Count -gt 0) {
  Write-Host "Found $($violations.Count) boundary violation(s):"
  foreach ($violation in $violations) {
    Write-Host ("- {0}:{1} {2}" -f $violation.File, $violation.Line, $violation.Text)
  }
  Write-Host ''
}

if ($writeViolations.Count -gt 0) {
  Write-Host "Found $($writeViolations.Count) direct task/event UI write violation(s):"
  foreach ($violation in $writeViolations) {
    Write-Host ("- {0}:{1} {2}" -f $violation.File, $violation.Line, $violation.Text)
  }
  Write-Host ''
}

if ($waived.Count -gt 0) {
  Write-Host "Found $($waived.Count) documented cache/legacy transition use(s):"
  foreach ($item in $waived) {
    Write-Host ("- {0}:{1} [{2}] {3}" -f $item.File, $item.Line, $item.Reason, $item.Text)
  }
  Write-Host ''
}

if ($violations.Count -eq 0 -and $writeViolations.Count -eq 0) {
  Write-Host 'OK: no unwaived boundary violations. Waived items must remain visible until their UI is migrated to server-first stores.'
} else {
  Write-Host 'Boundary violations must be migrated to server-first APIs or added to an explicit cache/offline/legacy waiver with a reason.'
}

if ($FailOnViolation -and ($violations.Count -gt 0 -or $writeViolations.Count -gt 0)) {
  exit 1
}
