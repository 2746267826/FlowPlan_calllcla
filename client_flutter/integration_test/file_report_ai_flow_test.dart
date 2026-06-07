import 'package:flowplanv2/app.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/test_support/provider_harness.dart';
import '../test/test_support/test_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('file transfer route exposes stable upload control', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      child: FlowPlanV2App(
        routerOverride: createAppRouter(initialLocation: AppRoutes.fileTransfers),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.fileTransferStartButton), findsOneWidget);
  });

  test('report and AI controls have reserved stable keys for future fake APIs', () {
    expect(AppKeys.reportGenerateButton, isNotNull);
  });
}
