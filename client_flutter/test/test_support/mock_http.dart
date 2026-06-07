import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements http.Client {}

void registerHttpFallbacks() {
  registerFallbackValue(Uri.parse('http://localhost.test'));
  registerFallbackValue(<String, String>{});
}
