import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ReminderPayloadCodec additional coverage', () {
    test('normalizes and round-trips nested DateTime Iterable and Map values',
        () {
      final localTime = DateTime(2026, 6, 10, 9, 30);
      final payload = <String, Object?>{
        'date': localTime,
        'items': <Object?>[
          DateTime.utc(2026, 6, 10, 1, 2, 3),
          <Object?, Object?>{
            7: <Object?>[
              DateTime.utc(2026, 6, 10, 4, 5),
              null,
            ],
          },
        ],
        'nested': <Object?, Object?>{
          42: DateTime.utc(2026, 6, 11),
          'set': <String>{'alpha', 'beta'},
        },
      };

      final normalized = ReminderPayloadCodec.normalize(payload);
      final decoded = ReminderPayloadCodec.decode(
        ReminderPayloadCodec.encode(payload),
      );

      expect(normalized, decoded);
      expect(decoded['date'], localTime.toUtc().toIso8601String());
      expect(
        decoded['items'],
        <Object?>[
          DateTime.utc(2026, 6, 10, 1, 2, 3).toIso8601String(),
          <String, Object?>{
            '7': <Object?>[
              DateTime.utc(2026, 6, 10, 4, 5).toIso8601String(),
              null,
            ],
          },
        ],
      );
      expect(
        decoded['nested'],
        <String, Object?>{
          '42': DateTime.utc(2026, 6, 11).toIso8601String(),
          'set': <Object?>['alpha', 'beta'],
        },
      );
    });

    test('decode returns empty maps for empty invalid and non-map payloads',
        () {
      expect(ReminderPayloadCodec.decode(null), isEmpty);
      expect(ReminderPayloadCodec.decode(''), isEmpty);
      expect(ReminderPayloadCodec.decode('   '), isEmpty);
      expect(ReminderPayloadCodec.decode('{nope'), isEmpty);
      expect(ReminderPayloadCodec.decode('[1, 2, 3]'), isEmpty);
      expect(ReminderPayloadCodec.decode('"text"'), isEmpty);
    });
  });

  group('ReminderRequest additional coverage', () {
    test('stores an immutable normalized payload and exposes encodedPayload',
        () {
      final source = <String, Object?>{
        'triggerAt': DateTime.utc(2026, 6, 10, 8, 45),
        'nested': <Object?, Object?>{
          1: <Object?>[DateTime.utc(2026, 6, 10, 9)],
        },
      };

      final request = ReminderRequest(
        id: 7,
        triggerAt: DateTime.utc(2026, 6, 10, 9),
        title: 'Title',
        body: 'Body',
        payload: source,
      );
      source['triggerAt'] = 'mutated';

      expect(
        request.payload,
        <String, Object?>{
          'triggerAt': DateTime.utc(2026, 6, 10, 8, 45).toIso8601String(),
          'nested': <String, Object?>{
            '1': <Object?>[DateTime.utc(2026, 6, 10, 9).toIso8601String()],
          },
        },
      );
      expect(
        () => request.payload['new'] = 'blocked',
        throwsUnsupportedError,
      );
      expect(
        ReminderPayloadCodec.decode(request.encodedPayload),
        request.payload,
      );
    });
  });

  group('ReminderService additional system scheduling coverage', () {
    late AppDatabase db;
    late _FakeReminderGateway gateway;
    late _FakeReminderEnvironment environment;

    setUp(() {
      db = createTestDatabase();
      addTearDown(db.close);
      gateway = _FakeReminderGateway();
      environment = _FakeReminderEnvironment(
        now: DateTime.utc(2026, 6, 10, 8),
        isAndroid: true,
      );
    });

    ReminderService service({int eventReminderMinutes = 0}) {
      return ReminderService(
        database: db,
        defaultEventReminderMinutes: () => eventReminderMinutes,
        gateway: gateway,
        environment: environment,
      );
    }

    test('needsAndroidExactAlarmPermission reflects support and permission',
        () {
      const androidBlocked = ReminderSystemStatus(
        platformLabel: 'Android',
        runtimeScannerEnabled: false,
        supportsSystemSchedule: true,
        canScheduleExactAlarms: false,
        pendingSystemReminderCount: 0,
        lastRebuiltAt: null,
      );
      const androidReady = ReminderSystemStatus(
        platformLabel: 'Android',
        runtimeScannerEnabled: false,
        supportsSystemSchedule: true,
        canScheduleExactAlarms: true,
        pendingSystemReminderCount: 0,
        lastRebuiltAt: null,
      );
      const unsupported = ReminderSystemStatus(
        platformLabel: 'Other',
        runtimeScannerEnabled: false,
        supportsSystemSchedule: false,
        canScheduleExactAlarms: false,
        pendingSystemReminderCount: 0,
        lastRebuiltAt: null,
      );

      expect(androidBlocked.needsAndroidExactAlarmPermission, isTrue);
      expect(androidReady.needsAndroidExactAlarmPermission, isFalse);
      expect(unsupported.needsAndroidExactAlarmPermission, isFalse);
    });

    test('non-Android rebuild records zero and last rebuilt timestamp',
        () async {
      environment
        ..isAndroid = false
        ..isWindows = false;
      gateway.pendingSystemReminderCountValue = 41;
      final reminders = service();

      final result = await reminders.rebuildSystemSchedule();
      final status = await reminders.getSystemStatus();

      expect(result.scheduledCount, 0);
      expect(result.canScheduleExactAlarms, isFalse);
      expect(gateway.cancelAllCalls, 0);
      expect(gateway.scheduleAttempts, 0);
      expect(
        await db.getIntSetting(
          'reminder.system_schedule.last_count',
          defaultValue: -1,
        ),
        0,
      );
      expect(status.supportsSystemSchedule, isFalse);
      expect(status.pendingSystemReminderCount, 0);
      expect(status.lastRebuiltAt, environment.now());
    });

    test(
        'Android rebuild without exact alarm permission cancels and records zero',
        () async {
      gateway
        ..canScheduleExactAlarmsValue = false
        ..pendingSystemReminderCountValue = 9;
      final listId = await _insertTaskList(db);
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'permission-blocked-start',
        summary: 'Blocked start',
        dtstart: environment.now().add(const Duration(hours: 1)),
        reminderMinutesBefore: 10,
      );
      final reminders = service();

      final result = await reminders.rebuildSystemSchedule();
      final status = await reminders.getSystemStatus();

      expect(result.scheduledCount, 0);
      expect(result.canScheduleExactAlarms, isFalse);
      expect(gateway.cancelAllCalls, 1);
      expect(gateway.scheduleAttempts, 0);
      expect(
        await db.getIntSetting(
          'reminder.system_schedule.last_count',
          defaultValue: -1,
        ),
        0,
      );
      expect(status.supportsSystemSchedule, isTrue);
      expect(status.needsAndroidExactAlarmPermission, isTrue);
      expect(status.pendingSystemReminderCount, 9);
      expect(status.lastRebuiltAt, environment.now());
    });

    test('Android rebuild keeps going after schedule exceptions', () async {
      final listId = await _insertTaskList(db);
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'throws-first',
        summary: 'Throws first',
        dtstart: environment.now().add(const Duration(hours: 1)),
        reminderMinutesBefore: 10,
      );
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'succeeds-second',
        summary: 'Succeeds second',
        dtstart: environment.now().add(const Duration(hours: 2)),
        reminderMinutesBefore: 10,
      );
      gateway.throwOnAttemptNumbers.add(1);
      final reminders = service();

      final result = await reminders.rebuildSystemSchedule();

      expect(result.canScheduleExactAlarms, isTrue);
      expect(result.scheduledCount, 1);
      expect(gateway.cancelAllCalls, 1);
      expect(gateway.scheduleAttempts, 2);
      expect(gateway.scheduledRequests, hasLength(1));
      expect(
          gateway.scheduledRequests.single.body, contains('Succeeds second'));
      expect(
        await db.getIntSetting(
          'reminder.system_schedule.last_count',
          defaultValue: -1,
        ),
        1,
      );
      expect(
        DateTime.parse(
          (await db.getSetting('reminder.system_schedule.last_rebuilt_at'))!,
        ),
        environment.now(),
      );
    });
  });
}

