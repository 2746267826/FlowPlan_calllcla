import 'dart:convert';

import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ReportRepository worker G coverage', () {
    test('refreshing a confirmed draft reuses identity and clears confirmation',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final start = DateTime(2026, 6, 10);
      final end = start.add(const Duration(days: 1));

      final first = await repository.upsertReportDraft(
        reportType: ReportType.daily,
        periodStart: start,
        periodEnd: end,
        title: 'Daily report',
        summaryMarkdown: 'Initial draft',
        metrics: const <String, Object?>{'tasks': 1},
        sourceSnapshot: const <String, Object?>{'version': 1},
      );
      await repository.confirmReport(first.id);

      final refreshed = await repository.upsertReportDraft(
        reportType: ReportType.daily,
        periodStart: start,
        periodEnd: end,
        title: 'Daily report refreshed',
        summaryMarkdown: 'Refreshed draft',
        metrics: const <String, Object?>{'tasks': 2},
        sourceSnapshot: const <String, Object?>{'version': 2},
      );

      expect(refreshed.id, first.id);
      expect(refreshed.reportUid, first.reportUid);
      expect(refreshed.status, ReportStatus.draft);
      expect(refreshed.confirmedAt, isNull);
      expect(jsonDecode(refreshed.metricsJson), <String, Object?>{
        'tasks': 2,
      });
      expect(jsonDecode(refreshed.sourceSnapshotJson), <String, Object?>{
        'version': 2,
      });
    });

    test('recent reports are ordered by period and limited', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);

      for (final day in <int>[8, 10, 9]) {
        final start = DateTime(2026, 6, day);
        await repository.upsertReportDraft(
          reportType: ReportType.daily,
          periodStart: start,
          periodEnd: start.add(const Duration(days: 1)),
          title: 'Daily $day',
          summaryMarkdown: 'Draft $day',
          metrics: const <String, Object?>{},
          sourceSnapshot: const <String, Object?>{},
        );
      }

      final recent = await repository.listRecentReports(limit: 2);

      expect(recent.map((report) => report.title), <String>[
        'Daily 10',
        'Daily 9',
      ]);
    });

    test('delivery failure, retry, and sent transitions preserve attempts',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final delivery = await repository.queueDelivery(
        channel: 'webhook',
        target: 'https://hooks.example/report',
        payload: const <String, Object?>{'event': 'report.ready'},
        scheduledAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await repository.markDeliveryFailed(delivery.id, 'first failure');
      var failed = await repository.getDeliveryById(delivery.id);
      expect(failed!.status, PushDeliveryStatus.failed);
      expect(failed.attempts, 0);
      expect(failed.lastError, 'first failure');
      expect(
        (await repository.listPendingDeliveries(channel: 'webhook'))
            .map((item) => item.id),
        <int>[delivery.id],
      );

      await repository.markDeliverySending(delivery.id);
      var sending = await repository.getDeliveryById(delivery.id);
      expect(sending!.status, PushDeliveryStatus.sending);
      expect(sending.attempts, 1);
      expect(sending.lastError, isNull);

      await repository.markDeliveryFailed(delivery.id, StateError('retry me'));
      await repository.markDeliverySending(delivery.id);
      await repository.markDeliverySent(delivery.id);
      final sent = await repository.getDeliveryById(delivery.id);
      expect(sent!.status, PushDeliveryStatus.sent);
      expect(sent.attempts, 2);
      expect(sent.sentAt, isNotNull);
      expect(
          await repository.listPendingDeliveries(channel: 'webhook'), isEmpty);
    });
  });
}
