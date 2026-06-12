import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flowplanv2/features/reports/services/report_push_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('static report value containers remain constructible for coverage', () {
    expect(const ReportType(), isA<ReportType>());
    expect(const ReportStatus(), isA<ReportStatus>());
    expect(const PushDeliveryStatus(), isA<PushDeliveryStatus>());
    expect(ReportType.weekly, 'weekly');
    expect(ReportStatus.confirmed, 'confirmed');
    expect(PushDeliveryStatus.failed, 'failed');
  });

  test('confirmReport records a sync update payload for an existing report',
      () async {
    final harness = _createHarness();
    addTearDown(harness.db.close);
    final repository = harness.repository;

    final report = await repository.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: DateTime.utc(2026, 6, 11),
      periodEnd: DateTime.utc(2026, 6, 12),
      title: 'Daily report',
      summaryMarkdown: 'Body',
      metrics: const <String, Object?>{'done': 1},
      sourceSnapshot: const <String, Object?>{'source': 'gap7'},
    );

    await repository.confirmReport(report.id);

    final confirmed = await repository.getReportById(report.id);
    final mutations = await harness.mutationStore.listPending(limit: 10);
    final reportMutations = mutations
        .where((mutation) =>
            mutation.objectType == SyncObjectType.reportDocument.key)
        .toList();
    final updatePayload =
        jsonDecode(reportMutations.last.payloadJson) as Map<String, dynamic>;

    expect(confirmed!.status, ReportStatus.confirmed);
    expect(confirmed.confirmedAt, isNotNull);
    expect(reportMutations.map((mutation) => mutation.action), <Object>[
      OfflineMutationAction.create,
      OfflineMutationAction.update,
    ]);
    expect(updatePayload, containsPair('status', ReportStatus.confirmed));
    expect(updatePayload, containsPair('reportUid', report.reportUid));
  });

  test(
      'upsertReportDraft falls back to the last inserted row when uid lookup misses',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = _UidMissReportRepository(db);

    final report = await repository.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: DateTime.utc(2026, 6, 11),
      periodEnd: DateTime.utc(2026, 6, 12),
      title: 'Fallback draft',
      summaryMarkdown: 'Inserted report',
      metrics: const <String, Object?>{'fallback': true},
      sourceSnapshot: const <String, Object?>{'source': 'uid-miss'},
    );

    expect(report.title, 'Fallback draft');
    expect(report.reportUid, 'report:daily:2026-06-11');
    expect(await ReportRepository(db).getReportById(report.id), isNotNull);
  });

  test('sendPendingWebhooks marks non-success responses failed', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = ReportRepository(db);
    final service = ReportPushService(
      database: db,
      reportRepository: repository,
      httpClient: MockClient(
        (_) async => http.Response('server exploded', 503),
      ),
    );
    final report = await repository.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: DateTime.utc(2026, 6, 11),
      periodEnd: DateTime.utc(2026, 6, 12),
      title: 'Webhook report',
      summaryMarkdown: 'Body',
      metrics: const <String, Object?>{},
      sourceSnapshot: const <String, Object?>{},
    );
    final delivery = await service.queueWebhookReport(
      report,
      webhookUrl: 'https://hooks.example/fail',
    );

    final result = await service.sendPendingWebhooks();

    expect(result.sent, 0);
    expect(result.failed, 1);
    final failed = await repository.getDeliveryById(delivery.id);
    expect(failed!.status, PushDeliveryStatus.failed);
    expect(failed.lastError, contains('Webhook returned 503'));
    expect(failed.lastError, contains('server exploded'));
  });
}

typedef _Harness = ({
  AppDatabase db,
  OfflineMutationStore mutationStore,
  ReportRepository repository,
});

_Harness _createHarness() {
  final db = createTestDatabase();
  final mutationStore = OfflineMutationStore(db);
  final recorder = SyncWriteRecorder(
    mutationStore: mutationStore,
    stateStore: SyncObjectStateStore(db),
  );
  final auditRepository = DataOperationLogRepository(db, recorder);
  return (
    db: db,
    mutationStore: mutationStore,
    repository: ReportRepository(db, auditRepository, recorder),
  );
}

class _UidMissReportRepository extends ReportRepository {
  _UidMissReportRepository(super.db);

  @override
  Future<ReportDocument?> getReportByUid(String reportUid) async => null;
}
