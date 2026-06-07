import 'package:flowplanv2/app.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/golden_harness.dart';

void main() {
  testWidgets('timeline fits Android narrow layout', (tester) async {
    await pumpGoldenScenario(
      tester,
      route: '/timeline',
      size: const Size(360, 800),
    );
    await expectLater(
      find.byType(FlowPlanV2App),
      matchesGoldenFile('goldens/timeline_android_360x800.png'),
    );
  });

  testWidgets('settings fits Windows desktop layout', (tester) async {
    await pumpGoldenScenario(
      tester,
      route: '/settings',
      size: const Size(1280, 800),
    );
    await expectLater(
      find.byType(FlowPlanV2App),
      matchesGoldenFile('goldens/settings_windows_1280x800.png'),
    );
  });
}
