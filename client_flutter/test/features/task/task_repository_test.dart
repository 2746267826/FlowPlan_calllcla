import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

typedef _Evidence = ({
  DataOperationLogRepository auditRepository,
  OfflineMutationStore mutationStore,
  SyncWriteRecorder recorder,
});

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
    expect(auditRows.map((row) => row.entityType), contains('task_item'));
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

  test('task list defaults switch only between active lists', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(db);

    final firstId = await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Inbox A',
        createdAt: fixtureNow(),
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final archivedId = await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Archived',
        createdAt: fixtureNow().add(const Duration(minutes: 1)),
        isArchived: const Value(true),
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final secondId = await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Inbox B',
        createdAt: fixtureNow().add(const Duration(minutes: 2)),
        isDefault: const Value(true),
      ),
      audit: false,
    );

    expect((await repository.getTaskListById(firstId))?.isDefault, isFalse);
    expect((await repository.getTaskListById(archivedId))?.isDefault, isFalse);
    expect((await repository.getTaskListById(secondId))?.isDefault, isTrue);
    await expectLater(
      repository.setDefaultTaskList(archivedId, audit: false),
      throwsA(isA<StateError>()),
    );
  });

  test('archive and restore task list migrate tasks and clear bindings',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final evidence = _createEvidence(db);
    final booksRepository = CalendarBooksRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );
    final taskRepository = TaskRepository(db);
    final bindingsRepository = OutlookSyncBindingsRepository(db);

    final sourceId = await booksRepository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Source',
        createdAt: fixtureNow(),
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final fallbackId = await booksRepository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Fallback',
        createdAt: fixtureNow().add(const Duration(minutes: 1)),
      ),
      audit: false,
    );
    final taskId = await db.into(db.taskItems).insert(
          fixtureTask(
            uid: 'task-migrates-on-archive',
            summary: 'Move when archived',
            taskListId: sourceId,
          ),
        );
    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: sourceId,
        remoteCalendarId: 'remote-list',
        remoteCalendarName: 'Remote list',
        linkedAt: fixtureNow(),
      ),
    );

    await booksRepository.archiveTaskList(sourceId);
    await booksRepository.unarchiveTaskList(sourceId);

    final movedTask = await taskRepository.getById(taskId);
    final restored = await booksRepository.getTaskListById(sourceId);
    final fallback = await booksRepository.getTaskListById(fallbackId);
    final auditRows = await evidence.auditRepository.listRecent();

    expect(movedTask?.taskListId, fallbackId);
    expect(restored?.isArchived, isFalse);
    expect(restored?.isVisible, isTrue);
    expect(restored?.isDefault, isFalse);
    expect(fallback?.isDefault, isTrue);
    expect(await bindingsRepository.getTaskListBinding(sourceId), isNull);
    expect(
      auditRows
          .where((row) => row.entityType == 'task_list')
          .map((row) => row.action),
      containsAll(<String>['archive', 'restore']),
    );
    expect(
      auditRows.where(
        (row) =>
            row.entityType == 'task_list' &&
            row.action == 'archive' &&
            row.metadataJson?.contains('"task_count":1') == true,
      ),
      isNotEmpty,
    );
  });

  test('deleting task list migrates tasks deletes defaults and records sync',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final evidence = _createEvidence(db);
    final booksRepository = CalendarBooksRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );
    final taskRepository = TaskRepository(db);
    final bindingsRepository = OutlookSyncBindingsRepository(db);

    final sourceId = await booksRepository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Delete me',
        createdAt: fixtureNow(),
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final fallbackId = await booksRepository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Keep me',
        createdAt: fixtureNow().add(const Duration(minutes: 1)),
      ),
      audit: false,
    );
    await booksRepository.saveTaskListDefaults(
      id: sourceId,
      defaultIsAutoScheduled: false,
      defaultReminderMinutesBefore: 45,
      audit: false,
    );
    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: sourceId,
        remoteCalendarId: 'remote-delete',
        remoteCalendarName: 'Remote delete',
        linkedAt: fixtureNow(),
      ),
    );
    final taskId = await db.into(db.taskItems).insert(
          fixtureTask(
            uid: 'task-migrates-on-delete',
            summary: 'Move when deleted',
            taskListId: sourceId,
          ),
        );

    final deleted = await booksRepository.deleteTaskList(sourceId);

    final movedTask = await taskRepository.getById(taskId);
    final defaults = await booksRepository.getTaskListDefaults(
      sourceId,
      fallbackReminderMinutes: 99,
    );
    final auditRows = await evidence.auditRepository.listRecent();
    final pendingMutations = await evidence.mutationStore.listPending();

    expect(deleted, 1);
    expect(await booksRepository.getTaskListById(sourceId), isNull);
    expect(movedTask?.taskListId, fallbackId);
    expect(
        (await booksRepository.getTaskListById(fallbackId))?.isDefault, isTrue);
    expect(await bindingsRepository.getTaskListBinding(sourceId), isNull);
    expect(defaults.defaultIsAutoScheduled, isTrue);
    expect(defaults.defaultReminderMinutesBefore, 99);
    expect(
      auditRows.where(
        (row) =>
            row.entityType == 'task_list' &&
            row.action == 'delete' &&
            row.metadataJson?.contains('"task_count":1') == true,
      ),
      isNotEmpty,
    );
    expect(
      pendingMutations.map((mutation) => mutation.objectType),
      containsAll(<String>['task_list', 'audit_log']),
    );
    expect(
      pendingMutations.where(
        (mutation) =>
            mutation.objectType == 'task_list' &&
            mutation.action.name == 'delete',
      ),
      isNotEmpty,
    );
  });

  test('task and task list visible queries hide hidden and archived containers',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final booksRepository = CalendarBooksRepository(db);
    final taskRepository = TaskRepository(db);

    final visibleListId = await booksRepository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Visible',
        createdAt: fixtureNow(),
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final hiddenListId = await booksRepository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Hidden',
        createdAt: fixtureNow().add(const Duration(minutes: 1)),
        isVisible: const Value(false),
      ),
      audit: false,
    );
    final archivedListId = await booksRepository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Archived',
        createdAt: fixtureNow().add(const Duration(minutes: 2)),
        isArchived: const Value(true),
      ),
      audit: false,
    );
    await taskRepository.create(
      fixtureTask(
        uid: 'visible-task',
        summary: 'Visible task',
        taskListId: visibleListId,
      ),
      audit: false,
    );
    await taskRepository.create(
      fixtureTask(
        uid: 'hidden-task',
        summary: 'Hidden task',
        taskListId: hiddenListId,
      ),
      audit: false,
    );
    await db.into(db.taskItems).insert(
          fixtureTask(
            uid: 'archived-task',
            summary: 'Archived task',
            taskListId: archivedListId,
          ),
        );

    final listedTasks = await taskRepository.listAllVisible();
    final watchedTasks = await taskRepository.watchAll().first;
    final activeLists = await booksRepository.watchAllTaskLists().first;
    final archivedLists = await booksRepository.watchArchivedTaskLists().first;

    expect(listedTasks.map((task) => task.summary), ['Visible task']);
    expect(watchedTasks.map((task) => task.summary), ['Visible task']);
    expect(
      activeLists.map((list) => list.name),
      containsAll(<String>['Visible', 'Hidden']),
    );
    expect(activeLists.map((list) => list.name), isNot(contains('Archived')));
    expect(archivedLists.map((list) => list.name), ['Archived']);
  });

  test('task repository rejects archived task list bindings', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = TaskRepository(db);
    final activeListId = await insertFixtureTaskList(db);
    final archivedListId = await db.into(db.taskLists).insert(
          TaskListsCompanion.insert(
            name: 'Archived',
            createdAt: fixtureNow(),
            isArchived: const Value(true),
          ),
        );
    final taskId = await repository.create(
      fixtureTask(
        uid: 'active-task',
        summary: 'Active task',
        taskListId: activeListId,
      ),
      audit: false,
    );
    final existing = await repository.getById(taskId);

    await expectLater(
      repository.create(
        fixtureTask(
          uid: 'archived-task-create',
          summary: 'Archived create',
          taskListId: archivedListId,
        ),
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.update(
        existing!.toCompanion(false).copyWith(
              taskListId: Value(archivedListId),
            ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('task update and delete record audit and sync evidence', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final evidence = _createEvidence(db);
    final repository = TaskRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );
    final taskListId = await insertFixtureTaskList(db);
    final taskId = await repository.create(
      fixtureTask(
        uid: 'task-audit',
        summary: 'Original task',
        taskListId: taskListId,
      ),
      audit: false,
    );
    final original = await repository.getById(taskId);

    await repository.update(
      original!.toCompanion(false).copyWith(
            summary: const Value('Updated task'),
          ),
    );
    final deleted = await repository.delete(taskId);

    final auditRows = await evidence.auditRepository.listRecent();
    final pendingMutations = await evidence.mutationStore.listPending();

    expect(deleted, 1);
    expect(await repository.getById(taskId), isNull);
    expect(
      auditRows
          .where((row) => row.entityType == 'task_item')
          .map((row) => row.action),
      containsAll(<String>['update', 'delete']),
    );
    expect(
      pendingMutations
          .where((mutation) => mutation.objectType == 'task_item')
          .map((mutation) => mutation.action.name),
      containsAll(<String>['update', 'delete']),
    );
  });

  test('batch schedule updates and clears dtstart with sync evidence',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final evidence = _createEvidence(db);
    final repository = TaskRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );
    final taskListId = await insertFixtureTaskList(db);
    final firstTaskId = await repository.create(
      fixtureTask(
        uid: 'batch-first',
        summary: 'Batch first',
        taskListId: taskListId,
      ),
      audit: false,
    );
    final secondTaskId = await repository.create(
      fixtureTask(
        uid: 'batch-second',
        summary: 'Batch second',
        taskListId: taskListId,
      ).copyWith(
        dtstart: Value(fixtureNow().add(const Duration(hours: 4))),
      ),
      audit: false,
    );

    await repository.batchUpdateSchedule([
      (
        id: firstTaskId,
        dtstart: fixtureNow().add(const Duration(hours: 1)),
      ),
    ]);
    expect(
      (await repository.getById(firstTaskId))?.dtstart?.toUtc(),
      fixtureNow().add(const Duration(hours: 1)),
    );

    await repository.batchApplySchedule(
      scheduled: [
        (
          id: firstTaskId,
          dtstart: fixtureNow().add(const Duration(hours: 2)),
        ),
      ],
      clearedTaskIds: <int>[secondTaskId, secondTaskId],
    );

    final first = await repository.getById(firstTaskId);
    final second = await repository.getById(secondTaskId);
    final pendingMutations = await evidence.mutationStore.listPending();
    final taskScheduleMutations = pendingMutations
        .where((mutation) => mutation.objectType == 'task_item')
        .toList();

    expect(first?.dtstart?.toUtc(), fixtureNow().add(const Duration(hours: 2)));
    expect(second?.dtstart, isNull);
    expect(
      taskScheduleMutations.map((mutation) => mutation.localId).toSet(),
      containsAll(<String>[firstTaskId.toString(), secondTaskId.toString()]),
    );
    expect(
      taskScheduleMutations.every(
        (mutation) =>
            mutation.action.name == 'update' &&
            mutation.changedFieldsJson?.contains('dtstart') == true,
      ),
      isTrue,
    );
  });

  test('task repository returns empty results for empty id filters', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = TaskRepository(db);

    expect(await repository.getByIds(const <int>[]), isEmpty);
    expect(await repository.getByTaskListIds(const <int>[]), isEmpty);
  });

  test('task repository update and delete are no-ops for missing rows',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final evidence = _createEvidence(db);
    final repository = TaskRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );

    final updated = await repository.update(
      TaskItemsCompanion.insert(
        id: const Value(404),
        uid: 'missing-task',
        dtstamp: fixtureNow(),
        summary: 'Missing task',
      ),
    );
    final deleted = await repository.delete(404);

    expect(updated, isFalse);
    expect(deleted, 0);
    expect(await evidence.auditRepository.listRecent(), isEmpty);
    expect(await evidence.mutationStore.listPending(), isEmpty);
  });

  test('empty batch schedule application does not record sync mutations',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final evidence = _createEvidence(db);
    final repository = TaskRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );

    await repository.batchApplySchedule(
      scheduled: const <({int id, DateTime dtstart})>[],
      clearedTaskIds: const <int>[],
    );

    expect(await evidence.mutationStore.listPending(), isEmpty);
  });

  test('task watch stream emits create update visibility and delete changes',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final booksRepository = CalendarBooksRepository(db);
    final taskRepository = TaskRepository(db);
    final taskListId = await booksRepository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Stream tasks',
        createdAt: fixtureNow(),
      ),
      audit: false,
    );
    final tasks = StreamQueue(taskRepository.watchAll());
    addTearDown(tasks.cancel);

    expect(await _nextTaskSummaries(tasks, const <String>[]), isEmpty);
    final taskId = await taskRepository.create(
      fixtureTask(
        uid: 'stream-task',
        summary: 'Visible stream task',
        taskListId: taskListId,
      ),
      audit: false,
    );
    expect(
      await _nextTaskSummaries(tasks, const <String>['Visible stream task']),
      ['Visible stream task'],
    );

    final task = await taskRepository.getById(taskId);
    await taskRepository.update(
      task!.toCompanion(false).copyWith(
            summary: const Value('Updated stream task'),
          ),
      audit: false,
    );
    expect(
      await _nextTaskSummaries(tasks, const <String>['Updated stream task']),
      ['Updated stream task'],
    );

    await booksRepository.toggleTaskListVisible(
      taskListId,
      false,
      audit: false,
    );
    expect(await _nextTaskSummaries(tasks, const <String>[]), isEmpty);

    await booksRepository.toggleTaskListVisible(
      taskListId,
      true,
      audit: false,
    );
    expect(
      await _nextTaskSummaries(tasks, const <String>['Updated stream task']),
      ['Updated stream task'],
    );

    await taskRepository.delete(taskId, audit: false);
    expect(await _nextTaskSummaries(tasks, const <String>[]), isEmpty);
  });
}

_Evidence _createEvidence(AppDatabase db) {
  final mutationStore = OfflineMutationStore(db);
  final recorder = SyncWriteRecorder(
    mutationStore: mutationStore,
    stateStore: SyncObjectStateStore(db),
  );
  return (
    auditRepository: DataOperationLogRepository(db, recorder),
    mutationStore: mutationStore,
    recorder: recorder,
  );
}

Future<List<String>> _nextTaskSummaries(
  StreamQueue<List<TaskItem>> queue,
  List<String> expected,
) async {
  final tasks = await _nextWhere(
    queue,
    (items) => _sameStrings(
      items.map((task) => task.summary).toList(growable: false),
      expected,
    ),
  );
  return tasks.map((task) => task.summary).toList(growable: false);
}

Future<T> _nextWhere<T>(
  StreamQueue<T> queue,
  bool Function(T value) predicate,
) async {
  for (var i = 0; i < 10; i++) {
    final value = await queue.next.timeout(const Duration(seconds: 2));
    if (predicate(value)) {
      return value;
    }
  }
  fail('Expected stream to emit a matching value.');
}

bool _sameStrings(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) {
    return false;
  }
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      return false;
    }
  }
  return true;
}
