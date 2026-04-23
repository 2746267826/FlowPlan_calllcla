import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../calendar/data/calendar_books_repository.dart';
import '../calendar/data/event_repository.dart';
import '../task/data/task_repository.dart';
import 'ms_graph_service.dart';
import 'outlook_auth_service.dart';
import 'outlook_sync_policy.dart';
import 'outlook_sync_bindings_repository.dart';
import 'outlook_task_mirror_repository.dart';
import 'outlook_task_mirror_sync_service.dart';

class OutlookSyncedCalendarSummary {
  const OutlookSyncedCalendarSummary({
    required this.remoteCalendarId,
    required this.localCalendarId,
    required this.calendarName,
    required this.colorHex,
    required this.downloaded,
  });

  final String remoteCalendarId;
  final int localCalendarId;
  final String calendarName;
  final String colorHex;
  final int downloaded;

  Map<String, dynamic> toJson() => {
        'remote_calendar_id': remoteCalendarId,
        'local_calendar_id': localCalendarId,
        'calendar_name': calendarName,
        'color_hex': colorHex,
        'downloaded': downloaded,
      };

  factory OutlookSyncedCalendarSummary.fromJson(Map<String, dynamic> json) {
    return OutlookSyncedCalendarSummary(
      remoteCalendarId: (json['remote_calendar_id'] as String? ?? '').trim(),
      localCalendarId: json['local_calendar_id'] as int? ?? 0,
      calendarName: (json['calendar_name'] as String? ?? '').trim(),
      colorHex: (json['color_hex'] as String? ?? '').trim(),
      downloaded: json['downloaded'] as int? ?? 0,
    );
  }
}

class OutlookTaskMirrorListSummary {
  const OutlookTaskMirrorListSummary({
    required this.localTaskListId,
    required this.taskListName,
    required this.remoteCalendarId,
    required this.remoteCalendarName,
    required this.created,
    required this.updated,
    required this.deleted,
    required this.conflicted,
  });

  final int localTaskListId;
  final String taskListName;
  final String remoteCalendarId;
  final String remoteCalendarName;
  final int created;
  final int updated;
  final int deleted;
  final int conflicted;

  int get changedCount => created + updated + deleted + conflicted;

  Map<String, dynamic> toJson() => {
        'local_task_list_id': localTaskListId,
        'task_list_name': taskListName,
        'remote_calendar_id': remoteCalendarId,
        'remote_calendar_name': remoteCalendarName,
        'created': created,
        'updated': updated,
        'deleted': deleted,
        'conflicted': conflicted,
      };

  factory OutlookTaskMirrorListSummary.fromJson(Map<String, dynamic> json) {
    return OutlookTaskMirrorListSummary(
      localTaskListId: json['local_task_list_id'] as int? ?? 0,
      taskListName: (json['task_list_name'] as String? ?? '').trim(),
      remoteCalendarId: (json['remote_calendar_id'] as String? ?? '').trim(),
      remoteCalendarName:
          (json['remote_calendar_name'] as String? ?? '').trim(),
      created: json['created'] as int? ?? 0,
      updated: json['updated'] as int? ?? 0,
      deleted: json['deleted'] as int? ?? 0,
      conflicted: json['conflicted'] as int? ?? 0,
    );
  }
}

class OutlookSyncReport {
  const OutlookSyncReport({
    required this.attemptedAt,
    required this.mode,
    required this.success,
    required this.calendarBooks,
    required this.downloaded,
    required this.mirroredCreated,
    required this.mirroredUpdated,
    required this.mirroredDeleted,
    required this.mirroredConflicted,
    this.calendarDetails = const <OutlookSyncedCalendarSummary>[],
    this.taskMirrorDetails = const <OutlookTaskMirrorListSummary>[],
    this.errorMessage,
  });

  final DateTime attemptedAt;
  final OutlookSyncMode mode;
  final bool success;
  final int calendarBooks;
  final int downloaded;
  final int mirroredCreated;
  final int mirroredUpdated;
  final int mirroredDeleted;
  final int mirroredConflicted;
  final List<OutlookSyncedCalendarSummary> calendarDetails;
  final List<OutlookTaskMirrorListSummary> taskMirrorDetails;
  final String? errorMessage;

