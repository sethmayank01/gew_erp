import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:gew_erp/screens/test_report_pdf_generator.dart';
import 'individual_load_test_test.dart' show individualReport;

class _OfflineFontCache extends PdfBaseCache {
  @override
  Future<Uint8List> resolve({
    required String name,
    required Uri uri,
    bool cache = true,
    Map<String, String>? headers,
  }) async {
    const path = String.fromEnvironment('REPORT_FONT_PATH');
    if (path.isNotEmpty) return File(path).readAsBytes();
    throw StateError('Offline test uses the built-in PDF font');
  }

  @override
  Future<void> add(String key, Uint8List bytes) async {}
  @override
  Future<Uint8List?> get(String key) async => null;
  @override
  Future<bool> contains(String key) async => false;
  @override
  Future<void> remove(String key) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'long dual-output ratio tables paginate in final and draft reports',
    () async {
      final previousCache = PdfBaseCache.defaultCache;
      PdfBaseCache.defaultCache = _OfflineFontCache();
      addTearDown(() => PdfBaseCache.defaultCache = previousCache);
      final data = individualReport()
        ..addAll({
          'serialNo': '17-TAP-QA',
          'dateOfTesting': '16-11-2026',
          'purchaserName': 'Pagination test',
          'phases': '3',
          'vectorGroup': 'Dyn11yn11',
          'tappingRangeMin': -10,
          'tappingRangeMax': 10,
          'stepVoltage': 1.25,
        });
      data['testData']['includeIndividualLoadTests'] = false;
      data['testData']['insulationResistance'] = {
        'hv-e': '100',
        'lv-e': '100',
        'hv-lv': '100',
      };
      data['testData']['noLoadTest'] = {
        for (final phase in ['U', 'V', 'W'])
          phase: {'amp': '1', 'volt': '710', 'watt': '100'},
      };
      for (final key in ['ratios', 'ratiosLv2']) {
        data['testData'][key] = List.generate(
          17,
          (_) => {'U': '46.48', 'V': '46.48', 'W': '46.48'},
        );
      }
      const savedPath = String.fromEnvironment('REPORT_QA_INPUT');
      final input = savedPath.isEmpty
          ? data
          : jsonDecode(await File(savedPath).readAsString())
                as Map<String, dynamic>;
      for (final draft in [false, true]) {
        final bytes = await TestReportPdfGenerator.generatePDF(input, draft);
        final document = latin1.decode(bytes);
        expect(document, startsWith('%PDF'));
        expect(
          RegExp(r'/Type\s*/Page\b').allMatches(document).length,
          greaterThan(1),
        );
        if (savedPath.isNotEmpty) {
          await Directory('tmp/pdfs').create(recursive: true);
          await File(
            'tmp/pdfs/trfd0721-${draft ? 'draft' : 'final'}-qa.pdf',
          ).writeAsBytes(bytes);
        }
      }
    },
  );
  testWidgets('preview reuses bytes and refreshes when report mode changes', (
    tester,
  ) async {
    const channel = MethodChannel('net.nfet.printing');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => {'canRaster': false},
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final previousCache = PdfBaseCache.defaultCache;
    PdfBaseCache.defaultCache = _OfflineFontCache();
    addTearDown(() => PdfBaseCache.defaultCache = previousCache);
    final data = individualReport()
      ..addAll({
        'isPreview': false,
        'serialNo': 'PREVIEW-QA',
        'purchaserName': 'Preview test',
        'dateOfTesting': '12-10-2026',
        'phases': '3',
        'tappingRangeMax': 0,
        'tappingRangeMin': 0,
        'stepVoltage': 0,
      });
    data['testData']['noLoadTest'] = {
      for (final phase in ['U', 'V', 'W'])
        phase: {'amp': '1', 'volt': '710', 'watt': '100'},
    };
    data['testData']['insulationResistance'] = {
      'hv-e': '100',
      'lv-e': '100',
      'hv-lv': '100',
    };
    await tester.pumpWidget(
      MaterialApp(home: TestReportPreviewScreen(data: data)),
    );
    await tester.pumpAndSettle();
    final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    late Future<Uint8List> first;
    await tester.runAsync(() async {
      first = preview.build(PdfPageFormat.a4) as Future<Uint8List>;
      expect(identical(first, preview.build(PdfPageFormat.a4)), isTrue);
      await first;
    });
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final draftPreview = tester.widget<PdfPreview>(find.byType(PdfPreview));
    expect(draftPreview.key, isNot(preview.key));
    await tester.runAsync(() async {
      final draft = draftPreview.build(PdfPageFormat.a4);
      expect(identical(first, draft), isFalse);
      await draft;
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  test('final has point 10 only, draft adds individual calculations', () async {
    final previousCache = PdfBaseCache.defaultCache;
    PdfBaseCache.defaultCache = _OfflineFontCache();
    addTearDown(() => PdfBaseCache.defaultCache = previousCache);
    final data = individualReport();
    data.addAll({
      'serialNo': 'INDIVIDUAL-QA',
      'dateOfTesting': '11-10-2026',
      'purchaserName': 'Report regression test',
      'phases': '3',
      'tappingRangeMax': 0,
      'tappingRangeMin': 0,
      'stepVoltage': 0,
    });
    data['testData']['insulationResistance'] = {
      'hv-e': '100',
      'lv-e': '100',
      'hv-lv': '100',
    };
    data['testData']['ratios'] = [
      {'U': '46.48', 'V': '46.48', 'W': '46.48'},
    ];
    data['testData']['ratiosLv2'] = [
      {'U': '80.50', 'V': '80.50', 'W': '80.50'},
    ];
    data['testData']['noLoadTest'] = {
      for (final phase in ['U', 'V', 'W'])
        phase: {'amp': '1', 'volt': '710', 'watt': '100'},
    };
    final enabled = await TestReportPdfGenerator.generatePDF(data, false);
    final draft = await TestReportPdfGenerator.generatePDF(data, true);
    data['testData']['includeIndividualLoadTests'] = false;
    final disabled = await TestReportPdfGenerator.generatePDF(data, false);
    final disabledDraft = await TestReportPdfGenerator.generatePDF(data, true);
    int pages(Uint8List bytes) =>
        RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length;
    expect(pages(enabled), pages(disabled) + 1);
    expect(pages(draft), pages(disabledDraft) + 3);
    expect(latin1.decode(enabled.sublist(0, 4)), '%PDF');
    if (const bool.fromEnvironment('REPORT_PDF_QA')) {
      await Directory('tmp/pdfs').create(recursive: true);
      await File('tmp/pdfs/individual-load-enabled.pdf').writeAsBytes(enabled);
      await File('tmp/pdfs/individual-load-draft.pdf').writeAsBytes(draft);
      await File(
        'tmp/pdfs/individual-load-disabled.pdf',
      ).writeAsBytes(disabled);
    }
  });
}
