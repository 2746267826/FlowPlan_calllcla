import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/sync/ms_graph_service.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_sync_policy.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_snapshot.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_sync_service.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('syncBoundTaskMirrors is a no-op when there are no task list bindings',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    await harness.createTask(
      taskListId: taskListId,
      summary: 'Unbound task',
    );

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 0);
    expect(result.updated, 0);
    expect(result.deleted, 0);
    expect(result.conflicted, 0);
    expect(result.taskListDetails, isEmpty);
    expect(harness.graph.createEventCalls, isEmpty);
    expect(harness.graph.updateEventCalls, isEmpty);
    expect(await harness.mirrorRepository.loadTaskMirrorBindings(), isEmpty);
  });

  test('syncBoundTaskMirrors creates missing mirrors in the managed container',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Write service coverage',
    );
    await harness.bindTaskList(taskListId);

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 1);
    expect(result.updated, 0);
    expect(result.conflicted, 0);
    expect(harness.graph.createEventCalls, hasLength(1));
    expect(
        harness.graph.createEventCalls.single.calendarId, 'remote-$taskListId');
    expect(harness.graph.createEventCalls.single.isManagedContainer, isTrue);

    final binding = await harness.mirrorRepository.getTaskMirrorBinding(taskId);
    expect(binding, isNotNull);
    expect(binding!.remoteEventId, 'created-1');
    expect(binding.conflictState, OutlookTaskMirrorConflictState.none);
    expect(binding.localSnapshotHash, isNotEmpty);
  });

  test('syncBoundTaskMirrors marks create null responses as conflicted',
      () async {
    final harness = await _createHarness();
    harness.graph.returnNullOnCreate = true;
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Create returns null',
    );
    await harness.bindTaskList(taskListId);

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 0);
    expect(result.updated, 0);
    expect(result.conflicted, 1);
    expect(harness.graph.createEventCalls, hasLength(1));
    expect(
      await harness.mirrorRepository.getTaskMirrorBinding(taskId),
      isNull,
    );
  });

  test(
      'syncBoundTaskMirrors records remoteDeleted when remote mirror is missing',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Missing remote',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteEventId: 'missing-event',
      ),
    );

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 0);
    expect(result.updated, 0);
    expect(result.conflicted, 1);
    expect(harness.graph.updateEventCalls, isEmpty);
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.remoteDeleted);
    expect(saved.conflictMessage, contains('Outlook'));
  });

  test('syncBoundTaskMirrors records remoteChanged instead of overwriting',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Local task',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteEventId: 'event-remote',
      ),
    );
    harness.graph.events['remote-$taskListId/event-remote'] = graphEvent(
      id: 'event-remote',
      subject: 'Changed in Outlook',
      snapshot: snapshot,
      start: fixtureNow(),
      end: fixtureNow().add(const Duration(hours: 1)),
    );

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 0);
    expect(result.updated, 0);
    expect(result.conflicted, 1);
    expect(harness.graph.updateEventCalls, isEmpty);
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.remoteChanged);
    expect(saved.remoteSnapshotHash, isNot(snapshot.fingerprint));
  });

  test('syncBoundTaskMirrors records divergent when both sides changed',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Original title',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteEventId: 'event-divergent',
      ),
    );
    await harness.updateTaskSummary(taskId, 'Changed locally');
    harness.graph.events['remote-$taskListId/event-divergent'] = graphEvent(
      id: 'event-divergent',
      subject: 'Changed remotely',
      snapshot: snapshot,
      start: fixtureNow(),
      end: fixtureNow().add(const Duration(hours: 1)),
    );

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 0);
    expect(result.updated, 0);
    expect(result.conflicted, 1);
    expect(harness.graph.updateEventCalls, isEmpty);
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.divergent);
    expect(saved.localSnapshotHash, isNot(snapshot.fingerprint));
    expect(saved.remoteSnapshotHash, isNot(snapshot.fingerprint));
  });

  test(
      'syncBoundTaskMirrors pushes local-only changes and resolves the binding',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Original local',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    final remoteEvent = graphEvent(
      id: 'event-local',
      subject: snapshot.summary,
      snapshot: snapshot,
      start: fixtureNow(),
      end: fixtureNow().add(const Duration(hours: 1)),
      showAs: 'busy',
    );
    final remoteSnapshot = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
      task: task,
      taskListName: 'Inbox',
      event: remoteEvent,
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteSnapshot: remoteSnapshot,
        remoteEventId: 'event-local',
      ),
    );
    harness.graph.events['remote-$taskListId/event-local'] = remoteEvent;
    await harness.updateTaskSummary(taskId, 'Changed locally');

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 0);
    expect(result.updated, 1);
    expect(result.conflicted, 0);
    expect(harness.graph.updateEventCalls, hasLength(1));
    expect(harness.graph.updateEventCalls.single.eventId, 'event-local');
    expect(
      harness.graph.updateEventCalls.single.event['subject'],
      'Changed locally',
    );
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.none);
    expect(saved.localSnapshotHash, isNot(snapshot.fingerprint));
    expect(saved.conflictMessage, isNull);
  });

  test('syncBoundTaskMirrors records writeFailed when remote update fails',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Original local',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    final remoteEvent = graphEvent(
      id: 'event-fail',
      subject: snapshot.summary,
      snapshot: snapshot,
      start: fixtureNow(),
      end: fixtureNow().add(const Duration(hours: 1)),
      showAs: 'busy',
    );
    final remoteSnapshot = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
      task: task,
      taskListName: 'Inbox',
      event: remoteEvent,
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteSnapshot: remoteSnapshot,
        remoteEventId: 'event-fail',
      ),
    );
    harness.graph.events['remote-$taskListId/event-fail'] = remoteEvent;
    harness.graph.updateFailures.add('event-fail');
    await harness.updateTaskSummary(taskId, 'Changed locally');

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 0);
    expect(result.updated, 0);
    expect(result.conflicted, 1);
    expect(harness.graph.updateEventCalls, hasLength(1));
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.writeFailed);
    expect(saved.conflictMessage, contains('Outlook 镜像更新返回失败'));
  });

  test('syncBoundTaskMirrors clears stale conflicts when both sides match',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Already resolved',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    final remoteEvent = graphEvent(
      id: 'event-resolved',
      subject: snapshot.summary,
      snapshot: snapshot,
      start: fixtureNow(),
      end: fixtureNow().add(const Duration(hours: 1)),
      showAs: 'busy',
    );
    final remoteSnapshot = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
      task: task,
      taskListName: 'Inbox',
      event: remoteEvent,
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteSnapshot: remoteSnapshot,
        remoteEventId: 'event-resolved',
        conflictState: OutlookTaskMirrorConflictState.remoteChanged,
      ),
    );
    harness.graph.events['remote-$taskListId/event-resolved'] = remoteEvent;

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 0);
    expect(result.updated, 0);
    expect(result.conflicted, 0);
    expect(harness.graph.updateEventCalls, isEmpty);
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.none);
    expect(saved.conflictMessage, isNull);
    expect(saved.conflictDetectedAt, isNull);
  });

  test('applyRemoteToLocal updates the task and resolves the mirror conflict',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Local title',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final localSnapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: localSnapshot,
        remoteEventId: 'event-remote',
        conflictState: OutlookTaskMirrorConflictState.remoteChanged,
      ),
    );
    final remoteSnapshot = localSnapshot.copyWith(
      summary: 'Remote title',
      description: 'Remote notes',
      location: 'Room 42',
      status: 'IN-PROCESS',
    );
    harness.graph.events['remote-$taskListId/event-remote'] = graphEvent(
      id: 'event-remote',
      subject: 'Remote title',
      snapshot: remoteSnapshot,
      start: fixtureNow(),
      end: fixtureNow().add(const Duration(hours: 2)),
      location: 'Room 42',
    );

    final result = await harness.service.applyRemoteToLocal(taskId);

    expect(result.success, isTrue);
    final updatedTask = await harness.taskRepository.getById(taskId);
    expect(updatedTask!.summary, 'Remote title');
    expect(updatedTask.description, 'Remote notes');
    expect(updatedTask.location, 'Room 42');
    expect(updatedTask.status, 'IN-PROCESS');
    expect(updatedTask.durationMinutes, 120);
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.none);
    expect(saved.remoteSnapshotHash, isNotEmpty);
  });

  test('forcePushLocalToRemote recreates remoteDeleted mirrors', () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Recreate me',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteEventId: 'deleted-event',
        conflictState: OutlookTaskMirrorConflictState.remoteDeleted,
      ),
    );

    final result = await harness.service.forcePushLocalToRemote(taskId);

    expect(result.success, isTrue);
    expect(harness.graph.createEventCalls, hasLength(1));
    expect(harness.graph.updateEventCalls, isEmpty);
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.none);
    expect(saved.remoteEventId, 'created-1');
  });

  test('action methods report missing context without creating graph writes',
      () async {
    final harness = await _createHarness();
    final missingTaskId = 404;

    final forceResult =
        await harness.service.forcePushLocalToRemote(missingTaskId);
    final applyResult = await harness.service.applyRemoteToLocal(missingTaskId);
    final recreateResult =
        await harness.service.recreateRemoteMirror(missingTaskId);

    expect(forceResult.success, isFalse);
    expect(applyResult.success, isFalse);
    expect(recreateResult.success, isFalse);
    expect(harness.graph.createEventCalls, isEmpty);
    expect(harness.graph.updateEventCalls, isEmpty);
  });

  test(
      'detachMirror removes an existing binding and treats no binding as no-op',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Detach me',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteEventId: 'event-detach',
      ),
    );

    final detached = await harness.service.detachMirror(taskId);
    final detachedAgain = await harness.service.detachMirror(taskId);

    expect(detached.success, isTrue);
    expect(detachedAgain.success, isTrue);
    expect(await harness.mirrorRepository.getTaskMirrorBinding(taskId), isNull);
    expect(harness.graph.createEventCalls, isEmpty);
    expect(harness.graph.updateEventCalls, isEmpty);
  });

  test('cleanupStaleTaskMirrors removes missing and unbound mirror indexes',
      () async {
    final harness = await _createHarness();
    final activeListId = await harness.createTaskList(name: 'Active');
    final unboundListId = await harness.createTaskList(name: 'Unbound');
    final activeTaskId = await harness.createTask(
      taskListId: activeListId,
      summary: 'Active mirror',
    );
    final unboundTaskId = await harness.createTask(
      taskListId: unboundListId,
      summary: 'Unbound mirror',
    );
    await harness.bindTaskList(activeListId);

    final activeTask = await harness.taskRepository.getById(activeTaskId);
    final activeSnapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: activeTask!,
      taskListName: 'Active',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: activeTask,
        taskListName: 'Active',
        snapshot: activeSnapshot,
        remoteEventId: 'active-event',
      ),
    );

    final unboundTask = await harness.taskRepository.getById(unboundTaskId);
    final unboundSnapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: unboundTask!,
      taskListName: 'Unbound',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: unboundTask,
        taskListName: 'Unbound',
        snapshot: unboundSnapshot,
        remoteEventId: 'unbound-event',
      ),
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: 9999,
        localTaskListId: activeListId,
        remoteCalendarId: 'remote-$activeListId',
        remoteCalendarName: harness.remoteCalendarName('Active'),
        remoteEventId: 'missing-event',
        syncedAt: fixtureNow(),
      ),
    );

    final result = await harness.service.cleanupStaleTaskMirrors();

    expect(result.success, isTrue);
    expect(result.affected, 2);
    final remaining = await harness.mirrorRepository.loadTaskMirrorBindings();
    expect(remaining.keys, contains(activeTaskId));
    expect(remaining.keys, isNot(contains(unboundTaskId)));
    expect(remaining.keys, isNot(contains(9999)));
  });

  test('forcePushAllPendingLocalChanges filters eligible mirrors only',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final dirtyTaskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Dirty mirror',
    );
    final cleanTaskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Clean mirror',
    );
    await harness.bindTaskList(taskListId);

    for (final taskId in <int>[dirtyTaskId, cleanTaskId]) {
      final task = await harness.taskRepository.getById(taskId);
      final snapshot = OutlookTaskMirrorSnapshot.fromTask(
        task: task!,
        taskListName: 'Inbox',
      );
      await harness.mirrorRepository.saveTaskMirrorBinding(
        harness.bindingFor(
          task: task,
          taskListName: 'Inbox',
          snapshot: snapshot,
          remoteEventId: 'event-$taskId',
          conflictState: taskId == dirtyTaskId
              ? OutlookTaskMirrorConflictState.writeFailed
              : OutlookTaskMirrorConflictState.none,
        ),
      );
      harness.graph.events['remote-$taskListId/event-$taskId'] = graphEvent(
        id: 'event-$taskId',
        subject: task.summary,
        snapshot: snapshot,
        start: fixtureNow(),
        end: fixtureNow().add(const Duration(hours: 1)),
      );
    }

    final result = await harness.service.forcePushAllPendingLocalChanges();

    expect(result.success, isTrue);
    expect(result.affected, 1);
    expect(result.failed, 0);
    expect(harness.graph.updateEventCalls, hasLength(1));
    expect(harness.graph.updateEventCalls.single.eventId, 'event-$dirtyTaskId');
  });

  test('forcePushAllPendingLocalChanges reports partial batch failures',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final successfulTaskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Successful dirty mirror',
    );
    final failingTaskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Failing dirty mirror',
    );
    await harness.bindTaskList(taskListId);

    for (final taskId in <int>[successfulTaskId, failingTaskId]) {
      final task = await harness.taskRepository.getById(taskId);
      final snapshot = OutlookTaskMirrorSnapshot.fromTask(
        task: task!,
        taskListName: 'Inbox',
      );
      final eventId = 'event-$taskId';
      final remoteEvent = graphEvent(
        id: eventId,
        subject: snapshot.summary,
        snapshot: snapshot,
        start: fixtureNow(),
        end: fixtureNow().add(const Duration(hours: 1)),
        showAs: 'busy',
      );
      final remoteSnapshot = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
        task: task,
        taskListName: 'Inbox',
        event: remoteEvent,
      );
      await harness.mirrorRepository.saveTaskMirrorBinding(
        harness.bindingFor(
          task: task,
          taskListName: 'Inbox',
          snapshot: snapshot,
          remoteSnapshot: remoteSnapshot,
          remoteEventId: eventId,
          conflictState: OutlookTaskMirrorConflictState.writeFailed,
        ),
      );
      harness.graph.events['remote-$taskListId/$eventId'] = remoteEvent;
    }
    harness.graph.updateFailures.add('event-$failingTaskId');

    final result = await harness.service.forcePushAllPendingLocalChanges();

    expect(result.success, isFalse);
    expect(result.affected, 1);
    expect(result.failed, 1);
    expect(harness.graph.updateEventCalls, hasLength(2));
    final successful =
        await harness.mirrorRepository.getTaskMirrorBinding(successfulTaskId);
    final failed =
        await harness.mirrorRepository.getTaskMirrorBinding(failingTaskId);
    expect(successful!.conflictState, OutlookTaskMirrorConflictState.none);
    expect(failed!.conflictState, OutlookTaskMirrorConflictState.writeFailed);
  });

  test('recreateAllRemoteDeletedMirrors only recreates deleted mirrors',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final deletedTaskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Deleted remote',
    );
    final failedTaskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Write failed',
    );
    await harness.bindTaskList(taskListId);

    for (final entry in <({int taskId, OutlookTaskMirrorConflictState state})>[
      (
        taskId: deletedTaskId,
        state: OutlookTaskMirrorConflictState.remoteDeleted
      ),
      (taskId: failedTaskId, state: OutlookTaskMirrorConflictState.writeFailed),
    ]) {
      final task = await harness.taskRepository.getById(entry.taskId);
      final snapshot = OutlookTaskMirrorSnapshot.fromTask(
        task: task!,
        taskListName: 'Inbox',
      );
      await harness.mirrorRepository.saveTaskMirrorBinding(
        harness.bindingFor(
          task: task,
          taskListName: 'Inbox',
          snapshot: snapshot,
          remoteEventId: 'event-${entry.taskId}',
          conflictState: entry.state,
        ),
      );
    }

    final result = await harness.service.recreateAllRemoteDeletedMirrors();

    expect(result.success, isTrue);
    expect(result.affected, 1);
    expect(harness.graph.createEventCalls, hasLength(1));
    final recreated =
        await harness.mirrorRepository.getTaskMirrorBinding(deletedTaskId);
    final untouched =
        await harness.mirrorRepository.getTaskMirrorBinding(failedTaskId);
    expect(recreated!.conflictState, OutlookTaskMirrorConflictState.none);
    expect(
        untouched!.conflictState, OutlookTaskMirrorConflictState.writeFailed);
  });
}

