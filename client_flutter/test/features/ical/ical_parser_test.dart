import 'package:flowplanv2/features/ical/ical_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a VEVENT summary and escaped location text', () {
    const source = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:event-1
SUMMARY:Design\\, review
LOCATION:Room\\; 42
DTSTART:20260608T090000
DTEND:20260608T100000
END:VEVENT
END:VCALENDAR
''';

    final events = const ICalParser().parse(source);

    expect(events, hasLength(1));
    expect(events.single.uid.value, 'event-1');
    expect(events.single.summary.value, 'Design, review');
    expect(events.single.location.value, 'Room; 42');
  });
}
