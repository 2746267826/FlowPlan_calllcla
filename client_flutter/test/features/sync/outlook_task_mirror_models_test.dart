import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_snapshot.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  group('OutlookTaskMirrorSnapshot', () {
    test('extracts metadata only from valid marked JSON payloads', () {
      final snapshot = _snapshot(summary: 'Original');
      final body = [
        'Visible notes',
        OutlookTaskMirrorSnapshot.metadataStartMarker,
        jsonEncode(snapshot.toJson()),
        OutlookTaskMirrorSnapshot.metadataEndMarker,
      ].join('\n');

      expect(
        OutlookTaskMirrorSnapshot.tryExtractMetadata(body),
        containsPair('summary', 'Original'),
      );
      expect(OutlookTaskMirrorSnapshot.tryExtractMetadata(null), isNull);
      expect(
          OutlookTaskMirrorSnapshot.tryExtractMetadata('plain body'), isNull);
      expect(
        OutlookTaskMirrorSnapshot.tryExtractMetadata(
          '${OutlookTaskMirrorSnapshot.metadataStartMarker}\n{bad',
        ),
        isNull,
      );
    });

    test('fromJson applies defaults and trims user-controlled strings', () {
      final snapshot = OutlookTaskMirrorSnapshot.fromJson({
        'task_id': 42,
        'task_uid': ' uid-42 ',
        'task_list_name': ' Inbox ',
        'summary': ' Title ',
        'description': ' Notes ',
        'location': ' Room ',
        'dtstart': fixtureNow().toIso8601String(),
      });

      expect(snapshot.taskId, 42);
      expect(snapshot.taskUid, 'uid-42');
      expect(snapshot.taskListName, 'Inbox');
      expect(snapshot.summary, 'Title');
      expect(snapshot.description, 'Notes');
      expect(snapshot.location, 'Room');
      expect(snapshot.status, 'NEEDS-ACTION');
      expect(snapshot.durationMinutes, 60);
      expect(snapshot.priorityLocal, 2);
      expect(snapshot.percentComplete, 0);
      expect(snapshot.isAutoScheduled, isTrue);
      expect(snapshot.isSplittable, isFalse);
      expect(snapshot.isLocked, isFalse);
      expect(snapshot.reminderMinutesBefore, 15);
      expect(snapshot.dtstart, fixtureNow().toLocal());
    });

    test('fromRemoteMirrorEvent merges Outlook fields over embedded metadata',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final taskListId = await insertFixtureTaskList(db, name: 'Inbox');
      final taskRepository = TaskRepository(db);
      final taskId = await taskRepository.create(
        TaskItemsCompanion.insert(
          uid: 'task-remote',
          dtstamp: fixtureNow(),
          summary: 'Local title',
          taskListId: Value(taskListId),
          description: const Value('Local notes'),
          location: const Value('Local room'),
          dtstart: Value(fixtureNow()),
          due: Value(fixtureNow().add(const Duration(hours: 1))),
        ),
        audit: false,
      );
      final task = await taskRepository.getById(taskId);
      final base = OutlookTaskMirrorSnapshot.fromTask(
        task: task!,
        taskListName: 'Inbox',
      );
      final start = fixtureNow().add(const Duration(hours: 3));
      final end = start.add(const Duration(minutes: 90));
      const descriptionMarker = '\u4e8c\u3001\u4efb\u52a1\u63cf\u8ff0';

      final remote = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
        task: task,
        taskListName: 'Inbox',
        event: {
          'subject': ' Remote title ',
          'body': {
            'content': [
              descriptionMarker,
              'Remote notes',
              '---',
              OutlookTaskMirrorSnapshot.metadataStartMarker,
              jsonEncode(base.toJson()),
              OutlookTaskMirrorSnapshot.metadataEndMarker,
            ].join('\n'),
          },
          'location': {'displayName': ' Remote room '},
          'start': {'dateTime': start.toIso8601String()},
          'end': {'dateTime': end.toIso8601String()},
          'showAs': 'free',
        },
      );

      expect(remote.taskId, taskId);
      expect(remote.taskUid, 'task-remote');
      expect(remote.taskListId, taskListId);
      expect(remote.taskListName, 'Inbox');
      expect(remote.summary, 'Remote title');
      expect(remote.description, 'Remote notes');
      expect(remote.location, 'Remote room');
      expect(remote.status, 'COMPLETED');
      expect(remote.durationMinutes, 90);
      expect(remote.dtstart, start.toLocal());
      expect(remote.due, end.toLocal());
    });

    test('changed field helpers report missing, invalid, and changed snapshots',
        () {
      final previous = _snapshot(summary: 'Before');
      final current = previous.copyWith(
        summary: 'After',
        durationMinutes: 120,
      );

      expect(
        OutlookTaskMirrorSnapshot.changedFieldLabels(
          previousSnapshotJson: null,
          current: current,
        ),
        hasLength(1),
      );
      expect(
        OutlookTaskMirrorSnapshot.changedFieldLabels(
          previousSnapshotJson: '{bad',
          current: current,
        ),
        hasLength(1),
      );
      expect(
        OutlookTaskMirrorSnapshot.changedFieldLabels(
          previousSnapshotJson: previous.stableJson,
          current: current,
        ),
        containsAll(<String>['\u6807\u9898', '\u9884\u8ba1\u65f6\u957f']),
      );
      expect(
        OutlookTaskMirrorSnapshot.changedFieldLabelsBetween(
          leftSnapshotJson: previous.stableJson,
          rightSnapshotJson: current.stableJson,
        ),
        containsAll(<String>['\u6807\u9898', '\u9884\u8ba1\u65f6\u957f']),
      );
      expect(
        OutlookTaskMirrorSnapshot.changedFieldLabelsBetween(
          leftSnapshotJson: previous.stableJson,
          rightSnapshotJson: null,
        ),
        hasLength(1),
      );
    });

    test('copyWith keeps summary when no replacement is provided', () {
      final snapshot = _snapshot(summary: 'Keep me');

      final copied = snapshot.copyWith();

      expect(copied.summary, 'Keep me');
      expect(copied.stableJson, snapshot.stableJson);
    });
  });

  group('Outlook task mirror bindings', () {
    test('conflict state storage values round-trip with safe defaults', () {
      for (final state in OutlookTaskMirrorConflictState.values) {
        expect(
          outlookTaskMirrorConflictStateFromStorage(state.storageValue),
          state,
        );
        expect(state.label, isNotEmpty);
      }

      expect(
        outlookTaskMirrorConflictStateFromStorage('unknown'),
        OutlookTaskMirrorConflictState.none,
      );
      expect(
        outlookTaskMirrorConflictStateFromStorage(null),
        OutlookTaskMirrorConflictState.none,
      );
    });

    test('binding map decoding filters malformed or incomplete entries', () {
      final valid = _binding(localTaskId: 7, localTaskListId: 3);
      final raw = jsonEncode([
        valid.toJson(),
        {'local_task_id': 0, 'remote_calendar_id': 'remote'},
        {'local_task_id': 8, 'local_task_list_id': 3, 'remote_event_id': 'e'},
        'not a binding',
      ]);

      final decoded = OutlookTaskMirrorBinding.decodeMap(raw);

      expect(decoded.keys, <int>[7]);
      expect(decoded[7]!.remoteCalendarId, 'remote-3');
      expect(OutlookTaskMirrorBinding.decodeMap(''), isEmpty);
      expect(OutlookTaskMirrorBinding.decodeMap('{bad'), isEmpty);
    });

    test('binding conflict helpers preserve snapshots and clear resolved state',
        () {
      final snapshot = _snapshot(summary: 'Local');
      final binding = _binding(
        localTaskId: 7,
        localTaskListId: 3,
        localSnapshotHash: snapshot.fingerprint,
        localSnapshotJson: snapshot.stableJson,
      );

      final conflicted = binding.markConflict(
        state: OutlookTaskMirrorConflictState.divergent,
        message: ' needs review ',
        detectedAt: fixtureNow(),
      );
      expect(
          conflicted.conflictState, OutlookTaskMirrorConflictState.divergent);
      expect(conflicted.conflictMessage, 'needs review');
      expect(conflicted.localSnapshotHash, snapshot.fingerprint);

      final resolved = conflicted.markResolved(
        syncedAt: fixtureNow().add(const Duration(minutes: 1)),
        localSnapshotHash: snapshot.fingerprint,
        localSnapshotJson: snapshot.stableJson,
        remoteSnapshotHash: snapshot.fingerprint,
        remoteSnapshotJson: snapshot.stableJson,
        remoteLastModifiedAt: fixtureNow(),
      );
      expect(resolved.conflictState, OutlookTaskMirrorConflictState.none);
      expect(resolved.conflictMessage, isNull);
      expect(resolved.conflictDetectedAt, isNull);
      expect(resolved.remoteLastModifiedAt, fixtureNow());
    });

    test('task list binding decode filters invalid entries', () {
      final valid = OutlookTaskListBinding(
        localTaskListId: 5,
        remoteCalendarId: ' remote-5 ',
        remoteCalendarName: ' FlowPlanV2 ',
        linkedAt: fixtureNow(),
      );
      final raw = jsonEncode([
        valid.toJson(),
        {'local_task_list_id': 0, 'remote_calendar_id': 'remote'},
        {'local_task_list_id': 6, 'remote_calendar_name': 'name'},
      ]);

      final decoded = OutlookTaskListBinding.decodeMap(raw);

      expect(decoded.keys, <int>[5]);
      expect(decoded[5]!.remoteCalendarId, 'remote-5');
      expect(decoded[5]!.remoteCalendarName, 'FlowPlanV2');
      expect(OutlookTaskListBinding.decodeMap(null), isEmpty);
      expect(OutlookTaskListBinding.decodeMap('{bad'), isEmpty);
    });
  });

  group('OutlookTaskMirrorRepository', () {
    test('saves, replaces, removes, and counts persisted mirror bindings',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = OutlookTaskMirrorRepository(db);

      await repository.saveTaskMirrorBinding(
        _binding(localTaskId: 1, localTaskListId: 10),
      );
      await repository.saveTaskMirrorBinding(
        _binding(localTaskId: 2, localTaskListId: 10),
      );
      await repository.saveTaskMirrorBinding(
        _binding(
          localTaskId: 2,
          localTaskListId: 20,
          remoteCalendarId: 'remote-replaced',
        ),
      );

      expect(await repository.countTaskMirrorBindingsForTaskList(10), 1);
      expect(await repository.countTaskMirrorBindingsForTaskList(20), 1);
      expect(
        (await repository.getTaskMirrorBinding(2))!.remoteCalendarId,
        'remote-replaced',
      );

      await repository.removeTaskMirrorBindings(<int>[1, 999]);
      expect((await repository.loadTaskMirrorBindings()).keys, <int>[2]);

      await repository.removeTaskMirrorBinding(2);
      expect(await repository.loadTaskMirrorBindings(), isEmpty);
    });
  });
}

