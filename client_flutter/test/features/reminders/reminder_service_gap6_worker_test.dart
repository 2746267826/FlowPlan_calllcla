import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReminderService gap6 worker coverage', () {
    late AppDatabase db;
    late _FakeReminderGateway gateway;
    late _FakeReminderEnvironment environment;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      db = createTestDatabase();
      gateway = _FakeReminderGateway();
      environment = _FakeReminderEnvironment(
        now: DateTime.utc(2026, 6, 11, 9),
        isAndroid: true,
      );
    });

    tearDown(() async {
      await db.close();
    });

    ReminderService service({int reminderMinutes = 15}) {
      return ReminderService(
        database: db,
        defaultEventReminderMinutes: () => reminderMinutes,
        gateway: gateway,
        environment: environment,
      );
    }

    test('runtime scan sends one due event reminder and de-duplicates it',
        () async {
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'runtime-event',
        summary: 'Runtime event',
        dtstart: DateTime.utc(2026, 6, 11, 9, 15),
      );
      final reminders = service();

      await reminders.scanNow();
      await reminders.scanNow();

      expect(gateway.shownReminders, hasLength(1));
      expect(gateway.shownReminders.single.title, 'Event reminder');
      expect(gateway.shownReminders.single.body, contains('Runtime event'));
      expect(
        ReminderPayloadCodec.decode(gateway.shownReminders.single.payload),
        containsPair('uid', 'runtime-event'),
      );
    });

    test('system rebuild cancels alarms when exact alarm permission is denied',
        () async {
      gateway.canScheduleExactAlarmsValue = false;

      final result = await service().rebuildSystemSchedule();
      final status = await service().getSystemStatus();
      await service().openAndroidExactAlarmSettings();

      expect(result.canScheduleExactAlarms, isFalse);
      expect(result.scheduledCount, 0);
      expect(gateway.cancelAllCalls, 1);
      expect(gateway.openSettingsCalls, 1);
      expect(status.needsAndroidExactAlarmPermission, isTrue);
    });

    test('system rebuild drops requests that fail during scheduling', () async {
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'schedule-fails',
        summary: 'Schedule fails',
        dtstart: DateTime.utc(2026, 6, 11, 9, 20),
      );
      gateway.throwOnSchedule = true;

      final result = await service().rebuildSystemSchedule();

      expect(result.canScheduleExactAlarms, isTrue);
      expect(result.scheduledCount, 0);
      expect(gateway.scheduleAttempts, 1);
      expect(gateway.scheduledRequests, isEmpty);
    });

    test('system rebuild schedules future event requests and records payload',
        () async {
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'future-event',
        summary: 'Future event',
        dtstart: DateTime.utc(2026, 6, 11, 9, 20),
      );

      final result = await service().rebuildSystemSchedule();

      expect(result.scheduledCount, 1);
      expect(gateway.cancelAllCalls, 1);
      expect(
        gateway.scheduledRequests.single.triggerAt.toUtc(),
        DateTime.utc(2026, 6, 11, 9, 5),
      );
      expect(gateway.scheduledRequests.single.title, 'Event reminder');
      expect(
        gateway.scheduledRequests.single.payload,
        containsPair('uid', 'future-event'),
      );
    });

    test('system rebuild schedules task start due and risk reminders',
        () async {
      final taskListId = await _insertTaskList(db);
      await _insertTask(
        db,
        taskListId: taskListId,
        uid: 'task-start-due',
        summary: 'Task start due',
        dtstart: DateTime.utc(2026, 6, 11, 9, 20),
        due: DateTime.utc(2026, 6, 11, 11, 30),
      );
      await _insertTask(
        db,
        taskListId: taskListId,
        uid: 'task-risk',
        summary: 'Task risk',
        due: DateTime.utc(2026, 6, 11, 12),
      );

      final result = await service().rebuildSystemSchedule();

      expect(result.scheduledCount, 4);
      expect(
        gateway.scheduledRequests.map((request) => request.title),
        containsAll(<String>[
          'Task start reminder',
          '浠诲姟鎴鎻愰啋',
          '浠诲姟椋庨櫓鎻愰啋',
        ]),
      );
    });

    test('non-Android rebuild cancels stored system reminders only', () async {
      environment.isAndroid = false;
      final reminders = service();

      final result = await reminders.rebuildSystemSchedule();
      final status = await reminders.getSystemStatus();

      expect(result.canScheduleExactAlarms, isFalse);
      expect(result.scheduledCount, 0);
      expect(gateway.cancelAllCalls, 0);
      expect(status.supportsSystemSchedule, isFalse);
      expect(status.pendingSystemReminderCount, 0);
    });
  });
}

Future<int> _insertCalendar(AppDatabase db) {
  return db.into(db.eventCalendars).insert(
        EventCalendarsCompanion.insert(
          name: 'Gap6 calendar',
          createdAt: DateTime.utc(2026, 6, 11),
        ),
      );
}

Future<int> _insertEvent(
  AppDatabase db, {
  required int calendarId,
  required String uid,
  required String summary,
  required DateTime dtstart,
}) {
  return db.into(db.calendarEvents).insert(
        CalendarEventsCompanion.insert(
          uid: uid,
          dtstamp: DateTime.utc(2026, 6, 11),
          summary: summary,
          dtstart: dtstart,
          eventCalendarId: Value(calendarId),
        ),
      );
}

Future<int> _insertTaskList(AppDatabase db) {
  return db.into(db.taskLists).insert(
        TaskListsCompanion.insert(
          name: 'Gap6 tasks',
          createdAt: DateTime.utc(2026, 6, 11),
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
}) {
  return db.into(db.taskItems).insert(
        TaskItemsCompanion.insert(
          uid: uid,
          dtstamp: DateTime.utc(2026, 6, 11),
          summary: summary,
          status: const Value('NEEDS-ACTION'),
          percentComplete: const Value(0),
          categories: const Value('[]'),
          durationMinutes: const Value(60),
          priorityLocal: const Value(2),
          isAutoScheduled: const Value(true),
          taskListId: Value(taskListId),
          reminderMinutesBefore: const Value(15),
          dtstart: Value(dtstart),
          due: Value(due),
        ),
      );
}

class _ShownReminder {
  const _ShownReminder({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });

  final int id;
  final String title;
  final String body;
  final String? payload;
}

class _FakeReminderEnvironment implements ReminderRuntimeEnvironment {
  _FakeReminderEnvironment({
    required DateTime now,
    this.isAndroid = false,
  })  : _now = now,
        isWindows = false;

  final DateTime _now;

  @override
  bool isAndroid;

  @override
  bool isWindows;

  @override
  DateTime now() => _now;
}

class _FakeReminderGateway implements ReminderNotificationGateway {
  var initializeCalls = 0;
  var canScheduleExactAlarmsValue = true;
  var pendingSystemReminderCountValue = 0;
  var cancelAllCalls = 0;
  var openSettingsCalls = 0;
  var scheduleAttempts = 0;
  var throwOnSchedule = false;
  final scheduledRequests = <ReminderRequest>[];
  final shownReminders = <_ShownReminder>[];

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    return canScheduleExactAlarmsValue;
  }

  @override
  Future<void> openAndroidExactAlarmSettings() async {
    openSettingsCalls++;
  }

  @override
  Future<int> pendingSystemReminderCount() async {
    return pendingSystemReminderCountValue;
  }

  @override
  Future<bool> scheduleSystemReminder(ReminderRequest request) async {
    scheduleAttempts++;
    if (throwOnSchedule) {
      throw StateError('schedule failed');
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
      _ShownReminder(id: id, title: title, body: body, payload: payload),
    );
  }
}