Future<_MirrorHarness> _createHarness() async {
  final db = createTestDatabase();
  addTearDown(db.close);
  final graph = _FakeGraphService();
  return _MirrorHarness(
    db: db,
    graph: graph,
    calendarBooksRepository: CalendarBooksRepository(db),
    taskRepository: TaskRepository(db),
    bindingsRepository: OutlookSyncBindingsRepository(db),
    mirrorRepository: OutlookTaskMirrorRepository(db),
  );
}

Map<String, dynamic> graphEvent({
  required String id,
  required String subject,
  required OutlookTaskMirrorSnapshot snapshot,
  required DateTime start,
  required DateTime end,
  String? location,
  String showAs = 'tentative',
}) {
  return <String, dynamic>{
    'id': id,
    'subject': subject,
    'body': <String, dynamic>{
      'contentType': 'Text',
      'content': [
        'Description',
        OutlookTaskMirrorSnapshot.metadataStartMarker,
        jsonEncode(snapshot.toJson()),
        OutlookTaskMirrorSnapshot.metadataEndMarker,
      ].join('\n'),
    },
    'start': <String, dynamic>{
      'dateTime': start.toIso8601String(),
      'timeZone': 'Asia/Shanghai',
    },
    'end': <String, dynamic>{
      'dateTime': end.toIso8601String(),
      'timeZone': 'Asia/Shanghai',
    },
    if (location != null)
      'location': <String, dynamic>{
        'displayName': location,
      },
    'showAs': showAs,
    'lastModifiedDateTime': fixtureNow().toIso8601String(),
  };
}

