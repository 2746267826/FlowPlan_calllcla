import 'dart:convert';

import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/outlook_settings_test_harness.dart';
import '../test_support/test_database.dart';

void main() {
  setUp(OutlookAuthService.debugResetTestOverrides);
  tearDown(OutlookAuthService.debugResetTestOverrides);

  testWidgets(
    'authorization submit reports server-managed exchange failures',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: <String, Object>{
          'outlook_client_id': 'deep-test-client',
          'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
          'outlook_pending_auth_session': jsonEncode(<String, Object?>{
            'client_id': 'deep-test-client',
            'code_verifier': 'gap4-verifier',
            'state': 'gap4-state',
            'requested_mode': OutlookSyncMode.bidirectional.storageValue,
            'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
          }),
        },
      );

      await tester.enterText(
        find.byType(TextField).last,
        'https://callback.local/?code=gap4-code&state=gap4-state',
      );
      await _tapText(tester, '提交授权码');

      expect(
        find.textContaining('Outlook is configured in the admin console.'),
        findsWidgets,
      );
      final token = await OutlookAuthService.loadToken();
      expect(token, isNull);
    },
  );

  testWidgets(
    'authorization submit validates empty callback input before exchange',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: <String, Object>{
          'outlook_client_id': 'deep-test-client',
          'outlook_pending_auth_session': jsonEncode(<String, Object?>{
            'client_id': 'deep-test-client',
            'code_verifier': 'gap4-verifier',
            'state': 'expected-state',
            'requested_mode': OutlookSyncMode.readOnly.storageValue,
            'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
          }),
        },
      );

      await _tapText(tester, '提交授权码');

      expect(find.textContaining('请输入授权码或完整回调地址'), findsOneWidget);
    },
  );

  testWidgets(
    'mirror cleanup stops at missing OAuth config after permission checks',
    (tester) async {
      final preferences = outlookAuthPreferences(
        syncMode: OutlookSyncMode.bidirectional,
        grantedMode: OutlookSyncMode.bidirectional,
        scope: 'Calendars.Read Calendars.ReadWrite offline_access',
      )..remove('outlook_client_id');
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: preferences,
        seedData: true,
      );
      final before = await harness.countTaskMirrorBindings();

      await _expandSection(tester, '同步对象');
      await _tapText(tester, '立即清理失效镜像');

      expect(find.textContaining('请先配置 OAuth 凭据'), findsOneWidget);
      expect(await harness.countTaskMirrorBindings(), before);
    },
  );

  testWidgets(
    'batch mirror actions report runner exceptions after confirmation',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
        extraOverrides: <Override>[
          outlookFieldConflictSummariesProvider.overrideWith(
            (ref) async => <OutlookFieldConflictSummary>[
              const OutlookFieldConflictSummary(
                taskId: 77,
                taskSummary: 'Gap4 pending push',
                taskListName: 'Gap4 List',
                remoteCalendarName: 'FlowPlanV2 Gap4',
                conflictState: OutlookTaskMirrorConflictState.pendingLocalPush,
                changedFields: <String>['标题'],
                detail: 'gap4 detail',
                canPushLocal: true,
                canPullRemote: false,
                canRecreateRemote: false,
                canDetachMirror: false,
              ),
            ],
          ),
          outlookTaskMirrorRepositoryProvider.overrideWithValue(
            _BatchThrowingTaskMirrorRepository(db),
          ),
        ],
      );

      await _expandSection(tester, '诊断与冲突');
      await _tapTextContaining(tester, '批量按本地覆盖远端');
      await _tapDialogButton(tester, '确认');

      expect(find.textContaining('批量处理失败'), findsOneWidget);
      expect(find.textContaining('gap4-batch-repo-down'), findsOneWidget);
    },
  );
}

class _BatchThrowingTaskMirrorRepository extends OutlookTaskMirrorRepository {
  _BatchThrowingTaskMirrorRepository(super.db);

  @override
  Future<Map<int, OutlookTaskMirrorBinding>> loadTaskMirrorBindings() {
    throw StateError('gap4-batch-repo-down');
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final button = _buttonWithText(text);
  final target = button?.first ?? find.text(text).first;
  await _bringIntoView(tester, target);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(target);
  await pumpOutlookSettingFrames(tester);
}

Future<void> _tapTextContaining(WidgetTester tester, String text) async {
  final finder = find.textContaining(text).first;
  final button = find.ancestor(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is TextButton ||
          widget is ElevatedButton ||
          widget is FilledButton ||
          widget is OutlinedButton,
    ),
  );
  final target = button.evaluate().isNotEmpty ? button.first : finder;
  await _bringIntoView(tester, target);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(target);
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

Future<void> _tapDialogButton(WidgetTester tester, String text) async {
  final textButton = find.widgetWithText(TextButton, text);
  final filledButton = find.widgetWithText(FilledButton, text);
  if (textButton.evaluate().isNotEmpty) {
    await tester.tap(textButton.last);
  } else {
    await tester.tap(filledButton.last);
  }
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

Future<void> _expandSection(WidgetTester tester, String title) async {
  final finder = find.text(title).first;
  await tester.ensureVisible(finder);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(finder);
  await pumpOutlookSettingFrames(tester);
}
