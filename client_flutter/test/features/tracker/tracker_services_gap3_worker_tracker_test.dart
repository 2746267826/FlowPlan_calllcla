import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/tracking_ingest_api.dart';
import 'package:flowplanv2/core/server_first/tracking_server_first_store.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flowplanv2/features/tracker/services/activity_log_service.dart';
import 'package:flowplanv2/features/tracker/services/android_usage_import_service.dart';
import 'package:flowplanv2/features/tracker/services/android_usage_stats_service.dart';
import 'package:flowplanv2/features/tracker/services/input_activity_event_service.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';
import '../../test_support/tracking_store_test_double.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    debugTrackerPlatformOverride = null;
    debugRawInputServiceOverride = null;
  });

  group('tracked input and work session model gaps', () {
    test(
        'input labels cover numeric, numpad, function, token, and fallback paths',
        () {
      expect(inputKeyLabelForCode(48), '0');
      expect(inputKeyLabelForCode(90), 'Z');
      expect(inputKeyLabelForCode(96), contains('0'));
      expect(inputKeyLabelForCode(123), 'F12');
      expect(inputKeyLabelForCode(999), 'VK_999');

      expect(inputMouseButtonLabel('wheel_left'), isNot('wheel_left'));
      expect(inputMouseButtonLabel('wheel_right'), isNot('wheel_right'));
      expect(inputMouseButtonLabel('move'), isNot('move'));
      expect(inputMouseButtonLabel('button'), isNot('button'));
      expect(inputMouseButtonLabel('custom'), 'custom');

      expect(describeInputToken(null), '');
      expect(describeInputToken(''), '');
      expect(describeInputToken('[BACKSPACE]'), contains('['));
      expect(describeInputToken('[ESC]'), '[Esc]');
      expect(describeInputToken('\n'), contains('['));
      expect(describeInputToken('\t'), '[Tab]');
      expect(describeInputToken(' '), contains('['));
      expect(describeInputToken('plain'), 'plain');
    });

    test('work session labels and signatures fall through sparse records', () {
      final base = DateTime(2026, 6, 10, 9);
      final processOnly = _activityRecord(
        id: 1,
        start: base,
        processName: ' Terminal.exe ',
        category: null,
      );
      final titleOnly = _activityRecord(
        id: 2,
        start: base.add(const Duration(minutes: 10)),
        processName: null,
        category: null,
        windowTitle: ' Untitled notes ',
      );
      final unknown = _activityRecord(
        id: 3,
        start: base.add(const Duration(minutes: 20)),
        processName: null,
        category: null,
        windowTitle: null,
      );

      expect(WorkSessionGrouper.preferredLabel(processOnly), 'Terminal.exe');
      expect(WorkSessionGrouper.preferredLabel(titleOnly), 'Untitled notes');
      expect(WorkSessionGrouper.preferredLabel(unknown), isNotEmpty);
      expect(WorkSessionGrouper.strictSignature(processOnly),
          'process:terminal.exe');
      expect(WorkSessionGrouper.strictSignature(titleOnly),
          'window:untitled notes');
      expect(WorkSessionGrouper.strictSignature(unknown), 'unknown');
      expect(WorkSessionGrouper.contextSignature(processOnly),
          'process:terminal.exe');
      expect(WorkSessionGrouper.contextSignature(titleOnly),
          'window:untitled notes');
      expect(WorkSessionGrouper.contextSignature(unknown), 'unknown');
    });

    test(
        'short interruption run refuses wide internal gaps and rewinds after merge',
        () {
      final base = DateTime(2026, 6, 10, 8);
      final wideGapSessions = WorkSessionGrouper.fromRecords(<ActivityRecord>[
        _activityRecord(id: 1, start: base, category: 'coding'),
        _activityRecord(
          id: 2,
          start: base.add(const Duration(minutes: 7)),
          durationMinutes: 1,
          processName: 'Chat.exe',
          category: 'chat',
          keyCount: 1,
          mouseClicks: 0,
        ),
        _activityRecord(
          id: 3,
          start: base.add(const Duration(minutes: 12)),
          durationMinutes: 1,
          processName: 'Mail.exe',
          category: 'mail',
          keyCount: 1,
          mouseClicks: 0,
        ),
        _activityRecord(
          id: 4,
          start: base.add(const Duration(minutes: 15)),
          processName: 'Terminal.exe',
          category: 'coding',
        ),
      ]);

      expect(wideGapSessions, hasLength(4));

      final mergedAfterEarlierSession =
          WorkSessionGrouper.fromRecords(<ActivityRecord>[
        _activityRecord(
          id: 10,
          start: base.subtract(const Duration(hours: 1)),
          processName: 'Browser.exe',
          category: 'research',
        ),
        _activityRecord(
          id: 11,
          start: base.add(const Duration(hours: 1)),
          processName: 'Code.exe',
          category: 'coding',
          keyCount: 20,
        ),
        _activityRecord(
          id: 12,
          start: base.add(const Duration(hours: 1, minutes: 6)),
          durationMinutes: 1,
          processName: 'Chat.exe',
          category: 'chat',
          keyCount: 1,
          mouseClicks: 0,
        ),
        _activityRecord(
          id: 13,
          start: base.add(const Duration(hours: 1, minutes: 9)),
          processName: 'Terminal.exe',
          category: 'coding',
          keyCount: 20,
        ),
      ]);

      expect(mergedAfterEarlierSession, hasLength(2));
      expect(mergedAfterEarlierSession.last.records.map((record) => record.id),
          <int>[11, 12, 13]);
      expect(mergedAfterEarlierSession.last.interruptionCount, 1);
    });

    test('ignored gap merge rewinds after an earlier unrelated session', () {
      final base = DateTime(2026, 6, 10, 13);

      final sessions = WorkSessionGrouper.fromRecords(<ActivityRecord>[
        _activityRecord(
          id: 20,
          start: base.subtract(const Duration(hours: 1)),
          processName: 'Browser.exe',
          category: 'research',
        ),
        _activityRecord(
          id: 21,
          start: base,
          processName: 'Code.exe',
          category: 'coding',
        ),
        _activityRecord(
          id: 22,
          start: base.add(const Duration(minutes: 6)),
          durationMinutes: 1,
          processName: 'FlowPlanV2.exe',
          windowTitle: 'FlowPlanV2 dashboard',
          category: 'system',
        ),
        _activityRecord(
          id: 23,
          start: base.add(const Duration(minutes: 8)),
          processName: 'Terminal.exe',
          category: 'coding',
        ),
      ]);

      expect(sessions, hasLength(2));
      expect(sessions.last.records.map((record) => record.id), <int>[21, 23]);
      expect(sessions.last.interruptionCount, 1);
    });

    test('same-process multi-category sessions prefer process mixed label', () {
      final base = DateTime(2026, 6, 10, 14);

      final sessions = WorkSessionGrouper.fromRecords(<ActivityRecord>[
        _activityRecord(
          id: 30,
          start: base,
          processName: 'Code.exe',
          category: 'coding',
          keyCount: 20,
        ),
        _activityRecord(
          id: 31,
          start: base.add(const Duration(minutes: 6)),
          processName: 'Code.exe',
          category: 'review',
          keyCount: 10,
        ),
      ]);

      expect(sessions.single.processNames, <String>['Code.exe']);
      expect(sessions.single.categories, <String>['coding', 'review']);
      expect(sessions.single.label, contains('Code.exe'));
    });
  });

  group('InputActivityEventService gap paths', () {
    test(
        'archive read backfills from database after migration was already marked',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap3-input-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = InputActivityEventService(db);
      final at = DateTime(2026, 6, 10, 10);
      await db.setBoolSetting(
        'tracker.input_events_database_to_daily_jsonl_backfilled',
        true,
      );
      await _insertTrackedInputEvent(
        db,
        at: at,
        sequenceId: 1,
        eventUid: 'db-only-event',
      );

      final archiveFile = File(
        '${await service.getArchiveDirectoryPath()}'
        '${Platform.pathSeparator}2026-06-10.input-events.jsonl',
      );
      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }

      final events = await service.readArchivedEventsForDate(at);

      expect(events.single.eventUid, 'db-only-event');
      expect(await archiveFile.exists(), isTrue);
      expect(await archiveFile.readAsString(), contains('db-only-event'));
    });

    test('page, recent, export overwrite, and summary tie-breakers are stable',
        () async {
      final storage = await setUpTempAppStorage(prefix: 'tracker-gap3-input-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = InputActivityEventService(db);
      final base = DateTime(2026, 6, 11, 9);

      await service.appendEvents(
        events: <RawInputEvent>[
          _rawInputEvent(
            sequenceId: 1,
            at: base,
            kind: RawInputEventKind.keyDown,
            keyCode: 66,
            eventCount: 2,
          ),
          _rawInputEvent(
            sequenceId: 2,
            at: base.add(const Duration(minutes: 1)),
            kind: RawInputEventKind.keyDown,
            keyCode: 65,
            eventCount: 2,
          ),
          _rawInputEvent(
            sequenceId: 3,
            at: base.add(const Duration(hours: 1)),
            kind: RawInputEventKind.mouseMove,
            eventCount: 10,
            moveDistance: 3200,
            processName: 'Canvas.exe',
          ),
        ],
        bindings: const <InputEventContextBinding>[
          InputEventContextBinding(
            recordId: 1,
            processName: 'Code.exe',
            category: 'coding',
          ),
          InputEventContextBinding(
            recordId: 2,
            processName: 'Canvas.exe',
            category: 'design',
          ),
        ],
      );

      final page = await service.listEventsPage(
        start: base,
        end: base.add(const Duration(days: 1)),
        limit: 2,
        includeIgnored: true,
      );
      final recent = await service.listRecentEvents(
        limit: 2,
        includeIgnored: true,
      );
      final exportFile =
          File('${storage.path}${Platform.pathSeparator}events.jsonl');
      await exportFile.writeAsString('stale contents');
      await service.exportEventsToJsonl(exportFile.path, includeIgnored: true);
      final summary = await service.buildHeatmapSummary(
        InputEventQuery(
          start: base,
          end: base.add(const Duration(days: 1)),
        ),
      );

      expect(page.map((event) => event.sequenceId), <int>[1, 2]);
      expect(recent.map((event) => event.sequenceId), <int>[3, 2]);
      expect(await exportFile.readAsString(), isNot(contains('stale')));
      expect(summary.topKeys.map((key) => key.label), <String>['A', 'B']);
      expect(summary.processIntensities.first.processName, 'Canvas.exe');
      expect(summary.processIntensities.first.totalEvents, 10);
    });
  });

  group('AndroidUsageImportService edge paths', () {
    test('default platform check reports unsupported on non-Android hosts',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap3-android-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = AndroidUsageImportService(
        database: db,
        activityRecordRepository: ActivityRecordRepository(db),
        activityLogService: ActivityLogService(db),
      );

      final result = await service.importLatest();

      expect(result.supported, Platform.isAndroid);
    });

    test('same-package resumes merge labels and cap future cursors', () async {
      await setUpTempAppStorage(prefix: 'tracker-gap3-android-');
      final db = createTestDatabase();
      addTearDown(db.close);
      await db.setSetting('device.identity.id', 'android-gap3-device');
      final now = DateTime.now();
      final base = now.subtract(const Duration(minutes: 30));
      final future = now.add(const Duration(days: 1));
      final usageStats = _FakeAndroidUsageStatsService(
        events: <AndroidUsageEvent>[
          _usageEvent(base, 'com.example.editor', 'activity_resumed'),
          _usageEvent(
            base.add(const Duration(minutes: 1)),
            'com.example.editor',
            'activity_resumed',
            appLabel: 'Editor',
          ),
          _usageEvent(
            base.add(const Duration(minutes: 5)),
            'com.example.editor',
            'activity_paused',
          ),
          _usageEvent(
            base.add(const Duration(minutes: 5, seconds: 5)),
            'com.example.editor',
            'activity_resumed',
            className: 'SecondActivity',
            appLabel: 'Editor v2',
          ),
          _usageEvent(
            base.add(const Duration(minutes: 8)),
            'com.example.editor',
            'activity_paused',
            className: 'SecondActivity',
          ),
          _usageEvent(
            future,
            'com.example.future',
            'activity_resumed',
          ),
        ],
      );
      final service = AndroidUsageImportService(
        database: db,
        activityRecordRepository: ActivityRecordRepository(db),
        activityLogService: ActivityLogService(db),
        usageStatsService: usageStats,
        isAndroid: () => true,
      );

      final result = await service.importLatest();
      final records = await db.customSelect(
        '''
            SELECT process_name, package_name
            FROM activity_records
            ORDER BY start_time ASC
            ''',
      ).get();

      expect(result.supported, isTrue);
      expect(result.importedUntil, isNotNull);
      expect(result.importedUntil!.isBefore(future), isTrue);
      expect(result.latestSnapshot?.className, 'SecondActivity');
      expect(records.first.read<String>('process_name'), 'Editor');
      expect(records.first.read<String>('package_name'), 'com.example.editor');
      expect(records, hasLength(1));
    });
  });

  group('TrackingUploadService retry and payload gaps', () {
    test(
        'nested batch ids, long source uids, and partial rejections are reported',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final longUid = 'input-${List<String>.filled(220, 'x').join()}';
      await _insertTrackedInputEvent(
        db,
        at: DateTime(2026, 6, 12, 9),
        sequenceId: 4,
        eventUid: longUid,
      );
      final api = _ConfigurableTrackingIngestApi(
        createResponse: (dataKind) => <String, dynamic>{
          'batch': <String, Object?>{'id': 'nested-$dataKind'},
        },
        completeResponse: (_) => <String, dynamic>{
          'ok': true,
          'accepted': 1.9,
          'rejected': 1.2,
        },
      );
      final service = _uploadService(db, api);

      final result =
          await service.uploadPending(limitPerKind: 10, chunkSize: 10);
      final diagnostics = await service.buildUploadDiagnostics();
      final uploadedRecord = api.chunkCalls.single.records.single;

      expect(result.uploadedBatches, 1);
      expect(
        result.details,
        contains(
          isA<Map<String, Object?>>()
              .having(
                  (detail) => detail['summary'], 'summary', 'rejectedRecords')
              .having((detail) => detail['count'], 'count', 1),
        ),
      );
      expect(api.createdBatchIds.single, 'nested-tracked_input_event');
      expect(
          uploadedRecord['uid'].toString(), startsWith('tracked-input-event:'));
      expect(uploadedRecord['uid'].toString(), isNot(longUid));
      expect(
        (uploadedRecord['metadata'] as Map<String, Object?>)['sourceUid'],
        longUid,
      );
      expect(
        diagnostics['lastError'],
        contains('partial success'),
      );
      expect(
        (await db.getSetting(TrackingUploadService.lastErrorKey))!,
        contains('partial success'),
      );
    });

    test('missing batch ids and all-rejected completes preserve cursors',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      await _insertActivityRecord(
        db,
        start: DateTime(2026, 6, 12, 10),
        isAutoValue: 1,
      );
      final missingBatchApi = _ConfigurableTrackingIngestApi(
        createResponse: (_) => <String, dynamic>{},
      );
      final missingBatchService = _uploadService(db, missingBatchApi);

      await expectLater(
        missingBatchService.uploadPending(limitPerKind: 10, chunkSize: 10),
        throwsA(isA<StateError>()),
      );

      var diagnostics = await missingBatchService.buildUploadDiagnostics();
      expect(diagnostics['lastActivityRecordId'], 0);
      expect(diagnostics['pendingActivityRecords'], 1);
      expect(diagnostics['lastError'].toString(), contains('batchId'));

      final rejectedApi = _ConfigurableTrackingIngestApi(
        completeResponse: (_) => <String, dynamic>{
          'ok': true,
          'accepted': 0,
          'rejected': 2,
        },
      );
      final rejectedService = _uploadService(db, rejectedApi);
      await expectLater(
        rejectedService.uploadPending(limitPerKind: 10, chunkSize: 10),
        throwsA(isA<StateError>()),
      );

      diagnostics = await rejectedService.buildUploadDiagnostics();
      expect(diagnostics['lastActivityRecordId'], 0);
      expect(diagnostics['pendingActivityRecords'], 1);
      expect(diagnostics['lastError'].toString(), contains('rejected all'));
      expect(rejectedApi.chunkCalls.single.records.single['isAuto'], isTrue);
    });

    test('raw log uploads parse string booleans and string counts', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      await _insertRawActivityLog(
        db,
        at: DateTime(2026, 6, 12, 11),
        entryUid: 'raw-text-bool',
        isIgnoredValue: 'true',
      );
      final api = _ConfigurableTrackingIngestApi(
        completeResponse: (_) => <String, dynamic>{
          'ok': true,
          'accepted': '1',
          'rejected': '0',
        },
      );
      final service = _uploadService(db, api);

      final result =
          await service.uploadPending(limitPerKind: 10, chunkSize: 10);
      final uploaded = api.chunkCalls.single.records.single;

      expect(result.uploadedBatches, 1);
      expect(api.createdBatchIds.single, 'batch-raw_activity_log');
      expect(uploaded['isIgnored'], isTrue);
      expect(await db.getSetting(TrackingUploadService.lastErrorKey), isNull);
    });
  });

  group('ActivityFusionRepository audit and sync gaps', () {
    test('range replacement audits counts and preserves confirmed rows',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repo = _fusionRepository(db);
      final base = DateTime(2026, 6, 13, 9);
      final confirmed = await repo.insertSegment(
        _segmentDraft(base, status: 'confirmed', label: 'Confirmed'),
        sync: false,
        audit: false,
      );
      await repo.insertSegment(
        _segmentDraft(base.add(const Duration(minutes: 30)), label: 'Old'),
        sync: false,
        audit: false,
      );

      await repo.replaceSegmentsForRange(
        start: base.subtract(const Duration(minutes: 5)),
        end: base.add(const Duration(hours: 1)),
        segments: <ActivitySegmentDraft>[
          _segmentDraft(base.add(const Duration(minutes: 10)), label: 'New'),
        ],
      );

      final segments = await repo.listSegmentsInRange(
        base.subtract(const Duration(minutes: 5)),
        base.add(const Duration(hours: 1)),
      );
      final logs = await DataOperationLogRepository(db).listRecent(limit: 5);

      expect(segments.map((segment) => segment.id), contains(confirmed.id));
      expect(segments.map((segment) => segment.label), contains('New'));
      expect(segments.map((segment) => segment.label), isNot(contains('Old')));
      expect(logs.first.action, 'rebuild_activity_segments');
      expect(logs.first.metadataJson, contains('"count":1'));
    });

    test('interpretation, work-log confirmation, and rejection write sync rows',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repo = _fusionRepository(db, withSync: true);
      final base = DateTime(2026, 6, 13, 11);
      final segment = await repo.insertSegment(
        _segmentDraft(base),
        sync: true,
        audit: true,
      );
      await repo.insertInterpretation(
        segmentId: segment.id,
        summary: 'Candidate task',
        confidence: 0.4,
      );

      await repo.updateInterpretationsStatusForSegment(
        segment.id,
        status: 'accepted',
      );

      final existing = await repo.insertTaskWorkLog(
        taskId: 1,
        segmentId: segment.id,
        actualId: 10,
        startAt: base,
        endAt: base.add(const Duration(minutes: 5)),
        confidence: 0.5,
        sourceType: 'candidate',
      );
      await repo.upsertConfirmedTaskWorkLogForSegment(
        taskId: 1,
        segmentId: segment.id,
        actualId: 11,
        startAt: base,
        endAt: base.add(const Duration(minutes: 15)),
        confidence: 0.9,
        evidence: const <String, Object?>{'confirmed': true},
      );
      await repo.insertTaskWorkLog(
        taskId: 2,
        segmentId: segment.id,
        actualId: 12,
        startAt: base,
        endAt: base.add(const Duration(minutes: 8)),
        confidence: 0.3,
        sourceType: 'candidate',
      );

      await repo.rejectTaskWorkLogsForSegmentExcept(
        segmentId: segment.id,
        taskId: 1,
      );
      await repo.rejectTaskWorkLogsForSegment(segmentId: segment.id);

      final workLogs = await repo.listTaskWorkLogsForSegment(segment.id);
      final actions =
          (await DataOperationLogRepository(db).listRecent(limit: 20))
              .map((entry) => entry.action)
              .toList();
      final mutations = await db.customSelect(
        '''
            SELECT object_type, action, changed_fields_json
            FROM offline_mutations
            ORDER BY id ASC
            ''',
      ).get();

      expect(workLogs.where((log) => log.id == existing.id).single.status,
          'rejected');
      expect(actions, contains('update_activity_interpretation_status'));
      expect(actions, contains('confirm_task_work_log'));
      expect(actions, contains('reject_competing_task_work_logs'));
      expect(actions, contains('reject_task_work_logs_for_segment'));
      expect(
        mutations.map((row) => row.read<String>('object_type')),
        containsAll(<String>[
          'activity_interpretation',
          'task_work_log',
        ]),
      );
      expect(
        mutations.map((row) => row.read<String>('changed_fields_json')),
        anyElement(contains('status')),
      );
    });
  });

  group('tracker provider direct branches', () {
    test('loading branches return defaults and simple state providers mutate',
        () {
      final pendingStore = Completer<TrackingServerFirstStore>();
      final container = ProviderContainer(
        overrides: <Override>[
          trackingServerFirstStoreProvider
              .overrideWith((ref) => pendingStore.future),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(workSessionsForDateProvider), isEmpty);
      expect(container.read(dragHoveringTimelineProvider), isFalse);
      container.read(dragHoveringTimelineProvider.notifier).state = true;
      expect(container.read(dragHoveringTimelineProvider), isTrue);
    });

    test('server conversion helpers tolerate sparse and loosely typed payloads',
        () async {
      final store = TrackingStoreTestDouble(
        trackingSummaryResponseBuilder: () => <String, dynamic>{
          'canonicalObjectCounts': <Object?, Object?>{
            'activity_record': 1.6,
            'tracked_input_event': '2',
          },
          'latestReceivedAtByKind': <Object?, Object?>{
            'old': DateTime(2026, 6, 1).toIso8601String(),
            'new': DateTime(2026, 6, 10).toIso8601String(),
          },
        },
        inputEventsResponseBuilder: (_) => <String, dynamic>{
          'items': <Map<String, Object?>>[
            <String, Object?>{
              'payload': <Object?, Object?>{
                'eventKind': 'mouse_wheel',
                'eventCount': 2.4,
                'recordId': 7.8,
                'keyCode': '65',
                'isIgnored': true,
              },
            },
          ],
        },
      );
      final container = ProviderContainer(
        overrides: <Override>[
          trackingServerFirstStoreProvider.overrideWith((ref) async => store),
        ],
      );
      addTearDown(container.dispose);

      final sessions = workSessionsFromServer(<String, dynamic>{
        'sessions': <Map<String, Object?>>[
          <String, Object?>{
            'processNames': <String>['Terminal.exe'],
          },
          <String, Object?>{
            'categories': <String>['coding'],
          },
        ],
      });
      final records = activityRecordsFromServerPreview(<String, dynamic>{
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'payload': <String, Object?>{},
          },
        ],
      });
      final history =
          await container.read(activityHistorySummaryProvider.future);
      final recent =
          await container.read(recentTrackedInputEventsProvider.future);

      expect(sessions.first.label, 'Terminal.exe');
      expect(sessions.last.label, 'coding');
      expect(sessions.first.startTime, DateTime.fromMillisecondsSinceEpoch(0));
      expect(records.single.startTime, DateTime.fromMillisecondsSinceEpoch(0));
      expect(history.totalRecords, 4);
      expect(history.lastRecordAt, DateTime(2026, 6, 10));
      expect(recent.single.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
      expect(recent.single.eventUid,
          DateTime.fromMillisecondsSinceEpoch(0).toIso8601String());
      expect(recent.single.kind, TrackedInputEventKind.mouseWheel);
      expect(recent.single.eventCount, 2);
      expect(recent.single.recordId, 8);
      expect(recent.single.keyCode, 65);
      expect(recent.single.isIgnored, isTrue);
    });

    test('activity day local fallback includes end time payload branches',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap3-provider-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final day = DateTime(2026, 6, 14);
      await db.setBoolSetting(
        'tracker.legacy_jsonl_to_database_migrated',
        true,
      );
      await db.setBoolSetting(
        'tracker.database_to_daily_jsonl_backfilled',
        true,
      );
      await ActivityLogService(db).append(
        ActivityLogEntry(
          timestamp: day.add(const Duration(hours: 9)),
          type: ActivityLogEntryType.sample,
          durationMinutes: 60,
          processName: 'Code.exe',
          category: 'coding',
        ),
      );
      await db.into(db.activityRecords).insert(
            ActivityRecordsCompanion.insert(
              startTime: day.add(const Duration(hours: 9)),
              endTime: Value(day.add(const Duration(hours: 10))),
              durationMinutes: const Value(60),
              processName: const Value('Code.exe'),
              windowTitle: const Value('provider fallback'),
              category: const Value('coding'),
              source: const Value('test'),
            ),
          );
      final store = TrackingStoreTestDouble(
        activityDaySummaryResponseBuilder: (_) => <String, dynamic>{
          'range': <String, Object?>{},
          'insights': <String, Object?>{'totalMinutes': 1},
          'previewRecords': <Map<String, Object?>>[],
          'sessions': <Map<String, Object?>>[],
        },
      );
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          trackingServerFirstStoreProvider.overrideWith((ref) async => store),
        ],
      );
      addTearDown(container.dispose);
      final dynamic selectedDate =
          container.read(selectedDateProvider.notifier);
      selectedDate.setDate(day);

      final summary = await container.read(activityDaySummaryProvider.future);
      final preview = summary['previewRecords'] as List<Object?>;
      final first = preview.single as Map<String, Object?>;
      final payload = first['payload'] as Map<String, Object?>;

      expect(summary['source'], 'local-fallback');
      expect(payload['endTime'],
          day.add(const Duration(hours: 10)).toIso8601String());
      expect(payload['durationMinutes'], 60);
    });
  });

  group('TrackerService state branches', () {
    test('unsupported platform start and refresh remain inert', () async {
      debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
        platformLabel: 'Test unsupported',
        collectionMode: TrackerCollectionMode.unsupported,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: false,
        supportsDetailedInputHistory: false,
      );
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(trackerServiceNotifierProvider.notifier);

      notifier.start();
      await notifier.refreshNow();
      await notifier.openAndroidUsageAccessSettings();
      notifier.stop();
      await _flushAsync();

      final state = container.read(trackerServiceNotifierProvider);
      expect(state.isRunning, isFalse);
      expect(state.currentSnapshot, isNull);
      expect(state.lastError, isNull);
    });
  });
}

