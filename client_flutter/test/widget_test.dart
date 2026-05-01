import 'package:flutter_test/flutter_test.dart';
import 'package:flowplanv2/app.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final db = AppDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const FlowPlanV2App(),
      ),
    );
    expect(find.byType(FlowPlanV2App), findsOneWidget);
    await db.close();
  });
}
