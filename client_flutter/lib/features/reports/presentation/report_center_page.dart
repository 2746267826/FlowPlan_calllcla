import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/app_providers.dart';

final reportRefreshTickProvider = StateProvider<int>((ref) => 0);

final reportCenterSnapshotProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(reportRefreshTickProvider);
  final api = await ref.watch(reportsApiProvider.future);
  final reports = await api.reports(limit: 80);
  final diary = await api.diary(limit: 80);
  final weatherLocations = await api.weatherLocations();
  final weatherSummary = await api.weatherSummary();
  final channels = await api.pushChannels();
  final deliveries = await api.pushDeliveries(limit: 30);
  return {
    'reports': _items(reports),
    'diary': _items(diary),
    'weatherLocations': _items(weatherLocations),
    'weatherSummary': _items(weatherSummary),
    'channels': _items(channels),
    'deliveries': _items(deliveries),
  };
});

class ReportCenterPage extends ConsumerWidget {
  const ReportCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(reportCenterSnapshotProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('报告、日记与推送'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _refresh(ref),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: '$error',
          onRetry: () => _refresh(ref),
        ),
        data: (data) => _ReportCenterBody(data: data),
      ),
    );
  }
}

class _ReportCenterBody extends ConsumerWidget {
  const _ReportCenterBody({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = _mapList(data['reports']);
    final diaries = _mapList(data['diary']);
    final locations = _mapList(data['weatherLocations']);
    final weather = _mapList(data['weatherSummary']);
    final channels = _mapList(data['channels']);
    final deliveries = _mapList(data['deliveries']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: () => _generateReport(context, ref),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('生成今日日报'),
            ),
            OutlinedButton.icon(
              onPressed: () => _generateDiary(context, ref),
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('生成今日日记'),
            ),
            OutlinedButton.icon(
              onPressed: () => _configureWeather(context, ref),
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('配置天气地点'),
            ),
            OutlinedButton.icon(
              onPressed: () => _configurePush(context, ref),
              icon: const Icon(Icons.send_outlined),
              label: const Text('配置推送渠道'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _InfoStrip(
          text:
              '报告和日记先由模板生成，不依赖 LLM。AI 润色只是可选增强；失败时模板草稿仍然保留。位置和蓝牙当前只作为未来预留，不会采集。',
        ),
        const SizedBox(height: 16),
        _Section(
          title: '报告草稿',
          emptyText: '暂无报告。生成今日日报后会出现在这里。',
          items: reports,
          itemBuilder: (item) => _ReportTile(item: item),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '自动日记',
          emptyText: '暂无日记。日记默认私密，不会自动推送。',
          items: diaries,
          itemBuilder: (item) => _DiaryTile(item: item),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '天气缓存',
          emptyText: '暂无天气缓存。请先手动配置默认地点并刷新。',
          items: weather,
          itemBuilder: (item) => ListTile(
            leading: const Icon(Icons.cloud_queue_outlined),
            title: Text('${item['locationName'] ?? '天气'}'),
            subtitle: Text('${item['summary'] ?? ''}'),
            trailing: Text('${item['expiresAt'] ?? ''}'),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '推送渠道',
          emptyText: '暂无推送渠道。至少配置 Telegram 或 Webhook 后才能发送报告。',
          items: channels,
          itemBuilder: (item) => ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: Text('${item['name'] ?? item['channelType'] ?? '渠道'}'),
            subtitle: Text('类型：${item['channelType'] ?? ''}  状态：${item['status'] ?? ''}'),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '推送记录',
          emptyText: '暂无推送记录。',
          items: deliveries,
          itemBuilder: (item) => ListTile(
            leading: Icon(
              item['status'] == 'sent'
                  ? Icons.check_circle_outline
                  : item['status'] == 'failed'
                      ? Icons.error_outline
                      : Icons.schedule_send_outlined,
            ),
            title: Text('${item['channel'] ?? '推送'}：${item['status'] ?? ''}'),
            subtitle: Text('${item['lastError'] ?? item['target'] ?? ''}'),
            trailing: item['status'] == 'failed'
                ? TextButton(
                    onPressed: () => _retryDelivery(context, ref, '${item['id']}'),
                    child: const Text('重试'),
                  )
                : null,
          ),
        ),
        if (locations.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Section(
            title: '天气地点',
            emptyText: '暂无天气地点。',
            items: locations,
            itemBuilder: (item) => ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text('${item['name'] ?? '地点'}'),
              subtitle: Text('${item['latitude']}, ${item['longitude']}'),
              trailing: TextButton(
                onPressed: () => _refreshWeather(context, ref, '${item['id']}'),
                child: const Text('刷新天气'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReportTile extends ConsumerWidget {
  const _ReportTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text('${item['title'] ?? '报告'}'),
        subtitle: Text(
          [
            '类型：${item['reportType'] ?? ''}',
            '状态：${item['status'] ?? ''}',
            '时间：${item['updatedAt'] ?? item['createdAt'] ?? ''}',
          ].join('  '),
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 4,
          children: [
            TextButton(
              onPressed: () => _openReportDetail(context, ref, item),
              child: const Text('查看'),
            ),
            TextButton(
              onPressed: () => _editReport(context, ref, item),
              child: const Text('编辑'),
            ),
            if (item['status'] != 'confirmed')
              TextButton(
                onPressed: () => _confirmReport(context, ref, '${item['id']}'),
                child: const Text('确认'),
              ),
            TextButton(
              onPressed: () => _polishReport(context, ref, '${item['id']}'),
              child: const Text('AI 润色'),
            ),
            TextButton(
              onPressed: () => _pushReport(context, ref, '${item['id']}'),
              child: const Text('推送'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiaryTile extends ConsumerWidget {
  const _DiaryTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text('${item['title'] ?? '日记'}'),
        subtitle: Text('日期：${item['date'] ?? ''}  状态：${item['status'] ?? ''}'),
        trailing: Wrap(
          spacing: 4,
          children: [
            TextButton(
              onPressed: () => _editDiary(context, ref, item),
              child: const Text('编辑'),
            ),
            if (item['status'] != 'confirmed')
              TextButton(
                onPressed: () => _confirmDiary(context, ref, '${item['id']}'),
                child: const Text('确认'),
              ),
            TextButton(
              onPressed: () => _polishDiary(context, ref, '${item['id']}'),
              child: const Text('AI 润色'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.emptyText,
    required this.items,
    required this.itemBuilder,
  });

  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic>) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(emptyText, style: const TextStyle(color: Colors.black54)),
              )
            else
              for (final item in items) itemBuilder(item),
          ],
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Text(text),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

Future<void> _generateReport(BuildContext context, WidgetRef ref) async {
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    await api.generateReport(
      reportType: 'daily',
      periodStart: start,
      periodEnd: start.add(const Duration(days: 1)),
    );
    return '已生成今日日报草稿。';
  });
}

Future<void> _generateDiary(BuildContext context, WidgetRef ref) async {
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    await api.generateDiary(date: DateTime.now());
    return '已生成今日日记草稿。';
  });
}

Future<void> _editReport(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> item,
) async {
  final result = await _editMarkdownDialog(
    context,
    title: '编辑报告',
    initialTitle: '${item['title'] ?? ''}',
    initialMarkdown: '${item['contentMarkdown'] ?? item['summary'] ?? ''}',
  );
  if (result == null) return;
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    await api.updateReport(
      reportId: '${item['id']}',
      title: result.title,
      contentMarkdown: result.markdown,
      userNote: result.userNote,
    );
    return '报告已保存。';
  });
}

Future<void> _openReportDetail(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> item,
) async {
  final api = await ref.read(reportsApiProvider.future);
  final detail = await api.report('${item['id']}');
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${_asMap(detail['report'])['title'] ?? '报告详情'}'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_asMap(detail['report'])['contentMarkdown'] ?? ''}'),
              const Divider(height: 28),
              Text('条目与证据', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final entry in _mapList(detail['entries']))
                ListTile(
                  dense: true,
                  title: Text('[${entry['claimType'] ?? entry['entryType']}] ${entry['title'] ?? ''}'),
                  subtitle: Text('${entry['body'] ?? ''}'),
                ),
              const Divider(height: 28),
              for (final evidence in _mapList(detail['evidence']))
                Text(
                  '- ${evidence['evidenceType']}: ${evidence['sourceType']} ${evidence['sourceId'] ?? ''} ${evidence['summary'] ?? ''}',
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
      ],
    ),
  );
}

Future<void> _editDiary(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> item,
) async {
  final result = await _editMarkdownDialog(
    context,
    title: '编辑日记',
    initialTitle: '${item['title'] ?? ''}',
    initialMarkdown: '${item['contentMarkdown'] ?? ''}',
  );
  if (result == null) return;
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    await api.updateDiary(
      diaryId: '${item['id']}',
      title: result.title,
      contentMarkdown: result.markdown,
    );
    return '日记已保存。';
  });
}

Future<void> _confirmReport(
  BuildContext context,
  WidgetRef ref,
  String reportId,
) async {
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    await api.confirmReport(reportId);
    return '报告已确认。';
  });
}

Future<void> _confirmDiary(
  BuildContext context,
  WidgetRef ref,
  String diaryId,
) async {
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    await api.confirmDiary(diaryId);
    return '日记已确认。';
  });
}

