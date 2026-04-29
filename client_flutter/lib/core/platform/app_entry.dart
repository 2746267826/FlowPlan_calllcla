export 'app_entry_stub.dart'
    if (dart.library.io) 'app_entry_io.dart'
    if (dart.library.html) 'app_entry_web.dart';
