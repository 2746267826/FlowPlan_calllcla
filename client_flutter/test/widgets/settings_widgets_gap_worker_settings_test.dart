import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/settings/presentation/settings_page.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
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

  testWidgets('settings renders grouped sections and persists control state', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final reminderService = _GapReminderService(db);
    final shell = _DesktopShellMock()..install();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 1200),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(reminderService),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('设置'), findsWidgets);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('工作时间'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('系统'), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(find.byIcon(Icons.work_history_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    expect(find.byIcon(Icons.tune_outlined), findsOneWidget);

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(0),
      valueFragment: 'dark',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownAt(1),
      valueFragment: '60',
    );

    await _tapReachable(tester, find.text('时间制'));
    expect(find.text('12 小时制'), findsOneWidget);

    await _scrollUntilPresent(tester, _dropdownWithValue(1));
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _dropdownWithValue(1),
      valueFragment: '7',
    );

    if (Platform.isWindows) {
      await _tapReachable(tester, find.byIcon(Icons.minimize_outlined));
      await _tapReachable(tester, find.byIcon(Icons.rocket_launch_outlined));
    }

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
    expect(prefs.getInt('reminder_minutes'), 60);
    expect(prefs.getBool('use_24h'), isFalse);
    expect(prefs.getInt('first_day_of_week'), 7);
    expect(reminderService.rebuildCalls, 1);

    if (Platform.isWindows) {
      expect(
        await db.getBoolSetting(
          'desktop.minimize_to_tray',
          defaultValue: true,
        ),
        isFalse,
      );
      expect(
        await db.getBoolSetting(
          'desktop.launch_at_startup',
          defaultValue: false,
        ),
        isTrue,
      );
      expect(
        shell.calls
            .where((call) => call.method == 'setCloseToTrayEnabled')
            .map((call) => (call.arguments as Map)['enabled']),
        contains(false),
      );
      expect(
        shell.calls
            .where((call) => call.method == 'setLaunchAtStartupEnabled')
            .map((call) => (call.arguments as Map)['enabled']),
        contains(true),
      );
    }
  });

  testWidgets('work schedule dialog helper buttons and suffix clear update UI',
      (
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
        reminderServiceProvider.overrideWithValue(_GapReminderService(db)),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    await _openWorkScheduleDialog(tester);

    await tester.enterText(_scheduleFieldAt(0), '06:15-07:45');
    await _tapDialogIconButtonAt(tester, 0);
    expect(_scheduleFieldTextAt(0), isEmpty);

    await tester.enterText(_scheduleFieldAt(0), '07:15-08:45');
    await _tapDialogOutlinedButtonAt(tester, 1);
    for (final index in <int>[0, 1, 2, 3, 4]) {
      expect(_scheduleFieldTextAt(index), '07:15-08:45');
    }

    await tester.enterText(_scheduleFieldAt(5), '10:00-11:00');
    await tester.enterText(_scheduleFieldAt(6), '12:00-13:00');
    await _tapDialogOutlinedButtonAt(tester, 2);
    expect(_scheduleFieldTextAt(5), isEmpty);
    expect(_scheduleFieldTextAt(6), isEmpty);

    await _tapDialogTextButtonAt(tester, 0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_scheduleFieldTextAt(0), contains('09:00-12:00'));
    expect(_scheduleFieldTextAt(5), contains('10:00-12:00'));
    expect(_scheduleFieldTextAt(6), isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);

    final raw = await db.getSetting(_weeklyWorkScheduleKey);
    expect(raw, isNotNull);
    final saved = WeeklyWorkSchedule.fromJsonString(raw!);
    expect(saved.rangesForWeekday(DateTime.monday).first.startMinute, 9 * 60);
    expect(saved.rangesForWeekday(DateTime.sunday), isEmpty);
  });

  testWidgets('work schedule save reports parse errors and valid ranges', (
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
        reminderServiceProvider.overrideWithValue(_GapReminderService(db)),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    await _openWorkScheduleDialog(tester);

    await tester.enterText(_scheduleFieldAt(0), 'bad');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await tester.pump();
    expect(find.textContaining('格式'), findsWidgets);
    expect(await db.getSetting(_weeklyWorkScheduleKey), isNull);

    await tester.enterText(_scheduleFieldAt(0), '25:00-26:00');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await tester.pump();
    expect(find.textContaining('超出范围'), findsWidgets);
    expect(await db.getSetting(_weeklyWorkScheduleKey), isNull);

    await tester.enterText(_scheduleFieldAt(0), '24:30-24:45');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await tester.pump();
    expect(find.textContaining('24'), findsWidgets);
    expect(await db.getSetting(_weeklyWorkScheduleKey), isNull);

    await tester.enterText(_scheduleFieldAt(0), '08:00-09:30; 10:00-11:15');
    await tester.enterText(_scheduleFieldAt(1), '休息');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await _pumpUntilNoDialog(tester);

    final raw = await db.getSetting(_weeklyWorkScheduleKey);
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['version'], 1);
    final saved = WeeklyWorkSchedule.fromJsonString(raw);
    expect(
      saved.rangesForWeekday(DateTime.monday).map(
            (range) => <int>[range.startMinute, range.endMinute],
          ),
      <List<int>>[
        <int>[8 * 60, 9 * 60 + 30],
        <int>[10 * 60, 11 * 60 + 15],
      ],
    );
    expect(saved.rangesForWeekday(DateTime.tuesday), isEmpty);
  });

  testWidgets('work schedule save failure keeps dialog open with error', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    _FailingWeeklyWorkScheduleNotifier? failingSchedule;
    _DesktopShellMock().install();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.settings,
      size: const Size(900, 1000),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(_GapReminderService(db)),
        weeklyWorkScheduleNotifierProvider.overrideWith((ref) {
          return failingSchedule = _FailingWeeklyWorkScheduleNotifier(ref);
        }),
      ],
    );
    await pumpUntilFound(tester, find.byType(SettingsPage));

    await _openWorkScheduleDialog(tester);
    await tester.enterText(_scheduleFieldAt(0), '08:00-09:00');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(failingSchedule?.savedSchedules, hasLength(1));
    expect(
      failingSchedule!.savedSchedules.single
          .rangesForWeekday(DateTime.monday)
          .single
          .startMinute,
      8 * 60,
    );
    expect(await db.getSetting(_weeklyWorkScheduleKey), isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(AppKeys.settingsSaveButton))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
      'android settings section opens usage access and refreshes status', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    _DesktopShellMock().install();
    var usageStatusReads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          reminderServiceProvider.overrideWithValue(_GapReminderService(db)),
          reminderSystemStatusProvider.overrideWith(
            (ref) async => const ReminderSystemStatus(
              platformLabel: 'android',
              runtimeScannerEnabled: true,
              supportsSystemSchedule: true,
              canScheduleExactAlarms: false,
              pendingSystemReminderCount: 2,
              lastRebuiltAt: null,
            ),
          ),
          androidUsageAccessStatusProvider.overrideWith((ref) async {
            usageStatusReads++;
            return false;
          }),
          deviceIdentityDisplayProvider.overrideWith(
            (ref) async => 'android-device-123456',
          ),
        ],
        child: const MaterialApp(
          home: SettingsPage(isAndroidOverride: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.notification_important_outlined), findsOneWidget);
    await _scrollUntilPresent(tester, find.byIcon(Icons.security_outlined));
    expect(find.byIcon(Icons.phone_android_outlined), findsOneWidget);
    expect(find.byIcon(Icons.security_outlined), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(usageStatusReads, 1);

    final usageAccessTile = find.ancestor(
      of: find.text('使用情况访问权限'),
      matching: find.byType(ListTile),
    );
    expect(usageAccessTile, findsOneWidget);
    final openUsageSettingsButton = find.descendant(
      of: usageAccessTile,
      matching: find.widgetWithText(TextButton, '去开启'),
    );
    expect(openUsageSettingsButton, findsOneWidget);
    tester.widget<TextButton>(openUsageSettingsButton).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(usageStatusReads, greaterThan(1));
  });
}

