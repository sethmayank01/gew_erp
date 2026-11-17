import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/screens/material_outgoing_screen.dart';
import 'http_test_support.dart';

void main() {
  testWidgets('outgoing entry loads and shows issue action', (tester) async {
    await withEmptyApi(() async {
      await tester.pumpWidget(
        const MaterialApp(home: OutgoingMaterialScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Issue'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
