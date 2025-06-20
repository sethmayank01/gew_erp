import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'package:go_router/go_router.dart';
import 'job_list_screen.dart';

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
  final _tapMaxController = TextEditingController();
  final _tapMinController = TextEditingController();
  final _stepVoltageController = TextEditingController();
  final _remarkController = TextEditingController();
  final _quantityController = TextEditingController();

  String? _selectedVectorGroup;
  String? _selectedRelevantIS;
  String? _selectedTappingType;
  String? _selectedJobType;
  String _userRole = '';
  bool _showTapping = true;

  final List<String> _vectorGroupOptions = [
    'Dyn11',
    'Ynd11',
    'Ddo',
    'Not Applicable',
  ];
  final List<String> _relevantISOptions = ['IS:2026', 'IS:1180'];
  final List<String> _tappingTypeOptions = ['OLTC', 'OCTC', 'No Tapping'];
  final List<String> _jobTypeOptions = ['New', 'Repair'];

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
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
    if (!_formKey.currentState!.validate()) return;

    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'unknown';

    final data = {
      'purchaserName': _purchaserNameController.text,
      'purchaserReference': _purchaserRefController.text,
      'serialNo': _serialNoController.text,
      'kva': _kvaController.text,
      'phases': _phasesController.text,
      'vectorGroup': _selectedVectorGroup,
      'relevantIS': _selectedRelevantIS,
      'tappingType': _selectedTappingType,
      'tappingRangeMax': _showTapping ? _tapMaxController.text : null,
      'tappingRangeMin': _showTapping ? _tapMinController.text : null,
      'stepVoltage': _showTapping ? _stepVoltageController.text : null,
      'hvVoltage': _hvVoltageController.text,
      'lvVoltage': _lvVoltageController.text,
      'jobType': _selectedJobType,
      'remark': _remarkController.text,
      'quantity': _quantityController.text,
      'entryDateTime': DateTime.now().toIso8601String(),
      'createdBy': username,
    };

    await ApiService.saveJob(data);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Job saved successfully')));

    // Navigate to JobListScreen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const JobListScreen()),
    );
  }

  Widget _buildField(TextEditingController controller, String label) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2 - 24,
      child: TextFormField(
        controller: controller,
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

  Widget _buildDropdownField(
    String label,
    List<String> options,
    String? selectedValue,
    void Function(String?) onChanged,
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
            value: selectedValue,
            isExpanded: true,
            onChanged: onChanged,
            items: options
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
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
                _buildDropdownField(
                  'Vector Group',
                  _vectorGroupOptions,
                  _selectedVectorGroup,
                  (val) => setState(() => _selectedVectorGroup = val),
                ),
                _buildDropdownField(
                  'Relevant IS',
                  _relevantISOptions,
                  _selectedRelevantIS,
                  (val) => setState(() => _selectedRelevantIS = val),
                ),
                _buildField(_hvVoltageController, 'HV Voltage'),
                _buildField(_lvVoltageController, 'LV Voltage'),
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
                _buildField(_quantityController, 'Quantity'),
                _buildField(_remarkController, 'Remark'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _submitForm,
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