ActivityRecord _activityRecord({
  required int id,
  required DateTime start,
  int durationMinutes = 5,
  String? manualLabel,
  String? processName = 'Code.exe',
  String? windowTitle = 'main.dart',
  String? category = 'coding',
  int? linkedTaskId,
  int keyCount = 5,
  int mouseClicks = 1,
  int mouseMovePx = 100,
  int scrollPx = 0,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(Duration(minutes: durationMinutes)),
    durationMinutes: durationMinutes,
    keyCount: keyCount,
    mouseClicks: mouseClicks,
    mouseMovePx: mouseMovePx,
    scrollPx: scrollPx,
    manualLabel: manualLabel,
    processName: processName,
    windowTitle: windowTitle,
    category: category,
    linkedTaskId: linkedTaskId,
    isAuto: true,
    source: 'test',
  );
}

RawInputEvent _rawInputEvent({
  required int sequenceId,
  required DateTime at,
  required RawInputEventKind kind,
  int eventCount = 1,
  int? keyCode,
  String? processName,
  String? className,
  String? windowTitle,
  String? mouseButton,
  int wheelDelta = 0,
  int deltaX = 0,
  int deltaY = 0,
  int moveDistance = 0,
  String? tokenText,
}) {
  return RawInputEvent(
    sequenceId: sequenceId,
    timestampMicros: at.microsecondsSinceEpoch,
    kind: kind,
    eventCount: eventCount,
    keyCode: keyCode,
    processName: processName,
    className: className,
    windowTitle: windowTitle,
    mouseButton: mouseButton,
    wheelDelta: wheelDelta,
    deltaX: deltaX,
    deltaY: deltaY,
    moveDistance: moveDistance,
    tokenText: tokenText,
  );
}

