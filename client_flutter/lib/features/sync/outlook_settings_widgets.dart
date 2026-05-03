part of 'outlook_settings_page_body.dart';

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isAuthenticated,
    required this.hasRequiredPermission,
    required this.syncMode,
    required this.grantedMode,
    required this.lastSync,
    required this.isRefreshingToken,
    required this.lastSyncFailed,
  });

  final bool isAuthenticated;
  final bool hasRequiredPermission;
  final OutlookSyncMode syncMode;
  final OutlookSyncMode grantedMode;
  final DateTime? lastSync;
  final bool isRefreshingToken;
  final bool lastSyncFailed;

  @override
  Widget build(BuildContext context) {
    final enabled = isAuthenticated && syncMode.allowsPull && hasRequiredPermission;
    final color = isRefreshingToken
        ? const Color(0xFF1E88E5)
        : lastSyncFailed
            ? const Color(0xFFE53935)
            : enabled
        ? const Color(0xFF43A047)
        : syncMode == OutlookSyncMode.paused
            ? Colors.orange
            : const Color(0xFFFB8C00);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            enabled ? Icons.cloud_done : Icons.cloud_off,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titleText(),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '当前连接状态：${_connectionStatusLabel()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '\u5f53\u524d\u6a21\u5f0f\uff1a${syncMode.label}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (isAuthenticated) ...[
                  const SizedBox(height: 2),
                  Text(
                    '\u5f53\u524d\u6388\u6743\uff1a${_permissionLabel(grantedMode)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  syncMode.description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (isAuthenticated && !hasRequiredPermission) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '\u5f53\u524d\u6a21\u5f0f\u4e0e\u6388\u6743\u4e0d\u5339\u914d\uff0c\u8bf7\u91cd\u65b0\u8fdb\u884c Outlook \u8ba4\u8bc1\u3002',
                    style: TextStyle(fontSize: 12, color: Color(0xFFFB8C00)),
                  ),
                ],
                if (lastSync != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '\u4e0a\u6b21\u540c\u6b65\uff1a${_formatDateTime(lastSync!)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _titleText() {
    if (isRefreshingToken) {
      return 'Outlook 连接仍可继续，正在刷新 token';
    }
    if (!isAuthenticated) {
      return '\u5c1a\u672a\u8fde\u63a5 Outlook';
    }
    if (lastSyncFailed) {
      return 'Outlook 已连接，但最近一次同步失败';
    }
    if (!hasRequiredPermission) {
      return '\u5df2\u8fde\u63a5 Outlook\uff08\u9700\u8981\u91cd\u65b0\u8ba4\u8bc1\uff09';
    }
    if (grantedMode == OutlookSyncMode.bidirectional) {
      return '\u5df2\u8fde\u63a5 Outlook\uff08\u8bfb\u5199\u6388\u6743\uff09';
    }
    return '\u5df2\u8fde\u63a5 Outlook\uff08\u53ea\u8bfb\u6388\u6743\uff09';
  }

  String _connectionStatusLabel() {
    if (isRefreshingToken) {
      return 'token 已过期，正在刷新';
    }
    if (!isAuthenticated) {
      return '未连接';
    }
    if (lastSyncFailed) {
      return '同步失败';
    }
    return '已连接';
  }

  String _permissionLabel(OutlookSyncMode mode) {
    switch (mode) {
      case OutlookSyncMode.paused:
      case OutlookSyncMode.readOnly:
        return '\u53ea\u8bfb\u6388\u6743';
      case OutlookSyncMode.bidirectional:
        return '\u8bfb\u5199\u6388\u6743';
    }
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _OutlookAdvancedSection extends StatelessWidget {
  const _OutlookAdvancedSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        children: [
          child,
        ],
      ),
    );
  }
}

class _StaticConfigTile extends StatelessWidget {
  const _StaticConfigTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.num,
    required this.text,
  });

  final String num;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            num,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

