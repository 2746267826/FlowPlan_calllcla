import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/ical/ical_import_export_page_body.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_path_provider.dart';
import 'provider_harness.dart';
import 'test_database.dart';

final DateTime icalHarnessStamp = DateTime.utc(2026, 6, 8, 9);

class ICalImportExportHarness {
  ICalImportExportHarness._({
    required this.db,
    required this.books,
    required this.events,
    required this.tasks,
    required this.filePicker,
    required this.documentsDirectory,
    required _ProviderSnapshotStream<EventCalendar> calendarStream,
    required _ProviderSnapshotStream<TaskList> taskListStream,
    required _ProviderSnapshotStream<TaskList> archivedTaskListStream,
  })  : _calendarStream = calendarStream,
        _taskListStream = taskListStream,
        _archivedTaskListStream = archivedTaskListStream;

  final AppDatabase db;
  final CalendarBooksRepository books;
  final EventRepository events;
  final TaskRepository tasks;
  final FakeICalFilePicker filePicker;
  final Directory documentsDirectory;
  final _ProviderSnapshotStream<EventCalendar> _calendarStream;
  final _ProviderSnapshotStream<TaskList> _taskListStream;
  final _ProviderSnapshotStream<TaskList> _archivedTaskListStream;

  static Future<ICalImportExportHarness> pump(
    WidgetTester tester, {
    Size size = const Size(900, 1400),
    FutureOr<void> Function(Directory documentsDirectory)? beforePump,
  }) async {
    final documentsDirectory = await setFakePathProviderDocumentsDirectory(
      'ical_import_export_widget_test_',
    );
    await beforePump?.call(documentsDirectory);
    final db = createTestDatabase();
    final books = CalendarBooksRepository(db);
    final events = EventRepository(db);
    final tasks = TaskRepository(db);
    final calendarStream = _ProviderSnapshotStream<EventCalendar>();
    final taskListStream = _ProviderSnapshotStream<TaskList>();
    final archivedTaskListStream = _ProviderSnapshotStream<TaskList>();
    final filePicker = FakeICalFilePicker();
    FilePicker? previousFilePicker;
    try {
      previousFilePicker = FilePicker.platform;
    } catch (_) {
      previousFilePicker = null;
    }
    FilePicker.platform = filePicker;

    addTearDown(() async {
      FilePicker.platform = previousFilePicker ?? FilePickerIO();
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await calendarStream.close();
      await taskListStream.close();
      await archivedTaskListStream.close();
      await db.close();
      if (documentsDirectory.existsSync()) {
        documentsDirectory.deleteSync(recursive: true);
      }
    });

    await _clearDefaultSeedData(db);

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: size,
      overrides: [
        allEventCalendarsProvider.overrideWith((ref) => calendarStream.stream),
        allTaskListsProvider.overrideWith((ref) => taskListStream.stream),
        archivedTaskListsProvider.overrideWith(
          (ref) => archivedTaskListStream.stream,
        ),
      ],
      child: const MaterialApp(
        home: ICalImportExportPage(),
      ),
    );
    await _refreshProviderSnapshots(
      db: db,
      calendarStream: calendarStream,
      taskListStream: taskListStream,
      archivedTaskListStream: archivedTaskListStream,
    );
    await pumpIcalFrames(tester);

