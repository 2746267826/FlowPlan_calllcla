import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/features/tracker/services/activity_log_service.dart';
import 'package:flowplanv2/features/tracker/services/android_usage_import_service.dart';
import 'package:flowplanv2/features/tracker/services/android_usage_stats_service.dart';
import 'package:flowplanv2/features/tracker/tracker_defaults.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.flowplanv2.app/android_usage_stats');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('AndroidUsageStatsService is a channel no-op on non-Android hosts',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'getUsageAccessPermissionStatus' => true,
        'queryUsageEvents' => <Object?>[
            <String, Object?>{
              'timestampMillis': DateTime(2026, 6, 10).millisecondsSinceEpoch,
              'packageName': 'com.example.app',
              'eventType': 'activity_resumed',
            },
          ],
        _ => null,
      };
    });

    final service = AndroidUsageStatsService(
      isAndroid: () => false,
      channel: channel,
    );

    expect(await service.hasUsageAccessPermission(), isFalse);
    await service.openUsageAccessSettings();
    expect(
      await service.queryUsageEvents(
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 6, 11),
      ),
      isEmpty,
    );
    expect(calls, isEmpty);
  });

  test('AndroidUsageStatsService calls channel and sorts valid Android events',
      () async {
    final calls = <MethodCall>[];
    final later = DateTime(2026, 6, 10, 9, 20);
    final earlier = DateTime(2026, 6, 10, 9, 5);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'getUsageAccessPermissionStatus' => true,
        'openUsageAccessSettings' => null,
        'queryUsageEvents' => <Object?>[
            <String, Object?>{
              'timestampMillis': later.millisecondsSinceEpoch,
              'packageName': 'com.example.later',
              'eventType': 'activity_paused',
            },
            'malformed',
            <String, Object?>{
              'timestampMillis': earlier.millisecondsSinceEpoch,
              'packageName': 'com.example.earlier',
              'eventType': 'activity_resumed',
            },
            <String, Object?>{
              'timestampMillis': earlier.millisecondsSinceEpoch,
              'packageName': 'com.example.bad',
              'eventType': 'unsupported',
            },
          ],
        _ => null,
      };
    });
    final service = AndroidUsageStatsService(
      isAndroid: () => true,
      channel: channel,
    );

    expect(await service.hasUsageAccessPermission(), isTrue);
    await service.openUsageAccessSettings();
    final events = await service.queryUsageEvents(
      start: DateTime(2026, 6, 10, 9),
      end: DateTime(2026, 6, 10, 10),
    );

    expect(calls.map((call) => call.method), <String>[
      'getUsageAccessPermissionStatus',
      'openUsageAccessSettings',
      'queryUsageEvents',
    ]);
    expect(calls.last.arguments, <String, Object?>{
      'sinceMillis': DateTime(2026, 6, 10, 9).millisecondsSinceEpoch,
      'untilMillis': DateTime(2026, 6, 10, 10).millisecondsSinceEpoch,
    });
    expect(events.map((event) => event.packageName), <String>[
      'com.example.earlier',
      'com.example.later',
    ]);
  });

  test('AndroidUsageEvent parsing sorts valid events and skips malformed ones',
      () async {
    final paused = AndroidUsageEvent.fromMap(<String, Object?>{
      'timestampMillis': DateTime(2026, 6, 10, 9, 5).millisecondsSinceEpoch,
      'packageName': ' com.example.editor ',
      'eventType': 'activity_paused',
      'className': ' MainActivity ',
      'appLabel': ' Editor ',
    });

    expect(paused.packageName, 'com.example.editor');
    expect(paused.className, 'MainActivity');
    expect(paused.appLabel, 'Editor');
    expect(paused.eventType.closesForegroundSession, isTrue);
    expect(
      () => AndroidUsageEvent.fromMap(<String, Object?>{
        'eventType': 'unknown',
      }),
      throwsArgumentError,
    );
  });

  test('AndroidUsageImportService reports unsupported without touching storage',
      () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = AndroidUsageImportService(
      database: db,
      activityRecordRepository: ActivityRecordRepository(db),
      activityLogService: ActivityLogService(db),
      isAndroid: () => false,
    );

    final result = await service.importLatest();

    expect(result.supported, isFalse);
    expect(result.permissionGranted, isFalse);
    expect(result.importedRecordCount, 0);
    expect(result.importedLogCount, 0);
    expect(result.importedUntil, isNull);
    final records =
        await db.customSelect('SELECT * FROM activity_records').get();
    final logs = await db.customSelect('SELECT * FROM raw_activity_logs').get();
    final cursor = await db.getSetting(
      'tracker.android_usage_stats_cursor_millis',
    );
    expect(records, isEmpty);
    expect(logs, isEmpty);
    expect(cursor, isNull);
  });

  test('AndroidUsageImportService stops when permission is denied', () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final usageStats = _FakeAndroidUsageStatsService(permissionGranted: false);
    final service = AndroidUsageImportService(
      database: db,
      activityRecordRepository: ActivityRecordRepository(db),
      activityLogService: ActivityLogService(db),
      usageStatsService: usageStats,
      isAndroid: () => true,
    );

    final result = await service.importLatest();

    expect(result.supported, isTrue);
    expect(result.permissionGranted, isFalse);
    expect(result.importedRecordCount, 0);
    expect(result.importedLogCount, 0);
    expect(usageStats.queryCalls, isEmpty);
    expect(
      await db.customSelect('SELECT * FROM activity_records').get(),
      isEmpty,
    );
    expect(
      await db.customSelect('SELECT * FROM raw_activity_logs').get(),
      isEmpty,
    );
  });

  test('AndroidUsageImportService stores cursor when no usage events exist',
      () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final futureCursor = DateTime.now().add(const Duration(days: 1));
    await db.setSetting(
      'tracker.android_usage_stats_cursor_millis',
      futureCursor.millisecondsSinceEpoch.toString(),
    );
    final usageStats = _FakeAndroidUsageStatsService(events: const []);
    final service = AndroidUsageImportService(
      database: db,
      activityRecordRepository: ActivityRecordRepository(db),
      activityLogService: ActivityLogService(db),
      usageStatsService: usageStats,
      isAndroid: () => true,
    );

    final result = await service.importLatest();

    expect(result.supported, isTrue);
    expect(result.permissionGranted, isTrue);
    expect(result.importedRecordCount, 0);
    expect(result.importedLogCount, 0);
    expect(result.importedUntil, isNotNull);
    expect(usageStats.queryCalls, hasLength(1));
    final start = usageStats.queryCalls.single.start;
    expect(start, DateTime(start.year, start.month, start.day));
    final cursor = await db.getSetting(
      'tracker.android_usage_stats_cursor_millis',
    );
    expect(cursor, result.importedUntil!.millisecondsSinceEpoch.toString());
  });

  test('AndroidUsageImportService imports, merges, and logs Android sessions',
      () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.setSetting('device.identity.id', 'android-device');
    final base = DateTime.now().subtract(const Duration(hours: 2));
    await db.setSetting(
      'tracker.android_usage_stats_cursor_millis',
      base
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch
          .toString(),
    );
    final usageStats = _FakeAndroidUsageStatsService(
      events: [
        _usageEvent(
          base.add(const Duration(minutes: 5)),
          'com.example.editor',
          'activity_paused',
          className: 'MainActivity',
          appLabel: 'Editor',
        ),
        _usageEvent(
          base,
          'com.example.editor',
          'activity_resumed',
          className: 'MainActivity',
          appLabel: ' Editor ',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 5, seconds: 5)),
          'com.example.editor',
          'activity_resumed',
          className: 'MainActivity',
          appLabel: 'Editor',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 10)),
          'com.example.editor',
          'activity_paused',
          className: 'MainActivity',
          appLabel: 'Editor',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 20)),
          'com.android.systemui',
          'activity_resumed',
          appLabel: 'System UI',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 25)),
          'com.android.systemui',
          'activity_paused',
          appLabel: 'System UI',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 30)),
          'com.example.flash',
          'activity_resumed',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 30, seconds: 1)),
          'com.example.flash',
          'activity_paused',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 40)),
          'com.example.browser',
          'move_to_foreground',
          appLabel: 'Browser',
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

    expect(result.supported, isTrue);
    expect(result.permissionGranted, isTrue);
    expect(result.importedRecordCount, 2);
    expect(result.importedLogCount, 4);
    expect(result.latestSnapshot?.processName, 'Browser');
    expect(result.latestSnapshot?.windowTitle, 'Browser');
    expect(result.latestClassification, isNotNull);
    expect(
      result.latestSessionStart,
      _millisDate(base.add(const Duration(minutes: 40))),
    );

    final records = await db
        .customSelect('SELECT * FROM activity_records ORDER BY start_time ASC')
        .get();
    expect(records, hasLength(2));
    expect(records.first.read<String>('process_name'), 'Editor');
    expect(records.first.read<String>('package_name'), 'com.example.editor');
    expect(records.first.read<int>('duration_minutes'), 10);
    expect(records.first.read<String>('device_id'), 'android-device');
    expect(records.first.read<String>('source'), 'android_usage_stats');
    expect(records.last.read<String>('process_name'), 'Browser');
    expect(records.last.read<String>('package_name'), 'com.example.browser');

    final logs = await ActivityLogService(db).readEntriesBetween(
      base.subtract(const Duration(minutes: 1)),
      DateTime.now().add(const Duration(minutes: 1)),
      limit: 20,
    );
    expect(logs, hasLength(4));
    expect(logs.map((entry) => entry.note), contains('android_import_open'));
    expect(logs.map((entry) => entry.note), contains('android_import_close'));
    expect(logs.map((entry) => entry.deviceId).toSet(), {'android-device'});

    final cursor = await db.getSetting(
      'tracker.android_usage_stats_cursor_millis',
    );
    expect(
      cursor,
      (_millisDate(base.add(const Duration(minutes: 40)))
                  .millisecondsSinceEpoch +
              1)
          .toString(),
    );
  });

  test('AndroidUsageImportService preserves label on repeated foreground open',
      () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final base =
        _secondsDate(DateTime.now().subtract(const Duration(hours: 2)));
    await db.setSetting(
      'tracker.android_usage_stats_cursor_millis',
      base
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch
          .toString(),
    );
    final usageStats = _FakeAndroidUsageStatsService(
      events: [
        _usageEvent(
          base,
          'com.example.reader',
          'activity_resumed',
          className: 'ReaderActivity',
          appLabel: 'Reader',
        ),
        _usageEvent(
          base.add(const Duration(seconds: 2)),
          'com.example.reader',
          'move_to_foreground',
          className: 'ReaderActivity',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 4)),
          'com.example.reader',
          'activity_paused',
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

    expect(result.importedRecordCount, 1);
    expect(result.importedLogCount, 2);
    expect(result.latestSnapshot?.processName, 'Reader');
    expect(result.latestSnapshot?.className, 'ReaderActivity');
    expect(result.latestSnapshot?.windowTitle, 'Reader');
    expect(result.latestClassification?.label, 'Reader');

    final records = await db
        .customSelect('SELECT * FROM activity_records ORDER BY start_time ASC')
        .get();
    expect(records, hasLength(1));
    expect(records.single.read<DateTime>('start_time'), _millisDate(base));
    expect(records.single.read<String>('process_name'), 'Reader');
    expect(records.single.read<String>('window_title'), 'Reader');
    expect(records.single.read<String>('package_name'), 'com.example.reader');

    final logs = await ActivityLogService(db).readEntriesBetween(
      base.subtract(const Duration(minutes: 1)),
      base.add(const Duration(minutes: 5)),
      limit: 10,
    );
    expect(logs, hasLength(2));
    expect(logs.first.timestamp, _millisDate(base));
    expect(logs.map((entry) => entry.appLabel).toSet(), {'Reader'});
    expect(logs.map((entry) => entry.className).toSet(), {'ReaderActivity'});
    expect(logs.map((entry) => entry.windowTitle).toSet(), {'Reader'});
  });

  test(
      'AndroidUsageImportService merges adjacent sessions and inherits metadata',
      () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final base =
        _secondsDate(DateTime.now().subtract(const Duration(hours: 2)));
    await db.setSetting(
      'tracker.android_usage_stats_cursor_millis',
      base
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch
          .toString(),
    );
    final expectedEnd = _millisDate(base.add(const Duration(minutes: 6)));
    final usageStats = _FakeAndroidUsageStatsService(
      events: [
        _usageEvent(
          base,
          'com.example.notes',
          'activity_resumed',
          className: 'NotesActivity',
          appLabel: 'Notes',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 2)),
          'com.example.notes',
          'activity_paused',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 2, seconds: 12)),
          'com.example.notes',
          'activity_resumed',
        ),
        _usageEvent(
          expectedEnd,
          'com.example.notes',
          'activity_paused',
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

    expect(result.importedRecordCount, 1);
    expect(result.importedLogCount, 2);
    expect(result.latestSnapshot?.processName, 'Notes');
    expect(result.latestSnapshot?.className, 'NotesActivity');
    expect(result.latestSnapshot?.windowTitle, 'Notes');
    expect(result.latestClassification?.label, 'Notes');

    final records = await db
        .customSelect('SELECT * FROM activity_records ORDER BY start_time ASC')
        .get();
    expect(records, hasLength(1));
    expect(records.single.read<String>('process_name'), 'Notes');
    expect(records.single.read<String>('window_title'), 'Notes');
    expect(records.single.read<DateTime>('end_time'), expectedEnd);

    final logs = await ActivityLogService(db).readEntriesBetween(
      base.subtract(const Duration(minutes: 1)),
      base.add(const Duration(minutes: 7)),
      limit: 10,
    );
    expect(logs, hasLength(2));
    expect(logs.map((entry) => entry.className).toSet(), {'NotesActivity'});
    expect(logs.map((entry) => entry.appLabel).toSet(), {'Notes'});
    expect(logs.map((entry) => entry.windowTitle).toSet(), {'Notes'});
    expect(logs.last.timestamp, expectedEnd);
  });

  test(
      'AndroidUsageImportService keeps open metadata across repeated foreground and adjacent merge',
      () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final base =
        _secondsDate(DateTime.now().subtract(const Duration(hours: 2)));
    await db.setSetting(
      'tracker.android_usage_stats_cursor_millis',
      base
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch
          .toString(),
    );
    final usageStats = _FakeAndroidUsageStatsService(
      events: [
        _usageEvent(
          base,
          'com.example.editor',
          'activity_resumed',
          className: 'MainActivity',
          appLabel: 'Editor',
        ),
        _usageEvent(
          base.add(const Duration(seconds: 1)),
          'com.example.editor',
          'move_to_foreground',
          className: 'MainActivity',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 4)),
          'com.example.editor',
          'activity_paused',
          className: 'MainActivity',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 4, seconds: 5)),
          'com.example.editor',
          'activity_resumed',
        ),
        _usageEvent(
          base.add(const Duration(minutes: 8)),
          'com.example.editor',
          'activity_paused',
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
        .customSelect('SELECT * FROM activity_records ORDER BY start_time ASC')
        .get();
    final logs = await ActivityLogService(db).readEntriesBetween(
      base.subtract(const Duration(minutes: 1)),
      base.add(const Duration(minutes: 9)),
      limit: 10,
    );

    expect(result.importedRecordCount, 1);
    expect(result.latestSnapshot?.processName, 'Editor');
    expect(result.latestSnapshot?.className, 'MainActivity');
    expect(records, hasLength(1));
    expect(records.single.read<String>('process_name'), 'Editor');
    expect(records.single.read<String?>('class_name'), 'MainActivity');
    expect(
      records.single.read<DateTime>('end_time'),
      _millisDate(base.add(const Duration(minutes: 8))),
    );
    expect(logs.map((entry) => entry.appLabel).toSet(), {'Editor'});
    expect(logs.map((entry) => entry.className).toSet(), {'MainActivity'});
  });

  test('default Android ignored package rules trim and normalize package names',
      () {
    expect(isAndroidTrackerIgnoredPackage(null), isTrue);
    expect(isAndroidTrackerIgnoredPackage('   '), isTrue);
    expect(isAndroidTrackerIgnoredPackage(' COM.ANDROID.SYSTEMUI '), isTrue);
    expect(isAndroidTrackerIgnoredPackage('com.example.editor'), isFalse);
  });

  test('Android usage session copy helpers preserve existing metadata', () {
    final start = DateTime(2026, 6, 12, 9);
    final end = start.add(const Duration(minutes: 5));

    final openCopy = AndroidUsageImportService.debugCopyOpenSessionForTesting(
      start: start,
      packageName: 'com.example.editor',
      className: 'MainActivity',
      appLabel: 'Editor',
    );
    final closedCopy =
        AndroidUsageImportService.debugCopyClosedSessionForTesting(
      start: start,
      end: end,
      packageName: 'com.example.editor',
      className: 'MainActivity',
      appLabel: 'Editor',
    );

    expect(openCopy['className'], 'MainActivity');
    expect(openCopy['appLabel'], 'Editor');
    expect(closedCopy['end'], end);
    expect(closedCopy['className'], 'MainActivity');
    expect(closedCopy['appLabel'], 'Editor');
  });
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

DateTime _millisDate(DateTime value) {
  return DateTime.fromMillisecondsSinceEpoch(value.millisecondsSinceEpoch);
}

DateTime _secondsDate(DateTime value) {
  return DateTime.fromMillisecondsSinceEpoch(
    value.millisecondsSinceEpoch ~/ 1000 * 1000,
  );
}

class _UsageQueryCall {
  const _UsageQueryCall({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _FakeAndroidUsageStatsService extends AndroidUsageStatsService {
  _FakeAndroidUsageStatsService({
    this.permissionGranted = true,
    this.events = const [],
  });

  final bool permissionGranted;
  final List<AndroidUsageEvent> events;
  final queryCalls = <_UsageQueryCall>[];

  @override
  Future<bool> hasUsageAccessPermission() async => permissionGranted;

  @override
  Future<List<AndroidUsageEvent>> queryUsageEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    queryCalls.add(_UsageQueryCall(start: start, end: end));
    return events;
  }
}
