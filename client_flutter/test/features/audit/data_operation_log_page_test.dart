import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/audit/presentation/data_operation_log_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('DataOperationLogPage', () {
    testWidgets('shows empty state and reloads when the limit filter changes',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = _FakeDataOperationLogRepository(
        db,
        (limit) async => const <DataOperationLogEntry>[],
      );

      await _pumpPage(tester, repository);
      await _pumpUntilFound(tester, find.textContaining('当前还没有'));

      expect(repository.limits, <int>[100]);

      await _chooseLimit(tester, 50);
      await _pumpUntil(
        tester,
        () => repository.limits.contains(50),
      );

      expect(repository.limits, <int>[100, 50]);
      expect(find.textContaining('当前还没有'), findsOneWidget);
    });

    testWidgets('refreshes the current list when the toolbar refresh is tapped',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      var call = 0;
      final repository = _FakeDataOperationLogRepository(db, (limit) async {
        call++;
        return <DataOperationLogEntry>[
          _entry(
            id: call,
            summary: call == 1 ? 'Initial audit row' : 'Refreshed audit row',
          ),
        ];
      });

      await _pumpPage(tester, repository);
      await _pumpUntilFound(tester, find.text('Initial audit row'));

      await tester.tap(find.byIcon(Icons.refresh));
      await _pumpUntilFound(tester, find.text('Refreshed audit row'));

      expect(repository.limits, <int>[100, 100]);
      expect(find.text('Initial audit row'), findsNothing);
    });

    testWidgets('shows repository errors without opening stale detail rows',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = _FakeDataOperationLogRepository(db, (limit) async {
        throw StateError('audit database unavailable');
      });

      await _pumpPage(tester, repository);
      await _pumpUntilFound(
          tester, find.textContaining('audit database unavailable'));

      expect(find.byType(ExpansionTile), findsNothing);
      expect(repository.limits, <int>[100]);
    });

    testWidgets('expands a row to reveal metadata and formatted JSON details',
        (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = _FakeDataOperationLogRepository(
        db,
        (limit) async => <DataOperationLogEntry>[
          _entry(
            summary: 'Updated focus task',
            actor: 'operator-a',
            action: 'update_task',
            entityType: 'task',
            entityId: 'task-42',
            beforeJson: '{"summary":"Before","priority":1}',
            afterJson: '{"summary":"After","priority":2}',
            metadataJson: '{"changed":["summary","priority"]}',
          ),
        ],
      );

      await _pumpPage(tester, repository);
      await _pumpUntilFound(tester, find.text('Updated focus task'));

      expect(find.text('操作者：operator-a'), findsOneWidget);
      expect(find.text('动作：update_task'), findsOneWidget);
      expect(find.text('类型：task'), findsOneWidget);
      expect(find.text('ID：task-42'), findsOneWidget);

      await tester.tap(find.text('Updated focus task'));
      await tester.pumpAndSettle();

      expect(find.text('变更前'), findsOneWidget);
      expect(find.text('变更后'), findsOneWidget);
      expect(find.text('附加信息'), findsOneWidget);
      expect(_selectableTextContaining('"summary": "Before"'), findsOneWidget);
      expect(_selectableTextContaining('"summary": "After"'), findsOneWidget);
      expect(_selectableTextContaining('"changed": ['), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  DataOperationLogRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        dataOperationLogRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        home: DataOperationLogPage(),
      ),
    ),
  );
}

Future<void> _chooseLimit(WidgetTester tester, int limit) async {
  await tester.tap(find.byType(DropdownButton<int>));
  await tester.pumpAndSettle();
  final item = find.byWidgetPredicate(
    (widget) => widget is DropdownMenuItem<int> && widget.value == limit,
  );
  expect(item, findsWidgets);
  final text = find.descendant(
    of: item.last,
    matching: find.byType(Text),
  );
  await tester.tap(text.last);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  await _pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    maxPumps: maxPumps,
  );
  expect(finder, findsWidgets);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _selectableTextContaining(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is SelectableText && (widget.data ?? '').contains(text),
  );
}

DataOperationLogEntry _entry({
  int id = 1,
  String actor = 'tester',
  String action = 'create',
  String entityType = 'task',
  String? entityId = 'task-1',
  String summary = 'Audit row',
  String? beforeJson,
  String? afterJson,
  String? metadataJson,
}) {
  return DataOperationLogEntry(
    id: id,
    occurredAt: DateTime.utc(2026, 6, 10, 9, id),
    actor: actor,
    action: action,
    entityType: entityType,
    entityId: entityId,
    summary: summary,
    beforeJson: beforeJson,
    afterJson: afterJson,
    metadataJson: metadataJson,
  );
}

class _FakeDataOperationLogRepository extends DataOperationLogRepository {
  _FakeDataOperationLogRepository(
    super.db,
    this._loader,
  );

  final Future<List<DataOperationLogEntry>> Function(int limit) _loader;
  final limits = <int>[];

  @override
  Future<List<DataOperationLogEntry>> listRecent({int limit = 100}) {
    limits.add(limit);
    return _loader(limit);
  }
}
