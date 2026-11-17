import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:gew_erp/main.dart';
import 'http_test_support.dart';

void main() {
  testWidgets('app starts at login without waiting for an update server', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'GEW ERP',
      packageName: 'gew_erp',
      version: '1.2.9',
      buildNumber: '1',
      buildSignature: '',
    );
    await withEmptyApi(() async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Checking for Updates'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
