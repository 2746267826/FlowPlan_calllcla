import 'dart:convert';

import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ReportRepository diary and delivery details', () {
    test('upserts diary drafts with linked data, weather, and location intact',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final day = DateTime(2026, 6, 10, 23, 30);

      final first = await repository.upsertDiaryDraft(
        entryDate: day,
        title: 'Diary draft',
        bodyMarkdown: '# Diary\n\nInitial markdown',
        sourceReportId: 7,
        linkedTaskIds: const <int>[1, 2, 3],
        linkedFileIds: const <String>['file-a', 'file-b'],
        location: const <String, Object?>{
          'name': 'Shanghai',
          'lat': 31.2304,
        },
        weather: const <String, Object?>{
          'condition': 'cloudy',
          'temperature_c': 26,
        },
      );

      expect(first.entryDate, DateTime(2026, 6, 10));
      expect(first.status, ReportStatus.draft);
      expect(first.sourceReportId, 7);
      expect(jsonDecode(first.linkedTaskIdsJson), <Object?>[1, 2, 3]);
      expect(jsonDecode(first.linkedFileIdsJson), <Object?>[
        'file-a',
        'file-b',
      ]);
      expect(jsonDecode(first.locationJson), <String, Object?>{
        'name': 'Shanghai',
        'lat': 31.2304,
      });
      expect(jsonDecode(first.weatherJson), <String, Object?>{
        'condition': 'cloudy',
        'temperature_c': 26,
      });

      await repository.confirmDiary(first.id);
      final confirmed = await repository.getDiaryById(first.id);
      expect(confirmed!.status, ReportStatus.confirmed);
      expect(confirmed.confirmedAt, isNotNull);

      final refreshed = await repository.upsertDiaryDraft(
        entryDate: DateTime(2026, 6, 10, 1),
        title: 'Diary refreshed',
        bodyMarkdown: '# Diary\n\nRefreshed markdown',
        linkedTaskIds: const <int>[3],
        linkedFileIds: const <String>['file-c'],
        location: const <String, Object?>{'name': 'Office'},
        weather: const <String, Object?>{'condition': 'sunny'},
      );

      expect(refreshed.id, first.id);
      expect(refreshed.status, ReportStatus.draft);
      expect(refreshed.confirmedAt, isNull);
      expect(refreshed.sourceReportId, isNull);
      expect(refreshed.title, 'Diary refreshed');
      expect(jsonDecode(refreshed.linkedTaskIdsJson), <Object?>[3]);
      expect(jsonDecode(refreshed.linkedFileIdsJson), <Object?>['file-c']);
      expect(jsonDecode(refreshed.locationJson), <String, Object?>{
        'name': 'Office',
      });
      expect(jsonDecode(refreshed.weatherJson), <String, Object?>{
        'condition': 'sunny',
      });

      final lookup = await repository.getDiaryForDate(
        DateTime(2026, 6, 10, 18),
      );
      expect(lookup!.id, first.id);
      expect(await repository.getDiaryById(404), isNull);
    });

    test('confirms reports and returns null for missing report lookups',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final start = DateTime(2026, 6, 10);
      final report = await repository.upsertReportDraft(
        reportType: ReportType.weekly,
        periodStart: start,
        periodEnd: start.add(const Duration(days: 7)),
        title: 'Weekly report',
        summaryMarkdown: '# Weekly report',
        metrics: const <String, Object?>{'task_work_minutes': 90},
        sourceSnapshot: const <String, Object?>{'source': 'unit-test'},
      );

      await repository.confirmReport(report.id);

      final confirmed = await repository.getReportById(report.id);
      expect(confirmed!.status, ReportStatus.confirmed);
      expect(confirmed.confirmedAt, isNotNull);
      expect(await repository.getReportById(404), isNull);
      expect(await repository.getReportByUid('missing'), isNull);
      expect(
        await repository.getReportForPeriod(
          reportType: ReportType.daily,
          periodStart: start,
          periodEnd: start.add(const Duration(days: 1)),
        ),
        isNull,
      );
    });

    test('lists pending and failed deliveries by schedule, channel, and limit',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final now = DateTime.now();

      final later = await repository.queueDelivery(
        channel: 'telegram',
        payload: const <String, Object?>{'text': 'future'},
        scheduledAt: now.add(const Duration(days: 1)),
      );
      final first = await repository.queueDelivery(
        channel: 'telegram',
        payload: const <String, Object?>{'text': 'first'},
        scheduledAt: now.subtract(const Duration(minutes: 20)),
      );
      final second = await repository.queueDelivery(
        channel: 'telegram',
        payload: const <String, Object?>{'text': 'second'},
        scheduledAt: now.subtract(const Duration(minutes: 10)),
      );
      final webhook = await repository.queueDelivery(
        channel: 'webhook',
        payload: const <String, Object?>{'event': 'ready'},
        scheduledAt: now.subtract(const Duration(minutes: 5)),
      );

      await repository.markDeliveryFailed(second.id, StateError('retry me'));
      await repository.markDeliverySending(first.id);

      final allDue = await repository.listPendingDeliveries(limit: 10);
      expect(allDue.map((item) => item.id), <int>[second.id, webhook.id]);
      expect(allDue.first.status, PushDeliveryStatus.failed);
      expect(allDue.first.lastError, contains('retry me'));

      final telegramDue = await repository.listPendingDeliveries(
        channel: 'telegram',
        limit: 1,
      );
      expect(telegramDue.map((item) => item.id), <int>[second.id]);
      expect(
        (await repository.getDeliveryById(first.id))!.status,
        PushDeliveryStatus.sending,
      );
      expect(
        (await repository.getDeliveryById(later.id))!.status,
        PushDeliveryStatus.pending,
      );
      expect(await repository.getDeliveryById(404), isNull);
    });
  });
}
