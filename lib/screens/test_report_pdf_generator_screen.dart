import 'package:flutter/material.dart';
import 'second_input_screen.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../models/transformer_vector_group.dart';

class TestReportPdfGeneratorScreen extends StatefulWidget {
  final Map<String, dynamic>? generalData;
  final int? tapCount;
  final bool isEdit;

  const TestReportPdfGeneratorScreen({
    Key? key,
    this.generalData,
    this.tapCount,
    this.isEdit = false,
  }) : super(key: key);

  @override
  State<TestReportPdfGeneratorScreen> createState() =>
      _TestReportPdfGeneratorScreenState();
}

class _TestReportPdfGeneratorScreenState
    extends State<TestReportPdfGeneratorScreen> {
  final _formKey = GlobalKey<FormState>();

  final _purchaserNameController = TextEditingController();
  final _purchaserRefController = TextEditingController();
  final _serialNoController = TextEditingController();
  final _dateOfTestingController = TextEditingController();
  final _kvaController = TextEditingController();
  final _phasesController = TextEditingController();
  final _hvVoltageController = TextEditingController();
  final _lvVoltageController = TextEditingController();
  final _lv2VoltageController = TextEditingController();
  final _tapMaxController = TextEditingController();
  final _tapMinController = TextEditingController();
  final _stepVoltageController = TextEditingController();
  final _tappingType = TextEditingController();

  String? _selectedVectorGroup = TransformerVectorGroup.supportedNames.first;
  final _vectorGroupController = TextEditingController(text: 'Dyn11');
  String? _selectedRelevantIS;
  String? _selectedJobNo;
  String? _remark;
  String? _selectedMaterial = 'Copper'; // Default to Copper
  List<Map<String, dynamic>> _jobs = [];

  final List<String> _vectorGroupOptions =
      TransformerVectorGroup.supportedNames;
  final List<String> _relevantISOptions = ['IS:2026', 'IS:1180'];
  final List<String> _materialOptions = ['Copper', 'Aluminum'];

  @override
  void initState() {
    super.initState();
    _loadJobs();
    if (widget.generalData != null) {
      _prefillFromData(widget.generalData!);
    }
  }

  Future<void> _loadJobs() async {
    final jobs = await ApiService.getJobs();
    setState(() {
      _jobs = List<Map<String, dynamic>>.from(
        jobs,
      ).where((job) => job['isFinal'] != true).toList();
    });
  }

  void _prefillFromData(Map<String, dynamic> data) {
    _purchaserNameController.text = data['purchaserName'] ?? '';
    _purchaserRefController.text = data['purchaserReference'] ?? '';
    _serialNoController.text = data['serialNo'] ?? '';
    _selectedJobNo = data['serialNo'] ?? '';
    _dateOfTestingController.text = data['dateOfTesting'] ?? '';
    _kvaController.text = data['kva'] ?? '';
    _phasesController.text = data['phases'] ?? '';
    _hvVoltageController.text = data['hvVoltage'] ?? '';
    _lvVoltageController.text = data['lvVoltage'] ?? '';
    _lv2VoltageController.text = data['lv2Voltage'] ?? '';
    _tappingType.text = data['tappingType'] ?? '';
    if (data['tappingType'] != "No Tapping") {
      _tapMaxController.text = data['tappingRangeMax']?.toString() ?? '';
      _tapMinController.text = data['tappingRangeMin']?.toString() ?? '';
      _stepVoltageController.text = data['stepVoltage']?.toString() ?? '';
    }
    _selectedVectorGroup = data['vectorGroup'];
    _vectorGroupController.text = _selectedVectorGroup ?? 'Dyn11';
    _selectedRelevantIS = data['relevantIS'];
    _remark = data['remark'] ?? '';
    // Material prefill with fallback to Copper if not present or null/empty/invalid
    final material = (data['material'] ?? '').toString();
    if (_materialOptions.contains(material)) {
      _selectedMaterial = material;
    } else {
      _selectedMaterial = 'Copper';
    }
  }

  TransformerVectorGroup get _vectorConfig {
    try {
      return TransformerVectorGroup.fromName(_selectedVectorGroup);
    } on FormatException {
      return TransformerVectorGroup.fromName('Dyn11');
    }
  }

  bool get _hasDualOutput => _vectorConfig.hasDualOutput;

  @override
  void dispose() {
    _purchaserNameController.dispose();
    _purchaserRefController.dispose();
    _serialNoController.dispose();
    _dateOfTestingController.dispose();
    _kvaController.dispose();
    _phasesController.dispose();
    _hvVoltageController.dispose();
    _lvVoltageController.dispose();
    _lv2VoltageController.dispose();
    _tapMaxController.dispose();
    _tapMinController.dispose();
    _stepVoltageController.dispose();
    _tappingType.dispose();
    _vectorGroupController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    int tapCount = 1;
    double maxTap = 0.0;
    double minTap = 0.0;
    double stepVoltage = 0.0;
    if (_tappingType.text != "No Tapping") {
      maxTap = double.tryParse(_tapMaxController.text) ?? 0.0;
      minTap = double.tryParse(_tapMinController.text) ?? 0.0;
      stepVoltage = double.tryParse(_stepVoltageController.text) ?? 0.0;

      final tapSpan = maxTap - minTap;
      final result = tapSpan / stepVoltage;

      if (result % 1 != 0) {
        _showError(
          'Invalid tap settings: (Max - Min) / Step must be a whole number.',
        );
        return;
      }

      tapCount = result.toInt() + 1;
    }
    final data = {
      'purchaserName': _purchaserNameController.text,
      'purchaserReference': _purchaserRefController.text,
      'serialNo': _serialNoController.text,
      'dateOfTesting': _dateOfTestingController.text,
      'kva': _kvaController.text,
      'phases': _phasesController.text,
      'vectorGroup': _vectorGroupController.text.trim(),
      'relevantIS': _selectedRelevantIS,
      'tappingRangeMax': maxTap,
      'tappingRangeMin': minTap,
      'stepVoltage': stepVoltage,
      'hvVoltage': _hvVoltageController.text,
      'lvVoltage': _lvVoltageController.text,
      if (_hasDualOutput) 'lv2Voltage': _lv2VoltageController.text,
      'material': _selectedMaterial ?? 'Copper',
      'remark': _remark,
    };

    context.push(
      '/second-input',
      extra: {
        'generalData': data,
        'tapCount': tapCount,
        'isEdit': widget.isEdit,
        'testData': widget.generalData?['testData'],
      },
    );
  }

  void _onJobSelected(String? jobNo) {
    setState(() => _selectedJobNo = jobNo);
    final selectedJob = _jobs.firstWhere(
      (job) => job['serialNo'] == jobNo,
      orElse: () => {},
    );
    if (selectedJob.isNotEmpty) {
      _prefillFromData(selectedJob);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _dateOfTestingController.text =
          '${picked.day.toString().padLeft(2, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Report PDF Generator'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/dashboard'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (_jobs.isNotEmpty)
                  _buildDropdownField(
                    'Job Number',
                    _jobs.map((e) => e['serialNo'].toString()).toList(),
                    _selectedJobNo,
                    _onJobSelected,
                  ),
                Wrap(
                  runSpacing: 8,
                  spacing: 8,
                  children: [
                    _buildField(_purchaserNameController, 'Purchaser Name'),
                    _buildField(_purchaserRefController, 'Purchaser Reference'),
                    _buildField(_serialNoController, 'Serial No'),
                    _buildDateField(
                      _dateOfTestingController,
                      'Date of Testing',
                    ),
                    _buildField(_kvaController, 'KVA'),
                    _buildField(_phasesController, 'Phases'),
                    _buildVectorGroupField(),
                    _buildDropdownField(
                      'Relevant IS',
                      _relevantISOptions,
                      _selectedRelevantIS,
                      (val) => setState(() => _selectedRelevantIS = val),
                    ),
                    _buildField(_hvVoltageController, 'HV Voltage'),
                    _buildField(
                      _lvVoltageController,
                      '${_vectorConfig.outputLabel(0)} Voltage',
                    ),
                    if (_hasDualOutput)
                      _buildField(
                        _lv2VoltageController,
                        '${_vectorConfig.outputLabel(1)} Voltage',
                      ),
                    _buildField(_tapMaxController, 'Tapping Max'),
                    _buildField(_tapMinController, 'Tapping Min'),
                    _buildField(_stepVoltageController, 'Step Voltage'),
                    _buildDropdownField(
                      'Material',
                      _materialOptions,
                      _selectedMaterial,
                      (val) =>
                          setState(() => _selectedMaterial = val ?? 'Copper'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _submitForm,
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 24,
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
        ),
        validator: (value) =>
            value == null || value.isEmpty ? 'Required' : null,
      ),
    );
  }

  Widget _buildVectorGroupField() {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 24,
      child: TextFormField(
        controller: _vectorGroupController,
        onChanged: (value) {
          setState(() => _selectedVectorGroup = value);
        },
        decoration: InputDecoration(
          labelText: 'Vector Group',
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: PopupMenuButton<String>(
            tooltip: 'Vector groups',
            icon: const Icon(Icons.arrow_drop_down),
            itemBuilder: (context) => _vectorGroupOptions
                .map((name) => PopupMenuItem(value: name, child: Text(name)))
                .toList(),
            onSelected: (value) {
              _vectorGroupController.text = value;
              setState(() => _selectedVectorGroup = value);
            },
          ),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'Required';
          try {
            TransformerVectorGroup.fromName(value);
            return null;
          } on FormatException catch (error) {
            return error.message;
          }
        },
      ),
    );
  }

  Widget _buildDateField(TextEditingController controller, String label) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 24,
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: () => _selectDate(context),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        validator: (value) => value == null || value.isEmpty
            ? 'Date of Testing is required'
            : null,
      ),
    );
  }

  Widget _buildDropdownField(
    String label,
    List<String> items,
    String? selectedValue,
    ValueChanged<String?> onChanged,
  ) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 24,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          border: const OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: (selectedValue != null && items.contains(selectedValue))
                ? selectedValue
                : items.first,
            isExpanded: true,
            items: items
                .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                .toList(),
            onChanged: onChanged,
            hint: Text('Select $label'),
          ),
        ),
      ),
    );
  }
}
