import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
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

const _timelineRoute = '/timeline';
const _eventCreateRoute = '/event/create';
const _eventDetailRoute = '/event/:id';

void main() {
  testWidgets(
    'event detail creates a local event through the server-first store',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final fakeStore = FakeTaskEventServerFirstStore();
      final calendarId = await insertFixtureCalendar(
        db,
        name: 'Blocked calendar',
      );
      await CalendarBooksRepository(db).saveEventCalendarDefaults(
        id: calendarId,
        defaultIsBlock: true,
        audit: false,
      );

      await _pumpEventDetailRoute(
        tester,
        db: db,
        initialLocation: _eventCreateRoute,
        fakeStore: fakeStore,
      );
      await _pumpUntil(
        tester,
        () => find.text('Blocked calendar').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Blocked calendar'));
      await _pumpUntil(
        tester,
        () {
          final switches = tester.widgetList<Switch>(find.byType(Switch));
          return switches.length >= 2 && switches.last.value;
        },
      );

      await tester.enterText(
        find.byKey(AppKeys.eventSummaryField),
        'Planning window',
      );
      await tester.tap(find.byKey(AppKeys.eventSaveButton));
      await _pumpUntil(tester, () => fakeStore.createdEvents.isNotEmpty);

      final payload = fakeStore.createdEvents.single;
      final startAt = DateTime.parse(payload['startAt']! as String);
      final endAt = DateTime.parse(payload['endAt']! as String);
      expect(payload['summary'], 'Planning window');
      expect(payload['eventCalendarId'], calendarId);
      expect(payload['isBlock'], isTrue);
      expect(endAt.isAfter(startAt), isTrue);
      await _pumpUntil(
        tester,
        () => find.text('timeline fallback').evaluate().isNotEmpty,
      );
    },
  );

  testWidgets('event detail validates blank titles before saving',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    await insertFixtureCalendar(db, name: 'Validation calendar');

    await _pumpEventDetailRoute(
      tester,
      db: db,
      initialLocation: _eventCreateRoute,
      fakeStore: fakeStore,
    );
    await tester.tap(find.byKey(AppKeys.eventSaveButton));
    await tester.pump();

    expect(fakeStore.createdEvents, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(EventDetailPage), findsOneWidget);
  });

  testWidgets('event detail deletes an existing local event after confirmation',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await insertFixtureCalendar(
      db,
      name: 'Delete calendar',
    );
    final eventId = await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'delete-event-detail',
            dtstamp: fixtureNow(),
            summary: 'Delete candidate',
            dtstart: DateTime.utc(2026, 6, 10, 13),
            dtend: Value(DateTime.utc(2026, 6, 10, 14)),
            eventCalendarId: Value(calendarId),
          ),
        );

    await _pumpEventDetailRoute(
      tester,
      db: db,
      initialLocation: '/event/$eventId',
      fakeStore: fakeStore,
    );
    await _pumpUntil(
      tester,
      () {
        final field = tester.widget<TextField>(
          find.byKey(AppKeys.eventSummaryField),
        );
        return field.controller?.text == 'Delete candidate';
      },
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await _pumpUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isNotEmpty,
    );
    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          )
          .last,
    );
    await _pumpUntil(tester, () => fakeStore.deletedEventIds.isNotEmpty);

    expect(fakeStore.deletedEventIds, [eventId]);
    await _pumpUntil(
      tester,
      () => find.text('timeline fallback').evaluate().isNotEmpty,
    );
  });
}

Future<void> _pumpEventDetailRoute(
  WidgetTester tester, {
  required AppDatabase db,
  required String initialLocation,
  required FakeTaskEventServerFirstStore fakeStore,
}) async {
  final calendars = await db.select(db.eventCalendars).get();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: _timelineRoute,
        builder: (context, state) => const Center(
          child: Text('timeline fallback'),
        ),
      ),
      GoRoute(
        path: _eventCreateRoute,
        builder: (context, state) => const EventDetailPage(eventId: null),
      ),
      GoRoute(
        path: _eventDetailRoute,
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
    size: const Size(900, 1000),
    overrides: [
      allEventCalendarsProvider.overrideWith((ref) => Stream.value(calendars)),
      onlinePrimaryPolicyProvider.overrideWith(
        (ref) => writableOnlinePrimaryPolicy,
      ),
      taskEventServerFirstStoreProvider.overrideWith((ref) async => fakeStore),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue);
}
