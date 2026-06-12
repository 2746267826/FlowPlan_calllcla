import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/outlook_settings_test_harness.dart';

void main() {
  setUp(OutlookAuthService.debugResetTestOverrides);
  tearDown(OutlookAuthService.debugResetTestOverrides);

  testWidgets(
    'authorization callback keeps server-managed exchange failure local',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: <String, Object>{
          'outlook_client_id': 'gap5-client',
          'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
          'outlook_pending_auth_session': jsonEncode(<String, Object?>{
            'client_id': 'gap5-client',
            'code_verifier': 'gap5-verifier',
            'state': 'gap5-state',
            'requested_mode': OutlookSyncMode.bidirectional.storageValue,
            'created_at': DateTime.utc(2026, 6, 11, 9).toIso8601String(),
          }),
        },
      );

      await tester.enterText(
        find.byType(TextField).last,
        'https://callback.local/?code=gap5-code&state=gap5-state',
      );
      await _tapElevatedIcon(tester, Icons.login);

      expect(
        find.textContaining('Outlook is configured in the admin console.'),
        findsWidgets,
      );
      expect(await OutlookAuthService.loadToken(), isNull);
    },
  );

  testWidgets(
    'bidirectional manual sync reports zero mirror writes when no local mirrors exist',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
      );

      await _tapElevatedIcon(tester, Icons.sync);

      expect(
        find.textContaining('\u4efb\u52a1\u955c\u50cf\u65b0\u5efa 0'),
        findsOneWidget,
      );
      expect(find.textContaining('\u51b2\u7a81 0 \u6761'), findsOneWidget);
      expect(harness.reminderService.rebuildCalls, 1);
      final report = await SyncEngine.getLastSyncReport();
      expect(report, isNotNull);
      expect(report!.success, isTrue);
      expect(report.mode, OutlookSyncMode.bidirectional);
      expect(report.mirroredChanges, 0);
    },
  );

  testWidgets(
    'bidirectional manual sync surfaces client Graph server-managed write guard',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
        seedData: true,
      );
      final before = await harness.countTaskMirrorBindings();
      await harness.db.into(harness.db.taskItems).insert(
            TaskItemsCompanion.insert(
              uid: 'gap5-unmirrored-write',
              dtstamp: DateTime.utc(2026, 6, 11, 10),
              summary: 'Gap5 unmirrored write',
              taskListId: Value(harness.activeTaskListId),
            ),
          );

      await _tapElevatedIcon(tester, Icons.sync);

      expect(
        find.textContaining('\u540c\u6b65\u5931\u8d25\uff1aBad state'),
        findsOneWidget,
      );
      expect(find.textContaining('server-managed and read-only'), findsWidgets);
      expect(await harness.countTaskMirrorBindings(), before);
      final report = await SyncEngine.getLastSyncReport();
      expect(report, isNotNull);
      expect(report!.success, isFalse);
      expect(report.errorMessage, contains('server-managed and read-only'));
    },
  );
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

Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.35,
    duration: Duration.zero,
  );
  await tester.pump();
}
