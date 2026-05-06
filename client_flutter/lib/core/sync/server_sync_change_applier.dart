import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'sync_object_registry.dart';
import 'sync_object_state_store.dart';

class ServerSyncChange {
  const ServerSyncChange({
    required this.changeId,
    required this.objectType,
    required this.serverId,
    required this.action,
    required this.serverVersion,
    required this.payload,
    this.uid,
  });

  final String changeId;
  final String objectType;
  final String serverId;
  final String action;
  final int serverVersion;
  final Map<String, dynamic> payload;
  final String? uid;

  factory ServerSyncChange.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    return ServerSyncChange(
      changeId: (json['changeId'] as String?) ?? '',
      objectType: (json['objectType'] as String?) ?? '',
      serverId: (json['serverId'] as String?) ?? '',
      uid: json['uid'] as String?,
      action: (json['action'] as String?) ?? 'upsert',
      serverVersion: json['serverVersion'] as int? ?? 1,
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
    );
  }
}

class ServerSyncApplyResult {
  const ServerSyncApplyResult({
    required this.received,
    required this.applied,
    required this.skipped,
    required this.failed,
    required this.perType,
    required this.appliedChangeIds,
    required this.errors,
    this.orphanCalendarEvents = 0,
  });

  final int received;
  final int applied;
  final int skipped;
  final int failed;
  final Map<String, int> perType;
  final List<String> appliedChangeIds;
  final List<String> errors;
  final int orphanCalendarEvents;

  bool get hasFailures => failed > 0;

  Map<String, Object?> toSummary() {
    return <String, Object?>{
      'received': received,
      'applied': applied,
      'skipped': skipped,
      'failed': failed,
      'perType': perType,
      'orphanCalendarEvents': orphanCalendarEvents,
      if (errors.isNotEmpty) 'errors': errors.take(5).toList(growable: false),
    };
  }
}

class ServerSyncChangeApplier {
  ServerSyncChangeApplier(
    this._database,
    this._stateStore, {
    SyncObjectRegistry registry = const SyncObjectRegistry(
      SyncObjectType.p1Objects,
    ),
  }) : _registry = registry;

  final AppDatabase _database;
  final SyncObjectStateStore _stateStore;
  final SyncObjectRegistry _registry;

  Future<ServerSyncApplyResult> applyPullResponse(
    Map<String, dynamic> response,
  ) async {
    final rawChanges = response['changes'];
    if (rawChanges is! List) {
      return const ServerSyncApplyResult(
        received: 0,
        applied: 0,
        skipped: 0,
        failed: 0,
        perType: <String, int>{},
        appliedChangeIds: <String>[],
        errors: <String>[],
      );
    }

    final applied = <String>[];
    final errors = <String>[];
    final changes = <ServerSyncChange>[];
    final perType = <String, int>{};
    var skipped = 0;
    var failed = 0;
    for (final raw in rawChanges) {
      if (raw is! Map) {
        skipped++;
        continue;
      }
      final change = ServerSyncChange.fromJson(Map<String, dynamic>.from(raw));
      perType.update(change.objectType, (value) => value + 1, ifAbsent: () => 1);
      if (change.changeId.isEmpty ||
          change.objectType.isEmpty ||
          change.serverId.isEmpty) {
        skipped++;
        continue;
      }
      if (!_registry.contains(change.objectType)) {
        skipped++;
        continue;
      }
      changes.add(change);
    }
    changes.sort((left, right) {
      final priority = _changePriority(left).compareTo(_changePriority(right));
      if (priority != 0) {
        return priority;
      }
      return left.changeId.compareTo(right.changeId);
    });

    for (final change in changes) {
      try {
        await applyChange(change);
        applied.add(change.changeId);
      } catch (error) {
        failed++;
        errors.add('${change.objectType}:${change.changeId}: $error');
      }
    }
    await _refreshPlaceholderCalendarNames(changes);
    final repairedOrphans = await repairOutlookOrphanEvents();
    return ServerSyncApplyResult(
      received: rawChanges.length,
      applied: applied.length,
      skipped: skipped,
      failed: failed,
      perType: perType,
      appliedChangeIds: applied,
      errors: errors,
      orphanCalendarEvents: repairedOrphans,
    );
  }

  int _changePriority(ServerSyncChange change) {
    switch (change.objectType) {
      case 'calendar_book':
        return 0;
      case 'calendar_event':
        return 1;
      default:
        return 2;
    }
  }

  Future<void> applyChange(ServerSyncChange change) async {
    final state = await _stateStore.getStateByServerId(
      objectType: change.objectType,
      serverId: change.serverId,
    );

    if (change.action == 'delete') {
      if (state != null) {
        await _deleteLocal(change.objectType, state.localId);
        await _stateStore.removeState(
          objectType: change.objectType,
          localId: state.localId,
        );
      }
      return;
    }

    final localId = await _upsertLocal(change, state?.localId);
    if (localId == null || localId.isEmpty) {
      return;
    }

    await _stateStore.markSynced(
      objectType: change.objectType,
      localId: localId,
      serverId: change.serverId,
      serverVersion: change.serverVersion,
      uid: change.uid ?? _string(change.payload, 'uid'),
    );
  }

  Future<String?> _upsertLocal(
    ServerSyncChange change,
    String? currentLocalId,
  ) {
    switch (change.objectType) {
      case 'calendar_book':
        return _upsertCalendarBook(change, currentLocalId);
      case 'task_list':
        return _upsertTaskList(change, currentLocalId);
      case 'calendar_event':
        return _upsertCalendarEvent(change, currentLocalId);
      case 'task_item':
        return _upsertTaskItem(change, currentLocalId);
      case 'task_schedule_segment':
        return _upsertTaskScheduleSegment(change, currentLocalId);
      case 'actual_activity_log':
        return _upsertActualActivityLog(change, currentLocalId);
      case 'activity_segment':
        return _upsertActivitySegment(change, currentLocalId);
      case 'activity_interpretation':
        return _upsertActivityInterpretation(change, currentLocalId);
      case 'task_work_log':
        return _upsertTaskWorkLog(change, currentLocalId);
      case 'report_document':
        return _upsertReportDocument(change, currentLocalId);
      case 'diary_entry':
        return _upsertDiaryEntry(change, currentLocalId);
      case 'report_push_delivery':
        return _upsertReportPushDelivery(change, currentLocalId);
      case 'file_folder':
        return _upsertFileFolder(change, currentLocalId);
      case 'file_item':
        return _upsertFileItem(change, currentLocalId);
      case 'file_context_link':
        return _upsertFileContextLink(change, currentLocalId);
      case 'file_folder_usage':
        return _upsertFileFolderUsage(change, currentLocalId);
      case 'file_version_record':
        return _upsertFileVersionRecord(change, currentLocalId);
      case 'audit_log':
        return _upsertAuditLog(change, currentLocalId);
      case 'user_setting':
        return _upsertUserSetting(change);
      default:
        return Future<String?>.value(null);
    }
  }

