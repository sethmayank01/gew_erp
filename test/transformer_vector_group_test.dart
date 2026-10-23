import 'package:flutter_test/flutter_test.dart';
import 'package:gew_erp/models/transformer_vector_group.dart';

void main() {
  test('parses Delta/Star groups without a fixed-name lookup', () {
    for (final entry in {
      'Dyn11d0': [false, true, false],
      'Yy0': [true, true],
      'Dd6': [false, false],
      'YNyn0d11': [true, true, false],
      ' dyn1d5 ': [false, true, false],
    }.entries) {
      final config = TransformerVectorGroup.fromName(entry.key);
      expect(config.hvStar, entry.value.first);
      expect(config.outputStar, entry.value.sublist(1));
    }
  });

  test(
    'malformed and unsupported groups never silently calculate as Dyn11',
    () {
      for (final name in ['unknown', 'D', 'Dyn12', 'Ddn0', 'Dz0', 'Dd0d0d0']) {
        expect(
          () => TransformerVectorGroup.fromName(name),
          throwsFormatException,
        );
      }
    },
  );

  test('mixed outputs use connection names without numbering', () {
    final config = TransformerVectorGroup.fromName('Dd0yn11');
    expect(config.outputRatioLabel(0), 'Delta Output Ratio');
    expect(config.outputRatioLabel(1), 'Star Output Ratio');
    expect(config.outputWindingLabel(0), 'Delta Winding');
    expect(config.outputWindingLabel(1), 'Star Winding');
  });

  test('matching output connections are numbered', () {
    final star = TransformerVectorGroup.fromName('Dyn11yn11');
    expect(star.outputWindingLabel(0), 'Star Winding 1');
    expect(star.outputWindingLabel(1), 'Star Winding 2');
    expect(star.outputRatioLabel(0), 'Star 1 Output Ratio');
    expect(star.outputRatioLabel(1), 'Star 2 Output Ratio');
    final delta = TransformerVectorGroup.fromName('YNd11d11');
    expect(delta.hvStar, isTrue);
    expect(delta.outputStar, [false, false]);
    expect(delta.outputWindingLabel(0), 'Delta Winding 1');
    expect(delta.outputWindingLabel(1), 'Delta Winding 2');
    expect(delta.outputRatioLabel(0), 'Delta 1 Output Ratio');
    expect(delta.outputRatioLabel(1), 'Delta 2 Output Ratio');
    expect(TransformerVectorGroup.supportedNames, contains('YNd11d11'));
  });

  test('single-output vector groups expose one winding', () {
    final dyn11 = TransformerVectorGroup.fromName('Dyn11');
    final ynd11 = TransformerVectorGroup.fromName('YNd11');

    expect(dyn11.hvStar, isFalse);
    expect(dyn11.outputStar, [true]);
    expect(dyn11.hasDualOutput, isFalse);
    expect(ynd11.hvStar, isTrue);
    expect(ynd11.outputStar, [false]);
  });

  test('dual-output vector groups expose both winding connections', () {
    final dd0yn11 = TransformerVectorGroup.fromName('Dd0yn11');
    final dyn11yn11 = TransformerVectorGroup.fromName('Dyn11yn11');
    final yn11d0d0 = TransformerVectorGroup.fromName('YN11d0d0');

    expect(dd0yn11.outputStar, [false, true]);
    expect(dyn11yn11.outputStar, [true, true]);
    expect(yn11d0d0.hvStar, isTrue);
    expect(yn11d0d0.outputStar, [false, false]);
    expect(yn11d0d0.hasDualOutput, isTrue);
  });

  test('ratio calculation uses each output winding connection', () {
    final config = TransformerVectorGroup.fromName('Dd0yn11');

    expect(
      config.calculatedRatio(
        hvLineVoltage: 11000,
        outputLineVoltage: 433,
        tapPercent: 0,
        outputIndex: 0,
      ),
      closeTo(25.404, 0.001),
    );
    expect(
      config.calculatedRatio(
        hvLineVoltage: 11000,
        outputLineVoltage: 433,
        tapPercent: 0,
        outputIndex: 1,
      ),
      closeTo(44.001, 0.001),
    );
  });
}
