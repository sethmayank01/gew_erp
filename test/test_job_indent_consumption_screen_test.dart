import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/screens/job_indent_consumption.dart';
import 'http_test_support.dart';

void main() {
  testWidgets('indent entry loads without a real server', (tester) async {
    await withEmptyApi(() async {
      await tester.pumpWidget(
        const MaterialApp(home: JobIndentConsumptionScreen()),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Job Indent Entry'), findsOneWidget);
      expect(find.text('Submit Indent'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
