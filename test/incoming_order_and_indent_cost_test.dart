import 'dart:convert';

import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/screens/indent_view_screen.dart';
import 'package:gew_erp/screens/material_incoming_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response jsonResponse(Object data) => http.Response(jsonEncode(data), 200);

void setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<String> incomingTitles(WidgetTester tester) => tester
    .widgetList<ListTile>(find.byType(ListTile))
    .map((tile) => (tile.title! as Text).data!)
    .toList();

void main() {
  testWidgets(
    'pending incoming entries lead dated approved entries and reorder after approval',
    (tester) async {
      setViewport(tester, const Size(1200, 3000));
      SharedPreferences.setMockInitialValues({
        'username': 'admin',
        'role': 'admin',
      });
      Map<String, dynamic> entry(
        String id,
        String label,
        String? date,
        bool? approved,
      ) => {
        'id': id,
        'material': label,
        'type': 'Audit',
        'subtype': label,
        'quantity': 1,
        'price': 10,
        'user': 'admin',
        'entryDate': date,
        if (approved != null) 'approved': approved,
        'invoice': (id == 'a1' || id == 'p2') ? 'needle' : 'other',
      };
      final entries = [
        entry('a1', 'Approved newest', '2026-11-03T12:00:00', true),
        entry('p2', 'Pending oldest', '2026-10-01T12:00:00', false),
        entry('a2', 'Approved older', '2026-10-31T12:00:00', true),
        entry('p1', 'Pending newest', '2026-11-02T12:00:00', false),
        entry('p3', 'Pending missing date', null, null),
        entry('a3', 'Approved invalid date', 'bad-date', true),
        entry('p4', 'Pending invalid date', 'bad-date', false),
      ];
      final client = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/incoming_materials') {
          return jsonResponse(entries);
        }
        if (request.method == 'POST' &&
            request.url.path == '/incoming_materials/p1/approve') {
          entries.firstWhere((item) => item['id'] == 'p1')['approved'] = true;
          return jsonResponse({'message': 'Approved'});
        }
        return jsonResponse([]);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(home: MaterialIncomingScreen()),
        );
        await tester.pumpAndSettle();
        expect(incomingTitles(tester), [
          'Pending newest',
          'Pending oldest',
          'Pending missing date',
          'Pending invalid date',
          'Approved newest',
          'Approved older',
          'Approved invalid date',
        ]);
        final pendingTile = find.ancestor(
          of: find.text('Pending newest'),
          matching: find.byType(ListTile),
        );
        await tester.tap(
          find.descendant(
            of: pendingTile,
            matching: find.byTooltip('Approve'),
          ),
        );
        await tester.pumpAndSettle();
        expect(incomingTitles(tester), [
          'Pending oldest',
          'Pending missing date',
          'Pending invalid date',
          'Approved newest',
          'Pending newest',
          'Approved older',
          'Approved invalid date',
        ]);
        final search = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Search incoming entries',
        );
        await tester.enterText(search, 'needle');
        await tester.pumpAndSettle();
        expect(incomingTitles(tester), ['Pending oldest', 'Approved newest']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }, () => client);
    },
  );

  for (final scenario in <({Object? quantity, String? perUnit})>[
    (quantity: 2, perUnit: 'Cost per Unit (2 nos): \u20b9105.00'),
    (quantity: '3', perUnit: 'Cost per Unit (3 nos): \u20b970.00'),
    (quantity: 1, perUnit: null),
    (quantity: null, perUnit: null),
    (quantity: 0, perUnit: null),
    (quantity: 'invalid', perUnit: null),
    (quantity: 'NaN', perUnit: null),
  ]) {
    testWidgets('indent costing uses saved quantity ${scenario.quantity}', (
      tester,
    ) async {
      setViewport(tester, const Size(1200, 900));
      SharedPreferences.setMockInitialValues({});
      final job = <String, dynamic>{
        'serialNo': 'TRFD0745',
        'quantity': scenario.quantity,
      };
      final client = MockClient((request) async {
        if (request.url.path == '/jobs') return jsonResponse([job]);
        if (request.url.path == '/materials') {
          return jsonResponse([
            {'type': 'Core', 'subtype': 'CRGO', 'category': 'CCA'},
          ]);
        }
        if (request.url.path == '/job_indents/TRFD0745') {
          return jsonResponse([
            {'type': 'Core', 'subtype': 'CRGO', 'issuedValue': 150},
            {'type': 'Copper', 'subtype': 'Wire', 'issuedValue': '60.00'},
            {'type': 'Other', 'subtype': 'Unissued', 'issuedValue': null},
          ]);
        }
        throw StateError('Unexpected request: ${request.url}');
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: IndentViewScreen()));
        await tester.pumpAndSettle();
        tester
            .widget<DropdownSearch<Map<String, dynamic>>>(
              find.byType(DropdownSearch<Map<String, dynamic>>),
            )
            .onChanged!(job);
        await tester.pumpAndSettle();
        expect(find.text('Final Total Price: \u20b9210.00'), findsOneWidget);
        if (scenario.perUnit == null) {
          expect(find.textContaining('Cost per Unit'), findsNothing);
        } else {
          expect(find.text(scenario.perUnit!), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        tester
            .widget<DropdownSearch<Map<String, dynamic>>>(
              find.byType(DropdownSearch<Map<String, dynamic>>),
            )
            .onChanged!(null);
        await tester.pumpAndSettle();
        expect(find.textContaining('Final Total Price'), findsNothing);
        expect(find.textContaining('Cost per Unit'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }, () => client);
    });
  }

  testWidgets(
    'multi-unit costing wraps on a narrow screen and updates between jobs',
    (tester) async {
      setViewport(tester, const Size(360, 800));
      SharedPreferences.setMockInitialValues({});
      final multi = <String, dynamic>{'serialNo': 'MULTI', 'quantity': '3'};
      final single = <String, dynamic>{'serialNo': 'SINGLE', 'quantity': 1};
      final client = MockClient((request) async {
        if (request.url.path == '/jobs') return jsonResponse([multi, single]);
        if (request.url.path == '/materials') return jsonResponse([]);
        return jsonResponse([
          {
            'type': 'Core',
            'subtype': 'CRGO',
            'issuedValue': request.url.path.endsWith('MULTI') ? 300 : 75,
          },
        ]);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: IndentViewScreen()));
        await tester.pumpAndSettle();
        void select(Map<String, dynamic> job) => tester
            .widget<DropdownSearch<Map<String, dynamic>>>(
              find.byType(DropdownSearch<Map<String, dynamic>>),
            )
            .onChanged!(job);
        select(multi);
        await tester.pumpAndSettle();
        expect(find.text('Final Total Price: \u20b9300.00'), findsOneWidget);
        expect(
          find.text('Cost per Unit (3 nos): \u20b9100.00'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        select(single);
        await tester.pumpAndSettle();
        expect(find.text('Final Total Price: \u20b975.00'), findsOneWidget);
        expect(find.textContaining('Cost per Unit'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }, () => client);
    },
  );
}
