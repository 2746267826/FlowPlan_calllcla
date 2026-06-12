import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/app_providers.dart';
import '../models/input_event_query.dart';
import '../models/input_heatmap_summary.dart';
import '../models/tracked_input_event.dart';

enum _InputRangePreset { today, sevenDays, thirtyDays, all, custom }

class InputHeatmapPage extends ConsumerStatefulWidget {
  const InputHeatmapPage({super.key});

  @override
  ConsumerState<InputHeatmapPage> createState() => _InputHeatmapPageState();
}

@visibleForTesting
InputEventQuery debugBuildCustomInputHeatmapQueryWithoutRange({
  required DateTime now,
  String? processName,
}) {
  return _customInputHeatmapQuery(
    now: now,
    range: null,
    processName: processName,
  );
}

class _InputHeatmapPageState extends ConsumerState<InputHeatmapPage> {
  _InputRangePreset _rangePreset = _InputRangePreset.today;
  String? _selectedProcess;
  DateTimeRange? _customRange;
  AsyncValue<List<String>> _processOptionsAsync = const AsyncValue.loading();
  AsyncValue<InputHeatmapSummary> _summaryAsync = const AsyncValue.loading();
  bool _isRefreshing = false;
  DateTime? _lastRefreshedAt;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_reloadPage);
  }

  @override
  Widget build(BuildContext context) {
    final processOptions = _processOptionsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <String>[],
    );
    final effectiveProcess =
        processOptions.contains(_selectedProcess) ? _selectedProcess : null;
    final query = _buildQuery(processName: effectiveProcess);

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u952e\u9f20\u70ed\u529b\u56fe'),
        actions: [
          IconButton(
            tooltip: _isRefreshing
                ? '\u6b63\u5728\u5237\u65b0'
                : '\u624b\u52a8\u5237\u65b0',
            onPressed: _isRefreshing ? null : _reloadPage,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '\u5bfc\u51fa\u5f53\u524d\u7b5b\u9009\u7ed3\u679c',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _exportCurrentFilter(query),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\u7b5b\u9009\u6761\u4ef6',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    key: ValueKey<String?>(effectiveProcess),
                    initialValue: effectiveProcess,
                    decoration: const InputDecoration(
                      labelText: '\u5e94\u7528\u7a0b\u5e8f',
                      border: OutlineInputBorder(),
                    ),
                    isExpanded: true,
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('\u5168\u90e8\u5e94\u7528'),
                      ),
                      ...processOptions.map(
                        (process) => DropdownMenuItem<String?>(
                          value: process,
                          child: Text(process),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedProcess = value;
                      });
                      unawaited(_reloadSummary());
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _RangeChip(
                        label: '\u4eca\u5929',
                        selected: _rangePreset == _InputRangePreset.today,
                        onSelected: () =>
                            _setRangePreset(_InputRangePreset.today),
                      ),
                      _RangeChip(
                        label: '\u6700\u8fd1 7 \u5929',
                        selected: _rangePreset == _InputRangePreset.sevenDays,
                        onSelected: () =>
                            _setRangePreset(_InputRangePreset.sevenDays),
                      ),
                      _RangeChip(
                        label: '\u6700\u8fd1 30 \u5929',
                        selected: _rangePreset == _InputRangePreset.thirtyDays,
                        onSelected: () =>
                            _setRangePreset(_InputRangePreset.thirtyDays),
                      ),
                      _RangeChip(
                        label: '\u5168\u90e8\u65f6\u95f4',
                        selected: _rangePreset == _InputRangePreset.all,
                        onSelected: () =>
                            _setRangePreset(_InputRangePreset.all),
                      ),
                      _RangeChip(
                        label: '\u81ea\u5b9a\u4e49',
                        selected: _rangePreset == _InputRangePreset.custom,
                        onSelected: _pickCustomRange,
                      ),
                    ],
                  ),
                  if (_rangePreset == _InputRangePreset.custom) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _pickCustomRange,
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(
                        _customRange == null
                            ? '\u9009\u62e9\u81ea\u5b9a\u4e49\u65e5\u671f\u8303\u56f4'
                            : '\u5df2\u9009\u62e9\uff1a${_formatDate(_customRange!.start)} '
                                '\u81f3 ${_formatDate(_customRange!.end)}',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '\u5f53\u524d\u8303\u56f4\uff1a${_describeQuery(query)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isRefreshing
                        ? '\u6b63\u5728\u5237\u65b0\u5f53\u524d\u89c6\u56fe\uff0c'
                            '\u4f1a\u5c3d\u91cf\u4fdd\u7559\u5df2\u663e\u793a\u5185\u5bb9\u3002'
                        : _lastRefreshedAt == null
                            ? '\u672c\u9875\u4e0d\u4f1a\u968f\u540e\u53f0\u91c7\u6837'
                                '\u81ea\u52a8\u6574\u9875\u5237\u65b0\uff0c'
                                '\u53ef\u7528\u53f3\u4e0a\u89d2\u5237\u65b0\u6309\u94ae\u624b\u52a8\u66f4\u65b0\u3002'
                            : '\u6700\u540e\u5237\u65b0\uff1a${_formatDateTime(_lastRefreshedAt!)}'
                                ' \u00b7 \u540e\u53f0\u65b0\u6570\u636e\u4e0d\u4f1a'
                                '\u81ea\u52a8\u6253\u65ad\u5f53\u524d\u67e5\u770b\u3002',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '\u70ed\u529b\u56fe\u9ed8\u8ba4\u6392\u9664 FlowPlanV2 '
                    '\u672c\u4f53\u7b49\u5df2\u5ffd\u7565\u7a97\u53e3\uff0c'
                    '\u4ec5\u5c55\u793a\u53ef\u5206\u6790\u7684\u5916\u90e8\u8f93\u5165\u8bb0\u5f55\u3002',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isRefreshing && _summaryAsync.hasValue)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            _summaryAsync.when(
              loading: () => const _SectionCard(
                child: SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => _SectionCard(
                child: SizedBox(
                  height: 180,
                  child: Center(
                    child: Text(
                        '\u52a0\u8f7d\u952e\u9f20\u70ed\u529b\u56fe\u5931\u8d25\uff1a$error'),
                  ),
                ),
              ),
              data: (summary) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCard(context, summary),
                  const SizedBox(height: 16),
                  _SectionCard(
                    child: _InputBehaviorOverviewPanel(summary: summary),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(child: _KeyboardHeatmap(summary: summary)),
                  const SizedBox(height: 16),
                  _SectionCard(child: _MouseHeatmap(summary: summary)),
                  const SizedBox(height: 16),
                  _SectionCard(child: _TopKeysAnalysisPanel(summary: summary)),
                  const SizedBox(height: 16),
                  _SectionCard(
                    child: _ProcessIntensityAnalysisPanel(summary: summary),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    child: _HourlyDistributionAnalysisPanel(summary: summary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reloadPage() async {
    final hasProcessValue = _processOptionsAsync.hasValue;
    final hasSummaryValue = _summaryAsync.hasValue;
    setState(() {
      _isRefreshing = true;
      if (!hasProcessValue) {
        _processOptionsAsync = const AsyncValue.loading();
      }
      if (!hasSummaryValue) {
        _summaryAsync = const AsyncValue.loading();
      }
    });

    ref.invalidate(inputEventProcessOptionsProvider);
    final nextProcessOptions = await AsyncValue.guard(
      () => ref.read(inputEventProcessOptionsProvider.future),
    );
    if (!mounted) {
      return;
    }

    final processOptions = nextProcessOptions.valueOrNull ??
        _processOptionsAsync.valueOrNull ??
        const <String>[];
    final effectiveProcess =
        processOptions.contains(_selectedProcess) ? _selectedProcess : null;
    final nextQuery = _buildQuery(processName: effectiveProcess);

    ref.invalidate(inputHeatmapSummaryProvider(nextQuery));
    final nextSummary = await AsyncValue.guard(
      () => ref.read(inputHeatmapSummaryProvider(nextQuery).future),
    );
    if (!mounted) {
      return;
    }

    final processError = nextProcessOptions.whenOrNull(
      error: (error, _) => error,
    );
    final summaryError = nextSummary.whenOrNull(
      error: (error, _) => error,
    );

    setState(() {
      _selectedProcess = effectiveProcess;
      if (nextProcessOptions.hasValue || !hasProcessValue) {
        _processOptionsAsync = nextProcessOptions;
      }
      if (nextSummary.hasValue || !hasSummaryValue) {
        _summaryAsync = nextSummary;
      }
      _isRefreshing = false;
      if (nextSummary.hasValue) {
        _lastRefreshedAt = DateTime.now();
      }
    });

    if (processError != null) {
      _showMessage(
          '\u52a0\u8f7d\u5e94\u7528\u5217\u8868\u5931\u8d25\uff1a$processError');
    }
    if (summaryError != null) {
      _showMessage(
          '\u5237\u65b0\u952e\u9f20\u70ed\u529b\u56fe\u5931\u8d25\uff1a$summaryError');
    }
  }

  Future<void> _reloadSummary() async {
    final hasSummaryValue = _summaryAsync.hasValue;
    setState(() {
      _isRefreshing = true;
      if (!hasSummaryValue) {
        _summaryAsync = const AsyncValue.loading();
      }
    });

    final query = _buildQuery(
      processName: _effectiveProcess(
          _processOptionsAsync.valueOrNull ?? const <String>[]),
    );
    ref.invalidate(inputHeatmapSummaryProvider(query));
    final nextSummary = await AsyncValue.guard(
      () => ref.read(inputHeatmapSummaryProvider(query).future),
    );
    if (!mounted) {
      return;
    }

    final summaryError = nextSummary.whenOrNull(
      error: (error, _) => error,
    );
    setState(() {
      if (nextSummary.hasValue || !hasSummaryValue) {
        _summaryAsync = nextSummary;
      }
      _isRefreshing = false;
      if (nextSummary.hasValue) {
        _lastRefreshedAt = DateTime.now();
      }
    });

    if (summaryError != null) {
      _showMessage(
          '\u5237\u65b0\u952e\u9f20\u70ed\u529b\u56fe\u5931\u8d25\uff1a$summaryError');
    }
  }

  void _setRangePreset(_InputRangePreset preset) {
    if (_rangePreset == preset) {
      return;
    }
    setState(() {
      _rangePreset = preset;
    });
    unawaited(_reloadSummary());
  }

  String? _effectiveProcess(List<String> options) {
    return options.contains(_selectedProcess) ? _selectedProcess : null;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildSummaryCard(BuildContext context, InputHeatmapSummary summary) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u6982\u89c8',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryItem(
                title: '\u603b\u4e8b\u4ef6\u6570',
                value: '${summary.totalEventCount}',
                note: '\u5b8c\u6574\u987a\u5e8f\u4e8b\u4ef6\u6761\u76ee',
                color: const Color(0xFF2266CC),
              ),
              _SummaryItem(
                title: '\u952e\u76d8\u6309\u4e0b',
                value: '${summary.keyboardEventCount}',
                note: '\u6309\u952e\u8bb0\u5f55\u6b21\u6570',
                color: const Color(0xFFB85A00),
              ),
              _SummaryItem(
                title: '\u9f20\u6807\u6309\u952e',
                value: '${summary.mouseButtonEventCount}',
                note: '\u5de6\u53f3\u952e\u4e0e\u4fa7\u952e',
                color: const Color(0xFF0E8A75),
              ),
              _SummaryItem(
                title: '\u6eda\u8f6e\u4e8b\u4ef6',
                value: '${summary.wheelEventCount}',
                note: '\u542b\u7eb5\u5411\u4e0e\u6a2a\u5411\u6eda\u8f6e',
                color: const Color(0xFF7A4FD1),
              ),
              _SummaryItem(
                title: '\u9f20\u6807\u79fb\u52a8',
                value: '${summary.mouseMoveDistance}',
                note:
                    '\u7d2f\u8ba1 ${summary.mouseMoveEventCount} \u6b21\u79fb\u52a8\u8ddd\u79bb',
                color: const Color(0xFFCC3E68),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialRange = _customRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 6)),
          end: now,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: initialRange,
      helpText: '\u9009\u62e9\u65f6\u95f4\u8303\u56f4',
      saveText: '\u786e\u5b9a',
      cancelText: '\u53d6\u6d88',
      confirmText: '\u786e\u5b9a',
      errorInvalidRangeText: '\u65f6\u95f4\u8303\u56f4\u65e0\u6548',
      errorInvalidText: '\u65e5\u671f\u65e0\u6548',
      fieldStartHintText: '\u5f00\u59cb\u65e5\u671f',
      fieldEndHintText: '\u7ed3\u675f\u65e5\u671f',
      fieldStartLabelText: '\u5f00\u59cb\u65e5\u671f',
      fieldEndLabelText: '\u7ed3\u675f\u65e5\u671f',
    );
    if (!mounted || picked == null) {
      return;
    }
    setState(() {
      _customRange = picked;
      _rangePreset = _InputRangePreset.custom;
    });
    await _reloadSummary();
  }

  Future<void> _exportCurrentFilter(InputEventQuery _) async {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('当前筛选导出已迁移到服务端诊断包流程，本页只展示服务端汇总数据。'),
      ),
    );
  }

  InputEventQuery _buildQuery({required String? processName}) {
    final now = DateTime.now();
    switch (_rangePreset) {
      case _InputRangePreset.today:
        final start = _startOfDay(now);
        return InputEventQuery(
          start: start,
          end: start.add(const Duration(days: 1)),
          processName: processName,
        );
      case _InputRangePreset.sevenDays:
        final start = _startOfDay(now).subtract(const Duration(days: 6));
        return InputEventQuery(
          start: start,
          end: _startOfDay(now).add(const Duration(days: 1)),
          processName: processName,
        );
      case _InputRangePreset.thirtyDays:
        final start = _startOfDay(now).subtract(const Duration(days: 29));
        return InputEventQuery(
          start: start,
          end: _startOfDay(now).add(const Duration(days: 1)),
          processName: processName,
        );
      case _InputRangePreset.all:
        return InputEventQuery(processName: processName);
      case _InputRangePreset.custom:
        return _customInputHeatmapQuery(
          now: now,
          range: _customRange,
          processName: processName,
        );
    }
  }

  String _describeQuery(InputEventQuery query) {
    final timeLabel = switch (_rangePreset) {
      _InputRangePreset.today => '\u4eca\u5929',
      _InputRangePreset.sevenDays => '\u6700\u8fd1 7 \u5929',
      _InputRangePreset.thirtyDays => '\u6700\u8fd1 30 \u5929',
      _InputRangePreset.all => '\u5168\u90e8\u65f6\u95f4',
      _InputRangePreset.custom => _customRange == null
          ? '\u81ea\u5b9a\u4e49\u8303\u56f4'
          : '${_formatDate(_customRange!.start)} \u81f3 ${_formatDate(_customRange!.end)}',
    };
    final processLabel = query.processName == null
        ? '\u5168\u90e8\u5e94\u7528'
        : query.processName!;
    return '$timeLabel \u00b7 $processLabel';
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _formatDateTime(DateTime date) {
    final base = _formatDate(date);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    return '$base $hour:$minute:$second';
  }
}

