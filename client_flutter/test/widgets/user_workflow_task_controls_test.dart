import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/task/presentation/task_detail_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/task_detail_workflow_harness.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('task create and detail controls are reachable', (tester) async {
    await pumpAppAt(
      tester,
      initialLocation: AppRoutes.taskCreate,
      overrides: [
        onlinePrimaryPolicyProvider.overrideWith(
          (ref) => writableOnlinePrimaryPolicy,
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream.value([fixtureTaskList()]),
        ),
      ],
    );

    expect(find.byType(TaskDetailPage), findsOneWidget);
    expect(find.byKey(AppKeys.taskSummaryField), findsOneWidget);
    expect(find.byKey(AppKeys.taskSaveButton), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.enterText(
      find.byKey(AppKeys.taskSummaryField),
      'A-level widget task',
    );
    expect(find.byType(SwitchListTile), findsNWidgets(3));
  });
}
