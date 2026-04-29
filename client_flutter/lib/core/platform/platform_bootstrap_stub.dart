import 'package:flutter/widgets.dart';

import '../../app.dart';
import '../database/app_database.dart';
import 'platform_bootstrap_types.dart';

Future<PlatformStartup> preparePlatformStartup() async {
  return PlatformStartup(database: AppDatabase());
}

class FlowPlanPlatformBootstrapper extends StatelessWidget {
  const FlowPlanPlatformBootstrapper({super.key});

  @override
  Widget build(BuildContext context) => const FlowPlanApp();
}
