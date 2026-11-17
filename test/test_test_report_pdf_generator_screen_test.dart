import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/screens/test_report_pdf_generator_screen.dart';
import 'http_test_support.dart';

void main() {
  testWidgets('report entry loads without a real server', (tester) async {
    await withEmptyApi(() async {
      await tester.pumpWidget(
        const MaterialApp(home: TestReportPdfGeneratorScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Report PDF Generator'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
