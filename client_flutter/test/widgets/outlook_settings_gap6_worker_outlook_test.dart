import 'package:flowplanv2/features/sync/ms_graph_service.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_calendar_service.dart';
import 'package:flowplanv2/features/sync/outlook_managed_container_service.dart';
import 'package:flowplanv2/features/sync/outlook_settings_page.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_sync_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/outlook_settings_test_harness.dart';

void main() {
  setUp(OutlookAuthService.debugResetTestOverrides);
  tearDown(OutlookAuthService.debugResetTestOverrides);

  testWidgets(
    'authorization success updates connection state and clears pasted code',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: _configuredPreferences(),
        extraOverrides: <Override>[
          outlookCalendarServiceFactoryProvider.overrideWithValue(
            (config) => _Gap6CalendarService.success(config),
          ),
        ],
      );

      await tester.enterText(
        find.byType(TextField).last,
        'https://callback.local/?code=gap6-code&state=gap6-state',
      );
      await _tapElevatedIcon(tester, Icons.login);

      expect(find.textContaining('认证成功'), findsWidgets);
      expect(find.textContaining('Outlook 连接成功'), findsOneWidget);
      expect(find.byIcon(Icons.login), findsNothing);
      expect(find.textContaining('已连接 Outlook'), findsWidgets);
    },
  );

  testWidgets(
    'authorization auth exceptions surface user message and red snackbar',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: _configuredPreferences(),
        extraOverrides: <Override>[
          outlookCalendarServiceFactoryProvider.overrideWithValue(
            (config) => _Gap6CalendarService.authFailure(config),
          ),
        ],
      );

      await tester.enterText(find.byType(TextField).last, 'gap6-code');
      await _tapElevatedIcon(tester, Icons.login);

      expect(find.textContaining('gap6 auth denied'), findsWidgets);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, Colors.redAccent);
    },
  );

  testWidgets(
    'manual sync paused and missing grant guards show bottom status feedback',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(syncMode: OutlookSyncMode.paused),
      );

      await _tapElevatedIcon(tester, Icons.sync);
      expect(find.textContaining('当前 Outlook 同步处于暂停状态'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpOutlookSettingFrames(tester);
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.readOnly,
          scope: 'Calendars.Read offline_access',
        ),
      );

      await _tapElevatedIcon(tester, Icons.sync);
      expect(find.textContaining('当前模式需要读写授权'), findsOneWidget);
    },
  );

  testWidgets(
    'mirror cleanup read-only and missing write grant guards render status',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.readOnly,
          grantedMode: OutlookSyncMode.readOnly,
        ),
        seedData: true,
      );

      await _expandSection(tester, '同步对象');
      await _tapText(tester, '切换为双向同步');
      expect(find.textContaining('请重新认证一次'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpOutlookSettingFrames(tester);
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.readOnly,
          scope: 'Calendars.Read offline_access',
        ),
        seedData: true,
      );

      await _expandSection(tester, '同步对象');
      await _tapText(tester, '重新进行读写授权');
      expect(find.textContaining('当前还没有 Outlook 读写授权'), findsOneWidget);
    },
  );

  testWidgets(
    'binding an unbound task list refreshes bindings and reports container name',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
        seedData: true,
        extraOverrides: <Override>[
          outlookManagedContainerServiceFactoryProvider.overrideWithValue(
            ({
              required OutlookConfig config,
              required OutlookSyncBindingsRepository bindingsRepository,
            }) =>
                OutlookManagedContainerService(
              config: config,
              bindingsRepository: bindingsRepository,
              graphServiceFactory: (config, {required syncMode}) =>
                  _Gap6GraphService(config, syncMode: syncMode),
            ),
          ),
        ],
      );
      final before = await harness.countTaskListBindings();

      await _expandSection(tester, '同步对象');
      await _tapTileAction(tester, outlookUnboundTaskListName, '绑定镜像');

      expect(await harness.countTaskListBindings(), before + 1);
      expect(
        find.textContaining(
          OutlookSyncPolicy.buildManagedCalendarName(
            kind: OutlookManagedCalendarKind.taskMirrorBook,
            containerName: outlookUnboundTaskListName,
          ),
        ),
        findsWidgets,
      );
    },
  );
}

