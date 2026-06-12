import 'dart:convert';
import 'dart:collection';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_settings_page.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_sync_policy.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_snapshot.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'test_database.dart';

const outlookExternalCalendarName = 'Outlook Team Calendar';
const outlookManagedContainerName = 'FlowPlanV2 Deep Work';
const outlookMirrorTaskListName = 'Mirror Inbox';
const outlookUnboundTaskListName = 'Mirror Backlog';
const outlookMovedTaskListName = 'Moved Mirror List';
const outlookLocalChangedTask = 'Alpha local task';
const outlookRemoteDeletedTask = 'Beta deleted remotely';
const outlookRemoteChangedTask = 'Aardvark edited remotely';
const outlookMovedTask = 'Delta moved target';

Future<OutlookSettingsHarness> pumpLocalOutlookSettings(
  WidgetTester tester, {
  Map<String, Object> preferences = const <String, Object>{},
  bool seedData = false,
  bool hideExternalCalendar = false,
  Object? diagnosticsWriteError,
  Size size = const Size(960, 1100),
  List<Override> extraOverrides = const <Override>[],
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(preferences);

  final db = createTestDatabase();
  final reminderService = FakeOutlookReminderService(db);
  final filePicker = FakeOutlookFilePicker();
  FilePicker? previousFilePicker;
  try {
    previousFilePicker = FilePicker.platform;
  } catch (_) {
    previousFilePicker = null;
  }
  FilePicker.platform = filePicker;
  final harness = OutlookSettingsHarness._(
    db: db,
    reminderService: reminderService,
    filePicker: filePicker,
    diagnosticsWriteError: diagnosticsWriteError,
  );
  if (seedData) {
    await harness.seedOutlookData();
    if (hideExternalCalendar) {
      await harness.setExternalCalendarVisible(false);
    }
  }
  final calendarsSnapshot = await db.select(db.eventCalendars).get();
  final taskListsSnapshot = await db.select(db.taskLists).get();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    FilePicker.platform = previousFilePicker ?? FilePickerIO();
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpOutlookSettingFrames(tester);
    reminderService.dispose();
    await db.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        allEventCalendarsProvider.overrideWith(
          (ref) => Stream.value(calendarsSnapshot),
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream.value(taskListsSnapshot),
        ),
        reminderServiceProvider.overrideWithValue(reminderService),
        outlookDiagnosticsReportWriterProvider
            .overrideWithValue(harness.writeDiagnosticsReport),
        ...extraOverrides,
      ],
      child: const MaterialApp(
        home: OutlookSettingsPage(serverManaged: false),
      ),
    ),
  );
  await pumpOutlookSettingFrames(tester);
  return harness;
}

