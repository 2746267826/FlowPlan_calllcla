// Win32 前台窗口感知服务
// 使用 GetForegroundWindow / GetWindowText / GetClassName / GetWindowThreadProcessId
// 获取当前活跃窗口的进程名、类名和标题，以及全屏状态检测
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 前台窗口快照数据
class WindowSnapshot {
  final String processName;
  final String className;
  final String windowTitle;
  final bool isFullscreen;
  final DateTime timestamp;

  const WindowSnapshot({
    required this.processName,
    required this.className,
    required this.windowTitle,
    required this.isFullscreen,
    required this.timestamp,
  });

  @override
  String toString() => 'WindowSnapshot(process=$processName, class=$className, '
      'title=$windowTitle, fullscreen=$isFullscreen)';

  /// 判断是否与另一个快照为相同上下文（忽略标题微变）
  bool isSameContext(WindowSnapshot other) =>
      processName == other.processName && className == other.className;
}

/// 前台窗口感知器（纯 Dart FFI + win32 包实现）
class WindowSensor {
  const WindowSensor();

  /// 获取当前前台窗口的快照
  WindowSnapshot? capture() {
    try {
      final hwnd = GetForegroundWindow();
      if (hwnd == 0) return null;

      // ── 窗口标题 ────────────────────────────────────────────
      final titleBuf = wsalloc(512);
      GetWindowText(hwnd, titleBuf, 512);
      final title = titleBuf.toDartString();
      free(titleBuf);

      // ── 窗口类名 ────────────────────────────────────────────
      final classBuf = wsalloc(256);
      GetClassName(hwnd, classBuf, 256);
      final className = classBuf.toDartString();
      free(classBuf);

      // ── 进程名 ──────────────────────────────────────────────
      final pidPtr = calloc<Uint32>();
      GetWindowThreadProcessId(hwnd, pidPtr);
      final pid = pidPtr.value;
      free(pidPtr);

      String processName = 'unknown';
      if (pid != 0) {
        final hProcess = OpenProcess(
          PROCESS_QUERY_LIMITED_INFORMATION,
          FALSE,
          pid,
        );
        if (hProcess != 0) {
          final exeBuf = wsalloc(260);
          final sizePtr = calloc<Uint32>()..value = 260;
          final ok = QueryFullProcessImageName(hProcess, 0, exeBuf, sizePtr);
          if (ok != 0) {
            final fullPath = exeBuf.toDartString();
            // 只取文件名
            processName = fullPath.split('\\').last;
          }
          free(exeBuf);
          free(sizePtr);
          CloseHandle(hProcess);
        }
      }

      // ── 全屏检测 ────────────────────────────────────────────
      final isFullscreen = _isWindowFullscreen(hwnd);

      return WindowSnapshot(
        processName: processName,
        className: className,
        windowTitle: title,
        isFullscreen: isFullscreen,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 检测窗口是否处于全屏状态（覆盖整个屏幕）
  bool _isWindowFullscreen(int hwnd) {
    try {
      final rect = calloc<RECT>();
      GetWindowRect(hwnd, rect);
      final wWidth = rect.ref.right - rect.ref.left;
      final wHeight = rect.ref.bottom - rect.ref.top;
      free(rect);

      final screenW = GetSystemMetrics(SM_CXSCREEN);
      final screenH = GetSystemMetrics(SM_CYSCREEN);

      // 窗口尺寸与屏幕一致即视为全屏
      return wWidth >= screenW && wHeight >= screenH;
    } catch (_) {
      return false;
    }
  }
}
