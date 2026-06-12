import 'dart:io';

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

class DeviceIdentityService {
  DeviceIdentityService({
    Uuid? uuid,
    @visibleForTesting bool Function()? isWindowsForTesting,
    @visibleForTesting bool Function()? isAndroidForTesting,
  })  : _uuid = uuid ?? const Uuid(),
        _isWindows = isWindowsForTesting ?? (() => Platform.isWindows),
        _isAndroid = isAndroidForTesting ?? (() => Platform.isAndroid);

  static const _deviceIdSettingKey = 'device.identity.id';

  final Uuid _uuid;
  final bool Function() _isWindows;
  final bool Function() _isAndroid;

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
    if (_isWindows()) {
      return 'windows';
    }
    if (_isAndroid()) {
      return 'android';
    }
    return 'unknown';
  }
}
