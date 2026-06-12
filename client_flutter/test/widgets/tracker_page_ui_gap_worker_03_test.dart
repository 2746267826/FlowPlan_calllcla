import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/tracker/presentation/activity_review_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('activity review surfaces load and rebuild failures', (
    tester,
  ) async {
    final store = _ReviewStore(
      segmentsError: StateError('segments unavailable'),
      buildSegmentsError: StateError('builder unavailable'),
    );

    await _pumpActivityReview(tester, store: store);
    await pumpUntilFound(tester, find.byType(ActivityReviewPage));
    await pumpUntilFound(tester, find.textContaining('segments unavailable'));

    await tester.tap(find.byIcon(Icons.auto_fix_high_outlined).first);
    await _pumpUntil(tester, () => store.buildSegmentsCalls == 1);
    await pumpUntilFound(tester, find.textContaining('builder unavailable'));

    expect(store.buildSegmentsCalls, 1);
    expect(find.byIcon(Icons.auto_fix_high_outlined), findsWidgets);
  });

  testWidgets('activity review cancel and confirm failure keep segment pending', (
    tester,
  ) async {
    final store = _ReviewStore(
      confirmError: StateError('confirm transport failed'),
      items: <Map<String, Object?>>[_segmentItem(id: 'candidate-1')],
    );

    await _pumpActivityReview(tester, store: store);
    await pumpUntilFound(tester, find.text('Focused coding'));

    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await pumpUntilFound(tester, find.byKey(AppKeys.trackerReviewConfirmButton));
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(store.confirmedSegments, isEmpty);
    expect(find.text('Focused coding'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await pumpUntilFound(tester, find.byKey(AppKeys.trackerReviewConfirmButton));
    await tester.tap(find.byKey(AppKeys.trackerReviewConfirmButton));
    await _pumpUntil(tester, () => store.confirmAttempts == 1);
    await pumpUntilFound(tester, find.textContaining('confirm transport failed'));

    expect(store.confirmedSegments, isEmpty);
    expect(find.text('Focused coding'), findsOneWidget);
  });

  testWidgets('activity review reject failure keeps segment pending', (
    tester,
  ) async {
    final store = _ReviewStore(
      rejectError: StateError('reject transport failed'),
      items: <Map<String, Object?>>[_segmentItem(id: 'reject-candidate-1')],
    );

    await _pumpActivityReview(tester, store: store);
    await pumpUntilFound(tester, find.text('Focused coding'));

    await tester.tap(find.byIcon(Icons.block_outlined));
    await _pumpUntil(tester, () => store.rejectAttempts == 1);
    await pumpUntilFound(tester, find.textContaining('reject transport failed'));

    expect(store.rejectedSegments, isEmpty);
    expect(find.text('Focused coding'), findsOneWidget);
  });

  testWidgets('activity review disables completed edge actions', (tester) async {
    final store = _ReviewStore(
      items: <Map<String, Object?>>[
        _segmentItem(
          id: 'confirmed-1',
          title: 'Already confirmed coding',
          status: 'confirmed',
        ),
        _segmentItem(
          id: 'rejected-1',
          title: 'Already rejected browsing',
          status: 'rejected',
        ),
      ],
    );

    await _pumpActivityReview(tester, store: store);
    await pumpUntilFound(tester, find.text('Already confirmed coding'));
    await pumpUntilFound(tester, find.text('Already rejected browsing'));

    final confirmButtons = tester.widgetList<FilledButton>(
      find.widgetWithText(FilledButton, '确认'),
    );
    final rejectButtons = tester.widgetList<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '拒绝'),
    );

    expect(confirmButtons, hasLength(2));
    expect(rejectButtons, hasLength(2));
    expect(confirmButtons.first.onPressed, isNull);
    expect(rejectButtons.first.onPressed, isNotNull);
    expect(confirmButtons.last.onPressed, isNotNull);
    expect(rejectButtons.last.onPressed, isNull);
  });
}

Future<void> _pumpActivityReview(
  WidgetTester tester, {
  required _ReviewStore store,
}) async {
  await pumpAppAt(
    tester,
    initialLocation: AppRoutes.activityReview,
    size: const Size(1200, 900),
    overrides: [
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      allTasksProvider.overrideWith(
        (ref) => Stream.value(const <TaskItem>[]),
      ),
    ],
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 20; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

Map<String, Object?> _segmentItem({
  required String id,
  String title = 'Focused coding',
  String status = 'candidate',
}) {
  return <String, Object?>{
    'id': id,
    'segmentUid': id,
    'startAt': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
    'endAt': DateTime.utc(2026, 6, 8, 9, 30).toIso8601String(),
    'title': title,
    'summary': title,
    'primaryProcessName': 'Code.exe',
    'primaryWindowTitle': 'FlowPlanV2 tests',
    'category': 'coding',
    'confidence': 0.91,
    'status': status,
    'evidence': <String, Object?>{
      'activityRecordCount': 1,
      'rawLogCount': 2,
      'inputEventCount': 3,
      'processes': <String>['Code.exe'],
    },
  };
}

class _ReviewStore extends FakeTrackingServerFirstStore {
  _ReviewStore({
    this.segmentsError,
    this.buildSegmentsError,
    this.confirmError,
    this.rejectError,
    List<Map<String, Object?>>? items,
  }) : items = items ?? <Map<String, Object?>>[_segmentItem(id: 'segment-1')];

  final Object? segmentsError;
  final Object? buildSegmentsError;
  final Object? confirmError;
  final Object? rejectError;
  final List<Map<String, Object?>> items;
  var confirmAttempts = 0;
  var rejectAttempts = 0;

  @override
  Future<Map<String, dynamic>> segments({
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    final error = segmentsError;
    if (error != null) {
      throw error;
    }
    return <String, dynamic>{'items': items};
  }

  @override
  Future<Map<String, dynamic>> confirmSegment({
    required String segmentId,
    String? title,
    String? taskId,
    String? note,
  }) async {
    confirmAttempts += 1;
    final error = confirmError;
    if (error != null) {
      throw error;
    }
    return super.confirmSegment(
      segmentId: segmentId,
      title: title,
      taskId: taskId,
      note: note,
    );
  }

  @override
  Future<Map<String, dynamic>> rejectSegment({
    required String segmentId,
    String? reason,
  }) async {
    rejectAttempts += 1;
    final error = rejectError;
    if (error != null) {
      throw error;
    }
    return super.rejectSegment(segmentId: segmentId, reason: reason);
  }

  @override
  Future<Map<String, dynamic>> buildSegments({
    required DateTime date,
    bool includeTrackedInputEvents = true,
    bool includeRawActivityLogs = true,
    bool includeActivityRecords = true,
  }) async {
    buildSegmentsCalls += 1;
    final error = buildSegmentsError;
    if (error != null) {
      throw error;
    }
    return <String, dynamic>{
      'rawCount': 2,
      'segmentsCreated': 1,
      'segmentsUpdated': 1,
      'lowConfidenceCount': 1,
    };
  }

}
