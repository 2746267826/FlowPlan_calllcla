import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class EventRepository {
  final AppDatabase _db;
  EventRepository(this._db);

  Stream<List<CalendarEvent>> _watchEventsInRange({
    required DateTime start,
    required DateTime end,
    bool requireVisible = false,
    Expression<bool> Function(
      $CalendarEventsTable event,
      $EventCalendarsTable calendar,
    )? extraFilter,
  }) {
    final query = _db.select(_db.calendarEvents).join([
      innerJoin(
        _db.eventCalendars,
        _db.eventCalendars.id.equalsExp(_db.calendarEvents.eventCalendarId),
      ),
    ]);

    var predicate = _db.calendarEvents.dtstart.isBiggerOrEqualValue(start) &
        _db.calendarEvents.dtstart.isSmallerThanValue(end);
    if (requireVisible) {
      predicate = predicate & _db.eventCalendars.isVisible.equals(true);
    }
    if (extraFilter != null) {
      predicate = predicate &
          extraFilter(_db.calendarEvents, _db.eventCalendars);
    }

    query.where(predicate);
    query.orderBy([OrderingTerm.asc(_db.calendarEvents.dtstart)]);

    return query.watch().map(
          (rows) => rows.map((row) => row.readTable(_db.calendarEvents)).toList(),
        );
  }

  Future<void> _ensureEventCalendarBinding(
    Value<int?> eventCalendarId, {
    required bool requirePresent,
  }) async {
    if (!eventCalendarId.present) {
      if (requirePresent) {
        throw StateError(
          '\u65e5\u7a0b\u5fc5\u987b\u5f52\u5c5e\u4e8e\u4e00\u4e2a\u65e5\u5386\u672c\u3002',
        );
      }
      return;
    }

    final id = eventCalendarId.value;
    if (id == null) {
      throw StateError(
        '\u65e5\u7a0b\u5fc5\u987b\u5f52\u5c5e\u4e8e\u4e00\u4e2a\u65e5\u5386\u672c\u3002',
      );
    }

    final calendar = await (_db.select(_db.eventCalendars)
          ..where((c) => c.id.equals(id)))
        .getSingleOrNull();
    if (calendar == null) {
      throw StateError(
        '\u6240\u9009\u65e5\u5386\u672c\u4e0d\u5b58\u5728\u3002',
      );
    }
  }

  Stream<List<CalendarEvent>> watchForDateRange(DateTime start, DateTime end) {
    return _watchEventsInRange(
      start: start,
      end: end,
    );
  }

  Stream<List<CalendarEvent>> watchVisibleForDateRange(
    DateTime start,
    DateTime end,
  ) {
    return _watchEventsInRange(
      start: start,
      end: end,
      requireVisible: true,
    );
  }

  Stream<List<CalendarEvent>> watchByCalendar(int calendarId) =>
      (_db.select(_db.calendarEvents)
            ..where((e) => e.eventCalendarId.equals(calendarId))
            ..orderBy([(e) => OrderingTerm(expression: e.dtstart)]))
          .watch();

  Stream<List<CalendarEvent>> watchVisibleForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _watchEventsInRange(
      start: start,
      end: end,
      requireVisible: true,
    );
  }

  Future<CalendarEvent?> getById(int id) =>
      (_db.select(_db.calendarEvents)..where((e) => e.id.equals(id)))
          .getSingleOrNull();

  Future<List<CalendarEvent>> getAllByUid(String uid) =>
      (_db.select(_db.calendarEvents)..where((e) => e.uid.equals(uid))).get();

  Future<int> create(CalendarEventsCompanion companion) async {
    await _ensureEventCalendarBinding(
      companion.eventCalendarId,
      requirePresent: true,
    );
    return _db.into(_db.calendarEvents).insert(companion);
  }

  Future<bool> update(CalendarEventsCompanion companion) async {
    await _ensureEventCalendarBinding(
      companion.eventCalendarId,
      requirePresent: false,
    );
    return _db.update(_db.calendarEvents).replace(companion);
  }

  Future<void> updateTimes(int id, DateTime dtstart, DateTime dtend) =>
      (_db.update(_db.calendarEvents)..where((e) => e.id.equals(id))).write(
            CalendarEventsCompanion(
              dtstart: Value(dtstart),
              dtend: Value(dtend),
            ),
          );

  Future<int> delete(int id) =>
      (_db.delete(_db.calendarEvents)..where((e) => e.id.equals(id))).go();

  Future<void> deleteByUid(String uid) async {
    await (_db.delete(_db.calendarEvents)..where((e) => e.uid.equals(uid)))
        .go();
  }

  Future<void> deleteBySourceAndCalendarId({
    required String source,
    required int calendarId,
  }) async {
    await (_db.delete(_db.calendarEvents)
          ..where(
            (e) =>
                e.source.equals(source) &
                e.eventCalendarId.equals(calendarId),
          ))
        .go();
  }

  Future<void> upsertSyncedEvent({
    required String uid,
    required DateTime dtstamp,
    required String summary,
    required DateTime dtstart,
    required DateTime dtend,
    String? description,
    String? location,
    String? rrule,
    required String status,
    required String source,
    int? eventCalendarId,
    required String colorHex,
    bool isBlock = false,
  }) async {
    final matches = await getAllByUid(uid);
    final existing = matches.isNotEmpty ? matches.first : null;

    if (matches.length > 1) {
      final duplicateIds = matches.skip(1).map((event) => event.id).toList();
      if (duplicateIds.isNotEmpty) {
        await (_db.delete(_db.calendarEvents)
              ..where((e) => e.id.isIn(duplicateIds)))
            .go();
      }
    }

    if (existing == null) {
      await create(
        CalendarEventsCompanion.insert(
          uid: uid,
          dtstamp: dtstamp,
          summary: summary,
          description: Value(description),
          location: Value(location),
          dtstart: dtstart,
          dtend: Value(dtend),
          rrule: Value(rrule),
          status: Value(status),
          source: Value(source),
          eventCalendarId: Value(eventCalendarId),
          colorHex: Value(colorHex),
          isBlock: Value(isBlock),
        ),
      );
      return;
    }

    await (_db.update(_db.calendarEvents)..where((e) => e.id.equals(existing.id)))
        .write(
      CalendarEventsCompanion(
        uid: Value(uid),
        dtstamp: Value(dtstamp),
        summary: Value(summary),
        description: Value(description),
        location: Value(location),
        dtstart: Value(dtstart),
        dtend: Value(dtend),
        rrule: Value(rrule),
        status: Value(status),
        source: Value(source),
        eventCalendarId: Value(eventCalendarId),
        colorHex: Value(colorHex),
        isBlock: Value(isBlock),
      ),
    );
  }

  Future<List<CalendarEvent>> getBlocksForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final query = _db.select(_db.calendarEvents).join([
      innerJoin(
        _db.eventCalendars,
        _db.eventCalendars.id.equalsExp(_db.calendarEvents.eventCalendarId),
      ),
    ]);
    query.where(
      _db.calendarEvents.isBlock.equals(true) &
          _db.calendarEvents.dtstart.isBiggerOrEqualValue(start) &
          _db.calendarEvents.dtstart.isSmallerThanValue(end),
    );
    return query
        .get()
        .then((rows) => rows.map((row) => row.readTable(_db.calendarEvents)).toList());
  }

  Future<List<CalendarEvent>> getEventsForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final query = _db.select(_db.calendarEvents).join([
      innerJoin(
        _db.eventCalendars,
        _db.eventCalendars.id.equalsExp(_db.calendarEvents.eventCalendarId),
      ),
    ]);
    query.where(
      _db.calendarEvents.dtstart.isBiggerOrEqualValue(start) &
          _db.calendarEvents.dtstart.isSmallerThanValue(end),
    );
    query.orderBy([OrderingTerm.asc(_db.calendarEvents.dtstart)]);
    return query
        .get()
        .then((rows) => rows.map((row) => row.readTable(_db.calendarEvents)).toList());
  }
}
