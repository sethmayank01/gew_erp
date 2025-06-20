import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/screens/job_indent_consumption.dart';

void main() {
  testWidgets('JobIndentConsumptionScreen shows loading indicator', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: JobIndentConsumptionScreen()));
    // You may need to mock ApiService to control loading state
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}