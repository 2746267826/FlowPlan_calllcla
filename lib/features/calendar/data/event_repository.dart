import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../audit/data_operation_log_repository.dart';

class EventRepository {
  final AppDatabase _db;
  final DataOperationLogRepository? _operationLogRepository;
  EventRepository(this._db, [this._operationLogRepository]);

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
          (rows) =>
              rows.map((row) => row.readTable(_db.calendarEvents)).toList(),
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

  Future<List<CalendarEvent>> getByCalendarId(int calendarId) =>
      (_db.select(_db.calendarEvents)
            ..where((e) => e.eventCalendarId.equals(calendarId))
            ..orderBy([(e) => OrderingTerm(expression: e.dtstart)]))
          .get();

  Future<List<CalendarEvent>> getByCalendarIds(
    Iterable<int> calendarIds,
  ) async {
    final ids = calendarIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return const <CalendarEvent>[];
    }

    return (_db.select(_db.calendarEvents)
          ..where((e) => e.eventCalendarId.isIn(ids))
          ..orderBy([(e) => OrderingTerm(expression: e.dtstart)]))
        .get();
  }

  Future<List<CalendarEvent>> getAllByUid(String uid) =>
      (_db.select(_db.calendarEvents)..where((e) => e.uid.equals(uid))).get();

  Future<int> create(
    CalendarEventsCompanion companion, {
    bool audit = true,
    String actor = 'user',
    String action = 'create',
    String? summary,
    Object? metadata,
  }) async {
    await _ensureEventCalendarBinding(
      companion.eventCalendarId,
      requirePresent: true,
    );
    final id = await _db.into(_db.calendarEvents).insert(companion);
    if (audit) {
      final created = await getById(id);
      if (created != null) {
        await _recordEventOperation(
          actor: actor,
          action: action,
          event: created,
          summary:
              summary ?? '\u521b\u5efa\u65e5\u7a0b\u300c${created.summary}\u300d',
          after: created.toJson(),
          metadata: metadata,
        );
      }
    }
    return id;
  }

  Future<bool> update(
    CalendarEventsCompanion companion, {
    bool audit = true,
    String actor = 'user',
    String action = 'update',
    String? summary,
    Object? metadata,
  }) async {
    await _ensureEventCalendarBinding(
      companion.eventCalendarId,
      requirePresent: false,
    );
    final id = companion.id.present ? companion.id.value : null;
    final before = id == null ? null : await getById(id);
    final updated = await _db.update(_db.calendarEvents).replace(companion);
    if (audit && updated && id != null) {
      final after = await getById(id);
      final label =
          after?.summary ?? before?.summary ?? '\u672a\u547d\u540d\u65e5\u7a0b';
      await _recordEventOperation(
        actor: actor,
        action: action,
        event: after ?? before,
        summary: summary ?? '\u66f4\u65b0\u65e5\u7a0b\u300c$label\u300d',
        before: before?.toJson(),
        after: after?.toJson(),
        metadata: metadata,
      );
    }
    return updated;
  }

  Future<void> updateTimes(int id, DateTime dtstart, DateTime dtend) =>
      (_db.update(_db.calendarEvents)..where((e) => e.id.equals(id))).write(
            CalendarEventsCompanion(
              dtstart: Value(dtstart),
              dtend: Value(dtend),
            ),
          );

  Future<int> delete(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'delete',
    String? summary,
    Object? metadata,
  }) async {
    final before = audit ? await getById(id) : null;
    final deleted = await (_db.delete(_db.calendarEvents)
          ..where((e) => e.id.equals(id)))
        .go();
    if (audit && deleted > 0 && before != null) {
      await _recordEventOperation(
        actor: actor,
        action: action,
        event: before,
        summary:
            summary ?? '\u5220\u9664\u65e5\u7a0b\u300c${before.summary}\u300d',
        before: before.toJson(),
        metadata: metadata,
      );
    }
    return deleted;
  }

  Future<int> deleteByCalendarId(int calendarId) =>
      (_db.delete(_db.calendarEvents)
            ..where((e) => e.eventCalendarId.equals(calendarId)))
          .go();

  Future<void> replaceCalendarEvents({
    required int calendarId,
    required List<CalendarEventsCompanion> companions,
  }) async {
    final normalized = companions
        .map(
          (companion) => companion.copyWith(
            eventCalendarId: Value(calendarId),
          ),
        )
        .toList(growable: false);

    await _db.transaction(() async {
      await (_db.delete(_db.calendarEvents)
            ..where((e) => e.eventCalendarId.equals(calendarId)))
          .go();
      for (final companion in normalized) {
        await _ensureEventCalendarBinding(
          companion.eventCalendarId,
          requirePresent: true,
        );
        await _db.into(_db.calendarEvents).insert(companion);
      }
    });
  }

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
            (e) => e.source.equals(source) & e.eventCalendarId.equals(calendarId),
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
        await (_db.delete(_db.calendarEvents)..where((e) => e.id.isIn(duplicateIds)))
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
    return query.get().then(
          (rows) =>
              rows.map((row) => row.readTable(_db.calendarEvents)).toList(),
        );
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
    return query.get().then(
          (rows) =>
              rows.map((row) => row.readTable(_db.calendarEvents)).toList(),
        );
  }

  Future<void> _recordEventOperation({
    required String actor,
    required String action,
    required CalendarEvent? event,
    required String summary,
    Object? before,
    Object? after,
    Object? metadata,
  }) async {
    final operationLogs = _operationLogRepository;
    if (operationLogs == null || event == null) {
      return;
    }
    await operationLogs.record(
      actor: actor,
      action: action,
      entityType: 'calendar_event',
      entityId: event.id.toString(),
      summary: summary,
      before: before,
      after: after,
      metadata: metadata,
    );
  }
}
