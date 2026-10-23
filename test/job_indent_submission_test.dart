import 'dart:async';
import 'dart:convert';

import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gew_erp/screens/job_indent_consumption.dart';

void main() {
  for (final success in [true, false]) {
    testWidgets('rapid submit stays single-flight; success=$success', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'role': 'user',
        'username': 'test',
      });
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preflight = Completer<http.Response>();
      final save = Completer<http.Response>();
      var lookups = 0;
      var submissions = 0;
      List<dynamic> submitted = [];
      final job = <String, dynamic>{'serialNo': 'TEST-JOB', 'isFinal': false};
      final client = MockClient((request) async {
        if (request.url.path == '/jobs') {
          return http.Response(jsonEncode([job]), 200);
        }
        if (request.url.path == '/materials') {
          return http.Response(
            jsonEncode([
              for (final subtype in ['7035', 'Thinner', 'White'])
                {'type': 'Paint', 'subtype': subtype, 'jobSpecific': false},
            ]),
            200,
          );
        }
        if (request.url.path == '/job_indents/TEST-JOB') {
          lookups++;
          if (lookups == 2) return preflight.future;
          return http.Response(jsonEncode(lookups > 2 ? submitted : []), 200);
        }
        if (request.method == 'POST' && request.url.path == '/job_indents') {
          submissions++;
          submitted = jsonDecode(request.body)['data'] as List;
          return save.future;
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(home: JobIndentConsumptionScreen()),
        );
        await tester.pumpAndSettle();
        tester
            .widget<DropdownSearch<Map<String, dynamic>>>(
              find.byType(DropdownSearch<Map<String, dynamic>>),
            )
            .onChanged!(job);
        await tester.pumpAndSettle();
        final quantities = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Indent Quantity',
        );
        for (var index = 0; index < 3; index++) {
          await tester.enterText(quantities.at(index), index == 0 ? '7' : '3');
        }
        final button = find.byWidgetPredicate((widget) => widget is ElevatedButton);
        await tester.ensureVisible(button);
        final submit = tester.widget<ElevatedButton>(button).onPressed!;
        submit();
        submit();
        await tester.pumpAndSettle();
        expect(lookups, 2);
        expect(submissions, 0);
        expect(find.text('Submitting...'), findsOneWidget);
        expect(
          tester.widget<ElevatedButton>(button).onPressed,
          isNull,
        );
        preflight.complete(http.Response('[]', 200));
        await tester.pumpAndSettle();
        expect(submissions, 1);
        expect(submitted.length, 3);
        submit();
        await tester.pumpAndSettle();
        expect(submissions, 1);
        save.complete(
          http.Response(
            success ? '{}' : '{"error":"conflict"}',
            success ? 200 : 409,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Submit Indent'), findsOneWidget);
        for (var index = 0; index < 3; index++) {
          expect(
            tester.widget<TextField>(quantities.at(index)).controller!.text,
            success ? '' : (index == 0 ? '7' : '3'),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }, () => client);
    });
  }
}
