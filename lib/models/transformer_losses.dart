import 'dart:math';
import 'transformer_vector_group.dart';

class TransformerLosses {
  final Map<String, Map<String, double>> windings;
  final Map<String, double> totals;
  final Map<String, Map<String, double>> individualTests;

  const TransformerLosses(
    this.windings,
    this.totals, [
    this.individualTests = const {},
  ]);

  static String resistanceUnit(Map data, String winding) {
    final explicit = data['testData']?['windingResistanceUnits']?[winding];
    if (explicit != null) return explicit.toString();
    // Legacy dual-output reports use HV ohms and LV milliohms.
    final dual = TransformerVectorGroup.fromName(
      data['vectorGroup']?.toString(),
    ).hasDualOutput;
    return winding != 'hv' && dual ? 'mOhm' : 'Ohm';
  }

  static double _number(dynamic value, String label, {bool positive = false}) {
    final number = double.tryParse(value?.toString() ?? '');
    if (number == null ||
        !number.isFinite ||
        (positive ? number <= 0 : number < 0)) {
      throw FormatException('Invalid $label');
    }
    return number;
  }

  factory TransformerLosses.fromReport(Map data) {
    final test = data['testData'] as Map;
    final config = TransformerVectorGroup.fromName(
      data['vectorGroup']?.toString(),
    );
    final kva = _number(data['kva'], 'KVA', positive: true);
    final temperature = double.tryParse(test['temperature']?.toString() ?? '');
    final material = data['material']?.toString().trim().toLowerCase();
    final constant = material == 'aluminum' || material == 'aluminium'
        ? 225.0
        : 235.0;
    if (temperature == null ||
        !temperature.isFinite ||
        temperature <= -constant) {
      throw const FormatException('Invalid test temperature');
    }
    final temperatureFactor = (constant + 75) / (constant + temperature);
    final windings = <String, Map<String, double>>{};

    void addWinding(
      String key,
      List<String> terminals,
      double rating,
      dynamic voltage,
      bool isStar,
    ) {
      final readings = test['windingResistance']?[key] as Map?;
      if (readings == null)
        throw FormatException('Missing $key winding resistance');
      final unit = resistanceUnit(data, key);
      if (unit != 'Ohm' && unit != 'mOhm')
        throw FormatException('Invalid $key resistance unit');
      final scale = unit == 'mOhm' ? 0.001 : 1.0;
      final average =
          terminals
              .map(
                (t) =>
                    _number(readings[t], '$key resistance $t', positive: true),
              )
              .reduce((a, b) => a + b) /
          3 *
          scale;
      final current =
          rating *
          1000 /
          (_number(voltage, '$key voltage', positive: true) * sqrt(3));
      final phaseResistance = average * (isStar ? 0.5 : 1.5);
      final phaseCurrent = isStar ? current : current / sqrt(3);
      final ambient = 3 * phaseCurrent * phaseCurrent * phaseResistance;
      windings[key] = {
        'avg': average,
        'r75': phaseResistance * temperatureFactor,
        'current': current,
        'phaseCurrent': phaseCurrent,
        'ambientLoss': ambient,
        'loss': ambient * temperatureFactor,
        'kva': rating,
      };
    }

    addWinding(
      'hv',
      ['1U1V', '1V1W', '1W1U'],
      kva,
      data['hvVoltage'],
      config.hvStar,
    );
    final outputRating = kva / config.outputStar.length;
    addWinding(
      'lv',
      ['2u2v', '2v2w', '2w2u'],
      outputRating,
      data['lvVoltage'],
      config.outputIsStar(0),
    );
    if (config.hasDualOutput) {
      addWinding(
        'lv2',
        ['3u3v', '3v3w', '3w3u'],
        outputRating,
        data['lv2Voltage'],
        config.outputIsStar(1),
      );
    }
    final copperAmbient = windings.values.fold(
      0.0,
      (sum, w) => sum + w['ambientLoss']!,
    );
    final copper75 = windings.values.fold(0.0, (sum, w) => sum + w['loss']!);
    final totals = _calculateLoadTest(
      load: test['loadTest'] as Map,
      rating: kva,
      ratedCurrent: windings['hv']!['current']!,
      voltage: _number(data['hvVoltage'], 'HV voltage', positive: true),
      copperAmbient: copperAmbient,
      copper75: copper75,
      temperatureFactor: temperatureFactor,
    );
    final individualTests = <String, Map<String, double>>{};
    if (config.hasDualOutput && test['includeIndividualLoadTests'] == true) {
      final individual = test['individualLoadTests'] as Map?;
      for (final key in ['lv', 'lv2']) {
        final input = individual?[key] as Map?;
        if (input == null || input['phases'] is! Map) {
          throw FormatException('Missing $key individual load test');
        }
        final side = input['measurementSide'];
        if (side != 'hv' && side != key) {
          throw FormatException('Invalid $key measurement side');
        }
        final hvFraction = outputRating / kva;
        // Only this HV/LV pair carries current; the other output is open.
        final pairCopperAmbient =
            windings['hv']!['ambientLoss']! * hvFraction * hvFraction +
            windings[key]!['ambientLoss']!;
        final pairCopper75 =
            windings['hv']!['loss']! * hvFraction * hvFraction +
            windings[key]!['loss']!;
        final ratedCurrent = side == 'hv'
            ? windings['hv']!['current']! * hvFraction
            : windings[key]!['current']!;
        final voltage = side == 'hv'
            ? data['hvVoltage']
            : data[key == 'lv' ? 'lvVoltage' : 'lv2Voltage'];
        try {
          individualTests[key] = _calculateLoadTest(
            load: input['phases'] as Map,
            rating: outputRating,
            ratedCurrent: ratedCurrent,
            voltage: _number(
              voltage,
              '$key measurement voltage',
              positive: true,
            ),
            copperAmbient: pairCopperAmbient,
            copper75: pairCopper75,
            temperatureFactor: temperatureFactor,
          );
        } on FormatException catch (error) {
          throw FormatException('$key individual test: ${error.message}');
        }
      }
    }
    return TransformerLosses(windings, totals, individualTests);
  }

