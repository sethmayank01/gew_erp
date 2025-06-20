import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/screens/material_outgoing_screen.dart';

void main() {
  testWidgets('OutgoingMaterialScreen renders and has submit button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: OutgoingMaterialScreen()));
    expect(find.text('Submit'), findsWidgets);
  });
}
