import 'package:drift/drift.dart' hide isNotNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/fixtures.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('auto schedule applies a confirmed draft from the shell',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final taskListId = await insertFixtureTaskList(
      db,
      name: 'Auto schedule list',
    );
    final taskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'auto-schedule-task',
            dtstamp: fixtureNow(),
            summary: 'Task needing schedule',
            taskListId: Value(taskListId),
            durationMinutes: const Value(30),
            isAutoScheduled: const Value(true),
          ),
        );

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(1300, 900),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
        weeklyWorkScheduleProvider.overrideWithValue(alwaysOpenWorkSchedule()),
      ],
    );

    await tester.tap(find.byIcon(Icons.auto_awesome));
    await pumpQuickAddFrames(tester);
    await tester.tap(find.byType(SimpleDialogOption).last);
    await pumpQuickAddFrames(tester);
    await tester.tap(find.byType(FilledButton).last);
    await pumpQuickAddUntil(
      tester,
      () async {
        final scheduledTask = await (db.select(db.taskItems)
              ..where((row) => row.id.equals(taskId)))
            .getSingle();
        return scheduledTask.dtstart != null;
      },
      reason: 'confirmed schedule draft should be applied',
    );

    final scheduledTask = await (db.select(db.taskItems)
          ..where((row) => row.id.equals(taskId)))
        .getSingle();
    expect(scheduledTask.dtstart, isNotNull);
    expect(scheduledTask.dtstart!.hour, 0);
    expect(scheduledTask.dtstart!.minute, 0);
    await disposeCurrentQuickAddApp(tester);
  });
}