class _MirrorHarness {
  const _MirrorHarness({
    required this.db,
    required this.graph,
    required this.calendarBooksRepository,
    required this.taskRepository,
    required this.bindingsRepository,
    required this.mirrorRepository,
  });

  final AppDatabase db;
  final _FakeGraphService graph;
  final CalendarBooksRepository calendarBooksRepository;
  final TaskRepository taskRepository;
  final OutlookSyncBindingsRepository bindingsRepository;
  final OutlookTaskMirrorRepository mirrorRepository;

  OutlookTaskMirrorSyncService get service => OutlookTaskMirrorSyncService(
        graphService: graph,
        taskRepository: taskRepository,
        calendarBooksRepository: calendarBooksRepository,
        taskListBindingsRepository: bindingsRepository,
        taskMirrorRepository: mirrorRepository,
      );

  Future<int> createTaskList({required String name}) {
    return insertFixtureTaskList(db, name: name);
  }

  Future<int> createTask({
    required int taskListId,
    required String summary,
  }) {
    return taskRepository.create(
      TaskItemsCompanion.insert(
        uid: 'task-$summary',
        dtstamp: fixtureNow(),
        summary: summary,
        taskListId: Value(taskListId),
        description: const Value('Local notes'),
        dtstart: Value(fixtureNow()),
        due: Value(fixtureNow().add(const Duration(hours: 1))),
      ),
      audit: false,
    );
  }

