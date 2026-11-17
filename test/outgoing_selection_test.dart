import 'dart:async';
import 'dart:convert';

import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/screens/material_outgoing_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const jobA = {'serialNo': 'TRFD0001'};
const jobB = {'serialNo': 'TRFD0002'};
const materialA = {'type': 'Bolt', 'subtype': 'A', 'jobSpecific': true};
const materialB = {'type': 'Bolt', 'subtype': 'B', 'jobSpecific': true};

http.Response rows(List<Object> data) => http.Response(jsonEncode(data), 200);

class PendingRead {
  PendingRead(this.request);
  final http.Request request;
  final result = Completer<http.Response>();
}

class OutgoingApi {
  final stock = <PendingRead>[];
  final indents = <PendingRead>[];
  final searches = <PendingRead>[];
  int writes = 0;
  Map<String, dynamic>? lastIssue;
  int writeStatus = 200;
  bool failJobs = false;

  Future<http.Response> handle(http.Request request) async {
    if (request.method != 'GET') {
      writes++;
      lastIssue = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"error":"Review allocation"}', writeStatus);
    }
    switch (request.url.path) {
      case '/jobs':
        return failJobs ? http.Response('{}', 500) : rows([jobA, jobB]);
      case '/materials':
        return rows([materialA, materialB]);
      case '/stock':
        final read = PendingRead(request);
        stock.add(read);
        return read.result.future;
      case '/outgoing_materials':
        if ((request.url.queryParameters['search'] ?? '').isEmpty)
          return rows([]);
        final read = PendingRead(request);
        searches.add(read);
        return read.result.future;
      default:
        if (request.url.path.startsWith('/job_indents/')) {
          final read = PendingRead(request);
          indents.add(read);
          return read.result.future;
        }
        throw StateError('Unexpected request: ${request.url}');
    }
  }
}

void selectJob(WidgetTester tester, Map<String, dynamic>? job) {
  tester
      .widget<DropdownSearch<Map<String, dynamic>>>(
        find.byKey(const Key('outgoing-job')),
      )
      .onChanged!(job);
}

void selectMaterial(WidgetTester tester, String subtype) {
  tester
      .widget<DropdownSearch<String>>(
        find.byKey(const Key('outgoing-material')),
      )
      .onChanged!('Bolt - $subtype');
}

ElevatedButton submitButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Submit Issue'),
    );

List<Object> lots(String serialNo, String subtype, int quantity) => [
  {
    'id': '$serialNo-$subtype',
    'serialNo': serialNo,
    'type': 'Bolt',
    'subtype': subtype,
    'quantity': quantity,
    'price': 10,
  },
];

