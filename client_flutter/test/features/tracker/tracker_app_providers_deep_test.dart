import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/tracking_ingest_api.dart';
import 'package:flowplanv2/core/server_first/tracking_server_first_store.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  ProviderContainer createContainer({
    required AppDatabase db,
    _TrackingStoreFake? store,
    List<Override> overrides = const <Override>[],
  }) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        if (store != null)
          trackingServerFirstStoreProvider.overrideWith((ref) async => store),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
    return container;
  }

  test('repository and service providers build from the database override',
      () async {
    final db = createTestDatabase();
    final container = createContainer(
      db: db,
      overrides: [
        trackingIngestApiProvider.overrideWith(
          (ref) async => _UnusedTrackingIngestApi(),
        ),
      ],
    );

    final taskRepo = container.read(taskRepositoryProvider);
    final eventRepo = container.read(eventRepositoryProvider);
    final calendarRepo = container.read(calendarBooksRepositoryProvider);
    final activityRepo = container.read(activityRecordRepositoryProvider);
    final trackerRepo = container.read(trackerRepositoryProvider);

    expect(container.read(taskRepositoryProvider), same(taskRepo));
    expect(container.read(trackerRepositoryProvider), same(trackerRepo));
    expect(container.read(dataOperationLogRepositoryProvider), isNotNull);
    expect(container.read(syncObjectStateStoreProvider), isNotNull);
    expect(container.read(offlineMutationStoreProvider), isNotNull);
    expect(container.read(syncConflictStoreProvider), isNotNull);
    expect(container.read(syncWriteRecorderProvider), isNotNull);
    expect(container.read(actualActivityLogRepositoryProvider), isNotNull);
    expect(container.read(activityFusionRepositoryProvider), isNotNull);
    expect(
        container.read(blockingEventActualCandidateServiceProvider), isNotNull);
    expect(container.read(activityLogServiceProvider), isNotNull);
    expect(container.read(inputActivityEventServiceProvider), isNotNull);
    expect(container.read(activityFusionServiceProvider), isNotNull);
    expect(container.read(reportGenerationServiceProvider), isNotNull);
    expect(container.read(reportPushServiceProvider), isNotNull);

    final taskListId = await calendarRepo.createTaskList(
      TaskListsCompanion.insert(
        name: 'Provider inbox',
        createdAt: _now,
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final taskId = await taskRepo.create(
      TaskItemsCompanion.insert(
        uid: 'provider-task',
        dtstamp: _now,
        summary: 'Provider constructed task',
        taskListId: Value(taskListId),
      ),
      audit: false,
    );
    final eventCalendarId = await calendarRepo.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Provider calendar',
        createdAt: _now,
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final eventId = await eventRepo.create(
      CalendarEventsCompanion.insert(
        uid: 'provider-event',
        dtstamp: _now,
        summary: 'Provider constructed event',
        dtstart: _now,
        eventCalendarId: Value(eventCalendarId),
      ),
      audit: false,
    );
    final recordId = await activityRepo.insertImportedRecord(
      startTime: _now,
      endTime: _now.add(const Duration(minutes: 20)),
      processName: 'Code.exe',
      category: 'coding',
      deviceId: 'test-device',
      platform: 'test',
    );

    expect(
        (await taskRepo.getById(taskId))?.summary, 'Provider constructed task');
    expect((await eventRepo.getById(eventId))?.summary,
        'Provider constructed event');
    expect((await activityRepo.getById(recordId))?.processName, 'Code.exe');
    final history = await trackerRepo.getHistorySummary();
    expect(history.totalRecords, greaterThanOrEqualTo(1));
    expect(
        await container.read(trackingUploadServiceProvider.future), isNotNull);
  });

  test('selected-date stream providers read real repository ranges', () async {
    final db = createTestDatabase();
    final container = createContainer(db: db);
    final selected = DateTime(2026, 6, 9, 15, 30);
    final selectedStart = DateTime(2026, 6, 9, 9);
    final otherDay = DateTime(2026, 6, 10, 9);
    _setSelectedDate(container, selected);

    final calendarRepo = container.read(calendarBooksRepositoryProvider);
    final activeListId = await calendarRepo.createTaskList(
      TaskListsCompanion.insert(
        name: 'Active list',
        createdAt: _now,
        isDefault: const Value(true),
      ),
      audit: false,
    );
    await calendarRepo.createTaskList(
      TaskListsCompanion.insert(
        name: 'Archived list',
        createdAt: _now,
        isArchived: const Value(true),
      ),
      audit: false,
    );
    final eventCalendarId = await calendarRepo.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Visible calendar',
        createdAt: _now,
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final taskRepo = container.read(taskRepositoryProvider);
    final eventRepo = container.read(eventRepositoryProvider);
    await taskRepo.create(
      TaskItemsCompanion.insert(
        uid: 'task-selected',
        dtstamp: _now,
        summary: 'Selected day task',
        dtstart: Value(selectedStart),
        taskListId: Value(activeListId),
      ),
      audit: false,
    );
    await taskRepo.create(
      TaskItemsCompanion.insert(
        uid: 'task-other-day',
        dtstamp: _now,
        summary: 'Other day task',
        dtstart: Value(otherDay),
        taskListId: Value(activeListId),
      ),
      audit: false,
    );
    await eventRepo.create(
      CalendarEventsCompanion.insert(
        uid: 'event-selected',
        dtstamp: _now,
        summary: 'Selected day event',
        dtstart: selectedStart,
        eventCalendarId: Value(eventCalendarId),
      ),
      audit: false,
    );

    final selectedTasks =
        await container.read(tasksForSelectedDateProvider.future);
    final selectedEvents =
        await container.read(eventsForSelectedDateProvider.future);
    final allTasks = await container.read(allTasksProvider.future);
    final managementTasks =
        await container.read(managementTasksProvider.future);
    final managementEvents =
        await container.read(managementEventsProvider.future);
    final activeLists = await container.read(allTaskListsProvider.future);
    final archivedLists =
        await container.read(archivedTaskListsProvider.future);
    final calendars = await container.read(allEventCalendarsProvider.future);

    expect(selectedTasks.map((task) => task.summary),
        contains('Selected day task'));
    expect(selectedTasks.map((task) => task.summary),
        isNot(contains('Other day task')));
    expect(selectedEvents.map((event) => event.summary),
        contains('Selected day event'));
    expect(allTasks.map((task) => task.summary), contains('Selected day task'));
    expect(managementTasks.map((task) => task.summary),
        contains('Other day task'));
    expect(managementEvents.map((event) => event.summary),
        contains('Selected day event'));
    expect(activeLists.map((list) => list.name), contains('Active list'));
    expect(archivedLists.map((list) => list.name), contains('Archived list'));
    expect(calendars.map((calendar) => calendar.name),
        contains('Visible calendar'));
  });

  test('activityDaySummaryProvider falls back to local rows when server lags',
      () async {
    final db = createTestDatabase();
    await _markActivityLogDatabaseInitialized(db);
    final day = DateTime(2026, 6, 9);
    await _insertRawActivityLog(
      db,
      entry: ActivityLogEntry(
        timestamp: day.add(const Duration(hours: 9)),
        type: ActivityLogEntryType.sample,
        processName: 'Code.exe',
        windowTitle: 'provider_test.dart',
        category: 'coding',
        durationMinutes: 60,
        keyCount: 120,
      ),
    );
    await db.into(db.activityRecords).insert(
          ActivityRecordsCompanion.insert(
            startTime: day.add(const Duration(hours: 9)),
            endTime: Value(day.add(const Duration(hours: 10, minutes: 10))),
            durationMinutes: const Value(70),
            keyCount: const Value(120),
            mouseClicks: const Value(8),
            mouseMovePx: const Value(900),
            scrollPx: const Value(240),
            processName: const Value('Code.exe'),
            windowTitle: const Value('provider_test.dart'),
            category: const Value('coding'),
            manualLabel: const Value('Provider work'),
            source: const Value('test'),
          ),
        );
    final store = _TrackingStoreFake(
      activityDaySummaryBuilder: (date) => <String, dynamic>{
        'range': <String, Object?>{
          'start': DateTime(date.year, date.month, date.day).toIso8601String(),
          'end':
              DateTime(date.year, date.month, date.day + 1).toIso8601String(),
        },
        'source': 'server',
        'insights': <String, Object?>{
          'totalMinutes': 10,
        },
        'previewRecords': <Map<String, Object?>>[],
      },
    );
    final container = createContainer(db: db, store: store);
    _setSelectedDate(container, day);

    final summary = await container.read(activityDaySummaryProvider.future);
    final records = await container.read(activityRecordsForDateProvider.future);
    final insights = container.read(activityInsightsProvider);
    final sessions = container.read(workSessionsForDateProvider);

    expect(summary['source'], 'local-fallback');
    final summaryInsights = summary['insights'] as Map<String, Object?>;
    expect(summaryInsights['totalMinutes'], 70);
    expect(summaryInsights['totalKeys'], 120);
    expect(summaryInsights['totalClicks'], 8);
    expect(records, hasLength(1));
    expect(records.single.processName, 'Code.exe');
    expect(records.single.manualLabel, 'Provider work');
    expect(insights.totalMinutes, 70);
    expect(insights.totalKeys, 120);
    expect(sessions, isEmpty);
  });

  test('activityDaySummaryProvider gives open-ended local rows one minute',
      () async {
    final db = createTestDatabase();
    await _markActivityLogDatabaseInitialized(db);
    final day = DateTime(2026, 6, 9);
    await _insertRawActivityLog(
      db,
      entry: ActivityLogEntry(
        timestamp: day.add(const Duration(hours: 9)),
        type: ActivityLogEntryType.sample,
        processName: 'OpenEnded.exe',
        windowTitle: 'open row',
        category: 'coding',
        durationMinutes: 12,
      ),
    );
    await db.into(db.activityRecords).insert(
          ActivityRecordsCompanion.insert(
            startTime: day.add(const Duration(hours: 9)),
            endTime: const Value(null),
            durationMinutes: const Value(0),
            processName: const Value('OpenEnded.exe'),
            windowTitle: const Value('open row'),
            category: const Value('coding'),
            source: const Value('test'),
          ),
        );
    await db.into(db.activityRecords).insert(
          ActivityRecordsCompanion.insert(
            startTime: day.add(const Duration(hours: 10)),
            endTime: Value(day.add(const Duration(hours: 10, minutes: 7))),
            durationMinutes: const Value(0),
            processName: const Value('EndedFallback.exe'),
            windowTitle: const Value('ended row'),
            category: const Value('coding'),
            source: const Value('test'),
          ),
        );
    final store = _TrackingStoreFake(
      activityDaySummaryBuilder: (date) => <String, dynamic>{
        'range': <String, Object?>{
          'start': DateTime(date.year, date.month, date.day).toIso8601String(),
          'end':
              DateTime(date.year, date.month, date.day + 1).toIso8601String(),
        },
        'source': 'server',
        'insights': <String, Object?>{'totalMinutes': 1},
        'previewRecords': <Map<String, Object?>>[],
      },
    );
    final container = createContainer(db: db, store: store);
    _setSelectedDate(container, day);

    final summary = await container.read(activityDaySummaryProvider.future);

    expect(summary['source'], 'local-fallback');
    final summaryInsights = summary['insights'] as Map<String, Object?>;
    expect(summaryInsights['totalMinutes'], 8);
    final records = summary['previewRecords'] as List<Object?>;
    final openPayload = (records.first as Map<String, Object?>)['payload']
        as Map<String, Object?>;
    final endedPayload = (records.last as Map<String, Object?>)['payload']
        as Map<String, Object?>;
    expect(records.first, containsPair('metricMinutes', 1));
    expect(openPayload, containsPair('durationMinutes', 1));
    expect(openPayload, isNot(contains('endTime')));
    expect(records.last, containsPair('metricMinutes', 7));
    expect(endedPayload, containsPair('durationMinutes', 7));
    expect(
      endedPayload,
      containsPair('endTime',
          day.add(const Duration(hours: 10, minutes: 7)).toIso8601String()),
    );
  });

  test('refresh tick reloads input option and recent input providers',
      () async {
    final store = _TrackingStoreFake(
      processOptions: <String>['Code.exe'],
      categoryOptions: <String>['coding'],
      inputEventsBuilder: (call) => <String, dynamic>{
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'serverId': 'event-${call.offset}',
            'objectType': 'tracked_input_event',
            'metricCount': '4',
            'occurredAt': DateTime(2026, 6, 9, 10).toIso8601String(),
            'payload': <String, Object?>{
              'eventUid': 'event-${call.offset}',
              'sequenceId': '42',
              'kind': 'mouse_move',
              'process_name': 'Code.exe',
              'window_title': 'provider_test.dart',
              'category': 'coding',
              'move_distance': '320',
            },
          },
        ],
      },
    );
    final container = createContainer(db: createTestDatabase(), store: store);

    expect(await container.read(inputEventProcessOptionsProvider.future),
        <String>['Code.exe']);
    final events =
        await container.read(recentTrackedInputEventsProvider.future);
    expect(store.inputEventsCalls.single.limit, 12);
    expect(events.single.eventUid, 'event-0');
    expect(events.single.kind, TrackedInputEventKind.mouseMove);
    expect(events.single.eventCount, 4);
    expect(events.single.moveDistance, 320);

    store.processOptions = <String>['Terminal.exe'];
    final tick = container.read(activityLogRefreshTickProvider.notifier);
    tick.state = tick.state + 1;

    expect(await container.read(inputEventProcessOptionsProvider.future),
        <String>['Terminal.exe']);
    await container.read(recentTrackedInputEventsProvider.future);
    expect(store.filterOptionsCalls, hasLength(2));
    expect(store.inputEventsCalls, hasLength(2));
  });

  test('archive providers expose storage paths, days, and archived rows',
      () async {
    final storage = await setUpTempAppStorage(
      prefix: 'tracker-provider-archives-',
    );
    final db = createTestDatabase();
    final container = createContainer(db: db);
    final day = DateTime(2026, 6, 9, 14, 30);
    _setSelectedDate(container, day);

    await container.read(activityLogServiceProvider).append(
          ActivityLogEntry(
            timestamp: day,
            type: ActivityLogEntryType.sample,
            processName: 'Code.exe',
            windowTitle: 'provider archives',
            category: 'coding',
            label: 'Archive provider sample',
            durationMinutes: 15,
            keyCount: 30,
            mouseClicks: 2,
            keySequence: 'Ctrl+S',
          ),
        );
    await container.read(inputActivityEventServiceProvider).appendEvents(
      events: <RawInputEvent>[
        RawInputEvent(
          sequenceId: 101,
          timestampMicros: day.microsecondsSinceEpoch,
          kind: RawInputEventKind.mouseWheel,
          eventCount: 4,
          processName: 'Code.exe',
          className: 'Editor',
          windowTitle: 'provider archives',
          mouseButton: 'wheel_down',
          wheelDelta: -120,
        ),
      ],
      bindings: const <InputEventContextBinding>[
        InputEventContextBinding(
          recordId: 7,
          processName: 'Code.exe',
          className: 'Editor',
          windowTitle: 'provider archives',
          category: 'coding',
          activityLabel: 'Archive input sample',
        ),
      ],
    );

    final activityPath =
        await container.read(activityLogArchiveDirectoryPathProvider.future);
    final inputPath =
        await container.read(inputEventArchiveDirectoryPathProvider.future);
    final storagePath =
        await container.read(activityLogStoragePathProvider.future);
    final entries =
        await container.read(activityLogEntriesForDateProvider.future);
    final activityDays =
        await container.read(activityLogArchiveDaysProvider.future);
    final inputDays =
        await container.read(inputEventArchiveDaysProvider.future);
    final archivedEntries = await container.read(
      activityLogArchiveEntriesForDateProvider(day).future,
    );
    final archivedEvents = await container.read(
      inputEventArchiveEntriesForDateProvider(day).future,
    );

    expect(storagePath, isNotEmpty);
    expect(activityPath, contains(storage.path));
    expect(inputPath, contains(storage.path));
    expect(activityDays.single.dayKey, '2026-06-09');
    expect(inputDays.single.dayKey, '2026-06-09');
    expect(entries.single.label, 'Archive provider sample');
    expect(archivedEntries.single.keySequence, 'Ctrl+S');
    expect(archivedEvents.single.sequenceId, 101);
    expect(archivedEvents.single.kind, TrackedInputEventKind.mouseWheel);
    expect(archivedEvents.single.category, 'coding');
    expect(archivedEvents.single.activityLabel, 'Archive input sample');
  });

  test('activityHeatmapSeriesProvider applies recommended and override ranges',
      () async {
    final selected = DateTime(2026, 6, 9, 15);
    final store = _TrackingStoreFake(
      trackingSummaryResponse: <String, dynamic>{
        'canonicalObjectCounts': <String, Object?>{
          'activity_record': 5,
        },
        'latestReceivedAtByKind': <String, Object?>{
          'activity_record': selected.toIso8601String(),
        },
      },
      activityHeatmapBuilder: (call) => <String, dynamic>{
        'buckets': <Map<String, Object?>>[
          <String, Object?>{
            'bucketStart': call.start?.toIso8601String(),
            'recordCount': 2,
            'totalMinutes': 45,
          },
        ],
      },
    );
    final container = createContainer(db: createTestDatabase(), store: store);
    _setSelectedDate(container, selected);

    final dailySeries =
        await container.read(activityHeatmapSeriesProvider.future);

    expect(dailySeries.scale, ActivityHeatmapScale.day);
    expect(dailySeries.buckets, hasLength(30));
    expect(dailySeries.maxMinutes, 45);
    expect(store.activityHeatmapCalls.single.start, DateTime(2026, 6));
    expect(store.activityHeatmapCalls.single.end, DateTime(2026, 7));
    expect(store.activityHeatmapCalls.single.bucket, 'day');

    container.read(activityHeatmapScaleOverrideProvider.notifier).state =
        ActivityHeatmapScale.hour;
    final hourlySeries =
        await container.read(activityHeatmapSeriesProvider.future);

    expect(hourlySeries.scale, ActivityHeatmapScale.hour);
    expect(hourlySeries.buckets, hasLength(24));
    expect(store.activityHeatmapCalls.last.start, DateTime(2026, 6, 9));
    expect(store.activityHeatmapCalls.last.end, DateTime(2026, 6, 10));
    expect(store.activityHeatmapCalls.last.bucket, 'hour');
  });

  test('range analysis provider handles default, data, and error states',
      () async {
    final day = DateTime(2026, 6, 9);
    final store = _TrackingStoreFake(
      rangeAnalysisBuilder: (call) => <String, dynamic>{
        'insights': <String, Object?>{
          'totalMinutes': 40,
          'focusMinutes': 35,
          'totalKeys': 90,
          'productiveRecordCount': 1,
        },
        'previewRecords': <Map<String, Object?>>[
          <String, Object?>{
            'serverId': 'range-record',
            'objectType': 'activity_record',
            'occurredAt': day.add(const Duration(hours: 9)).toIso8601String(),
            'metricMinutes': 40,
            'payload': <String, Object?>{
              'processName': 'Code.exe',
              'category': 'coding',
              'keyCount': 90,
            },
          },
        ],
        'sessions': <Map<String, Object?>>[
          <String, Object?>{
            'startTime': day.add(const Duration(hours: 9)).toIso8601String(),
            'durationMinutes': 40,
            'processNames': <String>['Code.exe'],
            'categories': <String>['coding'],
          },
        ],
      },
    );
    final container = createContainer(db: createTestDatabase(), store: store);

    expect(container.read(trackerRangeAnalysisProvider).value, isNull);
    expect(await container.read(trackerRangeAnalysisRecordsProvider.future),
        isEmpty);
    expect(await container.read(trackerRangeAnalysisViewModelProvider.future),
        isEmpty);

    container
        .read(trackerHistorySelectedAnalysisBucketProvider.notifier)
        .state = ActivityHeatmapBucket(
      start: day.add(const Duration(hours: 9)),
      end: day.add(const Duration(hours: 10)),
      shortLabel: '09',
      longLabel: '09:00',
      completedCount: 1,
      totalMinutes: 40,
    );
    await container.read(trackerRangeAnalysisRecordsProvider.future);
    await container.read(trackerRangeAnalysisLogEntriesProvider.future);
    await container.read(trackerRangeAnalysisViewModelProvider.future);

    final state = container.read(trackerRangeAnalysisProvider);
    expect(state.hasValue, isTrue);
    final snapshot = state.value!;
    expect(snapshot.records.single.processName, 'Code.exe');
    expect(snapshot.logEntries, isEmpty);
    expect(snapshot.insights.totalMinutes, 40);
    expect(snapshot.sessions.single.processName, 'Code.exe');
    expect(store.rangeAnalysisCalls.first.bucket, 'hour');
  });

  test('range analysis provider forwards hour day and month bucket boundaries',
      () async {
    final day = DateTime(2026, 6, 9);
    final store = _TrackingStoreFake();
    final container = createContainer(db: createTestDatabase(), store: store);

    Future<void> selectAndRead(ActivityHeatmapBucket bucket) async {
      container
          .read(trackerHistorySelectedAnalysisBucketProvider.notifier)
          .state = bucket;
      container.read(trackerRangeAnalysisProvider);
      await container.read(trackerRangeAnalysisRecordsProvider.future);
      await container.read(trackerRangeAnalysisViewModelProvider.future);
    }

    await selectAndRead(
      ActivityHeatmapBucket(
        start: day.add(const Duration(hours: 9)),
        end: day.add(const Duration(hours: 10)),
        shortLabel: '09',
        longLabel: '09:00',
        completedCount: 1,
        totalMinutes: 25,
      ),
    );
    await selectAndRead(
      ActivityHeatmapBucket(
        start: day,
        end: day.add(const Duration(days: 1)),
        shortLabel: '09',
        longLabel: '2026-06-09',
        completedCount: 2,
        totalMinutes: 60,
      ),
    );
    await selectAndRead(
      ActivityHeatmapBucket(
        start: DateTime(2026, 6),
        end: DateTime(2026, 7),
        shortLabel: '06',
        longLabel: '2026-06',
        completedCount: 3,
        totalMinutes: 120,
      ),
    );

    expect(
      store.rangeAnalysisCalls.map((call) => call.bucket),
      <String>['hour', 'hour', 'day', 'day', 'month', 'month'],
    );
    expect(
        store.rangeAnalysisCalls[0].start, day.add(const Duration(hours: 9)));
    expect(store.rangeAnalysisCalls[0].end, day.add(const Duration(hours: 10)));
    expect(store.rangeAnalysisCalls[2].start, day);
    expect(store.rangeAnalysisCalls[2].end, day.add(const Duration(days: 1)));
    expect(store.rangeAnalysisCalls[4].start, DateTime(2026, 6));
    expect(store.rangeAnalysisCalls[4].end, DateTime(2026, 7));
  });

  test('server provider errors propagate through futures and aggregate state',
      () async {
    final error = StateError('server is unavailable');
    final day = DateTime(2026, 6, 9);
    final store = _TrackingStoreFake()
      ..activityRecordsError = error
      ..rangeAnalysisError = error;
    final container = createContainer(db: createTestDatabase(), store: store);

    await expectLater(
      container.read(
        serverActivityRecordsPageProvider(
          ServerRecordQuery(start: day, end: day.add(const Duration(days: 1))),
        ).future,
      ),
      throwsA(same(error)),
    );

    container
        .read(trackerHistorySelectedAnalysisBucketProvider.notifier)
        .state = ActivityHeatmapBucket(
      start: day,
      end: day.add(const Duration(days: 1)),
      shortLabel: '9',
      longLabel: 'June 9',
      completedCount: 0,
      totalMinutes: 0,
    );
    await expectLater(
      container.read(trackerRangeAnalysisRecordsProvider.future),
      throwsA(same(error)),
    );

    final aggregate = container.read(trackerRangeAnalysisProvider);
    expect(aggregate.hasError, isTrue);
    expect(aggregate.error, same(error));
    expect(store.activityRecordsCalls.single.limit, 100);
    expect(store.activityRecordsCalls.single.offset, 0);
  });

  test('trackingUploadDiagnosticsProvider reports real pending rows', () async {
    final db = createTestDatabase();
    final at = DateTime(2026, 6, 9, 9);
    await db.into(db.activityRecords).insert(
          ActivityRecordsCompanion.insert(
            startTime: at,
            endTime: Value(at.add(const Duration(minutes: 5))),
            durationMinutes: const Value(5),
            processName: const Value('Code.exe'),
          ),
        );
    await _insertTrackedInputEvent(db, at: at, sequenceId: 1);
    await _insertRawActivityLog(
      db,
      entry: ActivityLogEntry(
        timestamp: at,
        type: ActivityLogEntryType.snapshot,
        processName: 'Code.exe',
        durationMinutes: 5,
      ),
    );
    await db.setSetting(TrackingUploadService.lastCompletedAtKey,
        DateTime(2026, 6, 9, 12).toIso8601String());
    await db.setSetting(TrackingUploadService.lastErrorKey, 'previous error');
    final container = createContainer(
      db: db,
      overrides: [
        trackingIngestApiProvider.overrideWith(
          (ref) async => _UnusedTrackingIngestApi(),
        ),
      ],
    );

    final diagnostics =
        await container.read(trackingUploadDiagnosticsProvider.future);

    expect(diagnostics['lastActivityRecordId'], 0);
    expect(diagnostics['lastInputEventId'], 0);
    expect(diagnostics['lastRawLogId'], 0);
    expect(diagnostics['pendingActivityRecords'], 1);
    expect(diagnostics['pendingInputEvents'], 1);
    expect(diagnostics['pendingRawLogs'], 1);
    expect(diagnostics['lastCompletedAt'], isNotNull);
    expect(diagnostics['lastError'], 'previous error');
  });
}

