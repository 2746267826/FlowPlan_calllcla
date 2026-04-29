// 共享组件：锁定时间块（睡眠/三餐/外部事件阻挡）
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class BlockedTimeBlock extends StatelessWidget {
  final double top;
  final double height;
  final String label;
  final String emoji;

  const BlockedTimeBlock({
    super.key,
    required this.top,
    required this.height,
    required this.label,
    this.emoji = '🔒',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blockColor = isDark ? AppColors.blockDark : AppColors.blockLight;

    return Positioned(
      top: top + 2,
      left: 4,
      right: 4,
      height: height - 4,
      child: Container(
        decoration: BoxDecoration(
          color: blockColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
