import 'input_event_query.dart';

class InputKeyStat {
  final int keyCode;
  final String label;
  final int count;
  final double share;

  const InputKeyStat({
    required this.keyCode,
    required this.label,
    required this.count,
    required this.share,
  });
}

class InputProcessIntensity {
  final String processName;
  final int totalEvents;
  final int keyEvents;
  final int mouseButtonEvents;
  final int wheelEvents;
  final int mouseMoveEvents;
  final int moveDistance;
  final int activeMinutes;
  final int intensityScore;

  const InputProcessIntensity({
    required this.processName,
    required this.totalEvents,
    required this.keyEvents,
    required this.mouseButtonEvents,
    required this.wheelEvents,
    required this.mouseMoveEvents,
    required this.moveDistance,
    required this.activeMinutes,
    required this.intensityScore,
  });
}

class InputHourDistributionBucket {
  final int hour;
  final int totalEvents;
  final int keyEvents;
  final int mouseButtonEvents;
  final int wheelEvents;
  final int mouseMoveEvents;
  final int moveDistance;
  final int activeMinutes;
  final int intensityScore;

  const InputHourDistributionBucket({
    required this.hour,
    required this.totalEvents,
    required this.keyEvents,
    required this.mouseButtonEvents,
    required this.wheelEvents,
    required this.mouseMoveEvents,
    required this.moveDistance,
    required this.activeMinutes,
    required this.intensityScore,
  });
}

class InputHeatmapSummary {
  final InputEventQuery query;
  final int totalEventCount;
  final int activeMinuteCount;
  final int keyboardEventCount;
  final int mouseButtonEventCount;
  final int wheelEventCount;
  final int mouseMoveEventCount;
  final int mouseMoveDistance;
  final Map<int, int> keyCounts;
  final Map<String, int> mouseCounts;
  final List<InputKeyStat> topKeys;
  final List<InputProcessIntensity> processIntensities;
  final List<InputHourDistributionBucket> hourlyDistribution;

  const InputHeatmapSummary({
    required this.query,
    required this.totalEventCount,
    required this.activeMinuteCount,
    required this.keyboardEventCount,
    required this.mouseButtonEventCount,
    required this.wheelEventCount,
    required this.mouseMoveEventCount,
    required this.mouseMoveDistance,
    required this.keyCounts,
    required this.mouseCounts,
    required this.topKeys,
    required this.processIntensities,
    required this.hourlyDistribution,
  });

  factory InputHeatmapSummary.empty(InputEventQuery query) {
    return InputHeatmapSummary(
      query: query,
      totalEventCount: 0,
      activeMinuteCount: 0,
      keyboardEventCount: 0,
      mouseButtonEventCount: 0,
      wheelEventCount: 0,
      mouseMoveEventCount: 0,
      mouseMoveDistance: 0,
      keyCounts: const <int, int>{},
      mouseCounts: const <String, int>{},
      topKeys: const <InputKeyStat>[],
      processIntensities: const <InputProcessIntensity>[],
      hourlyDistribution: List<InputHourDistributionBucket>.generate(
        24,
        (hour) => InputHourDistributionBucket(
          hour: hour,
          totalEvents: 0,
          keyEvents: 0,
          mouseButtonEvents: 0,
          wheelEvents: 0,
          mouseMoveEvents: 0,
          moveDistance: 0,
          activeMinutes: 0,
          intensityScore: 0,
        ),
      ),
    );
  }

  InputKeyStat? get leadingKey {
    if (topKeys.isEmpty) {
      return null;
    }
    return topKeys.first;
  }

  InputProcessIntensity? get leadingProcessIntensity {
    if (processIntensities.isEmpty) {
      return null;
    }
    return processIntensities.first;
  }

  int get trackedInteractionCount =>
      keyboardEventCount +
      mouseButtonEventCount +
      wheelEventCount +
      mouseMoveEventCount;

  double get keyboardInteractionShare {
    if (trackedInteractionCount <= 0) {
      return 0;
    }
    return keyboardEventCount / trackedInteractionCount;
  }

  double get pointerInteractionShare {
    if (trackedInteractionCount <= 0) {
      return 0;
    }
    return (mouseButtonEventCount + wheelEventCount + mouseMoveEventCount) /
        trackedInteractionCount;
  }

  double get averageEventsPerActiveMinute {
    if (activeMinuteCount <= 0) {
      return 0;
    }
    return totalEventCount / activeMinuteCount;
  }

  int get maxKeyCount {
    if (keyCounts.isEmpty) {
      return 0;
    }
    return keyCounts.values.reduce((left, right) => left > right ? left : right);
  }

  int get maxMouseCount {
    if (mouseCounts.isEmpty) {
      return 0;
    }
    return mouseCounts.values
        .reduce((left, right) => left > right ? left : right);
  }

  int get maxProcessIntensityScore {
    if (processIntensities.isEmpty) {
      return 0;
    }
    return processIntensities
        .map((item) => item.intensityScore)
        .reduce((left, right) => left > right ? left : right);
  }

  int get maxHourlyIntensityScore {
    if (hourlyDistribution.isEmpty) {
      return 0;
    }
    return hourlyDistribution
        .map((item) => item.intensityScore)
        .reduce((left, right) => left > right ? left : right);
  }

  InputHourDistributionBucket? get peakHourBucket {
    if (hourlyDistribution.isEmpty) {
      return null;
    }
    final ordered = List<InputHourDistributionBucket>.from(hourlyDistribution)
      ..sort((left, right) {
        final byScore = right.intensityScore.compareTo(left.intensityScore);
        if (byScore != 0) {
          return byScore;
        }
        return right.totalEvents.compareTo(left.totalEvents);
      });
    return ordered.first;
  }
}
