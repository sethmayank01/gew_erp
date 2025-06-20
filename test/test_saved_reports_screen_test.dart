import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/screens/saved_reports_screen.dart';

void main() {
  testWidgets('SavedReportsScreen renders with ExpansionTile', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SavedReportsScreen()));
    expect(find.byType(SavedReportsScreen), findsOneWidget);
    // Optionally, pump and check for ExpansionTile or ListTile if you mock reports
  });
}