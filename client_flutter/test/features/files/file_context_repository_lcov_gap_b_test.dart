import 'dart:io';

import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('file item folder id resolver keeps existing folder when omitted', () {
    expect(resolveFileItemFolderId(null, 42), 42);
    expect(resolveFileItemFolderId(7, 42), 7);
  });

  test('scanRoot updates existing file items through the no-sync upsert path',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final directory = await Directory.systemTemp.createTemp(
      'flowplanv2-lcov-gap-b-repository-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}${Platform.pathSeparator}brief.md');
    await file.writeAsString('# Brief');
    final repository = FileContextRepository(db);
    final folder = await repository.upsertLocalFolder(
      localPath: directory.path,
      displayName: 'Scan Update Root',
    );

    await repository.scanRoot(folderId: folder.id);
    final first = (await repository.listFilesForFolder(folder.id)).single;

    await file.writeAsString('# Brief\n\nUpdated with more content.');
    await repository.scanRoot(folderId: folder.id);
    final updated = (await repository.listFilesForFolder(folder.id)).single;

    expect(updated.id, first.id);
    expect(updated.folderId, folder.id);
    expect(updated.displayName, 'brief.md');
    expect(updated.previewMode, 'text');
    expect(updated.sizeBytes, greaterThan(first.sizeBytes!));
  });
}
