import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpFlowPlanTestApp(
  WidgetTester tester, {
  required AppDatabase db,
  required Widget child,
  Size size = const Size(390, 844),
  List<Override> overrides = const <Override>[],
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        ...overrides,
      ],
      child: child,
    ),
  );
}
