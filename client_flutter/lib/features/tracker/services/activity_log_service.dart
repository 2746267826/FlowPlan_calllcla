import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../../../core/storage/app_storage.dart';
import '../models/activity_log_archive_day.dart';
import '../models/activity_log_entry.dart';

class ActivityLogService {
  ActivityLogService(this._database);

  final AppDatabase _database;

  static const _legacyMigrationSettingKey =
      'tracker.legacy_jsonl_to_database_migrated';
  static const _dailyArchiveBackfillSettingKey =
      'tracker.database_to_daily_jsonl_backfilled';

  Future<void>? _initializationFuture;

  Future<String> getStoragePath() async {
    return _database.getDatabasePath();
  }

  Future<String> getArchiveDirectoryPath() async {
    final directory = await _resolveLogDirectory();
    return directory.path;
  }

  Future<void> append(ActivityLogEntry entry) async {
    await _ensureInitialized();
    await _insertEntry(entry);
    await _appendToDailyArchive(entry);
  }

  Future<List<ActivityLogEntry>> readEntriesForDate(DateTime date) async {
    await _ensureInitialized();
    return _readEntriesForDayKey(_formatDate(date));
  }

  Future<List<ActivityLogEntry>> readArchivedEntriesForDate(
      DateTime date) async {
    await _ensureInitialized();
    final file = await _resolveDailyArchiveFile(date);
    if (!await file.exists()) {
      final databaseEntries = await _readEntriesForDayKey(_formatDate(date));
      if (databaseEntries.isNotEmpty) {
        await _writeArchiveFile(file, databaseEntries);
      }
      return databaseEntries;
    }

    return _readEntriesFromFile(file);
  }

