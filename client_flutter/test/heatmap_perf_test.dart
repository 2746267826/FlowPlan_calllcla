import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

/// C6: Verify that generating and sorting 5000 heatmap data points
/// completes within a reasonable time frame (< 500ms).
void main() {
  test('heatmap data generation and sorting performs well with 5000 points', () {
    final rng = Random(42);
    final stopwatch = Stopwatch()..start();

    // Generate 5000 random heatmap data points
    final points = List.generate(5000, (_) {
      final hour = rng.nextInt(24);
      final minute = rng.nextInt(60);
      final dayOffset = rng.nextInt(7);
      final value = rng.nextDouble() * 100;
      return _HeatmapPoint(
        day: dayOffset,
        hour: hour,
        minute: minute,
        value: value,
      );
    });

    // Group by day+hour (simulating heatmap aggregation)
    final map = <String, double>{};
    for (final p in points) {
      final key = '${p.day}:${p.hour}:${(p.minute / 10).floor()}';
      map[key] = (map[key] ?? 0) + p.value;
    }

    final aggregated = map.entries
        .map((e) => _HeatmapAggregate(
              key: e.key,
              value: e.value,
            ))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    stopwatch.stop();

    expect(aggregated.length, greaterThan(0));
    expect(stopwatch.elapsedMilliseconds, lessThan(500));
  });
}

class _HeatmapPoint {
  final int day;
  final int hour;
  final int minute;
  final double value;
  _HeatmapPoint({
    required this.day,
    required this.hour,
    required this.minute,
    required this.value,
  });
}

class _HeatmapAggregate {
  final String key;
  final double value;
  _HeatmapAggregate({required this.key, required this.value});
}
