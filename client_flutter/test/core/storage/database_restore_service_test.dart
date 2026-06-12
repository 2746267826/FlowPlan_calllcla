import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/core/storage/app_storage.dart';
import 'package:flowplanv2/core/storage/database_restore_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../test_support/temp_app_storage.dart';

void main() {
  group('DatabaseRestoreService', () {
    test('stageRestore rejects a missing database without staging files',
        () async {
      final tempRoot = await setUpTempAppStorage(
        prefix: 'database-restore-missing-',
      );
      final service = const DatabaseRestoreService();
      final missingFile = File(p.join(tempRoot.path, 'missing.db'));

      await expectLater(
        service.stageRestore(missingFile.path),
        throwsA(isA<StateError>()),
      );

      expect(await (await resolvePendingDatabaseRestoreFile()).exists(), false);
      expect(
        await (await resolvePendingDatabaseRestoreMetadataFile()).exists(),
        false,
      );
    });

    test('stageRestore validates the complete SQLite header before staging',
        () async {
      final tempRoot = await setUpTempAppStorage(
        prefix: 'database-restore-short-header-',
      );
      final service = const DatabaseRestoreService();
      final shortHeaderFile = File(p.join(tempRoot.path, 'short.db'));
      await shortHeaderFile.writeAsString('SQLite format 3');

      await expectLater(
        service.stageRestore(shortHeaderFile.path),
        throwsA(isA<StateError>()),
      );

      expect(await (await resolvePendingDatabaseRestoreFile()).exists(), false);
      expect(
        await (await resolvePendingDatabaseRestoreMetadataFile()).exists(),
        false,
      );
    });

    test('stageRestore rejects a non-SQLite file and leaves no pending restore',
        () async {
      final tempRoot = await setUpTempAppStorage(
        prefix: 'database-restore-invalid-',
      );
      final service = const DatabaseRestoreService();
      final invalidFile = File(p.join(tempRoot.path, 'notes.txt'));
      await invalidFile.writeAsString('not a sqlite database backup');

      await expectLater(
        service.stageRestore(invalidFile.path),
        throwsA(isA<StateError>()),
      );

      expect(await (await resolvePendingDatabaseRestoreFile()).exists(), false);
      expect(
        await (await resolvePendingDatabaseRestoreMetadataFile()).exists(),
        false,
      );
    });

    test('stageRestore copies a valid SQLite database and writes metadata',
        () async {
      final tempRoot = await setUpTempAppStorage(
        prefix: 'database-restore-valid-stage-',
      );
      final service = const DatabaseRestoreService();
      final sourceFile = File(p.join(tempRoot.path, 'backup.db'));
      await _writeSqliteLikeDatabase(sourceFile, marker: 'source-backup');
      final sourceBytes = await sourceFile.readAsBytes();

      final preparation = await service.stageRestore(sourceFile.path);

      final stagedFile = await resolvePendingDatabaseRestoreFile();
      final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
      expect(preparation.sourcePath, sourceFile.path);
      expect(preparation.stagedPath, stagedFile.path);
      expect(await stagedFile.readAsBytes(), sourceBytes);

      final metadata =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      expect(metadata['sourcePath'], sourceFile.path);
      expect(metadata['stagedPath'], stagedFile.path);
      expect(DateTime.tryParse(metadata['stagedAt'] as String), isNotNull);

      final pendingRestore = await service.getPendingRestore();
      expect(pendingRestore, isNotNull);
      expect(pendingRestore!.sourcePath, sourceFile.path);
      expect(pendingRestore.stagedPath, stagedFile.path);
      expect(pendingRestore.stagedAt, isA<DateTime>());
    });

    test('applyPendingRestoreIfNeeded skips and removes stale metadata',
        () async {
      await setUpTempAppStorage(prefix: 'database-restore-skip-');
      final service = const DatabaseRestoreService();
      final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
      await metadataFile.parent.create(recursive: true);
      await metadataFile.writeAsString('{"stale":true}');

      final result = await service.applyPendingRestoreIfNeeded();

      expect(result.applied, false);
      expect(result.previousDatabaseBackupPath, isNull);
      expect(result.restoredDatabasePath, isNull);
      expect(await metadataFile.exists(), false);
    });

    test(
        'getPendingRestore falls back to staged file when metadata is malformed',
        () async {
      await setUpTempAppStorage(prefix: 'database-restore-pending-fallback-');
      final service = const DatabaseRestoreService();
      final stagedFile = await resolvePendingDatabaseRestoreFile();
      final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
      await _writeSqliteLikeDatabase(stagedFile, marker: 'pending-db');
      await metadataFile.writeAsString('[not-a-metadata-map]');

      final pendingRestore = await service.getPendingRestore();

      expect(pendingRestore, isNotNull);
      expect(pendingRestore!.sourcePath, stagedFile.path);
      expect(pendingRestore.stagedPath, stagedFile.path);
      expect(pendingRestore.stagedAt, isA<DateTime>());
      expect(await metadataFile.exists(), false);
      expect(await stagedFile.exists(), true);
    });

    test('clearPendingRestore cancels a staged restore and metadata', () async {
      await setUpTempAppStorage(prefix: 'database-restore-clear-');
      final service = const DatabaseRestoreService();
      final stagedFile = await resolvePendingDatabaseRestoreFile();
      final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
      await _writeSqliteLikeDatabase(stagedFile, marker: 'pending-db');
      await metadataFile.writeAsString('{"sourcePath":"backup.db"}');

      await service.clearPendingRestore();

      expect(await stagedFile.exists(), false);
      expect(await metadataFile.exists(), false);
      expect(await service.getPendingRestore(), isNull);
    });

    test('applyPendingRestoreIfNeeded discards invalid staged databases',
        () async {
      await setUpTempAppStorage(prefix: 'database-restore-invalid-apply-');
      final service = const DatabaseRestoreService();
      final stagedFile = await resolvePendingDatabaseRestoreFile();
      final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
      await stagedFile.parent.create(recursive: true);
      await stagedFile.writeAsString('this is not sqlite');
      await metadataFile.writeAsString('{"sourcePath":"broken.db"}');

      final result = await service.applyPendingRestoreIfNeeded();

      expect(result.applied, false);
      expect(await stagedFile.exists(), false);
      expect(await metadataFile.exists(), false);
    });

    test('applyPendingRestoreIfNeeded restores when no current database exists',
        () async {
      await setUpTempAppStorage(prefix: 'database-restore-apply-fresh-');
      final service = const DatabaseRestoreService();
      final databaseFile = await resolvePrimaryDatabaseFile();
      final stagedFile = await resolvePendingDatabaseRestoreFile();
      final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
      final backupFile = await resolvePreRestoreDatabaseBackupFile();
      await _writeSqliteLikeDatabase(stagedFile, marker: 'fresh-restore');
      final restoredBytes = await stagedFile.readAsBytes();
      await metadataFile.writeAsString('{"sourcePath":"fresh-backup.db"}');

      final result = await service.applyPendingRestoreIfNeeded();

      expect(result.applied, true);
      expect(result.previousDatabaseBackupPath, isNull);
      expect(result.restoredDatabasePath, databaseFile.path);
      expect(await databaseFile.readAsBytes(), restoredBytes);
      expect(await backupFile.exists(), false);
      expect(await stagedFile.exists(), false);
      expect(await metadataFile.exists(), false);
    });

    test(
      'applyPendingRestoreIfNeeded backs up the current database and removes sidecars',
      () async {
        await setUpTempAppStorage(prefix: 'database-restore-apply-');
        final service = const DatabaseRestoreService();
        final databaseFile = await resolvePrimaryDatabaseFile();
        final stagedFile = await resolvePendingDatabaseRestoreFile();
        final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
        final backupFile = await resolvePreRestoreDatabaseBackupFile();
        final walFile = File('${databaseFile.path}-wal');
        final shmFile = File('${databaseFile.path}-shm');

        await _writeSqliteLikeDatabase(databaseFile, marker: 'existing-db');
        final existingBytes = await databaseFile.readAsBytes();
        await _writeSqliteLikeDatabase(stagedFile, marker: 'restored-db');
        final restoredBytes = await stagedFile.readAsBytes();
        await _writeSqliteLikeDatabase(backupFile, marker: 'stale-backup');
        await walFile.writeAsString('wal sidecar');
        await shmFile.writeAsString('shm sidecar');
        await metadataFile.writeAsString('{"sourcePath":"backup.db"}');

        final result = await service.applyPendingRestoreIfNeeded();

        expect(result.applied, true);
        expect(result.previousDatabaseBackupPath, backupFile.path);
        expect(result.restoredDatabasePath, databaseFile.path);
        expect(await databaseFile.readAsBytes(), restoredBytes);
        expect(await backupFile.readAsBytes(), existingBytes);
        expect(await stagedFile.exists(), false);
        expect(await metadataFile.exists(), false);
        expect(await walFile.exists(), false);
        expect(await shmFile.exists(), false);

        final noticeFile = await resolveDatabaseRestoreNoticeFile();
        final notice =
            jsonDecode(await noticeFile.readAsString()) as Map<String, dynamic>;
        expect(DateTime.tryParse(notice['restoredAt'] as String), isNotNull);
        expect(notice['previousDatabaseBackupPath'], backupFile.path);
        expect(notice['restoredDatabasePath'], databaseFile.path);
      },
    );

    test('consumeRestoreNotice deletes invalid JSON and returns null',
        () async {
      await setUpTempAppStorage(prefix: 'database-restore-notice-invalid-');
      final service = const DatabaseRestoreService();
      final noticeFile = await resolveDatabaseRestoreNoticeFile();
      await noticeFile.parent.create(recursive: true);
      await noticeFile.writeAsString('{not valid json');

      final notice = await service.consumeRestoreNotice();

      expect(notice, isNull);
      expect(await noticeFile.exists(), false);
    });

    test('consumeRestoreNotice returns a notice and consumes the file',
        () async {
      await setUpTempAppStorage(prefix: 'database-restore-notice-valid-');
      final service = const DatabaseRestoreService();
      final noticeFile = await resolveDatabaseRestoreNoticeFile();
      final restoredAt = DateTime.utc(2026, 6, 10, 1, 2, 3);
      await noticeFile.parent.create(recursive: true);
      await noticeFile.writeAsString(
        jsonEncode(<String, Object?>{
          'restoredAt': restoredAt.toIso8601String(),
          'previousDatabaseBackupPath': 'before.db',
          'restoredDatabasePath': 'restored.db',
        }),
      );

      final notice = await service.consumeRestoreNotice();

      expect(notice, isNotNull);
      expect(notice!.restoredAt, restoredAt);
      expect(notice.previousDatabaseBackupPath, 'before.db');
      expect(notice.restoredDatabasePath, 'restored.db');
      expect(await noticeFile.exists(), false);
    });
  });
}

Future<void> _writeSqliteLikeDatabase(
  File file, {
  required String marker,
}) async {
  await file.parent.create(recursive: true);
  await file.writeAsBytes(
    <int>[
      ...ascii.encode('SQLite format 3\x00'),
      ...utf8.encode(marker),
    ],
    flush: true,
  );
}
