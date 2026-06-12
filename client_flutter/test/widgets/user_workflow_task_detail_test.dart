import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fixtures.dart';
import '../test_support/task_detail_workflow_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('task detail creates a task and saves the payload',
      (tester) async {
    final db = createTestDatabase();
    final fakeStore = FakeTaskEventServerFirstStore();
    final taskListId = await insertFixtureTaskList(
      db,
      name: 'Create task list',
    );

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
      'Created Task Title',
    );
    await tester.tap(find.text('Create task list'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Created notes');
    await tester.enterText(find.byType(TextField).at(2), 'Created room');
    await tapTaskDetailChoiceChip(tester, '2 \u5c0f\u65f6');
    await tapTaskDetailChoiceChip(tester, '\u9ad8');
    await tapTaskDetailChoiceChip(tester, '\u6bcf\u5468');
    await tapTaskDetailChoiceChip(tester, '30 \u5206\u949f', last: true);
    await tapTaskDetailSwitchListTile(tester, '\u81ea\u52a8\u6392\u7a0b');
    await tapTaskDetailSwitchListTile(tester, '\u5141\u8bb8\u62c6\u5206');
    await tapTaskDetailSwitchListTile(tester, '\u9501\u5b9a\u6392\u7a0b');

    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await pumpUntilTaskCreated(tester, fakeStore);
    await pumpUntilFound(tester, find.text('timeline fallback'));

    expect(fakeStore.createdTasks, hasLength(1));
    final payload = fakeStore.createdTasks.single;
    expect(
      payload['uid'],
      isA<String>().having((uid) => uid, 'uid', isNotEmpty),
    );
    expect(payload['summary'], 'Created Task Title');
    expect(payload['title'], 'Created Task Title');
    expect(payload['description'], 'Created notes');
    expect(payload['location'], 'Created room');
    expect(payload['durationMinutes'], 120);
    expect(payload['priorityLocal'], 1);
    expect(payload['rrule'], 'FREQ=WEEKLY');
    expect(payload['reminderMinutesBefore'], 30);
    expect(payload['isAutoScheduled'], isFalse);
    expect(payload['isSplittable'], isTrue);
    expect(payload['isLocked'], isTrue);
    expect(payload['taskListId'], taskListId);
  });
}
