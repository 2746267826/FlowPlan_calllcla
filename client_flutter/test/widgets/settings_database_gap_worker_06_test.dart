import 'dart:async';
import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/settings/presentation/settings_page.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

const _weeklyWorkScheduleKey = 'scheduler.weekly_work_schedule.v1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('work schedule save disables actions until async save finishes', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    _SlowWeeklyWorkScheduleNotifier? scheduleNotifier;
    _DesktopShellMock().install();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 1000),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(_WorkerReminderService(db)),
        weeklyWorkScheduleNotifierProvider.overrideWith(
          (ref) => scheduleNotifier = _SlowWeeklyWorkScheduleNotifier.pending(
            ref,
          ),
        ),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    await _openWorkScheduleDialog(tester);
    await tester.enterText(_scheduleFieldAt(0), '08:00-09:00');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(scheduleNotifier?.savedSchedules, hasLength(1));
    expect(
      tester.widget<FilledButton>(find.byKey(AppKeys.settingsSaveButton))
          .onPressed,
      isNull,
    );
    expect(_dialogButton<TextButton>(0).evaluate(), isNotEmpty);
    expect(
      tester.widget<TextButton>(_dialogButton<TextButton>(0)).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(_dialogButton<IconButton>(0)).onPressed,
      isNull,
    );
    expect(await db.getSetting(_weeklyWorkScheduleKey), isNull);

    scheduleNotifier?.completeSave();
    await _pumpUntilNoDialog(tester);

    expect(
      scheduleNotifier!.savedSchedules.single
          .rangesForWeekday(DateTime.monday)
          .single
          .endMinute,
      9 * 60,
    );
  });

  testWidgets('work schedule parser accepts 24:00 and rejects zero length', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    _DesktopShellMock().install();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 1000),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(_WorkerReminderService(db)),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    await _openWorkScheduleDialog(tester);
    await tester.enterText(_scheduleFieldAt(0), '09:00-09:00');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('结束'), findsWidgets);
    expect(await db.getSetting(_weeklyWorkScheduleKey), isNull);

    await tester.enterText(_scheduleFieldAt(0), '23:00-24:00');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await _pumpUntilNoDialog(tester);

    final raw = await db.getSetting(_weeklyWorkScheduleKey);
    expect(raw, isNotNull);
    final saved = WeeklyWorkSchedule.fromJsonString(raw!);
    final mondayRange = saved.rangesForWeekday(DateTime.monday).single;
    expect(mondayRange.startMinute, 23 * 60);
    expect(mondayRange.endMinute, 24 * 60);
  });
}

Future<void> _openWorkScheduleDialog(WidgetTester tester) async {
  final tileTitle = find.text('多组工作时间');
  await _scrollUntilPresent(tester, tileTitle);
  await tester.tap(tileTitle);
  await tester.pump();
  await pumpUntilFound(tester, find.byType(AlertDialog));
  await pumpUntilFound(tester, find.byKey(AppKeys.settingsSaveButton));
}

Finder _scheduleFieldAt(int index) {
  return find
      .descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      )
      .at(index);
}

Finder _dialogButton<T extends Widget>(int index) {
  return find
      .descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(T),
      )
      .at(index);
}

Future<void> _scrollUntilPresent(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 20; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

Future<void> _pumpUntilNoDialog(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(AlertDialog).evaluate().isEmpty) {
      return;
    }
  }
  expect(find.byType(AlertDialog), findsNothing);
}

class _SlowWeeklyWorkScheduleNotifier extends WeeklyWorkScheduleNotifier {
  _SlowWeeklyWorkScheduleNotifier._(
    super.ref,
    this._saveCompleter,
  );

  factory _SlowWeeklyWorkScheduleNotifier.pending(Ref ref) {
    return _SlowWeeklyWorkScheduleNotifier._(ref, Completer<void>());
  }

  final Completer<void> _saveCompleter;
  final savedSchedules = <WeeklyWorkSchedule>[];

  @override
  Future<void> setSchedule(WeeklyWorkSchedule schedule) async {
    savedSchedules.add(schedule);
    await _saveCompleter.future;
  }

  void completeSave() {
    if (!_saveCompleter.isCompleted) {
      _saveCompleter.complete();
    }
  }
}

class _WorkerReminderService extends ReminderService {
  _WorkerReminderService(AppDatabase db)
      : super(
          database: db,
          defaultEventReminderMinutes: () => 0,
        );

  @override
  Future<ReminderRebuildResult> rebuildSystemSchedule() async {
    return const ReminderRebuildResult(
      scheduledCount: 0,
      canScheduleExactAlarms: false,
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

class _DesktopShellMock {
  void install() {
    if (!Platform.isWindows) {
      return;
    }
    const channel = MethodChannel('com.flowplanv2/desktop_shell');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getLaunchAtStartupEnabled':
          return false;
        case 'setLaunchAtStartupEnabled':
          return (call.arguments as Map)['enabled'] == true;
        case 'setCloseToTrayEnabled':
          return null;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }
}
