/// Shared payload key normalization helpers.
///
/// Replaces the duplicated `_stringAny`/`_int`/`_bool`/`_date` methods
/// in `task_event_server_first_store.dart` and `server_sync_change_applier.dart`.
///
/// All functions iterate through a list of key candidates and return the
/// first successfully typed value.

// ---- String helpers ----

String? stringFromMap(Map<String, Object?>? map, String key) {
  final value = map?[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? stringAny(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = stringFromMap(map, key);
    if (value != null) return value;
  }
  return null;
}

bool hasAny(Map<String, Object?> map, List<String> keys) {
  return keys.any(map.containsKey);
}

// ---- Numeric helpers ----

int? intAny(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

num? numAny(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value;
    if (value is String) {
      final parsed = num.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

double? doubleAny(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

// ---- Boolean helpers ----

bool? boolAny(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
  }
  return null;
}

// ---- Date helpers ----

DateTime? dateAny(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

// ---- Status normalization (aligned with server 5.1 standardization) ----

/// Normalized task status: 'todo' | 'in_progress' | 'done' | 'cancelled'
String taskStatus(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == 'done' || normalized == 'completed') return 'done';
  if (normalized == 'in_progress' || normalized == 'in-process') return 'in_progress';
  if (normalized == 'cancelled' || normalized == 'canceled') return 'cancelled';
  return 'todo';
}

/// Normalized event status: 'confirmed' | 'tentative' | 'cancelled'
String eventStatus(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == 'tentative') return 'tentative';
  if (normalized == 'cancelled' || normalized == 'canceled') return 'cancelled';
  return 'confirmed';
}

bool isDone(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == 'done' || normalized == 'completed';
}
