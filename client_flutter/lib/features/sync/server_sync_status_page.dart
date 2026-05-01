import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/client_bootstrap_service.dart';
import '../../core/database/app_database.dart';
import '../../core/router/app_router.dart';
import '../../core/server_api/server_config_store.dart';
import '../../core/sync/sync_cursor_store.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/providers/database_provider.dart';

final serverSyncMvpSummaryProvider =
    FutureProvider.autoDispose<ServerSyncMvpSummary>((ref) async {
  final database = ref.watch(databaseProvider);
  final cursorStore = ref.watch(syncCursorStoreProvider);
  return ServerSyncMvpSummary.load(database, cursorStore);
});

class ServerSyncMvpSummary {
  const ServerSyncMvpSummary({
    required this.waitingMutations,
    required this.failedMutations,
    required this.ackedMutations,
    required this.conflictMutations,
    required this.syncedObjects,
    required this.pendingObjects,
    required this.failedObjects,
    required this.conflictObjects,
    required this.recentMutations,
    this.lastPushAt,
    this.lastPullAt,
  });

  final int waitingMutations;
  final int failedMutations;
  final int ackedMutations;
  final int conflictMutations;
  final int syncedObjects;
  final int pendingObjects;
  final int failedObjects;
  final int conflictObjects;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  final List<LocalMutationDiagnostic> recentMutations;