InputEventQuery _customInputHeatmapQuery({
  required DateTime now,
  required DateTimeRange? range,
  required String? processName,
}) {
  if (range == null) {
    final start = _InputHeatmapPageState._startOfDay(now)
        .subtract(const Duration(days: 6));
    return InputEventQuery(
      start: start,
      end: _InputHeatmapPageState._startOfDay(now).add(const Duration(days: 1)),
      processName: processName,
    );
  }
  return InputEventQuery(
    start: _InputHeatmapPageState._startOfDay(range.start),
    end: _InputHeatmapPageState._startOfDay(range.end)
        .add(const Duration(days: 1)),
    processName: processName,
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.title,
    required this.value,
    required this.note,
    required this.color,
  });

  final String title;
  final String value;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(note, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }
}

class _InputBehaviorOverviewPanel extends StatelessWidget {
  const _InputBehaviorOverviewPanel({required this.summary});

  final InputHeatmapSummary summary;

  @override
  Widget build(BuildContext context) {
    final leadingKey = summary.leadingKey;
    final leadingProcess = summary.leadingProcessIntensity;
    final peakHour = summary.peakHourBucket;
    final hasData = summary.totalEventCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u8f93\u5165\u884c\u4e3a\u6982\u89c8',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          '\u628a\u5f53\u524d\u7b5b\u9009\u8303\u56f4\u5185\u7684\u8f93\u5165'
          '\u884c\u4e3a\u5148\u538b\u7f29\u6210\u51e0\u4e2a\u5173\u952e\u7ed3\u8bba\uff0c'
          '\u518d\u5411\u4e0b\u67e5\u770b\u8be6\u7ec6\u5206\u5e03\u3002',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        if (!hasData)
          const Text(
            '\u5f53\u524d\u7b5b\u9009\u6761\u4ef6\u4e0b\u6682\u65e0'
            '\u53ef\u7528\u7684\u8f93\u5165\u884c\u4e3a\u6982\u89c8\u3002',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _OverviewMetricTile(
                title: '\u6700\u5e38\u7528\u6309\u952e',
                value: leadingKey?.label ?? '\u6682\u65e0',
                note: leadingKey == null
                    ? '\u5f53\u524d\u8303\u56f4\u5185\u6682\u65e0\u952e\u76d8\u8f93\u5165'
                    : '${leadingKey.count}\u6b21'
                        ' \u00b7 \u5360\u952e\u76d8\u8f93\u5165 '
                        '${_formatPercent(leadingKey.share)}',
                color: const Color(0xFFCC6100),
              ),
              _OverviewMetricTile(
                title: '\u6700\u6d3b\u8dc3\u5e94\u7528',
                value: leadingProcess?.processName ?? '\u6682\u65e0',
                note: leadingProcess == null
                    ? '\u5f53\u524d\u8303\u56f4\u5185\u6682\u65e0\u5e94\u7528\u8f93\u5165'
                    : '${leadingProcess.totalEvents}\u6761\u4e8b\u4ef6'
                        ' \u00b7 \u5f3a\u5ea6 ${leadingProcess.intensityScore}'
                        ' \u00b7 \u6d3b\u8dc3 ${leadingProcess.activeMinutes}\u5206\u949f',
                color: const Color(0xFF0E8A75),
              ),
              _OverviewMetricTile(
                title: '\u5cf0\u503c\u65f6\u6bb5',
                value: peakHour == null
                    ? '\u6682\u65e0'
                    : _formatHourRange(peakHour.hour),
                note: peakHour == null
                    ? '\u5f53\u524d\u8303\u56f4\u5185\u6682\u65e0\u65f6\u6bb5\u5206\u5e03'
                    : '${peakHour.totalEvents}\u6761\u4e8b\u4ef6'
                        ' \u00b7 \u5f3a\u5ea6 ${peakHour.intensityScore}'
                        ' \u00b7 \u6d3b\u8dc3 ${peakHour.activeMinutes}\u5206\u949f',
                color: const Color(0xFF2266CC),
              ),
              _OverviewMetricTile(
                title: '\u8f93\u5165\u5bc6\u5ea6',
                value: summary.activeMinuteCount <= 0
                    ? '\u6682\u65e0'
                    : '${_formatDecimal(summary.averageEventsPerActiveMinute)}'
                        ' \u6761/\u5206\u949f',
                note: summary.activeMinuteCount <= 0
                    ? '\u5f53\u524d\u8303\u56f4\u5185\u6682\u65e0\u6d3b\u8dc3\u5206\u949f'
                    : '\u6d3b\u8dc3 ${summary.activeMinuteCount}\u5206\u949f'
                        ' \u00b7 \u952e\u76d8 '
                        '${_formatPercent(summary.keyboardInteractionShare)}'
                        ' \u00b7 \u6307\u9488 '
                        '${_formatPercent(summary.pointerInteractionShare)}',
                color: const Color(0xFF7A4FD1),
              ),
            ],
          ),
      ],
    );
  }
}

