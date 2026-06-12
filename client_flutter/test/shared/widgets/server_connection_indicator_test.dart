import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowplanv2/core/connection/server_connection_service.dart';
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/widgets/server_connection_indicator.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('renders an inactive indicator while the provider is loading',
      (tester) async {
    final pending = Completer<ServerConnectionService>();

    await _pumpIndicator(
      tester,
      override: serverConnectionServiceProvider.overrideWith(
        (ref) => pending.future,
      ),
    );

    expect(_tooltipMessage(), isNotEmpty);
    await tester.tap(find.byType(ServerConnectionIndicator));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('renders provider errors as an inactive tooltip', (tester) async {
    await _pumpIndicator(
      tester,
      override: serverConnectionServiceProvider.overrideWith((ref) async {
        throw StateError('server unavailable');
      }),
    );
    await tester.pump();

    expect(_tooltipMessage(), contains('server unavailable'));
    await tester.tap(find.byType(ServerConnectionIndicator));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('renders data states with sync progress in the tooltip',
      (tester) async {
    final service = _FakeServerConnectionService(
      const ServerConnectionState(
        level: ServerConnectionLevel.syncing,
        serverUrl: 'https://flowplan.test',
        deviceId: 'device-1',
        platform: 'windows',
        syncing: true,
        syncPhase: 'pulling',
        syncReason: 'manual refresh',
        progressCurrent: 3,
        progressTotal: 8,
      ),
    );

    await _pumpIndicator(tester, service: service);

    expect(_tooltipMessage(), contains('manual refresh'));
    expect(_tooltipMessage(), contains('3/8'));
  });

  testWidgets('compact mode hides the inline label but keeps the indicator',
      (tester) async {
    final service = _FakeServerConnectionService(_onlineState());

    await _pumpIndicator(tester, service: service, compact: true);

    expect(
      find.descendant(
        of: find.byType(ServerConnectionIndicator),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(find.byType(Tooltip), findsOneWidget);
  });

  testWidgets('dialog shows connection details and runs manual sync',
      (tester) async {
    final service = _FakeServerConnectionService(_onlineState());

    await _pumpIndicator(tester, service: service);
    await tester.tap(find.byType(ServerConnectionIndicator));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_selectableText('https://flowplan.test'), findsOneWidget);
    expect(_selectableText('device-1'), findsOneWidget);
    expect(_selectableText('windows'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(service.syncNowCalls, 1);
    expect(service.lastSyncSource, 'manual_indicator');
  });

  testWidgets('updates tooltip when the service notifies listeners',
      (tester) async {
    final service = _FakeServerConnectionService(
      _onlineState().copyWith(
        level: ServerConnectionLevel.offline,
        lastError: 'network down',
      ),
    );

    await _pumpIndicator(tester, service: service);

    expect(_tooltipMessage(), contains('network down'));

    service.update(
      _onlineState().copyWith(
        level: ServerConnectionLevel.syncing,
        syncing: true,
        syncPhase: 'applying',
        syncReason: 'retry after reconnect',
        progressCurrent: 1,
        progressTotal: 2,
        clearError: true,
      ),
    );
    await tester.pump();

    expect(_tooltipMessage(), contains('retry after reconnect'));
    expect(_tooltipMessage(), contains('1/2'));
  });

  testWidgets('dialog disables manual sync while a sync is already running',
      (tester) async {
    final service = _FakeServerConnectionService(
      _onlineState().copyWith(
        level: ServerConnectionLevel.syncing,
        syncing: true,
        syncPhase: 'pushing',
      ),
    );

    await _pumpIndicator(tester, service: service);
    await tester.tap(find.byType(ServerConnectionIndicator));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(service.syncNowCalls, 0);
  });

  testWidgets('dialog details action navigates to the server sync route',
      (tester) async {
    final service = _FakeServerConnectionService(_onlineState());

    await _pumpIndicator(tester, service: service);
    await tester.tap(find.byType(ServerConnectionIndicator));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextButton).at(1));
    await tester.pumpAndSettle();

    expect(find.text('server-sync-route'), findsOneWidget);
  });
}

Future<void> _pumpIndicator(
  WidgetTester tester, {
  _FakeServerConnectionService? service,
  Override? override,
  bool compact = false,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ServerConnectionIndicator(compact: compact),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.serverSync,
        builder: (context, state) => const Scaffold(
          body: Text('server-sync-route'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        override ??
            serverConnectionServiceProvider.overrideWith(
              (ref) async => service!,
            ),
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

Finder _selectableText(String data) {
  return find.byWidgetPredicate(
    (widget) => widget is SelectableText && widget.data == data,
  );
}

ServerConnectionState _onlineState() {
  return ServerConnectionState(
    level: ServerConnectionLevel.online,
    serverUrl: 'https://flowplan.test',
    deviceId: 'device-1',
    platform: 'windows',
    lastHeartbeatAt: DateTime.utc(2026, 6, 10, 9, 30, 5),
    lastSyncAt: DateTime.utc(2026, 6, 10, 9, 31, 5),
    pendingCount: 2,
    failedCount: 1,
  );
}

class _FakeServerConnectionService extends ChangeNotifier
    implements ServerConnectionService {
  _FakeServerConnectionService(this._state);

  ServerConnectionState _state;
  int syncNowCalls = 0;
  String? lastSyncSource;
  String? lastSyncReason;

  @override
  ServerConnectionState get state => _state;

  void update(ServerConnectionState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void start() {}

  @override
  void requestSync({
    String source = 'manual',
    String? reason,
    bool immediate = false,
  }) {}

  @override
  Future<void> syncNow({String source = 'manual', String? reason}) async {
    syncNowCalls++;
    lastSyncSource = source;
    lastSyncReason = reason;
  }

  @override
  Future<void> heartbeat({String eventSource = 'timer'}) async {}
}
