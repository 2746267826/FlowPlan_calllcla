import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('local folder upsert is idempotent by normalized path', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = FileContextRepository(db);
    const path = r'C:\FlowPlanV2\client-tests';

    final first = await repository.upsertLocalFolder(
      localPath: path,
      displayName: 'Client tests',
      pinned: true,
    );
    final second = await repository.upsertLocalFolder(
      localPath: path,
      displayName: 'Client tests renamed',
    );

    final folders = await repository.listFolders();
    expect(second.id, first.id);
    expect(folders, hasLength(1));
    expect(folders.single.displayName, 'Client tests renamed');
  });
}
