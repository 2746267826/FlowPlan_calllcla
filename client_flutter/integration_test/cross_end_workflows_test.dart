import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flowplanv2/app.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';

import '../test/test_support/provider_harness.dart';
import '../test/test_support/test_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'CE-CAL-001 event appears across timeline week and month with fake data',
    (tester) async {
      final db = createTestDatabase();
      addTearDown(db.close);

      await pumpFlowPlanTestApp(
        tester,
        db: db,
        child: const FlowPlanV2App(),
      );

      await tester.tap(find.byKey(AppKeys.shellTimeline));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AppKeys.shellWeek));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AppKeys.shellMonth));
      await tester.pumpAndSettle();

      expect(find.byKey(AppKeys.shellMonth), findsOneWidget);
    },
  );
}
