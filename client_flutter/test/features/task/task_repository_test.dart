import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('creating a task records local state audit and sync evidence', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final mutationStore = OfflineMutationStore(db);
    final recorder = SyncWriteRecorder(
      mutationStore: mutationStore,
      stateStore: SyncObjectStateStore(db),
    );
    final auditRepository = DataOperationLogRepository(db, recorder);
    final repository = TaskRepository(db, auditRepository, recorder);
    final taskListId = await insertFixtureTaskList(db);

    final taskId = await repository.create(
      fixtureTask(
        uid: 'task-1',
        summary: 'Write Flutter tests',
        taskListId: taskListId,
      ),
    );

    final task = await repository.getById(taskId);
    final auditRows = await auditRepository.listRecent();
    final pendingMutations = await mutationStore.listPending();

    expect(task?.summary, 'Write Flutter tests');
    expect(auditRows.map((row) => row.entityType), contains('task'));
    expect(
      pendingMutations.map((mutation) => mutation.objectType),
      containsAll(<String>['task_item', 'audit_log']),
    );
  });

  test('creating a task without a task list is rejected', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = TaskRepository(db);

    await expectLater(
      repository.create(
        TaskItemsCompanion.insert(
          uid: 'task-without-list',
          dtstamp: fixtureNow(),
          summary: 'Missing list',
          taskListId: const Value(null),
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
