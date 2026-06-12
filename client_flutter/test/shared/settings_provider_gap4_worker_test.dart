import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/core/connection/server_connection_service.dart';
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flowplanv2/shared/widgets/server_connection_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/test_database.dart';

void main() {
  group('settings provider gap4 coverage', () {
    test('work time range rejects non-map and reports duration', () {
      expect(WorkTimeRange.fromJson('not a map'), isNull);
      expect(
        const WorkTimeRange(startMinute: 8 * 60, endMinute: 9 * 60 + 45)
            .durationMinutes,
        105,
      );
    });

    test('weekly schedule keeps disjoint ranges while merging overlaps', () {
      final schedule = WeeklyWorkSchedule({
        DateTime.monday: const <WorkTimeRange>[
          WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60),
          WorkTimeRange(startMinute: 9 * 60 + 30, endMinute: 11 * 60),
          WorkTimeRange(startMinute: 13 * 60, endMinute: 14 * 60),
        ],
      });

      expect(
        schedule
            .rangesForWeekday(DateTime.monday)
            .map((range) => <int>[range.startMinute, range.endMinute]),
        <List<int>>[
          <int>[9 * 60, 11 * 60],
          <int>[13 * 60, 14 * 60],
        ],
      );
    });

    test('reset defaults persists the normalized default schedule', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(weeklyWorkScheduleNotifierProvider.notifier)
          .setDayRanges(DateTime.monday, const <WorkTimeRange>[]);
      await container
          .read(weeklyWorkScheduleNotifierProvider.notifier)
          .resetDefaults();

      final raw = await db.getSetting('scheduler.weekly_work_schedule.v1');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['version'], 1);
      final reloaded = WeeklyWorkSchedule.fromJsonString(raw);
      expect(reloaded.activeWeekdayCount, 6);
      expect(reloaded.rangesForWeekday(DateTime.sunday), isEmpty);
    });

    test(
        'desktop-only settings stay false without touching storage off Windows',
        () async {
      if (Platform.isWindows) {
        return;
      }
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(minimizeToTrayProvider), isFalse);
      expect(container.read(launchAtStartupProvider), isFalse);

      await container.read(minimizeToTrayNotifierProvider.notifier).set(true);
      await container.read(launchAtStartupNotifierProvider.notifier).set(true);

      expect(container.read(minimizeToTrayProvider), isFalse);
      expect(container.read(launchAtStartupProvider), isFalse);
      expect(
        await db.getBoolSetting(
          'desktop.minimize_to_tray',
          defaultValue: false,
        ),
        isFalse,
      );
      expect(
        await db.getBoolSetting(
          'desktop.launch_at_startup',
          defaultValue: false,
        ),
        isFalse,
      );
    });
  });

  group('server connection indicator gap4 coverage', () {
    testWidgets('conflict count takes precedence over an online state',
        (tester) async {
      final service = _FakeServerConnectionService(
        const ServerConnectionState(
          level: ServerConnectionLevel.online,
          serverUrl: 'https://flowplan.test',
          deviceId: 'device-gap4',
          platform: 'windows',
          conflictCount: 2,
        ),
      );

      await _pumpIndicator(tester, service);

      expect(_tooltipMessage(), contains('2'));
      expect(
        _statusDotColor(),
        Colors.deepOrange,
      );
    });

    testWidgets('sync progress without a total displays the current count only',
        (tester) async {
      final service = _FakeServerConnectionService(
        const ServerConnectionState(
          level: ServerConnectionLevel.syncing,
          serverUrl: 'https://flowplan.test',
          deviceId: 'device-gap4',
          platform: 'windows',
          syncing: true,
          syncPhase: 'completed',
          progressCurrent: 5,
        ),
      );

      await _pumpIndicator(tester, service);

      expect(_tooltipMessage(), contains('5'));
      expect(_tooltipMessage(), isNot(contains('/')));
    });

    testWidgets('dialog includes recent error details when present',
        (tester) async {
      final service = _FakeServerConnectionService(
        ServerConnectionState(
          level: ServerConnectionLevel.degraded,
          serverUrl: 'https://flowplan.test',
          deviceId: 'device-gap4',
          platform: 'windows',
          lastError: 'heartbeat timed out',
          lastHeartbeatAt: DateTime.utc(2026, 6, 11, 7, 30),
          lastSyncAt: DateTime.utc(2026, 6, 11, 7, 35),
        ),
      );

      await _pumpIndicator(tester, service);
      await tester.tap(find.byType(ServerConnectionIndicator));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_selectableText('heartbeat timed out'), findsOneWidget);
    });
  });
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

Finder _selectableText(String data) {
  return find.byWidgetPredicate(
    (widget) => widget is SelectableText && widget.data == data,
  );
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
