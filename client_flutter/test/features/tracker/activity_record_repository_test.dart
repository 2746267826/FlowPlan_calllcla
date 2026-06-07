import 'package:drift/drift.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('manual tracking records duration and device context', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = ActivityRecordRepository(db);
    final start = fixtureNow();

    final recordId = await repository.startRecord(
      startTime: start,
      manualLabel: 'Focused implementation',
      deviceId: 'device-test',
      platform: 'windows',
    );
    await repository.endRecord(recordId, start.add(const Duration(minutes: 35)));

    final record = await repository.getById(recordId);
    final deviceRow = await db.customSelect(
      'SELECT device_id, platform FROM activity_records WHERE id = ?',
      variables: [Variable<int>(recordId)],
    ).getSingle();
    expect(record?.manualLabel, 'Focused implementation');
    expect(record?.durationMinutes, 35);
    expect(deviceRow.data['device_id'], 'device-test');
    expect(deviceRow.data['platform'], 'windows');
  });
}