Future<void> pumpOutlookSettingFrames(
  WidgetTester tester, {
  int frames = 8,
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, Object> outlookAuthPreferences({
  OutlookSyncMode syncMode = OutlookSyncMode.readOnly,
  OutlookSyncMode grantedMode = OutlookSyncMode.readOnly,
  String accessToken = 'access-token',
  String? refreshToken = 'refresh-token',
  String scope = 'Calendars.Read offline_access',
  DateTime? expiresAt,
  bool includeLastFailure = false,
  bool includeLastSuccess = false,
}) {
  final obtainedAt = DateTime.utc(2026, 6, 8, 8);
  return <String, Object>{
    'outlook_client_id': 'deep-test-client',
    'outlook_sync_mode': syncMode.storageValue,
    'outlook_auth_token': jsonEncode(<String, Object?>{
      'access_token': accessToken,
      if (refreshToken != null) 'refresh_token': refreshToken,
      'expires_in': 3600,
      'obtained_at': obtainedAt.toIso8601String(),
      'expires_at': (expiresAt ?? DateTime.utc(2099)).toIso8601String(),
      'granted_mode': grantedMode.storageValue,
      'scope': scope,
    }),
    if (includeLastFailure) ..._lastFailurePreferences(syncMode),
    if (includeLastSuccess) ..._lastSuccessPreferences(syncMode),
  };
}

Map<String, Object> _lastFailurePreferences(OutlookSyncMode mode) {
  final attemptedAt = DateTime.utc(2026, 6, 8, 10, 30);
  return <String, Object>{
    'outlook_last_sync': attemptedAt.toIso8601String(),
    'outlook_last_sync_report_time': attemptedAt.toIso8601String(),
    'outlook_last_sync_report_status': 'failure',
    'outlook_last_sync_report_mode': mode.name,
    'outlook_last_sync_report_calendar_books': 0,
    'outlook_last_sync_report_downloaded': 0,
    'outlook_last_sync_report_mirrored_created': 0,
    'outlook_last_sync_report_mirrored_updated': 0,
    'outlook_last_sync_report_mirrored_deleted': 0,
    'outlook_last_sync_report_mirrored_conflicted': 0,
    'outlook_last_sync_report_calendar_details': '[]',
    'outlook_last_sync_report_task_mirror_details': '[]',
    'outlook_last_sync_report_error': 'Graph throttled during deep test',
  };
}

Map<String, Object> _lastSuccessPreferences(OutlookSyncMode mode) {
  final attemptedAt = DateTime.utc(2026, 6, 8, 11, 45);
  return <String, Object>{
    'outlook_last_sync': attemptedAt.toIso8601String(),
    'outlook_last_sync_report_time': attemptedAt.toIso8601String(),
    'outlook_last_sync_report_status': 'success',
    'outlook_last_sync_report_mode': mode.name,
    'outlook_last_sync_report_calendar_books': 2,
    'outlook_last_sync_report_downloaded': 4,
    'outlook_last_sync_report_mirrored_created': 1,
    'outlook_last_sync_report_mirrored_updated': 2,
    'outlook_last_sync_report_mirrored_deleted': 1,
    'outlook_last_sync_report_mirrored_conflicted': 1,
    'outlook_last_sync_report_calendar_details': jsonEncode(
      <Map<String, Object?>>[
        <String, Object?>{
          'remote_calendar_id': 'remote-external',
          'local_calendar_id': 1,
          'calendar_name': outlookExternalCalendarName,
          'color_hex': '#0078D4',
          'downloaded': 3,
        },
        <String, Object?>{
          'remote_calendar_id': 'remote-managed',
          'local_calendar_id': 2,
          'calendar_name': outlookManagedContainerName,
          'color_hex': '#43A047',
          'downloaded': 1,
        },
      ],
    ),
    'outlook_last_sync_report_task_mirror_details': jsonEncode(
      <Map<String, Object?>>[
        <String, Object?>{
          'local_task_list_id': 1,
          'task_list_name': outlookMirrorTaskListName,
          'remote_calendar_id': 'mirror-active',
          'remote_calendar_name': 'FlowPlanV2 Inbox Mirror',
          'created': 1,
          'updated': 2,
          'deleted': 1,
          'conflicted': 1,
        },
      ],
    ),
  };
}

class OutlookSettingsHarness {
  OutlookSettingsHarness._({
    required this.db,
    required this.reminderService,
    required this.filePicker,
    this.diagnosticsWriteError,
  });

  final AppDatabase db;
  final FakeOutlookReminderService reminderService;
  final FakeOutlookFilePicker filePicker;
  final Object? diagnosticsWriteError;
  final diagnosticsWrites = <FakeOutlookDiagnosticsWrite>[];

  late final int externalCalendarId;
  late final int managedCalendarId;
  late final int activeTaskListId;
  late final int unboundTaskListId;
  late final int movedTaskListId;

  String get managedCalendarName => OutlookSyncPolicy.buildManagedCalendarName(
        kind: OutlookManagedCalendarKind.scheduleBook,
        containerName: outlookManagedContainerName,
      );

  Future<void> seedOutlookData() async {
    final now = fixtureNow();
    externalCalendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: outlookExternalCalendarName,
            colorHex: const Value('#0078D4'),
            source: const Value('outlook'),
            syncUrl: const Value('remote-external'),
            createdAt: now,
          ),
        );
    managedCalendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: managedCalendarName,
            colorHex: const Value('#43A047'),
            source: const Value('outlook'),
            syncUrl: const Value('remote-managed'),
            createdAt: now,
          ),
        );
    await insertFixtureCalendar(db, name: 'Local calendar');

    await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'outlook-event-external',
            dtstamp: now,
            summary: 'Outlook imported standup',
            dtstart: now,
            source: const Value('outlook'),
            eventCalendarId: Value(externalCalendarId),
          ),
        );
    await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'outlook-event-managed',
            dtstamp: now,
            summary: 'Managed focus block',
            dtstart: now.add(const Duration(hours: 2)),
            source: const Value('outlook'),
            eventCalendarId: Value(managedCalendarId),
          ),
        );

    activeTaskListId =
        await insertFixtureTaskList(db, name: outlookMirrorTaskListName);
    unboundTaskListId =
        await insertFixtureTaskList(db, name: outlookUnboundTaskListName);
    movedTaskListId =
        await insertFixtureTaskList(db, name: outlookMovedTaskListName);

    final bindingsRepository = OutlookSyncBindingsRepository(db);
    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: activeTaskListId,
        remoteCalendarId: 'mirror-active',
        remoteCalendarName: 'FlowPlanV2 Inbox Mirror',
        linkedAt: now,
      ),
    );
    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: movedTaskListId,
        remoteCalendarId: 'mirror-new-target',
        remoteCalendarName: 'FlowPlanV2 Moved New',
        linkedAt: now,
      ),
    );

    final taskRepository = TaskRepository(db);
    final mirrorRepository = OutlookTaskMirrorRepository(db);

    final localChangedId = await taskRepository.create(
      fixtureTask(
        uid: 'task-local-changed',
        summary: outlookLocalChangedTask,
        taskListId: activeTaskListId,
      ),
      audit: false,
    );
    await _saveMirrorForTask(
      taskRepository: taskRepository,
      mirrorRepository: mirrorRepository,
      taskId: localChangedId,
      taskListName: outlookMirrorTaskListName,
      remoteCalendarId: 'mirror-active',
      remoteCalendarName: 'FlowPlanV2 Inbox Mirror',
      remoteEventId: 'mirror-event-local-changed',
    );
    await (db.update(db.taskItems)
          ..where((task) => task.id.equals(localChangedId)))
        .write(
      const TaskItemsCompanion(
        summary: Value('Alpha local task edited'),
      ),
    );

    final remoteDeletedId = await taskRepository.create(
      fixtureTask(
        uid: 'task-remote-deleted',
        summary: outlookRemoteDeletedTask,
        taskListId: activeTaskListId,
      ),
      audit: false,
    );
    await _saveMirrorForTask(
      taskRepository: taskRepository,
      mirrorRepository: mirrorRepository,
      taskId: remoteDeletedId,
      taskListName: outlookMirrorTaskListName,
      remoteCalendarId: 'mirror-active',
      remoteCalendarName: 'FlowPlanV2 Inbox Mirror',
      remoteEventId: 'mirror-event-remote-deleted',
      conflictState: OutlookTaskMirrorConflictState.remoteDeleted,
      conflictMessage: 'Remote mirror was deleted before the next sync.',
    );

    final remoteChangedId = await taskRepository.create(
      fixtureTask(
        uid: 'task-remote-changed',
        summary: outlookRemoteChangedTask,
        taskListId: activeTaskListId,
      ),
      audit: false,
    );
    await _saveMirrorForTask(
      taskRepository: taskRepository,
      mirrorRepository: mirrorRepository,
      taskId: remoteChangedId,
      taskListName: outlookMirrorTaskListName,
      remoteCalendarId: 'mirror-active',
      remoteCalendarName: 'FlowPlanV2 Inbox Mirror',
      remoteEventId: 'mirror-event-remote-changed',
      conflictState: OutlookTaskMirrorConflictState.remoteChanged,
      conflictMessage: 'Remote mirror changed its subject.',
      remoteSummary: 'Gamma remote subject',
    );

    final movedTaskId = await taskRepository.create(
      fixtureTask(
        uid: 'task-moved-target',
        summary: outlookMovedTask,
        taskListId: movedTaskListId,
      ),
      audit: false,
    );
    await _saveMirrorForTask(
      taskRepository: taskRepository,
      mirrorRepository: mirrorRepository,
      taskId: movedTaskId,
      taskListName: outlookMovedTaskListName,
      remoteCalendarId: 'mirror-old-target',
      remoteCalendarName: 'FlowPlanV2 Moved Old',
      remoteEventId: 'mirror-event-moved',
    );

    final unboundTaskId = await taskRepository.create(
      fixtureTask(
        uid: 'task-unbound-list',
        summary: 'Epsilon unbound list',
        taskListId: unboundTaskListId,
      ),
      audit: false,
    );
    await _saveMirrorForTask(
      taskRepository: taskRepository,
      mirrorRepository: mirrorRepository,
      taskId: unboundTaskId,
      taskListName: outlookUnboundTaskListName,
      remoteCalendarId: 'mirror-unbound',
      remoteCalendarName: 'FlowPlanV2 Unbound Mirror',
      remoteEventId: 'mirror-event-unbound',
    );

    await mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: 9999,
        localTaskListId: activeTaskListId,
        remoteCalendarId: 'mirror-active',
        remoteCalendarName: 'FlowPlanV2 Inbox Mirror',
        remoteEventId: 'mirror-event-missing-local',
        syncedAt: now,
        conflictState: OutlookTaskMirrorConflictState.writeFailed,
        conflictMessage: 'Local task has already been deleted.',
      ),
    );
  }

  Future<void> writeDiagnosticsReport(String outputPath, String report) async {
    final error = diagnosticsWriteError;
    if (error != null) {
      throw error;
    }
    diagnosticsWrites.add(
      FakeOutlookDiagnosticsWrite(outputPath: outputPath, report: report),
    );
  }

  Future<int> countOutlookCalendars() async {
    final rows = await (db.select(db.eventCalendars)
          ..where((calendar) => calendar.source.equals('outlook')))
        .get();
    return rows.length;
  }

  Future<int> countVisibleOutlookCalendars() async {
    final rows = await (db.select(db.eventCalendars)
          ..where(
            (calendar) =>
                calendar.source.equals('outlook') &
                calendar.isVisible.equals(true),
          ))
        .get();
    return rows.length;
  }

  Future<int> countOutlookEvents() async {
    final rows = await (db.select(db.calendarEvents)
          ..where((event) => event.source.equals('outlook')))
        .get();
    return rows.length;
  }

  Future<void> setExternalCalendarVisible(bool isVisible) async {
    await (db.update(db.eventCalendars)
          ..where((calendar) => calendar.id.equals(externalCalendarId)))
        .write(EventCalendarsCompanion(isVisible: Value(isVisible)));
  }

  Future<bool> isCalendarVisible(int calendarId) async {
    final calendar = await (db.select(db.eventCalendars)
          ..where((row) => row.id.equals(calendarId)))
        .getSingle();
    return calendar.isVisible;
  }

  Future<bool> hasTaskListBinding(int taskListId) async {
    final binding =
        await OutlookSyncBindingsRepository(db).getTaskListBinding(taskListId);
    return binding != null;
  }

  Future<int> countTaskListBindings() async {
    final bindings =
        await OutlookSyncBindingsRepository(db).loadTaskListBindings();
    return bindings.length;
  }

  Future<int> countTaskMirrorBindings() async {
    final bindings =
        await OutlookTaskMirrorRepository(db).loadTaskMirrorBindings();
    return bindings.length;
  }
}

