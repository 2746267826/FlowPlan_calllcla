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

  test('task candidates put anchored task before unanchored task', () {
    final day = DateTime(2026, 6, 12);
    final unanchored = _task(id: 1, summary: 'Aardvark');
    final anchored = _task(
      id: 2,
      summary: 'Zulu',
      dtstart: day.add(const Duration(hours: 13)),
    );

    final candidates = trackerPresentationDebugBuildTaskCandidates(
      <TaskItem>[unanchored, anchored],
      day,
    );

    expect(candidates.take(2), <TaskItem>[anchored, unanchored]);
  });

  test('task candidates prefer anchored task when sentinel distance ties', () {
    final day = DateTime(2026, 6, 12);
    final unanchored = _task(id: 1, summary: 'Aardvark');
    final anchored = _task(
      id: 2,
      summary: 'Zulu',
      dtstart: _dateAtDayDistance(day, 1 << 20),
    );

    final candidates = trackerPresentationDebugBuildTaskCandidates(
      <TaskItem>[unanchored, anchored],
      day,
    );

    expect(candidates.take(2), <TaskItem>[anchored, unanchored]);
  });

  test('task candidate comparator prefers anchored side on distance ties', () {
    final day = DateTime(2026, 6, 12);
    final unanchored = _task(id: 1, summary: 'Aardvark');
    final anchored = _task(
      id: 2,
      summary: 'Zulu',
      dtstart: _dateAtDayDistance(day, 1 << 20),
    );

    expect(
      trackerPresentationDebugCompareTaskCandidates(unanchored, anchored, day),
      isPositive,
    );
    expect(
      trackerPresentationDebugCompareTaskCandidates(anchored, unanchored, day),
      isNegative,
    );
  });

  testWidgets('database folder opener provider uses injected starter', (
    tester,
  ) async {
    final calls = <({String executable, List<String> arguments})>[];
    final container = ProviderContainer(
      overrides: <Override>[
        trackerPageProcessStarterProvider.overrideWithValue((
          executable,
          arguments,
        ) async {
          calls.add((executable: executable, arguments: arguments));
          return Object();
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(trackerPageDatabaseFolderOpenerProvider)('C:\\data');

    if (calls.isEmpty) {
      expect(calls, isEmpty);
    } else {
      expect(calls.single.executable, 'explorer.exe');
      expect(calls.single.arguments, <String>['C:\\data']);
    }
  });

  test('process starter provider exposes default starter without invoking it',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final starter = container.read(trackerPageProcessStarterProvider);

    expect(starter, isA<TrackerProcessStarter>());
  });

  test('dominant hour debug helper handles zero-length ranges', () {
    final day = DateTime(2026, 6, 12);

    expect(
      trackerPresentationDebugDominantHourForRange(
        itemStart: day.add(const Duration(hours: 9, minutes: 30)),
        itemEnd: day.add(const Duration(hours: 9, minutes: 30)),
        selectedDate: day,
      ),
      9,
    );
  });

  test('log matcher includes zero-length entries at bucket start', () {
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
      trackerPresentationDebugTimeRangeOverlaps(
        rangeStart: bucket.start,
        rangeEnd: bucket.end,
        itemStart: bucket.start,
        itemEnd: bucket.start,
      ),
      isTrue,
    );
  });

  test('log matcher excludes entries at bucket end boundary', () {
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
        _logEntry(timestamp: bucket.end, recordId: 7),
        searchQuery: '',
        selectedProcess: null,
        selectedCategory: null,
        selectedRecordIds: null,
        onlyWithInput: false,
        selectedHeatmapBucket: bucket,
      ),
      isFalse,
    );
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

  testWidgets('log entry tile shows details for key sequence only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: trackerPresentationDebugLogEntryTile(
            entry: _logEntry(
              timestamp: DateTime(2026, 6, 12, 9, 5),
              recordId: null,
              keySequence: 'Ctrl+S',
            ),
            showDetails: true,
          ),
        ),
      ),
    );

    expect(find.byType(ExpansionTile), findsOneWidget);
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
  String? keySequence,
}) {
  return ActivityLogEntry(
    timestamp: timestamp,
    type: ActivityLogEntryType.sample,
    recordId: recordId,
    processName: 'Code.exe',
    windowTitle: 'Coverage log',
    category: 'coding',
    durationMinutes: 1,
    keySequence: keySequence,
  );
}

DateTime _dateAtDayDistance(DateTime referenceDate, int distance) {
  final referenceDay = DateUtils.dateOnly(referenceDate);
  for (var offset = -3; offset <= 3; offset += 1) {
    final candidate = DateTime(
      referenceDay.year,
      referenceDay.month,
      referenceDay.day + distance + offset,
    );
    final candidateDistance = DateUtils.dateOnly(
      candidate,
    ).difference(referenceDay).inDays.abs();
    if (candidateDistance == distance) {
      return candidate;
    }
  }
  throw StateError('Could not construct a task date at distance $distance.');
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