  Future<void> _deleteLocal(String objectType, String localId) async {
    final id = int.tryParse(localId);
    switch (objectType) {
      case 'calendar_book':
        if (id != null) {
          await _database.customStatement(
            "DELETE FROM sync_object_states WHERE object_type = 'calendar_event' AND local_id IN (SELECT CAST(id AS TEXT) FROM calendar_events WHERE event_calendar_id = ?)",
            [id],
          );
          await _database.customStatement(
            'DELETE FROM calendar_events WHERE event_calendar_id = ?',
            [id],
          );
          await (_database.delete(_database.eventCalendars)
                ..where((row) => row.id.equals(id)))
              .go();
        }
        break;
      case 'task_list':
        if (id != null) {
          await (_database.delete(_database.taskLists)
                ..where((row) => row.id.equals(id)))
              .go();
        }
        break;
      case 'calendar_event':
        if (id != null) {
          await (_database.delete(_database.calendarEvents)
                ..where((row) => row.id.equals(id)))
              .go();
        }
        break;
      case 'task_item':
        if (id != null) {
          await (_database.delete(_database.taskItems)
                ..where((row) => row.id.equals(id)))
              .go();
        }
        break;
      case 'task_schedule_segment':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM task_schedule_segments WHERE id = ?',
            [id],
          );
        }
        break;
      case 'actual_activity_log':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM actual_activity_logs WHERE id = ?',
            [id],
          );
        }
        break;
      case 'activity_segment':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM activity_segments WHERE id = ?',
            [id],
          );
        }
        break;
      case 'activity_interpretation':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM activity_interpretations WHERE id = ?',
            [id],
          );
        }
        break;
      case 'task_work_log':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM task_work_logs WHERE id = ?',
            [id],
          );
        }
        break;
      case 'report_document':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM report_documents WHERE id = ?',
            [id],
          );
        }
        break;
      case 'diary_entry':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM diary_entries WHERE id = ?',
            [id],
          );
        }
        break;
      case 'report_push_delivery':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM report_push_deliveries WHERE id = ?',
            [id],
          );
        }
        break;
      case 'file_folder':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM file_folders WHERE id = ?',
            [id],
          );
        }
        break;
      case 'file_item':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM file_items WHERE id = ?',
            [id],
          );
        }
        break;
      case 'file_context_link':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM file_context_links WHERE id = ?',
            [id],
          );
        }
        break;
      case 'file_folder_usage':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM file_folder_usages WHERE id = ?',
            [id],
          );
        }
        break;
      case 'file_version_record':
        if (id != null) {
          await _database.customStatement(
            'DELETE FROM file_version_records WHERE id = ?',
            [id],
          );
        }
        break;
      case 'user_setting':
        await _database.deleteSetting(localId);
        break;
    }
  }

  Future<String> _upsertCalendarBook(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    var id = int.tryParse(currentLocalId ?? '');
    final remoteCalendarId = _calendarRemoteId(payload);
    if (id == null && remoteCalendarId != null) {
      id = await _findCalendarIdByRemoteId(remoteCalendarId);
    }
    final companion = EventCalendarsCompanion(
      id: id == null ? const Value.absent() : Value(id),
      name: Value(_string(payload, 'name') ?? '未命名日历本'),
      colorHex: Value(_string(payload, 'colorHex', 'color_hex') ?? '#6B5EE4'),
      description: Value(_string(payload, 'description')),
      isVisible: Value(_bool(payload, 'isVisible', 'is_visible') ?? true),
      isDefault: Value(_bool(payload, 'isDefault', 'is_default') ?? false),
      source: Value(_string(payload, 'source') ?? 'server'),
      syncUrl: Value(_string(payload, 'syncUrl', 'sync_url') ?? remoteCalendarId),
      createdAt: Value(_date(payload, 'createdAt', 'created_at') ?? DateTime.now()),
    );
    if (id == null) {
      final created = await _database.into(_database.eventCalendars).insert(companion);
      return created.toString();
    }
    await _database.update(_database.eventCalendars).replace(companion);
    return id.toString();
  }

  Future<String> _upsertTaskList(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final companion = TaskListsCompanion(
      id: id == null ? const Value.absent() : Value(id),
      name: Value(_string(payload, 'name') ?? '未命名任务本'),
      colorHex: Value(_string(payload, 'colorHex', 'color_hex') ?? '#0EA8A0'),
      emoji: Value(_string(payload, 'emoji')),
      isVisible: Value(_bool(payload, 'isVisible', 'is_visible') ?? true),
      isDefault: Value(_bool(payload, 'isDefault', 'is_default') ?? false),
      isArchived: Value(_bool(payload, 'isArchived', 'is_archived') ?? false),
      createdAt: Value(_date(payload, 'createdAt', 'created_at') ?? DateTime.now()),
    );
    if (id == null) {
      final created = await _database.into(_database.taskLists).insert(companion);
      return created.toString();
    }
    await _database.update(_database.taskLists).replace(companion);
    return id.toString();
  }

  Future<String> _upsertCalendarEvent(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final uid = change.uid ?? _string(payload, 'uid') ?? change.serverId;
    final eventCalendarId = await _resolveEventCalendarId(payload, uid);
    final companion = CalendarEventsCompanion(
      id: id == null ? const Value.absent() : Value(id),
      uid: Value(uid),
      dtstamp: Value(_date(payload, 'dtstamp') ?? DateTime.now()),
      summary: Value(
        _string(payload, 'summary', 'title', 'subject') ??
            _string(payload, 'bodyPreview', 'name') ??
            '未命名日程',
      ),
      description:
          Value(_string(payload, 'description', 'bodyPreview', 'notes') ?? _string(payload, 'note')),
      location: Value(_locationString(payload)),
      dtstart: Value(_date(payload, 'dtstart', 'startAt', 'start_at', 'startTime') ?? DateTime.now()),
      dtend: Value(_date(payload, 'dtend', 'endAt', 'end_at', 'endTime')),
      rrule: Value(_string(payload, 'rrule')),
      status: Value(_string(payload, 'status') ?? 'CONFIRMED'),
      transp: Value(_string(payload, 'transp') ?? 'OPAQUE'),
      source: Value(_string(payload, 'source') ?? 'server'),
      eventCalendarId: Value(eventCalendarId),
      colorHex: Value(_string(payload, 'colorHex', 'color_hex') ?? '#6B5EE4'),
      isBlock: Value(_bool(payload, 'isBlock', 'is_block') ?? false),
    );
    if (id == null) {
      final created = await _database.into(_database.calendarEvents).insert(companion);
      return created.toString();
    }
    await _database.update(_database.calendarEvents).replace(companion);
    return id.toString();
  }

  Future<int?> _findCalendarIdByRemoteId(String? remoteCalendarId) async {
    if (remoteCalendarId == null || remoteCalendarId.trim().isEmpty) {
      return null;
    }
    final query = _database.select(_database.eventCalendars)
      ..where(
        (table) =>
            table.source.equals('outlook') &
            table.syncUrl.equals(remoteCalendarId),
      )
      ..limit(1);
    final calendar = await query.getSingleOrNull();
    return calendar?.id;
  }

  Future<int> _resolveEventCalendarId(
    Map<String, dynamic> payload,
    String uid,
  ) async {
    final direct = _int(payload, 'eventCalendarId', 'event_calendar_id');
    if (direct != null) {
      return direct;
    }
    final remoteCalendarId =
        _calendarRemoteId(payload) ?? _calendarIdFromOutlookEventUid(uid);
    if (remoteCalendarId == null || remoteCalendarId.trim().isEmpty) {
      return _ensureDefaultCalendarId();
    }
    final existing = await _findCalendarIdByRemoteId(remoteCalendarId);
    if (existing != null) {
      return existing;
    }
    return _createOutlookPlaceholderCalendar(
      remoteCalendarId,
      colorHex: _string(payload, 'colorHex', 'color_hex'),
      calendarName: _string(payload, 'calendarName', 'calendar_name'),
    );
  }

  Future<int> _ensureDefaultCalendarId() async {
    final defaultCalendar = await _database.select(_database.eventCalendars)
      ..where((t) => t.isDefault.equals(true))
      ..limit(1);
    final existing = await defaultCalendar.getSingleOrNull();
    if (existing != null) {
      return existing.id;
    }
    final anyCalendar = await _database.select(_database.eventCalendars)
      ..limit(1);
    final any = await anyCalendar.getSingleOrNull();
    if (any != null) {
      return any.id;
    }
    return _database.into(_database.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: '默认日历',
            colorHex: const Value('#6B5EE4'),
            isVisible: const Value(true),
            isDefault: const Value(true),
            source: const Value('local'),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<int> _createOutlookPlaceholderCalendar(
    String remoteCalendarId, {
    String? colorHex,
    String? calendarName,
  }) {
    return _database.into(_database.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: calendarName ?? 'Outlook',
            colorHex: Value(colorHex ?? '#2563eb'),
            description:
                const Value('Outlook calendar restored from server sync'),
            isVisible: const Value(true),
            isDefault: const Value(false),
            source: const Value('outlook'),
            syncUrl: Value(remoteCalendarId),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> _refreshPlaceholderCalendarNames(
    List<ServerSyncChange> appliedChanges,
  ) async {
    final bookChanges = appliedChanges
        .where((c) => c.objectType == 'calendar_book')
        .toList();
    if (bookChanges.isEmpty) return;

    for (final bookChange in bookChanges) {
      final payload = bookChange.payload;
      final remoteCalendarId = _calendarRemoteId(payload);
      if (remoteCalendarId == null || remoteCalendarId.trim().isEmpty) {
        continue;
      }

      final existingId = await _findCalendarIdByRemoteId(remoteCalendarId);
      if (existingId == null) continue;

      final name = _string(payload, 'name') ?? 'Outlook';
      final colorHex = _string(payload, 'colorHex', 'color_hex') ?? '#2563eb';
      final description = _string(payload, 'description');
      final isVisible = _bool(payload, 'isVisible', 'is_visible') ?? true;
      final isDefault = _bool(payload, 'isDefault', 'is_default') ?? false;

      await _database.update(_database.eventCalendars)
        ..where((row) => row.id.equals(existingId))
        ..write(EventCalendarsCompanion(
          name: Value(name),
          colorHex: Value(colorHex),
          description: Value(description),
          isVisible: Value(isVisible),
          isDefault: Value(isDefault),
        ));
    }
  }

  Future<int> repairOutlookOrphanEvents() async {
    var repaired = 0;

    // 修复1：eventCalendarId 为 NULL 的 Outlook 事件
    final nullCalendarQuery = _database.select(_database.calendarEvents)
      ..where(
        (event) =>
            event.source.equals('outlook') & event.eventCalendarId.isNull(),
      );
    final nullCalendarEvents = await nullCalendarQuery.get();
    for (final event in nullCalendarEvents) {
      final remoteCalendarId = _calendarIdFromOutlookEventUid(event.uid);
      if (remoteCalendarId == null || remoteCalendarId.trim().isEmpty) {
        continue;
      }
      final calendarId = await _findCalendarIdByRemoteId(remoteCalendarId) ??
          await _createOutlookPlaceholderCalendar(
            remoteCalendarId,
            colorHex: event.colorHex,
          );
      await (_database.update(_database.calendarEvents)
            ..where((row) => row.id.equals(event.id)))
          .write(CalendarEventsCompanion(eventCalendarId: Value(calendarId)));
      repaired++;
    }

    // 修复2：eventCalendarId 指向不存在的日历本的 Outlook 事件（悬挂引用）
    final orphanEvents = await _database.customSelect('''
      SELECT ce.id, ce.uid, ce.color_hex
      FROM calendar_events ce
      LEFT JOIN event_calendars ec ON ec.id = ce.event_calendar_id
      WHERE ce.source = 'outlook'
        AND ce.event_calendar_id IS NOT NULL
        AND ec.id IS NULL
    ''').get();

    for (final row in orphanEvents) {
      final eventId = row.read<int>('id');
      final uid = row.read<String>('uid');
      final colorHex = row.read<String>('color_hex');

      final remoteCalendarId = _calendarIdFromOutlookEventUid(uid);
      if (remoteCalendarId == null || remoteCalendarId.trim().isEmpty) {
        continue;
      }
      final calendarId = await _findCalendarIdByRemoteId(remoteCalendarId) ??
          await _createOutlookPlaceholderCalendar(
            remoteCalendarId,
            colorHex: colorHex,
          );
      await (_database.update(_database.calendarEvents)
            ..where((row) => row.id.equals(eventId)))
          .write(CalendarEventsCompanion(eventCalendarId: Value(calendarId)));
      repaired++;
    }

    return repaired;
  }

  String? _calendarRemoteId(Map<String, dynamic> payload) {
    return _string(
          payload,
          'eventCalendarRemoteId',
          'remoteCalendarId',
          'calendarId',
        ) ??
        _string(payload, 'calendar_id');
  }

  String? _calendarIdFromOutlookEventUid(String uid) {
    const prefix = 'outlook_event:';
    if (!uid.startsWith(prefix)) {
      return null;
    }
    final rest = uid.substring(prefix.length);
    final separator = rest.indexOf(':');
    if (separator <= 0) {
      return null;
    }
    return rest.substring(0, separator);
  }

  Future<String> _upsertTaskItem(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final companion = TaskItemsCompanion(
      id: id == null ? const Value.absent() : Value(id),
      uid: Value(change.uid ?? _string(payload, 'uid') ?? change.serverId),
      dtstamp: Value(_date(payload, 'dtstamp') ?? DateTime.now()),
      summary: Value(
        _string(payload, 'summary', 'title', 'name') ?? '未命名任务',
      ),
      description: Value(_string(payload, 'description', 'notes')),
      location: Value(_string(payload, 'location')),
      dtstart: Value(_date(payload, 'dtstart')),
      due: Value(_date(payload, 'due', 'dueAt', 'dueDate', 'due_date')),
      completed: Value(_date(payload, 'completed')),
      priority: Value(_int(payload, 'priority') ?? 0),
      status: Value(_string(payload, 'status') ?? 'NEEDS-ACTION'),
      percentComplete: Value(_int(payload, 'percentComplete', 'percent_complete') ?? 0),
      categories: Value(_string(payload, 'categories') ?? '[]'),
      rrule: Value(_string(payload, 'rrule')),
      durationMinutes: Value(_int(payload, 'durationMinutes', 'duration_minutes') ?? 60),
      isSplittable: Value(_bool(payload, 'isSplittable', 'is_splittable') ?? false),
      priorityLocal: Value(_int(payload, 'priorityLocal', 'priority_local') ?? 2),
      isAutoScheduled: Value(
        _bool(payload, 'isAutoScheduled', 'is_auto_scheduled') ?? true,
      ),
      taskListId: Value(_int(payload, 'taskListId', 'task_list_id')),
      tagId: Value(_string(payload, 'tagId', 'tag_id')),
      isLocked: Value(_bool(payload, 'isLocked', 'is_locked') ?? false),
      reminderMinutesBefore: Value(
        _int(payload, 'reminderMinutesBefore', 'reminder_minutes_before') ?? 15,
      ),
    );
    if (id == null) {
      final created = await _database.into(_database.taskItems).insert(companion);
      return created.toString();
    }
    await _database.update(_database.taskItems).replace(companion);
    return id.toString();
  }

  Future<String> _upsertTaskScheduleSegment(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO task_schedule_segments (
          task_id,
          segment_index,
          start_at,
          end_at,
          source,
          plan_run_id,
          note,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          _int(payload, 'taskId', 'task_id') ?? 0,
          _int(payload, 'segmentIndex', 'segment_index') ?? 0,
          (_date(payload, 'startAt', 'start_at') ?? DateTime.now()).toIso8601String(),
          (_date(payload, 'endAt', 'end_at') ?? DateTime.now()).toIso8601String(),
          _string(payload, 'source') ?? 'server',
          _string(payload, 'planRunId', 'plan_run_id'),
          _string(payload, 'note'),
          _string(payload, 'createdAt', 'created_at') ?? now,
          now,
        ],
      );
      final row = await _database.customSelect(
        'SELECT last_insert_rowid() AS id',
      ).getSingle();
      return row.read<int>('id').toString();
    }

    await _database.customStatement(
      '''
      UPDATE task_schedule_segments
      SET task_id = ?,
          segment_index = ?,
          start_at = ?,
          end_at = ?,
          source = ?,
          plan_run_id = ?,
          note = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        _int(payload, 'taskId', 'task_id') ?? 0,
        _int(payload, 'segmentIndex', 'segment_index') ?? 0,
        (_date(payload, 'startAt', 'start_at') ?? DateTime.now()).toIso8601String(),
        (_date(payload, 'endAt', 'end_at') ?? DateTime.now()).toIso8601String(),
        _string(payload, 'source') ?? 'server',
        _string(payload, 'planRunId', 'plan_run_id'),
        _string(payload, 'note'),
        now,
        id,
      ],
    );
    return id.toString();
  }

  Future<String> _upsertActualActivityLog(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final values = [
      change.uid ?? _string(payload, 'actualUid', 'actual_uid') ?? change.serverId,
      _string(payload, 'title') ?? '未命名实际记录',
      (_date(payload, 'startAt', 'start_at') ?? DateTime.now()).toIso8601String(),
      (_date(payload, 'endAt', 'end_at') ?? DateTime.now()).toIso8601String(),
      _string(payload, 'sourceType', 'source_type') ?? 'server',
      _string(payload, 'sourceId', 'source_id'),
      _string(payload, 'sourcePayloadJson', 'source_payload_json') ?? '{}',
      _double(payload, 'confidence') ?? 0.5,
      _string(payload, 'status') ?? 'candidate',
      _string(payload, 'note'),
      _string(payload, 'createdAt', 'created_at') ?? now,
      now,
      _date(payload, 'confirmedAt', 'confirmed_at')?.toIso8601String(),
      _date(payload, 'rejectedAt', 'rejected_at')?.toIso8601String(),
      _int(payload, 'mergedIntoId', 'merged_into_id'),
    ];

    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO actual_activity_logs (
          actual_uid,
          title,
          start_at,
          end_at,
          source_type,
          source_id,
          source_payload_json,
          confidence,
          status,
          note,
          created_at,
          updated_at,
          confirmed_at,
          rejected_at,
          merged_into_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }

    await _database.customStatement(
      '''
      UPDATE actual_activity_logs
      SET actual_uid = ?,
          title = ?,
          start_at = ?,
          end_at = ?,
          source_type = ?,
          source_id = ?,
          source_payload_json = ?,
          confidence = ?,
          status = ?,
          note = ?,
          created_at = ?,
          updated_at = ?,
          confirmed_at = ?,
          rejected_at = ?,
          merged_into_id = ?
      WHERE id = ?
      ''',
      [...values, id],
    );
    return id.toString();
  }

  Future<String> _upsertActivitySegment(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final values = [
      change.uid ?? _string(payload, 'segmentUid', 'segment_uid') ?? change.serverId,
      (_date(payload, 'startAt', 'start_at') ?? DateTime.now()).toIso8601String(),
      (_date(payload, 'endAt', 'end_at') ?? DateTime.now()).toIso8601String(),
      _string(payload, 'primaryProcessName', 'primary_process_name'),
      _string(payload, 'primaryWindowTitle', 'primary_window_title'),
      _string(payload, 'category'),
      _string(payload, 'label'),
      _string(payload, 'sourceRecordIdsJson', 'source_record_ids_json') ?? '[]',
      _string(payload, 'evidenceJson', 'evidence_json') ?? '{}',
      _double(payload, 'confidence') ?? 0.5,
      _string(payload, 'status') ?? 'candidate',
      _string(payload, 'createdAt', 'created_at') ?? now,
      now,
    ];

    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO activity_segments (
          segment_uid,
          start_at,
          end_at,
          primary_process_name,
          primary_window_title,
          category,
          label,
          source_record_ids_json,
          evidence_json,
          confidence,
          status,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }

    await _database.customStatement(
      '''
      UPDATE activity_segments
      SET segment_uid = ?,
          start_at = ?,
          end_at = ?,
          primary_process_name = ?,
          primary_window_title = ?,
          category = ?,
          label = ?,
          source_record_ids_json = ?,
          evidence_json = ?,
          confidence = ?,
          status = ?,
          created_at = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [...values, id],
    );
    return id.toString();
  }

  Future<String> _upsertActivityInterpretation(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final values = [
      change.uid ??
          _string(payload, 'interpretationUid', 'interpretation_uid') ??
          change.serverId,
      _int(payload, 'segmentId', 'segment_id') ?? 0,
      _string(payload, 'summary') ?? '远端活动解释',
      _string(payload, 'inferredProject', 'inferred_project'),
      _string(payload, 'inferredDocument', 'inferred_document'),
      _int(payload, 'inferredTaskId', 'inferred_task_id'),
      _double(payload, 'confidence') ?? 0.5,
      _string(payload, 'evidenceJson', 'evidence_json') ?? '{}',
      _string(payload, 'status') ?? 'candidate',
      _string(payload, 'createdAt', 'created_at') ?? now,
      now,
    ];

    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO activity_interpretations (
          interpretation_uid,
          segment_id,
          summary,
          inferred_project,
          inferred_document,
          inferred_task_id,
          confidence,
          evidence_json,
          status,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }

    await _database.customStatement(
      '''
      UPDATE activity_interpretations
      SET interpretation_uid = ?,
          segment_id = ?,
          summary = ?,
          inferred_project = ?,
          inferred_document = ?,
          inferred_task_id = ?,
          confidence = ?,
          evidence_json = ?,
          status = ?,
          created_at = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [...values, id],
    );
    return id.toString();
  }

  Future<String> _upsertTaskWorkLog(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final startAt = _date(payload, 'startAt', 'start_at') ?? DateTime.now();
    final endAt = _date(payload, 'endAt', 'end_at') ?? startAt;
    final values = [
      change.uid ?? _string(payload, 'workUid', 'work_uid') ?? change.serverId,
      _int(payload, 'taskId', 'task_id') ?? 0,
      _int(payload, 'segmentId', 'segment_id'),
      _int(payload, 'actualId', 'actual_id'),
      startAt.toIso8601String(),
      endAt.toIso8601String(),
      _int(payload, 'durationMinutes', 'duration_minutes') ??
          endAt.difference(startAt).inMinutes,
      _double(payload, 'confidence') ?? 0.5,
      _string(payload, 'sourceType', 'source_type') ?? 'server',
      _string(payload, 'evidenceJson', 'evidence_json') ?? '{}',
      _string(payload, 'status') ?? 'candidate',
      _string(payload, 'createdAt', 'created_at') ?? now,
      now,
    ];

    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO task_work_logs (
          work_uid,
          task_id,
          segment_id,
          actual_id,
          start_at,
          end_at,
          duration_minutes,
          confidence,
          source_type,
          evidence_json,
          status,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }

    await _database.customStatement(
      '''
      UPDATE task_work_logs
      SET work_uid = ?,
          task_id = ?,
          segment_id = ?,
          actual_id = ?,
          start_at = ?,
          end_at = ?,
          duration_minutes = ?,
          confidence = ?,
          source_type = ?,
          evidence_json = ?,
          status = ?,
          created_at = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [...values, id],
    );
    return id.toString();
  }

  Future<String> _upsertReportDocument(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final reportUid =
        change.uid ?? _string(payload, 'reportUid', 'report_uid') ?? change.serverId;
    final values = [
      reportUid,
      _string(payload, 'reportType', 'report_type') ?? 'daily',
      (_date(payload, 'periodStart', 'period_start') ?? DateTime.now()).toIso8601String(),
      (_date(payload, 'periodEnd', 'period_end') ?? DateTime.now()).toIso8601String(),
      _string(payload, 'title') ?? '远端报告',
      _string(payload, 'summaryMarkdown', 'summary_markdown') ?? '',
      _string(payload, 'metricsJson', 'metrics_json') ?? '{}',
      _string(payload, 'sourceSnapshotJson', 'source_snapshot_json') ?? '{}',
      _string(payload, 'status') ?? 'draft',
      _string(payload, 'createdAt', 'created_at') ?? now,
      now,
      _date(payload, 'confirmedAt', 'confirmed_at')?.toIso8601String(),
    ];
    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO report_documents (
          report_uid,
          report_type,
          period_start,
          period_end,
          title,
          summary_markdown,
          metrics_json,
          source_snapshot_json,
          status,
          created_at,
          updated_at,
          confirmed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(report_uid) DO UPDATE SET
          report_type = excluded.report_type,
          period_start = excluded.period_start,
          period_end = excluded.period_end,
          title = excluded.title,
          summary_markdown = excluded.summary_markdown,
          metrics_json = excluded.metrics_json,
          source_snapshot_json = excluded.source_snapshot_json,
          status = excluded.status,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at,
          confirmed_at = excluded.confirmed_at
        ''',
        values,
      );
      final row = await _database.customSelect(
        'SELECT id FROM report_documents WHERE report_uid = ? LIMIT 1',
        variables: [Variable<String>(reportUid)],
      ).getSingleOrNull();
      final localId = row?.read<int>('id');
      return localId == null ? _lastInsertId() : localId.toString();
    }
    await _database.customStatement(
      '''
      UPDATE report_documents
      SET report_uid = ?,
          report_type = ?,
          period_start = ?,
          period_end = ?,
          title = ?,
          summary_markdown = ?,
          metrics_json = ?,
          source_snapshot_json = ?,
          status = ?,
          created_at = ?,
          updated_at = ?,
          confirmed_at = ?
      WHERE id = ?
      ''',
      [...values, id],
    );
    return id.toString();
  }

  Future<String> _upsertDiaryEntry(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final entryDate = _date(payload, 'entryDate', 'entry_date') ?? DateTime.now();
    final diaryUid =
        change.uid ?? _string(payload, 'diaryUid', 'diary_uid') ?? change.serverId;
    final values = [
      diaryUid,
      _dayKey(entryDate),
      _string(payload, 'title') ?? '远端日记',
      _string(payload, 'bodyMarkdown', 'body_markdown') ?? '',
      _int(payload, 'sourceReportId', 'source_report_id'),
      _string(payload, 'linkedTaskIdsJson', 'linked_task_ids_json') ?? '[]',
      _string(payload, 'linkedFileIdsJson', 'linked_file_ids_json') ?? '[]',
      _string(payload, 'locationJson', 'location_json') ?? '{}',
      _string(payload, 'weatherJson', 'weather_json') ?? '{}',
      _string(payload, 'status') ?? 'draft',
      _string(payload, 'createdAt', 'created_at') ?? now,
      now,
      _date(payload, 'confirmedAt', 'confirmed_at')?.toIso8601String(),
    ];
    var targetId = id;
    if (targetId == null) {
      final existing = await _database.customSelect(
        'SELECT id FROM diary_entries WHERE diary_uid = ? LIMIT 1',
        variables: [Variable<String>(diaryUid)],
      ).getSingleOrNull();
      targetId = existing == null ? null : existing.read<int>('id');
    }
    if (targetId == null) {
      await _database.customStatement(
        '''
        INSERT INTO diary_entries (
          diary_uid,
          entry_date,
          title,
          body_markdown,
          source_report_id,
          linked_task_ids_json,
          linked_file_ids_json,
          location_json,
          weather_json,
          status,
          created_at,
          updated_at,
          confirmed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }
    await _database.customStatement(
      '''
      UPDATE diary_entries
      SET diary_uid = ?,
          entry_date = ?,
          title = ?,
          body_markdown = ?,
          source_report_id = ?,
          linked_task_ids_json = ?,
          linked_file_ids_json = ?,
          location_json = ?,
          weather_json = ?,
          status = ?,
          created_at = ?,
          updated_at = ?,
          confirmed_at = ?
      WHERE id = ?
      ''',
      [...values, targetId],
    );
    return targetId.toString();
  }

  Future<String> _upsertReportPushDelivery(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final values = [
      change.uid ??
          _string(payload, 'deliveryUid', 'delivery_uid') ??
          change.serverId,
      _int(payload, 'reportId', 'report_id'),
      _int(payload, 'diaryId', 'diary_id'),
      _string(payload, 'channel') ?? 'telegram',
      _string(payload, 'target'),
      _string(payload, 'payloadJson', 'payload_json') ?? '{}',
      _string(payload, 'status') ?? 'pending',
      _int(payload, 'attempts') ?? 0,
      _string(payload, 'lastError', 'last_error'),
      (_date(payload, 'scheduledAt', 'scheduled_at') ?? DateTime.now()).toIso8601String(),
      _date(payload, 'sentAt', 'sent_at')?.toIso8601String(),
      _string(payload, 'createdAt', 'created_at') ?? now,
      now,
    ];
    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO report_push_deliveries (
          delivery_uid,
          report_id,
          diary_id,
          channel,
          target,
          payload_json,
          status,
          attempts,
          last_error,
          scheduled_at,
          sent_at,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }
    await _database.customStatement(
      '''
      UPDATE report_push_deliveries
      SET delivery_uid = ?,
          report_id = ?,
          diary_id = ?,
          channel = ?,
          target = ?,
          payload_json = ?,
          status = ?,
          attempts = ?,
          last_error = ?,
          scheduled_at = ?,
          sent_at = ?,
          created_at = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [...values, id],
    );
    return id.toString();
  }

  Future<String> _upsertFileFolder(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final values = [
      change.uid ?? _string(payload, 'folderUid', 'folder_uid') ?? change.serverId,
      _string(payload, 'provider') ?? 'local',
      _string(payload, 'displayName', 'display_name') ?? '远端文件夹',
      _string(payload, 'localPath', 'local_path'),
      _string(payload, 'remoteId', 'remote_id'),
      _string(payload, 'parentPath', 'parent_path'),
      _string(payload, 'sourceContext', 'source_context'),
      (_bool(payload, 'pinned') ?? false) ? 1 : 0,
      _string(payload, 'availability') ?? 'remote_only',
      _int(payload, 'useCount', 'use_count') ?? 0,
      _date(payload, 'lastUsedAt', 'last_used_at')?.toIso8601String(),
      _string(payload, 'metadataJson', 'metadata_json') ?? '{}',
      _string(payload, 'createdAt', 'created_at') ?? now,
      now,
    ];
    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO file_folders (
          folder_uid,
          provider,
          display_name,
          local_path,
          remote_id,
          parent_path,
          source_context,
          pinned,
          availability,
          use_count,
          last_used_at,
          metadata_json,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }
    await _database.customStatement(
      '''
      UPDATE file_folders
      SET folder_uid = ?,
          provider = ?,
          display_name = ?,
          local_path = ?,
          remote_id = ?,
          parent_path = ?,
          source_context = ?,
          pinned = ?,
          availability = ?,
          use_count = ?,
          last_used_at = ?,
          metadata_json = ?,
          created_at = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [...values, id],
    );
    return id.toString();
  }

  Future<String> _upsertFileItem(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final values = [
      change.uid ?? _string(payload, 'fileUid', 'file_uid') ?? change.serverId,
      _string(payload, 'provider') ?? 'local',
      _string(payload, 'displayName', 'display_name') ?? '远端文件',
      _int(payload, 'folderId', 'folder_id'),
      _string(payload, 'localPath', 'local_path'),
      _string(payload, 'remoteId', 'remote_id'),
      _string(payload, 'mimeType', 'mime_type'),
      _int(payload, 'sizeBytes', 'size_bytes'),
      _date(payload, 'modifiedAt', 'modified_at')?.toIso8601String(),
      _string(payload, 'availability') ?? 'remote_only',
      _string(payload, 'previewMode', 'preview_mode') ?? 'none',
      _string(payload, 'metadataJson', 'metadata_json') ?? '{}',
      _string(payload, 'createdAt', 'created_at') ?? now,
      now,
    ];
    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO file_items (
          file_uid,
          provider,
          display_name,
          folder_id,
          local_path,
          remote_id,
          mime_type,
          size_bytes,
          modified_at,
          availability,
          preview_mode,
          metadata_json,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }
    await _database.customStatement(
      '''
      UPDATE file_items
      SET file_uid = ?,
          provider = ?,
          display_name = ?,
          folder_id = ?,
          local_path = ?,
          remote_id = ?,
          mime_type = ?,
          size_bytes = ?,
          modified_at = ?,
          availability = ?,
          preview_mode = ?,
          metadata_json = ?,
          created_at = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [...values, id],
    );
    return id.toString();
  }

  Future<String> _upsertFileContextLink(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final values = [
      change.uid ?? _string(payload, 'linkUid', 'link_uid') ?? change.serverId,
      _string(payload, 'entityType', 'entity_type') ?? 'task',
      _string(payload, 'entityId', 'entity_id') ?? '',
      _string(payload, 'targetType', 'target_type') ?? 'folder',
      _int(payload, 'targetId', 'target_id') ?? 0,
      _string(payload, 'relationType', 'relation_type') ?? 'manual',
      _double(payload, 'confidence') ?? 1.0,
      _string(payload, 'reason'),
      _string(payload, 'status') ?? 'confirmed',
      _string(payload, 'createdAt', 'created_at') ?? now,
      now,
      _date(payload, 'confirmedAt', 'confirmed_at')?.toIso8601String(),
    ];
    var targetId = id;
    if (targetId == null) {
      final existingByUid = await _database.customSelect(
        'SELECT id FROM file_context_links WHERE link_uid = ? LIMIT 1',
        variables: [Variable<String>(values[0] as String)],
      ).getSingleOrNull();
      targetId = existingByUid?.read<int>('id');
    }
    if (targetId == null) {
      final existingByNaturalKey = await _database.customSelect(
        '''
        SELECT id
        FROM file_context_links
        WHERE entity_type = ?
          AND entity_id = ?
          AND target_type = ?
          AND target_id = ?
          AND status <> 'rejected'
        LIMIT 1
        ''',
        variables: [
          Variable<String>(values[1] as String),
          Variable<String>(values[2] as String),
          Variable<String>(values[3] as String),
          Variable<int>(values[4] as int),
        ],
      ).getSingleOrNull();
      targetId = existingByNaturalKey?.read<int>('id');
    }
    if (targetId == null) {
      await _database.customStatement(
        '''
        INSERT INTO file_context_links (
          link_uid,
          entity_type,
          entity_id,
          target_type,
          target_id,
          relation_type,
          confidence,
          reason,
          status,
          created_at,
          updated_at,
          confirmed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }
    await _database.customStatement(
      '''
      UPDATE file_context_links
      SET link_uid = ?,
          entity_type = ?,
          entity_id = ?,
          target_type = ?,
          target_id = ?,
          relation_type = ?,
          confidence = ?,
          reason = ?,
          status = ?,
          created_at = ?,
          updated_at = ?,
          confirmed_at = ?
      WHERE id = ?
      ''',
      [...values, targetId],
    );
    return targetId.toString();
  }

  Future<String> _upsertFileFolderUsage(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final values = [
      change.uid ?? _string(payload, 'usageUid', 'usage_uid') ?? change.serverId,
      _int(payload, 'folderId', 'folder_id') ?? 0,
      _string(payload, 'entityType', 'entity_type'),
      _string(payload, 'entityId', 'entity_id'),
      _string(payload, 'action') ?? 'open',
      _string(payload, 'source') ?? 'sync',
      (_date(payload, 'usedAt', 'used_at') ?? DateTime.now()).toIso8601String(),
      _string(payload, 'metadataJson', 'metadata_json') ?? '{}',
    ];
    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO file_folder_usages (
          usage_uid,
          folder_id,
          entity_type,
          entity_id,
          action,
          source,
          used_at,
          metadata_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }
    await _database.customStatement(
      '''
      UPDATE file_folder_usages
      SET usage_uid = ?,
          folder_id = ?,
          entity_type = ?,
          entity_id = ?,
          action = ?,
          source = ?,
          used_at = ?,
          metadata_json = ?
      WHERE id = ?
      ''',
      [...values, id],
    );
    return id.toString();
  }

  Future<String> _upsertFileVersionRecord(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final payload = change.payload;
    final id = int.tryParse(currentLocalId ?? '');
    final now = DateTime.now().toIso8601String();
    final values = [
      change.uid ??
          _string(payload, 'versionUid', 'version_uid') ??
          change.serverId,
      _int(payload, 'fileId', 'file_id') ?? 0,
      _string(payload, 'provider') ?? 'kopia',
      _string(payload, 'versionRef', 'version_ref') ?? change.serverId,
      _string(payload, 'displayName', 'display_name') ?? '历史版本',
      _int(payload, 'sizeBytes', 'size_bytes'),
      _date(payload, 'modifiedAt', 'modified_at')?.toIso8601String(),
      _string(payload, 'checksum'),
      _string(payload, 'sourceDevice', 'source_device'),
      _string(payload, 'sourceBackend', 'source_backend'),
      _string(payload, 'note'),
      _string(payload, 'metadataJson', 'metadata_json') ?? '{}',
      _string(payload, 'createdAt', 'created_at') ?? now,
    ];
    if (id == null) {
      await _database.customStatement(
        '''
        INSERT INTO file_version_records (
          version_uid,
          file_id,
          provider,
          version_ref,
          display_name,
          size_bytes,
          modified_at,
          checksum,
          source_device,
          source_backend,
          note,
          metadata_json,
          created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        values,
      );
      return _lastInsertId();
    }
    await _database.customStatement(
      '''
      UPDATE file_version_records
      SET version_uid = ?,
          file_id = ?,
          provider = ?,
          version_ref = ?,
          display_name = ?,
          size_bytes = ?,
          modified_at = ?,
          checksum = ?,
          source_device = ?,
          source_backend = ?,
          note = ?,
          metadata_json = ?,
          created_at = ?
      WHERE id = ?
      ''',
      [...values, id],
    );
    return id.toString();
  }

  Future<String> _upsertAuditLog(
    ServerSyncChange change,
    String? currentLocalId,
  ) async {
    final id = int.tryParse(currentLocalId ?? '');
    if (id != null) {
      return id.toString();
    }
    final payload = change.payload;
    await _database.customStatement(
      '''
      INSERT INTO data_operation_logs (
        occurred_at,
        actor,
        action,
        entity_type,
        entity_id,
        summary,
        before_json,
        after_json,
        metadata_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        (_date(payload, 'occurredAt', 'occurred_at') ?? DateTime.now())
            .toIso8601String(),
        _string(payload, 'actor') ?? 'sync',
        _string(payload, 'action') ?? 'remote_change',
        _string(payload, 'entityType', 'entity_type') ?? 'unknown',
        _string(payload, 'entityId', 'entity_id'),
        _string(payload, 'summary') ?? '远端同步操作',
        _string(payload, 'beforeJson', 'before_json'),
        _string(payload, 'afterJson', 'after_json'),
        _string(payload, 'metadataJson', 'metadata_json'),
      ],
    );
    final row = await _database.customSelect(
      'SELECT last_insert_rowid() AS id',
    ).getSingle();
    return row.read<int>('id').toString();
  }

  Future<String?> _upsertUserSetting(ServerSyncChange change) async {
    final key = change.uid ?? _string(change.payload, 'settingKey', 'setting_key');
    final value = _string(change.payload, 'settingValue', 'setting_value');
    if (key == null || value == null) {
      return null;
    }
    await _database.setSetting(key, value);
    return key;
  }

  String? _string(Map<String, dynamic> payload, String key, [String? alt, String? alt2]) {
    final value = payload[key] ??
        (alt == null ? null : payload[alt]) ??
        (alt2 == null ? null : payload[alt2]);
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _locationString(Map<String, dynamic> payload) {
    final direct = payload['location'];
    if (direct is String) {
      final text = direct.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    if (direct is Map) {
      final displayName = direct['displayName']?.toString().trim();
      if (displayName != null && displayName.isNotEmpty) {
        return displayName;
      }
    }
    final locations = payload['locations'];
    if (locations is List) {
      final names = locations
          .whereType<Map>()
          .map((item) => item['displayName']?.toString().trim())
          .whereType<String>()
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
      if (names.isNotEmpty) {
        return names.join(', ');
      }
    }
    return null;
  }

  int? _int(Map<String, dynamic> payload, String key, [String? alt]) {
    final value = payload[key] ?? (alt == null ? null : payload[alt]);
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  double? _double(Map<String, dynamic> payload, String key, [String? alt]) {
    final value = payload[key] ?? (alt == null ? null : payload[alt]);
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  bool? _bool(Map<String, dynamic> payload, String key, [String? alt]) {
    final value = payload[key] ?? (alt == null ? null : payload[alt]);
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }

  DateTime? _date(Map<String, dynamic> payload, String key, [String? alt, String? alt2, String? alt3]) {
    final value = payload[key] ??
        (alt == null ? null : payload[alt]) ??
        (alt2 == null ? null : payload[alt2]) ??
        (alt3 == null ? null : payload[alt3]);
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String _dayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<String> _lastInsertId() async {
    final row = await _database.customSelect(
      'SELECT last_insert_rowid() AS id',
    ).getSingle();
    return row.read<int>('id').toString();
  }
}
