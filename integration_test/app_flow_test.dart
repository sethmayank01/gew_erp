import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gew_erp/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Basic App Flow: Launch, tap Submit, see next screen', (
    WidgetTester tester,
  ) async {
    // Start the app
    app.main();
    await tester.pumpAndSettle();

    // Check initial screen (e.g., look for a known widget or text)
    expect(find.text('Login'), findsOneWidget); // Change to what your app shows

    // Find and tap the submit button
    final submitButton = find.text('Submit');
    expect(submitButton, findsOneWidget);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    // Verify navigation/result (e.g., next screen loaded)
    expect(
      find.text('GEW ERP'),
      findsOneWidget,
    ); // Change to what you expect next
  });
}
