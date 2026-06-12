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

  test('work schedule JSON round-trips and invalid input falls back', () {
    final schedule = WeeklyWorkSchedule({
      DateTime.monday: const <WorkTimeRange>[
        WorkTimeRange(startMinute: 8 * 60 + 15, endMinute: 11 * 60 + 45),
        WorkTimeRange(startMinute: 13 * 60, endMinute: 17 * 60 + 30),
      ],
      DateTime.saturday: const <WorkTimeRange>[
        WorkTimeRange(startMinute: 10 * 60, endMinute: 12 * 60),
      ],
      DateTime.sunday: const <WorkTimeRange>[],
    });

    final encoded = jsonEncode(schedule.toJson());
    final decoded = WeeklyWorkSchedule.fromJsonString(encoded);

    expect(decoded.rangesForWeekday(DateTime.monday), hasLength(2));
    expect(
        decoded.summaryForWeekday(DateTime.monday), '08:15-11:45，13:00-17:30');
    expect(decoded.rangesForWeekday(DateTime.sunday), isEmpty);
    expect(jsonDecode(encoded), containsPair('version', 1));

    final fallback = WeeklyWorkSchedule.fromJsonString('{not valid json');

    expect(fallback.rangesForWeekday(DateTime.monday), hasLength(3));
    expect(fallback.rangesForWeekday(DateTime.saturday), hasLength(2));
    expect(fallback.rangesForWeekday(DateTime.sunday), isEmpty);
    expect(fallback.activeWeekdayCount, 6);
  });

  test('default weekday and weekend schedule summaries stay distinct', () {
    final defaults = WeeklyWorkSchedule.defaults();

    for (final weekday in <int>[
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    ]) {
      expect(defaults.rangesForWeekday(weekday), hasLength(3));
      expect(defaults.summaryForWeekday(weekday), contains('09:00-12:00'));
    }

    expect(defaults.rangesForWeekday(DateTime.saturday), hasLength(2));
    expect(
        defaults.summaryForWeekday(DateTime.saturday), contains('10:00-12:00'));
    expect(defaults.rangesForWeekday(DateTime.sunday), isEmpty);
    expect(defaults.summaryForWeekday(DateTime.sunday), '休息');
  });

  testWidgets('settings dropdown and time-format control persist choices',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final reminderService = _AdditionalReminderService(db);
    final shellMock = _DesktopShellMock();
    shellMock.install();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 1000),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(reminderService),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('设置'), findsWidgets);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(0),
      valueFragment: 'light',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(1),
      valueFragment: '60',
    );
    await _tapReachable(tester, find.text('时间制'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');
    expect(prefs.getInt('reminder_minutes'), 60);
    expect(prefs.getBool('use_24h'), isFalse);
    expect(reminderService.rebuildCalls, 1);

    if (Platform.isWindows) {
      await _tapReachable(tester, find.byIcon(Icons.minimize_outlined));
      expect(
        await db.getBoolSetting(
          'desktop.minimize_to_tray',
          defaultValue: true,
        ),
        false,
      );
      expect(
        shellMock.calls
            .where((call) => call.method == 'setCloseToTrayEnabled')
            .map((call) => (call.arguments as Map)['enabled']),
        contains(false),
      );
    }
  });

  testWidgets(
      'schedule dialog cancel, invalid save, and valid save are reachable',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    _DesktopShellMock().install();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 900),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(
          _AdditionalReminderService(db),
        ),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    await _openWorkScheduleDialog(tester);
    await tester.enterText(_scheduleFieldAt(0), '08:00-09:00');
    await _tapDialogTextButtonAt(tester, 1);
    await _pumpUntilNoDialog(tester);
    expect(await db.getSetting(_weeklyWorkScheduleKey), isNull);

    await _openWorkScheduleDialog(tester);
    await tester.enterText(_scheduleFieldAt(0), 'bad');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('格式'), findsWidgets);
    expect(await db.getSetting(_weeklyWorkScheduleKey), isNull);

    await tester.enterText(_scheduleFieldAt(0), '08:00-09:30, 10:00-11:15');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await _pumpUntilNoDialog(tester);

    final raw = await db.getSetting(_weeklyWorkScheduleKey);
    expect(raw, isNotNull);
    final saved = WeeklyWorkSchedule.fromJsonString(raw!);
    expect(
      saved.rangesForWeekday(DateTime.monday).map(
            (range) => <int>[range.startMinute, range.endMinute],
          ),
      <List<int>>[
        <int>[8 * 60, 9 * 60 + 30],
        <int>[10 * 60, 11 * 60 + 15],
      ],
    );
  });
}

Finder _dropdownAt(int index) {
  return find.byWidgetPredicate((widget) => widget is DropdownButton).at(index);
}

Finder _scheduleFieldAt(int index) {
  return find
      .descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      )
      .at(index);
}

Future<void> _openWorkScheduleDialog(WidgetTester tester) async {
  final tileTitle = find.text('多组工作时间');
  await _scrollUntilPresent(tester, tileTitle);
  await tester.tap(tileTitle);
  await tester.pump();
  await pumpUntilFound(tester, find.byType(AlertDialog));
  await pumpUntilFound(tester, find.byKey(AppKeys.settingsSaveButton));
}

Future<void> _tapDialogTextButtonAt(
  WidgetTester tester,
  int index,
) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        )
        .at(index),
  );
  await tester.pump();
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

class _AdditionalReminderService extends ReminderService {
  _AdditionalReminderService(AppDatabase db)
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

class _DesktopShellMock {
  final calls = <MethodCall>[];
  var launchAtStartup = false;

  void install() {
    const channel = MethodChannel('com.flowplanv2/desktop_shell');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
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
          .setMockMethodCallHandler(channel, null);
    });
  }
}
