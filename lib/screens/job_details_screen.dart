import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'package:go_router/go_router.dart';
import 'job_list_screen.dart';
import '../models/transformer_vector_group.dart';

class JobDetailsScreen extends StatefulWidget {
  const JobDetailsScreen({super.key});

  @override
  State<JobDetailsScreen> createState() => _JobDetailsScreenState();
}

class _JobDetailsScreenState extends State<JobDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _purchaserNameController = TextEditingController();
  final _purchaserRefController = TextEditingController();
  final _serialNoController = TextEditingController();
  final _kvaController = TextEditingController();
  final _phasesController = TextEditingController();
  final _hvVoltageController = TextEditingController();
  final _lvVoltageController = TextEditingController();
  final _lv2VoltageController = TextEditingController();
  final _vectorGroupController = TextEditingController();
  final _tapMaxController = TextEditingController();
  final _tapMinController = TextEditingController();
  final _stepVoltageController = TextEditingController();
  final _remarkController = TextEditingController();
  final _quantityController = TextEditingController();

  String? _selectedRelevantIS;
  String? _selectedTappingType;
  String? _selectedJobType;
  String? _selectedMaterial =
      'Copper'; // Default value (keep default for Material only)
  String _userRole = '';
  bool _showTapping = true;
  bool _isSaving = false;
  Map<String, dynamic>? _pendingJob;

  final List<String> _vectorGroupOptions = [
    ...TransformerVectorGroup.supportedNames,
    'Not Applicable',
  ];
  final List<String> _relevantISOptions = ['IS:2026', 'IS:1180'];
  final List<String> _tappingTypeOptions = ['OLTC', 'OCTC', 'No Tapping'];
  final List<String> _jobTypeOptions = ['New', 'Repair'];
  final List<String> _materialOptions = ['Copper', 'Aluminium'];

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  TransformerVectorGroup? get _vectorConfig {
    final name = _vectorGroupController.text.trim();
    if (name.isEmpty || name.toLowerCase() == 'not applicable') return null;
    try {
      return TransformerVectorGroup.fromName(name);
    } on FormatException {
      return null;
    }
  }

  bool get _hasDualOutput => _vectorConfig?.hasDualOutput ?? false;

  @override
  void dispose() {
    for (final controller in [
      _purchaserNameController,
      _purchaserRefController,
      _serialNoController,
      _kvaController,
      _phasesController,
      _hvVoltageController,
      _lvVoltageController,
      _lv2VoltageController,
      _vectorGroupController,
      _tapMaxController,
      _tapMinController,
      _stepVoltageController,
      _remarkController,
      _quantityController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userRole = prefs.getString('role') ?? 'user';
    });
  }

  Future<void> _generateNextSerialNo(String? type) async {
    if (type == null) return;
    final jobs = await ApiService.getJobs();
    final prefix = type == 'New' ? 'TRFD' : 'TRFR';
    final jobNumbers = jobs
        .map((j) => j['serialNo']?.toString())
        .where((s) => s != null && s.startsWith(prefix))
        .toList();

    int maxNum = 0;
    for (var sn in jobNumbers) {
      final number = int.tryParse(sn!.substring(4));
      if (number != null && number > maxNum) maxNum = number;
    }
    final next = prefix + (maxNum + 1).toString().padLeft(4, '0');
    setState(() => _serialNoController.text = next);
  }

  void _submitForm() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username') ?? 'unknown';

      final data = _pendingJob ??= {
        'purchaserName': _purchaserNameController.text,
        'purchaserReference': _purchaserRefController.text,
        'serialNo': _serialNoController.text,
        'kva': _kvaController.text,
        'phases': _phasesController.text,
        'vectorGroup': _vectorGroupController.text.trim(),
        'relevantIS': _selectedRelevantIS,
        'tappingType': _selectedTappingType,
        'tappingRangeMax': _showTapping ? _tapMaxController.text : null,
        'tappingRangeMin': _showTapping ? _tapMinController.text : null,
        'stepVoltage': _showTapping ? _stepVoltageController.text : null,
        'hvVoltage': _hvVoltageController.text,
        'lvVoltage': _lvVoltageController.text,
        if (_hasDualOutput) 'lv2Voltage': _lv2VoltageController.text,
        'jobType': _selectedJobType,
        'material': _selectedMaterial ?? 'Copper',
        'remark': _remarkController.text,
        'quantity': _quantityController.text,
        'entryDateTime': DateTime.now().toIso8601String(),
        'createdBy': username,
      };

      final serial = await ApiService.saveJob(data);
      _pendingJob = null;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Job $serial saved successfully')));

      // Navigate to JobListScreen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const JobListScreen()),
      );
    } catch (error) {
      if (error is ApiException && error.statusCode < 500) _pendingJob = null;
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save job: $error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    bool voltage = false,
  }) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 24,
      child: TextFormField(
        controller: controller,
        enabled: !_isSaving && _pendingJob == null,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'Required';
          if (voltage) {
            final number = double.tryParse(value);
            if (number == null || !number.isFinite || number <= 0) {
              return 'Enter a positive voltage';
            }
          }
          return null;
        },
      ),
    );
  }

  Widget _buildVectorGroupField() {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 24,
      child: TextFormField(
        controller: _vectorGroupController,
        enabled: !_isSaving && _pendingJob == null,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Vector Group',
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          suffixIcon: PopupMenuButton<String>(
            tooltip: 'Vector groups',
            icon: const Icon(Icons.arrow_drop_down),
            itemBuilder: (context) => _vectorGroupOptions
                .map((name) => PopupMenuItem(value: name, child: Text(name)))
                .toList(),
            onSelected: (value) {
              _vectorGroupController.text = value;
              setState(() {});
            },
          ),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'Required';
          if (value.trim().toLowerCase() == 'not applicable') return null;
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

  Widget _buildDropdownField(
    String label,
    List<String> options,
    String? selectedValue,
    void Function(String?) onChanged,
  ) {
    // Only Material will have a default value, others default to null (no selection)
    final bool isMaterial = label == 'Material';
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
            value: isMaterial
                ? (selectedValue != null && options.contains(selectedValue)
                      ? selectedValue
                      : options.first)
                : (selectedValue != null && options.contains(selectedValue)
                      ? selectedValue
                      : null), // no default for non-material
            isExpanded: true,
            onChanged: _isSaving || _pendingJob != null ? null : onChanged,
            items: options
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            hint: Text('Select $label'),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Job'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/dashboard'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Wrap(
              runSpacing: 8,
              spacing: 8,
              children: [
                _buildDropdownField(
                  'Job Type',
                  _jobTypeOptions,
                  _selectedJobType,
                  (val) {
                    setState(() => _selectedJobType = val);
                    _generateNextSerialNo(val);
                  },
                ),
                _buildField(_serialNoController, 'Serial No'),
                _buildField(_purchaserNameController, 'Purchaser Name'),
                _buildField(_purchaserRefController, 'Purchaser Reference'),
                _buildField(_kvaController, 'KVA'),
                _buildField(_phasesController, 'Phases'),
                _buildVectorGroupField(),
                _buildDropdownField(
                  'Relevant IS',
                  _relevantISOptions,
                  _selectedRelevantIS,
                  (val) => setState(() => _selectedRelevantIS = val),
                ),
                _buildField(
                  _hvVoltageController,
                  'HV Voltage',
                  voltage: _vectorConfig != null,
                ),
                _buildField(
                  _lvVoltageController,
                  _hasDualOutput ? 'LV1 Voltage' : 'LV Voltage',
                  voltage: _vectorConfig != null,
                ),
                if (_hasDualOutput)
                  _buildField(
                    _lv2VoltageController,
                    'LV2 Voltage',
                    voltage: true,
                  ),
                _buildDropdownField(
                  'Tapping Type',
                  _tappingTypeOptions,
                  _selectedTappingType,
                  (val) {
                    setState(() {
                      _selectedTappingType = val;
                      _showTapping = val != 'No Tapping';
                    });
                  },
                ),
                if (_showTapping) _buildField(_tapMaxController, 'Tapping Max'),
                if (_showTapping) _buildField(_tapMinController, 'Tapping Min'),
                if (_showTapping)
                  _buildField(_stepVoltageController, 'Step Voltage'),
                _buildDropdownField(
                  'Material',
                  _materialOptions,
                  _selectedMaterial,
                  (val) => setState(() => _selectedMaterial = val ?? 'Copper'),
                ),
                _buildField(_quantityController, 'Quantity'),
                _buildField(_remarkController, 'Remark'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _isSaving ? null : _submitForm,
                  child: const Text('Save Job'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