class _TopKeysAnalysisPanel extends StatelessWidget {
  const _TopKeysAnalysisPanel({required this.summary});

  final InputHeatmapSummary summary;

  @override
  Widget build(BuildContext context) {
    final topKeys = summary.topKeys.take(12).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u9ad8\u9891\u6309\u952e',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          '\u7528\u4e8e\u5feb\u901f\u5224\u65ad\u5f53\u524d\u65f6\u95f4\u8303\u56f4\u5185'
          '\u7684\u8f93\u5165\u7ed3\u6784\uff0c\u4f8b\u5982\u662f\u4ee5\u6587\u5b57\u8f93\u5165'
          '\u4e3a\u4e3b\uff0c\u8fd8\u662f\u4ee5\u5feb\u6377\u952e\u4ea4\u4e92\u4e3a\u4e3b\u3002',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        if (topKeys.isEmpty)
          const Text(
            '\u5f53\u524d\u7b5b\u9009\u6761\u4ef6\u4e0b\u6682\u65e0'
            '\u53ef\u5206\u6790\u7684\u952e\u76d8\u6309\u952e\u8bb0\u5f55\u3002',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          Column(
            children: topKeys
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _KeyRankingTile(
                      rank: entry.key + 1,
                      stat: entry.value,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _ProcessIntensityAnalysisPanel extends StatelessWidget {
  const _ProcessIntensityAnalysisPanel({required this.summary});

  final InputHeatmapSummary summary;

  @override
  Widget build(BuildContext context) {
    final items = summary.processIntensities.take(8).toList(growable: false);
    final maxScore = summary.maxProcessIntensityScore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u5e94\u7528\u5185\u8f93\u5165\u5f3a\u5ea6',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          '\u57fa\u4e8e\u952e\u76d8\u3001\u70b9\u51fb\u3001\u6eda\u8f6e\u548c\u9f20\u6807\u79fb\u52a8'
          '\u5408\u6210\u5f3a\u5ea6\u5206\u6570\uff0c\u7528\u6765\u5bf9\u6bd4\u4e0d\u540c\u5e94\u7528'
          '\u5728\u8be5\u65f6\u95f4\u8303\u56f4\u5185\u7684\u8f93\u5165\u6d3b\u8dc3\u5ea6\u3002',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          const Text(
            '\u5f53\u524d\u7b5b\u9009\u6761\u4ef6\u4e0b\u6682\u65e0'
            '\u53ef\u5206\u6790\u7684\u5e94\u7528\u8f93\u5165\u5f3a\u5ea6\u6570\u636e\u3002',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          Column(
            children: items
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ProcessIntensityTile(
                      item: item,
                      maxScore: maxScore,
                      totalEventCount: summary.totalEventCount,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _HourlyDistributionAnalysisPanel extends StatelessWidget {
  const _HourlyDistributionAnalysisPanel({required this.summary});

  final InputHeatmapSummary summary;

  @override
  Widget build(BuildContext context) {
    final maxScore = summary.maxHourlyIntensityScore;
    final peak = summary.peakHourBucket;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u65f6\u95f4\u6bb5\u5206\u5e03',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          peak == null
              ? '\u5f53\u524d\u8303\u56f4\u5185\u6682\u65e0\u65f6\u95f4\u6bb5\u5206\u5e03\u6570\u636e\u3002'
              : '\u5cf0\u503c\u65f6\u6bb5\uff1a${_formatHourRange(peak.hour)}'
                  ' \u00b7 \u5f3a\u5ea6\u5206 ${peak.intensityScore}'
                  ' \u00b7 \u4e8b\u4ef6 ${peak.totalEvents}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        if (summary.hourlyDistribution.every((item) => item.totalEvents <= 0))
          const Text(
            '\u5f53\u524d\u7b5b\u9009\u6761\u4ef6\u4e0b\u6682\u65e0'
            '\u53ef\u5206\u6790\u7684\u65f6\u95f4\u6bb5\u5206\u5e03\u3002',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 24 * 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: summary.hourlyDistribution
                    .map(
                      (bucket) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _HourDistributionBar(
                            bucket: bucket,
                            maxScore: maxScore,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (List<InputHourDistributionBucket>.from(
              summary.hourlyDistribution.where(
                (item) => item.totalEvents > 0,
              ),
            )..sort((left, right) {
                    final byScore =
                        right.intensityScore.compareTo(left.intensityScore);
                    if (byScore != 0) {
                      return byScore;
                    }
                    return right.totalEvents.compareTo(left.totalEvents);
                  }))
                .take(5)
                .map(
                  (item) => _StatChip(
                    label:
                        '${_formatHourRange(item.hour)} ${item.totalEvents}\u6761'
                        ' \u00b7 ${item.activeMinutes}\u5206',
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}

class _KeyRankingTile extends StatelessWidget {
  const _KeyRankingTile({
    required this.rank,
    required this.stat,
  });

  final int rank;
  final InputKeyStat stat;

  @override
  Widget build(BuildContext context) {
    final widthFactor = stat.share.clamp(0.05, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE8C4),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8D4E00),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stat.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${stat.count}\u6b21',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8D4E00),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: widthFactor,
              minHeight: 8,
              backgroundColor: const Color(0xFFE8EBF0),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFFCC6100)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '\u5360\u952e\u76d8\u8f93\u5165 ${_formatPercent(stat.share)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _ProcessIntensityTile extends StatelessWidget {
  const _ProcessIntensityTile({
    required this.item,
    required this.maxScore,
    required this.totalEventCount,
  });

  final InputProcessIntensity item;
  final int maxScore;
  final int totalEventCount;

  @override
  Widget build(BuildContext context) {
    final progress = maxScore <= 0 ? 0.0 : item.intensityScore / maxScore;
    final share =
        totalEventCount <= 0 ? 0.0 : item.totalEvents / totalEventCount;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.processName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '\u5f3a\u5ea6 ${item.intensityScore}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0E8A75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFFE8EBF0),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF0E8A75)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatChip(label: '\u4e8b\u4ef6 ${item.totalEvents}'),
              _StatChip(label: '\u5360\u6bd4 ${_formatPercent(share)}'),
              _StatChip(label: '\u952e\u76d8 ${item.keyEvents}'),
              _StatChip(
                label:
                    '\u70b9\u51fb ${item.mouseButtonEvents + item.wheelEvents}',
              ),
              _StatChip(label: '\u79fb\u52a8 ${item.moveDistance}'),
              _StatChip(
                  label: '\u6d3b\u8dc3 ${item.activeMinutes}\u5206\u949f'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HourDistributionBar extends StatelessWidget {
  const _HourDistributionBar({
    required this.bucket,
    required this.maxScore,
  });

  final InputHourDistributionBucket bucket;
  final int maxScore;

  @override
  Widget build(BuildContext context) {
    final ratio = maxScore <= 0 ? 0.0 : bucket.intensityScore / maxScore;
    final barHeight = 18 + (ratio.clamp(0.0, 1.0) * 120);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '${bucket.totalEvents}',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        Container(
          height: barHeight,
          decoration: BoxDecoration(
            color: Color.lerp(
                  const Color(0xFFF6D9A8),
                  const Color(0xFFCC6100),
                  ratio.clamp(0.0, 1.0),
                ) ??
                const Color(0xFFF6D9A8),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          bucket.hour.toString().padLeft(2, '0'),
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }
}

class _OverviewMetricTile extends StatelessWidget {
  const _OverviewMetricTile({
    required this.title,
    required this.value,
    required this.note,
    required this.color,
  });

  final String title;
  final String value;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 220,
        maxWidth: 280,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _KeyboardHeatmap extends StatelessWidget {
  const _KeyboardHeatmap({required this.summary});

  final InputHeatmapSummary summary;

  @override
  Widget build(BuildContext context) {
    final topKeys = summary.topKeys.take(12).toList(growable: false);
    final maxCount = summary.maxKeyCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u952e\u76d8\u6309\u952e\u70ed\u529b\u56fe',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          '\u989c\u8272\u8d8a\u6df1\uff0c\u8868\u793a\u8be5\u6309\u952e'
          '\u5728\u5f53\u524d\u8303\u56f4\u5185\u88ab\u89e6\u53d1\u5f97\u8d8a\u9891\u7e41\u3002',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _keyboardRows
                .map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: row
                          .map(
                            (spec) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _KeyboardKeyTile(
                                spec: spec,
                                count: _sumKeyCounts(
                                    summary.keyCounts, spec.keyCodes),
                                maxCount: maxCount,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 12),
        if (topKeys.isEmpty)
          const Text(
            '\u5f53\u524d\u7b5b\u9009\u6761\u4ef6\u4e0b'
            '\u6682\u65e0\u952e\u76d8\u8f93\u5165\u8bb0\u5f55\u3002',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: topKeys
                .map(
                  (entry) => _StatChip(
                    label: '${entry.label} ${entry.count}',
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _MouseHeatmap extends StatelessWidget {
  const _MouseHeatmap({required this.summary});

  final InputHeatmapSummary summary;

  @override
  Widget build(BuildContext context) {
    final topMouseEntries = summary.mouseCounts.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final maxCount = summary.maxMouseCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u9f20\u6807\u70ed\u529b\u56fe',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          '\u5c55\u793a\u5de6\u53f3\u952e\u3001\u4e2d\u952e\u3001'
          '\u4fa7\u952e\u548c\u6eda\u8f6e\u4e8b\u4ef6\u7684\u7d2f\u8ba1\u6b21\u6570\u3002',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: const Color(0xFFE2E5EA)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MouseKeyTile(
                        label: '\u5de6\u952e',
                        count: summary.mouseCounts['left'] ?? 0,
                        maxCount: maxCount,
                        height: 120,
                        radius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          bottomLeft: Radius.circular(18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MouseKeyTile(
                        label: '\u53f3\u952e',
                        count: summary.mouseCounts['right'] ?? 0,
                        maxCount: maxCount,
                        height: 120,
                        radius: const BorderRadius.only(
                          topRight: Radius.circular(24),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MouseKeyTile(
                        label: '\u4e2d\u952e',
                        count: summary.mouseCounts['middle'] ?? 0,
                        maxCount: maxCount,
                        height: 72,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MouseKeyTile(
                        label: '\u4fa7\u952e1',
                        count: summary.mouseCounts['x1'] ?? 0,
                        maxCount: maxCount,
                        height: 72,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MouseKeyTile(
                        label: '\u4fa7\u952e2',
                        count: summary.mouseCounts['x2'] ?? 0,
                        maxCount: maxCount,
                        height: 72,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MouseKeyTile(
                        label: '\u6eda\u8f6e\u4e0a',
                        count: summary.mouseCounts['wheel_up'] ?? 0,
                        maxCount: maxCount,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MouseKeyTile(
                        label: '\u6eda\u8f6e\u4e0b',
                        count: summary.mouseCounts['wheel_down'] ?? 0,
                        maxCount: maxCount,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MouseKeyTile(
                        label: '\u6a2a\u6eda\u5de6',
                        count: summary.mouseCounts['wheel_left'] ?? 0,
                        maxCount: maxCount,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MouseKeyTile(
                        label: '\u6a2a\u6eda\u53f3',
                        count: summary.mouseCounts['wheel_right'] ?? 0,
                        maxCount: maxCount,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E5EA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.open_with_rounded, color: Colors.grey),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '\u7d2f\u8ba1\u79fb\u52a8\u8ddd\u79bb ${summary.mouseMoveDistance}'
                          ' \u00b7 \u79fb\u52a8\u6b21\u6570 ${summary.mouseMoveEventCount}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (topMouseEntries.isEmpty)
          const Text(
            '\u5f53\u524d\u7b5b\u9009\u6761\u4ef6\u4e0b\u6682\u65e0'
            '\u9f20\u6807\u8f93\u5165\u8bb0\u5f55\u3002',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: topMouseEntries
                .take(10)
                .map(
                  (entry) => _StatChip(
                    label: '${inputMouseButtonLabel(entry.key)} ${entry.value}',
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _KeyboardKeyTile extends StatelessWidget {
  const _KeyboardKeyTile({
    required this.spec,
    required this.count,
    required this.maxCount,
  });

  final _KeyboardKeySpec spec;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final background = _heatColor(count: count, maxCount: maxCount);
    final foreground = count > 0 && maxCount > 0 && count / maxCount > 0.55
        ? Colors.white
        : const Color(0xFF24303F);
    return Container(
      width: spec.widthUnits * 26,
      height: 58,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: count > 0
              ? background.withValues(alpha: 0.95)
              : const Color(0xFFDADFE6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
          const Spacer(),
          Text('$count', style: TextStyle(fontSize: 12, color: foreground)),
        ],
      ),
    );
  }
}

class _MouseKeyTile extends StatelessWidget {
  const _MouseKeyTile({
    required this.label,
    required this.count,
    required this.maxCount,
    this.height = 58,
    this.radius,
  });

  final String label;
  final int count;
  final int maxCount;
  final double height;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final background = _heatColor(count: count, maxCount: maxCount);
    final foreground = count > 0 && maxCount > 0 && count / maxCount > 0.55
        ? Colors.white
        : const Color(0xFF24303F);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius ?? BorderRadius.circular(18),
        border: Border.all(
          color: count > 0
              ? background.withValues(alpha: 0.95)
              : const Color(0xFFDADFE6),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 46;
          final padding = compact ? 3.0 : 10.0;
          final fontSize = compact ? 10.0 : 14.0;
          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
                Text(
                  '$count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1,
                    color: foreground,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KeyboardKeySpec {
  final String label;
  final int widthUnits;
  final List<int> keyCodes;

  const _KeyboardKeySpec(this.label, this.widthUnits, this.keyCodes);
}

const List<List<_KeyboardKeySpec>> _keyboardRows = <List<_KeyboardKeySpec>>[
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('Esc', 5, <int>[27]),
    _KeyboardKeySpec('F1', 5, <int>[112]),
    _KeyboardKeySpec('F2', 5, <int>[113]),
    _KeyboardKeySpec('F3', 5, <int>[114]),
    _KeyboardKeySpec('F4', 5, <int>[115]),
    _KeyboardKeySpec('F5', 5, <int>[116]),
    _KeyboardKeySpec('F6', 5, <int>[117]),
    _KeyboardKeySpec('F7', 5, <int>[118]),
    _KeyboardKeySpec('F8', 5, <int>[119]),
    _KeyboardKeySpec('F9', 5, <int>[120]),
    _KeyboardKeySpec('F10', 5, <int>[121]),
    _KeyboardKeySpec('F11', 5, <int>[122]),
    _KeyboardKeySpec('F12', 5, <int>[123]),
    _KeyboardKeySpec('\u622a\u56fe', 7, <int>[44]),
  ],
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('`', 5, <int>[192]),
    _KeyboardKeySpec('1', 5, <int>[49]),
    _KeyboardKeySpec('2', 5, <int>[50]),
    _KeyboardKeySpec('3', 5, <int>[51]),
    _KeyboardKeySpec('4', 5, <int>[52]),
    _KeyboardKeySpec('5', 5, <int>[53]),
    _KeyboardKeySpec('6', 5, <int>[54]),
    _KeyboardKeySpec('7', 5, <int>[55]),
    _KeyboardKeySpec('8', 5, <int>[56]),
    _KeyboardKeySpec('9', 5, <int>[57]),
    _KeyboardKeySpec('0', 5, <int>[48]),
    _KeyboardKeySpec('-', 5, <int>[189]),
    _KeyboardKeySpec('=', 5, <int>[187]),
    _KeyboardKeySpec('\u9000\u683c', 11, <int>[8]),
  ],
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('Tab', 7, <int>[9]),
    _KeyboardKeySpec('Q', 5, <int>[81]),
    _KeyboardKeySpec('W', 5, <int>[87]),
    _KeyboardKeySpec('E', 5, <int>[69]),
    _KeyboardKeySpec('R', 5, <int>[82]),
    _KeyboardKeySpec('T', 5, <int>[84]),
    _KeyboardKeySpec('Y', 5, <int>[89]),
    _KeyboardKeySpec('U', 5, <int>[85]),
    _KeyboardKeySpec('I', 5, <int>[73]),
    _KeyboardKeySpec('O', 5, <int>[79]),
    _KeyboardKeySpec('P', 5, <int>[80]),
    _KeyboardKeySpec('[', 5, <int>[219]),
    _KeyboardKeySpec(']', 5, <int>[221]),
    _KeyboardKeySpec('\\', 9, <int>[220]),
  ],
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('\u5927\u5199', 9, <int>[20]),
    _KeyboardKeySpec('A', 5, <int>[65]),
    _KeyboardKeySpec('S', 5, <int>[83]),
    _KeyboardKeySpec('D', 5, <int>[68]),
    _KeyboardKeySpec('F', 5, <int>[70]),
    _KeyboardKeySpec('G', 5, <int>[71]),
    _KeyboardKeySpec('H', 5, <int>[72]),
    _KeyboardKeySpec('J', 5, <int>[74]),
    _KeyboardKeySpec('K', 5, <int>[75]),
    _KeyboardKeySpec('L', 5, <int>[76]),
    _KeyboardKeySpec(';', 5, <int>[186]),
    _KeyboardKeySpec('\'', 5, <int>[222]),
    _KeyboardKeySpec('\u56de\u8f66', 12, <int>[13]),
  ],
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('\u5de6 Shift', 12, <int>[16, 160]),
    _KeyboardKeySpec('Z', 5, <int>[90]),
    _KeyboardKeySpec('X', 5, <int>[88]),
    _KeyboardKeySpec('C', 5, <int>[67]),
    _KeyboardKeySpec('V', 5, <int>[86]),
    _KeyboardKeySpec('B', 5, <int>[66]),
    _KeyboardKeySpec('N', 5, <int>[78]),
    _KeyboardKeySpec('M', 5, <int>[77]),
    _KeyboardKeySpec(',', 5, <int>[188]),
    _KeyboardKeySpec('.', 5, <int>[190]),
    _KeyboardKeySpec('/', 5, <int>[191]),
    _KeyboardKeySpec('\u53f3 Shift', 14, <int>[16, 161]),
  ],
  <_KeyboardKeySpec>[
    _KeyboardKeySpec('\u5de6 Ctrl', 8, <int>[17, 162]),
    _KeyboardKeySpec('\u5de6 Win', 7, <int>[91]),
    _KeyboardKeySpec('\u5de6 Alt', 7, <int>[18, 164]),
    _KeyboardKeySpec('\u7a7a\u683c', 22, <int>[32]),
    _KeyboardKeySpec('\u53f3 Alt', 7, <int>[18, 165]),
    _KeyboardKeySpec('\u53f3 Win', 7, <int>[92]),
    _KeyboardKeySpec('\u83dc\u5355', 7, <int>[93]),
    _KeyboardKeySpec('\u53f3 Ctrl', 8, <int>[17, 163]),
    _KeyboardKeySpec('\u2190', 5, <int>[37]),
    _KeyboardKeySpec('\u2191', 5, <int>[38]),
    _KeyboardKeySpec('\u2193', 5, <int>[40]),
    _KeyboardKeySpec('\u2192', 5, <int>[39]),
  ],
];

int _sumKeyCounts(Map<int, int> source, List<int> keyCodes) {
  var total = 0;
  for (final code in keyCodes) {
    total += source[code] ?? 0;
  }
  return total;
}

Color _heatColor({required int count, required int maxCount}) {
  if (count <= 0 || maxCount <= 0) {
    return const Color(0xFFF2F4F7);
  }
  final ratio = (count / maxCount).clamp(0.0, 1.0);
  final eased = 0.18 + (0.82 * math.sqrt(ratio));
  return Color.lerp(
        const Color(0xFFFFF1D8),
        const Color(0xFFCC6100),
        eased,
      ) ??
      const Color(0xFFF2F4F7);
}

String _formatPercent(double value) {
  final percentage = (value * 100).clamp(0, 100);
  return '${percentage.toStringAsFixed(1)}%';
}

String _formatDecimal(double value) {
  return value.toStringAsFixed(1);
}

String _formatHourRange(int hour) {
  final start = hour.toString().padLeft(2, '0');
  final end = ((hour + 1) % 24).toString().padLeft(2, '0');
  return '$start:00-$end:00';
}
