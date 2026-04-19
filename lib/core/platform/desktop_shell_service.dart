import 'dart:io';

import 'package:flutter/services.dart';

class DesktopShellService {
  const DesktopShellService();

  static const MethodChannel _channel =
      MethodChannel('com.flowplan/desktop_shell');

  Future<void> setCloseToTrayEnabled(bool enabled) async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'setCloseToTrayEnabled',
        <String, Object?>{'enabled': enabled},
      );
    } catch (_) {
      // Runner capability failures should not block the app.
    }
  }

  Future<bool> getLaunchAtStartupEnabled() async {
    if (!Platform.isWindows) {
      return false;
    }
    try {
      final enabled = await _channel.invokeMethod<bool>(
        'getLaunchAtStartupEnabled',
      );
      return enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setLaunchAtStartupEnabled(bool enabled) async {
    if (!Platform.isWindows) {
      return enabled;
    }
    try {
      final applied = await _channel.invokeMethod<bool>(
        'setLaunchAtStartupEnabled',
        <String, Object?>{'enabled': enabled},
      );
      return applied ?? enabled;
    } catch (_) {
      return getLaunchAtStartupEnabled();
    }
  }
}
