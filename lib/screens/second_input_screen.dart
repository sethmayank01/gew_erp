import 'package:flutter/material.dart';
import '../models/transformer_losses.dart';
import '../services/api_service.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transformer_vector_group.dart';

class SecondInputScreen extends StatefulWidget {
  final Map<String, dynamic> generalData;
  final int tapCount;
  final bool isEdit;

  const SecondInputScreen({
    Key? key,
    required this.generalData,
    required this.tapCount,
    this.isEdit = false,
  }) : super(key: key);

  @override
  State<SecondInputScreen> createState() => _SecondInputScreenState();
}

class _SecondInputScreenState extends State<SecondInputScreen> {
  final _formKey = GlobalKey<FormState>();

  final _temperatureController = TextEditingController();
  final _hvEController = TextEditingController();
  final _lvEController = TextEditingController();
  final _hvLvController = TextEditingController();
  final _remarkController = TextEditingController();

  late List<Map<String, TextEditingController>> _ratioInputs;
  late List<Map<String, TextEditingController>> _ratioInputsLv2;

  final _hvResControllers = {
    '1U1V': TextEditingController(),
    '1V1W': TextEditingController(),
    '1W1U': TextEditingController(),
  };

  final _lvResControllers = {
    '2u2v': TextEditingController(),
    '2v2w': TextEditingController(),
    '2w2u': TextEditingController(),
  };

  final _lv2ResControllers = {
    '3u3v': TextEditingController(),
    '3v3w': TextEditingController(),
    '3w3u': TextEditingController(),
  };

  final _noLoadTest = {'U': {}, 'V': {}, 'W': {}};
  final _loadTest = {'U': {}, 'V': {}, 'W': {}};
  final Map<String, String> _resistanceUnits = {};
  bool _includeIndividualLoadTests = false;
  final _individualLoadTests = {
    for (final winding in ['lv', 'lv2'])
      winding: {
        for (final phase in ['U', 'V', 'W'])
          phase: {
            for (final field in ['amp', 'volt', 'watt'])
              field: TextEditingController(),
          },
      },
  };
  final _measurementSides = {'lv': 'hv', 'lv2': 'hv'};

