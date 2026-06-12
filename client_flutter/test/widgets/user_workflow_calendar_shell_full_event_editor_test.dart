import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/presentation/event_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/calendar_shell_quick_add_harness.dart';
import '../test_support/fixtures.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('quick add opens the full event editor from the shell',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await insertFixtureCalendar(db, name: 'Full event editor calendar');

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.timeline,
      size: const Size(900, 1000),
      overrides: [
        quickAddEmptyScheduleSegmentsOverride(),
      ],
    );

    await openQuickAdd(tester);
    await tapQuickAddEventTab(tester);
    await tapQuickAddReachable(tester, find.byType(OutlinedButton).last);
    await pumpQuickAddFrames(tester);

    expect(find.byType(EventDetailPage), findsOneWidget);
    expect(find.byKey(AppKeys.eventSummaryField), findsOneWidget);
    await disposeCurrentQuickAddApp(tester);
  });
}
