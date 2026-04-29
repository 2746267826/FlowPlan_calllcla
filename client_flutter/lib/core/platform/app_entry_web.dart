import 'package:flutter/material.dart';

import '../../web_app/flowplan_web_app.dart';
import '../../web_app/web_local_store.dart';

Future<void> runFlowPlanEntry() async {
  final store = await WebLocalStore.load();
  runApp(FlowPlanWebApp(store: store));
}
