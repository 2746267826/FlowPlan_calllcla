import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('log matcher rejects entries outside selected records and bucket', () {
    final day = DateTime(2026, 6, 12);
    final bucket = ActivityHeatmapBucket(
      start: day.add(const Duration(hours: 9)),
      end: day.add(const Duration(hours: 10)),
      shortLabel: '09',
      longLabel: '09:00',
      completedCount: 0,
      totalMinutes: 0,
    );

    expect(
      trackerPresentationDebugMatchesLogEntry(
        _logEntry(
          timestamp: day.add(const Duration(hours: 9, minutes: 10)),
          recordId: null,
        ),
        searchQuery: '',
        selectedProcess: null,
        selectedCategory: null,
        selectedRecordIds: <int>{7},
        onlyWithInput: false,
        selectedHeatmapBucket: null,
      ),
      isFalse,
    );
    expect(
      trackerPresentationDebugMatchesLogEntry(
        _logEntry(
          timestamp: day.add(const Duration(hours: 10)),
          recordId: 7,
        ),
        searchQuery: '',
        selectedProcess: null,
        selectedCategory: null,
        selectedRecordIds: <int>{7},
        onlyWithInput: false,
        selectedHeatmapBucket: bucket,
      ),
      isFalse,
    );
  });

  test('task candidates prefer anchored task when distance ties', () {
    final day = DateTime(2026, 6, 12);
    final anchored = _task(
      id: 1,
      summary: 'Anchored',
      dtstart: day.add(const Duration(hours: 9)),
    );
    final unanchored = _task(id: 2, summary: 'Unanchored');

    final candidates = trackerPresentationDebugBuildTaskCandidates(
      <TaskItem>[unanchored, anchored],
      day,
    );

    expect(candidates.take(2), <TaskItem>[anchored, unanchored]);
  });

  test('snapshot copyWith preserves refreshedAt when omitted', () {
    final refreshedAt = DateTime(2026, 6, 12, 17, 39);

    expect(
      trackerPresentationDebugCopySnapshotRefreshedAt(refreshedAt),
      refreshedAt,
    );
  });

  testWidgets('log entry tile can render time without date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: trackerPresentationDebugLogEntryTile(
            entry: _logEntry(
              timestamp: DateTime(2026, 6, 12, 9, 4),
              recordId: 7,
            ),
          ),
        ),
      ),
    );

    expect(find.text('09:04'), findsOneWidget);
    expect(find.textContaining('06-12'), findsNothing);
  });

  testWidgets('history filter panel includes log counts in summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: trackerPresentationDebugHistoryFilterPanel(
              searchQuery: '',
              selectedProcess: null,
              selectedCategory: null,
              taskOptions: const <TaskItem>[],
              selectedTaskId: null,
              onlyWithInput: false,
              selectedTimeBucketLabel: null,
              filteredSessionCount: 2,
              totalSessionCount: 3,
              filteredLogCount: 4,
              totalLogCount: 5,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('4/5'), findsOneWidget);
  });
}

ActivityLogEntry _logEntry({
  required DateTime timestamp,
  required int? recordId,
}) {
  return ActivityLogEntry(
    timestamp: timestamp,
    type: ActivityLogEntryType.sample,
    recordId: recordId,
    processName: 'Code.exe',
    windowTitle: 'Coverage log',
    category: 'coding',
    durationMinutes: 1,
  );
}

TaskItem _task({
  required int id,
  required String summary,
  DateTime? dtstart,
}) {
  return TaskItem(
    id: id,
    uid: 'task-$id',
    dtstamp: DateTime(2026, 6, 12),
    summary: summary,
    dtstart: dtstart,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: '',
    durationMinutes: 0,
    isSplittable: false,
    priorityLocal: 0,
    isAutoScheduled: false,
    isLocked: false,
    reminderMinutesBefore: 0,
  );
}
