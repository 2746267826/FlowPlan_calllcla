import 'dart:async';

import 'package:flowplanv2/core/connection/server_connection_service.dart';
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/storage/database_restore_service.dart';
import 'package:flowplanv2/features/ical/ical_import_export_page_body.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flowplanv2/shared/widgets/server_connection_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/fake_path_provider.dart';
import '../test_support/ical_import_export_harness.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

final _stamp = DateTime.utc(2026, 6, 11, 9);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('settings provider gap5 coverage', () {
    test('invalid persisted theme mode falls back to system', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'theme_mode': 'not-a-theme',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('contained overlapping ranges keep the longer existing end', () {
      final schedule = WeeklyWorkSchedule({
        DateTime.monday: const <WorkTimeRange>[
          WorkTimeRange(startMinute: 9 * 60, endMinute: 12 * 60),
          WorkTimeRange(startMinute: 10 * 60, endMinute: 11 * 60),
        ],
      });

      expect(
        schedule.rangesForWeekday(DateTime.monday).single.endMinute,
        12 * 60,
      );
    });
  });

  group('iCal page gap5 coverage', () {
    testWidgets('task list loading state is shown after calendars load',
        (tester) async {
      final taskLists = StreamController<List<TaskList>>();
      addTearDown(taskLists.close);

      await _pumpIcalPage(
        tester,
        overrides: <Override>[
          allEventCalendarsProvider.overrideWith(
            (ref) => Stream<List<EventCalendar>>.value([
              EventCalendar(
                id: 1,
                name: 'Loaded calendar',
                colorHex: '#6B5EE4',
                isVisible: true,
                isDefault: true,
                source: 'local',
                createdAt: _stamp,
              ),
            ]),
          ),
          allTaskListsProvider.overrideWith((ref) => taskLists.stream),
          archivedTaskListsProvider.overrideWith(
            (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
          ),
        ],
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loaded calendar'), findsNothing);
    });

    testWidgets('pending restore clear failures leave a status message',
        (tester) async {
      await _pumpIcalPage(
        tester,
        restoreService: _ThrowingRestoreService(),
        overrides: _emptyIcalProviders(),
      );

      final cancel = find.widgetWithText(TextButton, '取消恢复');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await pumpIcalFrames(tester);

      expect(find.textContaining('取消待恢复副本失败'), findsOneWidget);
      expect(find.textContaining('clear failed'), findsOneWidget);
    });

    testWidgets('replace import summary covers empty-calendar branch',
        (tester) async {
      final harness = await ICalImportExportHarness.pump(tester);
      final calendarId = await harness.createCalendar(
        name: 'Empty Replace',
        isDefault: true,
      );
      await pumpIcalFrames(tester);

      await _tapChoiceChip(tester, '清空后导入');
      harness.filePicker.queuePickText(
        name: 'replace-empty.ics',
        content: _ics([
          _vevent(
            uid: 'replacement-empty',
            summary: 'Replacement empty',
            start: '20260612T090000',
            end: '20260612T100000',
          ),
        ]),
      );

      await _tapIcalButtonWithRealAsync(tester, '选择文件');
      await pumpUntilIcalFound(tester, find.byType(AlertDialog));
      await _tapDialogButton(tester, '继续');
      await pumpIcalFrames(tester);

      final events = await _waitForEvents(tester, harness, calendarId);
      expect(events, hasLength(1));
      expect(events.single.summary, 'Replacement empty');
      expect(
        find.textContaining('已先清空「Empty Replace」中的 0 条原有日程，再导入 1 条新日程'),
        findsOneWidget,
      );
    });
  });

  group('server connection indicator gap5 coverage', () {
    testWidgets('explicit conflicted level is rendered even with zero count',
        (tester) async {
      final service = _FakeServerConnectionService(
        const ServerConnectionState(
          level: ServerConnectionLevel.conflicted,
          serverUrl: 'https://flowplan.test',
          deviceId: 'device-gap5',
          platform: 'windows',
        ),
      );

      await _pumpIndicator(tester, service);

      expect(_tooltipMessage(), contains('0'));
      expect(_statusDotColor(), Colors.deepOrange);
    });

    testWidgets('failed sync phase label and close action are reachable',
        (tester) async {
      final service = _FakeServerConnectionService(
        const ServerConnectionState(
          level: ServerConnectionLevel.syncing,
          serverUrl: 'https://flowplan.test',
          deviceId: 'device-gap5',
          platform: 'windows',
          syncing: true,
          syncPhase: 'failed',
        ),
      );

      await _pumpIndicator(tester, service);

      expect(_tooltipMessage(), contains('失败'));
      await tester.tap(find.byType(ServerConnectionIndicator));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '关闭'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}

List<Override> _emptyIcalProviders() {
  return <Override>[
    allEventCalendarsProvider.overrideWith(
      (ref) => Stream<List<EventCalendar>>.value(const <EventCalendar>[]),
    ),
    allTaskListsProvider.overrideWith(
      (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
    ),
    archivedTaskListsProvider.overrideWith(
      (ref) => Stream<List<TaskList>>.value(const <TaskList>[]),
    ),
  ];
}

Future<void> _pumpIcalPage(
  WidgetTester tester, {
  required List<Override> overrides,
  DatabaseRestoreService restoreService = const DatabaseRestoreService(),
}) async {
  final documentsDirectory = await setFakePathProviderDocumentsDirectory(
    'settings_ical_reminders_gap5_',
  );
  final db = createTestDatabase();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(900, 1400),
    overrides: overrides,
    child: MaterialApp(
      home: ICalImportExportPage(restoreService: restoreService),
    ),
  );
  await pumpIcalFrames(tester);
}

Future<void> _pumpIndicator(
  WidgetTester tester,
  _FakeServerConnectionService service,
) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ServerConnectionIndicator(),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.serverSync,
        builder: (context, state) => const Scaffold(body: Text('server sync')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        serverConnectionServiceProvider.overrideWith((ref) async => service),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

String _tooltipMessage() {
  final tooltip = find
      .byType(Tooltip)
      .evaluate()
      .map((element) => element.widget)
      .whereType<Tooltip>()
      .single;
  return tooltip.message ?? '';
}

Color _statusDotColor() {
  final decorated = find
      .descendant(
        of: find.byType(ServerConnectionIndicator),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.decoration is BoxDecoration,
        ),
      )
      .evaluate()
      .map((element) => element.widget)
      .whereType<Container>()
      .single;
  return (decorated.decoration! as BoxDecoration).color!;
}

Future<void> _tapChoiceChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  expect(chip, findsOneWidget);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

Future<void> _tapDialogButton(WidgetTester tester, String label) async {
  final button = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(label),
  );
  expect(button, findsOneWidget);
  await tester.runAsync(() async {
    await tester.tap(button);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

Future<List<CalendarEvent>> _waitForEvents(
  WidgetTester tester,
  ICalImportExportHarness harness,
  int calendarId,
) async {
  for (var i = 0; i < 20; i++) {
    final events = await harness.eventsInCalendar(calendarId);
    if (events.isNotEmpty) {
      return events;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  return harness.eventsInCalendar(calendarId);
}

Future<void> _tapIcalButtonWithRealAsync(
  WidgetTester tester,
  String text,
) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.last);
  await tester.runAsync(() async {
    await tester.tap(finder.last);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

String _ics(List<String> events) {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    ...events.map((event) => event.trim()),
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

String _vevent({
  required String uid,
  required String summary,
  required String start,
  required String end,
}) {
  return '''
BEGIN:VEVENT
UID:$uid
SUMMARY:$summary
DTSTART:$start
DTEND:$end
STATUS:CONFIRMED
END:VEVENT
''';
}

class _ThrowingRestoreService extends DatabaseRestoreService {
  @override
  Future<PendingDatabaseRestore?> getPendingRestore() async {
    return PendingDatabaseRestore(
      sourcePath: 'C:/tmp/source.db',
      stagedPath: 'C:/tmp/staged.db',
      stagedAt: _stamp,
    );
  }

  @override
  Future<DatabaseRestoreNotice?> consumeRestoreNotice() async {
    return null;
  }

  @override
  Future<void> clearPendingRestore() async {
    throw StateError('clear failed');
  }
}

class _FakeServerConnectionService extends ChangeNotifier
    implements ServerConnectionService {
  _FakeServerConnectionService(this._state);

  final ServerConnectionState _state;

  @override
  ServerConnectionState get state => _state;

  @override
  Future<void> heartbeat({String eventSource = 'timer'}) async {}

  @override
  void requestSync({
    String source = 'manual',
    String? reason,
    bool immediate = false,
  }) {}

  @override
  Future<void> syncNow({String source = 'manual', String? reason}) async {}

  @override
  void start() {}
}
