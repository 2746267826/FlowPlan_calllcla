import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReminderService worker 11 coverage', () {
    late AppDatabase db;
    late _FakeReminderGateway gateway;
    late _FakeReminderEnvironment environment;

    setUp(() {
      db = createTestDatabase();
      gateway = _FakeReminderGateway();
      environment = _FakeReminderEnvironment(
        nowValue: DateTime.utc(2026, 6, 10, 9),
      );
    });

    tearDown(() async {
      await db.close();
    });

    ReminderService service() {
      return ReminderService(
        database: db,
        defaultEventReminderMinutes: () => 15,
        gateway: gateway,
        environment: environment,
      );
    }

    test('start initializes once, rebuilds, scans, and dispose resets runtime',
        () async {
      final reminders = service();

      await reminders.start();
      await reminders.start();

      expect(gateway.initializeCalls, 1);
      expect(
        await db.getIntSetting(
          'reminder.system_schedule.last_count',
          defaultValue: -1,
        ),
        0,
      );

      final runningStatus = await reminders.getSystemStatus();
      expect(runningStatus.runtimeScannerEnabled, isTrue);

      reminders.dispose();

      final disposedStatus = await reminders.getSystemStatus();
      expect(disposedStatus.runtimeScannerEnabled, isFalse);
    });

    test('status uses non Android fallback count and invalid last rebuild safely',
        () async {
      environment
        ..isWindows = true
        ..isAndroid = false;
      gateway
        ..pendingSystemReminderCountValue = 44
        ..canScheduleExactAlarmsValue = true;
      await db.setIntSetting('reminder.system_schedule.last_count', 7);
      await db.setSetting('reminder.system_schedule.last_rebuilt_at', 'bad');

      final status = await service().getSystemStatus();

      expect(status.supportsSystemSchedule, isFalse);
      expect(status.runtimeScannerEnabled, isFalse);
      expect(status.canScheduleExactAlarms, isTrue);
      expect(status.pendingSystemReminderCount, 7);
      expect(status.lastRebuiltAt, isNull);
      expect(status.needsAndroidExactAlarmPermission, isFalse);
    });

    test('Android status reports exact alarm permission gap from gateway',
        () async {
      environment.isAndroid = true;
      gateway
        ..canScheduleExactAlarmsValue = false
        ..pendingSystemReminderCountValue = 3;
      await db.setSetting(
        'reminder.system_schedule.last_rebuilt_at',
        DateTime.utc(2026, 6, 10, 8, 45).toIso8601String(),
      );

      final status = await service().getSystemStatus();

      expect(status.supportsSystemSchedule, isTrue);
      expect(status.canScheduleExactAlarms, isFalse);
      expect(status.pendingSystemReminderCount, 3);
      expect(status.lastRebuiltAt, DateTime.utc(2026, 6, 10, 8, 45));
      expect(status.needsAndroidExactAlarmPermission, isTrue);
    });

    test('reminderSystemStatusProvider refresh tick re-reads service status',
        () async {
      environment.isAndroid = true;
      gateway
        ..canScheduleExactAlarmsValue = true
        ..pendingSystemReminderCountValue = 1;
      final reminders = service();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          reminderServiceProvider.overrideWithValue(reminders),
        ],
      );
      addTearDown(container.dispose);

      final first = await container.read(reminderSystemStatusProvider.future);
      gateway.pendingSystemReminderCountValue = 9;
      container.read(reminderScheduleRefreshTickProvider.notifier).state++;
      final second = await container.read(reminderSystemStatusProvider.future);

      expect(first.pendingSystemReminderCount, 1);
      expect(second.pendingSystemReminderCount, 9);
    });

    test('payload codec normalizes nested dates, iterables, and invalid input',
        () {
      final at = DateTime.utc(2026, 6, 10, 10, 30);

      final encoded = ReminderPayloadCodec.encode(<String, Object?>{
        'when': at,
        'nested': <String, Object?>{
          'items': <Object?>[at, null, Uri.parse('https://flowplan.test')],
        },
      });
      final decoded = ReminderPayloadCodec.decode(encoded);

      expect(decoded['when'], at.toIso8601String());
      expect(decoded['nested'], isA<Map<String, Object?>>());
      expect(
        (decoded['nested'] as Map<String, Object?>)['items'],
        <Object?>[
          at.toIso8601String(),
          null,
          'https://flowplan.test',
        ],
      );
      expect(ReminderPayloadCodec.decode('not-json'), isEmpty);
      expect(ReminderPayloadCodec.decode('[]'), isEmpty);
      expect(ReminderPayloadCodec.decode('  '), isEmpty);
    });
  });
}

class _FakeReminderEnvironment implements ReminderRuntimeEnvironment {
  _FakeReminderEnvironment({
    required this.nowValue,
  });

  DateTime nowValue;

  @override
  bool isAndroid = false;

  @override
  bool isWindows = false;

  @override
  DateTime now() => nowValue;
}

class _FakeReminderGateway implements ReminderNotificationGateway {
  var initializeCalls = 0;
  var canScheduleExactAlarmsValue = false;
  var pendingSystemReminderCountValue = 0;
  var cancelAllCalls = 0;
  var openedSettings = false;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<bool> canScheduleExactAlarms() async => canScheduleExactAlarmsValue;

  @override
  Future<void> openAndroidExactAlarmSettings() async {
    openedSettings = true;
  }

  @override
  Future<int> pendingSystemReminderCount() async {
    return pendingSystemReminderCountValue;
  }

  @override
  Future<bool> scheduleSystemReminder(ReminderRequest request) async => true;

  @override
  Future<void> cancelAllSystemReminders() async {
    cancelAllCalls++;
  }

  @override
  Future<void> showReminder({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {}
}
