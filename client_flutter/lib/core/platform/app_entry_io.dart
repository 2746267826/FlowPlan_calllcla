import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/database_provider.dart';
import 'platform_bootstrap.dart';

Future<void> runFlowPlanEntry() async {
  final startup = await preparePlatformStartup();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(startup.database),
      ],
      child: const FlowPlanPlatformBootstrapper(),
    ),
  );
}
