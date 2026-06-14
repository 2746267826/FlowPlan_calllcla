import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/storage/app_storage.dart';
import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/features/tracker/services/activity_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  String dayKey(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  ActivityLogEntry entry({
    required DateTime at,
    ActivityLogEntryType type = ActivityLogEntryType.sample,
    int? recordId,
    bool isIgnored = false,
    String? processName = 'Code.exe',
    String? windowTitle = 'main.dart',
    String? category = 'coding',
    String? label = 'Implementation',
    int? durationMinutes = 15,
    int keyCount = 8,
    int mouseClicks = 2,
    int mouseMovePx = 120,
    int scrollPx = 40,
    String? note,
  }) {
    return ActivityLogEntry(
      timestamp: at,
      type: type,
      recordId: recordId,
      isIgnored: isIgnored,
      processName: processName,
      windowTitle: windowTitle,
      category: category,
      label: label,
      durationMinutes: durationMinutes,
      keyCount: keyCount,
      mouseClicks: mouseClicks,
      mouseMovePx: mouseMovePx,
      scrollPx: scrollPx,
      keyDistribution: const <int, int>{65: 4, 66: 2},
      keySequence: 'AB',
      deviceId: 'device-test',
      platform: 'windows',
      source: 'test',
      note: note,
    );
  }

  Future<void> insertRawActivityLogRow(
    AppDatabase db, {
    required String entryUid,
    required DateTime at,
    required String payloadJson,
    ActivityLogEntryType type = ActivityLogEntryType.sample,
    int? recordId,
    bool isIgnored = false,
    String? processName = 'Code.exe',
    String? windowTitle = 'main.dart',
    String? category = 'coding',
    String? label = 'Implementation',
  }) async {
    await db.customStatement(
      '''
      INSERT INTO raw_activity_logs (
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
      <Object?>[
        entryUid,
        at.toIso8601String(),
        dayKey(at),
        type.value,
        recordId,
        processName,
        windowTitle,
        category,
        label,
        isIgnored ? 1 : 0,
        payloadJson,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  group('ActivityLogService', () {
    test('empty storage returns empty query and archive results', () async {
      await setUpTempAppStorage();
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = ActivityLogService(db);
      final day = DateTime(2026, 6, 9);

      expect(await service.readEntriesForDate(day), isEmpty);
      expect(
        await service.readEntriesBetween(
          day,
          day.add(const Duration(days: 1)),
        ),
        isEmpty,
      );
      expect(await service.readEntriesPage(), isEmpty);
      expect(await service.readArchivedEntriesForDate(day), isEmpty);
      expect(await service.listArchiveDays(), isEmpty);
    });

    test('append persists database rows and daily jsonl archive export',
        () async {
      final storage = await setUpTempAppStorage();
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = ActivityLogService(db);
      final base = DateTime(2026, 6, 9, 9);
      final first = entry(
        at: base,
        type: ActivityLogEntryType.sessionOpen,
        recordId: 101,
        note: 'started',
      );
      final second = entry(
        at: base.add(const Duration(minutes: 20)),
        type: ActivityLogEntryType.sessionUpdate,
        recordId: 101,
        durationMinutes: 20,
        keyCount: 16,
        note: 'updated',
      );

      await service.append(second);
      await service.append(first);

      final databaseEntries = await service.readEntriesForDate(base);
      expect(databaseEntries.map((item) => item.note), <String?>[
        'started',
        'updated',
      ]);
      expect(databaseEntries.first.recordId, 101);
      expect(
        databaseEntries.last.keyDistribution,
        const <int, int>{65: 4, 66: 2},
      );

      final archiveDirectoryPath = await service.getArchiveDirectoryPath();
      expect(archiveDirectoryPath, startsWith(storage.path));
      final archiveFile = File(
        '$archiveDirectoryPath${Platform.pathSeparator}2026-06-09.activity.jsonl',
      );
      expect(await archiveFile.exists(), isTrue);

      final exportedLines = await archiveFile.readAsLines();
      expect(exportedLines, hasLength(2));
      expect(jsonDecode(exportedLines.first), containsPair('note', 'updated'));
      expect(jsonDecode(exportedLines.last), containsPair('note', 'started'));

      final archiveDays = await service.listArchiveDays();
      expect(archiveDays.single.dayKey, '2026-06-09');
      expect(archiveDays.single.filePath, archiveFile.path);
      expect(archiveDays.single.fileSizeBytes, greaterThan(0));
    });

    test('range queries clamp pagination and skip malformed payload rows',
        () async {
      await setUpTempAppStorage();
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = ActivityLogService(db);
      final base = DateTime(2026, 6, 10, 10);

      await insertRawActivityLogRow(
        db,
        entryUid: 'before',
        at: base.subtract(const Duration(minutes: 1)),
        payloadJson:
            entry(at: base.subtract(const Duration(minutes: 1))).toJsonLine(),
      );
      await insertRawActivityLogRow(
        db,
        entryUid: 'first',
        at: base,
        payloadJson: entry(at: base, note: 'first').toJsonLine(),
      );
      await insertRawActivityLogRow(
        db,
        entryUid: 'bad-json',
        at: base.add(const Duration(minutes: 1)),
        payloadJson: '{not-json',
      );
      await insertRawActivityLogRow(
        db,
        entryUid: 'second',
        at: base.add(const Duration(minutes: 2)),
        payloadJson: entry(
          at: base.add(const Duration(minutes: 2)),
          note: 'second',
        ).toJsonLine(),
      );
      await insertRawActivityLogRow(
        db,
        entryUid: 'end-exclusive',
        at: base.add(const Duration(minutes: 4)),
        payloadJson: entry(
          at: base.add(const Duration(minutes: 4)),
          note: 'end',
        ).toJsonLine(),
      );

      final clamped = await service.readEntriesBetween(
        base.subtract(const Duration(minutes: 5)),
        base.add(const Duration(minutes: 5)),
        limit: 0,
        offset: -10,
      );
      expect(clamped.single.note, isNull);

      final paged = await service.readEntriesBetween(
        base,
        base.add(const Duration(minutes: 4)),
        limit: 10,
        offset: 1,
      );
      expect(paged.map((item) => item.note), <String?>['second']);
    });

    test('readEntriesPage filters type process category ignored and offset',
        () async {
      await setUpTempAppStorage();
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = ActivityLogService(db);
      final base = DateTime(2026, 6, 11, 8);

      Future<void> insert(
        String uid,
        DateTime at,
        ActivityLogEntry item, {
        ActivityLogEntryType type = ActivityLogEntryType.sample,
        bool isIgnored = false,
        String? processName = 'Code.exe',
        String? category = 'coding',
      }) {
        return insertRawActivityLogRow(
          db,
          entryUid: uid,
          at: at,
          payloadJson: item.toJsonLine(),
          type: type,
          isIgnored: isIgnored,
          processName: processName,
          category: category,
        );
      }

      await insert(
        'old-visible',
        base,
        entry(at: base, type: ActivityLogEntryType.snapshot, note: 'old'),
        type: ActivityLogEntryType.snapshot,
      );
      await insert(
        'new-visible',
        base.add(const Duration(minutes: 1)),
        entry(
          at: base.add(const Duration(minutes: 1)),
          type: ActivityLogEntryType.snapshot,
          note: 'new',
        ),
        type: ActivityLogEntryType.snapshot,
      );
      await insert(
        'ignored-visible-when-requested',
        base.add(const Duration(minutes: 2)),
        entry(
          at: base.add(const Duration(minutes: 2)),
          type: ActivityLogEntryType.snapshot,
          isIgnored: true,
          note: 'ignored',
        ),
        type: ActivityLogEntryType.snapshot,
        isIgnored: true,
      );
      await insert(
        'wrong-process',
        base.add(const Duration(minutes: 3)),
        entry(
          at: base.add(const Duration(minutes: 3)),
          type: ActivityLogEntryType.snapshot,
          processName: 'Chrome.exe',
          category: 'browser',
          note: 'wrong-process',
        ),
        type: ActivityLogEntryType.snapshot,
        processName: 'Chrome.exe',
        category: 'browser',
      );
      await insert(
        'wrong-type',
        base.add(const Duration(minutes: 4)),
        entry(
          at: base.add(const Duration(minutes: 4)),
          type: ActivityLogEntryType.sample,
          note: 'wrong-type',
        ),
      );

      final visible = await service.readEntriesPage(
        start: base,
        end: base.add(const Duration(minutes: 5)),
        entryType: ' snapshot ',
        processName: ' Code.exe ',
        category: ' coding ',
        limit: 10,
      );
      expect(visible.map((item) => item.note), <String?>['new', 'old']);

      final includeIgnored = await service.readEntriesPage(
        start: base,
        end: base.add(const Duration(minutes: 5)),
        entryType: 'snapshot',
        processName: 'Code.exe',
        category: 'coding',
        includeIgnored: true,
        limit: 2,
        offset: 1,
      );
      expect(includeIgnored.map((item) => item.note), <String?>['new', 'old']);
    });

    test('missing and malformed archives fall back to usable entries',
        () async {
      await setUpTempAppStorage();
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = ActivityLogService(db);
      final base = DateTime(2026, 6, 12, 12);
      final first = entry(at: base, note: 'first');
      final second = entry(
        at: base.add(const Duration(minutes: 5)),
        note: 'second',
      );

      await service.append(first);
      await service.append(second);
      final archiveDirectoryPath = await service.getArchiveDirectoryPath();
      final archiveFile = File(
        '$archiveDirectoryPath${Platform.pathSeparator}2026-06-12.activity.jsonl',
      );
      expect(await archiveFile.exists(), isTrue);

      await archiveFile.delete();
      final restored = await service.readArchivedEntriesForDate(base);
      expect(restored.map((item) => item.note), <String?>['first', 'second']);
      expect(await archiveFile.exists(), isTrue);

      await archiveFile.writeAsString(
        'not-json\n${first.toJsonLine()}\n\n[]\n${second.toJsonLine()}\n',
        flush: true,
      );
      final sanitized = await service.readArchivedEntriesForDate(base);
      expect(sanitized.map((item) => item.note), <String?>['first', 'second']);
    });

    test('malformed legacy archive does not block fresh append fallback',
        () async {
      await setUpTempAppStorage();
      final appStorageDirectory = await resolveAppStorageDirectory();
      final logsDirectory = Directory(
        '${appStorageDirectory.path}${Platform.pathSeparator}logs',
      );
      await logsDirectory.create(recursive: true);
      final base = DateTime(2026, 6, 13, 10);
      final legacyArchive = File(
        '${logsDirectory.path}${Platform.pathSeparator}2026-06-13.activity.jsonl',
      );
      await legacyArchive.writeAsString('not-json\n\n', flush: true);

      final db = createTestDatabase();
      addTearDown(db.close);
      final service = ActivityLogService(db);
      final fresh = entry(at: base, note: 'fresh');

      await service.append(fresh);

      final databaseEntries = await service.readEntriesForDate(base);
      expect(databaseEntries.map((item) => item.note), <String?>['fresh']);

      final archivedEntries = await service.readArchivedEntriesForDate(base);
      expect(archivedEntries.map((item) => item.note), <String?>['fresh']);
      expect(await legacyArchive.readAsLines(), hasLength(3));
    });

    test('valid legacy archive entries migrate into the database', () async {
      await setUpTempAppStorage();
      final appStorageDirectory = await resolveAppStorageDirectory();
      final logsDirectory = Directory(
        '${appStorageDirectory.path}${Platform.pathSeparator}logs',
      );
      await logsDirectory.create(recursive: true);
      final base = DateTime(2026, 6, 14, 9);
      final legacyArchive = File(
        '${logsDirectory.path}${Platform.pathSeparator}2026-06-14.activity.jsonl',
      );
      await legacyArchive.writeAsString(
        '${entry(at: base, note: 'legacy-migrated').toJsonLine()}\n'
        'not-json\n',
        flush: true,
      );

      final db = createTestDatabase();
      addTearDown(db.close);
      final service = ActivityLogService(db);

      final migrated = await service.readEntriesForDate(base);

      expect(migrated.map((item) => item.note), <String?>[
        'legacy-migrated',
      ]);
    });

    test('testing helper parses malformed day key as epoch fallback', () {
      final parsed = ActivityLogService.debugParseDayKeyForTesting('not-a-day');
      final missingParts =
          ActivityLogService.debugParseDayKeyForTesting('notaday');

      expect(parsed.year, 1970);
      expect(parsed.month, 1);
      expect(parsed.day, 1);
      expect(missingParts, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });
}