class FakeOutlookDiagnosticsWrite {
  const FakeOutlookDiagnosticsWrite({
    required this.outputPath,
    required this.report,
  });

  final String outputPath;
  final String report;
}

class FakeOutlookFilePicker extends FilePicker {
  final Queue<String?> _saveResults = Queue<String?>();
  final List<FakeOutlookSaveFileRequest> saveRequests =
      <FakeOutlookSaveFileRequest>[];

  void queueSavePath(String? path) {
    _saveResults.add(path);
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
      FakeOutlookSaveFileRequest(
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

class FakeOutlookSaveFileRequest {
  const FakeOutlookSaveFileRequest({
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

class FakeOutlookReminderService extends ReminderService {
  FakeOutlookReminderService(AppDatabase db)
      : super(
          database: db,
          defaultEventReminderMinutes: () => 0,
        );

  var rebuildCalls = 0;

  @override
  Future<ReminderRebuildResult> rebuildSystemSchedule() async {
    rebuildCalls++;
    return const ReminderRebuildResult(
      scheduledCount: 0,
      canScheduleExactAlarms: false,
    );
  }
}

Future<void> _saveMirrorForTask({
  required TaskRepository taskRepository,
  required OutlookTaskMirrorRepository mirrorRepository,
  required int taskId,
  required String taskListName,
  required String remoteCalendarId,
  required String remoteCalendarName,
  required String remoteEventId,
  OutlookTaskMirrorConflictState conflictState =
      OutlookTaskMirrorConflictState.none,
  String? conflictMessage,
  String? remoteSummary,
}) async {
  final task = await taskRepository.getById(taskId);
  final snapshot = OutlookTaskMirrorSnapshot.fromTask(
    task: task!,
    taskListName: taskListName,
  );
  final remoteSnapshot = remoteSummary == null
      ? snapshot
      : snapshot.copyWith(summary: remoteSummary);
  await mirrorRepository.saveTaskMirrorBinding(
    OutlookTaskMirrorBinding(
      localTaskId: taskId,
      localTaskListId: task.taskListId!,
      remoteCalendarId: remoteCalendarId,
      remoteCalendarName: remoteCalendarName,
      remoteEventId: remoteEventId,
      syncedAt: fixtureNow(),
      localSnapshotHash: snapshot.fingerprint,
      localSnapshotJson: snapshot.stableJson,
      remoteSnapshotHash: remoteSnapshot.fingerprint,
      remoteSnapshotJson: remoteSnapshot.stableJson,
      conflictState: conflictState,
      conflictMessage: conflictMessage,
      conflictDetectedAt: conflictState == OutlookTaskMirrorConflictState.none
          ? null
          : fixtureNow(),
    ),
  );
}
