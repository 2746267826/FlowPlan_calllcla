import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/input_activity_event_service.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  RawInputEvent rawEvent({
    required int sequenceId,
    required DateTime at,
    required RawInputEventKind kind,
    int eventCount = 1,
    int? keyCode,
    String? processName,
    String? className,
    String? windowTitle,
    String? mouseButton,
    int wheelDelta = 0,
    int deltaX = 0,
    int deltaY = 0,
    int moveDistance = 0,
    String? tokenText,
  }) {
    return RawInputEvent(
      sequenceId: sequenceId,
      timestampMicros: at.microsecondsSinceEpoch,
      kind: kind,
      eventCount: eventCount,
      keyCode: keyCode,
      processName: processName,
      className: className,
      windowTitle: windowTitle,
      mouseButton: mouseButton,
      wheelDelta: wheelDelta,
      deltaX: deltaX,
      deltaY: deltaY,
      moveDistance: moveDistance,
      tokenText: tokenText,
    );
  }

  Future<void> insertTrackedInputEventRow(
    AppDatabase db, {
    required String eventUid,
    required int sequenceId,
    required DateTime at,
    String kind = 'key_down',
    String? processName = 'Code.exe',
    String? className,
    String? windowTitle,
    String? category = 'coding',
    String? activityLabel = 'Implementation',
    bool isIgnored = false,
    int? keyCode = 65,
    String? keyLabel = 'A',
    String? mouseButton,
    int wheelDelta = 0,
    int deltaX = 0,
    int deltaY = 0,
    int moveDistance = 0,
    int eventCount = 1,
    String? tokenText,
    String payloadJson = '{}',
  }) async {
    await db.customStatement(
      '''
      INSERT INTO tracked_input_events (
        event_uid,
        sequence_id,
        occurred_at,
        day_key,
        event_kind,
        record_id,
        process_name,
        class_name,
        window_title,
        category,
        activity_label,
        is_ignored,
        key_code,
        key_label,
        mouse_button,
        wheel_delta,
        delta_x,
        delta_y,
        move_distance,
        event_count,
        token_text,
        payload_json,
        created_at
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        eventUid,
        sequenceId,
        at.toIso8601String(),
        '${at.year.toString().padLeft(4, '0')}-'
            '${at.month.toString().padLeft(2, '0')}-'
            '${at.day.toString().padLeft(2, '0')}',
        kind,
        processName,
        className,
        windowTitle,
        category,
        activityLabel,
        isIgnored ? 1 : 0,
        keyCode,
        keyLabel,
        mouseButton,
        wheelDelta,
        deltaX,
        deltaY,
        moveDistance,
        eventCount,
        tokenText,
        payloadJson,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  test('appendEvents orders raw events, binds context, and archives them',
      () async {
    final storage = await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = InputActivityEventService(db);
    final base = DateTime(2026, 6, 9, 9);

    await service.appendEvents(
      events: <RawInputEvent>[
        rawEvent(
          sequenceId: 3,
          at: base.add(const Duration(seconds: 2)),
          kind: RawInputEventKind.mouseMove,
          eventCount: 2,
          processName: 'FlowPlanV2.exe',
          windowTitle: 'FlowPlanV2 dashboard',
          moveDistance: 240,
        ),
        rawEvent(
          sequenceId: 2,
          at: base.add(const Duration(seconds: 1)),
          kind: RawInputEventKind.mouseButtonDown,
          eventCount: 3,
          processName: ' Chrome.exe ',
          className: ' Chrome_WidgetWin_1 ',
          windowTitle: 'Research - Browser',
          mouseButton: ' left ',
        ),
        rawEvent(
          sequenceId: 1,
          at: base,
          kind: RawInputEventKind.keyDown,
          keyCode: 65,
          tokenText: 'a',
        ),
      ],
      bindings: const <InputEventContextBinding>[
        InputEventContextBinding(
          recordId: 7,
          processName: 'Code.exe',
          className: 'Editor',
          windowTitle: 'main.dart',
          category: 'coding',
          activityLabel: 'Implementation',
        ),
        InputEventContextBinding(
          recordId: 8,
          processName: 'Chrome.exe',
          className: 'Chrome_WidgetWin_1',
          windowTitle: 'Research',
          category: 'browser',
          activityLabel: 'Research',
        ),
      ],
    );

    final allEvents = await service.listEvents(includeIgnored: true);
    expect(allEvents.map((event) => event.sequenceId), <int>[1, 2, 3]);
    expect(allEvents[0].recordId, 7);
    expect(allEvents[0].processName, 'Code.exe');
    expect(allEvents[0].category, 'coding');
    expect(allEvents[0].keyLabel, 'A');
    expect(allEvents[1].recordId, 8);
    expect(allEvents[1].processName, 'Chrome.exe');
    expect(allEvents[1].className, 'Chrome_WidgetWin_1');
    expect(allEvents[1].mouseButton, 'left');
    expect(allEvents[2].isIgnored, isTrue);
    expect(allEvents[2].recordId, isNull);
    expect(allEvents[2].category, isNull);

    final visibleEvents = await service.listEvents();
    expect(visibleEvents.map((event) => event.sequenceId), <int>[1, 2]);

    final archiveDirectoryPath = await service.getArchiveDirectoryPath();
    expect(archiveDirectoryPath, startsWith(storage.path));
    final archiveDays = await service.listArchiveDays();
    expect(archiveDays.single.dayKey, '2026-06-09');
    expect(archiveDays.single.fileSizeBytes, greaterThan(0));

    final archivedEvents = await service.readArchivedEventsForDate(base);
    expect(archivedEvents.map((event) => event.sequenceId), <int>[1, 2, 3]);
  });

  test('buildHeatmapSummary filters ignored events and aggregates input stats',
      () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = InputActivityEventService(db);
    final base = DateTime(2026, 6, 9, 10, 15);

    await service.appendEvents(
      events: <RawInputEvent>[
        rawEvent(
          sequenceId: 1,
          at: base,
          kind: RawInputEventKind.keyDown,
          eventCount: 5,
          keyCode: 65,
        ),
        rawEvent(
          sequenceId: 2,
          at: base.add(const Duration(minutes: 1)),
          kind: RawInputEventKind.mouseButtonDown,
          eventCount: 2,
          mouseButton: 'left',
        ),
        rawEvent(
          sequenceId: 3,
          at: base.add(const Duration(minutes: 2)),
          kind: RawInputEventKind.mouseWheel,
          eventCount: 4,
          mouseButton: 'wheel_down',
          wheelDelta: -120,
        ),
        rawEvent(
          sequenceId: 4,
          at: base.add(const Duration(minutes: 3)),
          kind: RawInputEventKind.mouseMove,
          moveDistance: 320,
        ),
        rawEvent(
          sequenceId: 5,
          at: base.add(const Duration(minutes: 4)),
          kind: RawInputEventKind.keyDown,
          eventCount: 99,
          keyCode: 66,
          processName: 'FlowPlanV2.exe',
        ),
      ],
      bindings: const <InputEventContextBinding>[
        InputEventContextBinding(
          recordId: 9,
          processName: 'Code.exe',
          category: 'coding',
          activityLabel: 'Implementation',
        ),
      ],
    );

    final summary = await service.buildHeatmapSummary(
      InputEventQuery(
        start: DateTime(2026, 6, 9),
        end: DateTime(2026, 6, 10),
        processName: 'Code.exe',
      ),
    );

    expect(summary.totalEventCount, 12);
    expect(summary.activeMinuteCount, 4);
    expect(summary.keyboardEventCount, 5);
    expect(summary.mouseButtonEventCount, 2);
    expect(summary.wheelEventCount, 4);
    expect(summary.mouseMoveEventCount, 1);
    expect(summary.mouseMoveDistance, 320);
    expect(summary.keyCounts, <int, int>{65: 5});
    expect(summary.mouseCounts, <String, int>{'left': 2, 'wheel_down': 4});
    expect(summary.leadingKey?.label, 'A');
    expect(summary.leadingKey?.share, 1);
    expect(summary.leadingProcessIntensity?.processName, 'Code.exe');
    expect(summary.leadingProcessIntensity?.intensityScore, 47);
    expect(summary.hourlyDistribution[10].totalEvents, 12);
    expect(summary.hourlyDistribution[10].intensityScore, 47);

    final filtered = await service.listEvents(
      category: 'coding',
      eventKind: 'key_down',
      limit: 10,
    );
    expect(filtered.map((event) => event.sequenceId), <int>[1]);
    expect(await service.listProcessNames(), <String>['Code.exe']);
  });

  test('task summaries, archive backfill, malformed archive reads, and export',
      () async {
    final storage = await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = InputActivityEventService(db);
    final base = DateTime(2026, 6, 10, 14);

    await db.customStatement(
      '''
      INSERT INTO activity_records (
        id,
        start_time,
        end_time,
        duration_minutes,
        key_count,
        mouse_clicks,
        mouse_move_px,
        scroll_px,
        linked_task_id,
        is_auto,
        source
      ) VALUES (?, ?, ?, ?, 0, 0, 0, 0, ?, 1, ?)
      ''',
      <Object?>[
        101,
        base.toIso8601String(),
        base.add(const Duration(minutes: 5)).toIso8601String(),
        5,
        77,
        'auto',
      ],
    );

    await service.appendEvents(
      events: <RawInputEvent>[
        rawEvent(
          sequenceId: 10,
          at: base,
          kind: RawInputEventKind.keyDown,
          keyCode: 67,
        ),
        rawEvent(
          sequenceId: 11,
          at: base.add(const Duration(seconds: 30)),
          kind: RawInputEventKind.mouseMove,
          eventCount: 2,
          moveDistance: 480,
        ),
      ],
      bindings: const <InputEventContextBinding>[
        InputEventContextBinding(
          recordId: 101,
          processName: 'Code.exe',
          category: 'coding',
        ),
      ],
    );

    final taskSummary = await service.buildHeatmapSummaryForTask(77);
    expect(taskSummary.totalEventCount, 3);
    expect(taskSummary.keyboardEventCount, 1);
    expect(taskSummary.mouseMoveDistance, 480);

    final recentForTask = await service.listRecentEventsForTask(77, limit: 1);
    expect(recentForTask.single.sequenceId, 11);

    final exportFile =
        File('${storage.path}${Platform.pathSeparator}events.jsonl');
    await service.exportEventsToJsonl(
      exportFile.path,
      processName: 'Code.exe',
      includeIgnored: false,
    );
    final exportedLines = await exportFile.readAsLines();
    expect(exportedLines, hasLength(2));
    expect(
        jsonDecode(exportedLines.first), containsPair('eventUid', isNotEmpty));

    final archiveDirectory = Directory(await service.getArchiveDirectoryPath());
    final archiveFile = File(
      '${archiveDirectory.path}${Platform.pathSeparator}2026-06-10.input-events.jsonl',
    );
    await archiveFile.delete();
    final restoredEvents = await service.readArchivedEventsForDate(base);
    expect(restoredEvents.map((event) => event.sequenceId), <int>[10, 11]);
    expect(await archiveFile.exists(), isTrue);

    await archiveFile.writeAsString(
      'not-json\n${jsonEncode(restoredEvents.first.toJson())}\n\n',
      flush: true,
    );
    final sanitizedEvents = await service.readArchivedEventsForDate(base);
    expect(sanitizedEvents.single.eventUid, restoredEvents.first.eventUid);
  });

  test(
      'listEvents clamps pagination, filters bounds, and uses payload fallback',
      () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = InputActivityEventService(db);
    final base = DateTime(2026, 6, 11, 9);

    await insertTrackedInputEventRow(
      db,
      eventUid: 'before-window',
      sequenceId: 1,
      at: base.subtract(const Duration(minutes: 1)),
    );
    await insertTrackedInputEventRow(
      db,
      eventUid: 'first-in-window',
      sequenceId: 2,
      at: base,
    );
    await insertTrackedInputEventRow(
      db,
      eventUid: 'payload-token-fallback',
      sequenceId: 3,
      at: base.add(const Duration(minutes: 1)),
      tokenText: null,
      payloadJson: jsonEncode(<String, Object?>{
        'tokenText': 'fallback-token',
      }),
    );
    await insertTrackedInputEventRow(
      db,
      eventUid: 'wrong-kind',
      sequenceId: 4,
      at: base.add(const Duration(minutes: 2)),
      kind: 'mouse_button_down',
      keyCode: null,
      keyLabel: null,
      mouseButton: 'left',
    );
    await insertTrackedInputEventRow(
      db,
      eventUid: 'ignored-match',
      sequenceId: 5,
      at: base.add(const Duration(minutes: 3)),
      isIgnored: true,
    );
    await insertTrackedInputEventRow(
      db,
      eventUid: 'end-exclusive',
      sequenceId: 6,
      at: base.add(const Duration(minutes: 4)),
    );
    await insertTrackedInputEventRow(
      db,
      eventUid: 'wrong-process',
      sequenceId: 7,
      at: base.add(const Duration(minutes: 1)),
      processName: 'Chrome.exe',
      category: 'browser',
    );

    final clampedPage = await service.listEvents(
      limit: 0,
      offset: -10,
      includeIgnored: true,
    );
    expect(clampedPage.map((event) => event.sequenceId), <int>[1]);

    final filtered = await service.listEvents(
      start: base,
      end: base.add(const Duration(minutes: 4)),
      processName: ' Code.exe ',
      category: 'coding',
      eventKind: ' key_down ',
      includeIgnored: true,
      limit: 10,
      offset: 1,
    );

    expect(filtered.map((event) => event.sequenceId), <int>[3, 5]);
    expect(filtered.first.tokenText, 'fallback-token');

    final visibleOnly = await service.listEvents(
      start: base,
      end: base.add(const Duration(minutes: 4)),
      processName: 'Code.exe',
      category: 'coding',
      eventKind: 'key_down',
    );
    expect(visibleOnly.map((event) => event.sequenceId), <int>[2, 3]);
  });

  test('appendEvents splits large batches and archives every event', () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = InputActivityEventService(db);
    final base = DateTime(2026, 6, 12, 8);

    final rawEvents = List<RawInputEvent>.generate(45, (index) {
      final sequenceId = index + 1;
      return rawEvent(
        sequenceId: sequenceId,
        at: base.add(Duration(seconds: sequenceId)),
        kind: RawInputEventKind.keyDown,
        keyCode: 65 + (index % 26),
        eventCount: 1 + (index % 3),
      );
    }).reversed.toList(growable: false);

    await service.appendEvents(
      events: rawEvents,
      bindings: const <InputEventContextBinding>[
        InputEventContextBinding(
          recordId: 42,
          processName: 'Code.exe',
          category: 'coding',
          activityLabel: 'Implementation',
        ),
      ],
    );

    final events = await service.listEvents(limit: 100);
    expect(events, hasLength(45));
    expect(events.map((event) => event.sequenceId),
        List<int>.generate(45, (i) => i + 1));
    expect(events.every((event) => event.recordId == 42), isTrue);

    final archived = await service.readArchivedEventsForDate(base);
    expect(archived, hasLength(45));
    expect(archived.map((event) => event.sequenceId),
        List<int>.generate(45, (i) => i + 1));
  });

  test('appendEvents scores bindings by process, class, and title', () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = InputActivityEventService(db);
    final base = DateTime(2026, 6, 13, 11);

    await service.appendEvents(
      events: <RawInputEvent>[
        rawEvent(
          sequenceId: 1,
          at: base,
          kind: RawInputEventKind.keyDown,
          processName: 'Browser.exe',
          className: 'Editor',
          windowTitle: 'Document - Browser',
          keyCode: 65,
        ),
        rawEvent(
          sequenceId: 2,
          at: base.add(const Duration(seconds: 1)),
          kind: RawInputEventKind.keyDown,
          className: 'Editor',
          windowTitle: 'Document - Editor',
          keyCode: 66,
        ),
        rawEvent(
          sequenceId: 3,
          at: base.add(const Duration(seconds: 2)),
          kind: RawInputEventKind.keyDown,
          processName: 'Unknown.exe',
          windowTitle: 'No matching context',
          keyCode: 67,
        ),
      ],
      bindings: const <InputEventContextBinding>[
        InputEventContextBinding(
          recordId: 10,
          processName: 'Editor.exe',
          className: 'Editor',
          windowTitle: 'Document',
          category: 'coding',
        ),
        InputEventContextBinding(
          recordId: 20,
          processName: 'Browser.exe',
          className: 'BrowserFrame',
          windowTitle: 'Research',
          category: 'browser',
        ),
      ],
    );

    final events = await service.listEvents(includeIgnored: true);

    expect(events[0].recordId, 20);
    expect(events[0].category, 'browser');
    expect(events[0].processName, 'Browser.exe');
    expect(events[1].recordId, 10);
    expect(events[1].category, 'coding');
    expect(events[1].processName, 'Editor.exe');
    expect(events[2].recordId, isNull);
    expect(events[2].processName, 'Unknown.exe');
    expect(events[2].category, isNull);
  });

  test('testing helpers decode legacy payload maps and invalid day keys',
      () async {
    await setUpTempAppStorage();
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = InputActivityEventService(db);

    final payload = service.debugDecodePayloadJsonForTesting('{"deltaX":4}');
    final invalidDay =
        InputActivityEventService.debugParseDayKeyForTesting('bad-day-key');

    expect(payload, <String, dynamic>{'deltaX': 4});
    expect(invalidDay.year, 1970);
    expect(invalidDay.month, 1);
    expect(invalidDay.day, 1);
  });
}