Finder _dropdownAt(int index) {
  return find.byWidgetPredicate((widget) => widget is DropdownButton).at(index);
}

Finder _dropdownWithValue(Object value) {
  return find.byWidgetPredicate(
    (widget) => widget is DropdownButton && widget.value == value,
  );
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

Future<void> _openWorkScheduleDialog(WidgetTester tester) async {
  final tileTitle = find.text('多组工作时间');
  await _scrollUntilPresent(tester, tileTitle);
  await tester.tap(tileTitle);
  await tester.pump();
  await pumpUntilFound(tester, find.byType(AlertDialog));
  await pumpUntilFound(tester, find.byKey(AppKeys.settingsSaveButton));
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

Future<void> _tapDialogIconButtonAt(
  WidgetTester tester,
  int index,
) async {
  await tester.tap(_dialogButtonsOfType<IconButton>().at(index));
  await tester.pump();
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

class _GapReminderService extends ReminderService {
  _GapReminderService(AppDatabase db)
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

class _FailingWeeklyWorkScheduleNotifier extends WeeklyWorkScheduleNotifier {
  _FailingWeeklyWorkScheduleNotifier(super.ref);

  final savedSchedules = <WeeklyWorkSchedule>[];

  @override
  Future<void> setSchedule(WeeklyWorkSchedule schedule) async {
    savedSchedules.add(schedule);
    throw StateError('worker save boom');
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
