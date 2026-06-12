import 'dart:convert';

import 'package:flowplanv2/core/platform/desktop_shell_service.dart';
import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flowplanv2/features/reports/services/report_push_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

class _FakeShellService extends DesktopShellService {
  _FakeShellService({this.throwOnShow = false});

  final bool throwOnShow;
  final reminders = <({String title, String body})>[];

  @override
  Future<void> showReminder({
    required String title,
    required String body,
  }) async {
    if (throwOnShow) {
      throw StateError('native shell unavailable');
    }
    reminders.add((title: title, body: body));
  }
}

void main() {
  Future<ReportDocument> createReport(ReportRepository repository) {
    final start = DateTime(2026, 6, 10);
    return repository.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: start,
      periodEnd: start.add(const Duration(days: 1)),
      title: 'Daily Focus Report',
      summaryMarkdown: [
        '# Daily Focus Report',
        '',
        'Completed task A',
        'Tracked 45 minutes',
        'Ignored blank lines',
      ].join('\n'),
      metrics: const <String, Object?>{'completed_task_count': 1},
      sourceSnapshot: const <String, Object?>{'source': 'test'},
    );
  }

  Map<String, dynamic> payloadOf(ReportPushDelivery delivery) =>
      jsonDecode(delivery.payloadJson) as Map<String, dynamic>;

  group('ReportPushService queueing', () {
    test('queues telegram delivery with configured target and detail link',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
      );
      await db.setSetting(
        ReportPushService.telegramChatIdKey,
        ' chat-from-settings ',
      );
      await db.setSetting(
        ReportPushService.reportDetailBaseUrlKey,
        'https://flowplan.test/app/',
      );
      final report = await createReport(repository);

      final delivery = await service.queueTelegramReport(report);
      final payload = payloadOf(delivery);

      expect(delivery.channel, 'telegram');
      expect(delivery.target, ' chat-from-settings ');
      expect(payload['report_uid'], report.reportUid);
      expect(payload['detail_url'], 'https://flowplan.test/app/reports/${report.reportUid}');
      expect(payload['text'], contains('Daily Focus Report'));
      expect(payload['text'], contains('Completed task A'));
      expect(payload['text'], contains('https://flowplan.test/app/reports/${report.reportUid}'));
    });

    test('queues system webhook and email payloads with expected fields',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
      );
      await db.setSetting(
        ReportPushService.reportWebhookUrlKey,
        'https://hooks.example/report',
      );
      await db.setSetting(
        ReportPushService.reportEmailTargetKey,
        'ops@example.com',
      );
      final report = await createReport(repository);

      final notification = await service.queueSystemNotification(report);
      final webhook = await service.queueWebhookReport(report);
      final email = await service.queueEmailReport(report);

      expect(notification.channel, 'system_notification');
      expect(payloadOf(notification)['title'], report.title);
      expect(payloadOf(notification)['body'], contains('Completed task A'));
      expect(webhook.target, 'https://hooks.example/report');
      expect(payloadOf(webhook)['summary_markdown'], report.summaryMarkdown);
      expect(email.target, 'ops@example.com');
      expect(payloadOf(email)['subject'], report.title);
      expect(payloadOf(email)['body_markdown'], report.summaryMarkdown);
    });
  });

  group('ReportPushService sending', () {
    test('sends pending telegram deliveries and marks HTTP failures', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final requests = <http.Request>[];
      var requestCount = 0;
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
        httpClient: MockClient((request) async {
          requests.add(request);
          requestCount += 1;
          if (requestCount == 1) {
            return http.Response('{"ok":true}', 200);
          }
          return http.Response('bad token', 401);
        }),
      );
      await db.setSetting(ReportPushService.telegramBotTokenKey, ' token ');
      await db.setSetting(ReportPushService.telegramChatIdKey, 'fallback-chat');
      final report = await createReport(repository);
      final sent = await service.queueTelegramReport(report, chatId: 'chat-1');
      final failed = await repository.queueDelivery(
        reportId: report.id,
        channel: 'telegram',
        target: null,
        payload: const <String, Object?>{'text': 'fallback target'},
      );

      final result = await service.sendPendingTelegram(limit: 10);

      expect(result.sent, 1);
      expect(result.failed, 1);
      expect(requests, hasLength(2));
      expect(requests.first.url.host, 'api.telegram.org');
      expect(jsonDecode(requests.first.body), <String, Object?>{
        'chat_id': 'chat-1',
        'text': payloadOf(sent)['text'],
        'disable_web_page_preview': true,
      });
      expect(jsonDecode(requests.last.body)['chat_id'], 'fallback-chat');

      final sentRow = await repository.getDeliveryById(sent.id);
      final failedRow = await repository.getDeliveryById(failed.id);
      expect(sentRow!.status, PushDeliveryStatus.sent);
      expect(sentRow.attempts, 1);
      expect(sentRow.sentAt, isNotNull);
      expect(failedRow!.status, PushDeliveryStatus.failed);
      expect(failedRow.attempts, 1);
      expect(failedRow.lastError, contains('Telegram returned 401'));
    });

    test('requires telegram token before marking deliveries sending', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final report = await createReport(repository);
      final delivery = await service.queueTelegramReport(report, chatId: 'chat');

      await expectLater(
        service.sendPendingTelegram(),
        throwsA(isA<StateError>()),
      );

      final unchanged = await repository.getDeliveryById(delivery.id);
      expect(unchanged!.status, PushDeliveryStatus.pending);
      expect(unchanged.attempts, 0);
    });

    test('sends webhooks and records missing target as failed', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final requests = <http.Request>[];
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('accepted', 202);
        }),
      );
      final report = await createReport(repository);
      final sent = await service.queueWebhookReport(
        report,
        webhookUrl: 'https://hooks.example/report',
      );
      final failed = await repository.queueDelivery(
        reportId: report.id,
        channel: 'webhook',
        payload: const <String, Object?>{'event': 'missing-target'},
      );

      final result = await service.sendPendingWebhooks(limit: 10);

      expect(result.sent, 1);
      expect(result.failed, 1);
      expect(requests.single.url.toString(), 'https://hooks.example/report');
      expect(requests.single.body, sent.payloadJson);
      expect((await repository.getDeliveryById(sent.id))!.status,
          PushDeliveryStatus.sent);
      final failedRow = await repository.getDeliveryById(failed.id);
      expect(failedRow!.status, PushDeliveryStatus.failed);
      expect(failedRow.lastError, contains('Webhook url is not configured'));
    });

    test('sends system notifications through shell service and records failures',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final shell = _FakeShellService();
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
        shellService: shell,
      );
      final report = await createReport(repository);
      final sent = await service.queueSystemNotification(report);

      final result = await service.sendPendingSystemNotifications();

      expect(result.sent, 1);
      expect(result.failed, 0);
      expect(shell.reminders.single.title, report.title);
      expect(shell.reminders.single.body, contains('Completed task A'));
      expect((await repository.getDeliveryById(sent.id))!.status,
          PushDeliveryStatus.sent);

      final failingService = ReportPushService(
        database: db,
        reportRepository: repository,
        shellService: _FakeShellService(throwOnShow: true),
      );
      final failed = await service.queueSystemNotification(report);
      final failedResult =
          await failingService.sendPendingSystemNotifications();
      expect(failedResult.sent, 0);
      expect(failedResult.failed, 1);
      final failedRow = await repository.getDeliveryById(failed.id);
      expect(failedRow!.status, PushDeliveryStatus.failed);
      expect(failedRow.lastError, contains('native shell unavailable'));
    });
  });
}
