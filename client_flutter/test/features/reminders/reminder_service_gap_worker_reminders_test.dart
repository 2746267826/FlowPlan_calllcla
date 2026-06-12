import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemReminderRuntimeEnvironment coverage', () {
    test('now returns the current wall clock time', () {
      const environment = SystemReminderRuntimeEnvironment();
      final before = DateTime.now();

      final value = environment.now();

      final after = DateTime.now();
      expect(value.isBefore(before), isFalse);
      expect(value.isAfter(after), isFalse);
    });
  });

  group('ReminderService gap worker reminders coverage', () {
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

    ReminderService service({int eventReminderMinutes = 15}) {
      return ReminderService(
        database: db,
        defaultEventReminderMinutes: () => eventReminderMinutes,
        gateway: gateway,
        environment: environment,
      );
    }

    test(
        'reentrant rebuild returns pending gateway status without rescheduling',
        () async {
      final listId = await _insertTaskList(db);
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'reentrant-start',
        summary: 'Reentrant start',
        dtstart: environment.now().add(const Duration(hours: 1)),
        reminderMinutesBefore: 10,
      );
      gateway
        ..pendingSystemReminderCountValue = 23
        ..canScheduleExactAlarmsValue = true;

      late ReminderService reminders;
      ReminderRebuildResult? nestedResult;
      gateway.onSchedule = (_) async {
        nestedResult = await reminders.rebuildSystemSchedule();
      };
      reminders = service(eventReminderMinutes: 0);

      final result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 1);
      expect(result.canScheduleExactAlarms, isTrue);
      expect(nestedResult?.scheduledCount, 23);
      expect(nestedResult?.canScheduleExactAlarms, isTrue);
      expect(gateway.scheduleAttempts, 1);
      expect(gateway.cancelAllCalls, 1);
    });

    test('scan trims old delivered keys and allows only overflow to redeliver',
        () async {
      final reminders = service(eventReminderMinutes: 0);
      final listId = await _insertTaskList(db);
      final now = environment.now();
      for (var index = 0; index < 405; index++) {
        await _insertTask(
          db,
          taskListId: listId,
          uid: 'bulk-start-$index',
          summary: 'Bulk task $index',
          dtstart: now.add(const Duration(minutes: 15)),
          reminderMinutesBefore: 15,
          isAutoScheduled: false,
        );
      }

      await reminders.scanNow();
      expect(gateway.shownReminders, hasLength(405));

      await reminders.scanNow();

      expect(gateway.shownReminders, hasLength(510));
      expect(
        gateway.shownReminders
            .skip(405)
            .map((reminder) => reminder.body)
            .where((body) => body.contains('Bulk task')),
        hasLength(105),
      );
    });

    test('system scheduling skips deadline risk when planned start is earlier',
        () async {
      final reminders = service(eventReminderMinutes: 0);
      final listId = await _insertTaskList(db);
      final now = environment.now();
      await _insertTask(
        db,
        taskListId: listId,
        uid: 'risk-skipped-by-start',
        summary: 'Already planned before risk',
        dtstart: now.add(const Duration(minutes: 45)),
        due: now.add(const Duration(hours: 3)),
        reminderMinutesBefore: 15,
      );

      final result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 2);
      expect(
        gateway.scheduledRequests
            .map((request) => request.triggerAt.millisecondsSinceEpoch)
            .toList(),
        <DateTime>[
          DateTime.utc(2026, 6, 10, 8, 30),
          DateTime.utc(2026, 6, 10, 10, 45),
        ].map((value) => value.millisecondsSinceEpoch).toList(),
      );
      expect(
        gateway.scheduledRequests.where(
          (request) =>
              request.triggerAt.millisecondsSinceEpoch ==
              DateTime.utc(2026, 6, 10, 9).millisecondsSinceEpoch,
        ),
        isEmpty,
      );
    });

    test('weekly and yearly recurrence fast-forward into system window',
        () async {
      environment.nowValue = DateTime.utc(2026, 6, 10, 8);
      final reminders = service(eventReminderMinutes: 30);
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'weekly-fast-forward',
        summary: 'Weekly sync',
        dtstart: DateTime.utc(2026, 6, 1, 9),
        rrule: 'FREQ=WEEKLY;COUNT=4',
      );
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'yearly-fast-forward',
        summary: 'Annual review',
        dtstart: DateTime.utc(2024, 6, 12, 10),
        rrule: 'FREQ=YEARLY;COUNT=5',
      );

      final result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 2);
      expect(
        gateway.scheduledRequests
            .map((request) => request.triggerAt.millisecondsSinceEpoch)
            .toList(),
        <DateTime>[
          DateTime.utc(2026, 6, 12, 9, 30),
          DateTime.utc(2026, 6, 15, 8, 30),
        ].map((value) => value.millisecondsSinceEpoch).toList(),
      );
      final payloads = gateway.scheduledRequests.map((request) {
        return ReminderPayloadCodec.decode(request.encodedPayload);
      });
      expect(
        payloads,
        contains(
          containsPair(
            'occurrenceAt',
            DateTime.utc(2026, 6, 12, 10).toIso8601String(),
          ),
        ),
      );
      expect(
        payloads,
        contains(
          containsPair(
            'occurrenceAt',
            DateTime.utc(2026, 6, 15, 9).toIso8601String(),
          ),
        ),
      );
    });

    test('rrule until forms bound recurring event reminders', () async {
      final reminders = service(eventReminderMinutes: 30);
      final calendarId = await _insertCalendar(db);
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'until-date-form',
        summary: 'Date until',
        dtstart: DateTime.utc(2026, 6, 9, 9),
        rrule: 'FREQ=DAILY;UNTIL=20260610',
      );
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'until-z-form',
        summary: 'UTC until',
        dtstart: DateTime.utc(2026, 6, 9, 10),
        rrule: 'FREQ=DAILY;UNTIL=20260610T100000Z',
      );
      await _insertEvent(
        db,
        calendarId: calendarId,
        uid: 'until-iso-form',
        summary: 'ISO until',
        dtstart: DateTime.utc(2026, 6, 9, 11),
        rrule: 'FREQ=DAILY;UNTIL=2026-06-10T11:00:00Z',
      );

      final result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 3);
      expect(
        gateway.scheduledRequests.map((request) => request.body),
        containsAll(<Matcher>[
          contains('Date until'),
          contains('UTC until'),
          contains('ISO until'),
        ]),
      );
    });

    test('empty rebuild cancels Android reminders and persists zero count',
        () async {
      final reminders = service(eventReminderMinutes: 0);

      final result = await reminders.rebuildSystemSchedule();

      expect(result.scheduledCount, 0);
      expect(result.canScheduleExactAlarms, isTrue);
      expect(gateway.cancelAllCalls, 1);
      expect(gateway.scheduleAttempts, 0);
      expect(
        await db.getIntSetting(
          'reminder.system_schedule.last_count',
          defaultValue: -1,
        ),
        0,
      );
      expect(
        DateTime.parse(
          (await db.getSetting('reminder.system_schedule.last_rebuilt_at'))!,
        ),
        environment.now(),
      );
    });
  });

  group('SystemReminderNotificationGateway platform channel coverage', () {
    const channel = MethodChannel('com.flowplanv2.app/android_reminders');
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'canScheduleExactAlarms':
            return true;
          case 'pendingExactReminderCount':
            return 7;
          case 'scheduleExactReminder':
            return true;
          case 'openExactAlarmSettings':
          case 'cancelAllExactReminders':
            return null;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('non-Android gateway methods are unavailable no-ops', () async {
      final gateway = SystemReminderNotificationGateway(
        _FakeReminderEnvironment(
          now: DateTime.utc(2026, 6, 10),
          isAndroid: false,
        ),
      );

      await gateway.initialize();
      expect(await gateway.canScheduleExactAlarms(), isFalse);
      expect(await gateway.pendingSystemReminderCount(), 0);
      expect(
        await gateway.scheduleSystemReminder(
          ReminderRequest(
            id: 1,
            triggerAt: DateTime.utc(2026, 6, 10, 9),
            title: 'Title',
            body: 'Body',
          ),
        ),
        isFalse,
      );
      await gateway.openAndroidExactAlarmSettings();
      await gateway.cancelAllSystemReminders();
      await gateway.showReminder(id: 1, title: 'Title', body: 'Body');

      expect(calls, isEmpty);
    });

    test('Android channel methods return values and encode schedule payload',
        () async {
      final gateway = SystemReminderNotificationGateway(
        _FakeReminderEnvironment(
          now: DateTime.utc(2026, 6, 10),
          isAndroid: true,
        ),
      );
      final request = ReminderRequest(
        id: 42,
        triggerAt: DateTime.utc(2026, 6, 10, 9, 30),
        title: 'Exact title',
        body: 'Exact body',
        payload: <String, Object?>{'kind': 'test'},
      );

      expect(await gateway.canScheduleExactAlarms(), isTrue);
      expect(await gateway.pendingSystemReminderCount(), 7);
      expect(await gateway.scheduleSystemReminder(request), isTrue);
      await gateway.openAndroidExactAlarmSettings();
      await gateway.cancelAllSystemReminders();

      expect(
        calls.map((call) => call.method),
        <String>[
          'canScheduleExactAlarms',
          'pendingExactReminderCount',
          'scheduleExactReminder',
          'openExactAlarmSettings',
          'cancelAllExactReminders',
        ],
      );
      final scheduleCall = calls.singleWhere(
        (call) => call.method == 'scheduleExactReminder',
      );
      final arguments = scheduleCall.arguments as Map<Object?, Object?>;
      expect(arguments['id'], 42);
      expect(
        arguments['triggerAtMillis'],
        DateTime.utc(2026, 6, 10, 9, 30).millisecondsSinceEpoch,
      );
      expect(arguments['title'], 'Exact title');
      expect(arguments['body'], 'Exact body');
      expect(
        ReminderPayloadCodec.decode(arguments['payload'] as String?),
        containsPair('kind', 'test'),
      );
    });

    test('Android channel exceptions and nulls fall back safely', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'openExactAlarmSettings' ||
            call.method == 'cancelAllExactReminders') {
          throw PlatformException(code: 'blocked');
        }
        return null;
      });
      final gateway = SystemReminderNotificationGateway(
        _FakeReminderEnvironment(
          now: DateTime.utc(2026, 6, 10),
          isAndroid: true,
        ),
      );

      expect(await gateway.canScheduleExactAlarms(), isFalse);
      expect(await gateway.pendingSystemReminderCount(), 0);
      expect(
        await gateway.scheduleSystemReminder(
          ReminderRequest(
            id: 9,
            triggerAt: DateTime.utc(2026, 6, 10, 10),
            title: 'Null schedule',
            body: 'Body',
          ),
        ),
        isFalse,
      );
      await gateway.openAndroidExactAlarmSettings();
      await gateway.cancelAllSystemReminders();

      expect(calls.map((call) => call.method), hasLength(5));
    });
  });
}

Future<int> _insertCalendar(AppDatabase db) {
  return db.into(db.eventCalendars).insert(
        EventCalendarsCompanion.insert(
          name: 'Gap worker calendar',
          createdAt: DateTime.utc(2026, 6, 1),
        ),
      );
}

Future<int> _insertEvent(
  AppDatabase db, {
  required int calendarId,
  required String uid,
  required String summary,
  required DateTime dtstart,
  String? rrule,
}) {
  return db.into(db.calendarEvents).insert(
        CalendarEventsCompanion.insert(
          uid: uid,
          dtstamp: DateTime.utc(2026, 6, 1),
          summary: summary,
          dtstart: dtstart,
          eventCalendarId: Value(calendarId),
          rrule: Value(rrule),
        ),
      );
}

Future<int> _insertTaskList(AppDatabase db) {
  return db.into(db.taskLists).insert(
        TaskListsCompanion.insert(
          name: 'Gap worker tasks',
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
  Future<void> Function(ReminderRequest request)? onSchedule;
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
    await onSchedule?.call(request);
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
