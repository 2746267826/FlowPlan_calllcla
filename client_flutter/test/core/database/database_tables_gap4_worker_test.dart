import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('calendar events and time blocks expose every table column', () async {
    final db = createTestDatabase();
    addTearDown(db.close);

    expect(
      db.calendarEvents.$columns.map((column) => column.$name),
      containsAll(<String>[
        'id',
        'uid',
        'dtstamp',
        'summary',
        'description',
        'location',
        'dtstart',
        'dtend',
        'rrule',
        'status',
        'transp',
        'source',
        'event_calendar_id',
        'color_hex',
        'is_block',
      ]),
    );
    expect(
      db.timeBlocks.$columns.map((column) => column.$name),
      containsAll(<String>[
        'id',
        'name',
        'start_hour',
        'start_minute',
        'end_hour',
        'end_minute',
        'weekdays',
        'is_active',
        'color_hex',
        'emoji',
      ]),
    );
  });

  test('calendar event companion writes defaults and clears nullable fields',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 6, 11, 9);
    final calendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Gap4 calendar',
            createdAt: now,
          ),
        );

    final eventId = await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'gap4-event',
            dtstamp: now,
            summary: 'Gap4 event',
            description: const Value('Initial description'),
            location: const Value('Room 1'),
            dtstart: now,
            dtend: Value(now.add(const Duration(hours: 1))),
            rrule: const Value('FREQ=DAILY'),
            eventCalendarId: Value(calendarId),
          ),
        );

    final inserted = await (db.select(db.calendarEvents)
          ..where((row) => row.id.equals(eventId)))
        .getSingle();
    expect(inserted.status, 'CONFIRMED');
    expect(inserted.transp, 'OPAQUE');
    expect(inserted.source, 'local');
    expect(inserted.colorHex, '#6B5EE4');
    expect(inserted.isBlock, isFalse);

    await (db.update(db.calendarEvents)..where((row) => row.id.equals(eventId)))
        .write(
      CalendarEventsCompanion(
        description: const Value(null),
        location: const Value(null),
        dtend: const Value(null),
        rrule: const Value(null),
        eventCalendarId: const Value(null),
        colorHex: const Value('#123456'),
        isBlock: const Value(true),
      ),
    );

    final updated = await (db.select(db.calendarEvents)
          ..where((row) => row.id.equals(eventId)))
        .getSingle();
    expect(updated.description, isNull);
    expect(updated.location, isNull);
    expect(updated.dtend, isNull);
    expect(updated.rrule, isNull);
    expect(updated.eventCalendarId, isNull);
    expect(updated.colorHex, '#123456');
    expect(updated.isBlock, isTrue);
  });

  test('time block companion writes defaults and explicit overrides', () async {
    final db = createTestDatabase();
    addTearDown(db.close);

    final defaultId = await db.into(db.timeBlocks).insert(
          TimeBlocksCompanion.insert(
            name: 'Morning focus',
            startHour: 9,
            endHour: 11,
          ),
        );
    final defaultBlock = await (db.select(db.timeBlocks)
          ..where((row) => row.id.equals(defaultId)))
        .getSingle();
    expect(defaultBlock.startMinute, 0);
    expect(defaultBlock.endMinute, 0);
    expect(defaultBlock.weekdays, '[1,2,3,4,5,6,7]');
    expect(defaultBlock.isActive, isTrue);
    expect(defaultBlock.colorHex, '#E0E0E0');
    expect(defaultBlock.emoji, isNotEmpty);

    await (db.update(db.timeBlocks)..where((row) => row.id.equals(defaultId)))
        .write(
      const TimeBlocksCompanion(
        startMinute: Value(30),
        endMinute: Value(45),
        weekdays: Value('[1,3,5]'),
        isActive: Value(false),
        colorHex: Value('#654321'),
        emoji: Value('F'),
      ),
    );

    final updated = await (db.select(db.timeBlocks)
          ..where((row) => row.id.equals(defaultId)))
        .getSingle();
    expect(updated.startMinute, 30);
    expect(updated.endMinute, 45);
    expect(updated.weekdays, '[1,3,5]');
    expect(updated.isActive, isFalse);
    expect(updated.colorHex, '#654321');
    expect(updated.emoji, 'F');
  });
}
