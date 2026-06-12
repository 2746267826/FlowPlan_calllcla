import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_status.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('value holder constructors remain callable at runtime', () {
    expect(ReportType(), isA<ReportType>());
    expect(ReportStatus(), isA<ReportStatus>());
    expect(PushDeliveryStatus(), isA<PushDeliveryStatus>());
  });

  test('report draft upsert replaces the same period draft', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = ReportRepository(db);
    final start = fixtureNow();
    final end = start.add(const Duration(days: 1));

    final first = await repository.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: start,
      periodEnd: end,
      title: 'Daily report',
      summaryMarkdown: 'Initial',
      metrics: const <String, Object?>{'tasks': 1},
      sourceSnapshot: const <String, Object?>{'source': 'test'},
    );
    final second = await repository.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: start,
      periodEnd: end,
      title: 'Daily report revised',
      summaryMarkdown: 'Revised',
      metrics: const <String, Object?>{'tasks': 2},
      sourceSnapshot: const <String, Object?>{'source': 'test'},
    );

    expect(second.id, first.id);
    expect(second.title, 'Daily report revised');
    expect(await repository.listRecentReports(), hasLength(1));
  });

  test('report drafts record audit rows and sync mutations', () async {
    final harness = _createRepositoryHarness();
    addTearDown(harness.db.close);
    final repository = harness.repository;
    final start = DateTime(2026, 6, 10);
    final end = start.add(const Duration(days: 1));

    final created = await repository.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: start,
      periodEnd: end,
      title: 'Daily report',
      summaryMarkdown: 'Initial report markdown',
      metrics: const <String, Object?>{'completed_task_count': 1},
      sourceSnapshot: const <String, Object?>{'source': 'generation'},
    );
    final refreshed = await repository.upsertReportDraft(
      reportType: ReportType.daily,
      periodStart: start,
      periodEnd: end,
      title: 'Daily report refreshed',
      summaryMarkdown: 'Refreshed report markdown',
      metrics: const <String, Object?>{'completed_task_count': 2},
      sourceSnapshot: const <String, Object?>{'source': 'refresh'},
    );

    final auditRows = await harness.auditRepository.listRecent(limit: 10);
    final createLog = auditRows.singleWhere(
      (row) => row.action == 'generate_report_draft',
    );
    final updateLog = auditRows.singleWhere(
      (row) => row.action == 'refresh_report_draft',
    );
    final mutations = await harness.mutationStore.listPending(limit: 10);
    final reportMutations = mutations
        .where(
          (mutation) =>
              mutation.objectType == SyncObjectType.reportDocument.key,
        )
        .toList();
    final reportState = await harness.stateStore.getState(
      objectType: SyncObjectType.reportDocument.key,
      localId: created.id.toString(),
    );

    expect(refreshed.id, created.id);
    expect(createLog.entityType, 'report_document');
    expect(jsonDecode(createLog.afterJson!),
        containsPair('title', 'Daily report'));
    expect(updateLog.entityId, refreshed.id.toString());
    expect(jsonDecode(updateLog.beforeJson!),
        containsPair('title', 'Daily report'));
    expect(
      jsonDecode(updateLog.afterJson!),
      containsPair('title', 'Daily report refreshed'),
    );
    expect(
      reportMutations.map((mutation) => mutation.action),
      <OfflineMutationAction>[
        OfflineMutationAction.create,
        OfflineMutationAction.update,
      ],
    );
    expect(
      mutations.map((mutation) => mutation.objectType),
      contains(SyncObjectType.auditLog.key),
    );
    expect(reportState!.uid, created.reportUid);
    expect(reportState.localVersion, 2);
    expect(reportState.syncState, SyncState.pendingCreate);
  });

  test('diaries and deliveries record sync payloads for lifecycle changes',
      () async {
    final harness = _createRepositoryHarness();
    addTearDown(harness.db.close);
    final repository = harness.repository;

    final diary = await repository.upsertDiaryDraft(
      entryDate: DateTime(2026, 6, 10, 23, 45),
      title: 'Diary draft',
      bodyMarkdown: 'Initial diary',
      linkedTaskIds: const <int>[7],
      linkedFileIds: const <String>['file-1'],
      location: const <String, Object?>{'name': 'Desk'},
      weather: const <String, Object?>{'summary': 'Clear'},
    );
    final refreshedDiary = await repository.upsertDiaryDraft(
      entryDate: DateTime(2026, 6, 10, 1),
      title: 'Diary refreshed',
      bodyMarkdown: 'Refreshed diary',
    );
    await repository.confirmDiary(diary.id);
    final delivery = await repository.queueDelivery(
      diaryId: diary.id,
      channel: 'telegram',
      target: 'chat-1',
      payload: const <String, Object?>{'text': 'Diary ready'},
      scheduledAt: DateTime(2026, 6, 10, 9),
    );
    await repository.markDeliverySent(delivery.id);

    final mutations = await harness.mutationStore.listPending(limit: 20);
    final diaryMutations = mutations
        .where(
            (mutation) => mutation.objectType == SyncObjectType.diaryEntry.key)
        .toList();
    final deliveryMutations = mutations
        .where(
          (mutation) =>
              mutation.objectType == SyncObjectType.reportPushDelivery.key,
        )
        .toList();
    final sentDelivery = await repository.getDeliveryById(delivery.id);
    final deliveryPayload =
        jsonDecode(deliveryMutations.last.payloadJson) as Map<String, dynamic>;

    expect(refreshedDiary.id, diary.id);
    expect(
        diaryMutations.map((mutation) => mutation.action),
        <OfflineMutationAction>[
          OfflineMutationAction.create,
          OfflineMutationAction.update,
          OfflineMutationAction.update,
        ]);
    expect(
      deliveryMutations.map((mutation) => mutation.action),
      <OfflineMutationAction>[
        OfflineMutationAction.create,
        OfflineMutationAction.update,
      ],
    );
    expect(sentDelivery!.status, PushDeliveryStatus.sent);
    expect(deliveryPayload, containsPair('status', PushDeliveryStatus.sent));
    expect(deliveryPayload['sentAt'], isNotNull);
  });

  test('missing ids do not enqueue sync updates', () async {
    final harness = _createRepositoryHarness();
    addTearDown(harness.db.close);
    final repository = harness.repository;

    await repository.confirmReport(404);
    await repository.confirmDiary(404);
    await repository.markDeliverySent(404);

    expect(await harness.mutationStore.listPending(), isEmpty);
  });
}

typedef _RepositoryHarness = ({
  AppDatabase db,
  DataOperationLogRepository auditRepository,
  OfflineMutationStore mutationStore,
  ReportRepository repository,
  SyncObjectStateStore stateStore,
});

_RepositoryHarness _createRepositoryHarness() {
  final db = createTestDatabase();
  final mutationStore = OfflineMutationStore(db);
  final stateStore = SyncObjectStateStore(db);
  final recorder = SyncWriteRecorder(
    mutationStore: mutationStore,
    stateStore: stateStore,
  );
  final auditRepository = DataOperationLogRepository(db, recorder);
  return (
    db: db,
    auditRepository: auditRepository,
    mutationStore: mutationStore,
    repository: ReportRepository(db, auditRepository, recorder),
    stateStore: stateStore,
  );
}