Future<int> _insertActivityRecord(
  AppDatabase db, {
  required DateTime start,
  Object? isAutoValue = 1,
}) async {
  await db.customStatement(
    '''
    INSERT INTO activity_records (
      start_time,
      end_time,
      duration_minutes,
      key_count,
      mouse_clicks,
      mouse_move_px,
      scroll_px,
      process_name,
      window_title,
      category,
      is_auto,
      source
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    <Object?>[
      start.toIso8601String(),
      start.add(const Duration(minutes: 5)).toIso8601String(),
      5,
      12,
      3,
      320,
      240,
      'Code.exe',
      'main.dart',
      'coding',
      isAutoValue,
      'test',
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
  required String eventUid,
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
    ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    <Object?>[
      eventUid,
      sequenceId,
      at.toIso8601String(),
      _dayKey(at),
      'key_down',
      'Code.exe',
      'Editor',
      'main.dart',
      'coding',
      'Implementation',
      65,
      'A',
      'left',
      0,
      4,
      2,
      120,
      3,
      'a',
      jsonEncode(<String, Object?>{'source': 'gap3'}),
      DateTime.now().toIso8601String(),
    ],
  );
  final row =
      await db.customSelect('SELECT last_insert_rowid() AS id').getSingle();
  return row.read<int>('id');
}

Future<int> _insertRawActivityLog(
  AppDatabase db, {
  required DateTime at,
  required String entryUid,
  Object? isIgnoredValue = 0,
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
    ) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?)
    ''',
    <Object?>[
      entryUid,
      at.toIso8601String(),
      _dayKey(at),
      'sample',
      'Code.exe',
      'main.dart',
      'coding',
      'Implementation',
      isIgnoredValue,
      jsonEncode(<String, Object?>{'entryUid': entryUid}),
      DateTime.now().toIso8601String(),
    ],
  );
  final row =
      await db.customSelect('SELECT last_insert_rowid() AS id').getSingle();
  return row.read<int>('id');
}

