import '../services/raw_input_service.dart';

enum TrackedInputEventKind {
  keyDown,
  keyUp,
  mouseButtonDown,
  mouseButtonUp,
  mouseButton,
  mouseWheel,
  mouseMove,
}

extension TrackedInputEventKindValue on TrackedInputEventKind {
  String get value {
    switch (this) {
      case TrackedInputEventKind.keyDown:
        return 'key_down';
      case TrackedInputEventKind.keyUp:
        return 'key_up';
      case TrackedInputEventKind.mouseButtonDown:
        return 'mouse_button_down';
      case TrackedInputEventKind.mouseButtonUp:
        return 'mouse_button_up';
      case TrackedInputEventKind.mouseButton:
        return 'mouse_button';
      case TrackedInputEventKind.mouseWheel:
        return 'mouse_wheel';
      case TrackedInputEventKind.mouseMove:
        return 'mouse_move';
    }
  }

  static TrackedInputEventKind fromValue(String value) {
    switch (value) {
      case 'key_up':
        return TrackedInputEventKind.keyUp;
      case 'mouse_button_down':
        return TrackedInputEventKind.mouseButtonDown;
      case 'mouse_button_up':
        return TrackedInputEventKind.mouseButtonUp;
      case 'mouse_button':
        return TrackedInputEventKind.mouseButton;
      case 'mouse_wheel':
        return TrackedInputEventKind.mouseWheel;
      case 'mouse_move':
        return TrackedInputEventKind.mouseMove;
      case 'key_down':
      default:
        return TrackedInputEventKind.keyDown;
    }
  }
}

class InputEventContextBinding {
  final int? recordId;
  final String? processName;
  final String? className;
  final String? windowTitle;
  final String? category;
  final String? activityLabel;
  final bool isIgnored;

  const InputEventContextBinding({
    this.recordId,
    this.processName,
    this.className,
    this.windowTitle,
    this.category,
    this.activityLabel,
    this.isIgnored = false,
  });
}

class TrackedInputEvent {
  final String eventUid;
  final int sequenceId;
  final DateTime timestamp;
  final TrackedInputEventKind kind;
  final int eventCount;
  final int? recordId;
  final bool isIgnored;
  final String? processName;
  final String? className;
  final String? windowTitle;
  final String? category;
  final String? activityLabel;
  final int? keyCode;
  final String? keyLabel;
  final String? mouseButton;
  final int wheelDelta;
  final int deltaX;
  final int deltaY;
  final int moveDistance;
  final String? tokenText;

  const TrackedInputEvent({
    required this.eventUid,
    required this.sequenceId,
    required this.timestamp,
    required this.kind,
    this.eventCount = 1,
    this.recordId,
    this.isIgnored = false,
    this.processName,
    this.className,
    this.windowTitle,
    this.category,
    this.activityLabel,
    this.keyCode,
    this.keyLabel,
    this.mouseButton,
    this.wheelDelta = 0,
    this.deltaX = 0,
    this.deltaY = 0,
    this.moveDistance = 0,
    this.tokenText,
  });

