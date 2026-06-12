import 'dart:convert';

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

  group('ReportPushService worker G coverage', () {
    test('telegram detail URLs trim repeated trailing slashes and cap excerpt',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
      );
      await db.setSetting(
        ReportPushService.reportDetailBaseUrlKey,
        ' https://flowplan.test/app/// ',
      );
      final report = await _createReport(
        repository,
        summaryMarkdown: [
          '# Daily Focus Report',
          '',
          for (var i = 1; i <= 12; i++) 'Line $i',
        ].join('\n'),
      );

      final delivery = await service.queueTelegramReport(
        report,
        chatId: 'chat-1',
      );
      final payload = jsonDecode(delivery.payloadJson) as Map<String, dynamic>;

      expect(
        payload['detail_url'],
        'https://flowplan.test/app/reports/${report.reportUid}',
      );
      expect(payload['text'], contains('Line 9'));
      expect(payload['text'], isNot(contains('Line 10')));
      expect(
        payload['text'],
        contains('https://flowplan.test/app/reports/${report.reportUid}'),
      );
    });

    test('email sending uses queued target before settings target', () async {
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
        'settings@example.com',
      );
      final delivery = await repository.queueDelivery(
        channel: 'email',
        target: 'queued@example.com',
        payload: const <String, Object?>{
          'subject': 'Daily report / review',
          'body_markdown': '# Body\n\nLine with spaces & symbols',
        },
      );

      final result = await service.sendPendingEmails();

      expect(result.sent, 1);
      expect(result.failed, 0);
      final uri = Uri.parse(launcher.launchedUrls.single);
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'queued@example.com');
      expect(uri.queryParameters['subject'], 'Daily report / review');
      expect(
        uri.queryParameters['body'],
        '# Body\n\nLine with spaces & symbols',
      );
      expect(
        (await repository.getDeliveryById(delivery.id))!.status,
        PushDeliveryStatus.sent,
      );
    });

    test('webhook sender records invalid URLs and continues with next delivery',
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
          return http.Response('accepted', 202);
        }),
      );
      final invalid = await repository.queueDelivery(
        channel: 'webhook',
        target: 'http://[invalid-host',
        payload: const <String, Object?>{'event': 'invalid'},
        scheduledAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      final valid = await repository.queueDelivery(
        channel: 'webhook',
        target: 'https://hooks.example/report',
        payload: const <String, Object?>{'event': 'valid'},
        scheduledAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final result = await service.sendPendingWebhooks(limit: 10);

      expect(result.sent, 1);
      expect(result.failed, 1);
      expect(requests.single.url.toString(), 'https://hooks.example/report');
      final invalidRow = await repository.getDeliveryById(invalid.id);
      final validRow = await repository.getDeliveryById(valid.id);
      expect(invalidRow!.status, PushDeliveryStatus.failed);
      expect(invalidRow.attempts, 1);
      expect(invalidRow.lastError, contains('FormatException'));
      expect(validRow!.status, PushDeliveryStatus.sent);
    });
  });
}

Future<ReportDocument> _createReport(
  ReportRepository repository, {
  required String summaryMarkdown,
}) {
  final start = DateTime(2026, 6, 10);
  return repository.upsertReportDraft(
    reportType: ReportType.daily,
    periodStart: start,
    periodEnd: start.add(const Duration(days: 1)),
    title: 'Daily Focus Report',
    summaryMarkdown: summaryMarkdown,
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
