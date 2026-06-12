import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/audit/presentation/data_operation_log_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  testWidgets('audit page separates multiple rows and falls back for raw JSON',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = _Gap6AuditRepository(
      db,
      <DataOperationLogEntry>[
        _entry(
          id: 1,
          summary: 'Malformed before snapshot',
          beforeJson: '{"missing-end"',
        ),
        _entry(
          id: 2,
          summary: 'Second audit row',
          afterJson: '{"ok":true}',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dataOperationLogRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: DataOperationLogPage()),
      ),
    );
    await _pumpUntilFound(tester, find.text('Second audit row'));

    expect(find.byType(SizedBox), findsWidgets);

    await tester.tap(find.text('Malformed before snapshot'));
    await tester.pumpAndSettle();

    expect(_selectableTextContaining('{"missing-end"'), findsOneWidget);
  });
}

DataOperationLogEntry _entry({
  required int id,
  required String summary,
  String? beforeJson,
  String? afterJson,
}) {
  return DataOperationLogEntry(
    id: id,
    occurredAt: DateTime.utc(2026, 6, 11, 9, id),
    actor: 'gap6',
    action: 'update',
    entityType: 'task',
    entityId: null,
    summary: summary,
    beforeJson: beforeJson,
    afterJson: afterJson,
    metadataJson: null,
  );
}

Finder _selectableTextContaining(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is SelectableText && (widget.data ?? '').contains(text),
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Expected finder did not appear: $finder');
}

class _Gap6AuditRepository extends DataOperationLogRepository {
  _Gap6AuditRepository(super.db, this.entries);

  final List<DataOperationLogEntry> entries;

  @override
  Future<List<DataOperationLogEntry>> listRecent({int limit = 100}) async {
    return entries.take(limit).toList(growable: false);
  }
}
