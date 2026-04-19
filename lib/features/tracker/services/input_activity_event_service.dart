import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../../../core/storage/app_storage.dart';
import '../models/activity_log_archive_day.dart';
import '../models/input_event_query.dart';
import '../models/input_heatmap_summary.dart';
import '../models/tracked_input_event.dart';
import 'raw_input_service.dart';
import '../tracker_defaults.dart';

class InputActivityEventService {
  InputActivityEventService(this._database);

  final AppDatabase _database;
  static const _dailyArchiveBackfillSettingKey =
      'tracker.input_events_database_to_daily_jsonl_backfilled';

  Future<void>? _initializationFuture;

  Future<String> getArchiveDirectoryPath() async {
    await _ensureInitialized();
    final directory = await _resolveLogDirectory();
    return directory.path;
  }

  Future<List<ActivityLogArchiveDay>> listArchiveDays() async {
    await _ensureInitialized();
    var days = await _scanArchiveDays();
    if (days.isEmpty) {
      await _ensureDailyArchiveBackfill();
      days = await _scanArchiveDays();
    }
    return days;
  }

  Future<List<TrackedInputEvent>> readArchivedEventsForDate(DateTime date) async {
    await _ensureInitialized();
    final file = await _resolveDailyArchiveFileForDayKey(_formatDate(date));
    if (!await file.exists()) {
      await _ensureDailyArchiveBackfill();
    }
    if (!await file.exists()) {
      final events = await _readEventsForDayKey(_formatDate(date));
      if (events.isNotEmpty) {
        await _writeArchiveFile(file, events);
      }
      return events;
    }
    return _readEventsFromFile(file);
  }