OutlookTaskMirrorSnapshot _snapshot({
  String summary = 'Task',
  int durationMinutes = 60,
}) {
  return OutlookTaskMirrorSnapshot(
    taskId: 1,
    taskUid: 'task-1',
    taskListId: 2,
    taskListName: 'Inbox',
    summary: summary,
    description: 'Notes',
    location: 'Room',
    status: 'NEEDS-ACTION',
    dtstart: fixtureNow(),
    due: fixtureNow().add(Duration(minutes: durationMinutes)),
    completed: null,
    durationMinutes: durationMinutes,
    priorityLocal: 2,
    percentComplete: 0,
    isAutoScheduled: true,
    isSplittable: false,
    isLocked: false,
    reminderMinutesBefore: 15,
  );
}

OutlookTaskMirrorBinding _binding({
  required int localTaskId,
  required int localTaskListId,
  String? remoteCalendarId,
  String? localSnapshotHash,
  String? localSnapshotJson,
}) {
  return OutlookTaskMirrorBinding(
    localTaskId: localTaskId,
    localTaskListId: localTaskListId,
    remoteCalendarId: remoteCalendarId ?? 'remote-$localTaskListId',
    remoteCalendarName: 'FlowPlanV2 task list',
    remoteEventId: 'event-$localTaskId',
    syncedAt: fixtureNow(),
    localSnapshotHash: localSnapshotHash,
    localSnapshotJson: localSnapshotJson,
  );
}
