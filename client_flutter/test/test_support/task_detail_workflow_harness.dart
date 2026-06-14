import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/online/online_primary_policy.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/task/presentation/task_detail_page.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'provider_harness.dart';
import 'user_workflow_harness.dart';

const writableOnlinePrimaryPolicy = OnlinePrimaryPolicy(
  serverReachable: true,
  authenticated: true,
  level: ServerConnectionLevel.online,
);

Future<void> pumpTaskDetailWorkflow(
  WidgetTester tester, {
  required AppDatabase db,
  required int? taskId,
  required FakeTaskEventServerFirstStore fakeStore,
  List<TaskList>? taskListsOverride,
}) async {
  final taskLists = taskListsOverride ?? await db.select(db.taskLists).get();
  final router = GoRouter(
    initialLocation: taskId == null ? AppRoutes.taskCreate : '/task/$taskId',
    routes: [
      GoRoute(
        path: AppRoutes.timeline,
        builder: (context, state) => const Center(
          child: Text('timeline fallback'),
        ),
      ),
      GoRoute(
        path: AppRoutes.taskCreate,
        builder: (context, state) => const TaskDetailPage(taskId: null),
      ),
      GoRoute(
        path: AppRoutes.taskDetail,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return TaskDetailPage(taskId: id);
        },
      ),
    ],
  );

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpTaskDetailFrames(tester, 4);
    router.dispose();
    await db.close();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(800, 1000),
    overrides: [
      onlinePrimaryPolicyProvider.overrideWith(
        (ref) => writableOnlinePrimaryPolicy,
      ),
      allTaskListsProvider.overrideWith((ref) => Stream.value(taskLists)),
      activityRecordRepositoryProvider.overrideWithValue(
        _FakeActivityRecordRepository(db),
      ),
      taskEventServerFirstStoreProvider.overrideWith(
        (ref) async => fakeStore,
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
}

Future<void> pumpTaskDetailFrames(
  WidgetTester tester, [
  int count = 6,
]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tapTaskDetailChoiceChip(
  WidgetTester tester,
  String label, {
  bool last = false,
}) async {
  final finder = find.widgetWithText(ChoiceChip, label);
  final target = last ? finder.last : finder.first;
  await _centerForTap(tester, target);
  final tappableTarget = target.hitTestable();
  expect(tappableTarget, findsOneWidget);
  await tester.tap(tappableTarget);
  await tester.pump();
}

Future<void> tapTaskDetailSwitchListTile(
  WidgetTester tester,
  String title,
) async {
  final finder = find.widgetWithText(SwitchListTile, title);
  await _centerForTap(tester, finder);
  final tappableTarget = finder.hitTestable();
  expect(tappableTarget, findsOneWidget);
  await tester.tap(tappableTarget);
  await tester.pump();
}

Future<void> pumpUntilTaskCreated(
  WidgetTester tester,
  FakeTaskEventServerFirstStore fakeStore,
) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (fakeStore.createdTasks.isNotEmpty) {
      return;
    }
  }
  expect(fakeStore.createdTasks, isNotEmpty);
}

Future<void> pumpUntilTaskUpdated(
  WidgetTester tester,
  FakeTaskEventServerFirstStore fakeStore,
) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (fakeStore.updatedTasks.isNotEmpty) {
      return;
    }
  }
  expect(fakeStore.updatedTasks, isNotEmpty);
}

Future<void> pumpUntilTaskDeleted(
  WidgetTester tester,
  FakeTaskEventServerFirstStore fakeStore,
) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (fakeStore.deletedTaskIds.isNotEmpty) {
      return;
    }
  }
  expect(fakeStore.deletedTaskIds, isNotEmpty);
}

Future<void> _centerForTap(WidgetTester tester, Finder target) async {
  final element = target.evaluate().single;
  await Scrollable.ensureVisible(
    element,
    alignment: 0.45,
    duration: Duration.zero,
  );
  await pumpTaskDetailFrames(tester, 3);
}

class _FakeActivityRecordRepository extends ActivityRecordRepository {
  _FakeActivityRecordRepository(super.db);

  @override
  Stream<List<ActivityRecord>> watchByTaskId(int taskId) {
    return Stream.value(const <ActivityRecord>[]);
  }
}
