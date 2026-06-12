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
  testWidgets('task detail edits an existing task and saves the patch',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = FakeTaskEventServerFirstStore();
    final taskListId = await insertFixtureTaskList(
      db,
      name: 'Detail task list',
    );
    final taskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-detail-edit',
            dtstamp: fixtureNow(),
            summary: 'Original Task Title',
            taskListId: Value(taskListId),
            description: const Value('Original description'),
            location: const Value('Original location'),
            durationMinutes: const Value(60),
            priorityLocal: const Value(2),
            isAutoScheduled: const Value(true),
            isSplittable: const Value(false),
            isLocked: const Value(false),
            rrule: const Value('FREQ=DAILY'),
            reminderMinutesBefore: const Value(15),
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

    final summaryField =
        tester.widget<TextField>(find.byKey(AppKeys.taskSummaryField));
    expect(summaryField.controller?.text, 'Original Task Title');

    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'Updated Task Title',
    );
    await tester.enterText(find.byType(TextField).at(1), 'Updated description');
    await tester.enterText(find.byType(TextField).at(2), 'Updated location');
    await tapTaskDetailChoiceChip(tester, '2 \u5c0f\u65f6');
    await tapTaskDetailChoiceChip(tester, '\u4f4e');
    await tapTaskDetailChoiceChip(tester, '\u6bcf\u5468');
    await tapTaskDetailChoiceChip(tester, '1 \u5c0f\u65f6', last: true);
    await tapTaskDetailSwitchListTile(tester, '\u81ea\u52a8\u6392\u7a0b');
    await tapTaskDetailSwitchListTile(tester, '\u5141\u8bb8\u62c6\u5206');
    await tapTaskDetailSwitchListTile(tester, '\u9501\u5b9a\u6392\u7a0b');

    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await pumpUntilTaskUpdated(tester, fakeStore);
    await pumpUntilFound(tester, find.text('timeline fallback'));

    expect(fakeStore.updatedTasks, hasLength(1));
    expect(fakeStore.updatedTasks.single.localId, taskId);
    expect(
      fakeStore.updatedTasks.single.payload['summary'],
      'Updated Task Title',
    );
    expect(
      fakeStore.updatedTasks.single.payload['description'],
      'Updated description',
    );
    expect(
      fakeStore.updatedTasks.single.payload['location'],
      'Updated location',
    );
    expect(fakeStore.updatedTasks.single.payload['durationMinutes'], 120);
    expect(fakeStore.updatedTasks.single.payload['priorityLocal'], 3);
    expect(fakeStore.updatedTasks.single.payload['rrule'], 'FREQ=WEEKLY');
    expect(fakeStore.updatedTasks.single.payload['reminderMinutesBefore'], 60);
    expect(fakeStore.updatedTasks.single.payload['isAutoScheduled'], isFalse);
    expect(fakeStore.updatedTasks.single.payload['isSplittable'], isTrue);
    expect(fakeStore.updatedTasks.single.payload['isLocked'], isTrue);
    expect(fakeStore.updatedTasks.single.payload['taskListId'], taskListId);
    expect(
      fakeStore.updatedTasks.single.changedFields,
      containsAll(<String>[
        'summary',
        'description',
        'location',
        'durationMinutes',
        'priorityLocal',
        'rrule',
        'reminderMinutesBefore',
        'isAutoScheduled',
        'isSplittable',
        'isLocked',
        'taskListId',
      ]),
    );
  });
}
