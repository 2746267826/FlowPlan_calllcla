import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/presentation/event_detail_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/task_detail_workflow_harness.dart'
    show writableOnlinePrimaryPolicy;
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('event detail edits an existing event and saves the patch',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await insertFixtureCalendar(
      db,
      name: 'Detail calendar',
    );
    final eventId = await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'event-detail-edit',
            dtstamp: fixtureNow(),
            summary: 'Original Event Title',
            dtstart: DateTime.utc(2026, 6, 10, 9),
            dtend: Value(DateTime.utc(2026, 6, 10, 10)),
            eventCalendarId: Value(calendarId),
            location: const Value('Original room'),
            description: const Value('Original notes'),
          ),
        );

    await _pumpEventDetail(
      tester,
      db: db,
      eventId: eventId,
      fakeStore: fakeStore,
    );
    await pumpUntilFound(tester, find.byKey(AppKeys.eventSummaryField));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final summaryField =
        tester.widget<TextField>(find.byKey(AppKeys.eventSummaryField));
    expect(summaryField.controller?.text, 'Original Event Title');

    await tester.enterText(
      find.byKey(AppKeys.eventSummaryField),
      'Updated Event Title',
    );
    await tester.tap(find.byKey(AppKeys.eventSaveButton));
    await _pumpUntilEventUpdated(tester, fakeStore);
    await pumpUntilFound(tester, find.text('timeline fallback'));

    expect(fakeStore.updatedEvents, hasLength(1));
    expect(fakeStore.updatedEvents.single.localId, eventId);
    expect(
      fakeStore.updatedEvents.single.payload['summary'],
      'Updated Event Title',
    );
    expect(
        fakeStore.updatedEvents.single.payload['eventCalendarId'], calendarId);
    expect(
      fakeStore.updatedEvents.single.changedFields,
      containsAll(<String>['summary', 'eventCalendarId', 'startAt', 'endAt']),
    );
  });
}

Future<void> _pumpEventDetail(
  WidgetTester tester, {
  required AppDatabase db,
  required int eventId,
  required FakeTaskEventServerFirstStore fakeStore,
}) async {
  final calendars = await db.select(db.eventCalendars).get();
  final router = GoRouter(
    initialLocation: '/event/$eventId',
    routes: [
      GoRoute(
        path: AppRoutes.timeline,
        builder: (context, state) => const Center(
          child: Text('timeline fallback'),
        ),
      ),
      GoRoute(
        path: AppRoutes.eventDetail,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return EventDetailPage(eventId: id);
        },
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    router.dispose();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(800, 1000),
    overrides: [
      allEventCalendarsProvider.overrideWith((ref) => Stream.value(calendars)),
      onlinePrimaryPolicyProvider.overrideWith(
        (ref) => writableOnlinePrimaryPolicy,
      ),
      taskEventServerFirstStoreProvider.overrideWith(
        (ref) async => fakeStore,
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
}

Future<void> _pumpUntilEventUpdated(
  WidgetTester tester,
  FakeTaskEventServerFirstStore fakeStore,
) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (fakeStore.updatedEvents.isNotEmpty) {
      return;
    }
  }
  expect(fakeStore.updatedEvents, isNotEmpty);
}
