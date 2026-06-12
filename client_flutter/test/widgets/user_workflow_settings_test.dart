import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/settings/presentation/settings_page.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

const _weeklyWorkScheduleKey = 'scheduler.weekly_work_schedule.v1';

void main() {
  testWidgets('settings schedule save validates input and persists to database',
      (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 900),
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    await tester.ensureVisible(find.text('多组工作时间'));
    await tester.tap(find.text('多组工作时间'));
    await pumpUntilFound(tester, find.byKey(AppKeys.settingsSaveButton));

    expect(find.byKey(AppKeys.settingsSaveButton), findsOneWidget);

    final mondayField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '周一',
    );
    expect(mondayField, findsOneWidget);

    await tester.enterText(mondayField, '18:00-09:00');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await tester.pump();

    expect(find.textContaining('结束时间必须晚于开始时间'), findsOneWidget);
    expect(find.byKey(AppKeys.settingsSaveButton), findsOneWidget);
    expect(await db.getSetting(_weeklyWorkScheduleKey), isNull);

    await tester.enterText(mondayField, '08:30-11:30, 13:00-17:30');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(AppKeys.settingsSaveButton), findsNothing);

    final raw = await db.getSetting(_weeklyWorkScheduleKey);
    expect(raw, isNotNull);
    final saved = WeeklyWorkSchedule.fromJsonString(raw!);
    expect(
      saved.rangesForWeekday(DateTime.monday).map((range) => [
            range.startMinute,
            range.endMinute,
          ]),
      [
        [8 * 60 + 30, 11 * 60 + 30],
        [13 * 60, 17 * 60 + 30],
      ],
    );

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['version'], 1);
  });

  testWidgets('settings schedule dialog buttons cancel reset and save ranges', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 900),
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    await _openWorkScheduleDialog(tester);
    await tester.enterText(_scheduleFieldAt(0), '07:00-08:00');
    await _tapDialogTextButtonAt(tester, 1);
    await _pumpUntilNoDialog(tester);

    expect(await db.getSetting(_weeklyWorkScheduleKey), isNull);

    await _openWorkScheduleDialog(tester);
    await _tapDialogOutlinedButtonAt(tester, 0);
    expect(_scheduleFieldTextAt(0), contains('09:00-12:00'));

    await _tapDialogTextButtonAt(tester, 0);
    await tester.pump(const Duration(milliseconds: 50));

    var raw = await db.getSetting(_weeklyWorkScheduleKey);
    expect(raw, isNotNull);
    var saved = WeeklyWorkSchedule.fromJsonString(raw!);
    expect(saved.rangesForWeekday(DateTime.monday).first.startMinute, 9 * 60);
    expect(saved.rangesForWeekday(DateTime.sunday), isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(_scheduleFieldAt(0), '07:15-08:45');
    await _tapDialogOutlinedButtonAt(tester, 1);
    await _tapDialogOutlinedButtonAt(tester, 2);
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await _pumpUntilNoDialog(tester);

    raw = await db.getSetting(_weeklyWorkScheduleKey);
    expect(raw, isNotNull);
    saved = WeeklyWorkSchedule.fromJsonString(raw!);
    for (final weekday in [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    ]) {
      expect(
        saved.rangesForWeekday(weekday).map((range) => [
              range.startMinute,
              range.endMinute,
            ]),
        [
          [7 * 60 + 15, 8 * 60 + 45],
        ],
      );
    }
    expect(saved.rangesForWeekday(DateTime.saturday), isEmpty);
    expect(saved.rangesForWeekday(DateTime.sunday), isEmpty);
  });

  testWidgets('settings controls persist preferences and rebuild reminders', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final reminderService = _SettingsReminderService(db);
    final shellCalls = <MethodCall>[];
    var launchAtStartup = false;
    const shellChannel = MethodChannel('com.flowplanv2/desktop_shell');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shellChannel, (call) async {
      shellCalls.add(call);
      switch (call.method) {
        case 'getLaunchAtStartupEnabled':
          return launchAtStartup;
        case 'setLaunchAtStartupEnabled':
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          launchAtStartup = args['enabled'] == true;
          return launchAtStartup;
        case 'setCloseToTrayEnabled':
          return null;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shellChannel, null);
    });

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 1000),
      overrides: [
        reminderServiceProvider.overrideWithValue(reminderService),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));
    await tester.pump(const Duration(milliseconds: 50));

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(0),
      valueFragment: 'dark',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(1),
      valueFragment: '30',
    );

    if (Platform.isWindows) {
      await _tapReachable(tester, find.byIcon(Icons.minimize_outlined));
      await tester.pump(const Duration(milliseconds: 50));
      await _tapReachable(tester, find.byIcon(Icons.rocket_launch_outlined));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        await db.getBoolSetting(
          'desktop.minimize_to_tray',
          defaultValue: true,
        ),
        false,
      );
      expect(
        await db.getBoolSetting(
          'desktop.launch_at_startup',
          defaultValue: false,
        ),
        true,
      );
      expect(
        shellCalls
            .where((call) => call.method == 'setCloseToTrayEnabled')
            .map((call) => (call.arguments as Map)['enabled']),
        contains(false),
      );
      expect(
        shellCalls
            .where((call) => call.method == 'setLaunchAtStartupEnabled')
            .map((call) => (call.arguments as Map)['enabled']),
        contains(true),
      );
    }

    await _tapReachable(tester, find.text('时间制'));
    await _scrollUntilPresent(tester, _dropdownWithValue(1));
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownWithValue(1),
      valueFragment: '7',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
    expect(prefs.getInt('reminder_minutes'), 30);
    expect(prefs.getBool('use_24h'), false);
    expect(prefs.getInt('first_day_of_week'), 7);
    expect(reminderService.rebuildCalls, 1);
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

String _scheduleFieldTextAt(int index) {
  final field = _scheduleFieldAt(index).evaluate().single.widget as TextField;
  return field.controller?.text ?? '';
}

Finder _dialogButtonsOfType<T extends Widget>() {
  return find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(T),
  );
}

Future<void> _tapDialogOutlinedButtonAt(
  WidgetTester tester,
  int index,
) async {
  await tester.tap(_dialogButtonsOfType<OutlinedButton>().at(index));
  await tester.pump();
}

Future<void> _tapDialogTextButtonAt(
  WidgetTester tester,
  int index,
) async {
  await tester.tap(_dialogButtonsOfType<TextButton>().at(index));
  await tester.pump();
}

Finder _dropdownAt(int index) {
  return find.byWidgetPredicate((widget) => widget is DropdownButton).at(index);
}

Finder _dropdownWithValue(Object value) {
  return find.byWidgetPredicate(
    (widget) => widget is DropdownButton && widget.value == value,
  );
}

Future<void> _tapReachable(WidgetTester tester, Finder finder) async {
  await _scrollUntilPresent(tester, finder);
  final element = finder.evaluate().single;
  await Scrollable.ensureVisible(
    element,
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pump();
  await tester.tap(finder.hitTestable());
  await tester.pump();
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

class _SettingsReminderService extends ReminderService {
  _SettingsReminderService(AppDatabase db)
      : super(
          database: db,
          defaultEventReminderMinutes: () => 0,
        );

  var rebuildCalls = 0;

  @override
  Future<ReminderRebuildResult> rebuildSystemSchedule() async {
    rebuildCalls++;
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