  @override
  void initState() {
    super.initState();
    final savedUnits =
        widget.generalData['testData']?['windingResistanceUnits'] as Map?;
    for (final winding in ['hv', 'lv', 'lv2']) {
      _resistanceUnits[winding] =
          savedUnits?[winding]?.toString() ??
          (winding != 'hv' && _hasDualOutput ? 'mOhm' : 'Ohm');
    }
    _ratioInputs = List.generate(
      widget.tapCount,
      (_) => {
        'U': TextEditingController(),
        'V': TextEditingController(),
        'W': TextEditingController(),
      },
    );
    _ratioInputsLv2 = List.generate(
      widget.tapCount,
      (_) => {
        'U': TextEditingController(),
        'V': TextEditingController(),
        'W': TextEditingController(),
      },
    );

    for (var phase in ['U', 'V', 'W']) {
      _noLoadTest[phase]!['amp'] = TextEditingController();
      _noLoadTest[phase]!['volt'] = TextEditingController();
      _noLoadTest[phase]!['watt'] = TextEditingController();

      _loadTest[phase]!['amp'] = TextEditingController();
      _loadTest[phase]!['volt'] = TextEditingController();
      _loadTest[phase]!['watt'] = TextEditingController();
    }

    if (widget.generalData.containsKey('testData')) {
      final test = widget.generalData['testData'];
      _includeIndividualLoadTests =
          _hasDualOutput && test['includeIndividualLoadTests'] == true;
      for (final winding in ['lv', 'lv2']) {
        final saved = test['individualLoadTests']?[winding] as Map?;
        final side = saved?['measurementSide'];
        _measurementSides[winding] = side == winding ? winding : 'hv';
        for (final phase in ['U', 'V', 'W']) {
          for (final field in ['amp', 'volt', 'watt']) {
            _individualLoadTests[winding]![phase]![field]!.text =
                saved?['phases']?[phase]?[field]?.toString() ?? '';
          }
        }
      }
      _temperatureController.text = test['temperature'] ?? '';

      _hvEController.text = test['insulationResistance']['hv-e'] ?? '';
      _lvEController.text = test['insulationResistance']['lv-e'] ?? '';
      _hvLvController.text = test['insulationResistance']['hv-lv'] ?? '';

      final ratios = test['ratios'] as List<dynamic>;
      for (int i = 0; i < _ratioInputs.length && i < ratios.length; i++) {
        _ratioInputs[i]['U']!.text = ratios[i]['U'] ?? '';
        _ratioInputs[i]['V']!.text = ratios[i]['V'] ?? '';
        _ratioInputs[i]['W']!.text = ratios[i]['W'] ?? '';
      }

      final ratiosLv2 = (test['ratiosLv2'] as List?) ?? [];
      for (int i = 0; i < _ratioInputsLv2.length && i < ratiosLv2.length; i++) {
        _ratioInputsLv2[i]['U']!.text = ratiosLv2[i]['U']?.toString() ?? '';
        _ratioInputsLv2[i]['V']!.text = ratiosLv2[i]['V']?.toString() ?? '';
        _ratioInputsLv2[i]['W']!.text = ratiosLv2[i]['W']?.toString() ?? '';
      }

      final wr = test['windingResistance'];
      _hvResControllers['1U1V']!.text = wr['hv']['1U1V'] ?? '';
      _hvResControllers['1V1W']!.text = wr['hv']['1V1W'] ?? '';
      _hvResControllers['1W1U']!.text = wr['hv']['1W1U'] ?? '';
      _lvResControllers['2u2v']!.text = wr['lv']['2u2v'] ?? '';
      _lvResControllers['2v2w']!.text = wr['lv']['2v2w'] ?? '';
      _lvResControllers['2w2u']!.text = wr['lv']['2w2u'] ?? '';
      final lv2Resistance = wr['lv2'] as Map?;
      if (lv2Resistance != null) {
        for (final entry in _lv2ResControllers.entries) {
          entry.value.text = lv2Resistance[entry.key]?.toString() ?? '';
        }
      }

      for (var phase in ['U', 'V', 'W']) {
        _noLoadTest[phase]!['amp'].text =
            test['noLoadTest'][phase]['amp'] ?? '';
        _noLoadTest[phase]!['volt'].text =
            test['noLoadTest'][phase]['volt'] ?? '';
        _noLoadTest[phase]!['watt'].text =
            test['noLoadTest'][phase]['watt'] ?? '';

        _loadTest[phase]!['amp'].text = test['loadTest'][phase]['amp'] ?? '';
        _loadTest[phase]!['volt'].text = test['loadTest'][phase]['volt'] ?? '';
        _loadTest[phase]!['watt'].text = test['loadTest'][phase]['watt'] ?? '';
      }
      // Prefill remark if present

      _remarkController.text = widget.generalData['remark'] ?? '';
    }
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    _hvEController.dispose();
    _lvEController.dispose();
    _hvLvController.dispose();
    _remarkController.dispose();

    for (var map in _ratioInputs) {
      map.forEach((_, ctrl) => ctrl.dispose());
    }
    for (var map in _ratioInputsLv2) {
      map.forEach((_, ctrl) => ctrl.dispose());
    }

    _hvResControllers.values.forEach((c) => c.dispose());
    _lvResControllers.values.forEach((c) => c.dispose());
    _lv2ResControllers.values.forEach((c) => c.dispose());
    for (final winding in _individualLoadTests.values) {
      for (final phase in winding.values) {
        for (final controller in phase.values) {
          controller.dispose();
        }
      }
    }

    for (var phase in ['U', 'V', 'W']) {
      _noLoadTest[phase]!.values.forEach(
        (c) => (c as TextEditingController).dispose(),
      );
      _loadTest[phase]!.values.forEach(
        (c) => (c as TextEditingController).dispose(),
      );
    }

    super.dispose();
  }

  Map<String, String> _extractTestValues(Map map) => {
    'amp': map['amp']!.text,
    'volt': map['volt']!.text,
    'watt': map['watt']!.text,
  };

  TransformerVectorGroup get _vectorConfig => TransformerVectorGroup.fromName(
    widget.generalData['vectorGroup']?.toString(),
  );

  bool get _hasDualOutput => _vectorConfig.hasDualOutput;

  List<Map<String, String>> _extractRatios(
    List<Map<String, TextEditingController>> inputs,
  ) => inputs
      .map(
        (map) => {
          'U': map['U']!.text,
          'V': map['V']!.text,
          'W': map['W']!.text,
        },
      )
      .toList();

