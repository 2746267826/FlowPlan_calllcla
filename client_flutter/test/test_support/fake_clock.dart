import 'package:flowplanv2/core/time/app_clock.dart';

class FakeClock extends AppClock {
  FakeClock(DateTime initial) : _now = initial;

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  void set(DateTime value) {
    _now = value;
  }
}