String _dayKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

AndroidUsageEvent _usageEvent(
  DateTime timestamp,
  String packageName,
  String eventType, {
  String? className,
  String? appLabel,
}) {
  return AndroidUsageEvent.fromMap(<String, Object?>{
    'timestampMillis': timestamp.millisecondsSinceEpoch,
    'packageName': packageName,
    'eventType': eventType,
    if (className != null) 'className': className,
    if (appLabel != null) 'appLabel': appLabel,
  });
}

class _UsageQueryCall {
  const _UsageQueryCall({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _FakeAndroidUsageStatsService extends AndroidUsageStatsService {
  _FakeAndroidUsageStatsService({
    this.events = const <AndroidUsageEvent>[],
  });

  final List<AndroidUsageEvent> events;
  final queryCalls = <_UsageQueryCall>[];

  @override
  Future<bool> hasUsageAccessPermission() async => true;

  @override
  Future<List<AndroidUsageEvent>> queryUsageEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    queryCalls.add(_UsageQueryCall(start: start, end: end));
    return events;
  }
}

TrackingUploadService _uploadService(
  AppDatabase db,
  TrackingIngestApi api,
) {
  return TrackingUploadService(
    database: db,
    api: api,
    operationLogs: DataOperationLogRepository(db),
  );
}

typedef _CreateResponse = Map<String, dynamic> Function(String dataKind);
typedef _CompleteResponse = Map<String, dynamic> Function(String dataKind);

class _ConfigurableTrackingIngestApi implements TrackingIngestApi {
  _ConfigurableTrackingIngestApi({
    _CreateResponse? createResponse,
    _CompleteResponse? completeResponse,
  })  : _createResponse = createResponse,
        _completeResponse = completeResponse;

  final _CreateResponse? _createResponse;
  final _CompleteResponse? _completeResponse;
  final createdBatchIds = <String>[];
  final chunkCalls = <_ChunkCall>[];
  final _batchKindsById = <String, String>{};

  @override
  Future<Map<String, dynamic>> createBatch({
    required String batchUid,
    required String dataKind,
    DateTime? startAt,
    DateTime? endAt,
    String compression = 'none',
    List<Map<String, dynamic>> records = const <Map<String, dynamic>>[],
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    final response = _createResponse?.call(dataKind) ??
        <String, dynamic>{'batchId': 'batch-$dataKind'};
    final batch = response['batch'];
    final batchMap = batch is Map ? Map<String, Object?>.from(batch) : null;
    final batchId = response['batchId']?.toString() ??
        response['id']?.toString() ??
        batchMap?['batchId']?.toString() ??
        batchMap?['id']?.toString();
    if (batchId != null) {
      createdBatchIds.add(batchId);
      _batchKindsById[batchId] = dataKind;
    }
    return response;
  }

  @override
  Future<Map<String, dynamic>> uploadChunk({
    required String batchId,
    required int chunkIndex,
    List<Map<String, dynamic>> records = const <Map<String, dynamic>>[],
    Uint8List? compressedJsonBytes,
    String? checksum,
  }) async {
    chunkCalls.add(
      _ChunkCall(
        batchId: batchId,
        chunkIndex: chunkIndex,
        records: records,
      ),
    );
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> completeBatch({
    required String batchId,
    List<Map<String, dynamic>> records = const <Map<String, dynamic>>[],
  }) async {
    final dataKind = _batchKindsById[batchId] ?? 'unknown';
    return _completeResponse?.call(dataKind) ??
        <String, dynamic>{
          'ok': true,
          'accepted': chunkCalls
              .where((call) => call.batchId == batchId)
              .fold<int>(0, (sum, call) => sum + call.records.length),
          'rejected': 0,
        };
  }

  @override
  Future<Map<String, dynamic>> summary({DateTime? start, DateTime? end}) async {
    return <String, dynamic>{};
  }
}

class _ChunkCall {
  const _ChunkCall({
    required this.batchId,
    required this.chunkIndex,
    required this.records,
  });

  final String batchId;
  final int chunkIndex;
  final List<Map<String, dynamic>> records;
}

ActivityFusionRepository _fusionRepository(
  AppDatabase db, {
  bool withSync = false,
}) {
  final sync = withSync
      ? SyncWriteRecorder(
          mutationStore: OfflineMutationStore(db),
          stateStore: SyncObjectStateStore(db),
        )
      : null;
  return ActivityFusionRepository(
    db,
    DataOperationLogRepository(db),
    sync,
  );
}

ActivitySegmentDraft _segmentDraft(
  DateTime start, {
  String status = 'candidate',
  String label = 'Focused work',
}) {
  return ActivitySegmentDraft(
    startAt: start,
    endAt: start.add(const Duration(minutes: 20)),
    sourceRecordIds: const <int>[1, 2],
    evidence: const <String, Object?>{'source': 'gap3'},
    primaryProcessName: 'Code.exe',
    primaryWindowTitle: 'tracker gap3',
    category: 'coding',
    label: label,
    confidence: 0.7,
    status: status,
  );
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 1));
}