Future<void> runScreen(
  WidgetTester tester,
  OutgoingApi api,
  Future<void> Function() action,
) async {
  SharedPreferences.setMockInitialValues({
    'username': 'tester',
    'role': 'admin',
  });
  await http.runWithClient(() async {
    await tester.pumpWidget(const MaterialApp(home: OutgoingMaterialScreen()));
    await tester.pumpAndSettle();
    await action();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, () => MockClient(api.handle));
}

void main() {
  testWidgets(
    'FIFO preview and submission split oldest lots at their own rates',
    (tester) async {
      final api = OutgoingApi()..writeStatus = 409;
      await runScreen(tester, api, () async {
        selectJob(tester, jobA);
        selectMaterial(tester, 'A');
        await tester.pump();
        final base = lots('TRFD0001', 'A', 5).single as Map<String, dynamic>;
        api.stock.single.result.complete(
          rows([
            {...base, 'id': 'missing-date', 'price': 1},
            {
              ...base,
              'id': 'newer',
              'entryDate': '2026-10-01T03:45:00Z',
              'price': 220,
            },
            {...base, 'id': 'empty', 'entryDate': '2026-09-30', 'quantity': 0},
            {
              ...base,
              'id': 'older',
              'entryDate': '2026-10-01T09:00:00',
              'quantity': 1,
              'price': 100,
            },
          ]),
        );
        await tester.pump();
        api.indents.single.result.complete(rows(lots('TRFD0001', 'A', 10)));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), '1.5');
        await tester.pump();
        final older = find.textContaining('StockID: older');
        final newer = find.textContaining('StockID: newer');
        expect(
          tester.getTopLeft(older).dy,
          lessThan(tester.getTopLeft(newer).dy),
        );
        expect(find.textContaining('StockID: missing-date'), findsNothing);
        expect(find.textContaining('StockID: empty'), findsNothing);
        submitButton(tester).onPressed!();
        await tester.pump();
        final details = api.lastIssue!['details'] as List;
        expect(details.map((lot) => [lot['id'], lot['consumedQty']]).toList(), [
          ['older', 1.0],
          ['newer', 0.5],
        ]);
        expect(api.lastIssue!['issuedValue'], 210);
        expect(api.lastIssue!['weightedAvgPrice'], 140);
        expect(api.stock.length, 2);
        expect(submitButton(tester).onPressed, isNull);
        api.stock.last.result.complete(rows([]));
        await tester.pump();
        api.indents.last.result.complete(rows(lots('TRFD0001', 'A', 10)));
        await tester.pumpAndSettle();
      });
    },
  );

  testWidgets('late stock cannot overwrite a newer material selection', (
    tester,
  ) async {
    final api = OutgoingApi();
    await runScreen(tester, api, () async {
      selectJob(tester, jobA);
      selectMaterial(tester, 'A');
      await tester.pump();
      expect(submitButton(tester).onPressed, isNull);
      selectMaterial(tester, 'B');
      await tester.pump();
      api.stock[1].result.complete(rows(lots('TRFD0001', 'B', 8)));
      await tester.pump();
      api.indents.single.result.complete(rows(lots('TRFD0001', 'B', 6)));
      await tester.pump();
      expect(find.text('Available Qty (FIFO): 8.0'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNotNull);
      api.stock[0].result.complete(rows(lots('TRFD0001', 'A', 99)));
      await tester.pumpAndSettle();
      expect(api.indents.length, 1);
      expect(find.text('Available Qty (FIFO): 8.0'), findsOneWidget);
      expect(find.textContaining('Indent Qty: 6.0'), findsOneWidget);
    });
  });

  testWidgets('late indent cannot overwrite a new job or cleared job', (
    tester,
  ) async {
    final api = OutgoingApi();
    await runScreen(tester, api, () async {
      selectJob(tester, jobA);
      selectMaterial(tester, 'A');
      await tester.pump();
      api.stock[0].result.complete(rows(lots('TRFD0001', 'A', 99)));
      await tester.pump();
      selectJob(tester, jobB);
      await tester.pump();
      expect(find.text('Available Qty (FIFO): 0.0'), findsOneWidget);
      api.stock[1].result.complete(rows(lots('TRFD0002', 'A', 7)));
      await tester.pump();
      expect(api.indents[1].request.url.path, '/job_indents/TRFD0002');
      api.indents[1].result.complete(rows(lots('TRFD0002', 'A', 5)));
      await tester.pump();
      api.indents[0].result.complete(rows(lots('TRFD0001', 'A', 99)));
      await tester.pumpAndSettle();
      expect(find.text('Available Qty (FIFO): 7.0'), findsOneWidget);
      expect(find.textContaining('Indent Qty: 5.0'), findsOneWidget);
      selectJob(tester, jobA);
      await tester.pump();
      selectJob(tester, null);
      await tester.pump();
      api.stock[2].result.complete(rows(lots('TRFD0001', 'A', 99)));
      await tester.pumpAndSettle();
      expect(submitButton(tester).onPressed, isNull);
      expect(find.text('Available Qty (FIFO): 0.0'), findsOneWidget);
      expect(api.indents.length, 2);
    });
  });

  testWidgets('failed selection stays blocked until retry and rejects NaN', (
    tester,
  ) async {
    final api = OutgoingApi();
    await runScreen(tester, api, () async {
      selectJob(tester, jobA);
      selectMaterial(tester, 'A');
      await tester.pump();
      api.stock.single.result.complete(http.Response('{}', 500));
      await tester.pumpAndSettle();
      expect(submitButton(tester).onPressed, isNull);
      expect(
        find.textContaining('Could not load stock and indent'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Retry stock and indent'));
      await tester.pump();
      api.stock[1].result.complete(rows(lots('TRFD0001', 'A', 8)));
      await tester.pump();
      api.indents.single.result.complete(rows(lots('TRFD0001', 'A', 6)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantity to Issue'),
        'NaN',
      );
      await tester.ensureVisible(find.text('Submit Issue'));
      await tester.tap(find.text('Submit Issue'));
      await tester.pump();
      expect(find.text('Enter valid number'), findsOneWidget);
      expect(api.writes, 0);
    });
  });

  testWidgets('initial load failure is visible and retryable', (tester) async {
    final api = OutgoingApi()..failJobs = true;
    await runScreen(tester, api, () async {
      expect(
        find.textContaining('Could not load jobs and materials'),
        findsOneWidget,
      );
      api.failJobs = false;
      await tester.tap(find.byTooltip('Retry jobs and materials'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('outgoing-job')), findsOneWidget);
    });
  });

  testWidgets('older searches cannot replace newer results', (tester) async {
    final api = OutgoingApi();
    await runScreen(tester, api, () async {
      final search = find.widgetWithText(TextField, 'Search outgoing entries');
      await tester.enterText(search, 'old');
      await tester.pump(const Duration(milliseconds: 401));
      await tester.enterText(search, 'new');
      api.searches[0].result.complete(
        rows([
          {'material': 'Old result'},
        ]),
      );
      await tester.pump();
      expect(find.text('Old result'), findsNothing);
      await tester.pump(const Duration(milliseconds: 401));
      api.searches[1].result.complete(
        rows([
          {'material': 'New result'},
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('New result'), findsOneWidget);
      expect(find.text('Old result'), findsNothing);
    });
  });

  testWidgets('selection completion after disposal is ignored', (tester) async {
    final api = OutgoingApi();
    await runScreen(tester, api, () async {
      selectJob(tester, jobA);
      selectMaterial(tester, 'A');
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      api.stock.single.result.complete(rows(lots('TRFD0001', 'A', 8)));
      await tester.pumpAndSettle();
      expect(api.indents, isEmpty);
    });
  });
}
