import 'dart:convert';

import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../test_support/outlook_settings_test_harness.dart';

void main() {
  setUp(OutlookAuthService.debugResetTestOverrides);
  tearDown(OutlookAuthService.debugResetTestOverrides);

  testWidgets('local Outlook setup validates config and auth failure flows',
      (tester) async {
    await pumpLocalOutlookSettings(tester);

    expect(find.text('Outlook 同步设置'), findsOneWidget);
    expect(find.textContaining('尚未连接 Outlook'), findsOneWidget);
    expect(find.text('连接 Outlook 日历'), findsOneWidget);
    expect(find.text('提交授权码'), findsOneWidget);
    expect(_elevatedButton('手动同步 Outlook 日历').evaluate(), isNotEmpty);
    expect(
      tester
          .widget<ElevatedButton>(_elevatedButton('手动同步 Outlook 日历'))
          .onPressed,
      isNull,
    );

    await _tapText(tester, '保存配置');
    expect(find.textContaining('请填写完整的客户端 ID'), findsOneWidget);

    await _tapText(tester, '连接 Outlook 日历');
    expect(find.textContaining('请先保存 OAuth 配置'), findsOneWidget);

    await _tapText(tester, '提交授权码');
    expect(find.textContaining('请输入授权码或完整回调地址'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'deep-test-client');
    await _tapText(tester, '保存配置');
    expect(find.textContaining('OAuth 配置已保存'), findsOneWidget);

    await _tapText(tester, '连接 Outlook 日历');
    expect(find.textContaining('无法打开浏览器'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      'code=abc&state=wrong',
    );
    await _tapText(tester, '提交授权码');
    expect(find.textContaining('认证失败'), findsWidgets);
    expect(find.textContaining('Outlook is configured'), findsWidgets);
  });

  testWidgets(
    'expired token refresh success keeps Outlook connected',
    (tester) async {
      Map<String, String>? postedBody;
      OutlookAuthService.debugSetTestOverrides(
        networkDiagnostics: () async => const OutlookNetworkDiagnostics(
          canResolveMicrosoftHost: true,
          canReachMicrosoftServer: true,
        ),
        tokenPost: (url, {headers, body, encoding}) async {
          postedBody = Map<String, String>.from(body! as Map);
          return _jsonResponse(<String, Object?>{
            'access_token': 'refreshed-access-token',
            'expires_in': 3600,
            'scope': 'Calendars.Read Calendars.ReadWrite offline_access',
          });
        },
      );

      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          accessToken: 'expired-access-token',
          refreshToken: 'stored-refresh-token',
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
          expiresAt: DateTime.utc(2020),
        ),
      );

      expect(postedBody, containsPair('grant_type', 'refresh_token'));
      expect(postedBody, containsPair('refresh_token', 'stored-refresh-token'));
      expect(find.textContaining('Outlook token 刷新成功'), findsOneWidget);
      expect(find.textContaining('已连接 Outlook（读写授权）'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(_elevatedButton('手动同步 Outlook 日历'))
            .onPressed,
        isNotNull,
      );
      expect(
        (await OutlookAuthService.loadToken())!.accessToken,
        'refreshed-access-token',
      );
    },
  );

  testWidgets(
    'invalid refresh grant clears Outlook connection state',
    (tester) async {
      OutlookAuthService.debugSetTestOverrides(
        networkDiagnostics: () async => const OutlookNetworkDiagnostics(
          canResolveMicrosoftHost: true,
          canReachMicrosoftServer: true,
        ),
        tokenPost: (url, {headers, body, encoding}) async {
          return _jsonResponse(
            <String, Object?>{
              'error': 'invalid_grant',
              'error_description': 'Refresh token expired.',
            },
            statusCode: 401,
          );
        },
      );

      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.readOnly,
          accessToken: 'expired-access-token',
          refreshToken: 'revoked-refresh-token',
          expiresAt: DateTime.utc(2020),
        ),
      );

      expect(await OutlookAuthService.loadToken(), isNull);
      expect(find.textContaining('授权码已过期'), findsOneWidget);
      expect(find.textContaining('尚未连接 Outlook'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(_elevatedButton('手动同步 Outlook 日历'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'read-only auth can retry sync, then bidirectional mismatch disables writes',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.readOnly,
          grantedMode: OutlookSyncMode.readOnly,
          includeLastFailure: true,
        ),
      );

      expect(find.textContaining('Outlook 已连接，但最近一次同步失败'), findsOneWidget);
      expect(find.textContaining('当前授权：只读授权'), findsWidgets);
      expect(find.textContaining('最近一次同步失败'), findsWidgets);
      expect(find.textContaining('Graph throttled during deep test'),
          findsOneWidget);

      await _tapText(tester, '重试同步');
      expect(find.textContaining('同步完成：已同步 0 个 Outlook 日历本'), findsOneWidget);
      expect(harness.reminderService.rebuildCalls, 1);

      await _chooseSyncMode(tester, 'bidirectional');
      expect(find.textContaining('当前 Outlook 已连接，但建议重新认证'), findsOneWidget);
      expect(find.textContaining('当前模式与授权不匹配'), findsOneWidget);
      expect(find.textContaining('读写授权'), findsWidgets);
      expect(find.textContaining('现有 Outlook 令牌仍是只读权限'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(_elevatedButton('手动同步 Outlook 日历'))
            .onPressed,
        isNotNull,
      );
      await _tapText(tester, '手动同步 Outlook 日历');
      expect(find.textContaining('当前模式需要读写授权'), findsOneWidget);

      await _tapText(tester, '立即重新进行读写授权');
      expect(find.textContaining('无法打开浏览器'), findsOneWidget);

      await _tapText(tester, '断开 Outlook 连接');
      expect(find.textContaining('已断开 Outlook 连接'), findsOneWidget);
      expect(find.textContaining('尚未连接 Outlook'), findsOneWidget);
    },
  );

  testWidgets(
    'paused mode keeps the connection but disables pull and push actions',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.paused,
          grantedMode: OutlookSyncMode.readOnly,
        ),
        seedData: true,
      );

      expect(find.textContaining('已连接 Outlook（只读授权）'), findsOneWidget);
      expect(find.textContaining('当前模式：暂停同步'), findsOneWidget);
      expect(find.textContaining('当前保持 Outlook 连接'), findsOneWidget);
      expect(
        find.textContaining('暂时停止拉取和推送同步'),
        findsWidgets,
      );
      expect(
        tester
            .widget<ElevatedButton>(_elevatedButton('手动同步 Outlook 日历'))
            .onPressed,
        isNotNull,
      );
      await _tapText(tester, '手动同步 Outlook 日历');
      expect(find.textContaining('当前 Outlook 同步处于暂停状态'), findsOneWidget);

      await _expandSection(tester, '写回边界');
      expect(find.textContaining('不会与 Outlook 发生任何读写'), findsOneWidget);

      await _expandSection(tester, '同步对象');
      expect(find.textContaining('当前共接入 2 个 Outlook 日历本'), findsOneWidget);
      expect(find.textContaining('FlowPlanV2 托管容器，当前已暂停同步'), findsWidgets);
      expect(find.textContaining('已绑定，但当前处于暂停同步'), findsWidgets);
      expect(find.text(outlookMirrorTaskListName), findsWidgets);

      await _chooseSyncMode(tester, 'readOnly');
      expect(find.textContaining('同步模式已更新为“只读”'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(_elevatedButton('手动同步 Outlook 日历'))
            .onPressed,
        isNotNull,
      );
      expect(await harness.countOutlookCalendars(), 2);
      expect(await harness.countTaskListBindings(), 2);
    },
  );

  testWidgets(
    'read-only mirror cleanup action guides the user through reauth',
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
      expect(find.textContaining('有部分镜像索引等待清理'), findsOneWidget);
      expect(find.text('切换为双向同步'), findsOneWidget);

      await _tapText(tester, '切换为双向同步');
      expect(find.textContaining('当前 Outlook 授权仍为只读授权'), findsOneWidget);
      expect(find.textContaining('当前模式与授权不匹配'), findsOneWidget);
      expect(find.text('重新进行读写授权'), findsOneWidget);

      await _tapText(tester, '重新进行读写授权');
      expect(find.textContaining('当前还没有 Outlook 读写授权'), findsOneWidget);
    },
  );

  testWidgets(
    'empty diagnostics and sync objects show safe zero-data states',
    (tester) async {
      await pumpLocalOutlookSettings(tester);

      await _expandSection(tester, '诊断与冲突');
      expect(find.textContaining('暂无冲突候选'), findsOneWidget);
      expect(
        find.textContaining('当前没有需要人工检查的字段级冲突候选'),
        findsOneWidget,
      );

      await _expandSection(tester, '同步对象');
      expect(find.textContaining('当前还没有接入任何 Outlook 日历本'), findsOneWidget);
      expect(find.textContaining('未绑定 Outlook 专属镜像容器'), findsWidgets);
      expect(find.textContaining('当前还没有任务镜像索引'), findsOneWidget);
    },
  );

  testWidgets(
    'bidirectional settings expose diagnostics, objects, and local reset actions',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
          includeLastSuccess: true,
        ),
        seedData: true,
      );

      expect(find.textContaining('已连接 Outlook（读写授权）'), findsOneWidget);
      expect(find.textContaining('最近一次同步已完成'), findsOneWidget);
      expect(find.textContaining('任务镜像：新增 1 / 更新 2 / 删除 1 / 冲突 1'),
          findsOneWidget);

      await _expandSection(tester, '诊断与冲突');
      expect(find.textContaining('字段级冲突候选'), findsWidgets);
      expect(find.textContaining('需要检查'), findsOneWidget);
      expect(find.textContaining('Alpha local task edited'), findsWidgets);
      expect(find.textContaining(outlookRemoteDeletedTask), findsWidgets);
      expect(find.textContaining(outlookRemoteChangedTask), findsWidgets);
      expect(find.textContaining('批量按本地覆盖远端（4）'), findsOneWidget);
      expect(find.textContaining('批量重建已删除镜像（2）'), findsOneWidget);
      expect(find.text('导出 Outlook 同步诊断报告'), findsOneWidget);

      await _tapTextContaining(tester, '批量按本地覆盖远端');
      expect(find.text('批量按本地覆盖远端'), findsWidgets);
      await _tapDialogButton(tester, '取消');

      await _tapText(tester, '采用 Outlook 内容');
      expect(find.text('采用 Outlook 内容'), findsWidgets);
      await _tapDialogButton(tester, '取消');

      expect(await harness.countTaskMirrorBindings(), greaterThan(0));
      await _tapText(tester, '解除镜像绑定');
      expect(find.text('解除镜像绑定'), findsWidgets);
      await _tapDialogButton(tester, '确认');
      expect(find.textContaining('已解除 Outlook 任务镜像绑定'), findsOneWidget);
      expect(await harness.countTaskMirrorBindings(), greaterThan(0));

      await _expandSection(tester, '写回边界');
      expect(find.text('普通 Outlook 日历'), findsOneWidget);
      expect(find.text('始终只读'), findsOneWidget);
      expect(find.textContaining('已满足双向写回前置条件'), findsOneWidget);

      await _expandSection(tester, '同步对象');
      expect(find.textContaining('当前共接入 2 个 Outlook 日历本'), findsOneWidget);
      expect(find.textContaining('已绑定 2 /'), findsOneWidget);
      expect(find.text(outlookExternalCalendarName), findsWidgets);
      expect(find.text(harness.managedCalendarName), findsWidgets);
      expect(find.textContaining('外部 Outlook 日历，仅只读导入'), findsOneWidget);
      expect(find.textContaining('可受控写回'), findsWidgets);
      expect(find.text(outlookMirrorTaskListName), findsWidgets);
      expect(find.text(outlookUnboundTaskListName), findsWidgets);

      expect(await harness.countVisibleOutlookCalendars(), 2);
      await _tapText(tester, '隐藏');
      expect(await harness.countVisibleOutlookCalendars(), 1);
      expect(find.textContaining('已在 FlowPlanV2 中隐藏'), findsOneWidget);

      expect(await harness.countTaskListBindings(), 2);
      await _tapTileAction(tester, outlookMovedTaskListName, '解除绑定');
      expect(find.text('解除 Outlook 绑定'), findsOneWidget);
      await _tapDialogButton(tester, '解除');
      expect(await harness.countTaskListBindings(), 1);
      expect(find.text('解除 Outlook 绑定'), findsNothing);
      expect(find.text('绑定镜像'), findsWidgets);

      await _tapTileAction(tester, outlookMovedTaskListName, '绑定镜像');
      await _waitForTextContaining(tester, '绑定 Outlook 容器失败');
      expect(
          find.textContaining('server-managed and read-only'), findsOneWidget);

      await _tapText(tester, '重置同步状态');
      expect(find.textContaining('同步状态已重置'), findsOneWidget);
      expect(find.textContaining('当前还没有最近同步结果'), findsOneWidget);

      expect(await harness.countOutlookCalendars(), 2);
      expect(await harness.countOutlookEvents(), 2);
      await _tapText(tester, '完全重置已同步的 Outlook 日历本');
      expect(find.text('完全重置 Outlook 日历本'), findsOneWidget);
      await _tapDialogButton(tester, '确认重置');
      expect(find.textContaining('已重置 Outlook 日历本'), findsOneWidget);
      expect(await harness.countOutlookCalendars(), 0);
      expect(await harness.countOutlookEvents(), 0);
    },
  );

  testWidgets(
    'diagnostics export handles cancel and writes selected markdown report',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
          includeLastSuccess: true,
        ),
        seedData: true,
      );

      await _expandSection(tester, '诊断与冲突');
      await _tapText(tester, '导出 Outlook 同步诊断报告');
      expect(harness.filePicker.saveRequests, hasLength(1));
      expect(
        harness.filePicker.saveRequests.single.allowedExtensions,
        <String>['md', 'txt'],
      );
      expect(find.textContaining('已取消导出 Outlook 同步诊断报告'), findsOneWidget);

      const exportPath = 'C:/fake/outlook-diagnostics.md';
      harness.filePicker.queueSavePath(exportPath);

      await _tapText(tester, '导出 Outlook 同步诊断报告');
      await _waitForTextContaining(tester, '已导出 Outlook 同步诊断报告');
      expect(harness.filePicker.saveRequests, hasLength(2));
      expect(harness.diagnosticsWrites, hasLength(1));
      expect(harness.diagnosticsWrites.single.outputPath, exportPath);

      final report = harness.diagnosticsWrites.single.report;
      expect(report, contains('# FlowPlanV2 Outlook 同步诊断报告'));
      expect(report, contains(outlookExternalCalendarName));
      expect(report, contains('任务镜像绑定'));
    },
  );

  testWidgets(
    'diagnostics export reports writer failures without touching real files',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
          includeLastSuccess: true,
        ),
        seedData: true,
        diagnosticsWriteError: StateError('fake-writer-failed'),
      );

      harness.filePicker.queueSavePath('C:/fake/failing-diagnostics.md');
      await _expandSection(tester, '诊断与冲突');
      await _tapText(tester, '导出 Outlook 同步诊断报告');

      await _waitForTextContaining(tester, '导出 Outlook 同步诊断报告失败');
      expect(find.textContaining('fake-writer-failed'), findsOneWidget);
      expect(harness.diagnosticsWrites, isEmpty);
    },
  );

  testWidgets(
    'bidirectional mirror cleanup removes stale local indexes',
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

      await _expandSection(tester, '同步对象');
      expect(find.textContaining('有部分镜像索引等待清理'), findsOneWidget);
      await _tapText(tester, '立即清理失效镜像');

      await _waitForTextContaining(tester, '镜像清理完成');
      expect(find.textContaining('已删除 3 条失效 Outlook 任务镜像'), findsOneWidget);
      expect(await harness.countTaskMirrorBindings(), before - 3);
    },
  );

  testWidgets(
    'hidden Outlook calendar can be shown and reset cancellation preserves data',
    (tester) async {
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
        seedData: true,
        hideExternalCalendar: true,
      );

      await _expandSection(tester, '同步对象');
      expect(await harness.countVisibleOutlookCalendars(), 1);
      expect(find.textContaining('在 FlowPlanV2 中：已隐藏'), findsOneWidget);

      await _tapTileAction(tester, outlookExternalCalendarName, '显示');
      expect(
          await harness.isCalendarVisible(harness.externalCalendarId), isTrue);
      expect(find.textContaining('已在 FlowPlanV2 中显示'), findsOneWidget);

      await _tapText(tester, '完全重置已同步的 Outlook 日历本');
      expect(find.text('完全重置 Outlook 日历本'), findsOneWidget);
      await _tapDialogButton(tester, '取消');
      expect(find.text('完全重置 Outlook 日历本'), findsNothing);
      expect(await harness.countOutlookCalendars(), 2);
      expect(await harness.countOutlookEvents(), 2);
    },
  );
}

