import 'package:flowplanv2/core/platform/device_identity_service.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app keys constructor can be invoked at runtime', () {
    // ignore: prefer_const_constructors
    expect(AppKeys(), isA<AppKeys>());
    expect(AppKeys.shellReports, const Key('flowplan.shell.reports'));
  });

  test('device identity falls through to the default android platform probe',
      () {
    final platform = DeviceIdentityService(
      isWindowsForTesting: () => false,
    ).currentPlatform;

    expect(platform, isIn(<String>['android', 'unknown']));
  });
}
