import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/fixtures.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('shell navigation switches between calendar views',
      (tester) async {
    await pumpShellNavigationHarness(
      tester,
      size: const Size(1300, 900),
    );

    expect(find.text('timeline route'), findsWidgets);

    await tapShellDestination(tester, AppKeys.shellWeek);
    expect(find.text('week route'), findsWidgets);

    await tapShellDestination(tester, AppKeys.shellMonth);
    expect(find.text('month route'), findsWidgets);

    await tapShellDestination(tester, AppKeys.shellTimeline);
    expect(find.text('timeline route'), findsWidgets);

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('empty timeline keeps primary actions and date controls working',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(1300, 900),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
      ],
    );
    await pumpQuickAddFrames(tester);

    expect(find.byKey(AppKeys.shellCreateTask), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    final initialDate = _selectedDate(tester);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await pumpQuickAddFrames(tester);
    expect(
        _selectedDate(tester), initialDate.subtract(const Duration(days: 1)));
    expect(find.text('今日'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await pumpQuickAddFrames(tester);
    expect(_selectedDate(tester), initialDate);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await pumpQuickAddFrames(tester);
    expect(_selectedDate(tester), initialDate.add(const Duration(days: 1)));

    await tester.tap(find.text('今日'));
    await pumpQuickAddFrames(tester);
    expect(_selectedDate(tester), _today());

    await disposeCurrentQuickAddApp(tester);
  });

  testWidgets('quick add event tab can be dismissed without creating data',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureTaskList(db, name: 'Dismiss tasks');
    await insertFixtureCalendar(db, name: 'Dismiss calendar');
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
    await tapQuickAddEventTab(tester);
    await tester.enterText(
      find.byKey(AppKeys.eventSummaryField),
      'Dismissed event draft',
    );
    await tester.tapAt(const Offset(20, 20));
    await waitForQuickAddClosed(tester);

    expect(fakeStore.createdEvents, isEmpty);
    expect(fakeStore.createdTasks, isEmpty);

    await disposeCurrentQuickAddApp(tester);
  });
}

DateTime _selectedDate(WidgetTester tester) {
  return _container(tester).read(selectedDateProvider);
}

ProviderContainer _container(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byKey(AppKeys.shellCreateTask)),
  );
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}