  static Map<String, double> _calculateLoadTest({
    required Map load,
    required double rating,
    required double ratedCurrent,
    required double voltage,
    required double copperAmbient,
    required double copper75,
    required double temperatureFactor,
  }) {
    double sum(String key) => ['U', 'V', 'W']
        .map(
          (phase) => _number(
            load[phase]?[key],
            'load test $phase $key',
            positive: key != 'watt',
          ),
        )
        .reduce((a, b) => a + b);
    final measuredLoss = sum('watt');
    final averageCurrent = sum('amp') / 3;
    final averageVoltage = sum('volt') / 3;
    final currentRatio = ratedCurrent / averageCurrent;
    final correctedLoss = measuredLoss * currentRatio * currentRatio;
    final strayAmbient = correctedLoss - copperAmbient;
    if (strayAmbient < 0) {
      throw const FormatException(
        'Copper loss exceeds measured load loss. Check resistance units and test readings.',
      );
    }
    final stray75 = strayAmbient / temperatureFactor;
    final load75 = copper75 + stray75;
    // Preserve the original line-to-line voltage input convention.
    final averagePhaseVoltage = averageVoltage / sqrt(3);
    final correctedPhaseVoltage = currentRatio * averagePhaseVoltage;
    final zAmbient = correctedPhaseVoltage * sqrt(3) / voltage * 100;
    final rAmbient = correctedLoss / (rating * 1000) * 100;
    final reactanceSquared = zAmbient * zAmbient - rAmbient * rAmbient;
    if (reactanceSquared < 0)
      throw const FormatException(
        'Load loss is inconsistent with measured impedance.',
      );
    final xAmbient = sqrt(reactanceSquared);
    final r75 = load75 / (rating * 1000) * 100;
    return {
      'kva': rating,
      'ratedCurrent': ratedCurrent,
      'averageCurrent': averageCurrent,
      'averageVoltage': averageVoltage,
      'correctedVoltage': averageVoltage * currentRatio,
      'measuredLoss': measuredLoss,
      'correctedLoss': correctedLoss,
      'copperAmbient': copperAmbient,
      'copper75': copper75,
      'strayAmbient': strayAmbient,
      'stray75': stray75,
      'load75': load75,
      'zAmbient': zAmbient,
      'rAmbient': rAmbient,
      'xAmbient': xAmbient,
      'r75': r75,
      'z75': sqrt(xAmbient * xAmbient + r75 * r75),
    };
  }
}
