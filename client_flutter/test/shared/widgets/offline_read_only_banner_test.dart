import 'package:flowplanv2/shared/widgets/offline_read_only_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders compact read-only cache state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OfflineReadOnlyBanner(),
        ),
      ),
    );

    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Offline cache is read-only'), findsOneWidget);
  });

  testWidgets('renders optional read-only cache reason', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OfflineReadOnlyBanner(
            reason: 'Reconnect to save changes.',
          ),
        ),
      ),
    );

    expect(find.text('Offline cache is read-only'), findsOneWidget);
    expect(find.text('Reconnect to save changes.'), findsOneWidget);
  });
}