Future<int> _insertTaskList(AppDatabase db) {
  return db.into(db.taskLists).insert(
        TaskListsCompanion.insert(
          name: 'Additional reminder tasks',
          createdAt: DateTime.utc(2026, 6, 1),
        ),
      );
}

Future<int> _insertTask(
  AppDatabase db, {
  required int taskListId,
  required String uid,
  required String summary,
  DateTime? dtstart,
  DateTime? due,
  int reminderMinutesBefore = 15,
}) {
  return db.into(db.taskItems).insert(
        TaskItemsCompanion.insert(
          uid: uid,
          dtstamp: DateTime.utc(2026, 6, 1),
          summary: summary,
          dtstart: Value(dtstart),
          due: Value(due),
          taskListId: Value(taskListId),
          reminderMinutesBefore: Value(reminderMinutesBefore),
        ),
      );
}

class _FakeReminderEnvironment implements ReminderRuntimeEnvironment {
  _FakeReminderEnvironment({
    required DateTime now,
    this.isAndroid = false,
  }) : _now = now;

  final DateTime _now;

  @override
  bool isAndroid;

  @override
  bool isWindows = false;

  @override
  DateTime now() => _now;
}

class _FakeReminderGateway implements ReminderNotificationGateway {
  var canScheduleExactAlarmsValue = true;
  var pendingSystemReminderCountValue = 0;
  var cancelAllCalls = 0;
  var scheduleAttempts = 0;
  final throwOnAttemptNumbers = <int>{};
  final scheduledRequests = <ReminderRequest>[];
  final shownReminders = <_ShownReminder>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> canScheduleExactAlarms() async => canScheduleExactAlarmsValue;

  @override
  Future<void> openAndroidExactAlarmSettings() async {}

  @override
  Future<int> pendingSystemReminderCount() async {
    return pendingSystemReminderCountValue;
  }

  @override
  Future<bool> scheduleSystemReminder(ReminderRequest request) async {
    scheduleAttempts++;
    if (throwOnAttemptNumbers.contains(scheduleAttempts)) {
      throw StateError('schedule failed for attempt $scheduleAttempts');
    }
    scheduledRequests.add(request);
    return true;
  }

  @override
  Future<void> cancelAllSystemReminders() async {
    cancelAllCalls++;
    scheduledRequests.clear();
  }

  @override
  Future<void> showReminder({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    shownReminders.add(
      _ShownReminder(
        id: id,
        title: title,
        body: body,
        payload: payload,
      ),
    );
  }
}

class _ShownReminder {
  const _ShownReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final String? payload;
}
