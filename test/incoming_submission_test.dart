import 'dart:async';
import 'dart:convert';

import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gew_erp/screens/material_incoming_screen.dart';

void main() {
  testWidgets('rapid incoming submit is single-flight and retries the original request', (tester) async {
    SharedPreferences.setMockInitialValues({'username': 'test', 'role': 'user'});
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<http.Response>();
    final submissions = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path == '/materials') {
        return http.Response('[{"type":"Audit","subtype":"Material","jobSpecific":false}]', 200);
      }
      if (request.method == 'POST') {
        submissions.add(jsonDecode(request.body) as Map<String, dynamic>);
        return submissions.length == 1 ? pending.future : http.Response('{}', 201);
      }
      return http.Response('[]', 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: MaterialIncomingScreen()));
      await tester.pumpAndSettle();
      tester.widget<DropdownSearch<String>>(find.byType(DropdownSearch<String>).first)
          .onChanged!('Audit - Material');
      await tester.pumpAndSettle();
      Finder field(String label) => find.ancestor(
        of: find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == label),
        matching: find.byType(TextFormField),
      );
      for (final entry in {'Quantity': '5', 'Price': '10', 'Make': 'Test', 'Invoice Number': 'INV'}.entries) {
        await tester.enterText(field(entry.key), entry.value);
      }
      final submit = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Submit')).onPressed!;
      submit();
      submit();
      await tester.pumpAndSettle();
      expect(submissions.length, 1);
      pending.complete(http.Response('{"error":"unknown outcome"}', 500));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field('Quantity')).controller!.text, '5');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(submissions.length, 2);
      expect(submissions[0], submissions[1]);
      expect(tester.widget<TextFormField>(field('Quantity')).controller!.text, '');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, () => client);
  });
}
