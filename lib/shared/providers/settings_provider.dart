// 设置 Provider：主题模式、工作时间、提醒、时间格式等
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/desktop_shell_service.dart';
import 'database_provider.dart';

part 'settings_provider.g.dart';

// ── 主题模式 ──────────────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
class ThemeModeNotifier extends _$ThemeModeNotifier {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    _loadTheme();
    return ThemeMode.system; // 默认跟随系统
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value != null) {
      state = ThemeMode.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ThemeMode.system,
      );
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

/// 便捷访问当前主题模式
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(themeModeNotifierProvider);
});

// ── 工作开始时间 ──────────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
class WorkStartNotifier extends _$WorkStartNotifier {
  static const _key = 'work_start';

  @override
  TimeOfDay build() {
    _load();
    return const TimeOfDay(hour: 9, minute: 0);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null) state = TimeOfDay(hour: v ~/ 60, minute: v % 60);
  }

  Future<void> set(TimeOfDay t) async {
    state = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, t.hour * 60 + t.minute);
  }
}

final workStartProvider = Provider<TimeOfDay>((ref) {
  return ref.watch(workStartNotifierProvider);
});

// ── 工作结束时间 ──────────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
class WorkEndNotifier extends _$WorkEndNotifier {
  static const _key = 'work_end';

  @override
  TimeOfDay build() {
    _load();
    return const TimeOfDay(hour: 22, minute: 0);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null) state = TimeOfDay(hour: v ~/ 60, minute: v % 60);
  }

  Future<void> set(TimeOfDay t) async {
    state = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, t.hour * 60 + t.minute);
  }
}

final workEndProvider = Provider<TimeOfDay>((ref) {
  return ref.watch(workEndNotifierProvider);
});

// ── 默认提醒分钟数 ────────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
class ReminderMinutesNotifier extends _$ReminderMinutesNotifier {
  static const _key = 'reminder_minutes';

  @override
  int build() {
    _load();
    return 15;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null) state = v;
  }

  Future<void> set(int minutes) async {
    state = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, minutes);
  }
}

final reminderMinutesProvider = Provider<int>((ref) {
  return ref.watch(reminderMinutesNotifierProvider);
});

// ── 24 小时制 ─────────────────────────────────────────────────────────────────

@Riverpod(keepAlive: true)
class Use24hNotifier extends _$Use24hNotifier {
  static const _key = 'use_24h';

  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_key);
    if (v != null) state = v;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

final use24hProvider = Provider<bool>((ref) {
  return ref.watch(use24hNotifierProvider);
});

// ── 一周起始日（1=周一, 7=周日）───────────────────────────────────────────────

@Riverpod(keepAlive: true)
class FirstDayOfWeekNotifier extends _$FirstDayOfWeekNotifier {
  static const _key = 'first_day_of_week';

  @override
  int build() {
    _load();
    return 1; // 默认周一
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key);
    if (v != null) state = v;
  }

  Future<void> set(int day) async {
    state = day;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, day);
  }
}

final firstDayOfWeekProvider = Provider<int>((ref) {
  return ref.watch(firstDayOfWeekNotifierProvider);
});

// 鈹€鈹€ 逐字序列记录（默认关闭） 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

@Riverpod(keepAlive: true)
class SequenceRecordingNotifier extends _$SequenceRecordingNotifier {
  static const _key = 'sequence_recording';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_key);
    if (v != null) state = v;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

final sequenceRecordingProvider = Provider<bool>((ref) {
  return ref.watch(sequenceRecordingNotifierProvider);
});

const _minimizeToTraySettingKey = 'desktop.minimize_to_tray';
const _launchAtStartupSettingKey = 'desktop.launch_at_startup';

class MinimizeToTrayNotifier extends StateNotifier<bool> {
  MinimizeToTrayNotifier(this._ref) : super(Platform.isWindows) {
    _load();
  }

  final Ref _ref;
  final DesktopShellService _desktopShell = const DesktopShellService();
  int _operationVersion = 0;

  Future<void> _load() async {
    if (!Platform.isWindows) {
      state = false;
      return;
    }

    final currentVersion = ++_operationVersion;
    final db = _ref.read(databaseProvider);
    final enabled = await db.getBoolSetting(
      _minimizeToTraySettingKey,
      defaultValue: true,
    );
    if (currentVersion != _operationVersion) {
      return;
    }
    state = enabled;
    await _desktopShell.setCloseToTrayEnabled(enabled);
  }

  Future<void> set(bool enabled) async {
    if (!Platform.isWindows) {
      state = false;
      return;
    }

    final currentVersion = ++_operationVersion;
    final db = _ref.read(databaseProvider);
    await db.setBoolSetting(_minimizeToTraySettingKey, enabled);
    await _desktopShell.setCloseToTrayEnabled(enabled);
    if (currentVersion != _operationVersion) {
      return;
    }
    state = enabled;
  }
}

final minimizeToTrayNotifierProvider =
    StateNotifierProvider<MinimizeToTrayNotifier, bool>(
  (ref) => MinimizeToTrayNotifier(ref),
);

final minimizeToTrayProvider = Provider<bool>((ref) {
  return ref.watch(minimizeToTrayNotifierProvider);
});

class LaunchAtStartupNotifier extends StateNotifier<bool> {
  LaunchAtStartupNotifier(this._ref) : super(false) {
    _load();
  }

  final Ref _ref;
  final DesktopShellService _desktopShell = const DesktopShellService();
  int _operationVersion = 0;

  Future<void> _load() async {
    if (!Platform.isWindows) {
      state = false;
      return;
    }

    final currentVersion = ++_operationVersion;
    final db = _ref.read(databaseProvider);
    final actual = await _desktopShell.getLaunchAtStartupEnabled();
    if (currentVersion != _operationVersion) {
      return;
    }
    state = actual;
    await db.setBoolSetting(_launchAtStartupSettingKey, actual);
  }

  Future<void> set(bool enabled) async {
    if (!Platform.isWindows) {
      state = false;
      return;
    }

    final currentVersion = ++_operationVersion;
    await _desktopShell.setLaunchAtStartupEnabled(enabled);
    final actual = await _desktopShell.getLaunchAtStartupEnabled();
    if (currentVersion != _operationVersion) {
      return;
    }
    state = actual;
    final db = _ref.read(databaseProvider);
    await db.setBoolSetting(_launchAtStartupSettingKey, actual);
  }
}

final launchAtStartupNotifierProvider =
    StateNotifierProvider<LaunchAtStartupNotifier, bool>(
  (ref) => LaunchAtStartupNotifier(ref),
);

final launchAtStartupProvider = Provider<bool>((ref) {
  return ref.watch(launchAtStartupNotifierProvider);
});
