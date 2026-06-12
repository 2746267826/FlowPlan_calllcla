// 设置 Provider：主题模式、工作时间、提醒、时间格式等
import 'dart:convert';
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

// ── 多组工作时间 ──────────────────────────────────────────────────────────────

class WorkTimeRange {
  const WorkTimeRange({
    required this.startMinute,
    required this.endMinute,
  });

  final int startMinute;
  final int endMinute;

  bool get isValid =>
      startMinute >= 0 && endMinute <= 24 * 60 && startMinute < endMinute;

  int get durationMinutes => endMinute - startMinute;

  Map<String, dynamic> toJson() => {
        'start': startMinute,
        'end': endMinute,
      };

  static WorkTimeRange? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final start = raw['start'];
    final end = raw['end'];
    if (start is! num || end is! num) {
      return null;
    }
    final range = WorkTimeRange(
      startMinute: start.round(),
      endMinute: end.round(),
    );
    return range.isValid ? range : null;
  }

  String format() => '${_formatMinute(startMinute)}-${_formatMinute(endMinute)}';

  static String _formatMinute(int value) {
    final hour = (value ~/ 60).toString().padLeft(2, '0');
    final minute = (value % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class WeeklyWorkSchedule {
  WeeklyWorkSchedule(Map<int, List<WorkTimeRange>> rangesByWeekday)
      : rangesByWeekday = {
          for (var weekday = DateTime.monday;
              weekday <= DateTime.sunday;
              weekday++)
            weekday: _normalize(rangesByWeekday[weekday] ?? const []),
        };

  final Map<int, List<WorkTimeRange>> rangesByWeekday;

  factory WeeklyWorkSchedule.defaults() {
    return WeeklyWorkSchedule({
      for (var weekday = DateTime.monday;
          weekday <= DateTime.friday;
          weekday++)
        weekday: const [
          WorkTimeRange(startMinute: 9 * 60, endMinute: 12 * 60),
          WorkTimeRange(startMinute: 13 * 60 + 30, endMinute: 18 * 60),
          WorkTimeRange(startMinute: 19 * 60 + 30, endMinute: 22 * 60),
        ],
      DateTime.saturday: const [
        WorkTimeRange(startMinute: 10 * 60, endMinute: 12 * 60),
        WorkTimeRange(startMinute: 14 * 60, endMinute: 18 * 60),
      ],
      DateTime.sunday: const <WorkTimeRange>[],
    });
  }

  factory WeeklyWorkSchedule.fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return WeeklyWorkSchedule.defaults();
      }
      final days = decoded['days'];
      if (days is! Map) {
        return WeeklyWorkSchedule.defaults();
      }
      return WeeklyWorkSchedule({
        for (final entry in days.entries)
          if (int.tryParse(entry.key.toString()) != null)
            int.parse(entry.key.toString()): entry.value is List
                ? (entry.value as List)
                    .map(WorkTimeRange.fromJson)
                    .whereType<WorkTimeRange>()
                    .toList()
                : const <WorkTimeRange>[],
      });
    } catch (_) {
      return WeeklyWorkSchedule.defaults();
    }
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'days': {
          for (final entry in rangesByWeekday.entries)
            entry.key.toString():
                entry.value.map((range) => range.toJson()).toList(),
        },
      };

  List<WorkTimeRange> rangesForWeekday(int weekday) {
    return List.unmodifiable(rangesByWeekday[weekday] ?? const []);
  }

  WeeklyWorkSchedule copyWithDay(
    int weekday,
    List<WorkTimeRange> ranges,
  ) {
    return WeeklyWorkSchedule({
      ...rangesByWeekday,
      weekday: ranges,
    });
  }

  int get activeWeekdayCount => rangesByWeekday.values
      .where((ranges) => ranges.isNotEmpty)
      .length;

  String summaryForWeekday(int weekday) {
    final ranges = rangesForWeekday(weekday);
    if (ranges.isEmpty) {
      return '休息';
    }
    return ranges.map((range) => range.format()).join('，');
  }

  String get compactSummary {
    final activeCount = activeWeekdayCount;
    if (activeCount == 0) {
      return '所有日期均未设置工作时段';
    }
    final monday = summaryForWeekday(DateTime.monday);
    final tuesday = summaryForWeekday(DateTime.tuesday);
    final wednesday = summaryForWeekday(DateTime.wednesday);
    final thursday = summaryForWeekday(DateTime.thursday);
    final friday = summaryForWeekday(DateTime.friday);
    if (monday == tuesday &&
        monday == wednesday &&
        monday == thursday &&
        monday == friday) {
      return '工作日：$monday；已启用 $activeCount 天';
    }
    return '已启用 $activeCount 天；今天：${summaryForWeekday(DateTime.now().weekday)}';
  }

  static List<WorkTimeRange> _normalize(List<WorkTimeRange> input) {
    final sorted = input.where((range) => range.isValid).toList()
      ..sort((left, right) => left.startMinute.compareTo(right.startMinute));
    if (sorted.isEmpty) {
      return const <WorkTimeRange>[];
    }

    final merged = <WorkTimeRange>[];
    for (final range in sorted) {
      if (merged.isEmpty) {
        merged.add(range);
        continue;
      }
      final last = merged.last;
      if (range.startMinute <= last.endMinute) {
        merged[merged.length - 1] = WorkTimeRange(
          startMinute: last.startMinute,
          endMinute: range.endMinute > last.endMinute
              ? range.endMinute
              : last.endMinute,
        );
      } else {
        merged.add(range);
      }
    }
    return List.unmodifiable(merged);
  }
}