  Map<String, dynamic> _buildTestData() => {
    'temperature': _temperatureController.text,
    'insulationResistance': {
      'hv-e': _hvEController.text,
      'lv-e': _lvEController.text,
      'hv-lv': _hvLvController.text,
    },
    'ratios': _extractRatios(_ratioInputs),
    if (_hasDualOutput) 'ratiosLv2': _extractRatios(_ratioInputsLv2),
    'windingResistance': {
      'hv': {
        '1U1V': _hvResControllers['1U1V']!.text,
        '1V1W': _hvResControllers['1V1W']!.text,
        '1W1U': _hvResControllers['1W1U']!.text,
      },
      'lv': {
        '2u2v': _lvResControllers['2u2v']!.text,
        '2v2w': _lvResControllers['2v2w']!.text,
        '2w2u': _lvResControllers['2w2u']!.text,
      },
      if (_hasDualOutput)
        'lv2': {
          '3u3v': _lv2ResControllers['3u3v']!.text,
          '3v3w': _lv2ResControllers['3v3w']!.text,
          '3w3u': _lv2ResControllers['3w3u']!.text,
        },
    },
    'windingResistanceUnits': {
      'hv': _resistanceUnits['hv'],
      'lv': _resistanceUnits['lv'],
      if (_hasDualOutput) 'lv2': _resistanceUnits['lv2'],
    },
    'noLoadTest': {
      'U': _extractTestValues(_noLoadTest['U']!),
      'V': _extractTestValues(_noLoadTest['V']!),
      'W': _extractTestValues(_noLoadTest['W']!),
    },
    'loadTest': {
      'U': _extractTestValues(_loadTest['U']!),
      'V': _extractTestValues(_loadTest['V']!),
      'W': _extractTestValues(_loadTest['W']!),
    },
    if (_hasDualOutput)
      'includeIndividualLoadTests': _includeIndividualLoadTests,
    if (_hasDualOutput && _includeIndividualLoadTests)
      'individualLoadTests': {
        for (final winding in ['lv', 'lv2'])
          winding: {
            'measurementSide': _measurementSides[winding],
            'phases': {
              for (final phase in ['U', 'V', 'W'])
                phase: _extractTestValues(
                  _individualLoadTests[winding]![phase]!,
                ),
            },
          },
      },
  };

  bool _validateIndividualTests(Map<String, dynamic> testData) {
    if (!_hasDualOutput || !_includeIndividualLoadTests) return true;
    try {
      TransformerLosses.fromReport({
        ...widget.generalData,
        'testData': testData,
      });
      return true;
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return false;
    }
  }

  Future<void> _saveReport() async {
    if (!_formKey.currentState!.validate()) return;

    final testData = _buildTestData();
    if (!_validateIndividualTests(testData)) return;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'Unknown';
    final fullData = {
      ...widget.generalData,
      'testData': testData,
      'savedBy': username,
      'remark': _remarkController.text,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await ApiService.saveReport(fullData);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Report saved successfully.')));
  }

  void _submitForm(bool isPreview) async {
    if (!_formKey.currentState!.validate()) return; // Validate form

    final testData = _buildTestData();
    if (!_validateIndividualTests(testData)) return;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'Unknown';
    final fullData = {
      ...widget.generalData,
      'testData': testData,
      'isPreview': isPreview,
      'savedBy': username,
      'remark': _remarkController.text,
    };

    GoRouter.of(context).push('/preview', extra: fullData);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Preview generated. Report not saved yet.')),
    );
  }

