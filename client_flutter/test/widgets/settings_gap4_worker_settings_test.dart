import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/settings/presentation/settings_page.dart';
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

  testWidgets('settings shows Android reminder status data and rebuilds it',
      (tester) async {
    if (!Platform.isAndroid) {
      return;
    }
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _SettingsGapReminderService(db);
    final status = ReminderSystemStatus(
      platformLabel: 'Android',
      runtimeScannerEnabled: true,
      supportsSystemSchedule: true,
      canScheduleExactAlarms: false,
      pendingSystemReminderCount: 3,
      lastRebuiltAt: DateTime(2026, 6, 11, 9, 5),
    );

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 1200),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(service),
        reminderSystemStatusProvider.overrideWith((ref) async => status),
        androidUsageAccessStatusProvider.overrideWith((ref) async => false),
        deviceIdentityDisplayProvider.overrideWith(
          (ref) async => 'device-abcdef1234567890',
        ),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    expect(find.byIcon(Icons.alarm_off_outlined), findsOneWidget);
    expect(find.textContaining('3'), findsWidgets);
    expect(find.textContaining('2026-06-11 09:05'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh_outlined));
    await tester.pump();

    expect(service.rebuildCalls, 1);
  });

  testWidgets('settings Android status errors expose retry actions',
      (tester) async {
    if (!Platform.isAndroid) {
      return;
    }
    final db = createTestDatabase();
    addTearDown(db.close);

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 1200),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(
          _SettingsGapReminderService(db),
        ),
        reminderSystemStatusProvider.overrideWith((ref) async {
          throw StateError('alarm status failed');
        }),
        androidUsageAccessStatusProvider.overrideWith((ref) async {
          throw StateError('usage status failed');
        }),
        deviceIdentityDisplayProvider.overrideWith((ref) async {
          throw StateError('identity failed');
        }),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));
    await tester.pump();

    expect(find.textContaining('alarm status failed'), findsOneWidget);
    expect(find.textContaining('usage status failed'), findsOneWidget);
    expect(find.textContaining('identity failed'), findsOneWidget);
    expect(find.text('閲嶈瘯'), findsWidgets);
  });

  testWidgets('settings non-Android page hides Android-only status tiles',
      (tester) async {
    if (Platform.isAndroid) {
      return;
    }
    final db = createTestDatabase();
    addTearDown(db.close);

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 1000),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(
          _SettingsGapReminderService(db),
        ),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    expect(find.byIcon(Icons.alarm_on_outlined), findsNothing);
    expect(find.byIcon(Icons.query_stats_outlined), findsNothing);
    expect(find.byIcon(Icons.perm_device_information_outlined), findsNothing);
  });

  testWidgets('settings reminder dropdown invokes schedule rebuild',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _SettingsGapReminderService(db);

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 1000),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(service),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: find
          .byWidgetPredicate(
            (widget) => widget is DropdownButton && widget.value == 15,
          )
          .first,
      valueFragment: '30',
    );

    expect(service.rebuildCalls, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('reminder_minutes'), 30);
  });
}

class _SettingsGapReminderService extends ReminderService {
  _SettingsGapReminderService(AppDatabase db)
      : super(
          database: db,
          defaultEventReminderMinutes: () => 15,
        );

  var rebuildCalls = 0;

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
}
