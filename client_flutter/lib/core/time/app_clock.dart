typedef DateTimeFactory = DateTime Function();

class AppClock {
  AppClock({DateTimeFactory? now}) : _now = now ?? DateTime.now;

  final DateTimeFactory _now;

  DateTime now() => _now();

  DateTime today() {
    final value = now();
    return DateTime(value.year, value.month, value.day);
  }
}
