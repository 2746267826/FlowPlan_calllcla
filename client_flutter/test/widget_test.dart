import 'package:flowplanv2/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_support/provider_harness.dart';
import 'test_support/test_database.dart';

void main() {
  testWidgets('App smoke test renders through a controlled test route', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Text('FlowPlan test shell'),
        ),
      ],
    );

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      child: FlowPlanV2App(routerOverride: router),
    );

    expect(find.byType(FlowPlanV2App), findsOneWidget);
    expect(find.text('FlowPlan test shell'), findsOneWidget);
  });
}
