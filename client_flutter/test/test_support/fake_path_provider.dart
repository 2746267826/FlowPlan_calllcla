import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationCachePath() async => rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;

  @override
  Future<String?> getTemporaryPath() async => rootPath;
}

Future<Directory> setFakePathProviderDocumentsDirectory(String prefix) async {
  final directory = Directory.systemTemp.createTempSync(prefix);
  PathProviderPlatform.instance = FakePathProviderPlatform(directory.path);
  return directory;
}
