import 'dart:convert';
import 'dart:io';

import 'app_storage.dart';

class DatabaseRestorePreparation {
  const DatabaseRestorePreparation({
    required this.sourcePath,
    required this.stagedPath,
  });

  final String sourcePath;
  final String stagedPath;
}

class DatabaseRestoreApplyResult {
  const DatabaseRestoreApplyResult({
    required this.applied,
    this.previousDatabaseBackupPath,
    this.restoredDatabasePath,
  });

  const DatabaseRestoreApplyResult.skipped()
      : applied = false,
        previousDatabaseBackupPath = null,
        restoredDatabasePath = null;

  final bool applied;
  final String? previousDatabaseBackupPath;
  final String? restoredDatabasePath;
}

class DatabaseRestoreNotice {
  const DatabaseRestoreNotice({
    required this.restoredAt,
    required this.previousDatabaseBackupPath,
    required this.restoredDatabasePath,
  });

  final DateTime restoredAt;
  final String? previousDatabaseBackupPath;
  final String restoredDatabasePath;
}

class PendingDatabaseRestore {
  const PendingDatabaseRestore({
    required this.sourcePath,
    required this.stagedPath,
    required this.stagedAt,
  });

  final String sourcePath;
  final String stagedPath;
  final DateTime stagedAt;
}

class DatabaseRestoreService {
  const DatabaseRestoreService();

  static const _sqliteHeader = 'SQLite format 3';

  Future<DatabaseRestorePreparation> stageRestore(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('\u6240\u9009\u5907\u4efd\u6587\u4ef6\u4e0d\u5b58\u5728\u3002');
    }
    if (!await _looksLikeSqliteDatabase(sourceFile)) {
      throw StateError(
        '\u6240\u9009\u6587\u4ef6\u4e0d\u662f\u6709\u6548\u7684 SQLite \u6570\u636e\u5e93\u526f\u672c\u3002',
      );
    }

    final stagedFile = await resolvePendingDatabaseRestoreFile();
    await stagedFile.parent.create(recursive: true);
    if (await stagedFile.exists()) {
      await stagedFile.delete();
    }
    await sourceFile.copy(stagedFile.path);

    final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
    await metadataFile.parent.create(recursive: true);
    await metadataFile.writeAsString(
      jsonEncode(<String, Object?>{
        'sourcePath': sourceFile.path,
        'stagedPath': stagedFile.path,
        'stagedAt': DateTime.now().toIso8601String(),
      }),
    );

    return DatabaseRestorePreparation(
      sourcePath: sourceFile.path,
      stagedPath: stagedFile.path,
    );
  }

  Future<DatabaseRestoreApplyResult> applyPendingRestoreIfNeeded() async {
    final stagedFile = await resolvePendingDatabaseRestoreFile();
    final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
    if (!await stagedFile.exists()) {
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }
      return const DatabaseRestoreApplyResult.skipped();
    }

    if (!await _looksLikeSqliteDatabase(stagedFile)) {
      await stagedFile.delete();
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }
      return const DatabaseRestoreApplyResult.skipped();
    }

    final databaseFile = await resolvePrimaryDatabaseFile();
    final previousBackupFile = await resolvePreRestoreDatabaseBackupFile();
    await databaseFile.parent.create(recursive: true);

    await _deleteSqliteSidecars(databaseFile);

    String? previousDatabaseBackupPath;
    if (await databaseFile.exists()) {
      if (await previousBackupFile.exists()) {
        await previousBackupFile.delete();
      }
      await databaseFile.copy(previousBackupFile.path);
      previousDatabaseBackupPath = previousBackupFile.path;
      await databaseFile.delete();
    }

    await stagedFile.copy(databaseFile.path);
    await stagedFile.delete();
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }

    final noticeFile = await resolveDatabaseRestoreNoticeFile();
    await noticeFile.parent.create(recursive: true);
    await noticeFile.writeAsString(
      jsonEncode(<String, Object?>{
        'restoredAt': DateTime.now().toIso8601String(),
        'previousDatabaseBackupPath': previousDatabaseBackupPath,
        'restoredDatabasePath': databaseFile.path,
      }),
    );

    return DatabaseRestoreApplyResult(
      applied: true,
      previousDatabaseBackupPath: previousDatabaseBackupPath,
      restoredDatabasePath: databaseFile.path,
    );
  }

  Future<DatabaseRestoreNotice?> consumeRestoreNotice() async {
    final noticeFile = await resolveDatabaseRestoreNoticeFile();
    if (!await noticeFile.exists()) {
      return null;
    }

    try {
      final raw = await noticeFile.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        await noticeFile.delete();
        return null;
      }

      final restoredAtRaw = json['restoredAt'] as String?;
      final restoredDatabasePath = json['restoredDatabasePath'] as String?;
      if (restoredAtRaw == null || restoredDatabasePath == null) {
        await noticeFile.delete();
        return null;
      }

      final notice = DatabaseRestoreNotice(
        restoredAt: DateTime.tryParse(restoredAtRaw) ?? DateTime.now(),
        previousDatabaseBackupPath:
            json['previousDatabaseBackupPath'] as String?,
        restoredDatabasePath: restoredDatabasePath,
      );
      await noticeFile.delete();
      return notice;
    } catch (_) {
      await noticeFile.delete();
      return null;
    }
  }

  Future<PendingDatabaseRestore?> getPendingRestore() async {
    final stagedFile = await resolvePendingDatabaseRestoreFile();
    final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
    if (!await stagedFile.exists()) {
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }
      return null;
    }

    if (!await metadataFile.exists()) {
      return PendingDatabaseRestore(
        sourcePath: stagedFile.path,
        stagedPath: stagedFile.path,
        stagedAt: await stagedFile.lastModified(),
      );
    }

    try {
      final raw = await metadataFile.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        await metadataFile.delete();
        return PendingDatabaseRestore(
          sourcePath: stagedFile.path,
          stagedPath: stagedFile.path,
          stagedAt: await stagedFile.lastModified(),
        );
      }

      return PendingDatabaseRestore(
        sourcePath: (json['sourcePath'] as String?) ?? stagedFile.path,
        stagedPath: (json['stagedPath'] as String?) ?? stagedFile.path,
        stagedAt:
            DateTime.tryParse(json['stagedAt'] as String? ?? '') ??
            await stagedFile.lastModified(),
      );
    } catch (_) {
      await metadataFile.delete();
      return PendingDatabaseRestore(
        sourcePath: stagedFile.path,
        stagedPath: stagedFile.path,
        stagedAt: await stagedFile.lastModified(),
      );
    }
  }

  Future<void> clearPendingRestore() async {
    final stagedFile = await resolvePendingDatabaseRestoreFile();
    final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
    if (await stagedFile.exists()) {
      await stagedFile.delete();
    }
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
  }

  Future<bool> _looksLikeSqliteDatabase(File file) async {
    try {
      final input = await file.open();
      final bytes = await input.read(16);
      await input.close();
      if (bytes.length < 16) {
        return false;
      }
      final header = ascii.decode(bytes, allowInvalid: true);
      return header.startsWith(_sqliteHeader);
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteSqliteSidecars(File databaseFile) async {
    final walFile = File('${databaseFile.path}-wal');
    final shmFile = File('${databaseFile.path}-shm');
    if (await walFile.exists()) {
      await walFile.delete();
    }
    if (await shmFile.exists()) {
      await shmFile.delete();
    }
  }
}
