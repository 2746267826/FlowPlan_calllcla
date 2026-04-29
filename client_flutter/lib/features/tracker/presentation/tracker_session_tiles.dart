part of 'tracker_page.dart';

class _WorkSessionTile extends StatelessWidget {
  final WorkSession session;
  final DateTime selectedDate;
  final String? selectedProcess;
  final int? selectedHour;
  final Map<int, TaskItem> taskById;
  final ValueChanged<String>? onLinkProcessAnalysis;
  final ValueChanged<int>? onLinkHourAnalysis;
  final VoidCallback? onBindTask;
  final ValueChanged<int>? onOpenTask;
  final ValueChanged<ActivityRecord>? onBindRecordTask;

  const _WorkSessionTile({
    required this.session,
    required this.selectedDate,
    this.selectedProcess,
    this.selectedHour,
    this.taskById = const <int, TaskItem>{},
    this.onLinkProcessAnalysis,
    this.onLinkHourAnalysis,
    this.onBindTask,
    this.onOpenTask,
    this.onBindRecordTask,
  });

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (session.category != null && session.category!.trim().isNotEmpty)
        session.category!.trim(),
      if (!session.spansMultipleProcesses &&
          session.processName != null &&
          session.processName!.trim().isNotEmpty)
        session.processName!.trim(),
      if (session.spansMultipleProcesses) '${session.processNames.length} 个应用',
      if (session.spansMultipleCategories) '${session.categories.length} 个分类',
    ].join(' \u00b7 ');
    final processSummary = _joinPreview(session.processNames);
    final linkedTaskIds = _collectLinkedTaskIds(session.records);
    final singleLinkedTaskId =
        linkedTaskIds.length == 1 ? linkedTaskIds.first : null;
    final primaryProcess = session.processName?.trim().isNotEmpty == true
        ? session.processName!.trim()
        : null;
    final linkedHour = _dominantHourForRange(
      itemStart: session.startTime,
      itemEnd: session.endTime,
      selectedDate: selectedDate,
    );
    final isProcessLinked =
        primaryProcess != null && primaryProcess == selectedProcess;
    final isHourLinked = linkedHour != null && linkedHour == selectedHour;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  '${_formatTime(session.startTime)} - ${_formatTime(session.endTime)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  session.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _formatMinutes(session.durationMinutes),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            meta.isEmpty ? '\u672a\u5206\u7c7b\u5de5\u4f5c\u4f1a\u8bdd' : meta,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (session.spansMultipleProcesses) ...[
            const SizedBox(height: 4),
            Text(
              '涉及应用：$processSummary',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          if (linkedTaskIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: linkedTaskIds
                  .map(
                    (taskId) => _tag(
                      '任务：${_taskLabel(taskById[taskId], fallbackId: taskId)}',
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag('${session.rawRecordCount} '
                  '\u6761\u539f\u59cb\u8bb0\u5f55'),
              if (session.spansMultipleProcesses)
                _tag('跨 ${session.processNames.length} 个应用'),
              if (session.interruptionCount > 0)
                _tag('已吸收 ${session.interruptionCount} 次打断'),
              _tag('${session.keyCount} \u6b21\u6309\u952e'),
              _tag('${session.mouseClicks} \u6b21\u70b9\u51fb'),
              _tag('${session.mouseMovePx}px \u79fb\u52a8'),
              _tag('${session.scrollPx}px \u6eda\u52a8'),
            ],
          ),
          if (onLinkProcessAnalysis != null || onLinkHourAnalysis != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (primaryProcess != null && onLinkProcessAnalysis != null)
                  ActionChip(
                    onPressed: () => onLinkProcessAnalysis!(primaryProcess),
                    avatar: isProcessLinked
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: AppColors.primary,
                          )
                        : const Icon(Icons.tune, size: 16),
                    label: Text(
                      isProcessLinked
                          ? '已联动应用分析'
                          : '查看「$primaryProcess」输入分析',
                    ),
                  ),
                if (linkedHour != null && onLinkHourAnalysis != null)
                  ActionChip(
                    onPressed: () => onLinkHourAnalysis!(linkedHour),
                    avatar: isHourLinked
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: AppColors.primary,
                          )
                        : const Icon(Icons.schedule_outlined, size: 16),
                    label: Text(
                      isHourLinked
                          ? '已联动时段分析'
                          : '查看 ${_formatHourLabel(linkedHour)} 输入分析',
                    ),
                  ),
              ],
            ),
          ],
          if (onBindTask != null || (singleLinkedTaskId != null && onOpenTask != null)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onBindTask != null)
                  TextButton.icon(
                    onPressed: onBindTask,
                    icon: const Icon(Icons.link_outlined, size: 16),
                    label: Text(
                      linkedTaskIds.isEmpty ? '关联任务' : '调整任务关联',
                    ),
                  ),
                if (singleLinkedTaskId != null && onOpenTask != null)
                  TextButton.icon(
                    onPressed: () => onOpenTask!(singleLinkedTaskId),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('打开任务'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: const Text(
                '\u67e5\u770b\u539f\u59cb\u8bb0\u5f55\u4e0e\u5408\u5e76\u7ec6\u8282',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                session.interruptionCount > 0
                    ? '\u672c\u6bb5\u5305\u542b ${session.rawRecordCount} \u6761\u539f\u59cb\u8bb0\u5f55\uff0c\u5176\u4e2d ${session.interruptionCount} \u6b21\u6253\u65ad\u5df2\u88ab\u5438\u6536'
                    : '\u672c\u6bb5\u5305\u542b ${session.rawRecordCount} \u6761\u539f\u59cb\u8bb0\u5f55',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              children: [
                if (session.categories.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '涉及分类：${session.categories.join('\u3001')}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ),
                if (session.processNames.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '涉及应用：${session.processNames.join('\u3001')}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ),
                ...session.records.map(
                  (record) => _SessionRecordRow(
                    record: record,
                    selectedDate: selectedDate,
                    selectedProcess: selectedProcess,
                    selectedHour: selectedHour,
                    taskById: taskById,
                    onLinkProcessAnalysis: onLinkProcessAnalysis,
                    onLinkHourAnalysis: onLinkHourAnalysis,
                    onBindTask: onBindRecordTask == null
                        ? null
                        : () => onBindRecordTask!(record),
                    onOpenTask: record.linkedTaskId != null && onOpenTask != null
                        ? () => onOpenTask!(record.linkedTaskId!)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRecordRow extends StatelessWidget {
  final ActivityRecord record;
  final DateTime? selectedDate;
  final String? selectedProcess;
  final int? selectedHour;
  final Map<int, TaskItem> taskById;
  final ValueChanged<String>? onLinkProcessAnalysis;
  final ValueChanged<int>? onLinkHourAnalysis;
  final VoidCallback? onBindTask;
  final VoidCallback? onOpenTask;

  const _SessionRecordRow({
    required this.record,
    this.selectedDate,
    this.selectedProcess,
    this.selectedHour,
    this.taskById = const <int, TaskItem>{},
    this.onLinkProcessAnalysis,
    this.onLinkHourAnalysis,
    this.onBindTask,
    this.onOpenTask,
  });

  @override
  Widget build(BuildContext context) {
    final title = WorkSessionGrouper.preferredLabel(record);
    final endTime = record.endTime ?? record.startTime;
    final linkedTaskId = record.linkedTaskId;
    final linkedTask =
        linkedTaskId == null ? null : taskById[linkedTaskId];
    final processName = record.processName?.trim().isNotEmpty == true
        ? record.processName!.trim()
        : null;
    final linkedHour = selectedDate == null
        ? null
        : _dominantHourForRange(
            itemStart: record.startTime,
            itemEnd: endTime,
            selectedDate: selectedDate!,
          );
    final isProcessLinked =
        processName != null && processName == selectedProcess;
    final isHourLinked = linkedHour != null && linkedHour == selectedHour;
    final meta = <String>[
      if (record.category != null && record.category!.trim().isNotEmpty)
        record.category!.trim(),
      if (record.processName != null && record.processName!.trim().isNotEmpty)
        record.processName!.trim(),
    ].join(' \u00b7 ');
    final metrics = <String>[
      if (record.durationMinutes > 0) '${record.durationMinutes} \u5206\u949f',
      if (record.keyCount > 0) '${record.keyCount} \u6b21\u6309\u952e',
      if (record.mouseClicks > 0) '${record.mouseClicks} \u6b21\u70b9\u51fb',
      if (record.mouseMovePx > 0) '${record.mouseMovePx}px \u79fb\u52a8',
      if (record.scrollPx > 0) '${record.scrollPx}px \u6eda\u52a8',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  '${_formatTime(record.startTime)} - ${_formatTime(endTime)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metrics.map(_tag).toList(),
            ),
          ],
          if (linkedTaskId != null) ...[
            const SizedBox(height: 6),
            Text(
              '关联任务：${_taskLabel(linkedTask, fallbackId: linkedTaskId)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (onLinkProcessAnalysis != null ||
              onLinkHourAnalysis != null ||
              onBindTask != null ||
              onOpenTask != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (processName != null && onLinkProcessAnalysis != null)
                  TextButton.icon(
                    onPressed: () => onLinkProcessAnalysis!(processName),
                    icon: Icon(
                      isProcessLinked
                          ? Icons.check_circle
                          : Icons.tune_outlined,
                      size: 14,
                    ),
                    label: Text(
                      isProcessLinked ? '已联动应用分析' : '联动应用分析',
                    ),
                  ),
                if (linkedHour != null && onLinkHourAnalysis != null)
                  TextButton.icon(
                    onPressed: () => onLinkHourAnalysis!(linkedHour),
                    icon: Icon(
                      isHourLinked
                          ? Icons.check_circle
                          : Icons.schedule_outlined,
                      size: 14,
                    ),
                    label: Text(
                      isHourLinked
                          ? '已联动时段分析'
                          : '联动 ${_formatHourLabel(linkedHour)}',
                    ),
                  ),
                if (onBindTask != null)
                  TextButton.icon(
                    onPressed: onBindTask,
                    icon: const Icon(Icons.link_outlined, size: 14),
                    label: Text(
                      linkedTaskId == null ? '关联任务' : '改绑任务',
                    ),
                  ),
                if (onOpenTask != null)
                  TextButton.icon(
                    onPressed: onOpenTask,
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('打开任务'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final ActivityLogEntry entry;
  final bool showDate;
  final bool showDetails;

  const _LogEntryTile({
    required this.entry,
    this.showDate = false,
    this.showDetails = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = entry.label?.trim().isNotEmpty == true
        ? entry.label!.trim()
        : (entry.windowTitle?.trim().isNotEmpty == true
            ? entry.windowTitle!.trim()
            : (entry.processName?.trim().isNotEmpty == true
                ? entry.processName!.trim()
                : '\u672a\u547d\u540d\u65e5\u5fd7\u9879'));

    final subtitle = <String>[
      if (entry.category != null && entry.category!.trim().isNotEmpty)
        entry.category!.trim(),
      if (entry.processName != null && entry.processName!.trim().isNotEmpty)
        entry.processName!.trim(),
      if (entry.isIgnored) '\u81ea\u6392\u9664',
    ].join(' \u00b7 ');

    final metrics = <String>[
      if (entry.keyCount > 0) '${entry.keyCount} \u6b21\u6309\u952e',
      if (entry.mouseClicks > 0) '${entry.mouseClicks} \u6b21\u70b9\u51fb',
      if (entry.mouseMovePx > 0) '${entry.mouseMovePx}px \u79fb\u52a8',
      if (entry.scrollPx > 0) '${entry.scrollPx}px \u6eda\u52a8',
      if (entry.durationMinutes != null)
        '${entry.durationMinutes} \u5206\u949f',
    ];
    final detailLines = <String>[
      if (entry.windowTitle != null &&
          entry.windowTitle!.trim().isNotEmpty &&
          entry.windowTitle!.trim() != title)
        '窗口标题：${entry.windowTitle!.trim()}',
      if (entry.className != null && entry.className!.trim().isNotEmpty)
        '窗口类名：${entry.className!.trim()}',
      if (entry.recordId != null) '关联记录：#${entry.recordId}',
      if (entry.isFullscreen) '窗口状态：全屏',
      if (entry.note != null && entry.note!.trim().isNotEmpty)
        '备注：${entry.note!.trim()}',
    ];
    final keySequence = entry.keySequence?.trim();
    final hasDetails =
        showDetails &&
        (detailLines.isNotEmpty || (keySequence != null && keySequence.isNotEmpty));
    final timeLabel = showDate
        ? _formatDateTimeShort(entry.timestamp)
        : _formatTime(entry.timestamp);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: showDate ? 104 : 64,
                child: Text(
                  timeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(
                _entryTypeLabel(entry.type),
                entry.isIgnored
                    ? const Color(0xFFF5935A)
                    : const Color(0xFF0EA8A0),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metrics.map(_tag).toList(),
            ),
          ],
          if (hasDetails) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: const Text(
                  '查看日志详情',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                children: [
                  for (final line in detailLines)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          line,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  if (keySequence != null && keySequence.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '按键序列：${keySequence.replaceAll('\n', ' <回车> ')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _entryTypeLabel(ActivityLogEntryType type) {
    switch (type) {
      case ActivityLogEntryType.sample:
        return '\u91c7\u6837';
      case ActivityLogEntryType.sessionOpen:
        return '\u4f1a\u8bdd\u5f00\u59cb';
      case ActivityLogEntryType.sessionUpdate:
        return '\u4f1a\u8bdd\u66f4\u65b0';
      case ActivityLogEntryType.sessionClose:
        return '\u4f1a\u8bdd\u7ed3\u675f';
      case ActivityLogEntryType.snapshot:
        return '\u5feb\u7167';
    }
  }
}

