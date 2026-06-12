import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/fixtures.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('shell navigation switches every destination', (tester) async {
    await pumpShellNavigationHarness(
      tester,
      size: const Size(390, 844),
    );

    expect(find.text('timeline route'), findsOneWidget);

    await tapShellDestination(tester, AppKeys.shellWeek);
    expect(find.text('week route'), findsOneWidget);

    await tapShellDestination(tester, AppKeys.shellMonth);
    expect(find.text('month route'), findsOneWidget);

    await tapShellDestination(tester, AppKeys.shellTracker);
    expect(find.text('tracker route'), findsOneWidget);

    await tapShellDestination(tester, AppKeys.shellReports);
    expect(find.text('reports route'), findsOneWidget);

    await tapShellDestination(tester, AppKeys.shellFiles);
    expect(find.text('files route'), findsOneWidget);

    await tapShellDestination(tester, AppKeys.shellSettings);
    expect(find.text('settings route'), findsOneWidget);

    await tapShellDestination(tester, AppKeys.shellTimeline);
    expect(find.text('timeline route'), findsWidgets);
  });

  testWidgets('shell create button opens quick add and ignores blank saves',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureTaskList(db, name: 'Controls tasks');
    await insertFixtureCalendar(db, name: 'Controls calendar');
    final fakeStore = FakeTaskEventServerFirstStore();

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(900, 1000),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
        taskEventServerFirstStoreProvider.overrideWith(
          (ref) async => fakeStore,
        ),
      ],
    );

    await openQuickAdd(tester);
    await tapQuickAddReachable(tester, find.byKey(AppKeys.taskSaveButton));
    await pumpQuickAddFrames(tester);

    expect(find.byKey(AppKeys.taskSummaryField), findsOneWidget);
    expect(fakeStore.createdTasks, isEmpty);

    await tapQuickAddEventTab(tester);
    await tapQuickAddReachable(tester, find.byKey(AppKeys.eventSaveButton));
    await pumpQuickAddFrames(tester);

    expect(find.byKey(AppKeys.eventSummaryField), findsOneWidget);
    expect(fakeStore.createdEvents, isEmpty);

    await disposeCurrentQuickAddApp(tester);
  });
}