    return ICalImportExportHarness._(
      db: db,
      books: books,
      events: events,
      tasks: tasks,
      filePicker: filePicker,
      documentsDirectory: documentsDirectory,
      calendarStream: calendarStream,
      taskListStream: taskListStream,
      archivedTaskListStream: archivedTaskListStream,
    );
  }

  File tempFile(String name) => File('${documentsDirectory.path}/$name');

  Future<int> createCalendar({
    required String name,
    String colorHex = '#6B5EE4',
    bool isDefault = false,
    String source = 'local',
    String? syncUrl,
  }) async {
    final id = await books.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: name,
        colorHex: Value(colorHex),
        isDefault: Value(isDefault),
        source: Value(source),
        syncUrl: Value(syncUrl),
        createdAt: icalHarnessStamp,
      ),
      audit: false,
    );
    await refreshProviderSnapshots();
    return id;
  }

  Future<int> createTaskList({
    required String name,
    String colorHex = '#0EA8A0',
    String? emoji,
    bool isDefault = false,
    bool isArchived = false,
  }) async {
    final id = await books.createTaskList(
      TaskListsCompanion.insert(
        name: name,
        colorHex: Value(colorHex),
        emoji: Value(emoji),
        isDefault: Value(isDefault),
        isArchived: Value(isArchived),
        createdAt: icalHarnessStamp,
      ),
      audit: false,
    );
    await refreshProviderSnapshots();
    return id;
  }

  Future<void> refreshProviderSnapshots() {
    return _refreshProviderSnapshots(
      db: db,
      calendarStream: _calendarStream,
      taskListStream: _taskListStream,
      archivedTaskListStream: _archivedTaskListStream,
    );
  }

  Future<int> createEvent({
    required int calendarId,
    required String uid,
    required String summary,
    DateTime? start,
    DateTime? end,
    String colorHex = '#6B5EE4',
    bool isBlock = false,
    String? description,
    String? location,
  }) {
    final dtstart = start ?? icalHarnessStamp;
    return events.create(
      CalendarEventsCompanion.insert(
        uid: uid,
        dtstamp: icalHarnessStamp,
        summary: summary,
        description: Value(description),
        location: Value(location),
        dtstart: dtstart,
        dtend: Value(end ?? dtstart.add(const Duration(hours: 1))),
        status: const Value('CONFIRMED'),
        transp: const Value('OPAQUE'),
        source: const Value('local'),
        eventCalendarId: Value(calendarId),
        colorHex: Value(colorHex),
        isBlock: Value(isBlock),
      ),
      audit: false,
    );
  }

  Future<int> createTask({
    required int taskListId,
    required String uid,
    required String summary,
  }) {
    return tasks.create(
      TaskItemsCompanion.insert(
        uid: uid,
        dtstamp: icalHarnessStamp,
        summary: summary,
        status: const Value('NEEDS-ACTION'),
        percentComplete: const Value(0),
        categories: const Value('[]'),
        durationMinutes: const Value(60),
        priorityLocal: const Value(2),
        isAutoScheduled: const Value(true),
        taskListId: Value(taskListId),
        reminderMinutesBefore: const Value(15),
      ),
      audit: false,
    );
  }

  Future<void> setCalendarDefaultIsBlock({
    required int calendarId,
    required bool value,
  }) {
    return books.saveEventCalendarDefaults(
      id: calendarId,
      defaultIsBlock: value,
      audit: false,
    );
  }

  Future<List<CalendarEvent>> eventsInCalendar(int calendarId) {
    return events.getByCalendarId(calendarId);
  }

  Future<List<TaskItem>> tasksInTaskList(int taskListId) {
    return tasks.getByTaskListIds([taskListId]);
  }
}

class _ProviderSnapshotStream<T> {
  _ProviderSnapshotStream() {
    _controller = StreamController<List<T>>.broadcast(
      onListen: () => _controller.add(_latest),
    );
  }

  late final StreamController<List<T>> _controller;
  List<T> _latest = const [];

  Stream<List<T>> get stream => _controller.stream;

  void add(List<T> values) {
    _latest = List<T>.unmodifiable(values);
    if (!_controller.isClosed) {
      _controller.add(_latest);
    }
  }

  Future<void> close() => _controller.close();
}

Future<void> _refreshProviderSnapshots({
  required AppDatabase db,
  required _ProviderSnapshotStream<EventCalendar> calendarStream,
  required _ProviderSnapshotStream<TaskList> taskListStream,
  required _ProviderSnapshotStream<TaskList> archivedTaskListStream,
}) async {
  calendarStream.add(await db.select(db.eventCalendars).get());
  taskListStream.add(
    await (db.select(db.taskLists)
          ..where((taskList) => taskList.isArchived.equals(false)))
        .get(),
  );
  archivedTaskListStream.add(
    await (db.select(db.taskLists)
          ..where((taskList) => taskList.isArchived.equals(true)))
        .get(),
  );
}

