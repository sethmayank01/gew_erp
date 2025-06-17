import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'package:go_router/go_router.dart';

class TestReportPdfGenerator {
  static Future<Uint8List> generatePDF(
    Map<String, dynamic> data,
    bool isPreview,
  ) async {
    //Temp Code Mayank for testing
    // Default data for testing

    final pdf = pw.Document();
    final logoImage = await imageFromAssetBundle('assets/logo.png');

    final robotoFont = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    final double hv = double.tryParse(data['hvVoltage']?.toString() ?? '') ?? 0;
    final double lv = double.tryParse(data['lvVoltage']?.toString() ?? '') ?? 0;
    final double tapMin =
        double.tryParse(data['tappingRangeMin']?.toString() ?? '') ?? 0;
    final double tapMax =
        double.tryParse(data['tappingRangeMax']?.toString() ?? '') ?? 0;
    final double step =
        double.tryParse(data['stepVoltage']?.toString() ?? '') ?? 0;
    final double kva = double.tryParse(data['kva']?.toString() ?? '') ?? 0;
    final double temperature =
        double.tryParse(data['testData']['temperature']?.toString() ?? '') ?? 0;

    final List<double> tapSteps = List.generate(
      (((tapMax - tapMin) / step).round() + 1),
      (i) => (tapMax - (i * step)),
    );
    final List<int> tapStepsSno = List.generate(
      (((tapMax - tapMin) / step).round() + 1),
      (i) => (i + 1),
    );

    final List ratioData = data['testData']['ratios'];
    final Map<String, double> hvResistance = _calcResistanceHV(
      data['testData']['windingResistance']['hv'],
      temperature,
      kva,
      hv,
    );
    final Map<String, double> lvResistance = _calcResistanceLV(
      data['testData']['windingResistance']['lv'],
      temperature,
      kva,
      lv,
    );

    final noLoad = data['testData']['noLoadTest'];
    final loadTest = data['testData']['loadTest'];
    final rmsVoltages = _calculateRMSVoltages(noLoad);
    final totalNoLoadLoss = _calculateTotalWatt(noLoad);

    final Map<String, double> loadAmps = {
      'U': double.tryParse(loadTest['U']['amp'].toString()) ?? 0,
      'V': double.tryParse(loadTest['V']['amp'].toString()) ?? 0,
      'W': double.tryParse(loadTest['W']['amp'].toString()) ?? 0,
    };
    final Map<String, double> loadVolts = {
      'U': double.tryParse(loadTest['U']['volt'].toString()) ?? 0,
      'V': double.tryParse(loadTest['V']['volt'].toString()) ?? 0,
      'W': double.tryParse(loadTest['W']['volt'].toString()) ?? 0,
    };
    final Map<String, double> loadWatts = {
      'U': double.tryParse(loadTest['U']['watt'].toString()) ?? 0,
      'V': double.tryParse(loadTest['V']['watt'].toString()) ?? 0,
      'W': double.tryParse(loadTest['W']['watt'].toString()) ?? 0,
    };

    final avgAmp = (loadAmps['U']! + loadAmps['V']! + loadAmps['W']!) / 3;
    final totalLoadLoss = loadWatts.values.reduce((a, b) => a + b);
    final correctedLoadLoss = (hvResistance['current']! / avgAmp) *
        (hvResistance['current']! / avgAmp) *
        totalLoadLoss;
    final i2rLoss75 = hvResistance['loss']! + lvResistance['loss']!;
    final tempFactor = (235 + temperature) / (235 + 75);
    final loadLoss75 =
        i2rLoss75 + correctedLoadLoss - (i2rLoss75 * tempFactor * tempFactor);
    final strayLoss = loadLoss75 - i2rLoss75;

    final avgVolt =
        (loadVolts['U']! + loadVolts['V']! + loadVolts['W']!) / 3 / sqrt(3);
    final correctedVoltage = (hvResistance['current']! / avgAmp) * avgVolt;
    final zAmb = correctedVoltage * sqrt(3) / hv * 100;
    final rAmb = (correctedLoadLoss / 1000) / kva * 100;
    final xAmb = sqrt(pow(zAmb, 2) - pow(rAmb, 2));
    final r75 = (loadLoss75 / 1000) / kva * 100;
    final z75 = sqrt(pow(xAmb, 2) + pow(r75, 2));

    final vectorGroup = data['vectorGroup'].toString().toLowerCase();
    //  final vectorImage = await imageFromAssetBundle('assets/$vectorGroup.png');
    //final vectorImage = await imageFromAssetBundle('assets/dyn11.png');
    /* Mayank to be removed final baseTextStyle = pw.TextStyle(fontSize: 10);
    final boldStyle = pw.TextStyle(
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
    );
    final ttf = await fontFromAssetBundle('fonts/Roboto-Regular.ttf');
    final baseTextStyle = pw.TextStyle(font: ttf, fontSize: 10);

    final boldStyle =
        pw.TextStyle(font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold);
        */
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
            pw.Text(title,
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
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
    pw.Widget header(pw.Context context) => pw.Column(children: [
          pw.Row(children: [
            pw.Container(
              width: 60,
              height: 60,
              child: pw.Image(logoImage),
            ),
            pw.SizedBox(width: 10),
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("General Engineering Works",
                      style: pw.TextStyle(font: boldFont, fontSize: 16)),
                  pw.Text("C 35,36 UPSIDC Industrial Area, Prayagraj",
                      style: baseTextStyle),
                ])
          ]),
          pw.SizedBox(height: 10),
          pw.Text("Routine Test Report",
              style: pw.TextStyle(font: boldFont, fontSize: 16)),
          pw.SizedBox(height: 6),
          pw.Table(columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(1),
          }, children: [
            _row('Purchaser Name', data['purchaserName'], 'Reference',
                data['purchaserReference'], baseTextStyle),
            _row('Serial No', data['serialNo'], 'Date of Testing', data['date'],
                baseTextStyle),
            _row('KVA', data['kva'].toString(), 'Phases',
                data['phases'].toString(), baseTextStyle),
            _row('HV Voltage', data['hvVoltage'], 'LV Voltage',
                data['lvVoltage'], baseTextStyle),
            _row('Vector Group', data['vectorGroup'], 'Relevant IS',
                data['relevantIS'], baseTextStyle),
            _row(
                'Tapping Range',
                '${data['tappingRangeMax']}% to ${data['tappingRangeMin']}%',
                'Step Voltage',
                '${data['stepVoltage']}%',
                baseTextStyle),
          ])
        ]);

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
                    child:
                        pw.Text("", style: baseTextStyle), // empty middle box
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
                "The test report is generated by GEW ERP Software 1.1 and does not require any signature or stamp",
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

    /* pdf.addPage(
      pw.MultiPage(
        maxPages: 100,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
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
                          vertical: 2, horizontal: 4),
                      child: pw.Text('Temperature', style: baseTextStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2, horizontal: 4),
                      child: pw.Text('${data['testData']['temperature']}°C',
                          style: baseTextStyle),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2, horizontal: 4),
                      child: pw.Text('HV-E', style: baseTextStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2, horizontal: 4),
                      child: pw.Text(
                          '${data['testData']['insulationResistance']['hv-e']} MΩ',
                          style: baseTextStyle),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2, horizontal: 4),
                      child: pw.Text('LV-E', style: baseTextStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2, horizontal: 4),
                      child: pw.Text(
                          '${data['testData']['insulationResistance']['lv-e']} MΩ',
                          style: baseTextStyle),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2, horizontal: 4),
                      child: pw.Text('HV-LV', style: baseTextStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2, horizontal: 4),
                      child: pw.Text(
                          '${data['testData']['insulationResistance']['hv-lv']} MΩ',
                          style: baseTextStyle),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _section(
            '2. Ratio Test',
            _buildRatioTable(tapStepsSno, tapSteps, hv, lv, ratioData),
          ),
          _section(
            '3. Measurement of Winding Resistance',
            pw.Row(
              children: [
                pw.Expanded(
                    child: _buildResistance(
                        'HV',
                        'in Ohm',
                        data['testData']['windingResistance']['hv'],
                        hvResistance)),
                pw.SizedBox(width: 8),
                pw.Expanded(
                    child: _buildResistance(
                        'LV',
                        'in Ohm',
                        data['testData']['windingResistance']['lv'],
                        lvResistance)),
              ],
            ),
          ),
          pw.NewPage(),
          _section('4. Measurement of No-Load Loss and Current',
              _buildNoLoadTable(noLoad, totalNoLoadLoss)),
          _section(
              '5. Measurement of Short Circuit Impedance and Load Losses',
              _buildLoadTable(loadTest, totalLoadLoss.toStringAsFixed(2),
                  loadLoss75.toStringAsFixed(2), z75.toStringAsFixed(2))),
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
                      '(A) Applied ${getWithstandVoltage(lv)} Between LV winding to HV Winding & Earth and Withstood for 60 sec',
                      style: baseTextStyle,
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '(B) Applied ${getWithstandVoltage(hv)} Between HV winding to LV Winding & Earth and Withstood for 60 sec',
                      style: baseTextStyle,
                    ),
                  ],
                )
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
          if (isPreview) pw.NewPage(),
          if (isPreview)
            _section(
                'Preview Calculations: Winding Resistance',
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                        'HV Avg Line Resistance: ${hvResistance['avg']!.toStringAsFixed(4)}',
                        style: baseTextStyle),
                    pw.Text(
                        'HV R @ 75°C: ${hvResistance['r75']!.toStringAsFixed(4)}',
                        style: baseTextStyle),
                    pw.Text(
                        'HV Current: ${hvResistance['current']!.toStringAsFixed(2)} A',
                        style: baseTextStyle),
                    pw.Text(
                        'HV I²R Loss: ${hvResistance['loss']!.toStringAsFixed(2)} W',
                        style: baseTextStyle),
                    pw.SizedBox(height: 6),
                    pw.Text(
                        'LV Avg Line Resistance: ${lvResistance['avg']!.toStringAsFixed(4)}',
                        style: baseTextStyle),
                    pw.Text(
                        'LV R @ 75°C: ${lvResistance['r75']!.toStringAsFixed(4)}',
                        style: baseTextStyle),
                    pw.Text(
                        'LV Current: ${lvResistance['current']!.toStringAsFixed(2)} A',
                        style: baseTextStyle),
                    pw.Text(
                        'LV I²R Loss: ${lvResistance['loss']!.toStringAsFixed(2)} W',
                        style: baseTextStyle),
                  ],
                )),
          if (isPreview)
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
                    'Total Load Loss: ${totalLoadLoss.toStringAsFixed(2)} W',
                    style: baseTextStyle,
                  ),
                  pw.Text(
                    'Corrected Load Loss: ${correctedLoadLoss.toStringAsFixed(2)} W',
                    style: baseTextStyle,
                  ),
                  pw.Text(
                    'Load Loss @ 75°C: ${loadLoss75.toStringAsFixed(2)} W',
                    style: baseTextStyle,
                  ),
                  pw.Text(
                    'Stray Loss: ${strayLoss.toStringAsFixed(2)} W',
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
    );
*/
    pdf.addPage(
      pw.MultiPage(
        maxPages: 100,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: header,
        footer: footer,
        build: (context) => [
          pw.Stack(
            children: [
              // Watermark
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Opacity(
                    opacity: 0.9,
                    child: pw.Transform.rotate(
                      angle: 0.5,
                      child: pw.Text(
                        isPreview ? 'Draft' : 'GEW',
                        style: pw.TextStyle(
                          fontSize: 100,
                          color: PdfColors.grey,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Your content
              pw.Column(
                children: [
                  _section(
                    '1. Insulation Resistance Test',
                    pw.Table(
                      columnWidths: {
                        0: const pw.FlexColumnWidth(3),
                        1: const pw.FlexColumnWidth(2),
                      },
                      border: pw.TableBorder.all(
                          color: PdfColors.grey600, width: 0.5),
                      children: [
                        pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 4),
                              child:
                                  pw.Text('Temperature', style: baseTextStyle),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 4),
                              child: pw.Text(
                                  '${data['testData']['temperature']}°C',
                                  style: baseTextStyle),
                            ),
                          ],
                        ),
                        pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 4),
                              child: pw.Text('HV-E', style: baseTextStyle),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 4),
                              child: pw.Text(
                                  '${data['testData']['insulationResistance']['hv-e']} MΩ',
                                  style: baseTextStyle),
                            ),
                          ],
                        ),
                        pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 4),
                              child: pw.Text('LV-E', style: baseTextStyle),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 4),
                              child: pw.Text(
                                  '${data['testData']['insulationResistance']['lv-e']} MΩ',
                                  style: baseTextStyle),
                            ),
                          ],
                        ),
                        pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 4),
                              child: pw.Text('HV-LV', style: baseTextStyle),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 4),
                              child: pw.Text(
                                  '${data['testData']['insulationResistance']['hv-lv']} MΩ',
                                  style: baseTextStyle),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _section(
                    '2. Ratio Test',
                    _buildRatioTable(tapStepsSno, tapSteps, hv, lv, ratioData),
                  ),
                  _section(
                    '3. Measurement of Winding Resistance',
                    pw.Row(
                      children: [
                        pw.Expanded(
                            child: _buildResistance(
                                'HV',
                                'in Ohm',
                                data['testData']['windingResistance']['hv'],
                                hvResistance)),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                            child: _buildResistance(
                                'LV',
                                'in Ohm',
                                data['testData']['windingResistance']['lv'],
                                lvResistance)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.Stack(
            children: [
              // Watermark
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Opacity(
                    opacity: 0.9,
                    child: pw.Transform.rotate(
                      angle: 0.5,
                      child: pw.Text(
                        isPreview ? 'Draft' : 'GEW',
                        style: pw.TextStyle(
                          fontSize: 100,
                          color: PdfColors.grey,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Your content
              pw.Column(
                children: [
                  _section('4. Measurement of No-Load Loss and Current',
                      _buildNoLoadTable(noLoad, totalNoLoadLoss)),
                  _section(
                      '5. Measurement of Short Circuit Impedance and Load Losses',
                      _buildLoadTable(
                          loadTest,
                          totalLoadLoss.toStringAsFixed(2),
                          loadLoss75.toStringAsFixed(2),
                          z75.toStringAsFixed(2))),
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
                              '(A) Applied ${getWithstandVoltage(lv)} Between LV winding to HV Winding & Earth and Withstood for 60 sec',
                              style: baseTextStyle,
                            ),
                          ],
                        ),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              '(B) Applied ${getWithstandVoltage(hv)} Between HV winding to LV Winding & Earth and Withstood for 60 sec',
                              style: baseTextStyle,
                            ),
                          ],
                        )
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
          if (isPreview)
            pw.Stack(
              children: [
                // Watermark
                pw.Positioned.fill(
                  child: pw.Center(
                    child: pw.Opacity(
                      opacity: 0.9,
                      child: pw.Transform.rotate(
                        angle: 0.5,
                        child: pw.Text(
                          isPreview ? 'Draft' : 'GEW',
                          style: pw.TextStyle(
                            fontSize: 100,
                            color: PdfColors.grey,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Your content
                pw.Column(
                  children: [
                    _section(
                        'Preview Calculations: Winding Resistance',
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                                'HV Avg Line Resistance: ${hvResistance['avg']!.toStringAsFixed(4)}',
                                style: baseTextStyle),
                            pw.Text(
                                'HV R @ 75°C: ${hvResistance['r75']!.toStringAsFixed(4)}',
                                style: baseTextStyle),
                            pw.Text(
                                'HV Current: ${hvResistance['current']!.toStringAsFixed(2)} A',
                                style: baseTextStyle),
                            pw.Text(
                                'HV I²R Loss: ${hvResistance['loss']!.toStringAsFixed(2)} W',
                                style: baseTextStyle),
                            pw.SizedBox(height: 6),
                            pw.Text(
                                'LV Avg Line Resistance: ${lvResistance['avg']!.toStringAsFixed(4)}',
                                style: baseTextStyle),
                            pw.Text(
                                'LV R @ 75°C: ${lvResistance['r75']!.toStringAsFixed(4)}',
                                style: baseTextStyle),
                            pw.Text(
                                'LV Current: ${lvResistance['current']!.toStringAsFixed(2)} A',
                                style: baseTextStyle),
                            pw.Text(
                                'LV I²R Loss: ${lvResistance['loss']!.toStringAsFixed(2)} W',
                                style: baseTextStyle),
                          ],
                        )),
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
                            'Total Load Loss: ${totalLoadLoss.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Corrected Load Loss: ${correctedLoadLoss.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Load Loss @ 75°C: ${loadLoss75.toStringAsFixed(2)} W',
                            style: baseTextStyle,
                          ),
                          pw.Text(
                            'Stray Loss: ${strayLoss.toStringAsFixed(2)} W',
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

  static Map<String, double> _calcResistanceHV(
    Map res,
    double temp,
    double kva,
    double voltage,
  ) {
    final r1 = double.tryParse(res['1U1V'].toString()) ?? 0;
    final r2 = double.tryParse(res['1V1W'].toString()) ?? 0;
    final r3 = double.tryParse(res['1W1U'].toString()) ?? 0;
    final avg = (r1 + r2 + r3) / 3;
    final r75 = ((235 + 75) / (235 + temp)) * avg * 0.5;
    final current = (kva * 1000) / (voltage * sqrt(3));
    final loss = current * current * r75 * 3;
    return {'avg': avg, 'r75': r75, 'current': current, 'loss': loss};
  }

  static Map<String, double> _calcResistanceLV(
    Map res,
    double temp,
    double kva,
    double voltage,
  ) {
    final r1 = double.tryParse(res['2u2v'].toString()) ?? 0;
    final r2 = double.tryParse(res['2v2w'].toString()) ?? 0;
    final r3 = double.tryParse(res['2w2u'].toString()) ?? 0;
    final avg = (r1 + r2 + r3) / 3;
    final r75 = ((235 + 75) / (235 + temp)) * avg * 0.5;
    final current = (kva * 1000) / (voltage * sqrt(3));
    final loss = current * current * r75 * 3;
    return {'avg': avg, 'r75': r75, 'current': current, 'loss': loss};
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
      String label, String unit, Map res, Map<String, double> calc) {
    final baseTextStyle = pw.TextStyle(
      fontSize: 10,
    );
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$label Winding Resistance $unit', style: baseTextStyle),
          pw.TableHelper.fromTextArray(
            headers: res.keys.toList(),
            data: [res.values.map((e) => e.toString()).toList()],
            border: pw.TableBorder.all(
              color: PdfColors.grey,
              width: 0.75,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColors.white,
            ),
            headerStyle: pw.TextStyle(
                // fontWeight: pw.FontWeight.bold,
                fontSize: 10),
            cellStyle: pw.TextStyle(fontSize: 10),
            cellPadding:
                const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          ),
        ]);
  }

  static pw.Widget _buildRatioTable(
    List<int> sno,
    List<double> tapSteps,
    double hv,
    double lv,
    List ratios,
  ) {
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
        final calcRatio = hv * (1 + tap / 100) / (lv / 1.732);
        final user = ratios[i];
        return [
          sno[i],
          tap.toStringAsFixed(1),
          calcRatio.toStringAsFixed(2),
          user['U'].toString(),
          _deviation(calcRatio, user['U']),
          user['V'].toString(),
          _deviation(calcRatio, user['V']),
          user['W'].toString(),
          _deviation(calcRatio, user['W']),
        ];
      }),
      border: pw.TableBorder.all(
        color: PdfColors.grey,
        width: 0.75,
      ),
      headerStyle: pw.TextStyle(
          // fontWeight: pw.FontWeight.bold,
          fontSize: 10),
      cellStyle: pw.TextStyle(fontSize: 10),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
    );
  }

  static String _deviation(double calc, dynamic user) {
    double u = double.tryParse(user.toString()) ?? 0;
    double dev = ((calc - u) / calc) * 100;
    return dev.toStringAsFixed(2);
  }

  static pw.Widget _buildNoLoadTable(
      Map<String, dynamic> data, String noLoadLoss) {
    return pw.TableHelper.fromTextArray(
      headers: ['Phase', 'Amp', 'Volt', 'Watt'],
      data: [
        ['U', data['U']['amp'], data['U']['volt'], data['U']['watt']],
        ['V', data['V']['amp'], data['V']['volt'], data['V']['watt']],
        ['W', data['W']['amp'], data['W']['volt'], data['W']['watt']],
        ['', '', 'Total Losses:', noLoadLoss],
      ],
      border: pw.TableBorder.all(
        color: PdfColors.grey,
        width: 0.75,
      ),
      headerDecoration: pw.BoxDecoration(
        color: PdfColors.white,
      ),
      headerStyle: pw.TextStyle(
          // fontWeight: pw.FontWeight.bold,
          fontSize: 10),
      cellStyle: pw.TextStyle(fontSize: 10),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
    );
  }

  static pw.Widget _buildLoadTable(Map<String, dynamic> data,
      String totalLosses, String lossat75, String zat75) {
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
      border: pw.TableBorder.all(
        color: PdfColors.grey,
        width: 0.75,
      ),
      headerDecoration: pw.BoxDecoration(
        color: PdfColors.white,
      ),
      headerStyle: pw.TextStyle(
          // fontWeight: pw.FontWeight.bold,
          fontSize: 10),
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
                onChanged: (val) {
                  setState(() {
                    _isPreview = val;
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
              build: (format) =>
                  TestReportPdfGenerator.generatePDF(widget.data, _isPreview),
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
              onPressed: () async {
                try {
                  final bytes = await TestReportPdfGenerator.generatePDF(
                      widget.data, _isPreview); // returns Uint8List

                  final dir = await getDownloadDirectory();
                  final fileName =
                      'TestReport_${widget.data['serialNo'] ?? 'Report'}.pdf';
                  final file = File('${dir.path}/$fileName');
                  await file.writeAsBytes(bytes);
                  await ApiService.saveReport(widget.data);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'PDF saved to ${file.path} and report stored.')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error saving PDF: $e')),
                  );
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
