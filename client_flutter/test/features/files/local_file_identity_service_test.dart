import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flowplanv2/features/files/services/local_file_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identify returns null for blank missing or directory paths', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('flowplanv2-identity-empty-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const service = LocalFileIdentityService();

    expect(await service.identify('   '), isNull);
    expect(
      await service.identify(
        '${tempDir.path}${Platform.pathSeparator}missing.txt',
      ),
      isNull,
    );
    expect(await service.identify(tempDir.path), isNull);
  });

  test('identify reads file hash size modified time and JSON metadata',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('flowplanv2-identity-file-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final file = File('${tempDir.path}${Platform.pathSeparator}note.txt');
    final bytes = <int>[70, 108, 111, 119, 80, 108, 97, 110];
    file.writeAsBytesSync(bytes);

    const service = LocalFileIdentityService();

    final identity = await service.identify('  ${file.path}  ');

    expect(identity, isNotNull);
    expect(identity!.localPath, file.path);
    expect(identity.hashSha256, sha256.convert(bytes).toString());
    expect(identity.sizeBytes, bytes.length);
    expect(identity.modifiedAt, file.statSync().modified);
    expect(identity.toJson(), <String, Object?>{
      'localPath': file.path,
      'hashSha256': sha256.convert(bytes).toString(),
      'sizeBytes': bytes.length,
      'modifiedAt': identity.modifiedAt.toIso8601String(),
    });
    expect(
      identity.toJson(storageObjectId: 'storage-1'),
      containsPair('storageObjectId', 'storage-1'),
    );
    expect(
      identity.toJson(storageObjectId: ''),
      isNot(contains('storageObjectId')),
    );
  });
}
