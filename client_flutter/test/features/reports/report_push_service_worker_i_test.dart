import 'dart:convert';

import 'package:flowplanv2/core/platform/desktop_shell_service.dart';
import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flowplanv2/features/reports/services/report_push_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../test_support/test_database.dart';

void main() {
  late UrlLauncherPlatform originalLauncher;

  setUp(() {
    originalLauncher = UrlLauncherPlatform.instance;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
  });

  group('ReportPushService additional delivery paths', () {
    test('normalizes decoded map-like delivery payloads', () {
      final payload = ReportPushService.decodePayloadForTesting(
        <Object?, Object?>{
          'title': 'Fallback title',
          'body': 'Fallback body',
        },
      );

      expect(payload, <String, Object?>{
        'title': 'Fallback title',
        'body': 'Fallback body',
      });
    });

    test('queues telegram report without configured target or detail link',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
      );
      final report = await _createReport(repository);

      final delivery = await service.queueTelegramReport(report);
      final payload = jsonDecode(delivery.payloadJson) as Map<String, dynamic>;

      expect(delivery.target, isNull);
      expect(payload['detail_url'], isNull);
      expect(payload['text'], contains('Daily Focus Report'));
      expect(payload['text'], isNot(contains('/reports/')));
    });

    test('falls back to configured webhook target and records HTTP exception',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final requests = <http.Request>[];
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
        httpClient: MockClient((request) async {
          requests.add(request);
          throw http.ClientException('network down', request.url);
        }),
      );
      await db.setSetting(
        ReportPushService.reportWebhookUrlKey,
        ' https://hooks.example/fallback ',
      );
      final report = await _createReport(repository);
      final delivery = await repository.queueDelivery(
        reportId: report.id,
        channel: 'webhook',
        payload: const <String, Object?>{'event': 'fallback'},
      );

      final result = await service.sendPendingWebhooks();

      expect(result.sent, 0);
      expect(result.failed, 1);
      expect(requests.single.url.toString(), 'https://hooks.example/fallback');
      final row = await repository.getDeliveryById(delivery.id);
      expect(row!.status, PushDeliveryStatus.failed);
      expect(row.attempts, 1);
      expect(row.lastError, contains('network down'));
    });

    test('fails telegram delivery when configured chat id is blank', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      await db.setSetting(ReportPushService.telegramBotTokenKey, 'token');
      await db.setSetting(ReportPushService.telegramChatIdKey, '   ');
      final delivery = await repository.queueDelivery(
        channel: 'telegram',
        payload: const <String, Object?>{'text': 'no chat'},
      );

      final result = await service.sendPendingTelegram();

      expect(result.sent, 0);
      expect(result.failed, 1);
      final row = await repository.getDeliveryById(delivery.id);
      expect(row!.status, PushDeliveryStatus.failed);
      expect(row.attempts, 1);
      expect(row.lastError, contains('Telegram chat id is not configured'));
    });

    test('email delivery opens mailto target from settings and marks sent',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final launcher = _FakeUrlLauncher(launchResult: true);
      UrlLauncherPlatform.instance = launcher;
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
      );
      await db.setSetting(
        ReportPushService.reportEmailTargetKey,
        ' ops@example.com ',
      );
      final report = await _createReport(repository);
      final delivery = await repository.queueDelivery(
        reportId: report.id,
        channel: 'email',
        payload: const <String, Object?>{
          'subject': 'Daily subject',
          'body_markdown': '# Body\n\nDone',
        },
      );

      final result = await service.sendPendingEmails();

      expect(result.sent, 1);
      expect(result.failed, 0);
      expect(launcher.launchedUrls, hasLength(1));
      final uri = Uri.parse(launcher.launchedUrls.single);
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'ops@example.com');
      expect(uri.queryParameters['subject'], 'Daily subject');
      expect(uri.queryParameters['body'], '# Body\n\nDone');
      final row = await repository.getDeliveryById(delivery.id);
      expect(row!.status, PushDeliveryStatus.sent);
      expect(row.sentAt, isNotNull);
    });

    test('email delivery records missing target and launch failures', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      UrlLauncherPlatform.instance = _FakeUrlLauncher(launchResult: false);
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
      );
      final missingTarget = await repository.queueDelivery(
        channel: 'email',
        payload: const <String, Object?>{'subject': 'missing'},
      );
      final launchFailure = await repository.queueDelivery(
        channel: 'email',
        target: 'person@example.com',
        payload: const <String, Object?>{'subject': 'cannot open'},
      );

      final result = await service.sendPendingEmails(limit: 10);

      expect(result.sent, 0);
      expect(result.failed, 2);
      final missingRow = await repository.getDeliveryById(missingTarget.id);
      final launchRow = await repository.getDeliveryById(launchFailure.id);
      expect(missingRow!.lastError, contains('Email target is not configured'));
      expect(launchRow!.lastError, contains('Could not open email client'));
    });

    test('system notification tolerates non-object payloads with defaults',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final shell = _RecordingShellService();
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
        shellService: shell,
      );
      final delivery = await repository.queueDelivery(
        channel: 'system_notification',
        payload: const <String, Object?>{'placeholder': 'will be replaced'},
      );
      await db.customStatement(
        'UPDATE report_push_deliveries SET payload_json = ? WHERE id = ?',
        <Object?>['[]', delivery.id],
      );

      final result = await service.sendPendingSystemNotifications();

      expect(result.sent, 1);
      expect(result.failed, 0);
      expect(shell.reminders.single.title, isNotEmpty);
      expect(shell.reminders.single.body, '');
      expect(
        (await repository.getDeliveryById(delivery.id))!.status,
        PushDeliveryStatus.sent,
      );
    });
  });
}

Future<ReportDocument> _createReport(ReportRepository repository) {
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
    ].join('\n'),
    metrics: const <String, Object?>{'completed_task_count': 1},
    sourceSnapshot: const <String, Object?>{'source': 'test'},
  );
}

class _FakeUrlLauncher extends UrlLauncherPlatform {
  _FakeUrlLauncher({required this.launchResult});

  final bool launchResult;
  final launchedUrls = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return launchResult;
  }
}

class _RecordingShellService extends DesktopShellService {
  final reminders = <({String title, String body})>[];

  @override
  Future<void> showReminder({
    required String title,
    required String body,
  }) async {
    reminders.add((title: title, body: body));
  }
}
