import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gew_erp/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'accessToken': 'existing-token'});
    ApiService.sessionExpired.value = false;
  });
  tearDown(() => ApiService.sessionExpired.value = false);

  test('job creation rejects HTTP errors and keeps one request id for retries', () async {
    final sent = <Map<String, dynamic>>[];
    final data = <String, dynamic>{'serialNo': 'TRFD0001', 'jobType': 'New'};
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer existing-token');
      sent.add(jsonDecode(request.body) as Map<String, dynamic>);
      return sent.length == 1
          ? http.Response('{"error":"retry"}', 500)
          : http.Response('{"serialNo":"TRFD0002"}', 201);
    });
    await http.runWithClient(() async {
      await expectLater(ApiService.saveJob(data), throwsA(isA<ApiException>()));
      expect(await ApiService.saveJob(data), 'TRFD0002');
      expect(sent[0]['_requestId'], sent[1]['_requestId']);
      expect(sent[0]['_autoNumber'], isTrue);
    }, () => client);
  });

  test('reports keep request ids and do not swallow failed saves', () async {
    final sent = <Map<String, dynamic>>[];
    final data = <String, dynamic>{'serialNo': 'TEST'};
    final client = MockClient((request) async {
      sent.add(jsonDecode(request.body)['data'] as Map<String, dynamic>);
      return sent.length == 1 ? http.Response('{"error":"failed"}', 500) : http.Response('{}', 201);
    });
    await http.runWithClient(() async {
      await expectLater(ApiService.saveReport(data), throwsA(isA<ApiException>()));
      await ApiService.saveReport(data);
      expect(sent[0]['_requestId'], sent[1]['_requestId']);
    }, () => client);
  });

  test('DELETE requests include JSON body and authentication', () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/reports');
      expect(request.headers['authorization'], 'Bearer existing-token');
      expect(jsonDecode(request.body)['_requestId'], 'report-one');
      return http.Response('{}', 200);
    });
    await http.runWithClient(() async {
      expect(await ApiService.deleteReport({'savedBy': 'test', '_requestId': 'report-one'}), isTrue);
    }, () => client);
  });

  test('login stores signed credential for subsequent requests', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/users/login') {
        return http.Response('{"username":"test","role":"admin","token":"new-token"}', 200);
      }
      expect(request.headers['authorization'], 'Bearer new-token');
      return http.Response('[]', 200);
    });
    await http.runWithClient(() async {
      expect((await ApiService.login('test', 'password'))!['role'], 'admin');
      await ApiService.getJobs();
    }, () => client);
  });

  test('expired credential prompts login rather than reporting successful save', () async {
    final client = MockClient((request) async => http.Response('{"error":"Login expired"}', 401));
    await http.runWithClient(() async {
      await expectLater(ApiService.saveReport({'serialNo': 'TEST'}), throwsA(isA<ApiException>()));
      expect(ApiService.sessionExpired.value, isTrue);
      expect((await SharedPreferences.getInstance()).getString('accessToken'), isNull);
    }, () => client);
  });

  test('unknown outgoing outcome retains retry identity; definite rejection does not', () async {
    for (final status in [500, 409]) {
      final client = MockClient((request) async => http.Response('{"error":"not saved"}', status));
      await http.runWithClient(() async {
        await expectLater(ApiService.saveOutgoingMaterial({'id': 'same-issue'}),
          throwsA(status == 500 ? isA<ApiException>() : isA<OutgoingIssueRejected>()));
      }, () => client);
    }
  });

  test('stock edit sends original balance as optimistic precondition', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body);
      expect(body['quantity'], 8);
      expect(body['expectedQuantity'], 5);
      expect(body['expectedPrice'], 10);
      return http.Response('{"error":"Stock changed"}', 409);
    });
    await http.runWithClient(() async {
      final result = await ApiService.updateStockQuantity(
        data: {'id': 'lot', 'quantity': 5, 'price': 10}, quantity: 8, price: 12, editFlag: true,
      );
      expect(result, 'Stock changed');
    }, () => client);
  });
}
