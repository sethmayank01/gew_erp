import 'package:flutter_test/flutter_test.dart';
import 'dart:math';
import 'package:gew_erp/models/transformer_losses.dart';

Map<String, dynamic> report() => {
  'kva': '8600',
  'hvVoltage': '33000',
  'lvVoltage': '710',
  'lv2Voltage': '710',
  'vectorGroup': 'Dd0yn11',
  'material': 'Copper',
  'testData': {
    'temperature': '32',
    'windingResistance': {
      'hv': {'1U1V': '0.691', '1V1W': '0.688', '1W1U': '0.688'},
      'lv': {'2u2v': '0.511', '2v2w': '0.495', '2w2u': '0.517'},
      'lv2': {'3u3v': '0.578', '3v3w': '0.566', '3w3u': '0.588'},
    },
    'loadTest': {
      'U': {'amp': '152.2', 'volt': '1375.87', 'watt': '22710'},
      'V': {'amp': '149.7', 'volt': '1382.2', 'watt': '19550'},
      'W': {'amp': '151.6', 'volt': '1392.03', 'watt': '20760'},
    },
  },
};

void main() {
  for (final group in ['Dyn11', 'Dd0', 'YNd11', 'Dd0yn11', 'Dyn11yn11']) {
    for (final fraction in [0.5, 1.0, 1.25]) {
      test('$group corrects load loss at ${fraction * 100}% rated current', () {
        final data = report()..['vectorGroup'] = group;
        if (['Dyn11', 'Dd0', 'YNd11'].contains(group)) {
          data['testData']['windingResistanceUnits'] = {
            'hv': 'Ohm', 'lv': 'mOhm',
          };
          final lv = data['testData']['windingResistance']['lv'] as Map;
          lv.updateAll((key, value) => (double.parse(value) / 10).toString());
        }
        final ratedCurrent = 8600000 / (33000 * sqrt(3));
        final load = data['testData']['loadTest'] as Map;
        for (final entry in {'U': 0.98, 'V': 1.0, 'W': 1.02}.entries) {
          load[entry.key] = {
            'amp': (ratedCurrent * fraction * entry.value).toString(),
            'volt': (1650 * fraction).toString(),
            'watt': (20000 * fraction * fraction).toString(),
          };
        }
        final calc = TransformerLosses.fromReport(data).totals;
        expect(calc['averageCurrent'], closeTo(ratedCurrent * fraction, 1e-8));
        expect(calc['measuredLoss'], closeTo(60000 * fraction * fraction, 1e-8));
        expect(calc['correctedLoss'], closeTo(60000, 1e-8));
        expect(calc['strayAmbient'], closeTo(60000 - calc['copperAmbient']!, 1e-8));
        expect(
          calc['load75'],
          closeTo(calc['copper75']! + (60000 - calc['copperAmbient']!) * 267 / 310, 1e-8),
        );
        expect(calc['rAmbient'], closeTo(60000 / 8600000 * 100, 1e-10));
        expect(calc['zAmbient'], closeTo(5, 1e-10));
      });
    }
  }
  for (final group in ['Dyn11', 'Dd0', 'YNd11']) {
    test('$group single output uses full kVA and its connection', () {
      final data = report()..['vectorGroup'] = group;
      data.remove('lv2Voltage');
      data['testData']['windingResistance'].remove('lv2');
      final readings = data['testData']['windingResistance']['lv'] as Map;
      readings.updateAll(
        (key, value) => (double.parse(value) / 10000).toString(),
      );
      final losses = TransformerLosses.fromReport(data);
      final hvStar = group == 'YNd11';
      final lvStar = group == 'Dyn11';
      final factor = 310 / 267;
      expect(losses.windings.keys, ['hv', 'lv']);
      expect(losses.windings['hv']!['kva'], 8600);
      expect(losses.windings['lv']!['kva'], 8600);
      expect(
        losses.windings['lv']!['current'],
        closeTo(8600000 / (710 * sqrt(3)), 1e-8),
      );
      expect(
        losses.windings['hv']!['r75'],
        closeTo(.689 * (hvStar ? .5 : 1.5) * factor, 1e-10),
      );
      expect(
        losses.windings['lv']!['r75'],
        closeTo(
          (.511 + .495 + .517) / 30000 * (lvStar ? .5 : 1.5) * factor,
          1e-12,
        ),
      );
      for (final key in ['hv', 'lv']) {
        final winding = losses.windings[key]!;
        expect(
          winding['loss'],
          closeTo(3 * pow(winding['phaseCurrent']!, 2) * winding['r75']!, 1e-8),
        );
      }
      expect(losses.totals['zAmbient'], closeTo(4.172450703, 1e-8));
      expect(losses.totals['z75']!.isFinite, isTrue);
    });
  }

  for (final group in ['Dyn11d0', 'Dyn11yn11', 'YNd11d11']) {
    test('$group dual output uses half kVA per LV and sums all losses', () {
      final losses = TransformerLosses.fromReport(
        report()..['vectorGroup'] = group,
      );
      expect(losses.windings['hv']!['kva'], 8600);
      expect(losses.windings['lv']!['kva'], 4300);
      expect(losses.windings['lv2']!['kva'], 4300);
      expect(
        losses.totals['copper75'],
        closeTo(
          losses.windings.values.fold(
            0.0,
            (sum, winding) => sum + winding['loss']!,
          ),
          1e-8,
        ),
      );
      expect(losses.totals['zAmbient'], closeTo(4.172450703, 1e-8));
    });
  }

  test(
    '34C reference table uses delta and star phase resistances correctly',
    () {
      final data = report();
      data['testData']['temperature'] = '34';
      data['testData']['windingResistance']['hv'] = {
        '1U1V': '0.6907',
        '1V1W': '0.6879',
        '1W1U': '0.6884',
      };
      final losses = TransformerLosses.fromReport(data);
      expect(losses.windings['hv']!['r75'], closeTo(1.1910223048, 1e-10));
      expect(losses.windings['lv']!['r75'], closeTo(.000877565056, 1e-12));
      expect(losses.windings['lv2']!['r75'], closeTo(.000332664188, 1e-12));
      expect(losses.windings['hv']!['loss'], closeTo(26962.965921, 1e-6));
      expect(losses.windings['lv']!['loss'], closeTo(10729.470265, 1e-6));
      expect(losses.windings['lv2']!['loss'], closeTo(12201.866381, 1e-6));
      expect(losses.totals['load75'], closeTo(66500.805356, 1e-6));
      expect(losses.totals['z75'], closeTo(4.180939945, 1e-8));
    },
  );

  test('impedance preserves the original phase-to-phase voltage formula', () {
    final losses = TransformerLosses.fromReport(report());
    final currentRatio =
        losses.windings['hv']!['current']! / ((152.2 + 149.7 + 151.6) / 3);
    final originalZ =
        currentRatio * ((1375.87 + 1382.2 + 1392.03) / 3) / 33000 * 100;
    expect(losses.totals['zAmbient'], closeTo(originalZ, 1e-10));
  });

  test(
    'TRFD0723 uses full HV rating, half LV ratings, and both LV copper losses',
    () {
      final losses = TransformerLosses.fromReport(report());
      expect(losses.windings['hv']!['kva'], 8600);
      expect(losses.windings['lv']!['kva'], 4300);
      expect(losses.windings['lv2']!['kva'], 4300);
      expect(losses.windings['hv']!['current'], closeTo(150.460979, 1e-6));
      expect(losses.windings['lv']!['current'], closeTo(3496.628391, 1e-6));
      expect(
        losses.windings['hv']!['ambientLoss'],
        closeTo(23396.896235, 1e-6),
      );
      expect(losses.windings['lv']!['ambientLoss'], closeTo(9310.411294, 1e-6));
      expect(
        losses.windings['lv2']!['ambientLoss'],
        closeTo(10588.071150, 1e-6),
      );
      expect(losses.windings['hv']!['loss'], closeTo(27164.935704, .00001));
      expect(losses.windings['lv']!['loss'], closeTo(10809.840828, .00001));
      expect(losses.windings['lv2']!['loss'], closeTo(12293.266129, .00001));
      expect(losses.totals['measuredLoss'], 63020);
      expect(losses.totals['correctedLoss'], closeTo(62432.984123, 1e-6));
      expect(losses.totals['copperAmbient'], closeTo(43295.378679, 1e-6));
      expect(losses.totals['strayAmbient'], closeTo(19137.605444, 1e-6));
      expect(losses.totals['load75'], closeTo(66751.077027, 1e-6));
      expect(losses.totals['zAmbient'], closeTo(4.172450703, 1e-8));
      expect(losses.totals['z75'], closeTo(4.181479153, 1e-8));
    },
  );

  test(
    'explicit ohm readings produce the same result as milliohm readings',
    () {
      final data = report();
      data['testData']['windingResistanceUnits'] = {
        'hv': 'Ohm',
        'lv': 'Ohm',
        'lv2': 'Ohm',
      };
      for (final key in ['lv', 'lv2']) {
        final readings = data['testData']['windingResistance'][key] as Map;
        readings.updateAll(
          (key, value) => (double.parse(value) / 1000).toString(),
        );
      }
      expect(
        TransformerLosses.fromReport(data).totals['load75'],
        closeTo(TransformerLosses.fromReport(report()).totals['load75']!, 1e-8),
      );
    },
  );

  test(
    'single-output legacy reports keep full output rating and ohm units',
    () {
      final data = report()..['vectorGroup'] = 'Dyn11';
      final readings = data['testData']['windingResistance']['lv'] as Map;
      readings.updateAll(
        (key, value) => (double.parse(value) / 10000).toString(),
      );
      final losses = TransformerLosses.fromReport(data);
      expect(losses.windings.keys, ['hv', 'lv']);
      expect(losses.windings['lv']!['kva'], 8600);
      expect(TransformerLosses.resistanceUnit(data, 'lv'), 'Ohm');
    },
  );

  test('wrong resistance units cannot generate negative stray loss', () {
    final data = report();
    data['testData']['windingResistanceUnits'] = {
      'hv': 'Ohm',
      'lv': 'Ohm',
      'lv2': 'Ohm',
    };
    expect(() => TransformerLosses.fromReport(data), throwsFormatException);
  });

  test('aluminum and aluminium use the same temperature correction', () {
    final american = TransformerLosses.fromReport(
      report()..['material'] = 'Aluminum',
    );
    final british = TransformerLosses.fromReport(
      report()..['material'] = 'Aluminium',
    );
    expect(american.totals['load75'], british.totals['load75']);
    expect(
      american.windings['hv']!['loss'],
      closeTo(american.windings['hv']!['ambientLoss']! * 300 / 257, 1e-8),
    );
  });
}
