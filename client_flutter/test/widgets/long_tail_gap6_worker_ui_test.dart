import 'dart:async';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flowplanv2/core/server_first/task_event_server_first_store.dart';
import 'package:flowplanv2/features/task/presentation/unscheduled_task_panel.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnscheduledTaskPanel gap6 worker', () {
    testWidgets('shows loading and stream errors from task provider',
        (tester) async {
      final tasks = StreamController<List<TaskItem>>();
      addTearDown(tasks.close);

      await _pumpPanel(
        tester,
        tasks: tasks.stream,
        taskLists: Stream<List<TaskList>>.value(const <TaskList>[]),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      tasks.addError(StateError('task stream offline'));
      await tester.pump();

      expect(find.textContaining('task stream offline'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows empty inbox when every task is already scheduled',
        (tester) async {
      await _pumpPanel(
        tester,
        tasks: Stream<List<TaskItem>>.value(<TaskItem>[
          _task(id: 1, summary: 'Scheduled task', start: DateTime(2026, 6, 11)),
        ]),
        taskLists: Stream<List<TaskList>>.value(const <TaskList>[]),
      );
      await tester.pump();

      expect(find.text('收集箱 / 未排程'), findsOneWidget);
      expect(find.text('所有任务均已排入日程'), findsOneWidget);
      expect(find.text('Scheduled task'), findsNothing);
    });

    testWidgets('renders unscheduled task metadata and starts detail dialog',
        (tester) async {
      await _pumpPanel(
        tester,
        tasks: Stream<List<TaskItem>>.value(<TaskItem>[
          _task(
            id: 2,
            summary: 'Plan review',
            start: null,
            due: DateTime(2026, 6, 18),
            priorityLocal: 1,
            taskListId: 7,
          ),
          _task(
            id: 3,
            summary: 'Already on calendar',
            start: DateTime(2026, 6, 11, 10),
            taskListId: 7,
          ),
        ]),
        taskLists: Stream<List<TaskList>>.value(<TaskList>[
          _taskList(id: 7, name: 'Focus', colorHex: 'not-a-color', emoji: 'F'),
        ]),
        detailBuilder: (context, task) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Detail opened for ${task.summary}'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Plan review'), findsOneWidget);
      expect(find.text('Already on calendar'), findsNothing);
      expect(find.text('F Focus'), findsOneWidget);
      expect(find.text('45 分钟'), findsOneWidget);
      expect(find.text('6/18'), findsOneWidget);

      await tester.tap(find.text('Plan review'));
      await tester.pump();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Detail opened for Plan review'), findsOneWidget);

      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required Stream<List<TaskItem>> tasks,
  required Stream<List<TaskList>> taskLists,
  UnscheduledTaskDetailBuilder? detailBuilder,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        allTasksProvider.overrideWith((ref) => tasks),
        allTaskListsProvider.overrideWith((ref) => taskLists),
        taskEventServerFirstStoreProvider.overrideWith(
          (ref) async => _Gap6TaskEventStore(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 520,
            child: UnscheduledTaskPanel(detailBuilder: detailBuilder),
          ),
        ),
      ),
    ),
  );
}

class _Gap6TaskEventStore implements TaskEventServerFirstStore {
  @override
  Future<ServerFirstWriteResult> updateLocalTask({
    required int localId,
    required Map<String, Object?> patch,
    int? baseServerVersion,
    List<String>? changedFields,
  }) async {
    return ServerFirstWriteResult.canonical(
      <String, dynamic>{'id': localId, ...patch},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TaskItem _task({
  required int id,
  required String summary,
  required DateTime? start,
  DateTime? due,
  int priorityLocal = 2,
  int? taskListId,
}) {
  return TaskItem(
    id: id,
    uid: 'task-$id',
    dtstamp: DateTime(2026, 6, 11),
    summary: summary,
    description: null,
    location: null,
    dtstart: start,
    due: due,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: '[]',
    durationMinutes: 45,
    isSplittable: false,
    priorityLocal: priorityLocal,
    isAutoScheduled: false,
    taskListId: taskListId,
    isLocked: false,
    reminderMinutesBefore: 0,
  );
}

TaskList _taskList({
  required int id,
  required String name,
  required String colorHex,
  String? emoji,
}) {
  return TaskList(
    id: id,
    name: name,
    colorHex: colorHex,
    emoji: emoji,
    isVisible: true,
    isDefault: false,
    isArchived: false,
    createdAt: DateTime(2026, 6, 11),
  );
}
