// Dart side RawInput bridge.
import 'dart:io';
import 'package:flutter/services.dart';

class MouseClicks {
  final int left;
  final int right;
  final int middle;
  final int xButton1;
  final int xButton2;

  const MouseClicks({
    this.left = 0,
    this.right = 0,
    this.middle = 0,
    this.xButton1 = 0,
    this.xButton2 = 0,
  });

  int get total => left + right + middle + xButton1 + xButton2;

  MouseClicks copyWith({
    int? left,
    int? right,
    int? middle,
    int? xButton1,
    int? xButton2,
  }) {
    return MouseClicks(
      left: left ?? this.left,
      right: right ?? this.right,
      middle: middle ?? this.middle,
      xButton1: xButton1 ?? this.xButton1,
      xButton2: xButton2 ?? this.xButton2,
    );
  }

  MouseClicks add(MouseClicks other) {
    return MouseClicks(
      left: left + other.left,
      right: right + other.right,
      middle: middle + other.middle,
      xButton1: xButton1 + other.xButton1,
      xButton2: xButton2 + other.xButton2,
    );
  }

  MouseClicks subtract(MouseClicks base) {
    return MouseClicks(
      left: (left - base.left).clamp(0, 1 << 31).toInt(),
      right: (right - base.right).clamp(0, 1 << 31).toInt(),
      middle: (middle - base.middle).clamp(0, 1 << 31).toInt(),
      xButton1: (xButton1 - base.xButton1).clamp(0, 1 << 31).toInt(),
      xButton2: (xButton2 - base.xButton2).clamp(0, 1 << 31).toInt(),
    );
  }

  factory MouseClicks.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const MouseClicks();
    return MouseClicks(
      left: (map['left'] as int?) ?? (map['leftClick'] as int?) ?? 0,
      right: (map['right'] as int?) ?? (map['rightClick'] as int?) ?? 0,
      middle: (map['middle'] as int?) ?? (map['middleClick'] as int?) ?? 0,
      xButton1: (map['xButton1'] as int?) ??
          (map['backward'] as int?) ??
          (map['x1'] as int?) ??
          0,
      xButton2: (map['xButton2'] as int?) ??
          (map['forward'] as int?) ??
          (map['x2'] as int?) ??
          0,
    );
  }

  Map<String, int> toMap() => {
        'left': left,
        'right': right,
        'middle': middle,
        'xButton1': xButton1,
        'xButton2': xButton2,
      };
}

enum RawInputEventKind {
  keyDown,
  keyUp,
  mouseButtonDown,
  mouseButtonUp,
  mouseButton,
  mouseWheel,
  mouseMove,
}

extension RawInputEventKindValue on RawInputEventKind {
  String get value {
    switch (this) {
      case RawInputEventKind.keyDown:
        return 'key_down';
      case RawInputEventKind.keyUp:
        return 'key_up';
      case RawInputEventKind.mouseButtonDown:
        return 'mouse_button_down';
      case RawInputEventKind.mouseButtonUp:
        return 'mouse_button_up';
      case RawInputEventKind.mouseButton:
        return 'mouse_button';
      case RawInputEventKind.mouseWheel:
        return 'mouse_wheel';
      case RawInputEventKind.mouseMove:
        return 'mouse_move';
    }
  }

  static RawInputEventKind fromValue(String value) {
    switch (value) {
      case 'key_up':
        return RawInputEventKind.keyUp;
      case 'mouse_button_down':
        return RawInputEventKind.mouseButtonDown;
      case 'mouse_button_up':
        return RawInputEventKind.mouseButtonUp;
      case 'mouse_button':
        return RawInputEventKind.mouseButton;
      case 'mouse_wheel':
        return RawInputEventKind.mouseWheel;
      case 'mouse_move':
        return RawInputEventKind.mouseMove;
      case 'key_down':
      default:
        return RawInputEventKind.keyDown;
    }
  }
}

class RawInputEvent {
  final int sequenceId;
  final int timestampMicros;
  final RawInputEventKind kind;
  final int eventCount;
  final int? keyCode;
  final String? processName;
  final String? className;
  final String? windowTitle;
  final String? mouseButton;
  final int wheelDelta;
  final int deltaX;
  final int deltaY;
  final int moveDistance;
  final String? tokenText;
  DateTime? _cachedTimestamp;

  RawInputEvent({
    required this.sequenceId,
    required this.timestampMicros,
    required this.kind,
    this.eventCount = 1,
    this.keyCode,
    this.processName,
    this.className,
    this.windowTitle,
    this.mouseButton,
    this.wheelDelta = 0,
    this.deltaX = 0,
    this.deltaY = 0,
    this.moveDistance = 0,
    this.tokenText,
  });