  Future<void> updateTaskSummary(int taskId, String summary) {
    return (db.update(db.taskItems)..where((task) => task.id.equals(taskId)))
        .write(TaskItemsCompanion(summary: Value(summary)));
  }

  Future<void> bindTaskList(int taskListId) {
    return bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: taskListId,
        remoteCalendarId: 'remote-$taskListId',
        remoteCalendarName: remoteCalendarName('Inbox'),
        linkedAt: fixtureNow(),
      ),
    );
  }

  String remoteCalendarName(String taskListName) {
    return OutlookSyncPolicy.buildManagedCalendarName(
      kind: OutlookManagedCalendarKind.taskMirrorBook,
      containerName: taskListName,
    );
  }

  OutlookTaskMirrorBinding bindingFor({
    required TaskItem task,
    required String taskListName,
    required OutlookTaskMirrorSnapshot snapshot,
    OutlookTaskMirrorSnapshot? remoteSnapshot,
    required String remoteEventId,
    OutlookTaskMirrorConflictState conflictState =
        OutlookTaskMirrorConflictState.none,
  }) {
    final resolvedRemoteSnapshot = remoteSnapshot ?? snapshot;
    return OutlookTaskMirrorBinding(
      localTaskId: task.id,
      localTaskListId: task.taskListId!,
      remoteCalendarId: 'remote-${task.taskListId}',
      remoteCalendarName: remoteCalendarName(taskListName),
      remoteEventId: remoteEventId,
      syncedAt: fixtureNow(),
      localSnapshotHash: snapshot.fingerprint,
      localSnapshotJson: snapshot.stableJson,
      remoteSnapshotHash: resolvedRemoteSnapshot.fingerprint,
      remoteSnapshotJson: resolvedRemoteSnapshot.stableJson,
      conflictState: conflictState,
      conflictMessage:
          conflictState == OutlookTaskMirrorConflictState.none ? null : 'mock',
      conflictDetectedAt: conflictState == OutlookTaskMirrorConflictState.none
          ? null
          : fixtureNow(),
    );
  }
}