  Widget _buildRatioInputs(
    List<Map<String, TextEditingController>> inputs, {
    String? title,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ...List.generate(widget.tapCount, (i) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ratio Tap ${i + 1}'),
              Row(
                children: ['U', 'V', 'W'].map((p) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: TextFormField(
                        controller: inputs[i][p],
                        decoration: InputDecoration(labelText: 'Phase $p'),
                        validator: _numberValidator,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildResistanceInputs(
    Map<String, TextEditingController> map,
    String title,
    String winding,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<String>(
                value: _resistanceUnits[winding],
                decoration: const InputDecoration(labelText: 'Unit'),
                items: ['Ohm', 'mOhm']
                    .map(
                      (unit) =>
                          DropdownMenuItem(value: unit, child: Text(unit)),
                    )
                    .toList(),
                onChanged: (unit) =>
                    setState(() => _resistanceUnits[winding] = unit!),
              ),
            ),
          ],
        ),
        Row(
          children: map.entries.map((e) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: TextFormField(
                  controller: e.value,
                  decoration: InputDecoration(labelText: e.key),
                  validator: _numberValidator,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTestRow(String label, Map phaseMap, {bool individual = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Row(
          children: ['U', 'V', 'W'].map((p) {
            return Expanded(
              child: Column(
                children: [
                  Text('Phase $p'),
                  TextFormField(
                    controller: phaseMap[p]['amp'],
                    decoration: const InputDecoration(labelText: 'Amp'),
                    validator: individual
                        ? _positiveNumberValidator
                        : _numberValidator,
                  ),
                  TextFormField(
                    controller: phaseMap[p]['volt'],
                    decoration: InputDecoration(
                      labelText: individual ? 'Volt (L-L)' : 'Volt',
                    ),
                    validator: individual
                        ? _positiveNumberValidator
                        : _numberValidator,
                  ),
                  TextFormField(
                    controller: phaseMap[p]['watt'],
                    decoration: const InputDecoration(labelText: 'Watt'),
                    validator: individual
                        ? _nonnegativeNumberValidator
                        : _numberValidator,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String? _numberValidator(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    if (double.tryParse(value) == null) return 'Enter valid number';
    return null;
  }

  String? _positiveNumberValidator(String? value) {
    final number = double.tryParse(value ?? '');
    return number == null || !number.isFinite || number <= 0
        ? 'Enter a positive number'
        : null;
  }

  String? _nonnegativeNumberValidator(String? value) {
    final number = double.tryParse(value ?? '');
    return number == null || !number.isFinite || number < 0
        ? 'Enter zero or a positive number'
        : null;
  }

  Widget _buildIndividualTest(int outputIndex) {
    final winding = outputIndex == 0 ? 'lv' : 'lv2';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HV - ${_vectorConfig.outputWindingLabel(outputIndex)} Impedance',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          DropdownButtonFormField<String>(
            value: _measurementSides[winding],
            decoration: const InputDecoration(labelText: 'Measurement Side'),
            items: [
              const DropdownMenuItem(value: 'hv', child: Text('HV')),
              DropdownMenuItem(
                value: winding,
                child: Text(_vectorConfig.outputWindingLabel(outputIndex)),
              ),
            ],
            onChanged: (side) =>
                setState(() => _measurementSides[winding] = side!),
          ),
          _buildTestRow(
            'Load Test',
            _individualLoadTests[winding]!,
            individual: true,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Parameters Input')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _temperatureController,
                  decoration: const InputDecoration(labelText: 'Temperature'),
                  validator: _numberValidator,
                ),
                TextFormField(
                  controller: _hvEController,
                  decoration: const InputDecoration(
                    labelText: 'Insulation Resistance HV-E',
                  ),
                  validator: _numberValidator,
                ),
                TextFormField(
                  controller: _lvEController,
                  decoration: const InputDecoration(
                    labelText: 'Insulation Resistance LV-E',
                  ),
                  validator: _numberValidator,
                ),
                TextFormField(
                  controller: _hvLvController,
                  decoration: const InputDecoration(
                    labelText: 'Insulation Resistance HV-LV',
                  ),
                  validator: _numberValidator,
                ),
                const SizedBox(height: 16),
                _buildRatioInputs(
                  _ratioInputs,
                  title: _vectorConfig.outputRatioLabel(0),
                ),
                if (_hasDualOutput) ...[
                  const SizedBox(height: 12),
                  _buildRatioInputs(
                    _ratioInputsLv2,
                    title: _vectorConfig.outputRatioLabel(1),
                  ),
                ],
                const SizedBox(height: 16),
                _buildResistanceInputs(
                  _hvResControllers,
                  'HV Winding Resistance',
                  'hv',
                ),
                _buildResistanceInputs(
                  _lvResControllers,
                  '${_vectorConfig.outputWindingLabel(0)} Resistance',
                  'lv',
                ),
                if (_hasDualOutput)
                  _buildResistanceInputs(
                    _lv2ResControllers,
                    '${_vectorConfig.outputWindingLabel(1)} Resistance',
                    'lv2',
                  ),
                const SizedBox(height: 16),
                _buildTestRow('No Load Test', _noLoadTest),
                const SizedBox(height: 16),
                _buildTestRow('Load Test', _loadTest),
                if (_hasDualOutput) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Include Individual Winding Impedance Tests',
                    ),
                    value: _includeIndividualLoadTests,
                    onChanged: (value) =>
                        setState(() => _includeIndividualLoadTests = value!),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_includeIndividualLoadTests) ...[
                    _buildIndividualTest(0),
                    _buildIndividualTest(1),
                  ],
                ],
                const SizedBox(height: 24),
                TextFormField(
                  controller: _remarkController,
                  decoration: const InputDecoration(
                    labelText: 'Remark',
                    hintText: 'Enter remark (optional)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () => _submitForm(false),
                        child: const Text('Preview Report'),
                      ),
                      ElevatedButton(
                        onPressed: _saveReport,
                        child: const Text('Save Report'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
