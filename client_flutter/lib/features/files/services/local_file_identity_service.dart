import 'dart:io';

import 'package:crypto/crypto.dart';

class LocalFileIdentity {
  const LocalFileIdentity({
    required this.localPath,
    required this.hashSha256,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String localPath;
  final String hashSha256;
  final int sizeBytes;
  final DateTime modifiedAt;

  Map<String, Object?> toJson({String? storageObjectId}) {
    return <String, Object?>{
      'localPath': localPath,
      'hashSha256': hashSha256,
      'sizeBytes': sizeBytes,
      'modifiedAt': modifiedAt.toIso8601String(),
      if (storageObjectId != null && storageObjectId.isNotEmpty)
        'storageObjectId': storageObjectId,
    };
  }
}

class LocalFileIdentityService {
  const LocalFileIdentityService();

  Future<LocalFileIdentity?> identify(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final file = File(normalized);
    if (!await file.exists()) {
      return null;
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }
    final digest = await sha256.bind(file.openRead()).first;
    return LocalFileIdentity(
      localPath: normalized,
      hashSha256: digest.toString(),
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
    );
  }
}
