import 'dart:math';

class TransformerVectorGroup {
  final bool hvStar;
  final List<bool> outputStar;

  const TransformerVectorGroup({
    required this.hvStar,
    required this.outputStar,
  });

  static const supportedNames = [
    'Dyn11',
    'YNd11',
    'Dd0',
    'YNd1',
    'Dd0yn11',
    'Dyn11d0',
    'Dyn11yn11',
    'YNd11d11',
    'YN11d0d0',
  ];

  bool get hasDualOutput => outputStar.length > 1;

  bool outputIsStar(int index) => outputStar[index];

  String outputLabel(int index) {
    final connection = outputIsStar(index) ? 'Star' : 'Delta';
    return _hasRepeatedConnection(index)
        ? '$connection ${index + 1}'
        : connection;
  }

  String outputWindingLabel(int index) {
    final connection = outputIsStar(index) ? 'Star' : 'Delta';
    return _hasRepeatedConnection(index)
        ? '$connection Winding ${index + 1}'
        : '$connection Winding';
  }

  String outputRatioLabel(int index) => '${outputLabel(index)} Output Ratio';

  bool _hasRepeatedConnection(int index) =>
      outputStar.where((star) => star == outputIsStar(index)).length > 1;

  double calculatedRatio({
    required double hvLineVoltage,
    required double outputLineVoltage,
    required double tapPercent,
    required int outputIndex,
  }) {
    final hvPhaseVoltage = hvStar ? hvLineVoltage / sqrt(3) : hvLineVoltage;
    final outputPhaseVoltage = outputIsStar(outputIndex)
        ? outputLineVoltage / sqrt(3)
        : outputLineVoltage;

    if (outputPhaseVoltage == 0) return 0;
    return hvPhaseVoltage * (1 + tapPercent / 100) / outputPhaseVoltage;
  }

  static TransformerVectorGroup fromName(String? vectorGroup) {
    var name = vectorGroup?.trim().toLowerCase() ?? '';
    if (name.isEmpty) name = 'dyn11';
    // Retain the notation used by existing saved two-delta reports.
    if (name == 'yn11d0d0') name = 'ynd0d0';
    final primary = RegExp(r'^(d|yn?)').firstMatch(name);
    if (primary == null) {
      throw const FormatException(
        'Only Delta/Star vector groups are supported.',
      );
    }
    var offset = primary.end;
    final outputs = <bool>[];
    final outputPattern = RegExp(r'(d|yn?)(1[01]|[0-9])');
    while (offset < name.length) {
      final output = outputPattern.matchAsPrefix(name, offset);
      if (output == null || outputs.length == 2) {
        throw const FormatException('Invalid single/dual-output vector group.');
      }
      outputs.add(output.group(1)!.startsWith('y'));
      offset = output.end;
    }
    if (outputs.isEmpty) {
      throw const FormatException(
        'Vector group must include an output winding.',
      );
    }
    return TransformerVectorGroup(
      hvStar: primary.group(1)!.startsWith('y'),
      outputStar: List.unmodifiable(outputs),
    );
  }
}
