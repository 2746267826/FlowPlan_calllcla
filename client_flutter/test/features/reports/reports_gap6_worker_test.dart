import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('report rows parse blank confirmation values as null', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = ReportRepository(db);

    await db.customStatement('''
      INSERT INTO report_documents (
        report_uid,
        report_type,
        period_start,
        period_end,
        title,
        summary_markdown,
        metrics_json,
        source_snapshot_json,
        status,
        created_at,
        updated_at,
        confirmed_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', <Object?>[
      'report:daily:2026-06-11',
      ReportType.daily,
      '2026-06-11T00:00:00.000',
      '2026-06-12T00:00:00.000',
      'Blank confirmed report',
      'Draft body',
      '{}',
      '{}',
      ReportStatus.draft,
      '2026-06-11T08:00:00.000',
      '2026-06-11T08:05:00.000',
      '   ',
    ]);

    final report = await repository.getReportByUid('report:daily:2026-06-11');

    expect(report, isNotNull);
    expect(report!.confirmedAt, isNull);
    expect(report.toJson(), containsPair('confirmedAt', null));
  });

  test('delivery rows parse blank sent values as null and channel filter works',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = ReportRepository(db);

    final due = DateTime.now().subtract(const Duration(minutes: 1));
    final mail = await repository.queueDelivery(
      channel: 'mail',
      payload: const <String, Object?>{'kind': 'report'},
      scheduledAt: due,
    );
    await repository.queueDelivery(
      channel: 'webhook',
      payload: const <String, Object?>{'kind': 'report'},
      scheduledAt: due,
    );
    await db.customStatement(
      'UPDATE report_push_deliveries SET sent_at = ? WHERE id = ?',
      <Object?>['', mail.id],
    );

    final parsed = await repository.getDeliveryById(mail.id);
    final mailPending = await repository.listPendingDeliveries(channel: 'mail');

    expect(parsed!.sentAt, isNull);
    expect(mailPending.map((delivery) => delivery.channel), <String>['mail']);
  });

  test('report refresh records before and after payloads', () async {
    final harness = _createHarness();
    addTearDown(harness.db.close);
    final repository = harness.repository;
    final start = DateTime(2026, 6, 11);

    final created = await repository.upsertReportDraft(
      reportType: ReportType.weekly,
      periodStart: start,
      periodEnd: start.add(const Duration(days: 7)),
      title: 'Weekly',
      summaryMarkdown: 'First',
      metrics: const <String, Object?>{'done': 1},
      sourceSnapshot: const <String, Object?>{'source': 'first'},
    );
    final refreshed = await repository.upsertReportDraft(
      reportType: ReportType.weekly,
      periodStart: start,
      periodEnd: start.add(const Duration(days: 7)),
      title: 'Weekly refreshed',
      summaryMarkdown: 'Second',
      metrics: const <String, Object?>{'done': 2},
      sourceSnapshot: const <String, Object?>{'source': 'second'},
    );

    final logs = await harness.operationLogs.listRecent(limit: 10);
    final refreshLog = logs.singleWhere(
      (log) => log.action == 'refresh_report_draft',
    );
    final mutations = await harness.mutationStore.listPending(limit: 10);
    final reportMutations = mutations
        .where((mutation) =>
            mutation.objectType == SyncObjectType.reportDocument.key)
        .toList();

    expect(refreshed.id, created.id);
    expect(jsonDecode(refreshLog.beforeJson!), containsPair('title', 'Weekly'));
    expect(
      jsonDecode(refreshLog.afterJson!),
      containsPair('title', 'Weekly refreshed'),
    );
    expect(reportMutations.map((mutation) => mutation.action), <Object>[
      OfflineMutationAction.create,
      OfflineMutationAction.update,
    ]);
  });
}

typedef _Harness = ({
  AppDatabase db,
  DataOperationLogRepository operationLogs,
  OfflineMutationStore mutationStore,
  ReportRepository repository,
});

_Harness _createHarness() {
  final db = createTestDatabase();
  final mutationStore = OfflineMutationStore(db);
  final stateStore = SyncObjectStateStore(db);
  final recorder = SyncWriteRecorder(
    mutationStore: mutationStore,
    stateStore: stateStore,
  );
  final operationLogs = DataOperationLogRepository(db, recorder);
  return (
    db: db,
    operationLogs: operationLogs,
    mutationStore: mutationStore,
    repository: ReportRepository(db, operationLogs, recorder),
  );
}
