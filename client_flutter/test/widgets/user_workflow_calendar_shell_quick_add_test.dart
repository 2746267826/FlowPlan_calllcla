import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/fixtures.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('quick add saves a task and an event through the shell',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureTaskList(db, name: 'Quick tasks');
    await insertFixtureCalendar(db, name: 'Quick calendar');
    final fakeStore = FakeTaskEventServerFirstStore();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(900, 1000),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
        taskEventServerFirstStoreProvider
            .overrideWith((ref) async => fakeStore),
      ],
    );

    await openQuickAdd(tester);
    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'Quick task from shell',
    );
    await tapQuickAddReachable(tester, find.byKey(AppKeys.taskSaveButton));
    await pumpQuickAddUntil(
      tester,
      () => fakeStore.createdTasks.isNotEmpty,
      reason: 'quick task create should reach the server-first store',
    );
    await waitForQuickAddClosed(tester);

    expect(fakeStore.createdTasks.single['summary'], 'Quick task from shell');
    expect(fakeStore.createdTasks.single['taskListId'], isA<int>());
    expect(fakeStore.createdTasks.single['durationMinutes'], 60);

    await openQuickAdd(tester);
    await tapQuickAddEventTab(tester);
    await tester.enterText(
      find.byKey(AppKeys.eventSummaryField),
      'Quick event from shell',
    );
    await tapQuickAddReachable(tester, find.byKey(AppKeys.eventSaveButton));
    await pumpQuickAddUntil(
      tester,
      () => fakeStore.createdEvents.isNotEmpty,
      reason: 'quick event create should reach the server-first store',
    );
    await waitForQuickAddClosed(tester);

    expect(fakeStore.createdEvents.single['summary'], 'Quick event from shell');
    expect(fakeStore.createdEvents.single['eventCalendarId'], isA<int>());
    expect(fakeStore.createdEvents.single['startAt'], isA<String>());
    expect(fakeStore.createdEvents.single['endAt'], isA<String>());
    await disposeCurrentQuickAddApp(tester);
  });
}
