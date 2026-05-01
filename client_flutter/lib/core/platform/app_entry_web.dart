import 'package:flutter/material.dart';

import '../../web_app/flowplan_web_app.dart';
import '../../web_app/web_local_store.dart';

Future<void> runFlowPlanEntry() async {
  runApp(const _FlowPlanWebBootApp());
}

class _FlowPlanWebBootApp extends StatefulWidget {
  const _FlowPlanWebBootApp();

  @override
  State<_FlowPlanWebBootApp> createState() => _FlowPlanWebBootAppState();
}

class _FlowPlanWebBootAppState extends State<_FlowPlanWebBootApp> {
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final store = await WebLocalStore.load();
      if (!mounted) return;
      runApp(FlowPlanWebApp(store: store));
    } catch (caught) {
      if (!mounted) return;
      setState(() => error = caught);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FlowPlan',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      ),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 42, color: Color(0xFF2563EB)),
                    const SizedBox(height: 16),
                    Text(
                      error == null ? 'FlowPlan 正在启动' : 'FlowPlan 启动失败',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error == null
                          ? '正在读取浏览器本地配置并准备连接服务端。'
                          : '$error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 18),
                    if (error == null)
                      const LinearProgressIndicator()
                    else
                      FilledButton.icon(
                        onPressed: () {
                          setState(() => error = null);
                          _load();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