Finder _elevatedButton(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(ElevatedButton),
  );
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  final button = _buttonWithText(text);
  final target = button?.first ?? finder;
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

Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.35,
    duration: Duration.zero,
  );
  await tester.pump();
}

Future<void> _tapDialogButton(WidgetTester tester, String text) async {
  final button = find.widgetWithText(TextButton, text);
  final filledButton = find.widgetWithText(FilledButton, text);
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button.last);
  } else {
    await tester.tap(filledButton.last);
  }
  await pumpOutlookSettingFrames(tester);
}

Future<void> _waitForTextContaining(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (find.textContaining(text).evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.textContaining(text), findsOneWidget);
}

Future<void> _expandSection(WidgetTester tester, String title) async {
  final finder = find.text(title).first;
  await tester.ensureVisible(finder);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(finder);
  await pumpOutlookSettingFrames(tester);
}

Future<void> _chooseSyncMode(WidgetTester tester, String valueFragment) async {
  final dropdown = find.byType(DropdownButtonFormField<OutlookSyncMode>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await pumpOutlookSettingFrames(tester, frames: 4);
  final menuItem = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownMenuItem<OutlookSyncMode> &&
        widget.value.toString().contains(valueFragment),
  );
  expect(menuItem, findsWidgets);
  final itemText = find
      .descendant(
        of: menuItem.last,
        matching: find.byType(Text),
      )
      .hitTestable();
  expect(itemText, findsWidgets);
  await tester.tap(itemText.last);
  await pumpOutlookSettingFrames(tester);
}

http.Response _jsonResponse(
  Map<String, Object?> body, {
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const <String, String>{
      'content-type': 'application/json',
    },
  );
}
