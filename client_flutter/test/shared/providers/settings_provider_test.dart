import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  group('shared settings providers', () {
    test('load defaults first and then persisted shared preference values',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'theme_mode': 'dark',
        'work_start': 8 * 60 + 15,
        'work_end': 19 * 60 + 45,
        'reminder_minutes': 30,
        'use_24h': false,
        'first_day_of_week': 7,
        'sequence_recording': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
      expect(container.read(workStartProvider),
          const TimeOfDay(hour: 9, minute: 0));
      expect(container.read(workEndProvider),
          const TimeOfDay(hour: 22, minute: 0));
      expect(container.read(reminderMinutesProvider), 15);
      expect(container.read(use24hProvider), isTrue);
      expect(container.read(firstDayOfWeekProvider), 1);
      expect(container.read(sequenceRecordingProvider), isFalse);

      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(
        container.read(workStartProvider),
        const TimeOfDay(hour: 8, minute: 15),
      );
      expect(
        container.read(workEndProvider),
        const TimeOfDay(hour: 19, minute: 45),
      );
      expect(container.read(reminderMinutesProvider), 30);
      expect(container.read(use24hProvider), isFalse);
      expect(container.read(firstDayOfWeekProvider), 7);
      expect(container.read(sequenceRecordingProvider), isTrue);
    });

    test('persist changes through notifier APIs', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(themeModeNotifierProvider.notifier)
          .setThemeMode(ThemeMode.light);
      await container
          .read(workStartNotifierProvider.notifier)
          .set(const TimeOfDay(hour: 7, minute: 30));
      await container
          .read(workEndNotifierProvider.notifier)
          .set(const TimeOfDay(hour: 18, minute: 15));
      await container.read(reminderMinutesNotifierProvider.notifier).set(45);
      await container.read(use24hNotifierProvider.notifier).toggle();
      await container.read(firstDayOfWeekNotifierProvider.notifier).set(6);
      await container
          .read(sequenceRecordingNotifierProvider.notifier)
          .set(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'light');
      expect(prefs.getInt('work_start'), 7 * 60 + 30);
      expect(prefs.getInt('work_end'), 18 * 60 + 15);
      expect(prefs.getInt('reminder_minutes'), 45);
      expect(prefs.getBool('use_24h'), isFalse);
      expect(prefs.getInt('first_day_of_week'), 6);
      expect(prefs.getBool('sequence_recording'), isTrue);
    });

    test('allows higher-level providers to be overridden in isolated scopes',
        () {
      final schedule = WeeklyWorkSchedule({
        DateTime.monday: const <WorkTimeRange>[
          WorkTimeRange(startMinute: 12 * 60, endMinute: 13 * 60),
        ],
      });
      final container = ProviderContainer(
        overrides: <Override>[
          themeModeProvider.overrideWithValue(ThemeMode.dark),
          weeklyWorkScheduleProvider.overrideWithValue(schedule),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(
        container.read(weeklyWorkScheduleProvider).summaryForWeekday(
              DateTime.monday,
            ),
        '12:00-13:00',
      );
    });
  });

  group('WeeklyWorkSchedule parsing', () {
    test('falls back to defaults when saved JSON is malformed', () {
      final schedule = WeeklyWorkSchedule.fromJsonString('{not-json');

      expect(schedule.activeWeekdayCount, 6);
      expect(schedule.rangesForWeekday(DateTime.monday), hasLength(3));
      expect(schedule.rangesForWeekday(DateTime.saturday), hasLength(2));
      expect(schedule.rangesForWeekday(DateTime.sunday), isEmpty);
      expect(
        schedule.summaryForWeekday(DateTime.monday),
        contains('09:00-12:00'),
      );
    });

    test('falls back to defaults when JSON shape is not a days map', () {
      final arraySchedule = WeeklyWorkSchedule.fromJsonString('[]');
      final missingDaysSchedule = WeeklyWorkSchedule.fromJsonString(
        jsonEncode(<String, Object?>{'version': 1}),
      );

      expect(arraySchedule.rangesForWeekday(DateTime.monday), hasLength(3));
      expect(
          missingDaysSchedule.rangesForWeekday(DateTime.monday), hasLength(3));
    });

    test('filters invalid ranges and normalizes the weekly summary', () {
      final schedule = WeeklyWorkSchedule.fromJsonString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'days': <String, Object?>{
            '1': <Map<String, Object?>>[
              <String, Object?>{'start': 8 * 60, 'end': 10 * 60},
              <String, Object?>{'start': 9 * 60, 'end': 11 * 60},
              <String, Object?>{'start': 22 * 60, 'end': 21 * 60},
              <String, Object?>{'start': 'bad', 'end': 18 * 60},
            ],
            '2': <Map<String, Object?>>[
              <String, Object?>{'start': 13 * 60, 'end': 14 * 60},
            ],
            '7': <Object?>[],
            '9': <Map<String, Object?>>[
              <String, Object?>{'start': 1, 'end': 2},
            ],
          },
        }),
      );

      expect(schedule.activeWeekdayCount, 2);
      expect(schedule.rangesForWeekday(DateTime.monday), hasLength(1));
      expect(
          schedule.rangesForWeekday(DateTime.monday).single.startMinute, 480);
      expect(schedule.rangesForWeekday(DateTime.monday).single.endMinute, 660);
      expect(schedule.rangesForWeekday(DateTime.sunday), isEmpty);
      expect(
        schedule.summaryForWeekday(DateTime.monday),
        contains('08:00-11:00'),
      );
      expect(schedule.compactSummary, contains('2'));
    });
  });

  group('weeklyWorkScheduleProvider', () {
    test('loads malformed persisted schedule as defaults', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      await db.setSetting('scheduler.weekly_work_schedule.v1', '{broken');
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(weeklyWorkScheduleProvider).rangesForWeekday(
              DateTime.monday,
            ),
        hasLength(3),
      );
      await Future<void>.delayed(Duration.zero);

      final loaded = container.read(weeklyWorkScheduleProvider);

      expect(loaded.activeWeekdayCount, 6);
      expect(loaded.rangesForWeekday(DateTime.sunday), isEmpty);
    });

    test('persists normalized day ranges through the notifier', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(weeklyWorkScheduleNotifierProvider.notifier)
          .setDayRanges(
        DateTime.wednesday,
        const <WorkTimeRange>[
          WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60),
          WorkTimeRange(startMinute: 9 * 60 + 30, endMinute: 11 * 60),
          WorkTimeRange(startMinute: 20 * 60, endMinute: 19 * 60),
        ],
      );

      final saved = await db.getSetting('scheduler.weekly_work_schedule.v1');
      final reloaded = WeeklyWorkSchedule.fromJsonString(saved!);

      expect(reloaded.rangesForWeekday(DateTime.wednesday), hasLength(1));
      expect(
        reloaded.summaryForWeekday(DateTime.wednesday),
        contains('09:00-11:00'),
      );
    });
  });
}
