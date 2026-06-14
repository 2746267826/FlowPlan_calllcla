import 'dart:convert';

import '../database/app_database.dart';

class LegacyOfflineMutationSummary {
  const LegacyOfflineMutationSummary({
    required this.totalCount,
    required this.pendingCount,
    required this.failedCount,
    required this.conflictCount,
  });

  final int totalCount;
  final int pendingCount;
  final int failedCount;
  final int conflictCount;
}

class LegacyOfflineMutationCleanupService {
  const LegacyOfflineMutationCleanupService(this._database);

  final AppDatabase _database;

  Future<LegacyOfflineMutationSummary> summary() async {
    final row = await _database.customSelect(
      '''
      SELECT
        COUNT(*) AS total_count,
        COALESCE(SUM(CASE WHEN status IN ('pending', 'sending') THEN 1 ELSE 0 END), 0) AS pending_count,
        COALESCE(SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END), 0) AS failed_count,
        COALESCE(SUM(CASE WHEN status = 'conflict' THEN 1 ELSE 0 END), 0) AS conflict_count
      FROM offline_mutations
      ''',
    ).getSingle();
    return LegacyOfflineMutationSummary(
      totalCount: row.read<int>('total_count'),
      pendingCount: row.read<int>('pending_count'),
      failedCount: row.read<int>('failed_count'),
      conflictCount: row.read<int>('conflict_count'),
    );
  }

  Future<String> exportJson() async {
    final rows = await _database
        .customSelect(
          'SELECT * FROM offline_mutations ORDER BY id ASC',
        )
        .get();
    return const JsonEncoder.withIndent('  ').convert(
      rows.map((row) => row.data).toList(growable: false),
    );
  }

  Future<int> markPendingAsLegacyFailed() async {
    final before = await summary();
    await _database.customStatement(
      '''
      UPDATE offline_mutations
      SET status = 'failed',
          last_error = 'Legacy offline mutation retained after online-primary migration.',
          attempts = attempts + 1
      WHERE status IN ('pending', 'sending')
      ''',
    );
    final after = await summary();
    return before.pendingCount - after.pendingCount;
  }
}