  int get mirroredChanges =>
      mirroredCreated + mirroredUpdated + mirroredDeleted + mirroredConflicted;
}

class SyncEngine {
  final EventRepository _eventRepo;
  final CalendarBooksRepository _calendarBooksRepo;
  final TaskRepository _taskRepo;
  final OutlookSyncBindingsRepository _taskListBindingsRepo;
  final OutlookTaskMirrorRepository _taskMirrorRepo;
  final OutlookConfig _config;
  late MsGraphService _graphService;

  static const _deltaLinkKeyPrefix = 'outlook_sync_delta_link.';
  static const _lastSyncKey = 'outlook_last_sync';
  static const _lastSyncReportTimeKey = 'outlook_last_sync_report_time';
  static const _lastSyncReportStatusKey = 'outlook_last_sync_report_status';
  static const _lastSyncReportModeKey = 'outlook_last_sync_report_mode';
  static const _lastSyncReportCalendarBooksKey =
      'outlook_last_sync_report_calendar_books';
  static const _lastSyncReportDownloadedKey =
      'outlook_last_sync_report_downloaded';
  static const _lastSyncReportMirroredCreatedKey =
      'outlook_last_sync_report_mirrored_created';
  static const _lastSyncReportMirroredUpdatedKey =
      'outlook_last_sync_report_mirrored_updated';
  static const _lastSyncReportMirroredDeletedKey =
      'outlook_last_sync_report_mirrored_deleted';
  static const _lastSyncReportMirroredConflictedKey =
      'outlook_last_sync_report_mirrored_conflicted';
  static const _lastSyncReportCalendarDetailsKey =
      'outlook_last_sync_report_calendar_details';
  static const _lastSyncReportTaskMirrorDetailsKey =
      'outlook_last_sync_report_task_mirror_details';
  static const _lastSyncReportErrorKey = 'outlook_last_sync_report_error';

  SyncEngine(
    this._eventRepo,
    this._calendarBooksRepo,
    this._taskRepo,
    this._taskListBindingsRepo,
    this._taskMirrorRepo,
    this._config,
  );

