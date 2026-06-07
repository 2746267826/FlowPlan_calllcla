import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weekly work schedule normalizes overlapping ranges', () {
    final schedule = WeeklyWorkSchedule({
      DateTime.monday: const <WorkTimeRange>[
        WorkTimeRange(startMinute: 9 * 60, endMinute: 12 * 60),
        WorkTimeRange(startMinute: 11 * 60, endMinute: 13 * 60),
      ],
    });

    final monday = schedule.rangesForWeekday(DateTime.monday);

    expect(monday, hasLength(1));
    expect(monday.single.startMinute, 9 * 60);
    expect(monday.single.endMinute, 13 * 60);
  });
}
