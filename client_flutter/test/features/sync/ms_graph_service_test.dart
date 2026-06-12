import 'package:flowplanv2/features/sync/ms_graph_service.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = OutlookConfig(clientId: 'client-id');

  group('calendar mapping helpers', () {
    test('calendarIdOf, calendarNameOf, and calendarColorHexOf normalize data',
        () {
      expect(MsGraphService.calendarIdOf(<String, dynamic>{'id': 'cal-1'}),
          'cal-1');
      expect(MsGraphService.calendarIdOf(<String, dynamic>{}), '');
      expect(
        MsGraphService.calendarNameOf(<String, dynamic>{'name': '  Work  '}),
        'Work',
      );
      expect(MsGraphService.calendarNameOf(<String, dynamic>{}),
          'Outlook \u65e5\u5386');
      expect(
        MsGraphService.calendarNameOf(<String, dynamic>{'name': '   '}),
        'Outlook \u65e5\u5386',
      );
      expect(
        MsGraphService.calendarColorHexOf(<String, dynamic>{
          'hexColor': '2F80ED',
        }),
        '#2F80ED',
      );
      expect(
        MsGraphService.calendarColorHexOf(<String, dynamic>{
          'hexColor': '#00AA88',
        }),
        '#00AA88',
      );
      expect(
        MsGraphService.calendarColorHexOf(<String, dynamic>{
          'hexColor': '   ',
        }),
        '#0078D4',
      );
      expect(MsGraphService.calendarColorHexOf(<String, dynamic>{}), '#0078D4');
    });
  });

  group('event mapping helpers', () {
    test('toGraphEvent preserves optional fields and UTC timezone', () {
      final start = DateTime.utc(2026, 6, 8, 9);
      final end = start.add(const Duration(hours: 1));

      final event = MsGraphService.toGraphEvent(
        subject: 'Planning',
        start: start,
        end: end,
        body: '<p>Agenda</p>',
        location: 'Room 1',
        isAllDay: true,
      );

      expect(event['subject'], 'Planning');
      expect(event['body'], <String, String>{
        'contentType': 'HTML',
        'content': '<p>Agenda</p>',
      });
      expect(event['start'], <String, String>{
        'dateTime': start.toIso8601String(),
        'timeZone': 'UTC',
      });
      expect(event['end'], <String, String>{
        'dateTime': end.toIso8601String(),
        'timeZone': 'UTC',
      });
      expect(event['location'], <String, String>{'displayName': 'Room 1'});
      expect(event['isAllDay'], isTrue);
    });

    test('toGraphEvent keeps absent optional fields predictable', () {
      final start = DateTime.utc(2026, 6, 8, 9);
      final event = MsGraphService.toGraphEvent(
        subject: 'No extras',
        start: start,
        end: start.add(const Duration(minutes: 30)),
      );

      expect(event['subject'], 'No extras');
      expect(event['body'], isNull);
      expect(event.containsKey('location'), isFalse);
      expect(event['isAllDay'], isFalse);
    });

    test('fromGraphEvent strips HTML, decodes entities, and joins locations',
        () {
      final parsed = MsGraphService.fromGraphEvent(<String, dynamic>{
        'id': 'event-1',
        'subject': '  Team sync  ',
        'body': <String, dynamic>{
          'contentType': 'html',
          'content': '<p>Line&nbsp;1 &amp; details</p><ul><li>First</li></ul>',
        },
        'locations': <Map<String, dynamic>>[
          <String, dynamic>{'displayName': ' Room A '},
          <String, dynamic>{'displayName': ''},
          <String, dynamic>{'displayName': 'Room B'},
        ],
        'start': <String, dynamic>{
          'dateTime': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        },
        'end': <String, dynamic>{
          'dateTime': DateTime.utc(2026, 6, 8, 10).toIso8601String(),
        },
        'showAs': 'tentative',
      });

      expect(parsed.id, 'event-1');
      expect(parsed.subject, 'Team sync');
      expect(parsed.body, contains('Line 1 & details'));
      expect(parsed.body, contains('- First'));
      expect(parsed.location, 'Room A, Room B');
      expect(parsed.status, 'TENTATIVE');
      expect(parsed.start.toUtc(), DateTime.utc(2026, 6, 8, 9));
      expect(parsed.end.toUtc(), DateTime.utc(2026, 6, 8, 10));
    });

    test('fromGraphEvent prefers primary location display name', () {
      final parsed = MsGraphService.fromGraphEvent(<String, dynamic>{
        'id': 'event-primary-location',
        'subject': 'Location priority',
        'body': <String, dynamic>{
          'contentType': 'text',
          'content': 'Plain notes',
        },
        'location': <String, dynamic>{'displayName': ' Main Room '},
        'locations': <Map<String, dynamic>>[
          <String, dynamic>{'displayName': 'Overflow Room'},
        ],
        'start': <String, dynamic>{
          'dateTime': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        },
        'end': <String, dynamic>{
          'dateTime': DateTime.utc(2026, 6, 8, 10).toIso8601String(),
        },
        'showAs': 'oof',
      });

      expect(parsed.body, 'Plain notes');
      expect(parsed.location, 'Main Room');
      expect(parsed.status, 'CONFIRMED');
    });

    test(
        'fromGraphEvent falls back to preview, default status, and one hour end',
        () {
      final start = DateTime.utc(2026, 6, 8, 9);
      final parsed = MsGraphService.fromGraphEvent(<String, dynamic>{
        'id': 'event-2',
        'subject': 'Preview body',
        'bodyPreview': 'Preview text',
        'start': <String, dynamic>{'dateTime': start.toIso8601String()},
        'showAs': 'free',
      });

      expect(parsed.body, 'Preview text');
      expect(parsed.location, isNull);
      expect(parsed.status, 'CONFIRMED');
      expect(parsed.end.difference(parsed.start), const Duration(hours: 1));
    });

    test('fromGraphEvent tolerates missing dates and unknown showAs values',
        () {
      final before = DateTime.now();
      final parsed = MsGraphService.fromGraphEvent(<String, dynamic>{
        'id': 'event-invalid-date',
        'subject': 'Invalid date',
        'body': <String, dynamic>{'content': 'Body text'},
        'start': <String, dynamic>{'dateTime': 'not-a-date'},
        'end': <String, dynamic>{'dateTime': ''},
        'showAs': 'workingElsewhere',
      });
      final after = DateTime.now();

      expect(parsed.status, 'CONFIRMED');
      expect(parsed.start.isBefore(before.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(
          parsed.start.isAfter(after.add(const Duration(seconds: 1))), isFalse);
      expect(parsed.end.difference(parsed.start), const Duration(hours: 1));
    });

    test('deleted events never need hydration details', () {
      final deleted = <String, dynamic>{
        'id': 'event-deleted',
        '@removed': <String, dynamic>{'reason': 'deleted'},
      };

      expect(MsGraphService.isDeletedEvent(deleted), isTrue);
      expect(MsGraphService.needsEventDetails(deleted), isFalse);
    });

    test('needsEventDetails detects compact delta payloads', () {
      expect(
        MsGraphService.needsEventDetails(<String, dynamic>{
          'id': 'event-partial',
          'subject': 'Only a subject',
        }),
        isTrue,
      );
      expect(
        MsGraphService.needsEventDetails(<String, dynamic>{
          'id': 'event-full',
          'subject': 'Full',
          'body': <String, dynamic>{'content': 'Body'},
          'bodyPreview': 'Body',
          'location': <String, dynamic>{'displayName': 'Room'},
        }),
        isFalse,
      );
    });
  });

  group('server-managed client write guard', () {
    test('write methods throw StateError even for managed containers',
        () async {
      final service =
          MsGraphService(config, syncMode: OutlookSyncMode.bidirectional);

      await expectLater(
        service.createCalendar(
          name: 'Managed',
          isFlowPlanV2ManagedContainer: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('server-managed'),
          ),
        ),
      );
      await expectLater(
        service.createEvent(
          <String, dynamic>{'subject': 'Write'},
          calendarId: 'calendar-id',
          isFlowPlanV2ManagedContainer: true,
        ),
        throwsStateError,
      );
      await expectLater(
        service.updateEvent(
          calendarId: 'calendar-id',
          eventId: 'event-id',
          event: <String, dynamic>{'subject': 'Write'},
          isFlowPlanV2ManagedContainer: true,
        ),
        throwsStateError,
      );
      await expectLater(
        service.deleteEvent(
          calendarId: 'calendar-id',
          eventId: 'event-id',
          isFlowPlanV2ManagedContainer: true,
        ),
        throwsStateError,
      );
      await expectLater(
        service.createCalendar(
          name: 'External',
          isFlowPlanV2ManagedContainer: false,
        ),
        throwsStateError,
      );
    });

    test('read methods return empty server-managed stubs', () async {
      final service =
          MsGraphService(config, syncMode: OutlookSyncMode.readOnly);

      expect(await service.getCalendars(), isEmpty);
      expect(
        await service.getEvents(calendarId: 'calendar-id'),
        (events: const <Map<String, dynamic>>[], deltaLink: null),
      );
      expect(
        await service.getEvent(calendarId: 'calendar-id', eventId: 'event-id'),
        isNull,
      );
    });
  });
}