  Future<void> appendEvents({
    required List<RawInputEvent> events,
    required List<InputEventContextBinding> bindings,
  }) async {
    await _ensureInitialized();
    if (events.isEmpty) {
      return;
    }

    final orderedEvents = List<RawInputEvent>.from(events)
      ..sort((left, right) {
        final byTime = left.timestampMicros.compareTo(right.timestampMicros);
        if (byTime != 0) {
          return byTime;
        }
        return left.sequenceId.compareTo(right.sequenceId);
      });

    const maxBatchSize = 40;
    for (var offset = 0; offset < orderedEvents.length; offset += maxBatchSize) {
      final batch = orderedEvents.skip(offset).take(maxBatchSize);
      final createdAtIso = DateTime.now().toIso8601String();
      final statements = <String>[];
      final arguments = <Object?>[];
      final trackedEventsInBatch = <TrackedInputEvent>[];
      for (final rawEvent in batch) {
        final explicitProcessName = _cleanText(rawEvent.processName);
        final explicitClassName = _cleanText(rawEvent.className);
        final explicitWindowTitle = _cleanText(rawEvent.windowTitle);
        final matchedBinding = _pickBinding(
          rawEvent: rawEvent,
          bindings: bindings,
        );
        final processName = explicitProcessName ?? matchedBinding?.processName;
        final className = explicitClassName ?? matchedBinding?.className;
        final windowTitle = explicitWindowTitle ?? matchedBinding?.windowTitle;
        final ignoredByContext = isTrackerSelfExcludedWindow(
          processName: processName,
          windowTitle: windowTitle,
        );
        final isIgnored =
            ignoredByContext || (matchedBinding?.isIgnored ?? false);
        final kind = trackedInputEventKindFromRaw(rawEvent.kind);
        final keyCode = rawEvent.keyCode;
        final keyLabel = keyCode == null ? null : inputKeyLabelForCode(keyCode);
        final occurredAt = rawEvent.timestamp;
        final occurredAtIso = occurredAt.toIso8601String();
        final trackedEvent = TrackedInputEvent(
          eventUid: _buildEventUid(
            rawEvent: rawEvent,
            occurredAtIso: occurredAtIso,
            processName: processName,
            windowTitle: windowTitle,
          ),
          sequenceId: rawEvent.sequenceId,
          timestamp: occurredAt,
          kind: kind,
          eventCount: rawEvent.eventCount,
          recordId: isIgnored ? null : matchedBinding?.recordId,
          isIgnored: isIgnored,
          processName: processName,
          className: className,
          windowTitle: windowTitle,
          category: isIgnored ? null : matchedBinding?.category,
          activityLabel: isIgnored ? null : matchedBinding?.activityLabel,
          keyCode: keyCode,
          keyLabel: keyLabel,
          mouseButton: _cleanText(rawEvent.mouseButton),
          wheelDelta: rawEvent.wheelDelta,
          deltaX: rawEvent.deltaX,
          deltaY: rawEvent.deltaY,
          moveDistance: rawEvent.moveDistance,
          tokenText: _cleanTokenText(rawEvent.tokenText),
        );
        trackedEventsInBatch.add(trackedEvent);

        statements.add(
          '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        );
        arguments.addAll(<Object?>[
          trackedEvent.eventUid,
          trackedEvent.sequenceId,
          occurredAtIso,
          _formatDate(occurredAt),
          trackedEvent.kind.value,
          trackedEvent.recordId,
          trackedEvent.processName,
          trackedEvent.windowTitle,
          trackedEvent.category,
          trackedEvent.activityLabel,
          trackedEvent.isIgnored ? 1 : 0,
          trackedEvent.keyCode,
          trackedEvent.keyLabel,
          trackedEvent.mouseButton,
          trackedEvent.wheelDelta,
          trackedEvent.deltaX,
          trackedEvent.deltaY,
          trackedEvent.moveDistance,
          trackedEvent.eventCount,
          trackedEvent.tokenText,
          '{}',
          createdAtIso,
          trackedEvent.className,
        ]);
      }

      await _database.customStatement(
        '''
        INSERT OR IGNORE INTO tracked_input_events (
          event_uid,
          sequence_id,
          occurred_at,
          day_key,
          event_kind,
          record_id,
          process_name,
          window_title,
          category,
          activity_label,
          is_ignored,
          key_code,
          key_label,
          mouse_button,
          wheel_delta,
          delta_x,
          delta_y,
          move_distance,
          event_count,
          token_text,
          payload_json,
          created_at,
          class_name
        ) VALUES ${statements.join(', ')}
        ''',
        arguments,
      );
      await _appendToDailyArchives(trackedEventsInBatch);
    }
  }

  Future<List<TrackedInputEvent>> listEvents({
    DateTime? start,
    DateTime? end,
    String? processName,
    int? limit,
    bool includeIgnored = false,
  }) async {
    await _ensureInitialized();
    final where = _buildWhereClause(
      start: start,
      end: end,
      processName: processName,
      includeIgnored: includeIgnored,
    );
    final rows = await _database.customSelect(
      '''
      SELECT ${_trackedInputEventProjection()}
      FROM tracked_input_events
      ${where.sql}
      ORDER BY occurred_at ASC, sequence_id ASC, id ASC
      ${limit == null ? '' : 'LIMIT ?'}
      ''',
      variables: <Variable>[
        ...where.variables,
        if (limit != null) Variable<int>(limit),
      ],
    ).get();
    return _decodeTrackedInputEventRows(rows);
  }

  Future<List<TrackedInputEvent>> listRecentEvents({
    int limit = 12,
    bool includeIgnored = false,
  }) async {
    await _ensureInitialized();
    final where = _buildWhereClause(
      includeIgnored: includeIgnored,
    );
    final rows = await _database.customSelect(
      '''
      SELECT ${_trackedInputEventProjection()}
      FROM tracked_input_events
      ${where.sql}
      ORDER BY occurred_at DESC, sequence_id DESC, id DESC
      LIMIT ?
      ''',
      variables: <Variable>[
        ...where.variables,
        Variable<int>(limit),
      ],
    ).get();
    return _decodeTrackedInputEventRows(rows);
  }

  Future<List<String>> listProcessNames() async {
    await _ensureInitialized();
    final rows = await _database.customSelect(
      '''
      SELECT DISTINCT process_name
      FROM tracked_input_events
      WHERE is_ignored = 0
        AND process_name IS NOT NULL
        AND TRIM(process_name) != ''
      ORDER BY LOWER(process_name) ASC
      ''',
    ).get();
    return rows
        .map((row) => row.read<String>('process_name'))
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<InputHeatmapSummary> buildHeatmapSummary(InputEventQuery query) async {
    await _ensureInitialized();
    final where = _buildWhereClause(
      start: query.start,
      end: query.end,
      processName: query.processName,
      includeIgnored: false,
    );
    final data = await _loadAggregateData(
      fromAndWhereSql: 'FROM tracked_input_events ${where.sql}',
      variables: where.variables,
    );
    return _buildSummaryFromAggregateData(query: query, data: data);
  }

  Future<InputHeatmapSummary> buildHeatmapSummaryForTask(int taskId) async {
    await _ensureInitialized();
    final data = await _loadAggregateData(
      fromAndWhereSql: '''
        FROM tracked_input_events e
        INNER JOIN activity_records r ON r.id = e.record_id
        WHERE r.linked_task_id = ?
          AND e.is_ignored = 0
      ''',
      variables: <Variable>[Variable<int>(taskId)],
      tableAlias: 'e',
    );

    final query = InputEventQuery(
      start: data.firstOccurredAt ?? DateTime.now(),
      end: data.lastOccurredAt?.add(const Duration(seconds: 1)) ?? DateTime.now(),
    );
    return _buildSummaryFromAggregateData(query: query, data: data);
  }

  Future<List<TrackedInputEvent>> listRecentEventsForTask(
    int taskId, {
    int limit = 10,
  }) async {
    await _ensureInitialized();
    final rows = await _database.customSelect(
      '''
      SELECT ${_trackedInputEventProjection(tableAlias: 'e')}
      FROM tracked_input_events e
      INNER JOIN activity_records r ON r.id = e.record_id
      WHERE r.linked_task_id = ?
        AND e.is_ignored = 0
      ORDER BY e.occurred_at DESC, e.sequence_id DESC, e.id DESC
      LIMIT ?
      ''',
      variables: <Variable>[
        Variable<int>(taskId),
        Variable<int>(limit),
      ],
    ).get();
    return _decodeTrackedInputEventRows(rows);
  }

  Future<void> exportEventsToJsonl(
    String targetPath, {
    DateTime? start,
    DateTime? end,
    String? processName,
    bool includeIgnored = true,
  }) async {
    await _ensureInitialized();
    final where = _buildWhereClause(
      start: start,
      end: end,
      processName: processName,
      includeIgnored: includeIgnored,
    );
    final rows = await _database.customSelect(
      '''
      SELECT ${_trackedInputEventProjection()}
      FROM tracked_input_events
      ${where.sql}
      ORDER BY occurred_at ASC, sequence_id ASC, id ASC
      ''',
      variables: where.variables,
    ).get();

    final file = File(targetPath);
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      await file.delete();
    }

    final sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    try {
      for (final row in rows) {
        sink.writeln(jsonEncode(_trackedInputEventFromRow(row).toJson()));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<void> _ensureInitialized() async {
    _initializationFuture ??= _initialize();
    await _initializationFuture;
  }

  Future<void> _initialize() async {}

  Future<void> _ensureDailyArchiveBackfill() async {
    final migrated = await _database.getBoolSetting(
      _dailyArchiveBackfillSettingKey,
      defaultValue: false,
    );
    if (migrated) {
      return;
    }

    await _materializeArchiveFilesFromDatabase();
    await _database.setBoolSetting(_dailyArchiveBackfillSettingKey, true);
  }

  Future<void> _materializeArchiveFilesFromDatabase() async {
    final rows = await _database.customSelect(
      '''
      SELECT day_key
      FROM tracked_input_events
      GROUP BY day_key
      ORDER BY day_key ASC
      ''',
    ).get();

    for (final row in rows) {
      final dayKey = row.read<String>('day_key');
      final file = await _resolveDailyArchiveFileForDayKey(dayKey);
      if (await file.exists()) {
        continue;
      }

      final events = await _readEventsForDayKey(dayKey);
      await _writeArchiveFile(file, events);
    }
  }

  Future<List<ActivityLogArchiveDay>> _scanArchiveDays() async {
    final directory = await _resolveLogDirectory();
    if (!await directory.exists()) {
      return const <ActivityLogArchiveDay>[];
    }

    final files = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => _tryParseDayKeyFromFileName(p.basename(file.path)) != null)
        .toList();

    final days = <ActivityLogArchiveDay>[];
    for (final file in files) {
      final fileName = p.basename(file.path);
      final dayKey = _tryParseDayKeyFromFileName(fileName);
      if (dayKey == null) {
        continue;
      }
      days.add(
        ActivityLogArchiveDay(
          date: _parseDayKey(dayKey),
          dayKey: dayKey,
          filePath: file.path,
          fileSizeBytes: await file.length(),
        ),
      );
    }

    days.sort((left, right) => right.dayKey.compareTo(left.dayKey));
    return days;
  }

  Future<List<TrackedInputEvent>> _readEventsForDayKey(String dayKey) async {
    final rows = await _database.customSelect(
      '''
      SELECT ${_trackedInputEventProjection()}
      FROM tracked_input_events
      WHERE day_key = ?
      ORDER BY occurred_at ASC, sequence_id ASC, id ASC
      ''',
      variables: [Variable<String>(dayKey)],
    ).get();
    return _decodeTrackedInputEventRows(rows);
  }

  Future<InputHeatmapSummary> _buildSummaryFromAggregateData({
    required InputEventQuery query,
    required _InputHeatmapAggregateData data,
  }) async {
    if (data.totalEventCount <= 0) {
      return InputHeatmapSummary.empty(query);
    }

    return _buildInputHeatmapSummary(
      query: query,
      data: data,
    );
  }

  Future<_InputHeatmapAggregateData> _loadAggregateData({
    required String fromAndWhereSql,
    required List<Variable> variables,
    String tableAlias = '',
  }) async {
    final occurredAt = _qualifiedColumn(tableAlias, 'occurred_at');
    final eventCount = _qualifiedColumn(tableAlias, 'event_count');
    final eventKind = _qualifiedColumn(tableAlias, 'event_kind');
    final keyCode = _qualifiedColumn(tableAlias, 'key_code');
    final mouseButton = _qualifiedColumn(tableAlias, 'mouse_button');
    final moveDistance = _qualifiedColumn(tableAlias, 'move_distance');
    final processName = _qualifiedColumn(tableAlias, 'process_name');
    final hasWhereClause = fromAndWhereSql.toUpperCase().contains('WHERE');

    final overallRow = await _database.customSelect(
      '''
      SELECT
        COALESCE(SUM($eventCount), 0) AS total_event_count,
        COUNT(DISTINCT substr($occurredAt, 1, 16)) AS active_minute_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'key_down' THEN $eventCount ELSE 0 END), 0) AS keyboard_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_button' THEN $eventCount ELSE 0 END), 0) AS mouse_button_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_wheel' THEN $eventCount ELSE 0 END), 0) AS wheel_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_move' THEN $eventCount ELSE 0 END), 0) AS mouse_move_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_move' THEN $moveDistance ELSE 0 END), 0) AS mouse_move_distance,
        MIN($occurredAt) AS first_occurred_at,
        MAX($occurredAt) AS last_occurred_at
      $fromAndWhereSql
      ''',
      variables: variables,
    ).getSingleOrNull();

    if (overallRow == null) {
      return const _InputHeatmapAggregateData.empty();
    }

    final totalEventCount = overallRow.read<int?>('total_event_count') ?? 0;
    final firstOccurredAt = DateTime.tryParse(
      overallRow.read<String?>('first_occurred_at') ?? '',
    );
    final lastOccurredAt = DateTime.tryParse(
      overallRow.read<String?>('last_occurred_at') ?? '',
    );

    if (totalEventCount <= 0) {
      return _InputHeatmapAggregateData(
        totalEventCount: 0,
        activeMinuteCount: 0,
        keyboardEventCount: 0,
        mouseButtonEventCount: 0,
        wheelEventCount: 0,
        mouseMoveEventCount: 0,
        mouseMoveDistance: 0,
        firstOccurredAt: firstOccurredAt,
        lastOccurredAt: lastOccurredAt,
        keyCounts: const <_InputCountAggregateRow>[],
        mouseCounts: const <_InputStringCountAggregateRow>[],
        processes: const <_InputProcessAggregateRow>[],
        hours: const <_InputHourAggregateRow>[],
      );
    }

    final keyRows = await _database.customSelect(
      '''
      SELECT
        $keyCode AS key_code,
        COALESCE(SUM($eventCount), 0) AS key_event_count
      $fromAndWhereSql
      ${hasWhereClause ? 'AND' : 'WHERE'} $eventKind = 'key_down'
        AND $keyCode IS NOT NULL
      GROUP BY $keyCode
      ORDER BY key_event_count DESC, key_code ASC
      ''',
      variables: variables,
    ).get();

    final mouseRows = await _database.customSelect(
      '''
      SELECT
        $mouseButton AS mouse_button,
        COALESCE(SUM($eventCount), 0) AS button_event_count
      $fromAndWhereSql
      ${hasWhereClause ? 'AND' : 'WHERE'} $mouseButton IS NOT NULL
        AND TRIM($mouseButton) != ''
        AND $eventKind IN ('mouse_button', 'mouse_wheel')
      GROUP BY $mouseButton
      ORDER BY button_event_count DESC, mouse_button ASC
      ''',
      variables: variables,
    ).get();

    final normalizedProcessName =
        "COALESCE(NULLIF(TRIM($processName), ''), '未知应用')";
    final processRows = await _database.customSelect(
      '''
      SELECT
        $normalizedProcessName AS process_name,
        COALESCE(SUM($eventCount), 0) AS total_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'key_down' THEN $eventCount ELSE 0 END), 0) AS key_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_button' THEN $eventCount ELSE 0 END), 0) AS mouse_button_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_wheel' THEN $eventCount ELSE 0 END), 0) AS wheel_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_move' THEN $eventCount ELSE 0 END), 0) AS mouse_move_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_move' THEN $moveDistance ELSE 0 END), 0) AS move_distance,
        COUNT(DISTINCT substr($occurredAt, 1, 16)) AS active_minute_count
      $fromAndWhereSql
      GROUP BY $normalizedProcessName
      ORDER BY total_event_count DESC, process_name ASC
      ''',
      variables: variables,
    ).get();

    final hourRows = await _database.customSelect(
      '''
      SELECT
        CAST(substr($occurredAt, 12, 2) AS INTEGER) AS hour_bucket,
        COALESCE(SUM($eventCount), 0) AS total_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'key_down' THEN $eventCount ELSE 0 END), 0) AS key_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_button' THEN $eventCount ELSE 0 END), 0) AS mouse_button_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_wheel' THEN $eventCount ELSE 0 END), 0) AS wheel_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_move' THEN $eventCount ELSE 0 END), 0) AS mouse_move_event_count,
        COALESCE(SUM(CASE WHEN $eventKind = 'mouse_move' THEN $moveDistance ELSE 0 END), 0) AS move_distance,
        COUNT(DISTINCT substr($occurredAt, 1, 16)) AS active_minute_count
      $fromAndWhereSql
      GROUP BY hour_bucket
      ORDER BY hour_bucket ASC
      ''',
      variables: variables,
    ).get();

    return _InputHeatmapAggregateData(
      totalEventCount: totalEventCount,
      activeMinuteCount: overallRow.read<int?>('active_minute_count') ?? 0,
      keyboardEventCount: overallRow.read<int?>('keyboard_event_count') ?? 0,
      mouseButtonEventCount:
          overallRow.read<int?>('mouse_button_event_count') ?? 0,
      wheelEventCount: overallRow.read<int?>('wheel_event_count') ?? 0,
      mouseMoveEventCount: overallRow.read<int?>('mouse_move_event_count') ?? 0,
      mouseMoveDistance: overallRow.read<int?>('mouse_move_distance') ?? 0,
      firstOccurredAt: firstOccurredAt,
      lastOccurredAt: lastOccurredAt,
      keyCounts: keyRows
          .map(
            (row) => _InputCountAggregateRow(
              key: row.read<int>('key_code'),
              count: row.read<int?>('key_event_count') ?? 0,
            ),
          )
          .toList(growable: false),
      mouseCounts: mouseRows
          .map(
            (row) => _InputStringCountAggregateRow(
              key: row.read<String>('mouse_button'),
              count: row.read<int?>('button_event_count') ?? 0,
            ),
          )
          .toList(growable: false),
      processes: processRows
          .map(
            (row) => _InputProcessAggregateRow(
              processName: row.read<String>('process_name'),
              totalEvents: row.read<int?>('total_event_count') ?? 0,
              keyEvents: row.read<int?>('key_event_count') ?? 0,
              mouseButtonEvents:
                  row.read<int?>('mouse_button_event_count') ?? 0,
              wheelEvents: row.read<int?>('wheel_event_count') ?? 0,
              mouseMoveEvents: row.read<int?>('mouse_move_event_count') ?? 0,
              moveDistance: row.read<int?>('move_distance') ?? 0,
              activeMinutes: row.read<int?>('active_minute_count') ?? 0,
            ),
          )
          .toList(growable: false),
      hours: hourRows
          .map(
            (row) => _InputHourAggregateRow(
              hour: row.read<int?>('hour_bucket') ?? 0,
              totalEvents: row.read<int?>('total_event_count') ?? 0,
              keyEvents: row.read<int?>('key_event_count') ?? 0,
              mouseButtonEvents:
                  row.read<int?>('mouse_button_event_count') ?? 0,
              wheelEvents: row.read<int?>('wheel_event_count') ?? 0,
              mouseMoveEvents: row.read<int?>('mouse_move_event_count') ?? 0,
              moveDistance: row.read<int?>('move_distance') ?? 0,
              activeMinutes: row.read<int?>('active_minute_count') ?? 0,
            ),
          )
          .toList(growable: false),
    );
  }

  List<TrackedInputEvent> _decodeTrackedInputEventRows(List<QueryRow> rows) {
    final events = <TrackedInputEvent>[];
    for (final row in rows) {
      try {
        events.add(_trackedInputEventFromRow(row));
      } catch (_) {
        // Ignore malformed rows so one damaged event won't block other results.
      }
    }
    return events;
  }

  TrackedInputEvent _trackedInputEventFromRow(QueryRow row) {
    final payload = _decodePayloadJson(row.read<String?>('payload_json'));
    return TrackedInputEvent(
      eventUid: row.read<String>('event_uid'),
      sequenceId: row.read<int>('sequence_id'),
      timestamp: DateTime.tryParse(row.read<String>('occurred_at')) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      kind: TrackedInputEventKindValue.fromValue(row.read<String>('event_kind')),
      eventCount:
          row.read<int?>('event_count') ??
          ((payload?['eventCount']) as num?)?.toInt() ??
          1,
      recordId: row.read<int?>('record_id'),
      isIgnored: (row.read<int?>('is_ignored') ?? 0) != 0,
      processName: row.read<String?>('process_name'),
      className: row.read<String?>('class_name'),
      windowTitle: row.read<String?>('window_title'),
      category: row.read<String?>('category'),
      activityLabel: row.read<String?>('activity_label'),
      keyCode: row.read<int?>('key_code'),
      keyLabel: row.read<String?>('key_label'),
      mouseButton: row.read<String?>('mouse_button'),
      wheelDelta: row.read<int?>('wheel_delta') ?? 0,
      deltaX:
          row.read<int?>('delta_x') ??
          ((payload?['deltaX']) as num?)?.toInt() ??
          0,
      deltaY:
          row.read<int?>('delta_y') ??
          ((payload?['deltaY']) as num?)?.toInt() ??
          0,
      moveDistance: row.read<int?>('move_distance') ?? 0,
      tokenText: _cleanTokenText(
        row.read<String?>('token_text') ??
            ((payload?['tokenText']) as String?),
      ),
    );
  }

  Map<String, dynamic>? _decodePayloadJson(String? payloadJson) {
    final trimmed = payloadJson?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == '{}') {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Ignore malformed historical payloads and fall back to structured columns.
    }
    return null;
  }

  String _trackedInputEventProjection({String tableAlias = ''}) {
    const columns = <String>[
      'event_uid',
      'sequence_id',
      'occurred_at',
      'event_kind',
      'record_id',
      'is_ignored',
      'process_name',
      'class_name',
      'window_title',
      'category',
      'activity_label',
      'key_code',
      'key_label',
      'mouse_button',
      'wheel_delta',
      'delta_x',
      'delta_y',
      'move_distance',
      'event_count',
      'token_text',
      'payload_json',
    ];
    return columns
        .map(
          (column) => '${_qualifiedColumn(tableAlias, column)} AS $column',
        )
        .join(', ');
  }

  String _qualifiedColumn(String tableAlias, String columnName) {
    final alias = tableAlias.trim();
    if (alias.isEmpty) {
      return columnName;
    }
    return '$alias.$columnName';
  }

  Future<List<TrackedInputEvent>> _readEventsFromFile(File file) async {
    final lines = await file.readAsLines();
    final events = <TrackedInputEvent>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          events.add(
            TrackedInputEvent.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {
        // Skip malformed lines so one damaged archive line won't block reading.
      }
    }
    return events;
  }

  Future<void> _appendToDailyArchives(List<TrackedInputEvent> events) async {
    if (events.isEmpty) {
      return;
    }

    final grouped = <String, List<TrackedInputEvent>>{};
    for (final event in events) {
      final dayKey = _formatDate(event.timestamp);
      grouped.putIfAbsent(dayKey, () => <TrackedInputEvent>[]).add(event);
    }

    for (final entry in grouped.entries) {
      final file = await _resolveDailyArchiveFileForDayKey(entry.key);
      await file.parent.create(recursive: true);
      final contents = entry.value
          .map((event) => jsonEncode(event.toJson()))
          .join('\n');
      await file.writeAsString(
        '$contents\n',
        mode: FileMode.append,
        flush: true,
      );
    }
  }

  Future<void> _writeArchiveFile(
    File file,
    List<TrackedInputEvent> events,
  ) async {
    if (events.isEmpty) {
      return;
    }

    await file.parent.create(recursive: true);
    final contents =
        events.map((event) => jsonEncode(event.toJson())).join('\n');
    await file.writeAsString('$contents\n', flush: true);
  }

  Future<Directory> _resolveLogDirectory() async {
    final root = await resolveAppStorageDirectory();
    return Directory('${root.path}${Platform.pathSeparator}logs');
  }

  Future<File> _resolveDailyArchiveFileForDayKey(String dayKey) async {
    final directory = await _resolveLogDirectory();
    return File(p.join(directory.path, '$dayKey.input-events.jsonl'));
  }

  static String? _tryParseDayKeyFromFileName(String fileName) {
    final match =
        RegExp(r'^(\d{4}-\d{2}-\d{2})\.input-events\.jsonl$').firstMatch(fileName);
    return match?.group(1);
  }

  static DateTime _parseDayKey(String dayKey) {
    final parts = dayKey.split('-');
    if (parts.length != 3) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    final year = int.tryParse(parts[0]) ?? 1970;
    final month = int.tryParse(parts[1]) ?? 1;
    final day = int.tryParse(parts[2]) ?? 1;
    return DateTime(year, month, day);
  }

  InputEventContextBinding? _pickBinding({
    required RawInputEvent rawEvent,
    required List<InputEventContextBinding> bindings,
  }) {
    if (bindings.isEmpty) {
      return null;
    }

    final explicitProcess = _normalize(rawEvent.processName);
    final explicitClass = _normalize(rawEvent.className);
    final explicitTitle = _normalize(rawEvent.windowTitle);
    final hasExplicitContext = explicitProcess != null ||
        explicitClass != null ||
        explicitTitle != null;

    if (!hasExplicitContext) {
      return bindings.first;
    }

    InputEventContextBinding? best;
    var bestScore = 0;
    for (final binding in bindings) {
      var score = 0;
      if (explicitProcess != null &&
          explicitProcess == _normalize(binding.processName)) {
        score += 4;
      }
      if (explicitClass != null && explicitClass == _normalize(binding.className)) {
        score += 2;
      }
      final bindingTitle = _normalize(binding.windowTitle);
      if (explicitTitle != null &&
          bindingTitle != null &&
          (explicitTitle == bindingTitle ||
              explicitTitle.contains(bindingTitle) ||
              bindingTitle.contains(explicitTitle))) {
        score += 1;
      }

      if (score > bestScore) {
        best = binding;
        bestScore = score;
      }
    }

    if (bestScore <= 0) {
      return null;
    }
    return best;
  }

  String _buildEventUid({
    required RawInputEvent rawEvent,
    required String occurredAtIso,
    required String? processName,
    required String? windowTitle,
  }) {
    return [
      occurredAtIso,
      rawEvent.sequenceId.toString(),
      rawEvent.kind.value,
      rawEvent.keyCode?.toString() ?? '',
      rawEvent.mouseButton ?? '',
      rawEvent.wheelDelta.toString(),
      rawEvent.deltaX.toString(),
      rawEvent.deltaY.toString(),
      rawEvent.moveDistance.toString(),
      rawEvent.eventCount.toString(),
      processName ?? '',
      windowTitle ?? '',
    ].join('|');
  }

  _WhereParts _buildWhereClause({
    DateTime? start,
    DateTime? end,
    String? processName,
    required bool includeIgnored,
    String tableAlias = '',
  }) {
    final qualifiedPrefix = tableAlias.trim().isEmpty ? '' : '${tableAlias.trim()}.';
    final clauses = <String>[];
    final variables = <Variable>[];

    if (!includeIgnored) {
      clauses.add('${qualifiedPrefix}is_ignored = 0');
    }
    if (start != null) {
      clauses.add('${qualifiedPrefix}occurred_at >= ?');
      variables.add(Variable<String>(start.toIso8601String()));
      clauses.add('${qualifiedPrefix}day_key >= ?');
      variables.add(Variable<String>(_formatDate(start)));
    }
    if (end != null) {
      clauses.add('${qualifiedPrefix}occurred_at < ?');
      variables.add(Variable<String>(end.toIso8601String()));
      final endDay = end.subtract(const Duration(microseconds: 1));
      clauses.add('${qualifiedPrefix}day_key <= ?');
      variables.add(Variable<String>(_formatDate(endDay)));
    }

    final trimmedProcess = processName?.trim();
    if (trimmedProcess != null && trimmedProcess.isNotEmpty) {
      clauses.add('${qualifiedPrefix}process_name = ?');
      variables.add(Variable<String>(trimmedProcess));
    }

    if (clauses.isEmpty) {
      return const _WhereParts(sql: '', variables: <Variable>[]);
    }

    return _WhereParts(
      sql: 'WHERE ${clauses.join(' AND ')}',
      variables: variables,
    );
  }

  static String? _cleanText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static String? _cleanTokenText(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.toLowerCase();
  }

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class _WhereParts {
  final String sql;
  final List<Variable> variables;

  const _WhereParts({
    required this.sql,
    required this.variables,
  });
}

class _InputHeatmapAggregateData {
  final int totalEventCount;
  final int activeMinuteCount;
  final int keyboardEventCount;
  final int mouseButtonEventCount;
  final int wheelEventCount;
  final int mouseMoveEventCount;
  final int mouseMoveDistance;
  final DateTime? firstOccurredAt;
  final DateTime? lastOccurredAt;
  final List<_InputCountAggregateRow> keyCounts;
  final List<_InputStringCountAggregateRow> mouseCounts;
  final List<_InputProcessAggregateRow> processes;
  final List<_InputHourAggregateRow> hours;

  const _InputHeatmapAggregateData({
    required this.totalEventCount,
    required this.activeMinuteCount,
    required this.keyboardEventCount,
    required this.mouseButtonEventCount,
    required this.wheelEventCount,
    required this.mouseMoveEventCount,
    required this.mouseMoveDistance,
    required this.firstOccurredAt,
    required this.lastOccurredAt,
    required this.keyCounts,
    required this.mouseCounts,
    required this.processes,
    required this.hours,
  });

  const _InputHeatmapAggregateData.empty()
      : totalEventCount = 0,
        activeMinuteCount = 0,
        keyboardEventCount = 0,
        mouseButtonEventCount = 0,
        wheelEventCount = 0,
        mouseMoveEventCount = 0,
        mouseMoveDistance = 0,
        firstOccurredAt = null,
        lastOccurredAt = null,
        keyCounts = const <_InputCountAggregateRow>[],
        mouseCounts = const <_InputStringCountAggregateRow>[],
        processes = const <_InputProcessAggregateRow>[],
        hours = const <_InputHourAggregateRow>[];
}

class _InputCountAggregateRow {
  final int key;
  final int count;

  const _InputCountAggregateRow({
    required this.key,
    required this.count,
  });
}

class _InputStringCountAggregateRow {
  final String key;
  final int count;

  const _InputStringCountAggregateRow({
    required this.key,
    required this.count,
  });
}

class _InputProcessAggregateRow {
  final String processName;
  final int totalEvents;
  final int keyEvents;
  final int mouseButtonEvents;
  final int wheelEvents;
  final int mouseMoveEvents;
  final int moveDistance;
  final int activeMinutes;

  const _InputProcessAggregateRow({
    required this.processName,
    required this.totalEvents,
    required this.keyEvents,
    required this.mouseButtonEvents,
    required this.wheelEvents,
    required this.mouseMoveEvents,
    required this.moveDistance,
    required this.activeMinutes,
  });
}

class _InputHourAggregateRow {
  final int hour;
  final int totalEvents;
  final int keyEvents;
  final int mouseButtonEvents;
  final int wheelEvents;
  final int mouseMoveEvents;
  final int moveDistance;
  final int activeMinutes;

  const _InputHourAggregateRow({
    required this.hour,
    required this.totalEvents,
    required this.keyEvents,
    required this.mouseButtonEvents,
    required this.wheelEvents,
    required this.mouseMoveEvents,
    required this.moveDistance,
    required this.activeMinutes,
  });
}

InputHeatmapSummary _buildInputHeatmapSummary({
  required InputEventQuery query,
  required _InputHeatmapAggregateData data,
}) {
  final keyCounts = <int, int>{
    for (final row in data.keyCounts) row.key: row.count,
  };
  final mouseCounts = <String, int>{
    for (final row in data.mouseCounts) row.key: row.count,
  };

  final topKeys = data.keyCounts
      .map(
        (row) => InputKeyStat(
          keyCode: row.key,
          label: inputKeyLabelForCode(row.key),
          count: row.count,
          share: data.keyboardEventCount <= 0
              ? 0
              : row.count / data.keyboardEventCount,
        ),
      )
      .toList(growable: false)
    ..sort((left, right) {
      final byCount = right.count.compareTo(left.count);
      if (byCount != 0) {
        return byCount;
      }
      return left.label.compareTo(right.label);
    });

  final processIntensities = data.processes
      .map(
        (row) => InputProcessIntensity(
          processName: row.processName,
          totalEvents: row.totalEvents,
          keyEvents: row.keyEvents,
          mouseButtonEvents: row.mouseButtonEvents,
          wheelEvents: row.wheelEvents,
          mouseMoveEvents: row.mouseMoveEvents,
          moveDistance: row.moveDistance,
          activeMinutes: row.activeMinutes,
          intensityScore: _calculateInputIntensityScore(
            keyEvents: row.keyEvents,
            mouseButtonEvents: row.mouseButtonEvents,
            wheelEvents: row.wheelEvents,
            moveDistance: row.moveDistance,
          ),
        ),
      )
      .toList(growable: false)
    ..sort((left, right) {
      final byScore = right.intensityScore.compareTo(left.intensityScore);
      if (byScore != 0) {
        return byScore;
      }
      return right.totalEvents.compareTo(left.totalEvents);
    });

  final hourlyDistribution = List<InputHourDistributionBucket>.generate(
    24,
    (hour) => InputHourDistributionBucket(
      hour: hour,
      totalEvents: 0,
      keyEvents: 0,
      mouseButtonEvents: 0,
      wheelEvents: 0,
      mouseMoveEvents: 0,
      moveDistance: 0,
      activeMinutes: 0,
      intensityScore: 0,
    ),
  );
  for (final row in data.hours) {
    if (row.hour < 0 || row.hour >= hourlyDistribution.length) {
      continue;
    }
    hourlyDistribution[row.hour] = InputHourDistributionBucket(
      hour: row.hour,
      totalEvents: row.totalEvents,
      keyEvents: row.keyEvents,
      mouseButtonEvents: row.mouseButtonEvents,
      wheelEvents: row.wheelEvents,
      mouseMoveEvents: row.mouseMoveEvents,
      moveDistance: row.moveDistance,
      activeMinutes: row.activeMinutes,
      intensityScore: _calculateInputIntensityScore(
        keyEvents: row.keyEvents,
        mouseButtonEvents: row.mouseButtonEvents,
        wheelEvents: row.wheelEvents,
        moveDistance: row.moveDistance,
      ),
    );
  }

  return InputHeatmapSummary(
    query: query,
    totalEventCount: data.totalEventCount,
    activeMinuteCount: data.activeMinuteCount,
    keyboardEventCount: data.keyboardEventCount,
    mouseButtonEventCount: data.mouseButtonEventCount,
    wheelEventCount: data.wheelEventCount,
    mouseMoveEventCount: data.mouseMoveEventCount,
    mouseMoveDistance: data.mouseMoveDistance,
    keyCounts: keyCounts,
    mouseCounts: mouseCounts,
    topKeys: topKeys,
    processIntensities: processIntensities,
    hourlyDistribution: hourlyDistribution,
  );
}

int _calculateInputIntensityScore({
  required int keyEvents,
  required int mouseButtonEvents,
  required int wheelEvents,
  required int moveDistance,
}) {
  return (keyEvents * 5) +
      (mouseButtonEvents * 4) +
      (wheelEvents * 3) +
      (moveDistance ~/ 160);
}
