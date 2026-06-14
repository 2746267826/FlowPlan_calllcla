import 'dart:async';

import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/online/online_primary_policy.dart';
import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/presentation/event_detail_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

const _timelineRoute = '/timeline';
const _eventCreateRoute = '/event/create';
const _eventDetailRoute = '/event/:id';
const _writablePolicy = OnlinePrimaryPolicy(
  serverReachable: true,
  authenticated: true,
  level: ServerConnectionLevel.online,
);
const _readOnlyPolicy = OnlinePrimaryPolicy(
  serverReachable: false,
  authenticated: true,
  level: ServerConnectionLevel.localCacheOnly,
);

void main() {
  testWidgets(
    'create event saves selected calendar defaults and edited payload fields',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final fakeStore = FakeTaskEventServerFirstStore();
      await insertFixtureCalendar(db, name: 'Personal');
      final focusCalendarId = await insertFixtureCalendar(db, name: 'Focus');
      await CalendarBooksRepository(db).saveEventCalendarDefaults(
        id: focusCalendarId,
        defaultIsBlock: true,
        audit: false,
      );

      await _pumpEventDetailRoute(
        tester,
        db: db,
        fakeStore: fakeStore,
        initialLocation: _eventCreateRoute,
      );
      await _pumpUntil(tester, () => find.text('Focus').evaluate().isNotEmpty);

      await _tapGestureByText(tester, 'Focus');
      await _pumpUntil(
        tester,
        () => tester.widgetList<Switch>(find.byType(Switch)).last.value,
      );
      await tester.enterText(
        find.byKey(AppKeys.eventSummaryField),
        '  Focus planning  ',
      );
      await tester.enterText(find.byType(TextField).at(1), '  Room 8  ');
      await tester.enterText(find.byType(TextField).at(2), '  Bring notes  ');
      await _tapChoiceChip(tester, '暂定');
      await _tapChoiceChip(tester, '每周');
      await tester.ensureVisible(find.byType(GestureDetector).last);
      await tester.tap(find.byType(GestureDetector).last);
      await tester.pump();

      await tester.tap(find.byKey(AppKeys.eventSaveButton));
      await _pumpUntil(tester, () => fakeStore.createdEvents.isNotEmpty);

      final payload = fakeStore.createdEvents.single;
      expect(payload['summary'], 'Focus planning');
      expect(payload['title'], 'Focus planning');
      expect(payload['location'], 'Room 8');
      expect(payload['description'], 'Bring notes');
      expect(payload['eventCalendarId'], focusCalendarId);
      expect(payload['status'], 'TENTATIVE');
      expect(payload['rrule'], 'FREQ=WEEKLY');
      expect(payload['isBlock'], isTrue);
      expect(payload['colorHex'], isA<String>());
      expect(payload['uid'], isA<String>());
      expect(
          DateTime.parse(payload['endAt']! as String)
              .isAfter(DateTime.parse(payload['startAt']! as String)),
          isTrue);
      await _pumpUntil(
        tester,
        () => find.text('timeline fallback').evaluate().isNotEmpty,
      );
    },
  );

  testWidgets('blank title validates before store calls', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    await insertFixtureCalendar(db, name: 'Writable');

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: _eventCreateRoute,
    );
    await _pumpUntil(tester, () => find.text('Writable').evaluate().isNotEmpty);
    await tester.tap(find.byKey(AppKeys.eventSaveButton));
    await tester.pump();
    expect(find.text('请输入日程标题'), findsOneWidget);

    expect(fakeStore.createdEvents, isEmpty);
    expect(find.byType(EventDetailPage), findsOneWidget);
  });

  testWidgets('create save guard blocks selected Outlook calendar',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await insertFixtureCalendar(db, name: 'Writable first');
    final calendarUpdates = StreamController<List<EventCalendar>>.broadcast(
      sync: true,
    );
    addTearDown(calendarUpdates.close);

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: _eventCreateRoute,
      calendarStream: calendarUpdates.stream,
    );
    calendarUpdates.add(await db.select(db.eventCalendars).get());
    await _pumpUntil(
        tester, () => find.text('Writable first').evaluate().isNotEmpty);
    await _tapGestureByText(tester, 'Writable first');
    await tester.enterText(
      find.byKey(AppKeys.eventSummaryField),
      'Should not create remotely',
    );

    await (db.update(db.eventCalendars)
          ..where((row) => row.id.equals(calendarId)))
        .write(
      const EventCalendarsCompanion(
        source: Value('outlook'),
        syncUrl: Value('remote-calendar'),
      ),
    );
    calendarUpdates.add(await db.select(db.eventCalendars).get());
    await tester.pump();

    await tester.tap(find.byKey(AppKeys.eventSaveButton));
    await _pumpUntil(
      tester,
      () => find.textContaining('Outlook').evaluate().isNotEmpty,
    );

    expect(find.textContaining('Outlook'), findsWidgets);
    expect(fakeStore.createdEvents, isEmpty);
    expect(find.byType(EventDetailPage), findsOneWidget);
  });

  testWidgets('save failure re-enables save and keeps user on detail page',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = _FailingEventStore(createError: StateError('offline'));
    await insertFixtureCalendar(db, name: 'Writable');

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: _eventCreateRoute,
    );
    await _pumpUntil(tester, () => find.text('Writable').evaluate().isNotEmpty);
    await tester.enterText(find.byKey(AppKeys.eventSummaryField), 'Retry me');

    await tester.tap(find.byKey(AppKeys.eventSaveButton));
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.textContaining('保存失败').evaluate().isNotEmpty,
    );

    expect(fakeStore.createdEvents, isEmpty);
    expect(find.byType(EventDetailPage), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('save button is disabled while a create request is in flight',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final completer = Completer<ServerFirstWriteResult>();
    final fakeStore = _SlowEventStore(createCompleter: completer);
    await insertFixtureCalendar(db, name: 'Writable');

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: _eventCreateRoute,
    );
    await _pumpUntil(tester, () => find.text('Writable').evaluate().isNotEmpty);
    await tester.enterText(find.byKey(AppKeys.eventSummaryField), 'One click');

    await tester.tap(find.byKey(AppKeys.eventSaveButton));
    await tester.pump();

    expect(fakeStore.createAttempts, 1);
    expect(_saveButton(tester).onPressed, isNull);

    completer.complete(_writeResult(<String, Object?>{'uid': 'created'}));
    await _pumpUntil(
      tester,
      () => find.text('timeline fallback').evaluate().isNotEmpty,
    );
    expect(fakeStore.createdEvents, hasLength(1));
  });

  testWidgets('close button falls back to timeline without saving',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    await insertFixtureCalendar(db, name: 'Writable');

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: _eventCreateRoute,
    );
    await _pumpUntil(tester, () => find.text('Writable').evaluate().isNotEmpty);
    await tester.enterText(find.byKey(AppKeys.eventSummaryField), 'Draft');

    await tester.tap(find.byIcon(Icons.close));
    await _pumpUntil(
      tester,
      () => find.text('timeline fallback').evaluate().isNotEmpty,
    );

    expect(fakeStore.createdEvents, isEmpty);
  });

  testWidgets('delete confirmation cancel does not call store', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await insertFixtureCalendar(db, name: 'Writable');
    final eventId = await _insertEvent(
      db,
      calendarId: calendarId,
      uid: 'cancel-delete',
      summary: 'Keep me',
    );

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: '/event/$eventId',
    );
    await _pumpUntilTextField(tester, 'Keep me');

    await tester.tap(find.byIcon(Icons.delete_outline));
    await _pumpUntil(
        tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.text('取消'),
          )
          .last,
    );
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fakeStore.deletedEventIds, isEmpty);
    expect(find.byType(EventDetailPage), findsOneWidget);
  });

  testWidgets('delete guard blocks when selected calendar becomes Outlook',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await insertFixtureCalendar(db, name: 'Initially local');
    final eventId = await _insertEvent(
      db,
      calendarId: calendarId,
      uid: 'outlook-delete-guard',
      summary: 'Guarded delete',
    );
    final calendarUpdates = StreamController<List<EventCalendar>>.broadcast(
      sync: true,
    );
    addTearDown(calendarUpdates.close);

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: '/event/$eventId',
      calendarStream: calendarUpdates.stream,
    );
    calendarUpdates.add(await db.select(db.eventCalendars).get());
    await _pumpUntilTextField(tester, 'Guarded delete');
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await (db.update(db.eventCalendars)
          ..where((row) => row.id.equals(calendarId)))
        .write(
      const EventCalendarsCompanion(
        source: Value('outlook'),
        syncUrl: Value('remote-calendar'),
      ),
    );
    calendarUpdates.add(await db.select(db.eventCalendars).get());

    await tester.tap(find.byIcon(Icons.delete_outline));
    await _pumpUntil(
      tester,
      () => find.textContaining('Outlook').evaluate().isNotEmpty,
    );

    expect(fakeStore.deletedEventIds, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('delete failure re-enables delete and stays on detail page',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = _FailingEventStore(deleteError: StateError('locked'));
    final calendarId = await insertFixtureCalendar(db, name: 'Writable');
    final eventId = await _insertEvent(
      db,
      calendarId: calendarId,
      uid: 'delete-fails',
      summary: 'Delete fails',
    );

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: '/event/$eventId',
    );
    await _pumpUntilTextField(tester, 'Delete fails');

    await tester.tap(find.byIcon(Icons.delete_outline));
    await _pumpUntil(
        tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
    await tester.tap(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.text('删除'),
          )
          .last,
    );
    await _pumpUntil(
      tester,
      () => find.textContaining('删除失败').evaluate().isNotEmpty,
    );

    expect(fakeStore.deletedEventIds, isEmpty);
    expect(find.byType(EventDetailPage), findsOneWidget);
    expect(_deleteButton(tester).onPressed, isNotNull);
  });

  testWidgets(
      'read-only cache shows event banner and disables save/delete controls',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await insertFixtureCalendar(db, name: 'Writable');
    final eventId = await _insertEvent(
      db,
      calendarId: calendarId,
      uid: 'event-read-only-cache',
      summary: 'Cached event',
    );

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: '/event/$eventId',
      readOnlyCache: true,
    );
    await _pumpUntilTextField(tester, 'Cached event');

    expect(find.text('Offline cache is read-only'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    expect(_deleteButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(AppKeys.eventSaveButton));
    await tester.tap(find.byIcon(Icons.delete_outline), warnIfMissed: false);
    await tester.pump();

    expect(fakeStore.updatedEvents, isEmpty);
    expect(fakeStore.deletedEventIds, isEmpty);
    expect(find.byType(EventDetailPage), findsOneWidget);
  });

  testWidgets('stale event save callback re-checks read-only cache policy',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await insertFixtureCalendar(db, name: 'Writable');
    final eventId = await _insertEvent(
      db,
      calendarId: calendarId,
      uid: 'event-stale-read-only-save',
      summary: 'Stale save guard',
    );
    var policy = _writablePolicy;

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: '/event/$eventId',
      policyProvider: () => policy,
    );
    await _pumpUntilTextField(tester, 'Stale save guard');
    expect(_saveButton(tester).onPressed, isNotNull);

    policy = _readOnlyPolicy;
    ProviderScope.containerOf(
      tester.element(find.byType(EventDetailPage)),
    ).invalidate(onlinePrimaryPolicyProvider);
    await tester.tap(find.byKey(AppKeys.eventSaveButton));
    await tester.pump();

    expect(
      find.text('Offline cache is read-only. Reconnect to save changes.'),
      findsOneWidget,
    );
    expect(fakeStore.updatedEvents, isEmpty);
  });

  testWidgets('stale event delete callback re-checks read-only cache policy',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await insertFixtureCalendar(db, name: 'Writable');
    final eventId = await _insertEvent(
      db,
      calendarId: calendarId,
      uid: 'event-stale-read-only-delete',
      summary: 'Stale delete guard',
    );
    var policy = _writablePolicy;

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: '/event/$eventId',
      policyProvider: () => policy,
    );
    await _pumpUntilTextField(tester, 'Stale delete guard');
    expect(_deleteButton(tester).onPressed, isNotNull);

    policy = _readOnlyPolicy;
    ProviderScope.containerOf(
      tester.element(find.byType(EventDetailPage)),
    ).invalidate(onlinePrimaryPolicyProvider);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(
      find.text('Offline cache is read-only. Reconnect to save changes.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(fakeStore.deletedEventIds, isEmpty);
  });

  testWidgets('all-day date picking validates and saves adjusted dates',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await insertFixtureCalendar(db, name: 'Writable');
    final eventId = await _insertEvent(
      db,
      calendarId: calendarId,
      uid: 'all-day',
      summary: 'All day',
      start: DateTime(2026, 6, 10, 9),
      end: DateTime(2026, 6, 10, 10),
    );

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: '/event/$eventId',
    );
    await _pumpUntilTextField(tester, 'All day');
    await tester.tap(find.widgetWithText(SwitchListTile, '全天'));
    await tester.pump();

    await _tapDateText(tester, '2026年6月10日', occurrence: 1);
    await tester.pumpAndSettle();
    await _tapDatePickerDay(tester, '9');
    await tester.tap(find.byType(TextButton).last);
    await tester.pump();
    expect(find.textContaining('结束时间必须晚于或等于开始时间'), findsOneWidget);

    await _tapDateText(tester, '2026年6月10日', occurrence: 0);
    await tester.pumpAndSettle();
    await _tapDatePickerDay(tester, '12');
    await tester.tap(find.byType(TextButton).last);
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.eventSaveButton));
    await _pumpUntil(tester, () => fakeStore.updatedEvents.isNotEmpty);

    final payload = fakeStore.updatedEvents.single.payload;
    expect(
        DateTime.parse(payload['startAt']! as String), DateTime(2026, 6, 12));
    expect(DateTime.parse(payload['endAt']! as String), DateTime(2026, 6, 12));
  });

  testWidgets('outlook event is read only and disables save/delete editing',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final fakeStore = FakeTaskEventServerFirstStore();
    final calendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Outlook',
            createdAt: fixtureNow(),
            source: const Value('outlook'),
            syncUrl: const Value('remote-calendar'),
          ),
        );
    final eventId = await _insertEvent(
      db,
      calendarId: calendarId,
      uid: 'outlook-readonly',
      summary: 'Remote standup',
      source: const Value('outlook'),
    );

    await _pumpEventDetailRoute(
      tester,
      db: db,
      fakeStore: fakeStore,
      initialLocation: '/event/$eventId',
    );
    await _pumpUntilTextField(tester, 'Remote standup');

    expect(find.text('Outlook 日程（只读）'), findsOneWidget);
    expect(find.textContaining('Outlook 官方客户端'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    await tester.tap(find.byKey(AppKeys.eventSaveButton));
    await tester.enterText(find.byKey(AppKeys.eventSummaryField), 'Ignored');
    await tester.pump();
    expect(fakeStore.updatedEvents, isEmpty);
  });
}

