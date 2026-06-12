import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fixtures.dart';
import '../test_support/task_detail_workflow_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('task create blocks empty titles without writing',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = FakeTaskEventServerFirstStore();
    await insertFixtureTaskList(db, name: 'Validation list');

    await pumpTaskDetailWorkflow(
      tester,
      db: db,
      taskId: null,
      fakeStore: fakeStore,
    );
    await pumpUntilFound(tester, find.byKey(AppKeys.taskSaveButton));

    expect(find.widgetWithIcon(IconButton, Icons.delete_outline), findsNothing);
    expect(
      tester.widget<TextButton>(find.byKey(AppKeys.taskSaveButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await pumpTaskDetailFrames(tester);

    expect(find.text('\u8bf7\u8f93\u5165\u4efb\u52a1\u6807\u9898'),
        findsOneWidget);
    expect(fakeStore.createdTasks, isEmpty);
    expect(
      tester.widget<TextButton>(find.byKey(AppKeys.taskSaveButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('task create blocks saving when no task list exists',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = FakeTaskEventServerFirstStore();

    await pumpTaskDetailWorkflow(
      tester,
      db: db,
      taskId: null,
      fakeStore: fakeStore,
      taskListsOverride: const <TaskList>[],
    );
    await pumpUntilFound(tester, find.byKey(AppKeys.taskSaveButton));
    await pumpTaskDetailFrames(tester, 8);

    expect(
      find.textContaining(
        '\u5f53\u524d\u6ca1\u6709\u53ef\u7528\u7684\u4efb\u52a1\u672c',
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'Needs a task list',
    );
    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await pumpTaskDetailFrames(tester);

    expect(
      find.textContaining('\u4efb\u52a1\u5fc5\u987b\u5f52\u5c5e'),
      findsOneWidget,
    );
    expect(fakeStore.createdTasks, isEmpty);
    expect(find.byKey(AppKeys.taskSummaryField), findsOneWidget);
  });

  testWidgets('close button cancels an edited task without saving',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = FakeTaskEventServerFirstStore();
    final taskListId = await insertFixtureTaskList(db, name: 'Cancel list');
    final taskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-detail-cancel',
            dtstamp: fixtureNow(),
            summary: 'Do not save me',
            taskListId: Value(taskListId),
          ),
        );

    await pumpTaskDetailWorkflow(
      tester,
      db: db,
      taskId: taskId,
      fakeStore: fakeStore,
    );
    await pumpUntilFound(tester, find.byKey(AppKeys.taskSummaryField));
    await pumpTaskDetailFrames(tester);

    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'Unsaved edit',
    );
    await tester.tap(find.byIcon(Icons.close).first);
    await pumpUntilFound(tester, find.text('timeline fallback'));

    expect(fakeStore.createdTasks, isEmpty);
    expect(fakeStore.updatedTasks, isEmpty);
    expect(fakeStore.deletedTaskIds, isEmpty);
  });

  testWidgets('deadline picker saves a due date in the create payload',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = FakeTaskEventServerFirstStore();
    await insertFixtureTaskList(db, name: 'Deadline list');

    await pumpTaskDetailWorkflow(
      tester,
      db: db,
      taskId: null,
      fakeStore: fakeStore,
    );
    await pumpUntilFound(tester, find.byKey(AppKeys.taskSummaryField));
    await pumpTaskDetailFrames(tester);

    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'Task with due date',
    );
    await _pickVisibleDeadlineDay(tester, '15');

    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await pumpUntilTaskCreated(tester, fakeStore);

    final dueAt = fakeStore.createdTasks.single['dueAt'];
    expect(dueAt, isA<String>());
    final parsedDue = DateTime.parse(dueAt! as String);
    expect(parsedDue.day, 15);
  });

  testWidgets('clearing an existing deadline saves a null due date patch',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = FakeTaskEventServerFirstStore();
    final taskListId = await insertFixtureTaskList(db, name: 'Clear due list');
    final taskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-detail-clear-due',
            dtstamp: fixtureNow(),
            summary: 'Clear due date',
            taskListId: Value(taskListId),
            due: Value(DateTime(2026, 6, 20, 14, 30)),
          ),
        );

    await pumpTaskDetailWorkflow(
      tester,
      db: db,
      taskId: taskId,
      fakeStore: fakeStore,
    );
    await pumpUntilFound(tester, find.byKey(AppKeys.taskSummaryField));
    await pumpTaskDetailFrames(tester);

    await _tapClearDeadline(tester, '2026\u5e746\u670820\u65e5 14:30');
    await pumpTaskDetailFrames(tester);

    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await pumpUntilTaskUpdated(tester, fakeStore);

    final update = fakeStore.updatedTasks.single;
    expect(update.localId, taskId);
    expect(update.payload['dueAt'], isNull);
    expect(update.changedFields, contains('dueAt'));
  });

  testWidgets(
      'task list defaults update auto scheduling unless reminder was edited',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = FakeTaskEventServerFirstStore();
    final books = CalendarBooksRepository(db);
    final firstListId = await db.into(db.taskLists).insert(
          TaskListsCompanion.insert(
            name: 'Defaults A',
            createdAt: fixtureNow(),
            isDefault: const Value(true),
          ),
        );
    final secondListId = await db.into(db.taskLists).insert(
          TaskListsCompanion.insert(
            name: 'Defaults B',
            createdAt: fixtureNow().add(const Duration(minutes: 1)),
          ),
        );
    await books.saveTaskListDefaults(
      id: firstListId,
      defaultIsAutoScheduled: false,
      defaultReminderMinutesBefore: 60,
      audit: false,
    );
    await books.saveTaskListDefaults(
      id: secondListId,
      defaultIsAutoScheduled: true,
      defaultReminderMinutesBefore: 5,
      audit: false,
    );

    await pumpTaskDetailWorkflow(
      tester,
      db: db,
      taskId: null,
      fakeStore: fakeStore,
    );
    await pumpUntilFound(tester, find.byKey(AppKeys.taskSummaryField));
    await pumpTaskDetailFrames(tester, 8);

    await _tapReminderChoiceChip(tester, '30 \u5206\u949f');
    await tester.ensureVisible(find.text('Defaults B'));
    await pumpTaskDetailFrames(tester, 2);
    await tester.tap(find.text('Defaults B'));
    await pumpTaskDetailFrames(tester, 8);
    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'Defaults aware task',
    );

    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await pumpUntilTaskCreated(tester, fakeStore);

    final payload = fakeStore.createdTasks.single;
    expect(payload['taskListId'], secondListId);
    expect(payload['isAutoScheduled'], isTrue);
    expect(payload['reminderMinutesBefore'], 30);
  });

  testWidgets('save failure keeps the form open and re-enables save',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = _FailingCreateStore(StateError('create boom'));
    await insertFixtureTaskList(db, name: 'Failing save list');

    await pumpTaskDetailWorkflow(
      tester,
      db: db,
      taskId: null,
      fakeStore: fakeStore,
    );
    await pumpUntilFound(tester, find.byKey(AppKeys.taskSummaryField));
    await pumpTaskDetailFrames(tester);

    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'Create will fail',
    );
    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await pumpTaskDetailFrames(tester, 8);

    expect(fakeStore.createAttempts, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byKey(AppKeys.taskSummaryField), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byKey(AppKeys.taskSaveButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('pending save disables the save button until it finishes',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = _PendingCreateStore();
    await insertFixtureTaskList(db, name: 'Pending save list');

    await pumpTaskDetailWorkflow(
      tester,
      db: db,
      taskId: null,
      fakeStore: fakeStore,
    );
    await pumpUntilFound(tester, find.byKey(AppKeys.taskSummaryField));
    await pumpTaskDetailFrames(tester);

    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'Pending task',
    );
    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await tester.pump();

    expect(fakeStore.createdTasks, hasLength(1));
    expect(
      tester.widget<TextButton>(find.byKey(AppKeys.taskSaveButton)).onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    fakeStore.complete();
    await pumpUntilFound(tester, find.text('timeline fallback'));
  });

  testWidgets('delete failure keeps detail open and re-enables buttons',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = _FailingDeleteStore(StateError('delete boom'));
    final taskListId = await insertFixtureTaskList(db, name: 'Delete failure');
    final taskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-delete-fails',
            dtstamp: fixtureNow(),
            summary: 'Delete fails',
            taskListId: Value(taskListId),
          ),
        );

    await pumpTaskDetailWorkflow(
      tester,
      db: db,
      taskId: taskId,
      fakeStore: fakeStore,
    );
    await pumpUntilFound(tester, find.byKey(AppKeys.taskSummaryField));
    await pumpTaskDetailFrames(tester);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpTaskDetailFrames(tester);
    await tester.tap(find.widgetWithText(TextButton, '\u5220\u9664').last);
    await pumpTaskDetailFrames(tester, 8);

    expect(fakeStore.deleteAttempts, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byKey(AppKeys.taskSummaryField), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester.widget<TextButton>(find.byKey(AppKeys.taskSaveButton)).onPressed,
      isNotNull,
    );
  });
}

