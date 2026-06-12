import 'package:flowplanv2/core/platform/device_identity_service.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start and imported records stamp default device and platform',
      () async {
    await setUpTempAppStorage(prefix: 'activity-record-repo-deep-');
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.setSetting('device.identity.id', 'test-device');
    final repository = ActivityRecordRepository(
      db,
      deviceIdentityService: DeviceIdentityService(
        isWindowsForTesting: () => true,
        isAndroidForTesting: () => false,
      ),
    );
    final start = DateTime(2026, 6, 12, 16);

    final manualId = await repository.startRecord(
      startTime: start,
      processName: 'Code.exe',
    );
    final importedId = await repository.insertImportedRecord(
      startTime: start.add(const Duration(minutes: 10)),
      endTime: start.add(const Duration(minutes: 20)),
      processName: 'Browser',
    );

    final rows = await db.customSelect(
      '''
          SELECT id, device_id, platform
          FROM activity_records
          ORDER BY id ASC
          ''',
    ).get();
    expect(rows.map((row) => row.read<int>('id')), <int>[
      manualId,
      importedId,
    ]);
    expect(rows.map((row) => row.read<String>('device_id')).toSet(), {
      'test-device',
    });
    expect(rows.map((row) => row.read<String>('platform')).toSet(), {
      'windows',
    });
  });
}