class _CreateEventCall {
  const _CreateEventCall({
    required this.calendarId,
    required this.event,
    required this.isManagedContainer,
  });

  final String calendarId;
  final Map<String, dynamic> event;
  final bool isManagedContainer;
}

class _UpdateEventCall {
  const _UpdateEventCall({
    required this.calendarId,
    required this.eventId,
    required this.event,
    required this.isManagedContainer,
  });

  final String calendarId;
  final String eventId;
  final Map<String, dynamic> event;
  final bool isManagedContainer;
}

class _FakeGraphService extends MsGraphService {
  _FakeGraphService()
      : super(
          const OutlookConfig(clientId: 'mock-client'),
          syncMode: OutlookSyncMode.bidirectional,
        );

  final createEventCalls = <_CreateEventCall>[];
  final updateEventCalls = <_UpdateEventCall>[];
  final events = <String, Map<String, dynamic>?>{};
  final updateFailures = <String>{};
  bool returnNullOnCreate = false;

  @override
  Future<Map<String, dynamic>?> createEvent(
    Map<String, dynamic> event, {
    required String calendarId,
    required bool isFlowPlanV2ManagedContainer,
  }) async {
    createEventCalls.add(
      _CreateEventCall(
        calendarId: calendarId,
        event: event,
        isManagedContainer: isFlowPlanV2ManagedContainer,
      ),
    );
    if (returnNullOnCreate) {
      return null;
    }
    final id = 'created-${createEventCalls.length}';
    final created = <String, dynamic>{
      ...event,
      'id': id,
      'lastModifiedDateTime': fixtureNow().toIso8601String(),
    };
    events['$calendarId/$id'] = created;
    return created;
  }

  @override
  Future<bool> updateEvent({
    required String calendarId,
    required String eventId,
    required Map<String, dynamic> event,
    required bool isFlowPlanV2ManagedContainer,
  }) async {
    updateEventCalls.add(
      _UpdateEventCall(
        calendarId: calendarId,
        eventId: eventId,
        event: event,
        isManagedContainer: isFlowPlanV2ManagedContainer,
      ),
    );
    if (updateFailures.contains(eventId)) {
      return false;
    }
    events['$calendarId/$eventId'] = <String, dynamic>{
      ...event,
      'id': eventId,
      'lastModifiedDateTime': fixtureNow().toIso8601String(),
    };
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getEvent({
    required String calendarId,
    required String eventId,
  }) async {
    return events['$calendarId/$eventId'];
  }
}
