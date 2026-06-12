import 'dart:async';

import 'package:async/async.dart';
import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('event streams emit creates, visibility changes and deletes', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final booksRepository = CalendarBooksRepository(db);
    final eventRepository = EventRepository(db);
    final calendarId = await booksRepository.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Stream calendar',
        createdAt: fixtureNow(),
      ),
      audit: false,
    );
    final events = StreamQueue(
      eventRepository.watchVisibleForDateRange(
        fixtureNow().subtract(const Duration(hours: 1)),
        fixtureNow().add(const Duration(hours: 4)),
      ),
    );
    addTearDown(events.cancel);

    expect(await _nextEventSummaries(events, const <String>[]), isEmpty);
    final eventId = await eventRepository.create(
      fixtureEvent(
        uid: 'stream-event',
        summary: 'Visible stream event',
        calendarId: calendarId,
      ),
      audit: false,
    );
    expect(
      await _nextEventSummaries(events, const <String>['Visible stream event']),
      ['Visible stream event'],
    );

    await booksRepository.toggleEventCalendarVisible(
      calendarId,
      false,
      audit: false,
    );
    expect(await _nextEventSummaries(events, const <String>[]), isEmpty);

    await booksRepository.toggleEventCalendarVisible(
      calendarId,
      true,
      audit: false,
    );
    expect(
      await _nextEventSummaries(events, const <String>['Visible stream event']),
      ['Visible stream event'],
    );

    await eventRepository.delete(eventId, audit: false);
    expect(await _nextEventSummaries(events, const <String>[]), isEmpty);
  });

  test('calendar book streams emit active and archived container changes',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(db);
    final calendars = _NameSnapshots(_calendarNameStream(repository));
    final activeLists = _NameSnapshots(_activeTaskListNameStream(repository));
    final archivedLists =
        _NameSnapshots(_archivedTaskListNameStream(repository));
    addTearDown(calendars.cancel);
    addTearDown(activeLists.cancel);
    addTearDown(archivedLists.cancel);
    await Future<void>.delayed(Duration.zero);

    final calendarId = await repository.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Stream calendar',
        createdAt: fixtureNow(),
      ),
      audit: false,
    );
    expect(
      await calendars.waitForWhere(
        (names) => names.contains('Stream calendar'),
        'created calendar appears',
      ),
      contains('Stream calendar'),
    );

    final sourceListId = await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Stream tasks',
        createdAt: fixtureNow(),
      ),
      audit: false,
    );
    expect(
      await activeLists.waitForWhere(
        (names) => names.contains('Stream tasks'),
        'created task list appears',
      ),
      contains('Stream tasks'),
    );

    await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Fallback tasks',
        createdAt: fixtureNow().add(const Duration(minutes: 1)),
      ),
      audit: false,
    );
    expect(
      await activeLists.waitForWhere(
        (names) =>
            names.contains('Stream tasks') && names.contains('Fallback tasks'),
        'fallback task list appears with stream task list',
      ),
      containsAll(<String>['Stream tasks', 'Fallback tasks']),
    );
    expect(
      await archivedLists.waitForWhere(
        (names) => !names.contains('Stream tasks'),
        'stream task list is initially active',
      ),
      isNot(contains('Stream tasks')),
    );

    await repository.updateEventCalendar(
      EventCalendarsCompanion(
        id: Value(calendarId),
        name: const Value('Renamed stream calendar'),
      ),
      audit: false,
    );
    expect(
      await calendars.waitForWhere(
        (names) =>
            names.contains('Renamed stream calendar') &&
            !names.contains('Stream calendar'),
        'renamed calendar replaces original name',
      ),
      contains('Renamed stream calendar'),
    );

    await repository.archiveTaskList(sourceListId, audit: false);
    expect(
      await activeLists.waitForWhere(
        (names) =>
            names.contains('Fallback tasks') && !names.contains('Stream tasks'),
        'archived task list leaves active stream',
      ),
      allOf(
        contains('Fallback tasks'),
        isNot(contains('Stream tasks')),
      ),
    );
    expect(
      await archivedLists.waitForWhere(
        (names) => names.contains('Stream tasks'),
        'archived task list appears',
      ),
      contains('Stream tasks'),
    );

    await repository.unarchiveTaskList(sourceListId, audit: false);
    expect(
      await activeLists.waitForWhere(
        (names) =>
            names.contains('Fallback tasks') && names.contains('Stream tasks'),
        'restored task list returns to active stream',
      ),
      containsAll(<String>['Fallback tasks', 'Stream tasks']),
    );
    expect(
      await archivedLists.waitForWhere(
        (names) => !names.contains('Stream tasks'),
        'restored task list leaves archived stream',
      ),
      isNot(contains('Stream tasks')),
    );
  });
}

Future<List<String>> _nextEventSummaries(
  StreamQueue<List<CalendarEvent>> queue,
  List<String> expected,
) async {
  final events = await _nextWhere(
    queue,
    (items) => _sameStrings(
      items.map((event) => event.summary).toList(growable: false),
      expected,
    ),
  );
  return events.map((event) => event.summary).toList(growable: false);
}

Future<T> _nextWhere<T>(
  StreamQueue<T> queue,
  bool Function(T value) predicate, {
  String label = 'stream value',
}) async {
  for (var i = 0; i < 10; i++) {
    final value = await queue.next.timeout(
      const Duration(seconds: 2),
      onTimeout: () => fail('Timed out waiting for $label.'),
    );
    if (predicate(value)) {
      return value;
    }
  }
  fail('Expected stream to emit a matching value.');
}

Stream<List<String>> _calendarNameStream(CalendarBooksRepository repository) {
  return repository.watchAllEventCalendars().map(
        (items) =>
            items.map((calendar) => calendar.name).toList(growable: false),
      );
}

Stream<List<String>> _activeTaskListNameStream(
  CalendarBooksRepository repository,
) {
  return repository.watchAllTaskLists().map(
        (items) => items.map((list) => list.name).toList(growable: false),
      );
}

Stream<List<String>> _archivedTaskListNameStream(
  CalendarBooksRepository repository,
) {
  return repository.watchArchivedTaskLists().map(
        (items) => items.map((list) => list.name).toList(growable: false),
      );
}

bool _sameStrings(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) {
    return false;
  }
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      return false;
    }
  }
  return true;
}

class _NameSnapshots {
  _NameSnapshots(Stream<List<String>> stream) {
    _subscription = stream.listen((snapshot) {
      _snapshots.add(List<String>.from(snapshot));
    });
  }

  final List<List<String>> _snapshots = <List<String>>[];
  late final StreamSubscription<List<String>> _subscription;

  Future<List<String>> waitForWhere(
    bool Function(List<String> names) predicate,
    String label,
  ) async {
    for (var i = 0; i < 40; i++) {
      for (final snapshot in _snapshots.reversed) {
        if (predicate(snapshot)) {
          return snapshot;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('Expected $label in snapshots $_snapshots.');
  }

  Future<void> cancel() => _subscription.cancel();
}
