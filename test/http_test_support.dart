import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> withEmptyApi(Future<void> Function() action) {
  SharedPreferences.setMockInitialValues({'username': 'test', 'role': 'admin'});
  return http.runWithClient(
    action,
    () => MockClient((request) async => http.Response('[]', 200)),
  );
}