  static Future<ServerSyncMvpSummary> load(
    AppDatabase database,
    SyncCursorStore cursorStore,
  ) async {
    final mutationCounts = await database.customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN status IN ('pending', 'sending') THEN 1 ELSE 0 END), 0) AS waiting,
        COALESCE(SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END), 0) AS failed,
        COALESCE(SUM(CASE WHEN status = 'acked' THEN 1 ELSE 0 END), 0) AS acked,
        COALESCE(SUM(CASE WHEN status = 'conflict' THEN 1 ELSE 0 END), 0) AS conflict
      FROM offline_mutations
      ''',
    ).getSingle();
    final stateCounts = await database.customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN sync_state = 'synced' THEN 1 ELSE 0 END), 0) AS synced,
        COALESCE(SUM(CASE WHEN sync_state IN ('pending_create', 'pending_update', 'pending_delete') THEN 1 ELSE 0 END), 0) AS pending,
        COALESCE(SUM(CASE WHEN sync_state = 'failed' THEN 1 ELSE 0 END), 0) AS failed,
        COALESCE(SUM(CASE WHEN sync_state = 'conflict' THEN 1 ELSE 0 END), 0) AS conflict
      FROM sync_object_states
      ''',
    ).getSingle();
    final recentRows = await database.customSelect(
      '''
      SELECT id, mutation_uid, object_type, local_id, action, status, attempts, last_error, created_at
      FROM offline_mutations
      ORDER BY id DESC
      LIMIT 30
      ''',
    ).get();

    return ServerSyncMvpSummary(
      waitingMutations: _readInt(mutationCounts, 'waiting'),
      failedMutations: _readInt(mutationCounts, 'failed'),
      ackedMutations: _readInt(mutationCounts, 'acked'),
      conflictMutations: _readInt(mutationCounts, 'conflict'),
      syncedObjects: _readInt(stateCounts, 'synced'),
      pendingObjects: _readInt(stateCounts, 'pending'),
      failedObjects: _readInt(stateCounts, 'failed'),
      conflictObjects: _readInt(stateCounts, 'conflict'),
      lastPushAt: await cursorStore.readLastPushAt(),
      lastPullAt: await cursorStore.readLastPullAt(),
      recentMutations: recentRows
          .map(LocalMutationDiagnostic.fromRow)
          .toList(growable: false),
    );
  }

  static int _readInt(QueryRow row, String key) {
    final value = row.data[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class LocalMutationDiagnostic {
  const LocalMutationDiagnostic({
    required this.id,
    required this.mutationUid,
    required this.objectType,
    required this.localId,
    required this.action,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastError,
  });

  final int id;
  final String mutationUid;
  final String objectType;
  final String localId;
  final String action;
  final String status;
  final int attempts;
  final DateTime createdAt;
  final String? lastError;

  factory LocalMutationDiagnostic.fromRow(QueryRow row) {
    return LocalMutationDiagnostic(
      id: row.read<int>('id'),
      mutationUid: row.read<String>('mutation_uid'),
      objectType: row.read<String>('object_type'),
      localId: row.read<String>('local_id'),
      action: row.read<String>('action'),
      status: row.read<String>('status'),
      attempts: row.read<int>('attempts'),
      lastError: row.data['last_error'] as String?,
      createdAt: DateTime.tryParse(row.read<String>('created_at')) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ServerSyncStatusPage extends ConsumerStatefulWidget {
  const ServerSyncStatusPage({super.key});

  @override
  ConsumerState<ServerSyncStatusPage> createState() =>
      _ServerSyncStatusPageState();
}

class _ServerSyncStatusPageState extends ConsumerState<ServerSyncStatusPage> {
  final _serverUrlController = TextEditingController();
  bool _loadingUrl = true;
  bool _savingUrl = false;
  bool _runningAction = false;
  String? _lastImportId;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadServerUrl);
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadServerUrl() async {
    final uri = await ref.read(serverConfigStoreProvider).readBaseUri();
    if (!mounted) {
      return;
    }
    setState(() {
      _serverUrlController.text = uri.toString();
      _loadingUrl = false;
    });
  }

  Future<void> _saveServerUrl() async {
    final raw = _serverUrlController.text.trim();
    final uri = Uri.tryParse(raw);
    if (raw.isEmpty || uri == null || !uri.hasScheme || !uri.hasAuthority) {
      _show('请输入完整的服务端 API 地址，例如 http://localhost:3202/api');
      return;
    }
    setState(() => _savingUrl = true);
    try {
      final normalized = ServerConfigStore.normalizeBaseUri(uri);
      await ref.read(serverConfigStoreProvider).saveBaseUri(normalized);
      _serverUrlController.text = normalized.toString();
      ref.invalidate(apiClientProvider);
      ref.invalidate(clientApiProvider);
      ref.invalidate(remoteSettingsRepositoryProvider);
      ref.invalidate(serverSyncEngineProvider);
      ref.invalidate(clientBootstrapServiceProvider);
      ref.invalidate(serverConnectionServiceProvider);
      final service = await ref.read(serverConnectionServiceProvider.future);
      service.start();
      await service.syncNow(source: 'server_url_saved');
      ref.invalidate(serverSyncMvpSummaryProvider);
      _show('服务端地址已保存并已重新连接');
    } catch (error) {
      _show('保存失败：$error');
    } finally {
      if (mounted) {
        setState(() => _savingUrl = false);
      }
    }
  }

  Future<void> _run(
    Future<void> Function(ClientBootstrapService service) action,
  ) async {
    if (_runningAction) {
      return;
    }
    setState(() => _runningAction = true);
    try {
      final service = await ref.read(clientBootstrapServiceProvider.future);
      await action(service);
      ref.invalidate(serverSyncMvpSummaryProvider);
    } catch (error) {
      _show('操作失败：$error');
    } finally {
      if (mounted) {
        setState(() => _runningAction = false);
      }
    }
  }

  Future<void> _prepareImport(ClientBootstrapService service) async {
    final response = await service.prepareLocalImport();
    final importId = response['importId']?.toString();
    setState(() => _lastImportId = importId);
    _show('已生成导入预览，请确认后再让服务端接管');
  }

  Future<void> _confirmImport(ClientBootstrapService service) async {
    final importId = _lastImportId;
    if (importId == null || importId.isEmpty) {
      _show('请先生成导入预览');
      return;
    }
    await service.confirmImport(importId);
    _show('服务端接管完成，已重新拉取 canonical 数据');
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(serverSyncMvpSummaryProvider);
    final runtime = ref.watch(clientBootstrapServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务端同步'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: _leavePage,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(serverSyncMvpSummaryProvider);
          await ref.read(serverSyncMvpSummaryProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ServerUrlCard(
              controller: _serverUrlController,
              loading: _loadingUrl,
              saving: _savingUrl,
              onSave: _saveServerUrl,
            ),
            const SizedBox(height: 12),
            runtime.when(
              loading: () => const _Notice(
                icon: Icons.hourglass_empty_outlined,
                title: '正在准备服务端连接',
                message: '应用会先显示本地缓存，然后在后台连接服务端。',
                color: Colors.blueGrey,
              ),
              error: (error, _) => _Notice(
                icon: Icons.cloud_off_outlined,
                title: '服务端接入未就绪',
                message: error.toString(),
                color: Colors.redAccent,
              ),
              data: (service) => _RuntimeCard(state: service.state),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _runningAction
                      ? null
                      : () => _run(
                            (service) => service.bootstrapAndSync(
                              source: 'manual',
                            ),
                          ),
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('启动检查并同步'),
                ),
                OutlinedButton.icon(
                  onPressed: _runningAction
                      ? null
                      : () => _run((service) => service.syncNow()),
                  icon: const Icon(Icons.sync_outlined),
                  label: const Text('立即同步全部'),
                ),
                OutlinedButton.icon(
                  onPressed: _runningAction
                      ? null
                      : () => _run((service) => _prepareImport(service)),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('生成服务端接管预览'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _runningAction || _lastImportId == null
                      ? null
                      : () => _run((service) => _confirmImport(service)),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('确认导入到服务端'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            summary.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => _Notice(
                icon: Icons.error_outline,
                title: '同步状态读取失败',
                message: error.toString(),
                color: Colors.redAccent,
              ),
              data: (value) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryGrid(summary: value),
                  const SizedBox(height: 16),
                  const Text(
                    '最近本地同步队列',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (value.recentMutations.isEmpty)
                    const _Notice(
                      icon: Icons.inbox_outlined,
                      title: '暂无同步队列',
                      message: '创建或修改任务、日程、文件元数据、实际记录后，这里会显示等待推送的记录。',
                      color: Colors.blueGrey,
                    )
                  else
                    for (final mutation in value.recentMutations)
                      _MutationTile(mutation: mutation),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _leavePage,
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回主界面'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _leavePage() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.timeline);
  }

  void _show(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _RuntimeCard extends StatelessWidget {
  const _RuntimeCard({required this.state});

  final ClientRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final reachable = state.serverReachable == true;
    final hasSyncError =
        reachable && state.lastError != null && state.lastError!.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasSyncError
                      ? Icons.sync_problem_outlined
                      : reachable
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                  color: hasSyncError
                      ? Colors.amber.shade700
                      : reachable
                          ? Colors.green
                          : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _modeLabel(state),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (state.syncing) const CircularProgressIndicator(strokeWidth: 2),
              ],
            ),
            const SizedBox(height: 10),
            Text('远程设置版本：${state.settingsVersion ?? 0}'),
            Text('服务端游标：${state.syncCursor ?? '0'}'),
            Text('上次启动检查：${_formatNullable(state.lastBootstrapAt)}'),
            Text('上次同步：${_formatNullable(state.lastSyncAt)}'),
            if (state.pendingActions.isNotEmpty)
              Text('待处理：${state.pendingActions}'),
            if (state.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.lastError!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _modeLabel(ClientRuntimeState state) {
    if (state.serverReachable == true &&
        state.lastError != null &&
        state.lastError!.isNotEmpty) {
      return '服务端在线 · 同步异常';
    }
    switch (state.mode) {
      case 'server_first':
        return '服务端事实库模式';
      case 'local_cache':
        return '本地缓存模式';
      default:
        return '尚未连接服务端';
    }
  }
}

class _ServerUrlCard extends StatelessWidget {
  const _ServerUrlCard({
    required this.controller,
    required this.loading,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool loading;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '服务端 API 地址',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              enabled: !loading && !saving,
              decoration: const InputDecoration(
                hintText: 'http://localhost:3202/api',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('保存地址'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final ServerSyncMvpSummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _MetricCard(
          label: '等待同步',
          value: summary.waitingMutations,
          icon: Icons.cloud_upload_outlined,
          color: Colors.orange,
        ),
        _MetricCard(
          label: '同步失败',
          value: summary.failedMutations,
          icon: Icons.sync_problem_outlined,
          color: Colors.redAccent,
        ),
        _MetricCard(
          label: '已同步对象',
          value: summary.syncedObjects,
          icon: Icons.cloud_done_outlined,
          color: Colors.green,
        ),
        _MetricCard(
          label: '冲突',
          value: summary.conflictMutations + summary.conflictObjects,
          icon: Icons.report_problem_outlined,
          color: Colors.deepOrange,
        ),
        _MetricCard(
          label: '上次推送',
          valueText: _formatNullable(summary.lastPushAt),
          icon: Icons.upload_outlined,
          color: Colors.blueGrey,
        ),
        _MetricCard(
          label: '上次拉取',
          valueText: _formatNullable(summary.lastPullAt),
          icon: Icons.download_outlined,
          color: Colors.blueGrey,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.icon,
    required this.color,
    this.value,
    this.valueText,
  });

  final String label;
  final int? value;
  final String? valueText;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                valueText ?? value.toString(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MutationTile extends StatelessWidget {
  const _MutationTile({required this.mutation});

  final LocalMutationDiagnostic mutation;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(mutation.status);
    return Card(
      child: ListTile(
        leading: Icon(_statusIcon(mutation.status), color: color),
        title: Text(
          '${_objectLabel(mutation.objectType)} ${mutation.action} · ${_statusLabel(mutation.status)}',
        ),
        subtitle: Text(
          '本地 ID ${mutation.localId} · 尝试 ${mutation.attempts} 次'
          '${mutation.lastError == null ? '' : '\n${mutation.lastError}'}',
        ),
        isThreeLine: mutation.lastError != null,
        trailing: Text('#${mutation.id}'),
      ),
    );
  }

  String _objectLabel(String value) {
    switch (value) {
      case 'task_item':
        return '任务';
      case 'calendar_event':
        return '日程';
      case 'file_item':
        return '文件';
      case 'actual_activity_log':
        return '实际记录';
      case 'report_document':
        return '报告';
      case 'audit_log':
        return '审计';
      default:
        return value;
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'pending':
      case 'sending':
        return '等待同步';
      case 'acked':
        return '已同步';
      case 'failed':
        return '同步失败';
      case 'conflict':
        return '有冲突';
      default:
        return value;
    }
  }

  IconData _statusIcon(String value) {
    switch (value) {
      case 'acked':
        return Icons.cloud_done_outlined;
      case 'failed':
        return Icons.sync_problem_outlined;
      case 'conflict':
        return Icons.report_problem_outlined;
      default:
        return Icons.cloud_upload_outlined;
    }
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'acked':
        return Colors.green;
      case 'failed':
        return Colors.redAccent;
      case 'conflict':
        return Colors.deepOrange;
      default:
        return Colors.orange;
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatNullable(DateTime? value) {
  if (value == null) {
    return '无';
  }
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}