Map<String, Object> _configuredPreferences() {
  return <String, Object>{
    'outlook_client_id': 'gap6-client',
    'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
  };
}

class _Gap6CalendarService extends OutlookCalendarService {
  _Gap6CalendarService.success(super.config) : _throws = false;

  _Gap6CalendarService.authFailure(super.config) : _throws = true;

  final bool _throws;

  @override
  Future<AuthToken> exchangeCodeForToken(
    String rawAuthorizationInput, {
    OutlookSyncMode requestedMode = OutlookSyncMode.readOnly,
  }) async {
    if (_throws) {
      throw const OutlookAuthException(
        code: 'gap6_denied',
        userMessage: 'gap6 auth denied',
      );
    }
    return AuthToken(
      accessToken: 'gap6-access',
      refreshToken: 'gap6-refresh',
      expiresInSeconds: 3600,
      obtainedAt: DateTime.utc(2026, 6, 11, 8),
      expiresAt: DateTime.utc(2099),
      grantedMode: OutlookSyncMode.bidirectional,
      scope: 'Calendars.Read Calendars.ReadWrite offline_access',
    );
  }
}

class _Gap6GraphService extends MsGraphService {
  _Gap6GraphService(super.config, {required super.syncMode});

  @override
  Future<List<Map<String, dynamic>>> getCalendars() async {
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> createCalendar({
    required String name,
    required bool isFlowPlanV2ManagedContainer,
  }) async {
    return <String, dynamic>{
      'id': 'gap6-${name.hashCode}',
      'name': name,
    };
  }
}

Future<void> _tapElevatedIcon(WidgetTester tester, IconData icon) async {
  final iconFinder = find.byIcon(icon).first;
  final button = find
      .ancestor(
        of: iconFinder,
        matching: find.byType(ElevatedButton),
      )
      .first;
  await _bringIntoView(tester, button);
  await tester.tap(button);
  await pumpOutlookSettingFrames(tester);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final button = _buttonWithText(text);
  final target = button?.first ?? find.text(text).first;
  await _bringIntoView(tester, target);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(target);
  await pumpOutlookSettingFrames(tester);
}

Future<void> _tapTileAction(
  WidgetTester tester,
  String tileTitle,
  String actionLabel,
) async {
  final title = find.text(tileTitle).last;
  await _bringIntoView(tester, title);
  final titleCenter = tester.getCenter(title);
  final candidates = find.widgetWithText(TextButton, actionLabel).evaluate();
  expect(candidates, isNotEmpty);

  Element? closest;
  var closestDistance = double.infinity;
  for (final candidate in candidates) {
    final center = tester.getCenter(find.byWidget(candidate.widget));
    final distance = (center.dy - titleCenter.dy).abs();
    if (distance < closestDistance) {
      closest = candidate;
      closestDistance = distance;
    }
  }

  final action = find.byWidget(closest!.widget);
  await _bringIntoView(tester, action);
  await tester.tap(action);
  await pumpOutlookSettingFrames(tester);
}

Finder? _buttonWithText(String text) {
  for (final finder in <Finder>[
    find.widgetWithText(TextButton, text),
    find.widgetWithText(ElevatedButton, text),
    find.widgetWithText(FilledButton, text),
    find.widgetWithText(OutlinedButton, text),
  ]) {
    if (finder.evaluate().isNotEmpty) {
      return finder;
    }
  }
  return null;
}

Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.35,
    duration: Duration.zero,
  );
  await tester.pump();
}

Future<void> _expandSection(WidgetTester tester, String title) async {
  final finder = find.text(title).first;
  await tester.ensureVisible(finder);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(finder);
  await pumpOutlookSettingFrames(tester);
}
