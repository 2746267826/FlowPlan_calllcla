import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ReminderService worker H coverage', () {
    late AppDatabase db;
    late _FakeReminderGateway gateway;
    late _FakeReminderEnvironment environment;

    setUp(() {
      db = createTestDatabase();
      gateway = _FakeReminderGateway();
      environment = _FakeReminderEnvironment(
        now: DateTime.utc(2026, 6, 10, 8),
        isAndroid: true,
      );
    });

    tearDown(() async {
      await db.close();
    });

    ReminderService service({int eventReminderMinutes = 0}) {
      return ReminderService(
        database: db,
        defaultEventReminderMinutes: () => eventReminderMinutes,
        gateway: gateway,
        environment: environment,
      );
    }

    test('scanNow creates task start due and deadline-risk reminders once',
        () async {
      final reminders = service();
      final listId = await _insertTaskList(db);
      final now = environment.now();

      await _insertTask(
        db,
        taskListId: listId,
        uid: 'task-start-reminder',
        summary: 'Focus block',
        dtstart: now.add(const Duration(minutes: 15)),
        reminderMinutesBefore: 15,
        isAutoScheduled: false,
      );
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'task-due-reminder',
        summary: 'Submit report',
        dtstart: now.subtract(const Duration(hours: 1)),
        due: now.add(const Duration(minutes: 30)),
        reminderMinutesBefore: 30,
        isAutoScheduled: false,
      );
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'task-risk-reminder',
        summary: 'Rescue deadline',
        due: now.add(const Duration(minutes: 90)),
        reminderMinutesBefore: 15,
        isAutoScheduled: false,
      );

      await reminders.scanNow();
      await reminders.scanNow();

      expect(gateway.shownReminders, hasLength(3));
      final bodies = gateway.shownReminders.map((reminder) => reminder.body);
      expect(bodies, contains(contains('Focus block')));
      expect(bodies, contains(contains('Submit report')));
      expect(bodies, contains(contains('Rescue deadline')));
    });

    test('scanNow ignores tasks that have no start or due date', () async {
      final reminders = service();
      final listId = await _insertTaskList(db);

      await _insertTask(
        db,
        taskListId: listId,
        uid: 'task-without-dates',
        summary: 'Someday maybe',
        reminderMinutesBefore: 15,
      );

      await reminders.scanNow();

      expect(gateway.shownReminders, isEmpty);
    });

    test('rebuild cancels system reminders when exact alarm permission is off',
        () async {
      final reminders = service();
      final listId = await _insertTaskList(db);
      gateway.canScheduleExactAlarmsValue = false;
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'blocked-by-permission',
        summary: 'Permission blocked task',
        dtstart: environment.now().add(const Duration(hours: 1)),
        reminderMinutesBefore: 10,
      );

      final result = await reminders.rebuildSystemSchedule();

      expect(result.canScheduleExactAlarms, isFalse);
      expect(result.scheduledCount, 0);
      expect(gateway.cancelAllCalls, 1);
      expect(gateway.scheduleAttempts, 0);
      expect(
        await db.getIntSetting(
          'reminder.system_schedule.last_count',
          defaultValue: -1,
        ),
        0,
      );
    });

    test('rebuild treats false schedule results as unscheduled', () async {
      final reminders = service();
      final listId = await _insertTaskList(db);
      gateway.scheduleResult = false;
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'schedule-returned-false',
        summary: 'Schedule false task',
        dtstart: environment.now().add(const Duration(hours: 1)),
        reminderMinutesBefore: 10,
      );

      final result = await reminders.rebuildSystemSchedule();

      expect(result.canScheduleExactAlarms, isTrue);
      expect(result.scheduledCount, 0);
      expect(gateway.cancelAllCalls, 1);
      expect(gateway.scheduleAttempts, 1);
      expect(gateway.scheduledRequests, isEmpty);
      expect(
        await db.getIntSetting(
          'reminder.system_schedule.last_count',
          defaultValue: -1,
        ),
        0,
      );
    });

    test('getSystemStatus uses fallback count on Windows state branch',
        () async {
      final reminders = service();
      final lastRebuiltAt = DateTime.utc(2026, 6, 10, 7, 45);
      environment
        ..isAndroid = false
        ..isWindows = true;
      gateway
        ..canScheduleExactAlarmsValue = false
        ..pendingSystemReminderCountValue = 99;
      await db.setIntSetting('reminder.system_schedule.last_count', 6);
      await db.setSetting(
        'reminder.system_schedule.last_rebuilt_at',
        lastRebuiltAt.toIso8601String(),
      );

      final status = await reminders.getSystemStatus();

      expect(status.platformLabel, contains('Windows'));
      expect(status.runtimeScannerEnabled, isFalse);
      expect(status.supportsSystemSchedule, isFalse);
      expect(status.canScheduleExactAlarms, isFalse);
      expect(status.needsAndroidExactAlarmPermission, isFalse);
      expect(status.pendingSystemReminderCount, 6);
      expect(status.lastRebuiltAt, lastRebuiltAt);
    });

    test('scanNow emits plan deviation only when linked evidence is missing',
        () async {
      final reminders = service();
      final listId = await _insertTaskList(db);
      final now = environment.now();
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'missing-evidence-task',
        summary: 'Untracked focus',
        dtstart: now.subtract(const Duration(minutes: 20)),
        durationMinutes: 45,
      );
      final evidencedTaskId = await _insertTask(
        db,
        taskListId: listId,
        uid: 'evidenced-task',
        summary: 'Tracked focus',
        dtstart: now.subtract(const Duration(minutes: 25)),
        durationMinutes: 60,
      );
      await db.into(db.activityRecords).insert(
            ActivityRecordsCompanion.insert(
              startTime: now.subtract(const Duration(minutes: 24)),
              endTime: Value(now.subtract(const Duration(minutes: 5))),
              linkedTaskId: Value(evidencedTaskId),
              source: const Value('reminder_service_worker_h_test'),
            ),
          );

      await reminders.scanNow();
      await reminders.scanNow();

      expect(gateway.shownReminders, hasLength(1));
      expect(gateway.shownReminders.single.body, contains('Untracked focus'));
    });
  });
}

