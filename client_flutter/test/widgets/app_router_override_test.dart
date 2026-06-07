import 'package:flowplanv2/app.dart';
import 'package:flowplanv2/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets('FlowPlanV2App uses routerOverride and keeps app theme fields', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Text('override route'),
        ),
      ],
    );

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      child: FlowPlanV2App(routerOverride: router),
    );

    expect(find.text('override route'), findsOneWidget);
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.title, 'FlowPlanV2');
    expect(materialApp.debugShowCheckedModeBanner, isFalse);
    expect(materialApp.themeMode, ThemeMode.system);
    expect(
      materialApp.theme?.colorScheme.primary,
      AppTheme.light.colorScheme.primary,
    );
    expect(
      materialApp.darkTheme?.colorScheme.primary,
      AppTheme.dark.colorScheme.primary,
    );
  });
}
