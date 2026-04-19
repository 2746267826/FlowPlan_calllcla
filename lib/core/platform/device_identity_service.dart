import 'dart:io';

import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

class DeviceIdentityService {
  DeviceIdentityService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const _deviceIdSettingKey = 'device.identity.id';

  final Uuid _uuid;

  Future<String> getOrCreateDeviceId(AppDatabase database) async {
    final existing = await database.getSetting(_deviceIdSettingKey);
    final trimmed = existing?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }

    final created = _uuid.v4();
    await database.setSetting(_deviceIdSettingKey, created);
    return created;
  }

  String get currentPlatform {
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isAndroid) {
      return 'android';
    }
    return 'unknown';
  }
}
