// 共享组件：当前时间红线指示器
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class TimeIndicator extends StatefulWidget {
  final double hourHeight;
  final int startHour;
  final Duration refreshIntervalForTesting;

  const TimeIndicator({
    super.key,
    required this.hourHeight,
    this.startHour = 0,
    this.refreshIntervalForTesting = const Duration(minutes: 1),
  });

  @override
  State<TimeIndicator> createState() => _TimeIndicatorState();
}

class _TimeIndicatorState extends State<TimeIndicator> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 每分钟刷新一次
    _timer = Timer.periodic(widget.refreshIntervalForTesting, (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMinutes = (_now.hour - widget.startHour) * 60 + _now.minute;
    final topPosition = (totalMinutes / 60) * widget.hourHeight;

    return Positioned(
      top: topPosition,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.timeIndicator,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Container(
              height: 2,
              color: AppColors.timeIndicator,
            ),
          ),
        ],
      ),
    );
  }
}
