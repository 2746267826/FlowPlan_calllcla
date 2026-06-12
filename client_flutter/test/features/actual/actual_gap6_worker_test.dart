import 'dart:async';

import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ActualActivityLogRepository gap6 worker', () {
    test('watchInRange forwards query errors to listeners', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = _ThrowingActualRepository(db);
      addTearDown(repository.dispose);
      final errors = <Object>[];
      final subscription = repository
          .watchInRange(
        DateTime.utc(2026, 6, 11, 9),
        DateTime.utc(2026, 6, 11, 10),
      )
          .listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          errors.add(error);
        },
      );
      addTearDown(subscription.cancel);

      await _pumpUntil(() => errors.isNotEmpty);
      expect(errors.single.toString(), contains('range query failed'));
    });

    test('fromRow normalizes string confidence and invalid optional dates',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActualActivityLogRepository(db);
      addTearDown(repository.dispose);

      await db.customStatement(
        '''
        INSERT INTO actual_activity_logs (
          actual_uid,
          title,
          start_at,
          end_at,
          source_type,
          source_payload_json,
          confidence,
          status,
          created_at,
          updated_at,
          confirmed_at,
          rejected_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          'actual-string-confidence',
          'Imported candidate',
          DateTime.utc(2026, 6, 11, 9).toIso8601String(),
          DateTime.utc(2026, 6, 11, 10).toIso8601String(),
          ActualActivitySourceType.aiDraft,
          '{}',
          '0.42',
          ActualActivityStatus.candidate,
          DateTime.utc(2026, 6, 11, 8).toIso8601String(),
          DateTime.utc(2026, 6, 11, 8).toIso8601String(),
          'not-a-date',
          '',
        ],
      );

      final row = (await repository.listInRange(
        DateTime.utc(2026, 6, 11, 8),
        DateTime.utc(2026, 6, 11, 11),
      ))
          .single;

      expect(row.sourceType, ActualActivitySourceType.aiDraft);
      expect(row.confidence, 0.42);
      expect(row.confirmedAt, isNull);
      expect(row.rejectedAt, isNull);
      expect(row.isConfirmed, isFalse);
    });
  });
}

class _ThrowingActualRepository extends ActualActivityLogRepository {
  _ThrowingActualRepository(super.db);

  @override
  Future<List<ActualActivityLog>> listInRange(
    DateTime start,
    DateTime end, {
    Iterable<String>? statuses,
  }) async {
    throw StateError('range query failed');
  }
}

Future<void> _pumpUntil(
  FutureOr<bool> Function() condition, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (await condition()) {
      return;
    }
    await pumpEventQueue(times: 4);
  }
  fail('Condition was not met after $maxPumps event queue pumps.');
}
