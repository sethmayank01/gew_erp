import 'package:flutter/material.dart';
import 'test_report_pdf_generator.dart';
import '../services/api_service.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  late List<Map<String, TextEditingController>> _ratioInputs;

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

  final _noLoadTest = {'U': {}, 'V': {}, 'W': {}};
  final _loadTest = {'U': {}, 'V': {}, 'W': {}};

  @override
  void initState() {
    super.initState();
    _ratioInputs = List.generate(
        widget.tapCount,
        (_) => {
              'U': TextEditingController(),
              'V': TextEditingController(),
              'W': TextEditingController(),
            });

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

      final wr = test['windingResistance'];
      _hvResControllers['1U1V']!.text = wr['hv']['1U1V'] ?? '';
      _hvResControllers['1V1W']!.text = wr['hv']['1V1W'] ?? '';
      _hvResControllers['1W1U']!.text = wr['hv']['1W1U'] ?? '';
      _lvResControllers['2u2v']!.text = wr['lv']['2u2v'] ?? '';
      _lvResControllers['2v2w']!.text = wr['lv']['2v2w'] ?? '';
      _lvResControllers['2w2u']!.text = wr['lv']['2w2u'] ?? '';

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
    }
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    _hvEController.dispose();
    _lvEController.dispose();
    _hvLvController.dispose();

    for (var map in _ratioInputs) {
      map.forEach((_, ctrl) => ctrl.dispose());
    }

    _hvResControllers.values.forEach((c) => c.dispose());
    _lvResControllers.values.forEach((c) => c.dispose());

    for (var phase in ['U', 'V', 'W']) {
      _noLoadTest[phase]!
          .values
          .forEach((c) => (c as TextEditingController).dispose());
      _loadTest[phase]!
          .values
          .forEach((c) => (c as TextEditingController).dispose());
    }

    super.dispose();
  }

  Map<String, String> _extractTestValues(Map map) => {
        'amp': map['amp']!.text,
        'volt': map['volt']!.text,
        'watt': map['watt']!.text,
      };

  void _submitForm(bool isPreview) async {
    if (!_formKey.currentState!.validate()) return; // Validate form

    final testData = {
      'temperature': _temperatureController.text,
      'insulationResistance': {
        'hv-e': _hvEController.text,
        'lv-e': _lvEController.text,
        'hv-lv': _hvLvController.text,
      },
      'ratios': _ratioInputs
          .map((map) => {
                'U': map['U']!.text,
                'V': map['V']!.text,
                'W': map['W']!.text,
              })
          .toList(),
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
    };
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'Unknown';
    final fullData = {
      ...widget.generalData,
      'testData': testData,
      'isPreview': isPreview,
      'savedBy': username,
    };

    if (widget.isEdit) {
      fullData['version'] = DateTime.now().millisecondsSinceEpoch;
    }

    GoRouter.of(context).push('/preview', extra: fullData);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Report saved successfully.')),
    );
  }

  Widget _buildRatioInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(widget.tapCount, (i) {
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
                      controller: _ratioInputs[i][p],
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
    );
  }

  Widget _buildResistanceInputs(
      Map<String, TextEditingController> map, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildTestRow(String label, Map phaseMap) {
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
                    validator: _numberValidator,
                  ),
                  TextFormField(
                    controller: phaseMap[p]['volt'],
                    decoration: const InputDecoration(labelText: 'Volt'),
                    validator: _numberValidator,
                  ),
                  TextFormField(
                    controller: phaseMap[p]['watt'],
                    decoration: const InputDecoration(labelText: 'Watt'),
                    validator: _numberValidator,
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

  @override
  Widget build(BuildContext context) {
    // UI unchanged
    // Calls _submitForm(false) or _submitForm(true)
    // All other widgets unchanged
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
                      labelText: 'Insulation Resistance HV-E'),
                  validator: _numberValidator,
                ),
                TextFormField(
                  controller: _lvEController,
                  decoration: const InputDecoration(
                      labelText: 'Insulation Resistance LV-E'),
                  validator: _numberValidator,
                ),
                TextFormField(
                  controller: _hvLvController,
                  decoration: const InputDecoration(
                      labelText: 'Insulation Resistance HV-LV'),
                  validator: _numberValidator,
                ),
                const SizedBox(height: 16),
                _buildRatioInputs(),
                const SizedBox(height: 16),
                _buildResistanceInputs(
                    _hvResControllers, 'HV Winding Resistance'),
                _buildResistanceInputs(
                    _lvResControllers, 'LV Winding Resistance'),
                const SizedBox(height: 16),
                _buildTestRow('No Load Test', _noLoadTest),
                const SizedBox(height: 16),
                _buildTestRow('Load Test', _loadTest),
                const SizedBox(height: 24),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () => _submitForm(false),
                        child: const Text('Customer Report'),
                      ),
                      ElevatedButton(
                        onPressed: () => _submitForm(true),
                        child: const Text('Internal Report'),
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

  // ... _buildRatioInputs, _buildResistanceInputs, _buildTestRow remain unchanged
}
