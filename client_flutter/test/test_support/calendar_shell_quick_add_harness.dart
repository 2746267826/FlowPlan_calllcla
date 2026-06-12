import 'dart:async';

import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpQuickAddUntil(
  WidgetTester tester,
  FutureOr<bool> Function() condition, {
  required String reason,
}) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (await condition()) {
      return;
    }
  }
  fail(reason);
}

Future<void> pumpQuickAddFrames(
  WidgetTester tester, [
  int count = 6,
]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> disposeCurrentQuickAddApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Override quickAddEmptyScheduleSegmentsOverride() {
  return taskScheduleSegmentsForSelectedDateProvider.overrideWith(
    (ref) => Stream.value(const <TaskScheduleSegmentWithTask>[]),
  );
}

Future<void> openQuickAdd(WidgetTester tester) async {
  await tester.tap(find.byKey(AppKeys.shellCreateTask));
  await pumpQuickAddUntil(
    tester,
    () => find.byType(TabBar).evaluate().length == 1,
    reason: 'quick add sheet should open',
  );
  await pumpQuickAddFrames(tester, 8);
}

Future<void> waitForQuickAddClosed(WidgetTester tester) async {
  tester.testTextInput.hide();
  await pumpQuickAddUntil(
    tester,
    () => find.byType(TabBar).evaluate().isEmpty,
    reason: 'quick add sheet should close',
  );
  await pumpQuickAddFrames(tester, 3);
}

Future<void> tapQuickAddEventTab(WidgetTester tester) async {
  final eventTab = find.byKey(AppKeys.quickAddEventTab);
  expect(eventTab, findsOneWidget);
  await tapQuickAddReachable(tester, eventTab);
  await pumpQuickAddFrames(tester);
  await pumpQuickAddUntil(
    tester,
    () => find.byKey(AppKeys.eventSummaryField).evaluate().isNotEmpty,
    reason: 'event tab should show the event summary field',
  );
}

Future<void> tapQuickAddReachable(
  WidgetTester tester,
  Finder finder,
) async {
  final element = finder.evaluate().single;
  await Scrollable.ensureVisible(
    element,
    alignment: 0.55,
    duration: Duration.zero,
  );
  await pumpQuickAddFrames(tester, 3);
  final target = finder.hitTestable();
  expect(target, findsOneWidget);
  await tester.tap(target);
  await tester.pump();
}

WeeklyWorkSchedule alwaysOpenWorkSchedule() {
  return WeeklyWorkSchedule({
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
      weekday: const [
        WorkTimeRange(startMinute: 0, endMinute: 24 * 60),
      ],
  });
}
