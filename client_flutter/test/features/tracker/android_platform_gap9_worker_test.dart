import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flowplanv2/features/tracker/services/activity_log_service.dart';
import 'package:flowplanv2/features/tracker/services/android_usage_import_service.dart';
import 'package:flowplanv2/features/tracker/services/android_usage_stats_service.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flowplanv2/features/tracker/services/window_sensor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const androidChannel = MethodChannel(
    'com.flowplanv2.app/android_usage_stats',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, null);
  });

  group('small tracker model gap9 coverage', () {
    test('InputEventQuery copyWith keeps existing fields when no override wins',
        () {
      final start = DateTime(2026, 6, 12, 9);
      final end = DateTime(2026, 6, 12, 10);
      final query = InputEventQuery(
        start: start,
        end: end,
        processName: 'Code.exe',
      );

      final copied = query.copyWith();

      expect(copied.start, start);
      expect(copied.end, end);
      expect(copied.processName, 'Code.exe');
      expect(copied.hasTimeRange, isTrue);
    });

    test('WorkSession values expose raw count override and category fallback',
        () {
      final start = DateTime(2026, 6, 12, 9);
      final record = _record(
        id: 1,
        start: start,
        processName: '  ',
        category: 'research',
      );

      expect(WorkSessionGrouper.strictSignature(record), 'category:research');

      final session = WorkSession(
        startTime: start,
        endTime: start.add(const Duration(minutes: 5)),
        label: 'Research',
        processName: null,
        category: 'research',
        records: <ActivityRecord>[record],
        durationMinutes: 5,
        keyCount: 1,
        mouseClicks: 0,
        mouseMovePx: 0,
        scrollPx: 0,
        processNames: const <String>['Code.exe', 'Browser.exe'],
        categories: const <String>['research', 'reading'],
        interruptionCount: 0,
        rawRecordCountOverride: 7,
      );

      expect(session.rawRecordCount, 7);
      expect(session.spansMultipleProcesses, isTrue);
      expect(session.spansMultipleCategories, isTrue);
    });

    test('WindowSnapshot string and context ignore title-only changes', () {
      final at = DateTime(2026, 6, 12, 9);
      final first = WindowSnapshot(
        processName: 'Code.exe',
        className: 'Chrome_WidgetWin_1',
        windowTitle: 'main.dart',
        isFullscreen: false,
        timestamp: at,
      );
      final sameContext = WindowSnapshot(
        processName: 'Code.exe',
        className: 'Chrome_WidgetWin_1',
        windowTitle: 'pubspec.yaml',
        isFullscreen: true,
        timestamp: at.add(const Duration(seconds: 1)),
      );

      expect(first.toString(), contains('process=Code.exe'));
      expect(first.toString(), contains('fullscreen=false'));
      expect(first.isSameContext(sameContext), isTrue);
    });
  });

  group('platform source and Android stats gap9 coverage', () {
    test('current resolves Android and fallback modes from injected probes',
        () {
      final android = TrackerPlatformSource.current(
        isWindows: () => false,
        isAndroid: () => true,
      );
      final fallback = TrackerPlatformSource.current(
        isWindows: () => false,
        isAndroid: () => false,
      );
      final windows = TrackerPlatformSource.current(
        isWindows: () => true,
        isAndroid: () => true,
      );

      expect(android.platformLabel, 'Android');
      expect(
        android.collectionMode,
        TrackerCollectionMode.manualUsageStatsImport,
      );
      expect(android.supportsUsageAccessPermission, isTrue);
      expect(android.supportsInputAnalytics, isFalse);
      expect(fallback.isSupported, isFalse);
      expect(windows.isWindows, isTrue);
    });

    test('platform testing constructors execute at runtime', () {
      final windows = TrackerPlatformSource.windowsForTesting();
      final custom = TrackerPlatformSource.testing(
        platformLabel: 'Runtime custom',
        collectionMode: TrackerCollectionMode.unsupported,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: false,
        supportsDetailedInputHistory: false,
      );

      expect(windows.platformLabel, 'Windows');
      expect(windows.supportsSequenceRecording, isTrue);
      expect(custom.platformLabel, 'Runtime custom');
      expect(custom.isSupported, isFalse);
    });

    test('TrackerPlatformSource constructors preserve explicit capabilities',
        () {
      const windows = TrackerPlatformSource.windowsForTesting();
      const android = TrackerPlatformSource.testing(
        platformLabel: 'Android',
        collectionMode: TrackerCollectionMode.manualUsageStatsImport,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: true,
        supportsDetailedInputHistory: false,
      );

      expect(windows.platformLabel, 'Windows');
      expect(windows.collectionMode,
          TrackerCollectionMode.continuousWindowSampling);
      expect(windows.supportsInputAnalytics, isTrue);
      expect(windows.collectionDescription, isNotEmpty);
      expect(android.isAndroid, isTrue);
      expect(android.supportsUsageAccessPermission, isTrue);
      expect(android.supportsDetailedInputHistory, isFalse);
    });

    test('current uses default Android probe when only Windows is injected',
        () {
      final source = TrackerPlatformSource.current(isWindows: () => false);

      expect(source.isAndroid, false);
      expect(source.collectionMode, TrackerCollectionMode.unsupported);
    });

    test('AndroidUsageEventType marks stopped and background as closers', () {
      expect(
        AndroidUsageEventType.activityStopped.closesForegroundSession,
        isTrue,
      );
      expect(
        AndroidUsageEventType.moveToBackground.closesForegroundSession,
        isTrue,
      );
      expect(
        AndroidUsageEventType.moveToForeground.opensForegroundSession,
        isTrue,
      );
    });

    test('AndroidUsageStatsService maps null permission result to false',
        () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, (call) async {
        calls.add(call);
        return null;
      });
      final service = AndroidUsageStatsService(
        isAndroid: () => true,
        channel: androidChannel,
      );

      expect(await service.hasUsageAccessPermission(), isFalse);
      expect(calls.single.method, 'getUsageAccessPermissionStatus');
    });
  });

  group('raw input gap9 coverage', () {
    test('value objects keep defaults and parse minimal raw event maps', () {
      const clicks = MouseClicks(left: 2, right: 1);
      expect(clicks.copyWith().toMap(), <String, int>{
        'left': 2,
        'right': 1,
        'middle': 0,
        'xButton1': 0,
        'xButton2': 0,
      });

      final before = DateTime.now();
      final event = RawInputEvent.fromMap(const <String, Object?>{});
      final after = DateTime.now();

      expect(event.sequenceId, 0);
      expect(event.kind, RawInputEventKind.keyDown);
      expect(event.timestamp.isBefore(before), isFalse);
      expect(event.timestamp.isAfter(after), isFalse);

      final telemetryAt = DateTime(2026, 6, 12, 9);
      final telemetry = InputTelemetry.empty(telemetryAt);
      final copied = telemetry.copyWith();

      expect(copied.keyCount, 0);
      expect(copied.keyDistribution, isEmpty);
      expect(copied.timestamp, telemetryAt);
    });
  });

  group('AndroidUsageImportService gap9 coverage', () {
    test('updates repeated foreground metadata and merges adjacent sessions',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap9-android-import-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime.now().subtract(const Duration(minutes: 40));
      await db.setSetting(
        'tracker.android_usage_stats_cursor_millis',
        base
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch
            .toString(),
      );
      final usageStats = _FakeAndroidUsageStatsService(
        events: <AndroidUsageEvent>[
          _usageEvent(
            base,
            ' com.example.editor ',
            AndroidUsageEventType.activityResumed,
            className: 'MainActivity',
            appLabel: 'Editor',
          ),
          _usageEvent(
            base.add(const Duration(minutes: 1)),
            'com.example.editor',
            AndroidUsageEventType.activityResumed,
            className: 'MainActivity',
          ),
          _usageEvent(
            base.add(const Duration(minutes: 5)),
            'com.example.editor',
            AndroidUsageEventType.activityPaused,
            className: 'MainActivity',
          ),
          _usageEvent(
            base.add(const Duration(minutes: 5, seconds: 6)),
            'com.example.editor',
            AndroidUsageEventType.moveToForeground,
            className: 'MainActivity',
            appLabel: 'Editor',
          ),
          _usageEvent(
            base.add(const Duration(minutes: 8)),
            'com.example.editor',
            AndroidUsageEventType.moveToBackground,
            className: 'MainActivity',
            appLabel: 'Editor',
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
      final records = await db
          .customSelect(
              'SELECT * FROM activity_records ORDER BY start_time ASC')
          .get();

      expect(result.importedRecordCount, 1);
      expect(result.importedLogCount, 2);
      expect(result.latestSnapshot?.processName, 'Editor');
      expect(records, hasLength(1));
      expect(records.single.read<String>('process_name'), 'Editor');
      expect(records.single.read<String>('package_name'), 'com.example.editor');
      expect(records.single.read<int>('duration_minutes'), 8);
    });
  });
}

ActivityRecord _record({
  required int id,
  required DateTime start,
  String? processName = 'Code.exe',
  String? category = 'coding',
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(const Duration(minutes: 5)),
    durationMinutes: 5,
    keyCount: 1,
    mouseClicks: 0,
    mouseMovePx: 0,
    scrollPx: 0,
    processName: processName,
    category: category,
    isAuto: true,
    source: 'test',
  );
}

AndroidUsageEvent _usageEvent(
  DateTime timestamp,
  String packageName,
  AndroidUsageEventType eventType, {
  String? className,
  String? appLabel,
}) {
  return AndroidUsageEvent(
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      timestamp.millisecondsSinceEpoch,
    ),
    packageName: packageName.trim(),
    eventType: eventType,
    className: className?.trim(),
    appLabel: appLabel?.trim(),
  );
}

class _FakeAndroidUsageStatsService extends AndroidUsageStatsService {
  _FakeAndroidUsageStatsService({required this.events});

  final List<AndroidUsageEvent> events;

  @override
  Future<bool> hasUsageAccessPermission() async => true;

  @override
  Future<List<AndroidUsageEvent>> queryUsageEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    return events;
  }
}
