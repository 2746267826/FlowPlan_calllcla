import 'package:flowplanv2/app.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/test_support/provider_harness.dart';
import '../test/test_support/test_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create task from shell quick add', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      child: FlowPlanV2App(
        routerOverride: createAppRouter(initialLocation: AppRoutes.timeline),
      ),
    );

    await tester.tap(find.byKey(AppKeys.shellCreateTask));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppKeys.taskSummaryField), 'A-level tests');
    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('A-level tests'), findsWidgets);
  });
}
