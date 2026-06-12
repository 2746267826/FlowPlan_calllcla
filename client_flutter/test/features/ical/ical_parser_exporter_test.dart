import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/ical/ical_exporter.dart';
import 'package:flowplanv2/features/ical/ical_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ICalParser', () {
    test('unfolds folded lines and unescapes text fields', () {
      const source = 'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'UID:folded-event\r\n'
          'SUMMARY:Quarterly planning \r\n'
          ' review\r\n'
          'DESCRIPTION:Line one\\nLine two\\, with comma\\; and semicolon\r\n'
          'LOCATION:Room\\\\A\r\n'
          'DTSTART:20260608T090000\r\n'
          'DTEND:20260608T100000\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';

      final events = const ICalParser().parse(source);

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.uid.value, 'folded-event');
      expect(event.summary.value, 'Quarterly planning review');
      expect(
        event.description.value,
        'Line one\nLine two, with comma; and semicolon',
      );
      expect(event.location.value, r'Room\A');
      expect(event.dtstart.value, DateTime(2026, 6, 8, 9));
      expect(event.dtend.value, DateTime(2026, 6, 8, 10));
    });

    test('accepts TZID parameters and keeps local wall-clock values', () {
      const source = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:tzid-event
SUMMARY:Shanghai standup
DTSTART;TZID=Asia/Shanghai:20260608T090000
DTEND;TZID=Asia/Shanghai:20260608T093000
END:VEVENT
END:VCALENDAR
''';

      final events = const ICalParser().parse(source);

      expect(events, hasLength(1));
      expect(events.single.dtstart.value, DateTime(2026, 6, 8, 9));
      expect(events.single.dtend.value, DateTime(2026, 6, 8, 9, 30));
    });

    test('parses UTC date-times as the same instant in local time', () {
      const source = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:utc-event
SUMMARY:UTC sync
DTSTART:20260608T013000Z
DTEND:20260608T023000Z
END:VEVENT
END:VCALENDAR
''';

      final events = const ICalParser().parse(source);

      expect(events, hasLength(1));
      expect(events.single.dtstart.value,
          DateTime.utc(2026, 6, 8, 1, 30).toLocal());
      expect(
          events.single.dtend.value, DateTime.utc(2026, 6, 8, 2, 30).toLocal());
    });

    test('parses all-day DATE values at local midnight', () {
      const source = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:all-day-event
SUMMARY:Focus day
DTSTART;VALUE=DATE:20260609
DTEND;VALUE=DATE:20260610
END:VEVENT
END:VCALENDAR
''';

      final events = const ICalParser().parse(source);

      expect(events, hasLength(1));
      expect(events.single.dtstart.value, DateTime(2026, 6, 9));
      expect(events.single.dtend.value, DateTime(2026, 6, 10));
    });

    test('skips invalid events without rejecting valid siblings', () {
      const source = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:missing-summary
DTSTART:20260608T090000
END:VEVENT
BEGIN:VEVENT
UID:invalid-start
SUMMARY:Bad date
DTSTART:not-a-date
END:VEVENT
BEGIN:VEVENT
UID:valid-event
SUMMARY:Valid event
DTSTART:20260608T110000
END:VEVENT
END:VCALENDAR
''';

      final events = const ICalParser().parse(source);

      expect(events, hasLength(1));
      expect(events.single.uid.value, 'valid-event');
      expect(events.single.summary.value, 'Valid event');
    });

    test('ignores malformed properties and non-event components', () {
      const source = '''
BEGIN:VCALENDAR
BEGIN:VTODO
UID:todo-ignored
SUMMARY:Should not become an event
DTSTART:20260608T090000
END:VTODO
BEGIN:VEVENT
UID:dirty-event
SUMMARY:Dirty\\, but valid
DESCRIPTION:Good description
THIS LINE HAS NO COLON
DTSTART;VALUE=DATE:20260609
X-UNKNOWN-PROP:value
LOCATION:
END:VEVENT
END:VCALENDAR
''';

      final events = const ICalParser().parse(source);

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.uid.value, 'dirty-event');
      expect(event.summary.value, 'Dirty, but valid');
      expect(event.description.value, 'Good description');
      expect(event.location.value, null);
      expect(event.dtstart.value, DateTime(2026, 6, 9));
    });
  });

  group('ICalExporter', () {
    test('escapes text fields and writes UTC date-time values', () {
      final event = _event(
        uid: 'export-event',
        dtstamp: DateTime.utc(2026, 6, 8, 1, 2, 3),
        dtstart: DateTime.utc(2026, 6, 8, 9, 30),
        dtend: DateTime.utc(2026, 6, 8, 10, 45),
        summary: r'Roadmap, Q3; backlog \ sync',
        description: 'Line 1\nLine 2, notes; owner',
        location: r'Room, A; Floor\5',
        rrule: 'FREQ=WEEKLY;COUNT=2',
        colorHex: '#123456',
      );

      final exported = const ICalExporter().export([event]);

      expect(exported, contains('DTSTAMP:20260608T010203Z'));
      expect(exported, contains('DTSTART:20260608T093000Z'));
      expect(exported, contains('DTEND:20260608T104500Z'));
      expect(
        exported,
        contains(r'SUMMARY:Roadmap\, Q3\; backlog \\ sync'),
      );
      expect(
        exported,
        contains(r'DESCRIPTION:Line 1\nLine 2\, notes\; owner'),
      );
      expect(exported, contains(r'LOCATION:Room\, A\; Floor\\5'));
      expect(exported, contains('RRULE:FREQ=WEEKLY;COUNT=2'));
      expect(exported, contains('X-APPLE-CALENDAR-COLOR:#123456'));
    });

    test('omits optional fields when values are null or empty', () {
      final event = _event(
        dtend: null,
        description: '',
        location: null,
        rrule: '',
        colorHex: '',
      );

      final exported = const ICalExporter().export([event]);

      expect(exported, isNot(contains('DTEND:')));
      expect(exported, isNot(contains('DESCRIPTION:')));
      expect(exported, isNot(contains('LOCATION:')));
      expect(exported, isNot(contains('RRULE:')));
      expect(exported, isNot(contains('X-APPLE-CALENDAR-COLOR:')));
      expect(exported, contains('STATUS:CONFIRMED'));
    });
  });
}

CalendarEvent _event({
  String uid = 'event-1',
  DateTime? dtstamp,
  String summary = 'Event summary',
  String? description,
  String? location,
  DateTime? dtstart,
  DateTime? dtend,
  String? rrule,
  String status = 'CONFIRMED',
  String transp = 'OPAQUE',
  String source = 'local',
  int? eventCalendarId,
  String colorHex = '#6B5EE4',
  bool isBlock = false,
}) {
  return CalendarEvent(
    id: 1,
    uid: uid,
    dtstamp: dtstamp ?? DateTime.utc(2026, 6, 8, 8),
    summary: summary,
    description: description,
    location: location,
    dtstart: dtstart ?? DateTime.utc(2026, 6, 8, 9),
    dtend: dtend,
    rrule: rrule,
    status: status,
    transp: transp,
    source: source,
    eventCalendarId: eventCalendarId,
    colorHex: colorHex,
    isBlock: isBlock,
  );
}