class WeeklyWorkScheduleNotifier extends StateNotifier<WeeklyWorkSchedule> {
  WeeklyWorkScheduleNotifier(this._ref) : super(WeeklyWorkSchedule.defaults()) {
    _load();
  }

  static const _key = 'scheduler.weekly_work_schedule.v1';

  final Ref _ref;
  int _loadVersion = 0;

  Future<void> _load() async {
    final version = ++_loadVersion;
    final db = _ref.read(databaseProvider);
    final raw = await db.getSetting(_key);
    if (version != _loadVersion || raw == null || raw.trim().isEmpty) {
      return;
    }
    state = WeeklyWorkSchedule.fromJsonString(raw);
  }

  Future<void> setSchedule(WeeklyWorkSchedule schedule) async {
    final normalized = WeeklyWorkSchedule(schedule.rangesByWeekday);
    state = normalized;
    final db = _ref.read(databaseProvider);
    await db.setSetting(_key, jsonEncode(normalized.toJson()));
  }

  Future<void> setDayRanges(
    int weekday,
    List<WorkTimeRange> ranges,
  ) async {
    await setSchedule(state.copyWithDay(weekday, ranges));
  }

  Future<void> resetDefaults() async {
    await setSchedule(WeeklyWorkSchedule.defaults());
  }
}

final weeklyWorkScheduleNotifierProvider =
    StateNotifierProvider<WeeklyWorkScheduleNotifier, WeeklyWorkSchedule>(
  (ref) => WeeklyWorkScheduleNotifier(ref),
);

final weeklyWorkScheduleProvider = Provider<WeeklyWorkSchedule>((ref) {
  return ref.watch(weeklyWorkScheduleNotifierProvider);
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
  MinimizeToTrayNotifier(this._ref, {bool? isWindowsOverride})
      : _isWindowsOverride = isWindowsOverride,
        super(isWindowsOverride ?? Platform.isWindows) {
    _load();
  }

  final Ref _ref;
  final DesktopShellService _desktopShell = const DesktopShellService();
  final bool? _isWindowsOverride;
  int _operationVersion = 0;

  bool get _isWindows => _isWindowsOverride ?? Platform.isWindows;

  Future<void> _load() async {
    if (!_isWindows) {
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
    if (!_isWindows) {
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
  LaunchAtStartupNotifier(this._ref, {bool? isWindowsOverride})
      : _isWindowsOverride = isWindowsOverride,
        super(false) {
    _load();
  }

  final Ref _ref;
  final DesktopShellService _desktopShell = const DesktopShellService();
  final bool? _isWindowsOverride;
  int _operationVersion = 0;

  bool get _isWindows => _isWindowsOverride ?? Platform.isWindows;

  Future<void> _load() async {
    if (!_isWindows) {
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
    if (!_isWindows) {
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
