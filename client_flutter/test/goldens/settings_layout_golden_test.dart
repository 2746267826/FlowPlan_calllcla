import 'package:flowplanv2/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets(
    'settings fits Windows desktop layout',
    (tester) async {
      await _pumpGoldenApp(
        tester,
        size: const Size(1280, 800),
        child: const _GoldenSettingsFixture(),
      );

      await expectLater(
        find.byType(FlowPlanV2App),
        matchesGoldenFile('goldens/settings_windows_1280x800.png'),
      );
    },
    tags: const ['golden'],
  );
}

Future<void> _pumpGoldenApp(
  WidgetTester tester, {
  required Size size,
  required Widget child,
}) async {
  final db = createTestDatabase();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => child,
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    router.dispose();
    await db.close();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: size,
    child: FlowPlanV2App(routerOverride: router),
  );
  await tester.pump();
}

class _GoldenSettingsFixture extends StatelessWidget {
  const _GoldenSettingsFixture();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GoldenNavTile(icon: Icons.sync, label: 'Sync'),
                  _GoldenNavTile(icon: Icons.notifications, label: 'Reminders'),
                  _GoldenNavTile(icon: Icons.security, label: 'Privacy'),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _GoldenHeader(
                        title: 'Automation Rules',
                        subtitle: 'Deterministic desktop layout contract',
                      ),
                      const SizedBox(height: 18),
                      SwitchListTile(
                        value: true,
                        onChanged: (_) {},
                        title: const Text('Run tests before completion'),
                      ),
                      SwitchListTile(
                        value: false,
                        onChanged: (_) {},
                        title: const Text('Allow external credentials'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoldenHeader extends StatelessWidget {
  const _GoldenHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _GoldenNavTile extends StatelessWidget {
  const _GoldenNavTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
      ),
    );
  }
}
