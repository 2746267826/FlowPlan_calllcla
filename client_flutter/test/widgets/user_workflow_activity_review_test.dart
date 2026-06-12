import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/tracker/presentation/activity_review_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('tracker review confirm dialog exposes commit control', (
    tester,
  ) async {
    final fakeTrackingStore = FakeTrackingServerFirstStore();

    await pumpAppAt(
      tester,
      initialLocation: AppRoutes.activityReview,
      overrides: [
        trackingServerFirstStoreProvider.overrideWith(
          (ref) async => fakeTrackingStore,
        ),
        allTasksProvider.overrideWith(
          (ref) => Stream.value(const <TaskItem>[]),
        ),
      ],
    );
    await pumpUntilFound(tester, find.byType(ActivityReviewPage));
    await pumpUntilFound(tester, find.text('Focused coding'), maxPumps: 20);

    expect(find.byType(ActivityReviewPage), findsOneWidget);
    expect(find.text('Focused coding'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await pumpUntilFound(
        tester, find.byKey(AppKeys.trackerReviewConfirmButton));

    expect(find.byKey(AppKeys.trackerReviewConfirmButton), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.trackerReviewConfirmButton));
    await _pumpUntilConfirmed(tester, fakeTrackingStore);

    expect(fakeTrackingStore.confirmedSegmentIds, ['segment-1']);
    expect(
        fakeTrackingStore.confirmedSegments.single['title'], 'Focused coding');
    expect(fakeTrackingStore.confirmedSegments.single['taskId'], isNull);
    expect(fakeTrackingStore.confirmedSegments.single['note'], isNull);
  });

  testWidgets('tracker review links confirmed segment to selected task', (
    tester,
  ) async {
    final fakeTrackingStore = FakeTrackingServerFirstStore();

    await pumpAppAt(
      tester,
      initialLocation: AppRoutes.activityReview,
      overrides: [
        trackingServerFirstStoreProvider.overrideWith(
          (ref) async => fakeTrackingStore,
        ),
        allTasksProvider.overrideWith(
          (ref) => Stream.value(<TaskItem>[
            _task(id: 1, summary: 'Task A'),
          ]),
        ),
      ],
    );
    await pumpUntilFound(tester, find.byType(ActivityReviewPage));
    await pumpUntilFound(tester, find.text('Focused coding'), maxPumps: 20);

    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await pumpUntilFound(
        tester, find.byKey(AppKeys.trackerReviewConfirmButton));

    final titleField = find.byType(TextField).first;
    final noteField = find.byType(TextField).last;
    await tester.enterText(titleField, 'Reviewed coding block');
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Task A').last);
    await tester.pumpAndSettle();
    await tester.enterText(noteField, 'Verified from review dialog');

    await tester.tap(find.byKey(AppKeys.trackerReviewConfirmButton));
    await _pumpUntil(
      tester,
      () => fakeTrackingStore.confirmedSegments.isNotEmpty,
    );

    expect(fakeTrackingStore.confirmedSegmentIds, ['segment-1']);
    expect(fakeTrackingStore.confirmedSegments.single, <String, Object?>{
      'segmentId': 'segment-1',
      'title': 'Reviewed coding block',
      'taskId': 'task-1',
      'note': 'Verified from review dialog',
    });
  });

  testWidgets('tracker review defaults matched server task on confirmation', (
    tester,
  ) async {
    final fakeTrackingStore = _MatchedTaskReviewStore();

    await pumpAppAt(
      tester,
      initialLocation: AppRoutes.activityReview,
      overrides: [
        trackingServerFirstStoreProvider.overrideWith(
          (ref) async => fakeTrackingStore,
        ),
        allTasksProvider.overrideWith(
          (ref) => Stream.value(<TaskItem>[
            _task(id: 7, summary: 'Matched Task'),
          ]),
        ),
      ],
    );
    await pumpUntilFound(tester, find.byType(ActivityReviewPage));
    await pumpUntilFound(tester, find.text('Matched server work'),
        maxPumps: 20);

    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await pumpUntilFound(
        tester, find.byKey(AppKeys.trackerReviewConfirmButton));

    final dropdown = tester.widget<DropdownButtonFormField<String?>>(
      find.byType(DropdownButtonFormField<String?>),
    );
    expect(dropdown.initialValue, 'task-7');

    await tester.tap(find.byKey(AppKeys.trackerReviewConfirmButton));
    await _pumpUntil(
      tester,
      () => fakeTrackingStore.confirmedSegments.isNotEmpty,
    );

    expect(fakeTrackingStore.confirmedSegments.single['taskId'], 'task-7');
  });

  testWidgets('tracker review reject action records the segment and reason', (
    tester,
  ) async {
    final fakeTrackingStore = FakeTrackingServerFirstStore();

    await pumpAppAt(
      tester,
      initialLocation: AppRoutes.activityReview,
      overrides: [
        trackingServerFirstStoreProvider.overrideWith(
          (ref) async => fakeTrackingStore,
        ),
        allTasksProvider.overrideWith(
          (ref) => Stream.value(const <TaskItem>[]),
        ),
      ],
    );
    await pumpUntilFound(tester, find.byType(ActivityReviewPage));
    await pumpUntilFound(tester, find.text('Focused coding'), maxPumps: 20);

    await tester.tap(find.byIcon(Icons.block_outlined));
    await _pumpUntil(
      tester,
      () => fakeTrackingStore.rejectedSegments.isNotEmpty,
    );

    expect(fakeTrackingStore.confirmedSegmentIds, isEmpty);
    expect(fakeTrackingStore.rejectedSegments.single, <String, Object?>{
      'segmentId': 'segment-1',
      'reason': 'user_rejected',
    });
  });
}

Future<void> _pumpUntilConfirmed(
  WidgetTester tester,
  FakeTrackingServerFirstStore fakeTrackingStore,
) async {
  await _pumpUntil(
    tester,
    () => fakeTrackingStore.confirmedSegmentIds.contains('segment-1'),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

class _MatchedTaskReviewStore extends FakeTrackingServerFirstStore {
  @override
  Future<Map<String, dynamic>> segments({
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    return <String, dynamic>{
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'segment-matched-task',
          'segmentUid': 'segment-matched-task',
          'startAt': DateTime.utc(2026, 6, 8, 10).toIso8601String(),
          'endAt': DateTime.utc(2026, 6, 8, 10, 30).toIso8601String(),
          'summary': 'Matched server work',
          'primaryProcessName': 'Code.exe',
          'category': 'coding',
          'confidence': 0.88,
          'status': 'candidate',
          'matchedTaskId': 'task-7',
          'evidence': <String, Object?>{
            'activityRecordCount': 1,
            'rawLogCount': 0,
            'inputEventCount': 0,
          },
        },
      ],
    };
  }
}

TaskItem _task({
  required int id,
  required String summary,
}) {
  return TaskItem(
    id: id,
    uid: 'task-$id',
    dtstamp: DateTime.utc(2026, 6, 8),
    summary: summary,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: '',
    durationMinutes: 0,
    isSplittable: false,
    priorityLocal: 0,
    isAutoScheduled: false,
    isLocked: false,
    reminderMinutesBefore: 0,
  );
}