  Future<List<ActivityLogArchiveDay>> listArchiveDays() async {
    await _ensureInitialized();
    var days = await _scanArchiveDays();
    if (days.isEmpty) {
      await _materializeArchiveFilesFromDatabase();
      days = await _scanArchiveDays();
    }
    return days;
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
        .where((file) =>
            _tryParseDayKeyFromFileName(p.basename(file.path)) != null)
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

  Future<List<ActivityLogEntry>> _readEntriesForDayKey(String dayKey) async {
    final rows = await _database.customSelect(
      '''
      SELECT payload_json
      FROM raw_activity_logs
      WHERE day_key = ?
      ORDER BY occurred_at ASC, id ASC
      ''',
      variables: [Variable<String>(dayKey)],
    ).get();

    final entries = <ActivityLogEntry>[];
    for (final row in rows) {
      final payload = row.read<String>('payload_json');
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          entries.add(
            ActivityLogEntry.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {
        // Ignore malformed rows so one damaged record doesn't block the page.
      }
    }
    return entries;
  }

  Future<List<ActivityLogEntry>> readEntriesBetween(
    DateTime start,
    DateTime end, {
    int limit = 200,
    int offset = 0,
  }) async {
    await _ensureInitialized();
    final normalizedLimit = limit.clamp(1, 1000).toInt();
    final normalizedOffset = offset < 0 ? 0 : offset;
    final rows = await _database.customSelect(
      '''
      SELECT payload_json
      FROM raw_activity_logs
      WHERE occurred_at >= ? AND occurred_at < ?
      ORDER BY occurred_at ASC, id ASC
      LIMIT ? OFFSET ?
      ''',
      variables: [
        Variable<String>(start.toIso8601String()),
        Variable<String>(end.toIso8601String()),
        Variable<int>(normalizedLimit),
        Variable<int>(normalizedOffset),
      ],
    ).get();

    return _decodeEntryRows(rows);
  }

  Future<List<ActivityLogEntry>> readEntriesPage({
    DateTime? start,
    DateTime? end,
    String? entryType,
    String? processName,
    String? category,
    bool includeIgnored = false,
    int limit = 200,
    int offset = 0,
  }) async {
    await _ensureInitialized();
    final clauses = <String>[];
    final variables = <Variable>[];
    if (!includeIgnored) {
      clauses.add('is_ignored = 0');
    }
    if (start != null) {
      clauses.add('occurred_at >= ?');
      variables.add(Variable<String>(start.toIso8601String()));
    }
    if (end != null) {
      clauses.add('occurred_at < ?');
      variables.add(Variable<String>(end.toIso8601String()));
    }
    final trimmedType = entryType?.trim();
    if (trimmedType != null && trimmedType.isNotEmpty) {
      clauses.add('entry_type = ?');
      variables.add(Variable<String>(trimmedType));
    }
    final trimmedProcess = processName?.trim();
    if (trimmedProcess != null && trimmedProcess.isNotEmpty) {
      clauses.add('process_name = ?');
      variables.add(Variable<String>(trimmedProcess));
    }
    final trimmedCategory = category?.trim();
    if (trimmedCategory != null && trimmedCategory.isNotEmpty) {
      clauses.add('category = ?');
      variables.add(Variable<String>(trimmedCategory));
    }

    final normalizedLimit = limit.clamp(1, 1000).toInt();
    final normalizedOffset = offset < 0 ? 0 : offset;
    final whereSql = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = await _database.customSelect(
      '''
      SELECT payload_json
      FROM raw_activity_logs
      $whereSql
      ORDER BY occurred_at DESC, id DESC
      LIMIT ? OFFSET ?
      ''',
      variables: [
        ...variables,
        Variable<int>(normalizedLimit),
        Variable<int>(normalizedOffset),
      ],
    ).get();

    return _decodeEntryRows(rows);
  }

  List<ActivityLogEntry> _decodeEntryRows(List<QueryRow> rows) {
    final entries = <ActivityLogEntry>[];
    for (final row in rows) {
      final payload = row.read<String>('payload_json');
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          entries.add(
            ActivityLogEntry.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {
        // Ignore malformed rows so one damaged record doesn't block the page.
      }
    }
    return entries;
  }

  Future<void> _ensureInitialized() async {
    _initializationFuture ??= _initialize();
    await _initializationFuture;
  }

  Future<void> _initialize() async {
    try {
      final migrated = await _database.getBoolSetting(
        _legacyMigrationSettingKey,
        defaultValue: false,
      );
      if (!migrated) {
        final legacyDirectory = await _resolveLogDirectory();
        if (!await legacyDirectory.exists()) {
          await _database.setBoolSetting(_legacyMigrationSettingKey, true);
        } else {
          final files = await legacyDirectory
              .list()
              .where((entity) => entity is File)
              .cast<File>()
              .where((file) => file.path.endsWith('.activity.jsonl'))
              .toList();
          files.sort((left, right) => left.path.compareTo(right.path));

          for (final file in files) {
            try {
              final lines = await file.readAsLines();
              for (final line in lines) {
                final entry = ActivityLogEntry.tryParseLine(line);
                if (entry == null) {
                  continue;
                }
                await _insertEntry(entry);
              }
            } catch (_) {
              // Skip damaged legacy files and keep the new database pipeline alive.
            }
          }

          await _database.setBoolSetting(_legacyMigrationSettingKey, true);
        }
      }

      await _ensureDailyArchiveBackfill();
    } catch (_) {
      // Migration is best-effort; fresh records should still be able to land in
      // the database even if old files fail to import.
    }
  }

  Future<void> _insertEntry(ActivityLogEntry entry) async {
    final payload = jsonEncode(entry.toJson());
    final timestampIso = entry.timestamp.toIso8601String();
    await _database.customStatement(
      '''
      INSERT OR IGNORE INTO raw_activity_logs (
        entry_uid,
        occurred_at,
        day_key,
        entry_type,
        record_id,
        process_name,
        window_title,
        category,
        label,
        is_ignored,
        payload_json,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _buildEntryUid(entry),
        timestampIso,
        _formatDate(entry.timestamp),
        entry.type.value,
        entry.recordId,
        entry.processName,
        entry.windowTitle,
        entry.category,
        entry.label,
        entry.isIgnored ? 1 : 0,
        payload,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  Future<void> _appendToDailyArchive(ActivityLogEntry entry) async {
    final file = await _resolveDailyArchiveFile(entry.timestamp);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${entry.toJsonLine()}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<List<ActivityLogEntry>> _readEntriesFromFile(File file) async {
    final lines = await file.readAsLines();
    final entries = <ActivityLogEntry>[];
    for (final line in lines) {
      final entry = ActivityLogEntry.tryParseLine(line);
      if (entry != null) {
        entries.add(entry);
      }
    }
    return entries;
  }

  Future<void> _writeArchiveFile(
    File file,
    List<ActivityLogEntry> entries,
  ) async {
    if (entries.isEmpty) {
      return;
    }

    await file.parent.create(recursive: true);
    final contents = entries.map((entry) => entry.toJsonLine()).join('\n');
    await file.writeAsString('$contents\n', flush: true);
  }

  Future<void> _ensureDailyArchiveBackfill() async {
    try {
      final migrated = await _database.getBoolSetting(
        _dailyArchiveBackfillSettingKey,
        defaultValue: false,
      );
      if (migrated) {
        return;
      }

      await _materializeArchiveFilesFromDatabase();

      await _database.setBoolSetting(_dailyArchiveBackfillSettingKey, true);
    } catch (_) {
      // Best-effort backfill: current writes should continue even if historical
      // archive materialization fails.
    }
  }

  Future<void> _materializeArchiveFilesFromDatabase() async {
    final rows = await _database.customSelect(
      '''
      SELECT day_key
      FROM raw_activity_logs
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

      final entries = await _readEntriesForDayKey(dayKey);
      await _writeArchiveFile(file, entries);
    }
  }

  Future<Directory> _resolveLogDirectory() async {
    final root = await resolveAppStorageDirectory();
    return Directory('${root.path}${Platform.pathSeparator}logs');
  }

  Future<File> _resolveDailyArchiveFile(DateTime date) {
    return _resolveDailyArchiveFileForDayKey(_formatDate(date));
  }

  Future<File> _resolveDailyArchiveFileForDayKey(String dayKey) async {
    final directory = await _resolveLogDirectory();
    return File(p.join(directory.path, '$dayKey.activity.jsonl'));
  }

  String _buildEntryUid(ActivityLogEntry entry) {
    final buffer = StringBuffer()
      ..write(entry.timestamp.toIso8601String())
      ..write('|')
      ..write(entry.type.value)
      ..write('|')
      ..write(entry.recordId ?? '')
      ..write('|')
      ..write(entry.isIgnored ? '1' : '0')
      ..write('|')
      ..write(entry.isFullscreen ? '1' : '0')
      ..write('|')
      ..write(entry.processName ?? '')
      ..write('|')
      ..write(entry.packageName ?? '')
      ..write('|')
      ..write(entry.className ?? '')
      ..write('|')
      ..write(entry.windowTitle ?? '')
      ..write('|')
      ..write(entry.appLabel ?? '')
      ..write('|')
      ..write(entry.category ?? '')
      ..write('|')
      ..write(entry.label ?? '')
      ..write('|')
      ..write(entry.durationMinutes ?? '')
      ..write('|')
      ..write(entry.keyCount)
      ..write('|')
      ..write(entry.mouseClicks)
      ..write('|')
      ..write(entry.mouseMovePx)
      ..write('|')
      ..write(entry.scrollPx)
      ..write('|')
      ..write(entry.keySequence ?? '')
      ..write('|')
      ..write(entry.deviceId ?? '')
      ..write('|')
      ..write(entry.platform ?? '')
      ..write('|')
      ..write(entry.source ?? '')
      ..write('|')
      ..write(entry.note ?? '');

    final sortedKeys = entry.keyDistribution.keys.toList()..sort();
    for (final key in sortedKeys) {
      buffer
        ..write('|')
        ..write(key)
        ..write(':')
        ..write(entry.keyDistribution[key] ?? 0);
    }
    return buffer.toString();
  }

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String? _tryParseDayKeyFromFileName(String fileName) {
    final match =
        RegExp(r'^(\d{4}-\d{2}-\d{2})\.activity\.jsonl$').firstMatch(fileName);
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

  static DateTime debugParseDayKeyForTesting(String dayKey) {
    return _parseDayKey(dayKey);
  }
}