Future<void> _pickVisibleDeadlineDay(
  WidgetTester tester,
  String dayLabel,
) async {
  tester.testTextInput.hide();
  await tester.pump();
  final tileText = find.text('\u8bbe\u7f6e\u622a\u6b62\u65f6\u95f4');
  await tester.ensureVisible(tileText);
  await pumpTaskDetailFrames(tester, 2);
  await tester.tap(
    find.ancestor(of: tileText, matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text(dayLabel),
        )
        .last,
  );
  await tester.pumpAndSettle();
  await _tapDialogConfirm(tester);
  await _tapDialogConfirm(tester);
}

Future<void> _tapDialogConfirm(WidgetTester tester) async {
  final ok = find.widgetWithText(TextButton, 'OK');
  final confirm = find.widgetWithText(TextButton, '\u786e\u5b9a');
  final target = ok.evaluate().isNotEmpty ? ok.last : confirm.last;
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tapClearDeadline(
  WidgetTester tester,
  String deadlineText,
) async {
  final text = find.text(deadlineText);
  await tester.ensureVisible(text);
  await pumpTaskDetailFrames(tester, 2);
  final tile = find.ancestor(of: text, matching: find.byType(InkWell)).first;
  final clearIcon =
      find.descendant(of: tile, matching: find.byIcon(Icons.close));
  expect(clearIcon, findsOneWidget);
  await tester.tap(clearIcon);
}

Future<void> _tapReminderChoiceChip(
  WidgetTester tester,
  String label,
) async {
  tester.testTextInput.hide();
  await tester.pump();
  await tester.ensureVisible(find.text('\u63d0\u524d\u63d0\u9192'));
  await pumpTaskDetailFrames(tester, 2);
  final chip = find.widgetWithText(ChoiceChip, label).last;
  await tester.ensureVisible(chip);
  await pumpTaskDetailFrames(tester, 2);
  final tappable = chip.hitTestable();
  expect(tappable, findsOneWidget);
  await tester.tap(tappable);
  await tester.pump();
}

class _FailingCreateStore extends FakeTaskEventServerFirstStore {
  _FailingCreateStore(this.error);

  final Object error;
  int createAttempts = 0;

  @override
  Future<ServerFirstWriteResult> createTask(
    Map<String, Object?> payload,
  ) async {
    createAttempts++;
    throw error;
  }
}

class _PendingCreateStore extends FakeTaskEventServerFirstStore {
  final Completer<ServerFirstWriteResult> _completer =
      Completer<ServerFirstWriteResult>();

  @override
  Future<ServerFirstWriteResult> createTask(
    Map<String, Object?> payload,
  ) {
    createdTasks.add(Map<String, Object?>.from(payload));
    return _completer.future;
  }

  void complete() {
    _completer.complete(
      ServerFirstWriteResult.canonical(
        <String, dynamic>{
          'serverVersion': 1,
          'item': <String, dynamic>{
            'id': 'task-pending',
            'uid': createdTasks.single['uid'],
            'payload': createdTasks.single,
          },
        },
      ),
    );
  }
}

class _FailingDeleteStore extends FakeTaskEventServerFirstStore {
  _FailingDeleteStore(this.error);

  final Object error;
  int deleteAttempts = 0;

  @override
  Future<ServerFirstWriteResult> deleteLocalTask({
    required int localId,
    int? baseServerVersion,
  }) async {
    deleteAttempts++;
    throw error;
  }
}