class FakeICalFilePicker extends FilePicker {
  final Queue<FilePickerResult?> _pickResults = Queue<FilePickerResult?>();
  final Queue<String?> _saveResults = Queue<String?>();
  final List<FakePickFilesRequest> pickRequests = <FakePickFilesRequest>[];
  final List<FakeSaveFileRequest> saveRequests = <FakeSaveFileRequest>[];

  void queuePickCancel() {
    _pickResults.add(null);
  }

  void queuePickText({
    required String name,
    required String content,
    String? path,
    bool malformedUtf8 = false,
  }) {
    final bytes = Uint8List.fromList([
      ...utf8.encode(content),
      if (malformedUtf8) 0xFF,
    ]);
    _pickResults.add(
      FilePickerResult([
        PlatformFile(
          name: name,
          path: path,
          size: bytes.length,
          bytes: bytes,
        ),
      ]),
    );
  }

  void queuePickPath(File file) {
    _pickResults.add(
      FilePickerResult([
        PlatformFile(
          name: file.uri.pathSegments.last,
          path: file.path,
          size: file.existsSync() ? file.lengthSync() : 0,
        ),
      ]),
    );
  }

  void queueUnreadableFile({String name = 'unreadable.ics'}) {
    _pickResults.add(
      FilePickerResult([
        PlatformFile(
          name: name,
          size: 0,
        ),
      ]),
    );
  }

  void queueSavePath(String? path) {
    _saveResults.add(path);
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    pickRequests.add(
      FakePickFilesRequest(
        dialogTitle: dialogTitle,
        type: type,
        allowedExtensions: allowedExtensions,
        withData: withData,
      ),
    );
    if (_pickResults.isEmpty) {
      return null;
    }
    return _pickResults.removeFirst();
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saveRequests.add(
      FakeSaveFileRequest(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: type,
        allowedExtensions: allowedExtensions,
      ),
    );
    if (_saveResults.isEmpty) {
      return null;
    }
    return _saveResults.removeFirst();
  }
}

class FakePickFilesRequest {
  const FakePickFilesRequest({
    required this.dialogTitle,
    required this.type,
    required this.allowedExtensions,
    required this.withData,
  });

  final String? dialogTitle;
  final FileType type;
  final List<String>? allowedExtensions;
  final bool withData;
}

class FakeSaveFileRequest {
  const FakeSaveFileRequest({
    required this.dialogTitle,
    required this.fileName,
    required this.type,
    required this.allowedExtensions,
  });

  final String? dialogTitle;
  final String? fileName;
  final FileType type;
  final List<String>? allowedExtensions;
}

Future<void> pumpIcalFrames(
  WidgetTester tester, {
  int frames = 8,
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tapIcalText(
  WidgetTester tester,
  String text, {
  Finder? within,
}) async {
  final finder = within == null
      ? find.text(text)
      : find.descendant(of: within, matching: find.text(text));
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await tester.pump();
}

Future<void> tapIcalButtonText(
  WidgetTester tester,
  String text, {
  Finder? within,
}) async {
  final finder = within == null
      ? find.text(text)
      : find.descendant(of: within, matching: find.text(text));
  await tester.ensureVisible(finder.last);
  await tester.tap(finder.last);
  await tester.pump();
}

Future<void> pumpUntilIcalFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 12,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

Future<void> _clearDefaultSeedData(AppDatabase db) async {
  await db.select(db.eventCalendars).get();
  await db.delete(db.calendarEvents).go();
  await db.delete(db.taskItems).go();
  await db.delete(db.eventCalendars).go();
  await db.delete(db.taskLists).go();
  await db.customStatement('DELETE FROM app_settings');
  await db.customStatement('DELETE FROM data_operation_logs');
}
