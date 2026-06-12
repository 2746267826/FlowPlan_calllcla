import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/settings/presentation/settings_page.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/features/task/presentation/task_detail_page.dart';
import 'package:flowplanv2/features/task/presentation/unscheduled_task_panel.dart';
import 'package:flowplanv2/features/task/presentation/widgets/task_tracker_evidence_section.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/input_activity_event_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('unscheduled panel highlights accepted drags and opens details',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final taskListId = await insertFixtureTaskList(db);
    final unscheduledId = await TaskRepository(db).create(
      fixtureTask(
        uid: 'gap7-unscheduled',
        summary: 'Gap7 unscheduled',
        taskListId: taskListId,
      ),
      audit: false,
    );
    final unscheduled = await TaskRepository(db).getById(unscheduledId);
    final scheduled = unscheduled!.copyWith(
      id: 777,
      uid: 'gap7-scheduled-drag',
      summary: 'Scheduled drag source',
      dtstart: Value(DateTime.utc(2026, 6, 11, 9)),
    );

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: const Size(820, 760),
      overrides: <Override>[
        allTasksProvider.overrideWith(
          (ref) => Stream.value(<TaskItem>[unscheduled]),
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream.value(<TaskList>[]),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              Draggable<TaskItem>(
                data: scheduled,
                feedback: const Material(child: Text('dragging')),
                child: const SizedBox(
                  width: 120,
                  height: 80,
                  child: Text('drag source'),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 320,
                child: UnscheduledTaskPanel(
                  detailBuilder: (context, task) => Dialog(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('detail ${task.id} ${task.summary}'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(
      find.text('drag source'),
    ));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(UnscheduledTaskPanel)));
    await tester.pump();

    final highlightedContainer = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) => container.constraints?.maxWidth == 320)
        .single;
    final decoration = highlightedContainer.decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);

    await gesture.moveTo(const Offset(10, 10));
    await tester.pump();
    await gesture.up();
    await _pumpFrames(tester, 2);
    await tester.tap(find.text('Gap7 unscheduled'));
    await _pumpFrames(tester, 8);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('detail $unscheduledId Gap7 unscheduled'), findsOneWidget);
  });

  testWidgets('task detail shows task-list errors and close pop branches',
      (tester) async {
    await _pumpTaskDetailOnRouter(
      tester,
      overrides: <Override>[
        allTaskListsProvider.overrideWith(
          (ref) => Stream<List<TaskList>>.error(StateError('lists failed')),
        ),
      ],
    );
    await tester.pump();

    expect(find.textContaining('lists failed'), findsOneWidget);
    await _tapTaskDetailCloseButton(tester);
    await _pumpFrames(tester);
    expect(find.text('host route'), findsOneWidget);
    await _disposeTestApp(tester);

    final db = createTestDatabase();
    addTearDown(db.close);
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (context) => const TaskDetailPage(taskId: null),
                );
              },
              child: const Text('open dialog detail'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpFlowPlanTestApp(
      tester,
      db: db,
      child: MaterialApp.router(routerConfig: router),
    );
    await tester.pump();
    expect(find.text('open dialog detail'), findsOneWidget);
    await tester.tap(find.text('open dialog detail'));
    await _pumpFrames(tester);
    expect(find.byType(TaskDetailPage), findsOneWidget);

    await _tapTaskDetailCloseButton(tester);
    await _pumpFrames(tester, 8);

    expect(find.byType(TaskDetailPage), findsNothing);
    expect(find.text('open dialog detail'), findsOneWidget);
    await _disposeTestApp(tester);
  });

  testWidgets('evidence record navigation selects the day while events load',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final taskListId = await insertFixtureTaskList(db);
    final taskId = await TaskRepository(db).create(
      fixtureTask(
        uid: 'gap7-evidence-task',
        summary: 'Gap7 evidence task',
        taskListId: taskListId,
      ),
      audit: false,
    );
    await db.into(db.activityRecords).insert(
          ActivityRecordsCompanion.insert(
            startTime: DateTime.utc(2026, 6, 10, 14),
            endTime: Value(DateTime.utc(2026, 6, 10, 14, 25)),
            durationMinutes: const Value(25),
            processName: const Value('Code.exe'),
            category: const Value('coding'),
            linkedTaskId: Value(taskId),
            keyCount: const Value(4),
            source: const Value('test'),
          ),
        );

    final router = GoRouter(
      initialLocation: '/evidence',
      routes: <RouteBase>[
        GoRoute(
          path: '/evidence',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
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
                body: Text(
                  'tracker ${selected.year}-${selected.month}-${selected.day}',
                ),
              );
            },
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: const Size(1000, 1000),
      overrides: <Override>[
        inputActivityEventServiceProvider.overrideWithValue(
          _LoadingRecentInputService(db),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
    await _pumpFrames(tester, 6);

    expect(find.byType(TaskTrackerEvidenceSection), findsOneWidget);
    expect(find.textContaining('读取'), findsWidgets);

    await tester.tap(find.byIcon(Icons.travel_explore_outlined));
    await _pumpFrames(tester, 6);

    expect(find.text('tracker 2026-6-10'), findsOneWidget);
    await _disposeTestApp(tester);
  });

  testWidgets('settings Android section routes to mobile sync status',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const SettingsPage(isAndroidOverride: true),
        ),
        GoRoute(
          path: AppRoutes.outlookSync,
          builder: (context, state) =>
              const Scaffold(body: Text('outlook sync route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: const Size(900, 1200),
      overrides: <Override>[
        reminderServiceProvider.overrideWithValue(_Gap7ReminderService(db)),
        reminderSystemStatusProvider.overrideWith(
          (ref) async => const ReminderSystemStatus(
            platformLabel: 'Android',
            runtimeScannerEnabled: true,
            supportsSystemSchedule: true,
            canScheduleExactAlarms: true,
            pendingSystemReminderCount: 0,
            lastRebuiltAt: null,
          ),
        ),
        androidUsageAccessStatusProvider.overrideWith((ref) async => true),
        deviceIdentityDisplayProvider.overrideWith(
          (ref) async => 'device-gap7',
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
    await _pumpFrames(tester, 6);

    expect(find.byIcon(Icons.phone_android_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.cloud_done_outlined));
    await _pumpFrames(tester, 6);

    expect(find.text('outlook sync route'), findsOneWidget);
    await _disposeTestApp(tester);
  });

  test('desktop-only settings stay false with a non-Windows override',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        minimizeToTrayNotifierProvider.overrideWith(
          (ref) => MinimizeToTrayNotifier(ref, isWindowsOverride: false),
        ),
        launchAtStartupNotifierProvider.overrideWith(
          (ref) => LaunchAtStartupNotifier(ref, isWindowsOverride: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(minimizeToTrayProvider), isFalse);
    expect(container.read(launchAtStartupProvider), isFalse);

    await container.read(minimizeToTrayNotifierProvider.notifier).set(true);
    await container.read(launchAtStartupNotifierProvider.notifier).set(true);

    expect(container.read(minimizeToTrayProvider), isFalse);
    expect(container.read(launchAtStartupProvider), isFalse);
  });
}

Future<void> _pumpTaskDetailOnRouter(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
}) async {
  final db = createTestDatabase();
  addTearDown(db.close);
  final router = GoRouter(
    initialLocation: '/host/detail',
    routes: <RouteBase>[
      GoRoute(
        path: '/host',
        builder: (context, state) => const Scaffold(body: Text('host route')),
        routes: <RouteBase>[
          GoRoute(
            path: 'detail',
            builder: (context, state) => const TaskDetailPage(taskId: null),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(900, 1100),
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapTaskDetailCloseButton(WidgetTester tester) async {
  final closeButton = find.descendant(
    of: find.byType(AppBar),
    matching: find.byIcon(Icons.close),
  );
  expect(closeButton, findsOneWidget);
  await tester.tap(closeButton);
}

Future<void> _disposeTestApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 1));
}

class _LoadingRecentInputService extends InputActivityEventService {
  _LoadingRecentInputService(super.database);

  @override
  Future<InputHeatmapSummary> buildHeatmapSummaryForTask(int taskId) async {
    final base = DateTime.utc(2026, 6, 10, 14);
    return InputHeatmapSummary(
      query: InputEventQuery(
        start: base,
        end: base.add(const Duration(minutes: 25)),
      ),
      totalEventCount: 3,
      activeMinuteCount: 1,
      keyboardEventCount: 2,
      mouseButtonEventCount: 1,
      wheelEventCount: 0,
      mouseMoveEventCount: 0,
      mouseMoveDistance: 0,
      keyCounts: const <int, int>{65: 2},
      mouseCounts: const <String, int>{'left': 1},
      topKeys: const <InputKeyStat>[
        InputKeyStat(keyCode: 65, label: 'A', count: 2, share: 0.67),
      ],
      processIntensities: const <InputProcessIntensity>[],
      hourlyDistribution: List<InputHourDistributionBucket>.generate(
        24,
        (hour) => InputHourDistributionBucket(
          hour: hour,
          totalEvents: hour == 14 ? 3 : 0,
          keyEvents: hour == 14 ? 2 : 0,
          mouseButtonEvents: hour == 14 ? 1 : 0,
          wheelEvents: 0,
          mouseMoveEvents: 0,
          moveDistance: 0,
          activeMinutes: hour == 14 ? 1 : 0,
          intensityScore: hour == 14 ? 3 : 0,
        ),
      ),
    );
  }

  @override
  Future<List<TrackedInputEvent>> listRecentEventsForTask(
    int taskId, {
    int limit = 8,
  }) {
    return Completer<List<TrackedInputEvent>>().future;
  }
}

class _Gap7ReminderService extends ReminderService {
  _Gap7ReminderService(AppDatabase db)
      : super(
          database: db,
          defaultEventReminderMinutes: () => 15,
        );

  @override
  Future<ReminderRebuildResult> rebuildSystemSchedule() async {
    return const ReminderRebuildResult(
      scheduledCount: 0,
      canScheduleExactAlarms: true,
    );
  }

  @override
  Future<ReminderSystemStatus> getSystemStatus() async {
    return const ReminderSystemStatus(
      platformLabel: 'test',
      runtimeScannerEnabled: true,
      supportsSystemSchedule: true,
      canScheduleExactAlarms: true,
      pendingSystemReminderCount: 0,
      lastRebuiltAt: null,
    );
  }
}
