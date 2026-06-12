import 'dart:async';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/task/presentation/widgets/task_tracker_evidence_section.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/input_activity_event_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/test_database.dart';

void main() {
  testWidgets('renders loading, repository error, and no evidence states',
      (tester) async {
    final loading = await _pumpEvidenceSection(
      tester,
      recordsLoading: true,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(loading.records.watchTaskIds, <int>[42]);
    await loading.dispose();

    final errored = await _pumpEvidenceSection(
      tester,
      recordsError: StateError('records boom'),
    );
    await pumpFrames(tester);
    expect(find.text('追踪证据读取失败'), findsOneWidget);
    expect(find.textContaining('records boom'), findsOneWidget);
    await errored.dispose();

    final empty = await _pumpEvidenceSection(tester);
    await pumpFrames(tester);
    expect(find.text('追踪证据'), findsOneWidget);
    expect(find.text('暂时没有追踪证据'), findsOneWidget);
    expect(find.textContaining('当前任务还没有关联追踪记录'), findsOneWidget);
    expect(empty.input.summaryTaskIds, <int>[42]);
    expect(empty.input.recentTaskIds, <int>[42]);
    expect(empty.fusion.workLogTaskIds, <int>[42]);
  });

  testWidgets(
      'renders linked evidence, input events, work logs, and status tags',
      (tester) async {
    final base = DateTime(2026, 6, 9, 9);
    final harness = await _pumpEvidenceSection(
      tester,
      records: <ActivityRecord>[
        activityRecord(
          id: 1,
          start: base,
          durationMinutes: 45,
          manualLabel: 'Implementation burst',
          processName: 'Code.exe',
          category: 'coding',
          keyCount: 120,
          mouseClicks: 8,
          mouseMovePx: 900,
          scrollPx: 360,
        ),
        activityRecord(
          id: 2,
          start: base.add(const Duration(hours: 2)),
          durationMinutes: 30,
          manualLabel: 'Review pass',
          processName: 'Browser.exe',
          category: 'research',
          keyCount: 40,
          mouseClicks: 15,
          mouseMovePx: 400,
          scrollPx: 120,
        ),
      ],
      summary: inputSummary(
        totalEvents: 30,
        activeMinutes: 60,
        keyboardEvents: 20,
        pointerEvents: 10,
        topKeys: const <InputKeyStat>[
          InputKeyStat(keyCode: 65, label: 'A', count: 12, share: 0.4),
        ],
        leadingProcess: const InputProcessIntensity(
          processName: 'Code.exe',
          totalEvents: 30,
          keyEvents: 20,
          mouseButtonEvents: 6,
          wheelEvents: 4,
          mouseMoveEvents: 0,
          moveDistance: 0,
          activeMinutes: 60,
          intensityScore: 88,
        ),
      ),
      recentEvents: <TrackedInputEvent>[
        trackedEvent(
          uid: 'key-a',
          at: base.add(const Duration(minutes: 12, seconds: 3)),
          kind: TrackedInputEventKind.keyDown,
          keyLabel: 'A',
          processName: 'Code.exe',
          activityLabel: 'Implementation burst',
        ),
        trackedEvent(
          uid: 'wheel',
          at: base.add(const Duration(minutes: 13, seconds: 4)),
          kind: TrackedInputEventKind.mouseWheel,
          wheelDelta: -120,
          processName: 'Browser.exe',
          activityLabel: 'Review pass',
        ),
      ],
      workLogs: <TaskWorkLog>[
        taskWorkLog(
          id: 1,
          start: base,
          durationMinutes: 45,
          status: 'confirmed',
        ),
        taskWorkLog(
          id: 2,
          start: base.add(const Duration(hours: 2)),
          durationMinutes: 30,
          status: 'candidate',
        ),
      ],
    );
    await pumpFrames(tester);

    expect(find.text('累计追踪时长'), findsOneWidget);
    expect(find.text('1 小时 15 分钟'), findsOneWidget);
    expect(find.text('工作会话'), findsOneWidget);
    expect(find.text('2 段'), findsOneWidget);
    expect(find.text('按键与点击'), findsOneWidget);
    expect(find.text('160 键 / 23 次'), findsOneWidget);
    expect(find.text('输入事件'), findsOneWidget);
    expect(find.text('30 条'), findsOneWidget);
    expect(find.textContaining('主力应用：Code.exe、Browser.exe'), findsOneWidget);

    expect(find.text('输入行为证据'), findsOneWidget);
    expect(find.text('键盘占比 66.7%'), findsOneWidget);
    expect(find.text('指针占比 33.3%'), findsOneWidget);
    expect(find.textContaining('峰值时段 10:00-11:00'), findsOneWidget);
    expect(find.textContaining('主力应用 Code.exe'), findsOneWidget);
    expect(find.text('A 12 次'), findsOneWidget);
    expect(find.text('按键 A'), findsOneWidget);
    expect(find.textContaining('滚轮 -120'), findsOneWidget);

    expect(find.text('实际投入'), findsOneWidget);
    expect(find.text('已确认 45 分钟'), findsWidgets);
    expect(find.text('候选 30 分钟'), findsWidgets);
    expect(find.text('关联工作会话'), findsOneWidget);
    expect(find.text('最近关联的原始记录'), findsOneWidget);
    expect(find.text('Implementation burst'), findsWidgets);
    expect(find.text('Review pass'), findsWidgets);
    expect(find.textContaining('45 分钟'), findsWidgets);
    expect(find.textContaining('30 分钟'), findsWidgets);
    expect(find.textContaining('15 分钟'), findsWidgets);
    expect(harness.input.recentLimits, <int>[8]);
  });

  testWidgets('renders nested loading and error states for evidence panels',
      (tester) async {
    final base = DateTime(2026, 6, 9, 9);
    final loading = await _pumpEvidenceSection(
      tester,
      records: <ActivityRecord>[activityRecord(id: 1, start: base)],
      summaryLoading: true,
      workLogsLoading: true,
    );
    await pumpFrames(tester);
    expect(
      find.textContaining('正在汇总任务级输入行为分析'),
      findsOneWidget,
    );
    expect(
      find.textContaining('正在读取任务实际投入'),
      findsOneWidget,
    );
    await loading.dispose();

    final errored = await _pumpEvidenceSection(
      tester,
      records: <ActivityRecord>[activityRecord(id: 1, start: base)],
      summaryError: StateError('summary boom'),
      workLogsError: StateError('work log boom'),
    );
    await pumpFrames(tester);
    expect(find.textContaining('summary boom'), findsOneWidget);
    expect(find.textContaining('work log boom'), findsOneWidget);
    await errored.dispose();

    final recentErrored = await _pumpEvidenceSection(
      tester,
      records: <ActivityRecord>[activityRecord(id: 1, start: base)],
      summary:
          inputSummary(totalEvents: 2, keyboardEvents: 1, pointerEvents: 1),
      recentError: StateError('recent boom'),
    );
    await pumpFrames(tester);
    expect(find.textContaining('recent boom'), findsOneWidget);
    await recentErrored.dispose();
  });

  testWidgets('opens tracker routes with the evidence date selected',
      (tester) async {
    final base = DateTime(2026, 6, 9, 9);
    await _pumpEvidenceSection(
      tester,
      records: <ActivityRecord>[
        activityRecord(id: 1, start: base, durationMinutes: 15),
        activityRecord(
          id: 2,
          start: DateTime(2026, 6, 10, 14),
          durationMinutes: 20,
          processName: 'Browser.exe',
          category: 'research',
        ),
      ],
    );
    await pumpFrames(tester);

    await tester.tap(find.widgetWithText(TextButton, '打开追踪页'));
    await tester.pumpAndSettle();

    expect(find.text('tracker fallback 2026-06-10'), findsOneWidget);

    await tester.tap(find.text('back to evidence'));
    await tester.pumpAndSettle();
    await scrollToText(tester, '查看当天追踪');
    await tester.tap(find.widgetWithText(TextButton, '查看当天追踪').first);
    await tester.pumpAndSettle();

    expect(find.text('tracker fallback 2026-06-10'), findsOneWidget);
  });

  testWidgets('unlink button calls repository and refreshes input evidence',
      (tester) async {
    final base = DateTime(2026, 6, 9, 9);
    final harness = await _pumpEvidenceSection(
      tester,
      records: <ActivityRecord>[
        activityRecord(id: 7, start: base, durationMinutes: 20),
      ],
      summary:
          inputSummary(totalEvents: 3, keyboardEvents: 2, pointerEvents: 1),
      recentEvents: <TrackedInputEvent>[
        trackedEvent(uid: 'event-1', at: base, keyLabel: 'F'),
      ],
    );
    await pumpFrames(tester);

    expect(harness.input.summaryTaskIds, <int>[42]);
    expect(harness.input.recentTaskIds, <int>[42]);

    await scrollToText(tester, '取消关联');
    await tester.tap(find.widgetWithText(TextButton, '取消关联').first);
    await pumpFrames(tester, 8);

    expect(harness.records.linkCalls, <_LinkCall>[
      const _LinkCall(recordId: 7, taskId: null),
    ]);
    expect(harness.input.summaryTaskIds, hasLength(greaterThanOrEqualTo(2)));
    expect(harness.input.recentTaskIds, hasLength(greaterThanOrEqualTo(2)));
    expect(
      find.textContaining('已取消这条记录与当前任务的关联'),
      findsOneWidget,
    );
  });

  testWidgets('renders linked records with empty input and work log evidence',
      (tester) async {
    final base = DateTime(2026, 6, 9, 9);
    await _pumpEvidenceSection(
      tester,
      records: <ActivityRecord>[
        activityRecord(id: 1, start: base, durationMinutes: 5),
      ],
      summary: InputHeatmapSummary.empty(
        InputEventQuery(
          start: base,
          end: base.add(const Duration(minutes: 5)),
        ),
      ),
      recentEvents: const <TrackedInputEvent>[],
      workLogs: const <TaskWorkLog>[],
    );
    await pumpFrames(tester);

    expect(
      find.textContaining('还没有更细粒度的输入事件可供分析'),
      findsOneWidget,
    );
    expect(
      find.textContaining('还没有来自活动理解确认的任务实际投入'),
      findsOneWidget,
    );
  });
}

Future<_EvidenceHarness> _pumpEvidenceSection(
  WidgetTester tester, {
  int taskId = 42,
  List<ActivityRecord> records = const <ActivityRecord>[],
  Object? recordsError,
  bool recordsLoading = false,
  InputHeatmapSummary? summary,
  Object? summaryError,
  bool summaryLoading = false,
  List<TrackedInputEvent> recentEvents = const <TrackedInputEvent>[],
  Object? recentError,
  bool recentLoading = false,
  List<TaskWorkLog> workLogs = const <TaskWorkLog>[],
  Object? workLogsError,
  bool workLogsLoading = false,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = createTestDatabase();
  final recordsRepo = _FakeActivityRecordRepository(
    db,
    records: records,
    error: recordsError,
    loading: recordsLoading,
  );
  final inputService = _FakeInputActivityEventService(
    db,
    summary: summary,
    summaryError: summaryError,
    summaryLoading: summaryLoading,
    recentEvents: recentEvents,
    recentError: recentError,
    recentLoading: recentLoading,
  );
  final fusionRepo = _FakeActivityFusionRepository(
    db,
    workLogs: workLogs,
    error: workLogsError,
    loading: workLogsLoading,
  );
  late final GoRouter router;
  router = GoRouter(
    initialLocation: '/evidence',
    routes: <RouteBase>[
      GoRoute(
        path: '/evidence',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: TaskTrackerEvidenceSection(taskId: taskId),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.tracker,
        builder: (context, state) => Consumer(
          builder: (context, ref, child) {
            final selected = ref.watch(selectedDateProvider);
            return Scaffold(
              body: Column(
                children: <Widget>[
                  Text('tracker fallback ${formatDay(selected)}'),
                  TextButton(
                    onPressed: () => context.go('/evidence'),
                    child: const Text('back to evidence'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );

  final harness = _EvidenceHarness(
    db: db,
    router: router,
    records: recordsRepo,
    input: inputService,
    fusion: fusionRepo,
    tester: tester,
  );
  addTearDown(harness.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        activityRecordRepositoryProvider.overrideWithValue(recordsRepo),
        inputActivityEventServiceProvider.overrideWithValue(inputService),
        activityFusionRepositoryProvider.overrideWithValue(fusionRepo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  return harness;
}

ActivityRecord activityRecord({
  required int id,
  required DateTime start,
  int durationMinutes = 10,
  String? manualLabel,
  String? processName = 'Code.exe',
  String? windowTitle,
  String? category = 'coding',
  int? linkedTaskId = 42,
  int keyCount = 12,
  int mouseClicks = 3,
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

InputHeatmapSummary inputSummary({
  int totalEvents = 0,
  int activeMinutes = 0,
  int keyboardEvents = 0,
  int pointerEvents = 0,
  List<InputKeyStat> topKeys = const <InputKeyStat>[],
  InputProcessIntensity? leadingProcess,
}) {
  final base = DateTime(2026, 6, 9, 9);
  return InputHeatmapSummary(
    query: InputEventQuery(
      start: base,
      end: base.add(const Duration(hours: 2)),
    ),
    totalEventCount: totalEvents,
    activeMinuteCount: activeMinutes,
    keyboardEventCount: keyboardEvents,
    mouseButtonEventCount: pointerEvents,
    wheelEventCount: 0,
    mouseMoveEventCount: 0,
    mouseMoveDistance: 0,
    keyCounts: const <int, int>{65: 12},
    mouseCounts: const <String, int>{'left': 4},
    topKeys: topKeys,
    processIntensities: leadingProcess == null
        ? const <InputProcessIntensity>[]
        : <InputProcessIntensity>[leadingProcess],
    hourlyDistribution: List<InputHourDistributionBucket>.generate(
      24,
      (hour) => InputHourDistributionBucket(
        hour: hour,
        totalEvents: hour == 10 ? totalEvents : 0,
        keyEvents: hour == 10 ? keyboardEvents : 0,
        mouseButtonEvents: hour == 10 ? pointerEvents : 0,
        wheelEvents: 0,
        mouseMoveEvents: 0,
        moveDistance: 0,
        activeMinutes: hour == 10 && totalEvents > 0 ? activeMinutes : 0,
        intensityScore: hour == 10 ? totalEvents : 0,
      ),
    ),
  );
}

TrackedInputEvent trackedEvent({
  required String uid,
  required DateTime at,
  TrackedInputEventKind kind = TrackedInputEventKind.keyDown,
  String? keyLabel,
  String? processName,
  String? activityLabel,
  int wheelDelta = 0,
}) {
  return TrackedInputEvent(
    eventUid: uid,
    sequenceId: uid.hashCode.abs(),
    timestamp: at,
    kind: kind,
    keyLabel: keyLabel,
    processName: processName,
    activityLabel: activityLabel,
    wheelDelta: wheelDelta,
  );
}

TaskWorkLog taskWorkLog({
  required int id,
  required DateTime start,
  required int durationMinutes,
  required String status,
}) {
  final now = DateTime(2026, 6, 9, 12);
  return TaskWorkLog(
    id: id,
    workUid: 'work-$id',
    taskId: 42,
    segmentId: id,
    actualId: null,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
    durationMinutes: durationMinutes,
    confidence: 0.8,
    sourceType: 'test',
    evidenceJson: '{}',
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> pumpFrames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> scrollToText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await pumpFrames(tester, 2);
}

String formatDay(DateTime value) {
  final date = value.toLocal();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

class _EvidenceHarness {
  _EvidenceHarness({
    required this.db,
    required this.router,
    required this.records,
    required this.input,
    required this.fusion,
    required this.tester,
  });

  final AppDatabase db;
  final GoRouter router;
  final _FakeActivityRecordRepository records;
  final _FakeInputActivityEventService input;
  final _FakeActivityFusionRepository fusion;
  final WidgetTester tester;
  var _disposed = false;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await records.dispose();
    router.dispose();
    await db.close();
  }
}

class _FakeActivityRecordRepository extends ActivityRecordRepository {
  _FakeActivityRecordRepository(
    super.db, {
    List<ActivityRecord> records = const <ActivityRecord>[],
    this.error,
    this.loading = false,
  }) : _records = List<ActivityRecord>.from(records) {
    _controller = StreamController<List<ActivityRecord>>.broadcast(
      onListen: () => scheduleMicrotask(_emit),
    );
  }

  final Object? error;
  final bool loading;
  final List<int> watchTaskIds = <int>[];
  final List<_LinkCall> linkCalls = <_LinkCall>[];
  final List<ActivityRecord> _records;
  late final StreamController<List<ActivityRecord>> _controller;
  final StreamController<List<ActivityRecord>> _loadingController =
      StreamController<List<ActivityRecord>>.broadcast();

  @override
  Stream<List<ActivityRecord>> watchByTaskId(int taskId) {
    watchTaskIds.add(taskId);
    if (loading) {
      return _loadingController.stream;
    }
    final streamError = error;
    if (streamError != null) {
      return Stream<List<ActivityRecord>>.error(streamError);
    }
    return _controller.stream;
  }

  @override
  Future<void> linkTask(int recordId, int? taskId) async {
    linkCalls.add(_LinkCall(recordId: recordId, taskId: taskId));
    if (taskId == null) {
      _records.removeWhere((record) => record.id == recordId);
      _emit();
    }
  }

  Future<void> dispose() async {
    await _controller.close();
    await _loadingController.close();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List<ActivityRecord>.unmodifiable(_records));
    }
  }
}

class _FakeInputActivityEventService extends InputActivityEventService {
  _FakeInputActivityEventService(
    super.db, {
    this.summary,
    this.summaryError,
    this.summaryLoading = false,
    this.recentEvents = const <TrackedInputEvent>[],
    this.recentError,
    this.recentLoading = false,
  });

  final InputHeatmapSummary? summary;
  final Object? summaryError;
  final bool summaryLoading;
  final List<TrackedInputEvent> recentEvents;
  final Object? recentError;
  final bool recentLoading;
  final List<int> summaryTaskIds = <int>[];
  final List<int> recentTaskIds = <int>[];
  final List<int> recentLimits = <int>[];
  final Completer<InputHeatmapSummary> _summaryCompleter =
      Completer<InputHeatmapSummary>();
  final Completer<List<TrackedInputEvent>> _recentCompleter =
      Completer<List<TrackedInputEvent>>();

  @override
  Future<InputHeatmapSummary> buildHeatmapSummaryForTask(int taskId) async {
    summaryTaskIds.add(taskId);
    if (summaryLoading) {
      return _summaryCompleter.future;
    }
    final failure = summaryError;
    if (failure != null) {
      throw failure;
    }
    return summary ??
        InputHeatmapSummary.empty(
          InputEventQuery(
            start: DateTime(2026, 6, 9, 9),
            end: DateTime(2026, 6, 9, 10),
          ),
        );
  }

  @override
  Future<List<TrackedInputEvent>> listRecentEventsForTask(
    int taskId, {
    int limit = 10,
  }) async {
    recentTaskIds.add(taskId);
    recentLimits.add(limit);
    if (recentLoading) {
      return _recentCompleter.future;
    }
    final failure = recentError;
    if (failure != null) {
      throw failure;
    }
    return recentEvents;
  }
}

class _FakeActivityFusionRepository extends ActivityFusionRepository {
  _FakeActivityFusionRepository(
    super.db, {
    this.workLogs = const <TaskWorkLog>[],
    this.error,
    this.loading = false,
  });

  final List<TaskWorkLog> workLogs;
  final Object? error;
  final bool loading;
  final List<int> workLogTaskIds = <int>[];
  final Completer<List<TaskWorkLog>> _workLogsCompleter =
      Completer<List<TaskWorkLog>>();

  @override
  Future<List<TaskWorkLog>> listTaskWorkLogsForTask(
    int taskId, {
    int limit = 200,
    int offset = 0,
  }) async {
    workLogTaskIds.add(taskId);
    if (loading) {
      return _workLogsCompleter.future;
    }
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return workLogs;
  }
}

class _LinkCall {
  const _LinkCall({
    required this.recordId,
    required this.taskId,
  });

  final int recordId;
  final int? taskId;

  @override
  bool operator ==(Object other) {
    return other is _LinkCall &&
        other.recordId == recordId &&
        other.taskId == taskId;
  }

  @override
  int get hashCode => Object.hash(recordId, taskId);

  @override
  String toString() => '_LinkCall(recordId: $recordId, taskId: $taskId)';
}
