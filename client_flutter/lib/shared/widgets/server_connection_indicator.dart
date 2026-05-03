import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/connection/server_connection_service.dart';
import '../../core/connection/server_connection_state.dart';
import '../../core/router/app_router.dart';
import '../providers/app_providers.dart';

class ServerConnectionIndicator extends ConsumerWidget {
  const ServerConnectionIndicator({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serviceAsync = ref.watch(serverConnectionServiceProvider);
    return serviceAsync.when(
      loading: () => _IndicatorShell(
        compact: compact,
        color: Colors.blueGrey,
        label: compact ? '' : '连接中',
        tooltip: '正在初始化服务端连接',
        onTap: null,
      ),
      error: (error, _) => _IndicatorShell(
        compact: compact,
        color: Colors.redAccent,
        label: compact ? '' : '连接异常',
        tooltip: error.toString(),
        onTap: null,
      ),
      data: (service) => ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final view = _viewFor(service.state);
          return _IndicatorShell(
            compact: compact,
            color: view.color,
            label: compact ? '' : _indicatorLabel(service.state, view),
            tooltip: _indicatorTooltip(service.state, view),
            onTap: () => _showConnectionDialog(context, service),
          );
        },
      ),
    );
  }

  _ConnectionIndicatorView _viewFor(ServerConnectionState state) {
    if (state.conflictCount > 0) {
      return _ConnectionIndicatorView(
        color: Colors.deepOrange,
        label: '有冲突',
        tooltip: '有 ${state.conflictCount} 个同步冲突需要处理',
      );
    }
    switch (state.level) {
      case ServerConnectionLevel.online:
        return const _ConnectionIndicatorView(
          color: Colors.green,
          label: '在线',
          tooltip: '服务端连接正常',
        );
      case ServerConnectionLevel.syncing:
        return const _ConnectionIndicatorView(
          color: Colors.blue,
          label: '同步中',
          tooltip: '正在与服务端同步',
        );
      case ServerConnectionLevel.degraded:
        return _ConnectionIndicatorView(
          color: Colors.amber.shade700,
          label: '异常',
          tooltip: state.lastError ?? '服务端可达，但最近同步或心跳异常',
        );
      case ServerConnectionLevel.offline:
        return _ConnectionIndicatorView(
          color: Colors.redAccent,
          label: '离线',
          tooltip: state.lastError ?? '服务端暂不可用，当前使用本地缓存',
        );
      case ServerConnectionLevel.authRequired:
        return const _ConnectionIndicatorView(
          color: Colors.purple,
          label: '需登录',
          tooltip: '服务端认证失效，需要重新登录',
        );
      case ServerConnectionLevel.conflicted:
        return _ConnectionIndicatorView(
          color: Colors.deepOrange,
          label: '有冲突',
          tooltip: '有 ${state.conflictCount} 个同步冲突需要处理',
        );
      case ServerConnectionLevel.localCacheOnly:
        return const _ConnectionIndicatorView(
          color: Colors.blueGrey,
          label: '本地缓存',
          tooltip: '尚未建立服务端连接',
        );
      case ServerConnectionLevel.unknown:
        return const _ConnectionIndicatorView(
          color: Colors.grey,
          label: '未连接',
          tooltip: '服务端连接状态未知',
        );
    }
  }

  String _indicatorLabel(
    ServerConnectionState state,
    _ConnectionIndicatorView fallback,
  ) {
    if (state.level != ServerConnectionLevel.syncing) {
      return fallback.label;
    }
    return _phaseLabel(state.syncPhase);
  }

  String _indicatorTooltip(
    ServerConnectionState state,
    _ConnectionIndicatorView fallback,
  ) {
    if (state.level != ServerConnectionLevel.syncing) {
      return fallback.tooltip;
    }
    final parts = <String>[_phaseLabel(state.syncPhase)];
    if (state.syncReason != null && state.syncReason!.isNotEmpty) {
      parts.add(state.syncReason!);
    }
    final progress = _progressText(state);
    if (progress.isNotEmpty) {
      parts.add(progress);
    }
    return parts.join(' · ');
  }

  String _phaseLabel(String? phase) {
    switch (phase) {
      case 'queued':
        return '已排队';
      case 'preparing':
        return '准备同步';
      case 'pushing':
        return '推送本地';
      case 'tracking_upload':
        return '上传追踪';
      case 'pulling':
        return '拉取远端';
      case 'applying':
        return '应用变更';
      case 'completed':
        return '同步完成';
      case 'failed':
        return '同步失败';
      default:
        return '同步中';
    }
  }

  String _progressText(ServerConnectionState state) {
    final current = state.progressCurrent;
    final total = state.progressTotal;
    if (current == null && total == null) {
      return '';
    }
    if (total == null || total <= 0) {
      return '${current ?? 0}';
    }
    return '${current ?? 0}/$total';
  }

  Future<void> _showConnectionDialog(
    BuildContext context,
    ServerConnectionService service,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final state = service.state;
          final view = _viewFor(state);
          return AlertDialog(
            title: Row(
              children: [
                _StatusDot(color: view.color, size: 12),
                const SizedBox(width: 8),
                Text('服务端连接：${view.label}'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InfoRow('服务端地址', state.serverUrl),
                  _InfoRow('设备 ID', state.deviceId),
                  _InfoRow('平台', state.platform),
                  _InfoRow('最后心跳', _formatTime(state.lastHeartbeatAt)),
                  _InfoRow('最后同步', _formatTime(state.lastSyncAt)),
                  _InfoRow('等待同步', '${state.pendingCount}'),
                  _InfoRow('同步失败', '${state.failedCount}'),
                  _InfoRow('冲突', '${state.conflictCount}'),
                  if (state.lastError != null)
                    _InfoRow('最近错误', state.lastError!),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  context.push(AppRoutes.serverSync);
                },
                child: const Text('同步详情'),
              ),
              FilledButton.icon(
                onPressed: state.syncing
                    ? null
                    : () => service.syncNow(source: 'manual_indicator'),
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('立即同步'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) {
      return '尚无';
    }
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute:$second';
  }
}

class _IndicatorShell extends StatelessWidget {
  const _IndicatorShell({
    required this.compact,
    required this.color,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final bool compact;
  final Color color;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.32)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusDot(color: color),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, this.size = 9});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _ConnectionIndicatorView {
  const _ConnectionIndicatorView({
    required this.color,
    required this.label,
    required this.tooltip,
  });

  final Color color;
  final String label;
  final String tooltip;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '无' : value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