Future<void> _pumpEventDetailRoute(
  WidgetTester tester, {
  required AppDatabase db,
  required String initialLocation,
  required FakeTaskEventServerFirstStore fakeStore,
  Stream<List<EventCalendar>>? calendarStream,
  bool readOnlyCache = false,
  OnlinePrimaryPolicy Function()? policyProvider,
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
    size: const Size(900, 1400),
    overrides: [
      onlinePrimaryPolicyProvider.overrideWith(
        (ref) =>
            policyProvider?.call() ??
            (readOnlyCache ? _readOnlyPolicy : _writablePolicy),
      ),
      allEventCalendarsProvider.overrideWith(
        (ref) => calendarStream ?? Stream.value(calendars),
      ),
      taskEventServerFirstStoreProvider.overrideWith((ref) async => fakeStore),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
}

Future<int> _insertEvent(
  AppDatabase db, {
  required int calendarId,
  required String uid,
  required String summary,
  DateTime? start,
  DateTime? end,
  Value<String> source = const Value.absent(),
}) {
  final eventStart = start ?? DateTime.utc(2026, 6, 10, 9);
  return db.into(db.calendarEvents).insert(
        CalendarEventsCompanion.insert(
          uid: uid,
          dtstamp: fixtureNow(),
          summary: summary,
          dtstart: eventStart,
          dtend: Value(end ?? eventStart.add(const Duration(hours: 1))),
          eventCalendarId: Value(calendarId),
          source: source,
        ),
      );
}

TextButton _saveButton(WidgetTester tester) {
  return tester.widget<TextButton>(find.byKey(AppKeys.eventSaveButton));
}

IconButton _deleteButton(WidgetTester tester) {
  return tester.widget<IconButton>(
    find.ancestor(
      of: find.byIcon(Icons.delete_outline),
      matching: find.byType(IconButton),
    ),
  );
}

Future<void> _tapChoiceChip(WidgetTester tester, String label) async {
  final chip = find.ancestor(
    of: find.text(label),
    matching: find.byType(ChoiceChip),
  );
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

Future<void> _tapGestureByText(WidgetTester tester, String text) async {
  final target = find.ancestor(
    of: find.text(text),
    matching: find.byType(GestureDetector),
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> _tapDatePickerDay(WidgetTester tester, String day) async {
  final dayText = find.descendant(
    of: find.byType(CalendarDatePicker),
    matching: find.text(day),
  );
  await tester.tap(dayText.last);
  await tester.pump();
}

Future<void> _tapDateText(
  WidgetTester tester,
  String text, {
  required int occurrence,
}) async {
  final label = find.text(text).at(occurrence);
  final tile = find.ancestor(
    of: label,
    matching: find.byType(InkWell),
  );
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pump();
}

Future<void> _pumpUntilTextField(WidgetTester tester, String text) {
  return _pumpUntil(
    tester,
    () {
      final field = tester.widget<TextField>(
        find.byKey(AppKeys.eventSummaryField),
      );
      return field.controller?.text == text;
    },
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue);
}

class _FailingEventStore extends FakeTaskEventServerFirstStore {
  _FailingEventStore({this.createError, this.deleteError});

  final Object? createError;
  final Object? deleteError;

  @override
  Future<ServerFirstWriteResult> createEvent(
    Map<String, Object?> payload,
  ) async {
    final error = createError;
    if (error != null) {
      throw error;
    }
    return super.createEvent(payload);
  }

  @override
  Future<ServerFirstWriteResult> deleteLocalEvent({
    required int localId,
    int? baseServerVersion,
  }) async {
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    return super.deleteLocalEvent(
      localId: localId,
      baseServerVersion: baseServerVersion,
    );
  }
}

class _SlowEventStore extends FakeTaskEventServerFirstStore {
  _SlowEventStore({required this.createCompleter});

  final Completer<ServerFirstWriteResult> createCompleter;
  var createAttempts = 0;

  @override
  Future<ServerFirstWriteResult> createEvent(
    Map<String, Object?> payload,
  ) async {
    createAttempts++;
    createdEvents.add(Map<String, Object?>.from(payload));
    return createCompleter.future;
  }
}

ServerFirstWriteResult _writeResult(Map<String, Object?> payload) {
  return ServerFirstWriteResult.canonical(
    <String, dynamic>{
      'serverVersion': 1,
      'item': <String, dynamic>{
        'id': 'event-created',
        'uid': payload['uid'],
        'payload': payload,
      },
    },
  );
}
