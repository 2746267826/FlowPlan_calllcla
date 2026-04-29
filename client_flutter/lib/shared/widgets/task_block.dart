// 共享组件：任务色块（支持上下拖拽移动 + 底缘拉伸调长）
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 拖拽回调签名
typedef DragUpdateCallback = void Function(double newTop);
typedef ResizeUpdateCallback = void Function(double newHeight);
typedef DragEndCallback = void Function(double finalTop);
typedef ResizeEndCallback = void Function(double finalHeight);

class TaskBlock extends StatefulWidget {
  final double top;
  final double height;
  final String label;
  final String? location;
  final String? note;
  final String? durationText;
  final Color color;
  final bool isActual;
  final VoidCallback? onTap;

  // 拖拽支持
  final bool isDraggable;
  final DragEndCallback? onDragEnd;
  final ResizeEndCallback? onResizeEnd;

  // 常量
  static const double minHeight = 20.0;

  const TaskBlock({
    super.key,
    required this.top,
    required this.height,
    required this.label,
    this.location,
    this.note,
    this.durationText,
    required this.color,
    this.isActual = false,
    this.onTap,
    this.isDraggable = false,
    this.onDragEnd,
    this.onResizeEnd,
  });

  @override
  State<TaskBlock> createState() => _TaskBlockState();
}

class _TaskBlockState extends State<TaskBlock> {
  late double _currentTop;
  late double _currentHeight;
  bool _isDragging = false;
  bool _isResizing = false;

  @override
  void initState() {
    super.initState();
    _currentTop = widget.top;
    _currentHeight = widget.height;
  }

  @override
  void didUpdateWidget(covariant TaskBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && !_isResizing) {
      _currentTop = widget.top;
      _currentHeight = widget.height;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveTop = _currentTop;
    final effectiveHeight = _currentHeight;
    final textColor = widget.isActual
        ? widget.color.withValues(alpha: 0.9)
        : _contrastColor(widget.color);

    return Positioned(
      top: effectiveTop + 2,
      left: 4,
      right: 4,
      height: effectiveHeight - 4,
      child: GestureDetector(
        onTap: (!_isDragging && !_isResizing) ? widget.onTap : null,
        // ── 上下拖拽改变位置 ──
        onVerticalDragStart: widget.isDraggable
            ? (_) => setState(() => _isDragging = true)
            : null,
        onVerticalDragUpdate: widget.isDraggable
            ? (details) {
                setState(() {
                  _currentTop = (_currentTop + details.delta.dy).clamp(0, 9999);
                });
              }
            : null,
        onVerticalDragEnd: widget.isDraggable
            ? (_) {
                widget.onDragEnd?.call(_currentTop);
                setState(() {
                  _isDragging = false;
                  _currentTop = widget.top;
                });
              }
            : null,
        child: Stack(
          children: [
            // ── 主体色块 ──
            Container(
              decoration: BoxDecoration(
                color: widget.isActual
                    ? widget.color.withValues(alpha: isDark ? 0.25 : 0.2)
                    : widget.color.withValues(alpha: _isDragging ? 1.0 : 0.9),
                borderRadius: BorderRadius.circular(10),
                border: widget.isActual
                    ? Border.all(
                        color: widget.color.withValues(alpha: 0.5), width: 1)
                    : _isDragging
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                boxShadow: _isDragging
                    ? [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: ClipRect(
                child: _buildContent(
                  height: effectiveHeight,
                  textColor: textColor,
                ),
              ),
            ),
            // ── 底部拉伸手柄 ──
            if (widget.isDraggable)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 12,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) =>
                      setState(() => _isResizing = true),
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      _currentHeight = (_currentHeight + details.delta.dy)
                          .clamp(TaskBlock.minHeight, 9999);
                    });
                  },
                  onVerticalDragEnd: (_) {
                    widget.onResizeEnd?.call(_currentHeight);
                    setState(() {
                      _isResizing = false;
                      _currentHeight = widget.height;
                    });
                  },
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color:
                            _contrastColor(widget.color).withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ).animate().fadeIn(duration: 200.ms),
    );
  }

  String _formatDuration(double heightPx) {
    // hourHeight = 80.0，从高度推算出可读时长
    const hourHeight = 80.0;
    final hours = heightPx / hourHeight;
    final mins = (hours * 60).round();
    if (mins < 60) return '$mins 分钟';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h 小时' : '$h 小时 $m 分钟';
  }

  Color _contrastColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.4 ? Colors.black87 : Colors.white;
  }

  Widget _buildContent({
    required double height,
    required Color textColor,
  }) {
    final duration = _clean(widget.durationText) ?? _formatDuration(height);
    final location = _clean(widget.location);
    final note = _clean(widget.note);
    final detailColor = widget.isActual
        ? widget.color.withValues(alpha: 0.65)
        : textColor.withValues(alpha: 0.76);

    final detailLines = <String>[
      duration,
      if (location != null) location,
      if (note != null) note,
    ];

    if (height < 30) {
      return Text(
        widget.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      );
    }

    final titleLines = height >= 72 ? 2 : 1;
    final maxDetailLines = height >= 78
        ? 3
        : height >= 58
            ? 2
            : height >= 42
                ? 1
                : 0;

    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          maxLines: titleLines,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: TextStyle(
            fontSize: 12,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        if (maxDetailLines > 0) ...[
          const SizedBox(height: 2),
          for (final line in detailLines.take(maxDetailLines))
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 10,
                height: 1.12,
                color: detailColor,
              ),
            ),
        ],
      ],
    );
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
