import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gew_erp/screens/second_input_screen.dart';
import 'individual_load_test_test.dart' show individualReport;

void main() {
  for (final enabled in [false, true]) {
    testWidgets('preview persists individual test option $enabled', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'username': 'test'});
      final data = individualReport();
      data['testData']['includeIndividualLoadTests'] = enabled;
      data['testData']['insulationResistance'] = {
        'hv-e': '100',
        'lv-e': '100',
        'hv-lv': '100',
      };
      data['testData']['ratios'] = [
        {'U': '1', 'V': '1', 'W': '1'},
      ];
      data['testData']['ratiosLv2'] = [
        {'U': '1', 'V': '1', 'W': '1'},
      ];
      data['testData']['noLoadTest'] = data['testData']['loadTest'];
      Map? captured;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                SecondInputScreen(generalData: data, tapCount: 1),
          ),
          GoRoute(
            path: '/preview',
            builder: (context, state) {
              captured = state.extra as Map;
              return const Scaffold(body: Text('Preview reached'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      final button = find.widgetWithText(ElevatedButton, 'Preview Report');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!['testData']['includeIndividualLoadTests'], enabled);
      if (enabled) {
        expect(
          captured!['testData']['individualLoadTests'],
          data['testData']['individualLoadTests'],
        );
      } else {
        expect(
          (captured!['testData'] as Map).containsKey('individualLoadTests'),
          isFalse,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'dual checkbox toggles named winding tests and preserves entries',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SecondInputScreen(
            generalData: {'vectorGroup': 'Dyn11d0'},
            tapCount: 1,
          ),
        ),
      );
      final checkbox = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(find.text('HV - Star Winding Impedance'), findsOneWidget);
      expect(find.text('HV - Delta Winding Impedance'), findsOneWidget);
      final voltage = find.widgetWithText(TextFormField, 'Volt (L-L)').first;
      await tester.ensureVisible(voltage);
      await tester.enterText(voltage, '1650');
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(find.text('HV - Star Winding Impedance'), findsNothing);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(find.text('1650'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('single output does not offer individual dual tests', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SecondInputScreen(
          generalData: {'vectorGroup': 'YNd11'},
          tapCount: 1,
        ),
      ),
    );
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('saved dual readings and measurement sides are restored', (
    tester,
  ) async {
    final data = individualReport(lvSide: true);
    data['testData']['insulationResistance'] = {
      'hv-e': '100',
      'lv-e': '100',
      'hv-lv': '100',
    };
    data['testData']['ratios'] = [];
    data['testData']['noLoadTest'] = data['testData']['loadTest'];
    await tester.pumpWidget(
      MaterialApp(home: SecondInputScreen(generalData: data, tapCount: 1)),
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    expect(find.text('HV - Delta Winding Impedance'), findsOneWidget);
    expect(find.text('HV - Star Winding Impedance'), findsOneWidget);
    expect(find.text('35.5'), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });
}
