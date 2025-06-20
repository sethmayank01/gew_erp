import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/screens/test_report_pdf_generator_screen.dart';

void main() {
  testWidgets('TestReportPdfGeneratorScreen displays app bar', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: TestReportPdfGeneratorScreen()));
    expect(find.text('Test Report PDF Generator'), findsOneWidget);
  });
}