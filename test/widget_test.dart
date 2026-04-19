import 'package:flutter_test/flutter_test.dart';
import 'package:flowplan/app.dart';
import 'package:flowplan/core/database/app_database.dart';
import 'package:flowplan/shared/providers/database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final db = AppDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const FlowPlanApp(),
      ),
    );
    expect(find.byType(FlowPlanApp), findsOneWidget);
    await db.close();
  });
}
