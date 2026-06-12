import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowplanv2/app.dart';
import 'package:flowplanv2/core/router/app_router.dart';

import 'provider_harness.dart';
import 'test_database.dart';

Future<void> pumpGoldenScenario(
  WidgetTester tester, {
  required String route,
  required Size size,
}) async {
  final db = createTestDatabase();
  addTearDown(db.close);

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: size,
    child: FlowPlanV2App(
      routerOverride: createAppRouter(initialLocation: route),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}
