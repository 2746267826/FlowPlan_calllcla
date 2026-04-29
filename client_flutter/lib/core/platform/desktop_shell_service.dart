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

  Future<void> showReminder({
    required String title,
    required String body,
  }) async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'showReminder',
        <String, Object?>{
          'title': title,
          'body': body,
        },
      );
    } catch (_) {
      // Reminder delivery is best-effort on the native shell side.
    }
  }

  Future<bool> openPath(String path) async {
    if (!Platform.isWindows) {
      return false;
    }
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openPath',
        <String, Object?>{'path': path},
      );
      return opened ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> revealPath(String path) async {
    if (!Platform.isWindows) {
      return false;
    }
    try {
      final revealed = await _channel.invokeMethod<bool>(
        'revealPath',
        <String, Object?>{'path': path},
      );
      return revealed ?? false;
    } catch (_) {
      return false;
    }
  }
}
