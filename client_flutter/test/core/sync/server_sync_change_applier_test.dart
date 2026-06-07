import 'package:flowplanv2/core/sync/server_sync_change_applier.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('applies user setting changes and records sync state', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);
    final applier = ServerSyncChangeApplier(db, stateStore);

    final result = await applier.applyPullResponse(<String, dynamic>{
      'changes': <Object?>[
        <String, Object?>{
          'changeId': 'change-1',
          'objectType': 'user_setting',
          'serverId': 'setting-server-1',
          'uid': 'client.theme',
          'action': 'upsert',
          'serverVersion': 2,
          'payload': <String, Object?>{
            'settingKey': 'client.theme',
            'settingValue': 'dark',
          },
        },
      ],
    });

    expect(result.applied, 1);
    expect(result.failed, 0);
    expect(await db.getSetting('client.theme'), 'dark');
    final state = await stateStore.getState(
      objectType: 'user_setting',
      localId: 'client.theme',
    );
    expect(state?.serverId, 'setting-server-1');
    expect(state?.serverVersion, 2);
  });

  test('skips malformed pull responses without mutating local data', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final applier = ServerSyncChangeApplier(db, SyncObjectStateStore(db));

    final result = await applier.applyPullResponse(<String, dynamic>{
      'changes': 'not-a-list',
    });

    expect(result.received, 0);
    expect(result.applied, 0);
    expect(result.skipped, 0);
  });
}
