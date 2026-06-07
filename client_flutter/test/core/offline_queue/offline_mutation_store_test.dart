import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('enqueue stores pending mutation payload and changed fields', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = OfflineMutationStore(db);

    final mutationUid = await store.enqueue(
      objectType: 'task_item',
      localId: 'local-task-1',
      action: OfflineMutationAction.create,
      payload: <String, Object?>{
        'uid': 'task-1',
        'summary': 'Write tests',
      },
      changedFields: const <String>['summary'],
    );

    final pending = await store.listPending();
    expect(pending, hasLength(1));
    expect(pending.single.mutationUid, mutationUid);
    expect(pending.single.status, OfflineMutationStatus.pending);
    expect(pending.single.objectType, 'task_item');
    expect(pending.single.payloadJson, contains('Write tests'));
    expect(pending.single.changedFieldsJson, contains('summary'));
  });
}