final _now = DateTime(2026, 6, 9, 8);

void _setSelectedDate(ProviderContainer container, DateTime date) {
  final dynamic notifier = container.read(selectedDateProvider.notifier);
  notifier.setDate(date);
}

String _dayKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

Future<void> _markActivityLogDatabaseInitialized(AppDatabase db) async {
  await db.setBoolSetting('tracker.legacy_jsonl_to_database_migrated', true);
  await db.setBoolSetting('tracker.database_to_daily_jsonl_backfilled', true);
}

Future<int> _insertRawActivityLog(
  AppDatabase db, {
  required ActivityLogEntry entry,
}) async {
  await db.customStatement(
    '''
    INSERT INTO raw_activity_logs (
      entry_uid,
      occurred_at,
      day_key,
      entry_type,
      record_id,
      process_name,
      window_title,
      category,
      label,
      is_ignored,
      payload_json,
      created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    <Object?>[
      '${entry.timestamp.toIso8601String()}-${entry.type.value}',
      entry.timestamp.toIso8601String(),
      _dayKey(entry.timestamp),
      entry.type.value,
      entry.recordId,
      entry.processName,
      entry.windowTitle,
      entry.category,
      entry.label,
      entry.isIgnored ? 1 : 0,
      jsonEncode(entry.toJson()),
      DateTime.now().toIso8601String(),
    ],
  );
  final row =
      await db.customSelect('SELECT last_insert_rowid() AS id').getSingle();
  return row.read<int>('id');
}

Future<int> _insertTrackedInputEvent(
  AppDatabase db, {
  required DateTime at,
  required int sequenceId,
}) async {
  await db.customStatement(
    '''
    INSERT INTO tracked_input_events (
      event_uid,
      sequence_id,
      occurred_at,
      day_key,
      event_kind,
      record_id,
      process_name,
      class_name,
      window_title,
      category,
      activity_label,
      is_ignored,
      key_code,
      key_label,
      mouse_button,
      wheel_delta,
      delta_x,
      delta_y,
      move_distance,
      event_count,
      token_text,
      payload_json,
      created_at
    ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, 0, ?, ?, NULL, 0, ?, ?, ?, ?, ?, ?, ?)
    ''',
    <Object?>[
      'input-$sequenceId',
      sequenceId,
      at.toIso8601String(),
      _dayKey(at),
      'key_down',
      'Code.exe',
      'Editor',
      'provider_test.dart',
      'coding',
      'Implementation',
      65,
      'A',
      4,
      2,
      120,
      3,
      'a',
      jsonEncode(<String, Object?>{'source': 'provider-test'}),
      DateTime.now().toIso8601String(),
    ],
  );
  final row =
      await db.customSelect('SELECT last_insert_rowid() AS id').getSingle();
  return row.read<int>('id');
}

class _UnusedTrackingIngestApi extends Mock implements TrackingIngestApi {}

class _FilterOptionsCall {
  const _FilterOptionsCall({required this.start, required this.end});

  final DateTime? start;
  final DateTime? end;
}

class _ActivityHeatmapCall {
  const _ActivityHeatmapCall({
    required this.start,
    required this.end,
    required this.bucket,
  });

  final DateTime? start;
  final DateTime? end;
  final String bucket;
}

class _RangeAnalysisCall {
  const _RangeAnalysisCall({
    required this.start,
    required this.end,
    required this.bucket,
  });

  final DateTime start;
  final DateTime end;
  final String bucket;
}

class _ActivityRecordsCall {
  const _ActivityRecordsCall({
    required this.start,
    required this.end,
    required this.processName,
    required this.category,
    required this.taskId,
    required this.limit,
    required this.offset,
  });

  final DateTime? start;
  final DateTime? end;
  final String? processName;
  final String? category;
  final int? taskId;
  final int limit;
  final int offset;
}

class _InputEventsCall {
  const _InputEventsCall({
    required this.start,
    required this.end,
    required this.processName,
    required this.category,
    required this.eventKind,
    required this.limit,
    required this.offset,
  });

  final DateTime? start;
  final DateTime? end;
  final String? processName;
  final String? category;
  final String? eventKind;
  final int limit;
  final int offset;
}

class _TrackingStoreFake implements TrackingServerFirstStore {
  _TrackingStoreFake({
    this.processOptions = const <String>[],
    this.categoryOptions = const <String>[],
    this.trackingSummaryResponse,
    this.activityDaySummaryBuilder,
    this.activityHeatmapBuilder,
    this.rangeAnalysisBuilder,
    this.inputEventsBuilder,
  });

  List<String> processOptions;
  List<String> categoryOptions;
  Map<String, dynamic>? trackingSummaryResponse;
  Map<String, dynamic> Function(DateTime date)? activityDaySummaryBuilder;
  Map<String, dynamic> Function(_ActivityHeatmapCall call)?
      activityHeatmapBuilder;
  Map<String, dynamic> Function(_RangeAnalysisCall call)? rangeAnalysisBuilder;
  Map<String, dynamic> Function(_InputEventsCall call)? inputEventsBuilder;

  final filterOptionsCalls = <_FilterOptionsCall>[];
  final activityHeatmapCalls = <_ActivityHeatmapCall>[];
  final rangeAnalysisCalls = <_RangeAnalysisCall>[];
  final activityRecordsCalls = <_ActivityRecordsCall>[];
  final inputEventsCalls = <_InputEventsCall>[];

  Object? activityRecordsError;
  Object? rangeAnalysisError;

  @override
  Future<Map<String, dynamic>> trackingSummary({
    DateTime? start,
    DateTime? end,
  }) async {
    return trackingSummaryResponse ??
        <String, dynamic>{
          'canonicalObjectCounts': <String, Object?>{},
          'latestReceivedAtByKind': <String, Object?>{},
        };
  }

  @override
  Future<Map<String, dynamic>> activityDaySummary({
    required DateTime date,
  }) async {
    return activityDaySummaryBuilder?.call(date) ??
        <String, dynamic>{
          'insights': <String, Object?>{},
          'previewRecords': <Map<String, Object?>>[],
          'sessions': <Map<String, Object?>>[],
        };
  }

  @override
  Future<Map<String, dynamic>> activityHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'day',
    String? processName,
    String? category,
    int? taskId,
  }) async {
    final call = _ActivityHeatmapCall(
      start: start,
      end: end,
      bucket: bucket,
    );
    activityHeatmapCalls.add(call);
    return activityHeatmapBuilder?.call(call) ??
        <String, dynamic>{'buckets': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> rangeAnalysis({
    required DateTime start,
    required DateTime end,
    String bucket = 'day',
  }) async {
    final call = _RangeAnalysisCall(
      start: start,
      end: end,
      bucket: bucket,
    );
    rangeAnalysisCalls.add(call);
    final error = rangeAnalysisError;
    if (error != null) {
      throw error;
    }
    return rangeAnalysisBuilder?.call(call) ??
        <String, dynamic>{
          'insights': <String, Object?>{},
          'previewRecords': <Map<String, Object?>>[],
          'sessions': <Map<String, Object?>>[],
        };
  }

  @override
  Future<Map<String, dynamic>> filterOptions({
    DateTime? start,
    DateTime? end,
  }) async {
    filterOptionsCalls.add(_FilterOptionsCall(start: start, end: end));
    return <String, dynamic>{
      'processOptions': processOptions,
      'categoryOptions': categoryOptions,
    };
  }

  @override
  Future<Map<String, dynamic>> activityRecords({
    DateTime? start,
    DateTime? end,
    String? processName,
    String? category,
    int? taskId,
    int limit = 100,
    int offset = 0,
  }) async {
    activityRecordsCalls.add(
      _ActivityRecordsCall(
        start: start,
        end: end,
        processName: processName,
        category: category,
        taskId: taskId,
        limit: limit,
        offset: offset,
      ),
    );
    final error = activityRecordsError;
    if (error != null) {
      throw error;
    }
    return <String, dynamic>{
      'items': <Map<String, Object?>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> inputEvents({
    DateTime? start,
    DateTime? end,
    String? processName,
    String? category,
    String? eventKind,
    int limit = 100,
    int offset = 0,
  }) async {
    final call = _InputEventsCall(
      start: start,
      end: end,
      processName: processName,
      category: category,
      eventKind: eventKind,
      limit: limit,
      offset: offset,
    );
    inputEventsCalls.add(call);
    return inputEventsBuilder?.call(call) ??
        <String, dynamic>{
          'items': <Map<String, Object?>>[],
        };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
