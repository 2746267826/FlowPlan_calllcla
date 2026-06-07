import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('calendar event repository returns events for the selected day', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final calendarId = await insertFixtureCalendar(db);
    final repository = EventRepository(db);
    await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'event-1',
            summary: 'Design review',
            calendarId: calendarId,
          ),
        );

    final events = await repository.getEventsForDate(fixtureNow());

    expect(events.map((event) => event.summary), contains('Design review'));
  });
}