Future<void> _polishReport(
  BuildContext context,
  WidgetRef ref,
  String reportId,
) async {
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    final result = await api.polishReport(reportId);
    return result['llmApplied'] == true
        ? 'AI 润色已加入报告。'
        : 'AI 不可用，已保留模板报告。';
  });
}

Future<void> _polishDiary(
  BuildContext context,
  WidgetRef ref,
  String diaryId,
) async {
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    final result = await api.polishDiary(diaryId);
    return result['llmApplied'] == true
        ? 'AI 润色已加入日记。'
        : 'AI 不可用，已保留模板日记。';
  });
}

Future<void> _pushReport(
  BuildContext context,
  WidgetRef ref,
  String reportId,
) async {
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    await api.pushReport(reportId: reportId);
    return '已创建推送记录并尝试发送。';
  });
}

Future<void> _retryDelivery(
  BuildContext context,
  WidgetRef ref,
  String deliveryId,
) async {
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    final result = await api.retryDelivery(deliveryId);
    return result['ok'] == true ? '重试成功。' : '重试失败，已记录原因。';
  });
}

Future<void> _configureWeather(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController(text: '默认地点');
  final latitude = TextEditingController();
  final longitude = TextEditingController();
  final timezone = TextEditingController(text: 'auto');
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('配置默认天气地点'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '地点名称')),
            TextField(controller: latitude, decoration: const InputDecoration(labelText: '纬度')),
            TextField(controller: longitude, decoration: const InputDecoration(labelText: '经度')),
            TextField(controller: timezone, decoration: const InputDecoration(labelText: '时区')),
            const SizedBox(height: 8),
            const Text('这里只保存手动地点，不请求 GPS 权限。'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存并刷新')),
      ],
    ),
  );
  if (saved != true) return;
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    final created = await api.upsertWeatherLocation(
      name: name.text.trim().isEmpty ? '默认地点' : name.text.trim(),
      latitude: double.parse(latitude.text.trim()),
      longitude: double.parse(longitude.text.trim()),
      timezone: timezone.text.trim().isEmpty ? 'auto' : timezone.text.trim(),
    );
    final location = _asMap(created['location']);
    await api.refreshWeather('${location['id']}');
    return '天气地点已保存并刷新。';
  });
}