  DateTime get timestamp =>
      _cachedTimestamp ??= DateTime.fromMicrosecondsSinceEpoch(timestampMicros);

  factory RawInputEvent.fromMap(Map<dynamic, dynamic> map) {
    final micros = (map['timestampMicros'] as num?)?.toInt() ??
        DateTime.now().microsecondsSinceEpoch;
    return RawInputEvent(
      sequenceId: (map['sequenceId'] as num?)?.toInt() ?? 0,
      timestampMicros: micros,
      kind: RawInputEventKindValue.fromValue(map['kind'] as String? ?? ''),
      eventCount: (map['eventCount'] as num?)?.toInt() ?? 1,
      keyCode: (map['keyCode'] as num?)?.toInt(),
      processName: map['processName'] as String?,
      className: map['className'] as String?,
      windowTitle: map['windowTitle'] as String?,
      mouseButton: map['mouseButton'] as String?,
      wheelDelta: (map['wheelDelta'] as num?)?.toInt() ?? 0,
      deltaX: (map['deltaX'] as num?)?.toInt() ?? 0,
      deltaY: (map['deltaY'] as num?)?.toInt() ?? 0,
      moveDistance: (map['moveDistance'] as num?)?.toInt() ?? 0,
      tokenText: map['tokenText'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sequenceId': sequenceId,
        'timestamp': timestamp.toIso8601String(),
        'kind': kind.value,
        'eventCount': eventCount,
        if (keyCode != null) 'keyCode': keyCode,
        if (processName != null && processName!.isNotEmpty)
          'processName': processName,
        if (className != null && className!.isNotEmpty) 'className': className,
        if (windowTitle != null && windowTitle!.isNotEmpty)
          'windowTitle': windowTitle,
        if (mouseButton != null) 'mouseButton': mouseButton,
        'wheelDelta': wheelDelta,
        'deltaX': deltaX,
        'deltaY': deltaY,
        'moveDistance': moveDistance,
        if (tokenText != null && tokenText!.isNotEmpty) 'tokenText': tokenText,
      };
}

/// Telemetry snapshot returned by the native RawInput plugin.
class InputTelemetry {
  final int keyCount;
  final Map<int, int> keyDistribution;
  final String? keySequence;
  final MouseClicks clicks;
  final int scrollPx;
  final int mouseMovePx;
  final DateTime timestamp;
  final List<RawInputEvent> inputEvents;

  const InputTelemetry({
    required this.keyCount,
    required this.keyDistribution,
    required this.keySequence,
    required this.clicks,
    required this.scrollPx,
    required this.mouseMovePx,
    required this.timestamp,
    required this.inputEvents,
  });

  factory InputTelemetry.empty([DateTime? timestamp]) {
    return InputTelemetry(
      keyCount: 0,
      keyDistribution: const <int, int>{},
      keySequence: null,
      clicks: const MouseClicks(),
      scrollPx: 0,
      mouseMovePx: 0,
      timestamp: timestamp ?? DateTime.now(),
      inputEvents: const <RawInputEvent>[],
    );
  }

  InputTelemetry add(InputTelemetry other) {
    return InputTelemetry(
      keyCount: keyCount + other.keyCount,
      keyDistribution: _mergeDistribution(keyDistribution, other.keyDistribution),
      keySequence: _mergeSequence(keySequence, other.keySequence),
      clicks: clicks.add(other.clicks),
      scrollPx: scrollPx + other.scrollPx,
      mouseMovePx: mouseMovePx + other.mouseMovePx,
      timestamp: other.timestamp,
      inputEvents: <RawInputEvent>[
        ...inputEvents,
        ...other.inputEvents,
      ]..sort((left, right) => left.sequenceId.compareTo(right.sequenceId)),
    );
  }

  InputTelemetry subtract(InputTelemetry base) {
    final sequence = keySequence;
    return InputTelemetry(
      keyCount: (keyCount - base.keyCount).clamp(0, 1 << 31).toInt(),
      keyDistribution: _subtractDistribution(keyDistribution, base.keyDistribution),
      keySequence: sequence,
      clicks: clicks.subtract(base.clicks),
      scrollPx: (scrollPx - base.scrollPx).clamp(0, 1 << 31).toInt(),
      mouseMovePx: (mouseMovePx - base.mouseMovePx).clamp(0, 1 << 31).toInt(),
      timestamp: timestamp,
      inputEvents: inputEvents,
    );
  }

  InputTelemetry copyWith({
    int? keyCount,
    Map<int, int>? keyDistribution,
    String? keySequence,
    MouseClicks? clicks,
    int? scrollPx,
    int? mouseMovePx,
    DateTime? timestamp,
    List<RawInputEvent>? inputEvents,
  }) {
    return InputTelemetry(
      keyCount: keyCount ?? this.keyCount,
      keyDistribution: keyDistribution ?? this.keyDistribution,
      keySequence: keySequence ?? this.keySequence,
      clicks: clicks ?? this.clicks,
      scrollPx: scrollPx ?? this.scrollPx,
      mouseMovePx: mouseMovePx ?? this.mouseMovePx,
      timestamp: timestamp ?? this.timestamp,
      inputEvents: inputEvents ?? this.inputEvents,
    );
  }

  static Map<int, int> _mergeDistribution(
      Map<int, int> left, Map<int, int> right) {
    final out = <int, int>{...left};
    for (final entry in right.entries) {
      out[entry.key] = (out[entry.key] ?? 0) + entry.value;
    }
    return out;
  }

  static Map<int, int> _subtractDistribution(
      Map<int, int> current, Map<int, int> base) {
    final out = <int, int>{};
    for (final entry in current.entries) {
      final value = entry.value - (base[entry.key] ?? 0);
      if (value > 0) {
        out[entry.key] = value;
      }
    }
    return out;
  }

  static String? _mergeSequence(String? left, String? right) {
    if (left == null || left.isEmpty) return right;
    if (right == null || right.isEmpty) return left;
    return '$left$right';
  }

  @override
  String toString() {
    return 'InputTelemetry(keys=$keyCount, clicks=${clicks.total}, '
        'move=${mouseMovePx}px, scroll=${scrollPx}px, events=${inputEvents.length})';
  }
}

class RawInputService {
  static const _channel = MethodChannel('com.flowplanv2/raw_input');

  bool _started = false;
  String? _lastError;
  bool get isRunning => _started;
  String? get lastError => _lastError;

  Future<void> start() async {
    if (!Platform.isWindows || _started) return;
    try {
      await _channel.invokeMethod('start');
      await _channel.invokeMethod('setSequenceRecording', {'enabled': true});
      _started = true;
      _lastError = null;
    } catch (error) {
      _started = false;
      _lastError = error.toString();
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    try {
      await _channel.invokeMethod('stop');
      _started = false;
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
    }
  }

  Future<void> setSequenceRecording(bool _) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('setSequenceRecording', {'enabled': true});
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
    }
  }

  Future<InputTelemetry?> getStats() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await _channel.invokeMethod<Map>('getStats');
      if (result == null) return null;
      final nativeError = result['lastError'] as String?;
      _lastError =
          nativeError == null || nativeError.trim().isEmpty ? null : nativeError;

      final rawKeyDist = result['keyDistribution'] as Map?;
      final keyDistribution = <int, int>{};
      rawKeyDist?.forEach((key, value) {
        final parsedKey = key is int ? key : int.tryParse(key.toString());
        if (parsedKey == null) return;
        keyDistribution[parsedKey] = (value as int?) ?? 0;
      });

      final rawClicks = result['mouseClicks'] as Map?;
      final clicks = MouseClicks.fromMap(rawClicks);
      final rawEvents = (result['inputEvents'] as List?) ?? const <dynamic>[];
      final inputEvents = rawEvents
          .whereType<Map>()
          .map((item) => RawInputEvent.fromMap(item))
          .toList(growable: false);

      return InputTelemetry(
        keyCount: (result['keyCount'] as int?) ?? 0,
        keyDistribution: keyDistribution,
        keySequence: result['keySequence'] as String?,
        clicks: clicks,
        scrollPx: (result['scrollPx'] as int?) ?? 0,
        mouseMovePx: (result['mouseMovePx'] as int?) ?? 0,
        timestamp: DateTime.now(),
        inputEvents: inputEvents,
      );
    } catch (error) {
      _lastError = error.toString();
      return null;
    }
  }

  Future<List<RawInputEvent>> getPendingInputEvents({
    int maxEvents = 1000,
  }) async {
    if (!Platform.isWindows) return const <RawInputEvent>[];
    try {
      final result = await _channel.invokeMethod<List>(
        'getPendingInputEvents',
        {'maxEvents': maxEvents},
      );
      _lastError = null;
      final rawEvents = result ?? const <dynamic>[];
      return rawEvents
          .whereType<Map>()
          .map((item) => RawInputEvent.fromMap(item))
          .toList(growable: false);
    } catch (error) {
      _lastError = error.toString();
      rethrow;
    }
  }

  Future<void> ackInputEvents(int throughSequenceId) async {
    if (!Platform.isWindows || throughSequenceId <= 0) return;
    try {
      await _channel.invokeMethod(
        'ackInputEvents',
        {'throughSequenceId': throughSequenceId},
      );
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
      rethrow;
    }
  }

  Future<void> resetStats() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('resetStats');
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
    }
  }
}

final RawInputService rawInputService = RawInputService();
