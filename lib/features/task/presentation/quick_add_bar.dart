// 底部快速打卡栏（「现在在做：___」活动追踪入口）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';

class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({super.key});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final _controller = TextEditingController();
  bool _isTracking = false;
  String _currentActivity = '';
  int? _activeRecordId;
  DateTime? _trackingStart;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  @override
  void dispose() {
    _controller.dispose();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  Future<void> _startTracking(String label) async {
    if (label.isEmpty) return;

    final repo = ref.read(activityRecordRepositoryProvider);
    final now = DateTime.now();

    final id = await repo.startRecord(
      startTime: now,
      manualLabel: label,
      source: 'manual',
    );

    setState(() {
      _isTracking = true;
      _currentActivity = label;
      _activeRecordId = id;
      _trackingStart = now;
      _elapsed = Duration.zero;
    });
    _controller.clear();

    // 启动每秒刷新计时器
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_trackingStart != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_trackingStart!);
        });
      }
    });
  }

  Future<void> _stopTracking() async {
    _elapsedTimer?.cancel();

    if (_activeRecordId != null) {
      final repo = ref.read(activityRecordRepositoryProvider);
      await repo.endRecord(_activeRecordId!, DateTime.now());
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('「$_currentActivity」已记录 ${_formatDuration(_elapsed)}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    setState(() {
      _isTracking = false;
      _currentActivity = '';
      _activeRecordId = null;
      _trackingStart = null;
      _elapsed = Duration.zero;
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: _isTracking ? _buildTracking() : _buildInput(),
    );
  }

  Widget _buildInput() {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: '现在在做：___',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(fontSize: 14),
            onSubmitted: _startTracking,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.play_circle_outline),
          color: AppColors.primary,
          iconSize: 28,
          onPressed: () => _startTracking(_controller.text),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildTracking() {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF43A047), // 绿色：追踪中
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _currentActivity,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 实时计时器
        Text(
          _formatDuration(_elapsed),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 12),
        TextButton.icon(
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: const Text('结束'),
          onPressed: _stopTracking,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFE53935),
          ),
        ),
      ],
    );
  }
}
