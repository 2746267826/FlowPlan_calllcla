import 'package:flowplanv2/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  testWidgets(
    'timeline fits Android narrow layout',
    (tester) async {
      await _pumpGoldenApp(
        tester,
        size: const Size(360, 800),
        child: _GoldenTimelineFixture(compact: true),
      );

      await expectLater(
        find.byType(FlowPlanV2App),
        matchesGoldenFile('goldens/timeline_android_360x800.png'),
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

class _GoldenTimelineFixture extends StatelessWidget {
  const _GoldenTimelineFixture({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timeline')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _GoldenHeader(
            title: 'Today',
            subtitle: compact ? '3 focused blocks' : 'Planning overview',
          ),
          const SizedBox(height: 16),
          for (final item in const [
            ('09:00', 'Write tests', 'server coverage wave'),
            ('11:00', 'Review flows', 'web buttons and dialogs'),
            ('14:30', 'Flutter pass', 'analyze and widget tests'),
          ])
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(item.$1.substring(0, 2))),
                title: Text(item.$2),
                subtitle: Text(item.$3),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
        ],
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
