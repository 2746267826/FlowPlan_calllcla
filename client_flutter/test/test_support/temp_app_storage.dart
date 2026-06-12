import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

Future<Directory> setUpTempAppStorage({String prefix = 'flowplanv2-test-'}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory.systemTemp.createTemp(prefix);

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationSupportDirectory':
      case 'getTemporaryDirectory':
        return directory.path;
      default:
        return null;
    }
  });

  addTearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  return directory;
}
