import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/settings/presentation/settings_page.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('settings async providers resolve platform access and device identity',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.setSetting('device.identity.id', 'worker-device-1234567890');

    final container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(androidUsageAccessStatusProvider.future),
        isFalse);
    expect(
      await container.read(deviceIdentityDisplayProvider.future),
      'worker-device-1234567890',
    );
  });

  testWidgets(
      'work time pickers confirm values and schedule parser reports raw time errors',
      (tester) async {
    final harness = await _pumpSettingsPage(tester);

    await _tapReachable(tester, find.text('每日工作开始'));
    await pumpUntilFound(tester, find.byType(TimePickerDialog));
    await _confirmTimePicker(tester);

    await _tapReachable(tester, find.text('每日工作结束'));
    await pumpUntilFound(tester, find.byType(TimePickerDialog));
    await _confirmTimePicker(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('work_start'), 9 * 60);
    expect(prefs.getInt('work_end'), 22 * 60);
    expect(harness.reminderService.rebuildCalls, 0);

    await _openWorkScheduleDialog(tester);
    await tester.enterText(_scheduleFieldAt(0), '08:00-nope');
    await tester.tap(find.byKey(AppKeys.settingsSaveButton));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('请使用 09:00'), findsWidgets);
    expect(
      await harness.db.getSetting('scheduler.weekly_work_schedule.v1'),
      isNull,
    );
  });

  testWidgets('settings navigation tiles push their target routes',
      (tester) async {
    final harness = await _pumpSettingsPage(tester);

    await _expectTilePushesTo(
      tester,
      harness,
      title: '历史日志文件',
      routeLabel: 'route: tracker log history',
    );
    await _expectTilePushesTo(
      tester,
      harness,
      title: '数据操作审计',
      routeLabel: 'route: audit logs',
    );
    await _expectTilePushesTo(
      tester,
      harness,
      title: '全部任务与日程管理',
      routeLabel: 'route: data management',
    );
    await _expectTilePushesTo(
      tester,
      harness,
      title: '导入 / 导出与备份',
      routeLabel: 'route: ical import export',
    );
    await _expectTilePushesTo(
      tester,
      harness,
      title: 'Outlook 日历同步',
      routeLabel: 'route: outlook sync',
    );
    await _expectTilePushesTo(
      tester,
      harness,
      title: 'FlowPlanV2 服务端同步',
      routeLabel: 'route: server sync',
    );
  });
}

Future<_SettingsHarness> _pumpSettingsPage(WidgetTester tester) async {
  final db = createTestDatabase();
  final reminderService = _SettingsReminderService(db);
  _DesktopShellMock().install();
  final router = GoRouter(
    initialLocation: AppRoutes.settings,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      _dummyRoute(AppRoutes.trackerLogHistory, 'route: tracker log history'),
      _dummyRoute(AppRoutes.auditLogs, 'route: audit logs'),
      _dummyRoute(AppRoutes.dataManagement, 'route: data management'),
      _dummyRoute(AppRoutes.icalImportExport, 'route: ical import export'),
      _dummyRoute(AppRoutes.outlookSync, 'route: outlook sync'),
      _dummyRoute(AppRoutes.serverSync, 'route: server sync'),
    ],
  );

  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await db.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        reminderServiceProvider.overrideWithValue(reminderService),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await pumpUntilFound(tester, find.byType(SettingsPage));
  return _SettingsHarness(
    db: db,
    router: router,
    reminderService: reminderService,
  );
}

GoRoute _dummyRoute(String path, String label) {
  return GoRoute(
    path: path,
    builder: (context, state) => Scaffold(
      body: Center(child: Text(label)),
    ),
  );
}

Future<void> _expectTilePushesTo(
  WidgetTester tester,
  _SettingsHarness harness, {
  required String title,
  required String routeLabel,
}) async {
  harness.router.go(AppRoutes.settings);
  await tester.pumpAndSettle();
  await pumpUntilFound(tester, find.byType(SettingsPage));

  await _tapReachable(tester, find.text(title));
  await pumpUntilFound(tester, find.text(routeLabel));
}

Future<void> _openWorkScheduleDialog(WidgetTester tester) async {
  await _tapReachable(tester, find.text('多组工作时间'));
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

Future<void> _tapReachable(WidgetTester tester, Finder finder) async {
  await _scrollUntilPresent(tester, finder);
  final element = finder.evaluate().single;
  await Scrollable.ensureVisible(
    element,
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pump();
  await _scrollUntilPresent(tester, finder.hitTestable());
  await tester.tap(finder.hitTestable());
  await tester.pump();
}

Future<void> _scrollUntilPresent(WidgetTester tester, Finder finder) async {
  final scrollable = find.descendant(
    of: find.byType(SettingsPage),
    matching: find.byType(Scrollable),
  ).first;
  for (var i = 0; i < 24; i++) {
    if (finder.evaluate().isNotEmpty && finder.hitTestable().evaluate().isNotEmpty) {
      return;
    }
    await tester.drag(scrollable, const Offset(0, -320), warnIfMissed: false);
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

Future<void> _confirmTimePicker(WidgetTester tester) async {
  for (final label in const <String>['OK', '确定']) {
    final button = find.text(label);
    if (button.evaluate().isNotEmpty) {
      await tester.tap(button.last);
      await _pumpUntilGone(tester, find.byType(TimePickerDialog));
      return;
    }
  }

  final dialogButtons = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextButton),
  );
  expect(dialogButtons, findsWidgets);
  await tester.tap(dialogButtons.last);
  await _pumpUntilGone(tester, find.byType(TimePickerDialog));
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
  expect(finder, findsNothing);
}

class _SettingsHarness {
  _SettingsHarness({
    required this.db,
    required this.router,
    required this.reminderService,
  });

  final AppDatabase db;
  final GoRouter router;
  final _SettingsReminderService reminderService;
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
    return ReminderSystemStatus(
      platformLabel: 'test',
      runtimeScannerEnabled: false,
      supportsSystemSchedule: true,
      canScheduleExactAlarms: false,
      pendingSystemReminderCount: 3,
      lastRebuiltAt: DateTime.utc(2026, 6, 10, 8, 30),
    );
  }

  @override
  Future<void> openAndroidExactAlarmSettings() async {
    return;
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
