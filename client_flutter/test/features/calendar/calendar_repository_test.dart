import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

typedef _Evidence = ({
  DataOperationLogRepository auditRepository,
  OfflineMutationStore mutationStore,
  SyncWriteRecorder recorder,
});

void main() {
  test('calendar event repository returns events for the selected day',
      () async {
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

  test('event calendar defaults switch only between local calendars', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(db);

    final firstId = await repository.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Local A',
        createdAt: fixtureNow(),
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final secondId = await repository.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Local B',
        createdAt: fixtureNow().add(const Duration(minutes: 1)),
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final syncedId = await repository.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Outlook',
        createdAt: fixtureNow().add(const Duration(minutes: 2)),
        source: const Value('outlook'),
        syncUrl: const Value('remote-calendar'),
        isDefault: const Value(true),
      ),
      audit: false,
    );

    expect(
        (await repository.getEventCalendarById(firstId))?.isDefault, isFalse);
    expect(
        (await repository.getEventCalendarById(secondId))?.isDefault, isTrue);
    expect(
        (await repository.getEventCalendarById(syncedId))?.isDefault, isFalse);
    await expectLater(
      repository.setDefaultEventCalendar(syncedId, audit: false),
      throwsA(isA<StateError>()),
    );
  });

  test('deleting a local event calendar migrates events and records evidence',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final evidence = _createEvidence(db);
    final booksRepository = CalendarBooksRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );

    final sourceId = await booksRepository.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Primary',
        createdAt: fixtureNow(),
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final fallbackId = await booksRepository.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: 'Fallback',
        createdAt: fixtureNow().add(const Duration(minutes: 1)),
      ),
      audit: false,
    );
    final eventId = await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'event-migrates',
            summary: 'Move me',
            calendarId: sourceId,
          ),
        );

    final deleted = await booksRepository.deleteEventCalendar(sourceId);

    final event = await EventRepository(db).getById(eventId);
    final auditRows = await evidence.auditRepository.listRecent();
    final pendingMutations = await evidence.mutationStore.listPending();

    expect(deleted, 1);
    expect(event?.eventCalendarId, fallbackId);
    expect(await booksRepository.getEventCalendarById(sourceId), isNull);
    expect(
      (await booksRepository.getEventCalendarById(fallbackId))?.isDefault,
      isTrue,
    );
    expect(
      auditRows.where(
        (row) =>
            row.entityType == 'event_calendar' &&
            row.action == 'delete' &&
            row.metadataJson?.contains('"event_count":1') == true,
      ),
      isNotEmpty,
    );
    expect(
      pendingMutations.map((mutation) => mutation.objectType),
      containsAll(<String>['calendar_book', 'audit_log']),
    );
    expect(
      pendingMutations.where(
        (mutation) =>
            mutation.objectType == 'calendar_book' &&
            mutation.action.name == 'delete',
      ),
      isNotEmpty,
    );
  });

  test('synced event calendar upsert dedupes books and migrates events',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = CalendarBooksRepository(db);

    final firstId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Remote old',
            createdAt: fixtureNow(),
            source: const Value('outlook'),
            syncUrl: const Value('remote-1'),
          ),
        );
    final duplicateId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Remote duplicate',
            createdAt: fixtureNow().add(const Duration(minutes: 1)),
            source: const Value('outlook'),
            syncUrl: const Value('remote-1'),
          ),
        );
    final eventId = await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'synced-event',
            summary: 'Remote event',
            calendarId: duplicateId,
          ),
        );

    final upsertedId = await repository.upsertSyncedEventCalendar(
      source: 'outlook',
      remoteId: 'remote-1',
      name: 'Remote renamed',
      colorHex: '#123456',
      audit: false,
    );

    final calendars = await repository.getEventCalendarsBySource('outlook');
    final migratedEvent = await EventRepository(db).getById(eventId);

    expect(upsertedId, firstId);
    expect(calendars, hasLength(1));
    expect(calendars.single.name, 'Remote renamed');
    expect(calendars.single.colorHex, '#123456');
    expect(migratedEvent?.eventCalendarId, firstId);
  });

  test(
      'container audit summaries use before names when rows vanish after write',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final evidence = _createEvidence(db);
    final repository = CalendarBooksRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );
    final calendarForDefaults = await insertFixtureCalendar(
      db,
      name: 'Before defaults calendar',
    );
    final calendarForVisible = await insertFixtureCalendar(
      db,
      name: 'Before visible calendar',
    );
    final taskListForDefaults = await insertFixtureTaskList(
      db,
      name: 'Before defaults tasks',
    );

    await db.customStatement('''
      CREATE TRIGGER delete_calendar_after_setting_write
      AFTER INSERT ON app_settings
      WHEN NEW.setting_key = 'event_calendar.default_is_block.v1.$calendarForDefaults'
      BEGIN
        DELETE FROM event_calendars WHERE id = $calendarForDefaults;
      END
    ''');
    await db.customStatement('''
      CREATE TRIGGER delete_calendar_after_visibility_update
      AFTER UPDATE ON event_calendars
      WHEN NEW.id = $calendarForVisible
      BEGIN
        DELETE FROM event_calendars WHERE id = NEW.id;
      END
    ''');
    await db.customStatement('''
      CREATE TRIGGER delete_task_list_after_setting_write
      AFTER INSERT ON app_settings
      WHEN NEW.setting_key = 'task_list.default_auto_scheduled.v1.$taskListForDefaults'
      BEGIN
        DELETE FROM task_lists WHERE id = $taskListForDefaults;
      END
    ''');

    await repository.saveEventCalendarDefaults(
      id: calendarForDefaults,
      defaultIsBlock: true,
    );
    await repository.toggleEventCalendarVisible(calendarForVisible, false);
    await repository.saveTaskListDefaults(
      id: taskListForDefaults,
      defaultIsAutoScheduled: false,
      defaultReminderMinutesBefore: 45,
    );

    final auditRows = await evidence.auditRepository.listRecent(limit: 10);

    expect(
      auditRows.map((row) => row.summary),
      containsAll(<Matcher>[
        contains('Before defaults calendar'),
        contains('Before visible calendar'),
        contains('Before defaults tasks'),
      ]),
    );
    expect(
      auditRows
          .where((row) =>
              row.entityId == '$calendarForDefaults' ||
              row.entityId == '$calendarForVisible' ||
              row.entityId == '$taskListForDefaults')
          .map((row) => row.afterJson),
      everyElement(isNull),
    );
  });

  test('event repository validates bindings and filters visible calendars',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = EventRepository(db);
    final visibleCalendarId = await insertFixtureCalendar(
      db,
      name: 'Visible',
    );
    final hiddenCalendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Hidden',
            createdAt: fixtureNow(),
            isVisible: const Value(false),
          ),
        );
    final visibleEventId = await repository.create(
      fixtureEvent(
        uid: 'visible-event',
        summary: 'Visible event',
        calendarId: visibleCalendarId,
      ),
      audit: false,
    );
    await repository.create(
      fixtureEvent(
        uid: 'hidden-event',
        summary: 'Hidden event',
        calendarId: hiddenCalendarId,
      ),
      audit: false,
    );

    final visibleEvents = await repository
        .watchVisibleForDateRange(
          fixtureNow().subtract(const Duration(hours: 1)),
          fixtureNow().add(const Duration(hours: 1)),
        )
        .first;
    final visibleDayEvents =
        await repository.watchVisibleForDate(fixtureNow()).first;

    expect(visibleEvents.map((event) => event.summary), ['Visible event']);
    expect(visibleDayEvents.map((event) => event.summary), ['Visible event']);
    await expectLater(
      repository.create(
        CalendarEventsCompanion.insert(
          uid: 'missing-calendar',
          dtstamp: fixtureNow(),
          summary: 'No calendar',
          dtstart: fixtureNow(),
          eventCalendarId: const Value(null),
        ),
      ),
      throwsA(isA<StateError>()),
    );
    final existing = await repository.getById(visibleEventId);
    await expectLater(
      repository.update(
        existing!.toCompanion(false).copyWith(
              eventCalendarId: const Value(9999),
            ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('event update, times and delete write audit and sync evidence',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final evidence = _createEvidence(db);
    final repository = EventRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );
    final calendarId = await insertFixtureCalendar(db);
    final eventId = await repository.create(
      fixtureEvent(
        uid: 'event-audit',
        summary: 'Original',
        calendarId: calendarId,
      ),
      audit: false,
    );
    final original = await repository.getById(eventId);

    await repository.update(
      original!.toCompanion(false).copyWith(
            summary: const Value('Updated'),
          ),
    );
    await repository.updateTimes(
      eventId,
      fixtureNow().add(const Duration(hours: 2)),
      fixtureNow().add(const Duration(hours: 3)),
    );
    final deleted = await repository.delete(eventId);

    final auditRows = await evidence.auditRepository.listRecent();
    final pendingMutations = await evidence.mutationStore.listPending();

    expect(deleted, 1);
    expect(await repository.getById(eventId), isNull);
    expect(
      auditRows
          .where((row) => row.entityType == 'calendar_event')
          .map((row) => row.action),
      containsAll(<String>['update', 'delete']),
    );
    expect(
      pendingMutations
          .where((mutation) => mutation.objectType == 'calendar_event')
          .map((mutation) => mutation.action.name),
      containsAll(<String>['update', 'delete']),
    );
    expect(
      pendingMutations.where(
        (mutation) =>
            mutation.objectType == 'calendar_event' &&
            mutation.changedFieldsJson?.contains('dtstart') == true &&
            mutation.changedFieldsJson?.contains('dtend') == true,
      ),
      isNotEmpty,
    );
  });

  test('synced event upsert dedupes existing uid and updates canonical row',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = EventRepository(db);
    final calendarId = await insertFixtureCalendar(db);

    await repository.upsertSyncedEvent(
      uid: 'remote-event',
      dtstamp: fixtureNow(),
      summary: 'Remote first',
      dtstart: fixtureNow(),
      dtend: fixtureNow().add(const Duration(hours: 1)),
      status: 'CONFIRMED',
      source: 'outlook',
      eventCalendarId: calendarId,
      colorHex: '#101010',
    );
    final canonical = (await repository.getAllByUid('remote-event')).single;
    await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'remote-event',
            summary: 'Duplicate',
            calendarId: calendarId,
          ),
        );

    await repository.upsertSyncedEvent(
      uid: 'remote-event',
      dtstamp: fixtureNow().add(const Duration(minutes: 1)),
      summary: 'Remote updated',
      dtstart: fixtureNow().add(const Duration(hours: 2)),
      dtend: fixtureNow().add(const Duration(hours: 3)),
      status: 'TENTATIVE',
      source: 'outlook',
      eventCalendarId: calendarId,
      colorHex: '#202020',
      isBlock: true,
    );

    final rows = await repository.getAllByUid('remote-event');

    expect(rows, hasLength(1));
    expect(rows.single.id, canonical.id);
    expect(rows.single.summary, 'Remote updated');
    expect(rows.single.status, 'TENTATIVE');
    expect(rows.single.colorHex, '#202020');
    expect(rows.single.isBlock, isTrue);
  });
}

_Evidence _createEvidence(AppDatabase db) {
  final mutationStore = OfflineMutationStore(db);
  final recorder = SyncWriteRecorder(
    mutationStore: mutationStore,
    stateStore: SyncObjectStateStore(db),
  );
  return (
    auditRepository: DataOperationLogRepository(db, recorder),
    mutationStore: mutationStore,
    recorder: recorder,
  );
}