Future<void> _refreshWeather(
  BuildContext context,
  WidgetRef ref,
  String locationId,
) async {
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    await api.refreshWeather(locationId);
    return '天气已刷新。';
  });
}

Future<void> _configurePush(BuildContext context, WidgetRef ref) async {
  final type = TextEditingController(text: 'webhook');
  final name = TextEditingController(text: '报告推送');
  final url = TextEditingController();
  final botToken = TextEditingController();
  final chatId = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('配置推送渠道'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: type, decoration: const InputDecoration(labelText: '类型：webhook 或 telegram')),
            TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
            TextField(controller: url, decoration: const InputDecoration(labelText: 'Webhook URL')),
            TextField(controller: botToken, decoration: const InputDecoration(labelText: 'Telegram Bot Token')),
            TextField(controller: chatId, decoration: const InputDecoration(labelText: 'Telegram Chat ID')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存')),
      ],
    ),
  );
  if (saved != true) return;
  await _run(context, ref, () async {
    final api = await ref.read(reportsApiProvider.future);
    await api.upsertPushChannel(
      channelType: type.text.trim().isEmpty ? 'webhook' : type.text.trim(),
      name: name.text.trim().isEmpty ? '报告推送' : name.text.trim(),
      config: {
        if (url.text.trim().isNotEmpty) 'url': url.text.trim(),
        if (botToken.text.trim().isNotEmpty) 'botToken': botToken.text.trim(),
        if (chatId.text.trim().isNotEmpty) 'chatId': chatId.text.trim(),
      },
    );
    return '推送渠道已保存。';
  });
}

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<String> Function() action,
) async {
  try {
    final message = await action();
    _refresh(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('操作失败：$error')),
    );
  }
}

void _refresh(WidgetRef ref) {
  ref.read(reportRefreshTickProvider.notifier).state++;
}

Future<_MarkdownEditResult?> _editMarkdownDialog(
  BuildContext context, {
  required String title,
  required String initialTitle,
  required String initialMarkdown,
}) async {
  final titleController = TextEditingController(text: initialTitle);
  final markdownController = TextEditingController(text: initialMarkdown);
  final userNoteController = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: markdownController,
              minLines: 12,
              maxLines: 18,
              decoration: const InputDecoration(
                labelText: 'Markdown 内容',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: userNoteController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '用户补充，可留空',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存')),
      ],
    ),
  );
  if (saved != true) return null;
  return _MarkdownEditResult(
    title: titleController.text.trim(),
    markdown: markdownController.text.trim(),
    userNote: userNoteController.text.trim(),
  );
}

class _MarkdownEditResult {
  const _MarkdownEditResult({
    required this.title,
    required this.markdown,
    required this.userNote,
  });

  final String title;
  final String markdown;
  final String userNote;
}

List<dynamic> _items(Map<String, dynamic> value) =>
    (value['items'] as List?) ?? const [];

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is Iterable) {
    return [for (final item in value) _asMap(item)];
  }
  return const [];
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}
