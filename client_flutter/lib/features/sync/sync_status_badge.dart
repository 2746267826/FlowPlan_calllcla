import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_status.dart';
import '../../shared/providers/app_providers.dart';

final syncObjectStateByKeyProvider =
    FutureProvider.autoDispose.family<SyncObjectState?, String>((ref, key) {
  final separator = key.indexOf('|');
  if (separator <= 0 || separator >= key.length - 1) {
    return Future<SyncObjectState?>.value(null);
  }
  final objectType = key.substring(0, separator);
  final localId = key.substring(separator + 1);
  return ref.read(syncObjectStateStoreProvider).getState(
        objectType: objectType,
        localId: localId,
      );
});

class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({
    super.key,
    required this.objectType,
    required this.localId,
  });

  final String objectType;
  final String localId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync =
        ref.watch(syncObjectStateByKeyProvider('$objectType|$localId'));
    return stateAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => _Badge(
        icon: Icons.error_outline,
        label: '同步状态读取失败',
        color: Colors.redAccent,
        tooltip: error.toString(),
      ),
      data: (state) {
        final view = _viewFor(state);
        return _Badge(
          icon: view.icon,
          label: view.label,
          color: view.color,
          tooltip: view.tooltip,
        );
      },
    );
  }

  _SyncBadgeView _viewFor(SyncObjectState? state) {
    if (state == null) {
      return const _SyncBadgeView(
        icon: Icons.cloud_off_outlined,
        label: '仅本地',
        color: Colors.blueGrey,
        tooltip: '此对象还没有服务端同步状态记录',
      );
    }
    switch (state.syncState) {
      case SyncState.synced:
        return _SyncBadgeView(
          icon: Icons.cloud_done_outlined,
          label: '已同步',
          color: Colors.green,
          tooltip: state.lastSyncedAt == null
              ? '服务端已接收'
              : '最后同步：${_formatTime(state.lastSyncedAt!)}',
        );
      case SyncState.pendingCreate:
      case SyncState.pendingUpdate:
      case SyncState.pendingDelete:
        return const _SyncBadgeView(
          icon: Icons.cloud_upload_outlined,
          label: '等待同步',
          color: Colors.orange,
          tooltip: '本地已保存，等待推送到服务端',
        );
      case SyncState.failed:
        return _SyncBadgeView(
          icon: Icons.sync_problem_outlined,
          label: '同步失败',
          color: Colors.redAccent,
          tooltip: state.lastSyncError?.isNotEmpty == true
              ? state.lastSyncError!
              : '最近一次推送失败，可在服务端同步页重试',
        );
      case SyncState.conflict:
        return const _SyncBadgeView(
          icon: Icons.report_problem_outlined,
          label: '有冲突',
          color: Colors.deepOrange,
          tooltip: '服务端返回冲突候选，需要人工处理',
        );
    }
  }

  String _formatTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}

class _SyncBadgeView {
  const _SyncBadgeView({
    required this.icon,
    required this.label,
    required this.color,
    required this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String tooltip;
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
    required this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
