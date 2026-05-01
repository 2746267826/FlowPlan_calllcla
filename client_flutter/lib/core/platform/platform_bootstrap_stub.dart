import 'package:flutter/widgets.dart';

import '../../app.dart';
import '../database/app_database.dart';
import 'platform_bootstrap_types.dart';

Future<PlatformStartup> preparePlatformStartup() async {
  return PlatformStartup(database: AppDatabase());
}

class FlowPlanV2PlatformBootstrapper extends StatelessWidget {
  const FlowPlanV2PlatformBootstrapper({super.key});

  @override
  Widget build(BuildContext context) => const FlowPlanV2App();
}
