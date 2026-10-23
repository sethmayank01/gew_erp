import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/models/transformer_losses.dart';
import 'transformer_losses_test.dart' show report;

Map<String, dynamic> individualReport({bool lvSide = false}) {
  final data = report();
  final voltage = lvSide ? 710.0 : 33000.0;
  final test = data['testData'] as Map;
  test['includeIndividualLoadTests'] = true;
  test['individualLoadTests'] = {
    for (final key in ['lv', 'lv2'])
      key: {
        'measurementSide': lvSide ? key : 'hv',
        'phases': {
          for (final phase in ['U', 'V', 'W'])
            phase: {
              'amp': (4300000 / (sqrt(3) * voltage)).toString(),
              'volt': (voltage * .05).toString(),
              'watt': '10000',
            },
        },
      },
  };
  return data;
}

void main() {
  for (final lvSide in [false, true]) {
    for (final fraction in [0.5, 1.0, 1.25]) {
      test('individual ${lvSide ? 'LV' : 'HV'} tests correct ${fraction * 100}% current', () {
        final data = individualReport(lvSide: lvSide);
        final reference = TransformerLosses.fromReport(data);
        for (final key in ['lv', 'lv2']) {
          final phases = data['testData']['individualLoadTests'][key]['phases'] as Map;
          for (final phase in ['U', 'V', 'W']) {
            final row = phases[phase] as Map;
            row['amp'] = (double.parse(row['amp']) * fraction).toString();
            row['volt'] = (double.parse(row['volt']) * fraction).toString();
            row['watt'] = (10000 * fraction * fraction).toString();
          }
        }
        final losses = TransformerLosses.fromReport(data);
        expect(losses.totals, reference.totals);
        for (final key in ['lv', 'lv2']) {
          final calc = losses.individualTests[key]!;
          expect(calc['measuredLoss'], closeTo(30000 * fraction * fraction, 1e-8));
          expect(calc['correctedLoss'], closeTo(30000, 1e-8));
          for (final field in ['load75', 'strayAmbient', 'rAmbient', 'zAmbient', 'z75']) {
            expect(calc[field], closeTo(reference.individualTests[key]![field]!, 1e-8));
          }
        }
      });
    }
  }
  test('individual tests use half HV current and only the tested LV loss', () {
    final losses = TransformerLosses.fromReport(individualReport());
    for (final key in ['lv', 'lv2']) {
      final calc = losses.individualTests[key]!;
      expect(calc['kva'], 4300);
      expect(
        calc['ratedCurrent'],
        closeTo(losses.windings['hv']!['current']! / 2, 1e-10),
      );
      expect(
        calc['copperAmbient'],
        closeTo(
          losses.windings['hv']!['ambientLoss']! / 4 +
              losses.windings[key]!['ambientLoss']!,
          1e-8,
        ),
      );
      expect(
        calc['copper75'],
        closeTo(
          losses.windings['hv']!['loss']! / 4 + losses.windings[key]!['loss']!,
          1e-8,
        ),
      );
      expect(calc['correctedLoss'], closeTo(30000, 1e-8));
      expect(calc['rAmbient'], closeTo(30000 / 4300000 * 100, 1e-10));
      expect(calc['zAmbient'], closeTo(5, 1e-10));
      final expected75 =
          calc['copper75']! + (30000 - calc['copperAmbient']!) * 267 / 310;
      expect(calc['load75'], closeTo(expected75, 1e-8));
      expect(
        calc['z75'],
        closeTo(
          sqrt(pow(calc['xAmbient']!, 2) + pow(expected75 / 4300000 * 100, 2)),
          1e-10,
        ),
      );
    }
    expect(losses.totals, TransformerLosses.fromReport(report()).totals);
  });

  test(
    'HV-side and LV-side phase-to-phase readings give equivalent results',
    () {
      final hv = TransformerLosses.fromReport(individualReport());
      final lv = TransformerLosses.fromReport(individualReport(lvSide: true));
      for (final key in ['lv', 'lv2']) {
        for (final field in ['correctedLoss', 'load75', 'zAmbient', 'z75']) {
          expect(
            lv.individualTests[key]![field],
            closeTo(hv.individualTests[key]![field]!, 1e-8),
          );
        }
        expect(
          lv.individualTests[key]!['ratedCurrent'],
          lv.windings[key]!['current'],
        );
      }
    },
  );

  test('unchecked option ignores stale or incomplete individual data', () {
    final data = individualReport();
    data['testData']['includeIndividualLoadTests'] = false;
    data['testData']['individualLoadTests'] = {};
    final losses = TransformerLosses.fromReport(data);
    expect(losses.individualTests, isEmpty);
    expect(losses.totals, TransformerLosses.fromReport(report()).totals);
    expect(TransformerLosses.fromReport(report()).individualTests, isEmpty);
  });

  test('saved individual tests survive JSON serialization', () {
    final data = individualReport(lvSide: true);
    final restored = jsonDecode(jsonEncode(data)) as Map;
    expect(
      TransformerLosses.fromReport(restored).individualTests,
      TransformerLosses.fromReport(data).individualTests,
    );
  });

  test(
    'missing readings, wrong sides, and invalid measurements are rejected',
    () {
      final missing = individualReport();
      missing['testData']['individualLoadTests'].remove('lv2');
      expect(
        () => TransformerLosses.fromReport(missing),
        throwsFormatException,
      );
      final wrongSide = individualReport();
      wrongSide['testData']['individualLoadTests']['lv']['measurementSide'] =
          'lv2';
      expect(
        () => TransformerLosses.fromReport(wrongSide),
        throwsFormatException,
      );
      for (final field in ['amp', 'volt', 'watt']) {
        final data = individualReport();
        data['testData']['individualLoadTests']['lv']['phases']['U'][field] =
            '-1';
        expect(() => TransformerLosses.fromReport(data), throwsFormatException);
      }
      final inconsistent = individualReport();
      for (final phase in ['U', 'V', 'W']) {
        inconsistent['testData']['individualLoadTests']['lv']['phases'][phase]['watt'] =
            '1';
      }
      expect(
        () => TransformerLosses.fromReport(inconsistent),
        throwsFormatException,
      );
    },
  );
}