  Future<
      ({
        int calendarBooks,
        int downloaded,
        int mirroredCreated,
        int mirroredUpdated,
        int mirroredDeleted,
        int mirroredConflicted,
      })> sync() async {
    final syncMode = await OutlookAuthService.loadSyncMode();
    if (!syncMode.allowsPull) {
      return (
        calendarBooks: 0,
        downloaded: 0,
        mirroredCreated: 0,
        mirroredUpdated: 0,
        mirroredDeleted: 0,
        mirroredConflicted: 0,
      );
    }
    _graphService = MsGraphService(_config, syncMode: syncMode);

    try {
      final calendars = await _syncCalendars();
      var downloaded = 0;
      final calendarDetails = <OutlookSyncedCalendarSummary>[];

      for (final entry in calendars.entries) {
        final downloadedForCalendar = await _pullCalendarEvents(
          remoteCalendarId: entry.key,
          localCalendarId: entry.value.localCalendarId,
          calendarColorHex: entry.value.colorHex,
        );
        downloaded += downloadedForCalendar;
        calendarDetails.add(
          OutlookSyncedCalendarSummary(
            remoteCalendarId: entry.key,
            localCalendarId: entry.value.localCalendarId,
            calendarName: entry.value.name,
            colorHex: entry.value.colorHex,
            downloaded: downloadedForCalendar,
          ),
        );
      }

      var mirroredCreated = 0;
      var mirroredUpdated = 0;
      var mirroredDeleted = 0;
      var mirroredConflicted = 0;
      var taskMirrorDetails = const <OutlookTaskMirrorListSummary>[];

      if (syncMode.allowsPush) {
        final mirrorResult = await OutlookTaskMirrorSyncService(
          graphService: _graphService,
          taskRepository: _taskRepo,
          calendarBooksRepository: _calendarBooksRepo,
          taskListBindingsRepository: _taskListBindingsRepo,
          taskMirrorRepository: _taskMirrorRepo,
        ).syncBoundTaskMirrors();
        mirroredCreated = mirrorResult.created;
        mirroredUpdated = mirrorResult.updated;
        mirroredDeleted = mirrorResult.deleted;
        mirroredConflicted = mirrorResult.conflicted;
        taskMirrorDetails = mirrorResult.taskListDetails
            .map(
              (detail) => OutlookTaskMirrorListSummary(
                localTaskListId: detail.localTaskListId,
                taskListName: detail.taskListName,
                remoteCalendarId: detail.remoteCalendarId,
                remoteCalendarName: detail.remoteCalendarName,
                created: detail.created,
                updated: detail.updated,
                deleted: detail.deleted,
                conflicted: detail.conflicted,
              ),
            )
            .toList(growable: false);
      }

      final completedAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncKey, completedAt.toIso8601String());
      await _saveLastSyncReport(
        OutlookSyncReport(
          attemptedAt: completedAt,
          mode: syncMode,
          success: true,
          calendarBooks: calendars.length,
          downloaded: downloaded,
          mirroredCreated: mirroredCreated,
          mirroredUpdated: mirroredUpdated,
          mirroredDeleted: mirroredDeleted,
          mirroredConflicted: mirroredConflicted,
          calendarDetails: calendarDetails,
          taskMirrorDetails: taskMirrorDetails,
        ),
        prefsInstance: prefs,
      );

      return (
        calendarBooks: calendars.length,
        downloaded: downloaded,
        mirroredCreated: mirroredCreated,
        mirroredUpdated: mirroredUpdated,
        mirroredDeleted: mirroredDeleted,
        mirroredConflicted: mirroredConflicted,
      );
    } catch (error) {
      await recordSyncFailure(mode: syncMode, error: error);
      rethrow;
    }
  }

  Future<Map<String, ({int localCalendarId, String colorHex, String name})>>
      _syncCalendars() async {
    final calendars = await _graphService.getCalendars();
    await _removeStaleCalendars(calendars);
    final mapping =
        <String, ({int localCalendarId, String colorHex, String name})>{};

    for (final calendar in calendars) {
      final remoteCalendarId = MsGraphService.calendarIdOf(calendar);
      if (remoteCalendarId.isEmpty) {
        continue;
      }

      final calendarName = MsGraphService.calendarNameOf(calendar);
      if (OutlookSyncPolicy.isTaskMirrorCalendarName(calendarName)) {
        continue;
      }

      final colorHex = MsGraphService.calendarColorHexOf(calendar);
      final localCalendarId = await _calendarBooksRepo.upsertSyncedEventCalendar(
        source: 'outlook',
        remoteId: remoteCalendarId,
        name: calendarName,
        colorHex: colorHex,
        description: OutlookSyncPolicy.localCalendarDescription(calendarName),
      );

      mapping[remoteCalendarId] = (
        localCalendarId: localCalendarId,
        colorHex: colorHex,
        name: calendarName,
      );
    }

    return mapping;
  }

  Future<void> _removeStaleCalendars(
    List<Map<String, dynamic>> remoteCalendars,
  ) async {
    if (remoteCalendars.isEmpty) {
      return;
    }

    final remoteIds = remoteCalendars
        .map(MsGraphService.calendarIdOf)
        .where((id) => id.isNotEmpty)
        .toSet();
    final localCalendars =
        await _calendarBooksRepo.getEventCalendarsBySource('outlook');
    if (localCalendars.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    for (final calendar in localCalendars) {
      final remoteId = calendar.syncUrl?.trim();
      if (remoteId == null || remoteId.isEmpty || remoteIds.contains(remoteId)) {
        continue;
      }

      await _eventRepo.deleteBySourceAndCalendarId(
        source: 'outlook',
        calendarId: calendar.id,
      );
      await _calendarBooksRepo.deleteEventCalendar(calendar.id);
      await prefs.remove('$_deltaLinkKeyPrefix$remoteId');
    }
  }

  Future<int> _pullCalendarEvents({
    required String remoteCalendarId,
    required int localCalendarId,
    required String calendarColorHex,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final deltaKey = '$_deltaLinkKeyPrefix$remoteCalendarId';
    final deltaLink = prefs.getString(deltaKey);

    final result = await _graphService.getEvents(
      calendarId: remoteCalendarId,
      deltaLink: deltaLink,
    );

    if (result.deltaLink != null) {
      await prefs.setString(deltaKey, result.deltaLink!);
    }

    var count = 0;
    for (final graphEvent in result.events) {
      final remoteEventId = graphEvent['id'] as String?;
      if (remoteEventId == null || remoteEventId.isEmpty) {
        continue;
      }

      final uid = 'outlook_$remoteEventId';

      if (MsGraphService.isDeletedEvent(graphEvent)) {
        await _eventRepo.deleteByUid(uid);
        count++;
        continue;
      }

      final parsed = MsGraphService.fromGraphEvent(graphEvent);
      await _eventRepo.upsertSyncedEvent(
        uid: uid,
        dtstamp: DateTime.now(),
        summary: parsed.subject,
        description: parsed.body,
        location: parsed.location,
        dtstart: parsed.start,
        dtend: parsed.end,
        status: parsed.status,
        source: 'outlook',
        eventCalendarId: localCalendarId,
        colorHex: calendarColorHex,
      );
      count++;
    }

    return count;
  }

  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSyncKey);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  static Future<OutlookSyncReport?> getLastSyncReport() async {
    final prefs = await SharedPreferences.getInstance();
    final rawTime = prefs.getString(_lastSyncReportTimeKey);
    final rawStatus = prefs.getString(_lastSyncReportStatusKey);
    if (rawTime == null || rawStatus == null) {
      return null;
    }

    final attemptedAt = DateTime.tryParse(rawTime);
    if (attemptedAt == null) {
      return null;
    }

    return OutlookSyncReport(
      attemptedAt: attemptedAt,
      mode: _syncModeFromKey(prefs.getString(_lastSyncReportModeKey)),
      success: rawStatus == 'success',
      calendarBooks: prefs.getInt(_lastSyncReportCalendarBooksKey) ?? 0,
      downloaded: prefs.getInt(_lastSyncReportDownloadedKey) ?? 0,
      mirroredCreated: prefs.getInt(_lastSyncReportMirroredCreatedKey) ?? 0,
      mirroredUpdated: prefs.getInt(_lastSyncReportMirroredUpdatedKey) ?? 0,
      mirroredDeleted: prefs.getInt(_lastSyncReportMirroredDeletedKey) ?? 0,
      mirroredConflicted:
          prefs.getInt(_lastSyncReportMirroredConflictedKey) ?? 0,
      calendarDetails: _decodeCalendarDetails(
        prefs.getString(_lastSyncReportCalendarDetailsKey),
      ),
      taskMirrorDetails: _decodeTaskMirrorDetails(
        prefs.getString(_lastSyncReportTaskMirrorDetailsKey),
      ),
      errorMessage: prefs.getString(_lastSyncReportErrorKey),
    );
  }

  static Future<void> recordSyncFailure({
    required OutlookSyncMode mode,
    required Object error,
  }) async {
    await _saveLastSyncReport(
      OutlookSyncReport(
        attemptedAt: DateTime.now(),
        mode: mode,
        success: false,
        calendarBooks: 0,
        downloaded: 0,
        mirroredCreated: 0,
        mirroredUpdated: 0,
        mirroredDeleted: 0,
        mirroredConflicted: 0,
        calendarDetails: const <OutlookSyncedCalendarSummary>[],
        taskMirrorDetails: const <OutlookTaskMirrorListSummary>[],
        errorMessage: error.toString(),
      ),
    );
  }

  static Future<void> resetSync() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    for (final key in keys) {
      if (key.startsWith(_deltaLinkKeyPrefix)) {
        await prefs.remove(key);
      }
    }

    await prefs.remove(_lastSyncKey);
    await _clearLastSyncReport(prefs);
  }

  static Future<void> _saveLastSyncReport(
    OutlookSyncReport report, {
    SharedPreferences? prefsInstance,
  }) async {
    final prefs = prefsInstance ?? await SharedPreferences.getInstance();
    await prefs.setString(
      _lastSyncReportTimeKey,
      report.attemptedAt.toIso8601String(),
    );
    await prefs.setString(
      _lastSyncReportStatusKey,
      report.success ? 'success' : 'failure',
    );
    await prefs.setString(_lastSyncReportModeKey, report.mode.name);
    await prefs.setInt(_lastSyncReportCalendarBooksKey, report.calendarBooks);
    await prefs.setInt(_lastSyncReportDownloadedKey, report.downloaded);
    await prefs.setInt(
      _lastSyncReportMirroredCreatedKey,
      report.mirroredCreated,
    );
    await prefs.setInt(
      _lastSyncReportMirroredUpdatedKey,
      report.mirroredUpdated,
    );
    await prefs.setInt(
      _lastSyncReportMirroredDeletedKey,
      report.mirroredDeleted,
    );
    await prefs.setInt(
      _lastSyncReportMirroredConflictedKey,
      report.mirroredConflicted,
    );
    await prefs.setString(
      _lastSyncReportCalendarDetailsKey,
      jsonEncode(
        report.calendarDetails
            .map((detail) => detail.toJson())
            .toList(growable: false),
      ),
    );
    await prefs.setString(
      _lastSyncReportTaskMirrorDetailsKey,
      jsonEncode(
        report.taskMirrorDetails
            .map((detail) => detail.toJson())
            .toList(growable: false),
      ),
    );
    if (report.errorMessage == null || report.errorMessage!.trim().isEmpty) {
      await prefs.remove(_lastSyncReportErrorKey);
    } else {
      await prefs.setString(_lastSyncReportErrorKey, report.errorMessage!);
    }
  }

  static Future<void> _clearLastSyncReport(SharedPreferences prefs) async {
    await prefs.remove(_lastSyncReportTimeKey);
    await prefs.remove(_lastSyncReportStatusKey);
    await prefs.remove(_lastSyncReportModeKey);
    await prefs.remove(_lastSyncReportCalendarBooksKey);
    await prefs.remove(_lastSyncReportDownloadedKey);
    await prefs.remove(_lastSyncReportMirroredCreatedKey);
    await prefs.remove(_lastSyncReportMirroredUpdatedKey);
    await prefs.remove(_lastSyncReportMirroredDeletedKey);
    await prefs.remove(_lastSyncReportMirroredConflictedKey);
    await prefs.remove(_lastSyncReportCalendarDetailsKey);
    await prefs.remove(_lastSyncReportTaskMirrorDetailsKey);
    await prefs.remove(_lastSyncReportErrorKey);
  }

  static List<OutlookSyncedCalendarSummary> _decodeCalendarDetails(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <OutlookSyncedCalendarSummary>[];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) => OutlookSyncedCalendarSummary.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (detail) =>
                detail.remoteCalendarId.isNotEmpty &&
                detail.localCalendarId > 0 &&
                detail.calendarName.isNotEmpty,
          )
          .toList(growable: false);
    } catch (_) {
      return const <OutlookSyncedCalendarSummary>[];
    }
  }

  static List<OutlookTaskMirrorListSummary> _decodeTaskMirrorDetails(
    String? raw,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return const <OutlookTaskMirrorListSummary>[];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) => OutlookTaskMirrorListSummary.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (detail) =>
                detail.localTaskListId > 0 &&
                detail.taskListName.isNotEmpty &&
                detail.remoteCalendarName.isNotEmpty,
          )
          .toList(growable: false);
    } catch (_) {
      return const <OutlookTaskMirrorListSummary>[];
    }
  }

  static OutlookSyncMode _syncModeFromKey(String? rawMode) {
    for (final mode in OutlookSyncMode.values) {
      if (mode.name == rawMode) {
        return mode;
      }
    }
    return OutlookSyncMode.readOnly;
  }
}