Future<int> _insertTaskList(AppDatabase db) {
  return db.into(db.taskLists).insert(
        TaskListsCompanion.insert(
          name: 'Worker H tasks',
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
  int durationMinutes = 60,
  int reminderMinutesBefore = 15,
  bool isAutoScheduled = true,
}) {
  return db.into(db.taskItems).insert(
        TaskItemsCompanion.insert(
          uid: uid,
          dtstamp: DateTime.utc(2026, 6, 1),
          summary: summary,
          dtstart: Value(dtstart),
          due: Value(due),
          durationMinutes: Value(durationMinutes),
          isAutoScheduled: Value(isAutoScheduled),
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

  DateTime _now;

  @override
  bool isAndroid;

  @override
  bool isWindows = false;

  @override
  DateTime now() => _now;

  set nowValue(DateTime value) {
    _now = value;
  }
}

class _FakeReminderGateway implements ReminderNotificationGateway {
  var canScheduleExactAlarmsValue = true;
  var pendingSystemReminderCountValue = 0;
  var cancelAllCalls = 0;
  var scheduleAttempts = 0;
  var scheduleResult = true;
  final scheduledRequests = <ReminderRequest>[];
  final shownReminders = <_ShownReminder>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> canScheduleExactAlarms() async {
    return canScheduleExactAlarmsValue;
  }

  @override
  Future<void> openAndroidExactAlarmSettings() async {}

  @override
  Future<int> pendingSystemReminderCount() async {
    return pendingSystemReminderCountValue;
  }

  @override
  Future<bool> scheduleSystemReminder(ReminderRequest request) async {
    scheduleAttempts++;
    if (!scheduleResult) {
      return false;
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
