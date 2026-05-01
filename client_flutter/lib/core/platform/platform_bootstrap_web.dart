import 'package:flutter/material.dart';

import '../database/app_database.dart';
import 'platform_bootstrap_types.dart';

Future<PlatformStartup> preparePlatformStartup() async {
  final database = AppDatabase();
  return PlatformStartup(database: database);
}

class FlowPlanV2PlatformBootstrapper extends StatelessWidget {
  const FlowPlanV2PlatformBootstrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FlowPlanV2 Web',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
      ),
      home: const _FlowPlanV2WebHome(),
    );
  }
}

class _FlowPlanV2WebHome extends StatelessWidget {
  const _FlowPlanV2WebHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FlowPlanV2 Web')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Web 端已启用',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '这是第一版 Web 安全入口，只加载浏览器兼容的 IndexedDB 缓存和基础界面。桌面追踪、系统托盘、原生文件扫描、数据库文件恢复等本机能力会继续保留在 Windows/Android 客户端中。',
                ),
                const SizedBox(height: 16),
                const _CapabilityRow(label: '服务端事实库', value: '需要继续接入登录与同步页'),
                const _CapabilityRow(label: '云盘文件中心', value: '下一步迁移为 Web-safe 页面'),
                const _CapabilityRow(label: '本地文件夹扫描', value: 'Web 不支持，改用上传/下载/浏览器文件选择'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