  factory TrackedInputEvent.fromJson(Map<String, dynamic> json) {
    return TrackedInputEvent(
      eventUid: json['eventUid'] as String? ?? '',
      sequenceId: (json['sequenceId'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      kind: TrackedInputEventKindValue.fromValue(
        json['kind'] as String? ?? 'key_down',
      ),
      eventCount: (json['eventCount'] as num?)?.toInt() ?? 1,
      recordId: (json['recordId'] as num?)?.toInt(),
      isIgnored: json['isIgnored'] as bool? ?? false,
      processName: json['processName'] as String?,
      className: json['className'] as String?,
      windowTitle: json['windowTitle'] as String?,
      category: json['category'] as String?,
      activityLabel: json['activityLabel'] as String?,
      keyCode: (json['keyCode'] as num?)?.toInt(),
      keyLabel: json['keyLabel'] as String?,
      mouseButton: json['mouseButton'] as String?,
      wheelDelta: (json['wheelDelta'] as num?)?.toInt() ?? 0,
      deltaX: (json['deltaX'] as num?)?.toInt() ?? 0,
      deltaY: (json['deltaY'] as num?)?.toInt() ?? 0,
      moveDistance: (json['moveDistance'] as num?)?.toInt() ?? 0,
      tokenText: json['tokenText'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'eventUid': eventUid,
        'sequenceId': sequenceId,
        'timestamp': timestamp.toIso8601String(),
        'kind': kind.value,
        'eventCount': eventCount,
        if (recordId != null) 'recordId': recordId,
        'isIgnored': isIgnored,
        if (processName != null) 'processName': processName,
        if (className != null) 'className': className,
        if (windowTitle != null) 'windowTitle': windowTitle,
        if (category != null) 'category': category,
        if (activityLabel != null) 'activityLabel': activityLabel,
        if (keyCode != null) 'keyCode': keyCode,
        if (keyLabel != null) 'keyLabel': keyLabel,
        if (mouseButton != null) 'mouseButton': mouseButton,
        'wheelDelta': wheelDelta,
        'deltaX': deltaX,
        'deltaY': deltaY,
        'moveDistance': moveDistance,
        if (tokenText != null && tokenText!.isNotEmpty) 'tokenText': tokenText,
      };
}

String inputKeyLabelForCode(int code) {
  const labels = <int, String>{
    8: '\u9000\u683c',
    9: 'Tab',
    13: '\u56de\u8f66',
    16: 'Shift',
    17: 'Ctrl',
    18: 'Alt',
    19: 'Pause',
    20: '\u5927\u5199',
    27: 'Esc',
    32: '\u7a7a\u683c',
    33: 'PgUp',
    34: 'PgDn',
    35: 'End',
    36: 'Home',
    37: '\u5de6',
    38: '\u4e0a',
    39: '\u53f3',
    40: '\u4e0b',
    44: '\u622a\u56fe',
    45: 'Insert',
    46: 'Delete',
    91: '\u5de6Win',
    92: '\u53f3Win',
    93: '\u83dc\u5355',
    144: 'Num',
    145: 'Scroll',
    160: '\u5de6Shift',
    161: '\u53f3Shift',
    162: '\u5de6Ctrl',
    163: '\u53f3Ctrl',
    164: '\u5de6Alt',
    165: '\u53f3Alt',
    186: ';',
    187: '=',
    188: ',',
    189: '-',
    190: '.',
    191: '/',
    192: '`',
    219: '[',
    220: '\\',
    221: ']',
    222: '\'',
  };

  final direct = labels[code];
  if (direct != null) {
    return direct;
  }
  if (code >= 48 && code <= 57) {
    return String.fromCharCode(code);
  }
  if (code >= 65 && code <= 90) {
    return String.fromCharCode(code);
  }
  if (code >= 96 && code <= 105) {
    return '\u5c0f\u952e\u76d8${code - 96}';
  }
  if (code >= 112 && code <= 123) {
    return 'F${code - 111}';
  }
  return 'VK_$code';
}

String inputMouseButtonLabel(String button) {
  switch (button) {
    case 'left':
      return '\u5de6\u952e';
    case 'right':
      return '\u53f3\u952e';
    case 'middle':
      return '\u4e2d\u952e';
    case 'x1':
      return '\u4fa7\u952e1';
    case 'x2':
      return '\u4fa7\u952e2';
    case 'wheel_up':
      return '\u6eda\u8f6e\u4e0a';
    case 'wheel_down':
      return '\u6eda\u8f6e\u4e0b';
    case 'wheel_left':
      return '\u6a2a\u6eda\u5de6';
    case 'wheel_right':
      return '\u6a2a\u6eda\u53f3';
    case 'move':
      return '\u79fb\u52a8';
    case 'button':
      return '\u6309\u94ae';
    default:
      return button;
  }
}

String describeInputToken(String? tokenText) {
  if (tokenText == null || tokenText.isEmpty) {
    return '';
  }
  switch (tokenText) {
    case '[BACKSPACE]':
      return '[\u9000\u683c]';
    case '[ESC]':
      return '[Esc]';
    case '\n':
      return '[\u56de\u8f66]';
    case '\t':
      return '[Tab]';
    case ' ':
      return '[\u7a7a\u683c]';
    default:
      return tokenText;
  }
}

TrackedInputEventKind trackedInputEventKindFromRaw(RawInputEventKind kind) {
  switch (kind) {
    case RawInputEventKind.keyDown:
      return TrackedInputEventKind.keyDown;
    case RawInputEventKind.keyUp:
      return TrackedInputEventKind.keyUp;
    case RawInputEventKind.mouseButtonDown:
      return TrackedInputEventKind.mouseButtonDown;
    case RawInputEventKind.mouseButtonUp:
      return TrackedInputEventKind.mouseButtonUp;
    case RawInputEventKind.mouseButton:
      return TrackedInputEventKind.mouseButton;
    case RawInputEventKind.mouseWheel:
      return TrackedInputEventKind.mouseWheel;
    case RawInputEventKind.mouseMove:
      return TrackedInputEventKind.mouseMove;
  }
}
