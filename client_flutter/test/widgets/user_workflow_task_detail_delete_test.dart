import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fixtures.dart';
import '../test_support/task_detail_workflow_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('task detail delete supports cancel and confirm', (tester) async {
    final db = createTestDatabase();
    final fakeStore = FakeTaskEventServerFirstStore();
    final taskListId = await insertFixtureTaskList(
      db,
      name: 'Delete task list',
    );
    final taskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-detail-delete',
            dtstamp: fixtureNow(),
            summary: 'Delete Candidate Task',
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
    await tester.tap(find.widgetWithText(TextButton, '\u53d6\u6d88'));
    await pumpTaskDetailFrames(tester);

    expect(fakeStore.deletedTaskIds, isEmpty);
    expect(find.byKey(AppKeys.taskSummaryField), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpTaskDetailFrames(tester);
    await tester.tap(find.widgetWithText(TextButton, '\u5220\u9664').last);
    await pumpUntilTaskDeleted(tester, fakeStore);
    await pumpUntilFound(tester, find.text('timeline fallback'));

    expect(fakeStore.deletedTaskIds, <int>[taskId]);
  });
}
