class InputEventQuery {
  final DateTime? start;
  final DateTime? end;
  final String? processName;

  const InputEventQuery({
    this.start,
    this.end,
    this.processName,
  });

  InputEventQuery copyWith({
    DateTime? start,
    DateTime? end,
    String? processName,
    bool clearStart = false,
    bool clearEnd = false,
    bool clearProcessName = false,
  }) {
    return InputEventQuery(
      start: clearStart ? null : (start ?? this.start),
      end: clearEnd ? null : (end ?? this.end),
      processName:
          clearProcessName ? null : (processName ?? this.processName),
    );
  }

  bool get hasTimeRange => start != null || end != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is InputEventQuery &&
        other.start == start &&
        other.end == end &&
        other.processName == processName;
  }

  @override
  int get hashCode => Object.hash(start, end, processName);
}
