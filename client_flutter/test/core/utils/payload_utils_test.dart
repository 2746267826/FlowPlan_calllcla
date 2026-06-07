import 'package:flowplanv2/core/utils/payload_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes string numeric boolean date and status payloads', () {
    final payload = <String, Object?>{
      'title': '  Ship tests  ',
      'minutes': '45',
      'ratio': '1.5',
      'enabled': 'yes',
      'when': '2026-06-08T09:00:00.000Z',
      'status': 'completed',
    };

    expect(stringAny(payload, const <String>['summary', 'title']), 'Ship tests');
    expect(intAny(payload, const <String>['minutes']), 45);
    expect(doubleAny(payload, const <String>['ratio']), 1.5);
    expect(boolAny(payload, const <String>['enabled']), isTrue);
    expect(dateAny(payload, const <String>['when']), DateTime.utc(2026, 6, 8, 9));
    expect(taskStatus(payload['status'] as String), 'done');
  });
}
