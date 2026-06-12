import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ActivityRecord record({
    required int id,
    required DateTime start,
    int durationMinutes = 5,
    String? manualLabel,
    String? processName = 'Code.exe',
    String? windowTitle,
    String? category = 'coding',
    int? linkedTaskId,
    int keyCount = 5,
    int mouseClicks = 1,
    int mouseMovePx = 100,
    int scrollPx = 0,
  }) {
    return ActivityRecord(
      id: id,
      startTime: start,
      endTime: start.add(Duration(minutes: durationMinutes)),
      durationMinutes: durationMinutes,
      keyCount: keyCount,
      mouseClicks: mouseClicks,
      mouseMovePx: mouseMovePx,
      scrollPx: scrollPx,
      manualLabel: manualLabel,
      processName: processName,
      windowTitle: windowTitle,
      category: category,
      linkedTaskId: linkedTaskId,
      isAuto: true,
      source: 'test',
    );
  }

  group('WorkSessionGrouper', () {
    test('session getters expose single-context and raw override values', () {
      final start = DateTime(2026, 6, 14, 8);
      final first = record(id: 1, start: start);
      final session = WorkSession(
        startTime: start,
        endTime: start.add(const Duration(minutes: 5)),
        label: 'coding - Code.exe',
        processName: 'Code.exe',
        category: 'coding',
        records: <ActivityRecord>[first],
        durationMinutes: 5,
        keyCount: 5,
        mouseClicks: 1,
        mouseMovePx: 100,
        scrollPx: 0,
        processNames: const <String>['Code.exe'],
        categories: const <String>['coding'],
        interruptionCount: 0,
        rawRecordCountOverride: 3,
      );

      expect(session.rawRecordCount, 3);
      expect(session.spansMultipleProcesses, isFalse);
      expect(session.spansMultipleCategories, isFalse);
    });

    test('merges nearby records with matching strict or context signatures',
        () {
      final base = DateTime(2026, 6, 14, 9);

      final sessions = WorkSessionGrouper.fromRecords(<ActivityRecord>[
        record(
          id: 1,
          start: base,
          processName: 'Code.exe',
          category: 'coding',
          keyCount: 20,
        ),
        record(
          id: 2,
          start: base.add(const Duration(minutes: 7)),
          processName: 'Code.exe',
          category: 'coding',
          keyCount: 10,
        ),
        record(
          id: 3,
          start: base.add(const Duration(minutes: 12)),
          processName: 'Terminal.exe',
          category: 'coding',
          keyCount: 8,
        ),
        record(
          id: 4,
          start: base.add(const Duration(minutes: 25)),
          processName: 'Browser.exe',
          category: 'research',
        ),
      ]);

      expect(sessions, hasLength(2));
      expect(sessions.first.records.map((item) => item.id), <int>[1, 2, 3]);
      expect(sessions.first.startTime, base);
      expect(sessions.first.endTime, base.add(const Duration(minutes: 17)));
      expect(sessions.first.keyCount, 38);
      expect(sessions.first.processNames, <String>['Code.exe', 'Terminal.exe']);
      expect(sessions.first.category, 'coding');
      expect(sessions.first.spansMultipleProcesses, isTrue);
      expect(sessions.last.records.single.id, 4);
    });

    test('bridges a short interruption run between same-context work', () {
      final base = DateTime(2026, 6, 14, 10);

      final sessions = WorkSessionGrouper.fromRecords(<ActivityRecord>[
        record(
          id: 1,
          start: base,
          processName: 'Code.exe',
          category: 'coding',
          keyCount: 30,
        ),
        record(
          id: 2,
          start: base.add(const Duration(minutes: 6)),
          durationMinutes: 2,
          processName: 'Chat.exe',
          category: 'communication',
          keyCount: 1,
          mouseClicks: 1,
        ),
        record(
          id: 3,
          start: base.add(const Duration(minutes: 10)),
          processName: 'Terminal.exe',
          category: 'coding',
          keyCount: 24,
        ),
      ]);

      expect(sessions, hasLength(1));
      expect(sessions.single.records.map((item) => item.id), <int>[1, 2, 3]);
      expect(sessions.single.interruptionCount, 1);
      expect(sessions.single.category, 'coding');
      expect(sessions.single.categories, <String>['coding', 'communication']);
      expect(sessions.single.spansMultipleCategories, isTrue);
    });

    test('does not bridge long or heavy interruptions', () {
      final base = DateTime(2026, 6, 14, 11);

      final sessions = WorkSessionGrouper.fromRecords(<ActivityRecord>[
        record(
          id: 1,
          start: base,
          processName: 'Code.exe',
          category: 'coding',
        ),
        record(
          id: 2,
          start: base.add(const Duration(minutes: 6)),
          durationMinutes: 4,
          processName: 'Chat.exe',
          category: 'communication',
          keyCount: 40,
          mouseClicks: 5,
        ),
        record(
          id: 3,
          start: base.add(const Duration(minutes: 12)),
          processName: 'Terminal.exe',
          category: 'coding',
        ),
      ]);

      expect(sessions, hasLength(3));
      expect(
          sessions.map((session) => session.records.single.id), <int>[1, 2, 3]);
      expect(
          sessions.every((session) => session.interruptionCount == 0), isTrue);
    });

    test('ignores tracker self records and bridges same-context ignored gaps',
        () {
      final base = DateTime(2026, 6, 14, 12);

      final sessions = WorkSessionGrouper.fromRecords(<ActivityRecord>[
        record(
          id: 1,
          start: base,
          processName: 'Code.exe',
          category: 'coding',
        ),
        record(
          id: 2,
          start: base.add(const Duration(minutes: 6)),
          durationMinutes: 2,
          processName: 'FlowPlanV2.exe',
          windowTitle: 'FlowPlanV2 dashboard',
          category: 'system',
        ),
        record(
          id: 3,
          start: base.add(const Duration(minutes: 10)),
          processName: 'Terminal.exe',
          category: 'coding',
        ),
      ]);

      expect(sessions, hasLength(1));
      expect(sessions.single.records.map((item) => item.id), <int>[1, 3]);
      expect(sessions.single.interruptionCount, 1);
      expect(sessions.single.rawRecordCount, 2);
    });

    test('drops sessions that only contain tracker self records', () {
      final base = DateTime(2026, 6, 14, 13);

      final sessions = WorkSessionGrouper.fromRecords(<ActivityRecord>[
        record(
          id: 1,
          start: base,
          processName: 'FlowPlanV2.exe',
          windowTitle: 'FlowPlanV2 dashboard',
          category: 'system',
        ),
        record(
          id: 2,
          start: base.add(const Duration(minutes: 3)),
          processName: 'Helper.exe',
          windowTitle: 'FlowPlanV2 helper',
          category: 'system',
        ),
      ]);

      expect(sessions, isEmpty);
    });

    test('testing helper exercises base-session merge path', () {
      final base = DateTime(2026, 6, 14, 14);

      final session = WorkSessionGrouper.debugMergeBaseSessionsForTesting(
        record(
          id: 1,
          start: base,
          processName: 'Code.exe',
          category: 'coding',
        ),
        record(
          id: 2,
          start: base.add(const Duration(minutes: 6)),
          processName: 'Code.exe',
          category: 'coding',
        ),
      );

      expect(session.records.map((item) => item.id), <int>[1, 2]);
      expect(session.processNames, <String>['Code.exe']);
      expect(session.category, 'coding');
    });
  });
}