class _InlineStateHint extends StatelessWidget {
  const _InlineStateHint({
    required this.icon,
    required this.message,
    this.iconColor = Colors.grey,
  });

  final IconData icon;
  final String message;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncScopeTile extends StatelessWidget {
  const _SyncScopeTile({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.status,
    required this.detail,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String status;
  final String detail;
  final String? actionLabel;
  final IconData? actionIcon;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (onAction != null && actionLabel != null) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
                          await onAction!.call();
                        },
                        icon: Icon(
                          actionIcon ?? Icons.open_in_new,
                          size: 16,
                        ),
                        label: Text(actionLabel!),
                        style: TextButton.styleFrom(
                          foregroundColor: accentColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlookRunLogTile extends StatelessWidget {
  const _OutlookRunLogTile({required this.run});

  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context) {
    final metadata = _map(run['metadata']);
    final fieldStats = _map(metadata['fieldStats']);
    final samples = _listOfMaps(metadata['graphEventSamples']);
    final fallbackSamples = _listOfMaps(metadata['recurrenceFallbackSamples']);
    final calendars = _listOfMaps(metadata['calendars']);
    final status = '${run['status'] ?? 'unknown'}';
    final error = '${run['errorMessage'] ?? ''}'.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          status == 'succeeded'
              ? Icons.check_circle_outline
              : status == 'failed'
                  ? Icons.error_outline
                  : Icons.sync,
          color: status == 'succeeded'
              ? Colors.green
              : status == 'failed'
                  ? Colors.redAccent
                  : AppColors.primary,
        ),
        title: Text(
          '${run['triggerSource'] ?? 'unknown'} · $status · ${run['startedAt'] ?? ''}',
        ),
        subtitle: Text(
          '日历 ${run['calendarCount'] ?? 0}，更新 ${run['eventUpserts'] ?? 0}，删除 ${run['eventDeletes'] ?? 0}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          if (error.isNotEmpty)
            _InlineStateHint(
              icon: Icons.error_outline,
              iconColor: Colors.redAccent,
              message: error,
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Graph 字段统计：总事件 ${fieldStats['totalEvents'] ?? 0}，删除 ${fieldStats['removedEvents'] ?? 0}，private ${fieldStats['privateEvents'] ?? 0}，缺 subject ${fieldStats['missingSubject'] ?? 0}，缺 location ${fieldStats['missingLocation'] ?? 0}，缺 bodyPreview ${fieldStats['missingBodyPreview'] ?? 0}，缺 organizer ${fieldStats['missingOrganizer'] ?? 0}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '重复日程补全：已补 ${fieldStats['recurrenceFallbacks'] ?? 0}，master 查找失败 ${fieldStats['masterLookupFailures'] ?? 0}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (calendars.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '日历分页：${calendars.map((item) => '${item['name'] ?? 'Outlook'} ${item['pageCount'] ?? 0}页/${item['eventCount'] ?? 0}项').join('；')}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
          if (samples.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final sample in samples.take(5))
              _OutlookGraphSampleTile(sample: sample),
          ],
          if (fallbackSamples.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'occurrence master fallback 样本',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            for (final sample in fallbackSamples.take(5))
              _OutlookGraphSampleTile(sample: sample),
          ],
        ],
      ),
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _listOfMaps(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
}

class _OutlookGraphSampleTile extends StatelessWidget {
  const _OutlookGraphSampleTile({required this.sample});

  final Map<String, dynamic> sample;

  @override
  Widget build(BuildContext context) {
    final mapped = sample['mappedPayload'];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        'Graph: id=${sample['id']}, subject=${sample['subject']}, location=${sample['location']}, bodyPreview=${sample['bodyPreview']}, organizer=${sample['organizer']}, attendees=${sample['attendees']}, start=${sample['start']}, end=${sample['end']}, sensitivity=${sample['sensitivity']}, showAs=${sample['showAs']}, type=${sample['type']}, removed=${sample['removed']}\nMapped payload: $mapped',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

