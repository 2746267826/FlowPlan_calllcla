// app.dart — MaterialApp.router 配置
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'shared/providers/settings_provider.dart';

class FlowPlanApp extends ConsumerWidget {
  const FlowPlanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'FlowPlan',
      debugShowCheckedModeBanner: false,

      // 双主题
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,

      // go_router
      routerConfig: appRouter,
    );
  }
}
