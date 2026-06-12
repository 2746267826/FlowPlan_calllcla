import 'dart:async';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/settings/presentation/settings_page.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Android status section renders loading rows', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await _pumpAndroidStatusSection(
      tester,
      db: db,
      overrides: <Override>[
        androidUsageAccessStatusProvider.overrideWith(
          (ref) => Completer<bool>().future,
        ),
        deviceIdentityDisplayProvider.overrideWith(
          (ref) => Completer<String>().future,
        ),
        reminderSystemStatusProvider.overrideWith(
          (ref) => Completer<ReminderSystemStatus>().future,
        ),
      ],
    );

    expect(find.byIcon(Icons.query_stats_outlined), findsOneWidget);
    expect(find.byIcon(Icons.perm_device_information_outlined), findsOneWidget);
    expect(find.byIcon(Icons.alarm_on_outlined), findsOneWidget);
    expect(find.textContaining('正在'), findsNWidgets(3));
  });

  testWidgets('Android status errors show messages and retry invalidates', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    var usageReads = 0;
    var reminderReads = 0;

    await _pumpAndroidStatusSection(
      tester,
      db: db,
      overrides: <Override>[
        androidUsageAccessStatusProvider.overrideWith((ref) {
          usageReads++;
          throw StateError('usage status failed');
        }),
        deviceIdentityDisplayProvider.overrideWith((ref) {
          throw StateError('identity failed');
        }),
        reminderSystemStatusProvider.overrideWith((ref) {
          reminderReads++;
          throw StateError('alarm status failed');
        }),
      ],
    );
    await tester.pump();

    expect(find.textContaining('usage status failed'), findsOneWidget);
    expect(find.textContaining('identity failed'), findsOneWidget);
    expect(find.textContaining('alarm status failed'), findsOneWidget);
    expect(find.byType(TextButton), findsNWidgets(2));

    await tester.tap(find.byType(TextButton).first);
    await tester.pump();
    await tester.tap(find.byType(TextButton).last);
    await tester.pump();

    expect(usageReads, 2);
    expect(reminderReads, 2);
  });

  testWidgets('Android status data exposes disabled access and short identity', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _Gap6ReminderService(db);

    await _pumpAndroidStatusSection(
      tester,
      db: db,
      reminderService: service,
      overrides: <Override>[
        androidUsageAccessStatusProvider.overrideWith((ref) async => false),
        deviceIdentityDisplayProvider.overrideWith((ref) async => 'short-id'),
        reminderSystemStatusProvider.overrideWith(
          (ref) async => const ReminderSystemStatus(
            platformLabel: 'Android',
            runtimeScannerEnabled: true,
            supportsSystemSchedule: true,
            canScheduleExactAlarms: false,
            pendingSystemReminderCount: 7,
            lastRebuiltAt: null,
          ),
        ),
      ],
    );
    await tester.pump();

    expect(find.byIcon(Icons.security_outlined), findsOneWidget);
    expect(find.byIcon(Icons.alarm_off_outlined), findsOneWidget);
    expect(find.textContaining('short-id'), findsOneWidget);
    expect(find.textContaining('7'), findsWidgets);
    expect(find.textContaining('尚未重建'), findsOneWidget);

    await tester.tap(_tileWithIcon(Icons.alarm_off_outlined));
    await tester.pump();
    expect(service.openSettingsCalls, 1);

    await tester.tap(find.byIcon(Icons.refresh_outlined));
    await tester.pump();
    expect(service.rebuildCalls, 1);
  });

  testWidgets('Android status data shows granted access and formatted values', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _Gap6ReminderService(db);

    await _pumpAndroidStatusSection(
      tester,
      db: db,
      reminderService: service,
      overrides: <Override>[
        androidUsageAccessStatusProvider.overrideWith((ref) async => true),
        deviceIdentityDisplayProvider.overrideWith(
          (ref) async => 'device-abcdef1234567890',
        ),
        reminderSystemStatusProvider.overrideWith(
          (ref) async => ReminderSystemStatus(
            platformLabel: 'Android',
            runtimeScannerEnabled: true,
            supportsSystemSchedule: true,
            canScheduleExactAlarms: true,
            pendingSystemReminderCount: 2,
            lastRebuiltAt: DateTime(2026, 6, 11, 9, 5),
          ),
        ),
      ],
    );
    await tester.pump();

    expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
    expect(find.byIcon(Icons.alarm_on_outlined), findsOneWidget);
    expect(find.textContaining('device-a...7890'), findsOneWidget);
    expect(find.textContaining('2026-06-11 09:05'), findsOneWidget);

    await tester.tap(_tileWithIcon(Icons.alarm_on_outlined));
    await tester.pump();
    expect(service.openSettingsCalls, 0);
  });
}

Future<void> _pumpAndroidStatusSection(
  WidgetTester tester, {
  required AppDatabase db,
  _Gap6ReminderService? reminderService,
  required List<Override> overrides,
}) async {
  final service = reminderService ?? _Gap6ReminderService(db);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        reminderServiceProvider.overrideWithValue(service),
        ...overrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, child) => ListView(
              children: [
                settingsAndroidStatusSectionForTesting(
                  reminderStatus: ref.watch(reminderSystemStatusProvider),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await pumpUntilFound(tester, find.byType(ListTile));
}

Finder _tileWithIcon(IconData icon) {
  return find.ancestor(
    of: find.byIcon(icon),
    matching: find.byType(ListTile),
  );
}

class _Gap6ReminderService extends ReminderService {
  _Gap6ReminderService(AppDatabase db)
      : super(
          database: db,
          defaultEventReminderMinutes: () => 0,
        );

  var rebuildCalls = 0;
  var openSettingsCalls = 0;

  @override
  Future<ReminderRebuildResult> rebuildSystemSchedule() async {
    rebuildCalls++;
    return const ReminderRebuildResult(
      scheduledCount: 0,
      canScheduleExactAlarms: true,
    );
  }

  @override
  Future<ReminderSystemStatus> getSystemStatus() async {
    return const ReminderSystemStatus(
      platformLabel: 'test',
      runtimeScannerEnabled: false,
      supportsSystemSchedule: false,
      canScheduleExactAlarms: false,
      pendingSystemReminderCount: 0,
      lastRebuiltAt: null,
    );
  }

  @override
  Future<void> openAndroidExactAlarmSettings() async {
    openSettingsCalls++;
  }
}
