import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gew_erp/screens/job_details_screen.dart';
import 'package:gew_erp/screens/test_report_pdf_generator_screen.dart';

Finder field(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);

void main() {
  testWidgets('dual voltage fields fit a mobile viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: JobDetailsScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(field('Vector Group'), 'YNd11d11');
    await tester.pumpAndSettle();
    expect(field('LV1 Voltage'), findsOneWidget);
    expect(field('LV2 Voltage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  setUp(
    () => SharedPreferences.setMockInitialValues({
      'username': 'test',
      'role': 'user',
    }),
  );

  testWidgets(
    'vector group determines whether one or two LV voltages are shown',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: JobDetailsScreen()));
      await tester.pumpAndSettle();
      expect(field('LV Voltage'), findsOneWidget);
      expect(field('LV2 Voltage'), findsNothing);
      for (final name in [
        'Dyn11d0',
        'Dd0yn11',
        'Dyn11yn11',
        'YNd11d11',
        'YNyn0d11',
      ]) {
        await tester.enterText(field('Vector Group'), name);
        await tester.pumpAndSettle();
        expect(field('LV1 Voltage'), findsOneWidget);
        expect(field('LV2 Voltage'), findsOneWidget);
      }
      await tester.enterText(field('LV2 Voltage'), '690');
      for (final name in ['Dyn11', 'Dd0', 'YNd11', 'Not Applicable']) {
        await tester.enterText(field('Vector Group'), name);
        await tester.pumpAndSettle();
        expect(field('LV Voltage'), findsOneWidget);
        expect(field('LV2 Voltage'), findsNothing);
      }
      await tester.enterText(field('Vector Group'), 'Dyn11d0');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('LV2 Voltage')).controller!.text,
        '690',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dual group menu choices are available', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: JobDetailsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Vector groups'));
    await tester.pumpAndSettle();
    expect(find.text('Dyn11d0'), findsOneWidget);
    expect(find.text('YNd11d11'), findsOneWidget);
    await tester.tap(find.text('Dyn11d0'));
    await tester.pumpAndSettle();
    expect(field('LV2 Voltage'), findsOneWidget);
  });

  testWidgets(
    'invalid vector groups and invalid second voltages block saving',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: JobDetailsScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(field('Vector Group'), 'Dyn12');
      final form = tester.state<FormState>(find.byType(Form));
      expect(form.validate(), isFalse);
      await tester.pump();
      expect(
        find.text('Invalid single/dual-output vector group.'),
        findsOneWidget,
      );
      await tester.enterText(field('Vector Group'), 'Dyn11d0');
      await tester.pump();
      await tester.enterText(field('LV2 Voltage'), '0');
      expect(form.validate(), isFalse);
      await tester.pump();
      expect(find.text('Enter a positive voltage'), findsOneWidget);
    },
  );

  for (final dual in [true, false]) {
    testWidgets(
      'saving ${dual ? 'dual' : 'single'} output persists correct voltage fields',
      (tester) async {
        Map<String, dynamic>? saved;
        final client = MockClient((request) async {
          if (request.method == 'POST') {
            saved = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{}', 200);
          }
          return http.Response(jsonEncode(saved == null ? [] : [saved]), 200);
        });
        await http.runWithClient(() async {
          await tester.pumpWidget(const MaterialApp(home: JobDetailsScreen()));
          await tester.pumpAndSettle();
          await tester.enterText(field('Vector Group'), 'Dyn11d0');
          await tester.pump();
          await tester.enterText(field('LV2 Voltage'), '690');
          if (!dual) {
            await tester.enterText(field('Vector Group'), 'YNd11');
            await tester.pump();
          }
          for (final entry in {
            'Serial No': 'TRFDQA',
            'Purchaser Name': 'QA',
            'Purchaser Reference': 'QA',
            'KVA': '8600',
            'Phases': '3',
            'HV Voltage': '33000',
            dual ? 'LV1 Voltage' : 'LV Voltage': '710',
            'Tapping Max': '5',
            'Tapping Min': '-5',
            'Step Voltage': '2.5',
            'Quantity': '1',
            'Remark': '-',
          }.entries) {
            await tester.enterText(field(entry.key), entry.value);
          }
          final save = find.widgetWithText(ElevatedButton, 'Save Job');
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(saved, isNotNull);
          expect(saved!['vectorGroup'], dual ? 'Dyn11d0' : 'YNd11');
          expect(saved!['lvVoltage'], '710');
          expect(saved!.containsKey('lv2Voltage'), dual);
          if (dual) {
            expect(saved!['lv2Voltage'], '690');
            expect(find.textContaining('710-690'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        }, () => client);
      },
    );
  }

  testWidgets('both saved job voltages prefill the report form', (
    tester,
  ) async {
    final client = MockClient((request) async => http.Response('[]', 200));
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TestReportPdfGeneratorScreen(
            generalData: {
              'vectorGroup': 'Dyn11d0',
              'lvVoltage': '710',
              'lv2Voltage': '690',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('Star Voltage')).controller!.text,
        '710',
      );
      expect(
        tester.widget<TextFormField>(field('Delta Voltage')).controller!.text,
        '690',
      );
      expect(tester.takeException(), isNull);
    }, () => client);
  });
}
