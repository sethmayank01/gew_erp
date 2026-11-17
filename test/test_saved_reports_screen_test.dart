import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/screens/saved_reports_screen.dart';
import 'http_test_support.dart';

void main() {
  testWidgets('saved reports loads without a real server', (tester) async {
    await withEmptyApi(() async {
      await tester.pumpWidget(const MaterialApp(home: SavedReportsScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(SavedReportsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
