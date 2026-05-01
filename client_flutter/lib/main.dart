import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/platform/app_entry.dart';
import 'core/storage/app_storage_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sharedPreferencesPrefix = appSharedPreferencesPrefix;
  if (sharedPreferencesPrefix != null) {
    SharedPreferences.setPrefix(sharedPreferencesPrefix);
  }

  await initializeDateFormatting('zh_CN', null);

  await runFlowPlanV2Entry();
}
