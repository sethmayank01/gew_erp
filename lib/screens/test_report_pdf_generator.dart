import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../models/transformer_vector_group.dart';
import '../models/transformer_losses.dart';
import 'package:go_router/go_router.dart';

class TestReportPdfGenerator {
  static Future<Uint8List> generatePDF(
    Map<String, dynamic> data,
    bool isPreview,
  ) async {
    final pdf = pw.Document();
    final logoImage = await imageFromAssetBundle('assets/logo.png');

    final robotoFont = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    final double hv = double.tryParse(data['hvVoltage']?.toString() ?? '') ?? 0;
    final double lv = double.tryParse(data['lvVoltage']?.toString() ?? '') ?? 0;
    final double lv2 =
        double.tryParse(data['lv2Voltage']?.toString() ?? '') ?? 0;
    final double tapMin =
        double.tryParse(data['tappingRangeMin']?.toString() ?? '') ?? 0;
    final double tapMax =
        double.tryParse(data['tappingRangeMax']?.toString() ?? '') ?? 0;
    final double step =
        double.tryParse(data['stepVoltage']?.toString() ?? '') ?? 0;

    // Defensive: fallback if step is 0 (avoid division by zero)
    final int tapCount = (step == 0)
        ? 1
        : (((tapMax - tapMin) / step).round() + 1);
    final vectorGroup = data['vectorGroup']?.toString() ?? '';
    final vectorConfig = TransformerVectorGroup.fromName(vectorGroup);
    final List<double> tapSteps = List.generate(
      tapCount,
      (i) => (tapMax - (i * step)),
    );
    final List<int> tapStepsSno = List.generate(tapCount, (i) => (i + 1));

    final List ratioData = (data['testData']?['ratios'] as List?) ?? [];
    final List ratioDataLv2 = (data['testData']?['ratiosLv2'] as List?) ?? [];
    final losses = TransformerLosses.fromReport(data);
    final hvResistance = losses.windings['hv']!;
    final lvResistance = losses.windings['lv']!;
    final lv2Resistance = losses.windings['lv2'];

    final noLoad = (data['testData']?['noLoadTest']) ?? {};
    final loadTest = (data['testData']?['loadTest']) ?? {};

    final rmsVoltages = _calculateRMSVoltages(
      (noLoad ?? <String, dynamic>{}).cast<String, dynamic>(),
    );
    final totalNoLoadLoss = _calculateTotalWatt(
      (noLoad ?? <String, dynamic>{}).cast<String, dynamic>(),
    );

    final totalLoadLoss = losses.totals['measuredLoss']!;
    final correctedLoadLoss = losses.totals['correctedLoss']!;
    final i2rLossAmbient = losses.totals['copperAmbient']!;
    final i2rLoss75 = losses.totals['copper75']!;
    final strayLossAmbient = losses.totals['strayAmbient']!;
    final strayLoss75 = losses.totals['stray75']!;
    final loadLoss75 = losses.totals['load75']!;
    final zAmb = losses.totals['zAmbient']!;
    final rAmb = losses.totals['rAmbient']!;
    final xAmb = losses.totals['xAmbient']!;
    final r75 = losses.totals['r75']!;
    final z75 = losses.totals['z75']!;

    final baseTextStyle = pw.TextStyle(
      fontSize: 10,
      fontFallback: [robotoFont],
    );
    final boldStyle = pw.TextStyle(
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
      fontFallback: [robotoFont],
    );

    pw.Widget _section(String title, pw.Widget content) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey700),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            content,
          ],
        ),
      );
    }

    pw.Widget section(String title, pw.Widget content) => pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 8),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: boldStyle.copyWith(fontSize: 10)),
          pw.SizedBox(height: 4),
          content,
        ],
      ),
    );
    pw.Widget header(pw.Context context) => pw.Column(
      children: [
        pw.Row(
          children: [
            pw.Container(width: 60, height: 60, child: pw.Image(logoImage)),
            pw.SizedBox(width: 10),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "General Engineering Works",
                  style: pw.TextStyle(font: boldFont, fontSize: 16),
                ),
                pw.Text(
                  "C 35,36 UPSIDC Industrial Area, Prayagraj",
                  style: baseTextStyle,
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          "Routine Test Report",
          style: pw.TextStyle(font: boldFont, fontSize: 16),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(1),
          },
          children: [
            _row(
              'Purchaser Name',
              data['purchaserName'] ?? '',
              'Reference',
              data['purchaserReference'] ?? '',
              baseTextStyle,
            ),
            _row(
              'Serial No',
              data['serialNo'] ?? '',
              'Date of Testing',
              data['dateOfTesting'] ?? '',
              baseTextStyle,
            ),
            _row(
              'KVA',
              data['kva']?.toString() ?? '',
              'Phases',
              data['phases']?.toString() ?? '',
              baseTextStyle,
            ),
            _row(
              'HV Voltage',
              data['hvVoltage']?.toString() ?? '',
              'LV Voltage',
              vectorConfig.hasDualOutput
                  ? '${data['lvVoltage'] ?? ''}-${data['lv2Voltage'] ?? ''}'
                  : data['lvVoltage']?.toString() ?? '',
              baseTextStyle,
            ),
            _row(
              'Vector Group',
              data['vectorGroup'] ?? '',
              'Relevant IS',
              data['relevantIS'] ?? '',
              baseTextStyle,
            ),
            _row(
              'Tapping Range',
              '${data['tappingRangeMax'] ?? ''}% to ${data['tappingRangeMin'] ?? ''}%',
              'Step Voltage',
              '${data['stepVoltage'] ?? ''}%',
              baseTextStyle,
            ),
          ],
        ),
      ],
    );

    pw.Widget footer(pw.Context context) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Container(
              width: 180,
              height: 40,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey600),
              ),
              child: pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text("Tested by", style: baseTextStyle),
              ),
            ),
            pw.Container(
              width: 180,
              height: 40,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey600),
              ),
              child: pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text("", style: baseTextStyle), // empty middle box
              ),
            ),
            pw.Container(
              width: 180,
              height: 40,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey600),
              ),
              child: pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text("Witnessed by", style: baseTextStyle),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            "The test report is generated by GEW ERP Software and does not require any signature or stamp",
            style: baseTextStyle.copyWith(
              fontSize: 8,
              color: PdfColors.grey600,
              fontStyle: pw.FontStyle.italic,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
      ],
    );

    pw.PageTheme watermarkedPageTheme({pw.ThemeData? theme}) => pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      theme: theme,
      // Paint an opaque page, then the watermark beneath transparent tables.
      buildBackground: (context) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Container(
          color: PdfColors.white,
          child: pw.Center(
            child: pw.Opacity(
              opacity: 0.35,
              child: pw.Transform.rotate(
                angle: 0.5,
                child: pw.Text(
                  isPreview ? 'Draft' : 'GEW',
                  style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 100,
                    color: PdfColors.grey,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        maxPages: 100,
        pageTheme: watermarkedPageTheme(),
        header: header,
        footer: footer,
        build: (context) => [
          _section(
            '1. Insulation Resistance Test',
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
              },
              border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
              children: [
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      child: pw.Text('Temperature', style: baseTextStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      child: pw.Text(
                        '${data['testData']['temperature']}°C',
                        style: baseTextStyle,
                      ),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      child: pw.Text('HV-E', style: baseTextStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      child: pw.Text(
                        '${data['testData']['insulationResistance']['hv-e']} MΩ',
                        style: baseTextStyle,
                      ),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      child: pw.Text('LV-E', style: baseTextStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      child: pw.Text(
                        '${data['testData']['insulationResistance']['lv-e']} MΩ',
                        style: baseTextStyle,
                      ),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      child: pw.Text('HV-LV', style: baseTextStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      child: pw.Text(
                        '${data['testData']['insulationResistance']['hv-lv']} MΩ',
                        style: baseTextStyle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Ratio tables must be direct MultiPage children to span pages.
          for (
            var output = 0;
            output < (vectorConfig.hasDualOutput ? 2 : 1);
            output++
          ) ...[
            pw.NewPage(freeSpace: 80),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
              child: pw.Text(
                output == 0
                    ? '2. ${vectorConfig.outputRatioLabel(output)}'
                    : vectorConfig.outputRatioLabel(output),
                style: boldStyle,
              ),
            ),
            _buildRatioTable(
              tapStepsSno,
              tapSteps,
              hv,
              output == 0 ? lv : lv2,
              output == 0 ? ratioData : ratioDataLv2,
              vectorGroup,
              output,
            ),
          ],
          _section(
            '3. Measurement of Winding Resistance',
            pw.Column(
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: _buildResistance(
                        'HV Winding',
                        'in ${TransformerLosses.resistanceUnit(data, 'hv')}',
                        data['testData']['windingResistance']['hv'],
                        hvResistance,
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: _buildResistance(
                        vectorConfig.outputWindingLabel(0),
                        'in ${TransformerLosses.resistanceUnit(data, 'lv')}',
                        data['testData']['windingResistance']['lv'],
                        lvResistance,
                      ),
                    ),
                  ],
                ),
                if (vectorConfig.hasDualOutput) ...[
                  pw.SizedBox(height: 6),
                  _buildResistance(
                    vectorConfig.outputWindingLabel(1),
                    'in ${TransformerLosses.resistanceUnit(data, 'lv2')}',
                    data['testData']['windingResistance']['lv2'] ?? {},
                    lv2Resistance!,
                  ),
                ],
              ],
            ),
          ),
          pw.Stack(
            children: [
              // Your content
              pw.Column(
                children: [
                  _section(
                    '4. Measurement of No-Load Loss and Current',
                    _buildNoLoadTable(noLoad, totalNoLoadLoss),
                  ),
                  _section(
                    '5. Measurement of Short Circuit Impedance and Load Losses',
                    _buildLoadTable(
                      loadTest,
                      totalLoadLoss.toStringAsFixed(2),
                      loadLoss75.toStringAsFixed(2),
                      z75.toStringAsFixed(2),
                    ),
                  ),
                  _section(
                    '6. Induced Over Voltage Test',
                    pw.Container(
                      width: double.infinity,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Tested on HV side', style: baseTextStyle),
                          pw.Text(
                            'Applied 2 x ${data['hvVoltage']} Volts at 125 Hz. And Withstood for 45 sec.',
                            style: baseTextStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _section(
                    '7. Separate Source Voltage Test:',
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              '(A) Applied ${getWithstandVoltage(lv)} Between ${vectorConfig.outputWindingLabel(0)} to HV Winding & Earth and Withstood for 60 sec',
                              style: baseTextStyle,
                            ),
                          ],
                        ),
                        if (vectorConfig.hasDualOutput)
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                '(B) Applied ${getWithstandVoltage(lv2)} Between ${vectorConfig.outputWindingLabel(1)} to HV Winding & Earth and Withstood for 60 sec',
                                style: baseTextStyle,
                              ),
                            ],
                          ),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              '(${vectorConfig.hasDualOutput ? 'C' : 'B'}) Applied ${getWithstandVoltage(hv)} Between HV winding to ${List.generate(vectorConfig.outputStar.length, vectorConfig.outputWindingLabel).join(' & ')} & Earth and Withstood for 60 sec',
                              style: baseTextStyle,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _section(
                    '8. Polarity Phase Relationship Checked:',
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(data['vectorGroup'], style: baseTextStyle),
                            pw.Text('FOUND OK', style: baseTextStyle),
                          ],
                        ),
                        pw.SizedBox(height: 8),
                        // pw.Image(vectorImage, height: 120),
                      ],
                    ),
                  ),
                  _section(
                    '9. BDV OF Oil (by 2.5 mm gap):',
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        '> 60 KV (Average of 4 samples)',
                        style: baseTextStyle,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (losses.individualTests.isNotEmpty)
            pw.Inseparable(
              child: _section(
                '10. Individual Winding Impedance and Load Losses',
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (final entry in losses.individualTests.entries) ...[
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6),
                        child: pw.Text(
                          'HV - ${vectorConfig.outputWindingLabel(entry.key == 'lv' ? 0 : 1)}',
                          style: boldStyle,
                        ),
                      ),
                      _buildLoadTable(
                        Map<String, dynamic>.from(
                          data['testData']['individualLoadTests'][entry
                                  .key]['phases']
                              as Map,
                        ),
                        entry.value['measuredLoss']!.toStringAsFixed(2),
                        entry.value['load75']!.toStringAsFixed(2),
                        entry.value['z75']!.toStringAsFixed(2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (isPreview)
            pw.Stack(
              children: [
                // Your content
                pw.Column(
                  children: [
                    _section(
                      'Preview Calculations: Winding Resistance',
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'HV Avg Line Resistance (Ohm): ${hvResistance['avg']!.toStringAsFixed(6)}',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'HV R @ 75°C: ${hvResistance['r75']!.toStringAsFixed(4)}',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'HV Current (${hvResistance['kva']!.toStringAsFixed(0)} kVA): ${hvResistance['current']!.toStringAsFixed(2)} A',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'HV I²R Loss (ambient): ${(hvResistance['current']! * hvResistance['current']! * hvResistance['avg']! * 0.5 * 3).toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'HV I²R Loss (75°C): ${hvResistance['loss']!.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            '${vectorConfig.outputLabel(0)} Avg Line Resistance (Ohm): ${lvResistance['avg']!.toStringAsFixed(6)}',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            '${vectorConfig.outputLabel(0)} R @ 75°C (Ohm): ${lvResistance['r75']!.toStringAsFixed(6)}',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            '${vectorConfig.outputLabel(0)} Current (${lvResistance['kva']!.toStringAsFixed(0)} kVA): ${lvResistance['current']!.toStringAsFixed(2)} A',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            '${vectorConfig.outputLabel(0)} I²R Loss (ambient): ${lvResistance['ambientLoss']!.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            '${vectorConfig.outputLabel(0)} I²R Loss (75°C): ${lvResistance['loss']!.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          if (lv2Resistance != null) ...[
                            pw.SizedBox(height: 6),
                            pw.Text(
                              '${vectorConfig.outputLabel(1)} Avg Line Resistance (Ohm): ${lv2Resistance['avg']!.toStringAsFixed(6)}',
                              style: baseTextStyle,
                            ),
                            pw.Text(
                              '${vectorConfig.outputLabel(1)} R @ 75°C (Ohm): ${lv2Resistance['r75']!.toStringAsFixed(6)}',
                              style: baseTextStyle,
                            ),
                            pw.Text(
                              '${vectorConfig.outputLabel(1)} Current (${lv2Resistance['kva']!.toStringAsFixed(0)} kVA): ${lv2Resistance['current']!.toStringAsFixed(2)} A',
                              style: baseTextStyle,
                            ),
                            pw.Text(
                              '${vectorConfig.outputLabel(1)} I²R Loss (ambient): ${lv2Resistance['ambientLoss']!.toStringAsFixed(2)} W',
                              style: baseTextStyle,
                            ),
                            pw.Text(
                              '${vectorConfig.outputLabel(1)} I²R Loss (75°C): ${lv2Resistance['loss']!.toStringAsFixed(2)} W',
                              style: baseTextStyle,
                            ),
                          ],
                        ],
                      ),
                    ),
                    _section(
                      'Load Test Preview Calculations',
                      pw.Column(
                        children: [
                          pw.Text(
                            'RMS Voltages: U=${rmsVoltages['U']} V, V=${rmsVoltages['V']} V, W=${rmsVoltages['W']} V',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Total No Load Loss: $totalNoLoadLoss W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Measured Load Loss (test current): ${totalLoadLoss.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Average Measured Current: ${losses.totals['averageCurrent']!.toStringAsFixed(4)} A',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Rated HV Current: ${losses.totals['ratedCurrent']!.toStringAsFixed(4)} A',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'P(rated) = P(measured) x (I(rated) / I(avg))^2',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Corrected Load Loss (rated current, ambient): ${correctedLoadLoss.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'i²R Loss (ambient): ${i2rLossAmbient.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Stray Loss (ambient): ${strayLossAmbient.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Stray Loss (75°C): ${strayLoss75.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'i²R Loss (75°C): ${i2rLoss75.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Load Loss @ 75°C: ${loadLoss75.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            '%Z (ambient): ${zAmb.toStringAsFixed(2)}%',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            '%R (ambient): ${rAmb.toStringAsFixed(2)}%',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            '%X (ambient): ${xAmb.toStringAsFixed(2)}%',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            '%R (75°C): ${r75.toStringAsFixed(2)}%',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            '%Z (75°C): ${z75.toStringAsFixed(2)}%',
                            style: baseTextStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
    if (isPreview) {
      for (final entry in losses.individualTests.entries) {
        final outputIndex = entry.key == 'lv' ? 0 : 1;
        final input = data['testData']['individualLoadTests'][entry.key] as Map;
        final calc = entry.value;
        final side = input['measurementSide'] == 'hv'
            ? 'HV'
            : vectorConfig.outputWindingLabel(outputIndex);
        pdf.addPage(
          pw.MultiPage(
            pageTheme: watermarkedPageTheme(
              theme: pw.ThemeData.withFont(base: robotoFont, bold: boldFont),
            ),
            header: header,
            footer: footer,
            build: (context) => [
              _section(
                '${isPreview ? 'Draft - ' : ''}Individual HV - ${vectorConfig.outputWindingLabel(outputIndex)} Impedance and Load Losses',
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Test rating: ${calc['kva']!.toStringAsFixed(2)} kVA; Measurement side: $side',
                      style: baseTextStyle,
                    ),
                    pw.Text(
                      'Other output winding open; voltage readings are phase-to-phase.',
                      style: baseTextStyle,
                    ),
                    pw.SizedBox(height: 8),
                    _buildLoadTable(
                      Map<String, dynamic>.from(input['phases'] as Map),
                      calc['measuredLoss']!.toStringAsFixed(2),
                      calc['load75']!.toStringAsFixed(2),
                      calc['z75']!.toStringAsFixed(2),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'P(rated) = P(measured) x (I(rated) / I(avg))^2',
                      style: baseTextStyle,
                    ),
                    pw.SizedBox(height: 4),
                    pw.TableHelper.fromTextArray(
                      headers: ['Parameter', 'Value'],
                      data: [
                        [
                          'Average Current',
                          '${calc['averageCurrent']!.toStringAsFixed(2)} A',
                        ],
                        [
                          'Rated Current ($side)',
                          '${calc['ratedCurrent']!.toStringAsFixed(2)} A',
                        ],
                        [
                          'Average Voltage (L-L)',
                          '${calc['averageVoltage']!.toStringAsFixed(2)} V',
                        ],
                        [
                          'Corrected Voltage (L-L)',
                          '${calc['correctedVoltage']!.toStringAsFixed(2)} V',
                        ],
                        [
                          'Load Loss at Rated Current (ambient)',
                          '${calc['correctedLoss']!.toStringAsFixed(2)} W',
                        ],
                        [
                          'Pair I2R Loss (ambient)',
                          '${calc['copperAmbient']!.toStringAsFixed(2)} W',
                        ],
                        [
                          'Pair I2R Loss (75 C)',
                          '${calc['copper75']!.toStringAsFixed(2)} W',
                        ],
                        [
                          'Stray Loss (ambient)',
                          '${calc['strayAmbient']!.toStringAsFixed(2)} W',
                        ],
                        [
                          'Stray Loss (75 C)',
                          '${calc['stray75']!.toStringAsFixed(2)} W',
                        ],
                        [
                          '%Z (ambient)',
                          '${calc['zAmbient']!.toStringAsFixed(2)}%',
                        ],
                        [
                          '%R (ambient)',
                          '${calc['rAmbient']!.toStringAsFixed(2)}%',
                        ],
                        [
                          '%X (ambient)',
                          '${calc['xAmbient']!.toStringAsFixed(2)}%',
                        ],
                        ['%R (75 C)', '${calc['r75']!.toStringAsFixed(2)}%'],
                        ['%Z (75 C)', '${calc['z75']!.toStringAsFixed(2)}%'],
                      ],
                      border: pw.TableBorder.all(
                        color: PdfColors.grey,
                        width: 0.75,
                      ),
                      headerStyle: boldStyle,
                      cellStyle: baseTextStyle,
                      cellPadding: const pw.EdgeInsets.symmetric(
                        vertical: 3,
                        horizontal: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    }
    return pdf.save();
  }

  static String getWithstandVoltage(double voltage) {
    if (voltage <= 1000) return '3 KV';
    if (voltage > 1000 && voltage <= 3300) return '10 KV';
    if (voltage > 3300 && voltage <= 6600) return '20 KV';
    if (voltage > 6600 && voltage <= 11000) return '28 KV';
    if (voltage > 11000 && voltage <= 22000) return '50 KV';
    if (voltage > 22000 && voltage <= 33000) return '70 KV';
    return '';
  }

  static pw.TableRow _row(
    String key1,
    String val1,
    String key2,
    String val2,
    pw.TextStyle style,
  ) {
    return pw.TableRow(
      children: [
        pw.Text('$key1: $val1', style: style),
        pw.Text('$key2: $val2', style: style),
      ],
    );
  }

  static Map<String, String> _calculateRMSVoltages(Map<String, dynamic> data) {
    return {
      'U': (double.tryParse(data['U']['volt'].toString()) ?? 0 / sqrt(3))
          .toStringAsFixed(2),
      'V': (double.tryParse(data['V']['volt'].toString()) ?? 0 / sqrt(3))
          .toStringAsFixed(2),
      'W': (double.tryParse(data['W']['volt'].toString()) ?? 0 / sqrt(3))
          .toStringAsFixed(2),
    };
  }

  static String _calculateTotalWatt(Map<String, dynamic> data) {
    final w1 = double.tryParse(data['U']['watt'].toString()) ?? 0;
    final w2 = double.tryParse(data['V']['watt'].toString()) ?? 0;
    final w3 = double.tryParse(data['W']['watt'].toString()) ?? 0;
    return (w1 + w2 + w3).toStringAsFixed(2);
  }

  static pw.Widget _buildResistance(
    String label,
    String unit,
    Map res,
    Map<String, double> calc,
  ) {
    final baseTextStyle = pw.TextStyle(fontSize: 10);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('$label Resistance $unit', style: baseTextStyle),
        pw.TableHelper.fromTextArray(
          headers: res.keys.toList(),
          data: [res.values.map((e) => e.toString()).toList()],
          border: pw.TableBorder.all(color: PdfColors.grey, width: 0.75),
          headerStyle: pw.TextStyle(fontSize: 10),
          cellStyle: pw.TextStyle(fontSize: 10),
          cellPadding: const pw.EdgeInsets.symmetric(
            vertical: 2,
            horizontal: 4,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildRatioTable(
    List<int> sno,
    List<double> tapSteps,
    double hv,
    double lv,
    List ratios,
    String vectorGroup,
    int outputIndex,
  ) {
    final config = TransformerVectorGroup.fromName(vectorGroup);

    return pw.TableHelper.fromTextArray(
      headers: [
        'S.No',
        'Tap (%)',
        'Calculated Ratio',
        'U',
        'U Dev %',
        'V',
        'V Dev %',
        'W',
        'W Dev %',
      ],
      data: List.generate(tapSteps.length, (i) {
        final tap = tapSteps[i];
        final calcRatio = config.calculatedRatio(
          hvLineVoltage: hv,
          outputLineVoltage: lv,
          tapPercent: tap,
          outputIndex: outputIndex,
        );
        final user = i < ratios.length ? ratios[i] : const {};
        return [
          sno[i],
          tap.toStringAsFixed(2),
          calcRatio.toStringAsFixed(2),
          user['U'].toString(),
          _deviation(calcRatio, user['U']),
          user['V'].toString(),
          _deviation(calcRatio, user['V']),
          user['W'].toString(),
          _deviation(calcRatio, user['W']),
        ];
      }),
      border: pw.TableBorder.all(color: PdfColors.grey, width: 0.75),
      headerStyle: pw.TextStyle(fontSize: 10),
      cellStyle: pw.TextStyle(fontSize: 10),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
    );
  }

  static String _deviation(double calc, dynamic user) {
    double u = double.tryParse(user.toString()) ?? 0;
    if (calc == 0) return '0.00';
    double dev = ((u - calc) / calc) * 100;
    return dev.toStringAsFixed(2);
  }

  static pw.Widget _buildNoLoadTable(
    Map<String, dynamic> data,
    String noLoadLoss,
  ) {
    return pw.TableHelper.fromTextArray(
      headers: ['Phase', 'Amp', 'Volt', 'Watt'],
      data: [
        ['U', data['U']['amp'], data['U']['volt'], data['U']['watt']],
        ['V', data['V']['amp'], data['V']['volt'], data['V']['watt']],
        ['W', data['W']['amp'], data['W']['volt'], data['W']['watt']],
        ['', '', 'Total Losses:', noLoadLoss],
      ],
      border: pw.TableBorder.all(color: PdfColors.grey, width: 0.75),
      headerStyle: pw.TextStyle(fontSize: 10),
      cellStyle: pw.TextStyle(fontSize: 10),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
    );
  }

  static pw.Widget _buildLoadTable(
    Map<String, dynamic> data,
    String totalLosses,
    String lossat75,
    String zat75,
  ) {
    return pw.TableHelper.fromTextArray(
      headers: ['Phase', 'Amp', 'Volt', 'Watt'],
      data: [
        ['U', data['U']['amp'], data['U']['volt'], data['U']['watt']],
        ['V', data['V']['amp'], data['V']['volt'], data['V']['watt']],
        ['W', data['W']['amp'], data['W']['volt'], data['W']['watt']],
        ['', '', 'Load Losses:', totalLosses],
        ['', '', 'Load Losses at 75°C:', lossat75],
        ['', '', 'Impedance at 75°C:', zat75],
      ],
      border: pw.TableBorder.all(color: PdfColors.grey, width: 0.75),
      headerStyle: pw.TextStyle(fontSize: 10),
      cellStyle: pw.TextStyle(fontSize: 10),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
    );
  }
}

class TestReportPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const TestReportPreviewScreen({super.key, required this.data});

  @override
  State<TestReportPreviewScreen> createState() =>
      _TestReportPreviewScreenState();
}

class _TestReportPreviewScreenState extends State<TestReportPreviewScreen> {
  bool _isPreview = true;
  bool _isDownloading = false;
  Map<String, dynamic>? _pendingDownloadReport;
  Future<Uint8List>? _pdfBytes;

  Future<Uint8List> _documentBytes() =>
      _pdfBytes ??= TestReportPdfGenerator.generatePDF(widget.data, _isPreview);

  @override
  void initState() {
    super.initState();
    _isPreview = widget.data['isPreview'] != false;
  }

  @override
  void didUpdateWidget(covariant TestReportPreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _isPreview = widget.data['isPreview'] != false;
      _pdfBytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Report Preview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              context.go('/dashboard'); // Navigate to your home/dashboard route
            },
          ),
          Row(
            children: [
              const Text('Preview'),
              Switch(
                value: _isPreview,
                onChanged: _isDownloading || _pendingDownloadReport != null
                    ? null
                    : (val) {
                        setState(() {
                          _isPreview = val;
                          _pdfBytes = null;
                        });
                      },
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              key: ValueKey(_isPreview),
              build: (format) => _documentBytes(),
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              allowPrinting: false,
              allowSharing: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('Save PDF to Downloads'),
              onPressed: _isDownloading
                  ? null
                  : () async {
                      if (_isDownloading) return;
                      setState(() => _isDownloading = true);
                      try {
                        final bytes = await _documentBytes();

                        final dir = await getDownloadDirectory();
                        final fileName =
                            'TestReport_${widget.data['serialNo'] ?? 'Report'}.pdf';
                        final file = File('${dir.path}/$fileName');
                        await file.writeAsBytes(bytes);
                        final reportToSave = _pendingDownloadReport ??= {
                          ...widget.data,
                          'isPreview': _isPreview,
                          'timestamp': DateTime.now().toIso8601String(),
                          'remark':
                              '${widget.data['remark'] ?? ''} - Downloaded',
                        };
                        await ApiService.saveReport(reportToSave);
                        _pendingDownloadReport = null;
                        if (!mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'PDF saved to ${file.path} and report stored.',
                            ),
                          ),
                        );
                      } catch (e) {
                        if (e is ApiException && e.statusCode < 500)
                          _pendingDownloadReport = null;
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error saving PDF: $e')),
                        );
                      } finally {
                        if (mounted) setState(() => _isDownloading = false);
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }

  Future<Directory> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Storage permission not granted');
      }
      return Directory('/storage/emulated/0/Download');
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }
}

/*
class TestReportPreviewScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const TestReportPreviewScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Report Preview')),
      body: PdfPreview(
        build: (format) => TestReportPdfGenerator.generatePDF(data, false),
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
      ),
    );
  }
}*/
