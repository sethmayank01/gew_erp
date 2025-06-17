import 'package:flutter/material.dart';
import 'package:intl/date_time_patterns.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JobIndentConsumptionScreen extends StatefulWidget {
  const JobIndentConsumptionScreen({super.key});

  @override
  State<JobIndentConsumptionScreen> createState() =>
      _JobIndentConsumptionScreenState();
}

class _JobIndentConsumptionScreenState
    extends State<JobIndentConsumptionScreen> {
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _materials = [];
  String? _selectedJobId;
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _descControllers = {};
  String _role = '';
  String _username = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _role = prefs.getString('role')?.toLowerCase() ?? 'user';
      _username = prefs.getString('username') ?? '';
    });
  }

  Future<void> _loadData() async {
    final jobs = await ApiService
        .getJobs(); // Should return job list with 'finalized' flag
    final materials =
        await ApiService.getMaterials(); // Should return list of materials

    final filteredJobs = jobs.where((job) => job['isFinal'] != true).toList();

    for (var mat in materials) {
      final id = _materialId(mat);
      _qtyControllers[id] = TextEditingController();
      _descControllers[id] = TextEditingController();
    }

    setState(() {
      _jobs = List<Map<String, dynamic>>.from(filteredJobs);
      _materials = List<Map<String, dynamic>>.from(materials);
      ;
      _isLoading = false;
    });
  }

  String _materialId(Map<String, dynamic> material) {
    return "${material['type']}_${material['subtype']}";
  }

  Future<void> _submitIndent() async {
    if (_selectedJobId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a job.")),
      );
      return;
    }
    final existingIndents = List<Map<String, dynamic>>.from(
        await ApiService.getIndentsForJob(_selectedJobId!));

    List<Map<String, dynamic>> indentItems = [];

    for (var material in _materials) {
      final id = _materialId(material);
      final qty = double.tryParse(_qtyControllers[id]?.text ?? '');
      final desc = _descControllers[id]?.text;

      if (qty != null && qty > 0) {
        final type = material['type'];
        final subtype = material['subtype'];
        final materialKey = "$type - $subtype";

        final alreadyExists = existingIndents.any((entry) =>
            entry['type'] == type &&
            entry['subtype'] == subtype &&
            entry['serialNo'] == _selectedJobId);

        if (alreadyExists && _role != 'admin') {
          // Block duplicate entry for user
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    "Indent for $materialKey already exists for this job. Only admins can update.")),
          );
          continue;
        }
        indentItems.add({
          'serialNo': _selectedJobId,
          'material': material['type'] + ' - ' + material['subtype'],
          'type': material['type'],
          'subtype': material['subtype'],
          'quantity': qty,
          'description': desc ?? '',
          'jobSpecific': material['jobSpecific'],
          'user_ind': _username,
          'ind_time': DateTime.now().toString(),
        });
      }
    }

    if (indentItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please enter at least one valid indent.")),
      );
      return;
    }

    final success = await ApiService.submitJobIndent(indentItems);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Indent submitted successfully!")),
      );
      _qtyControllers.values.forEach((c) => c.clear());
      _descControllers.values.forEach((c) => c.clear());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to submit indent.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Job Indent Entry")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: ListView(
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedJobId,
                    decoration: const InputDecoration(labelText: 'Select Job'),
                    items: _jobs.map((job) {
                      return DropdownMenuItem(
                        value: job['serialNo'].toString(),
                        child: Text("${job['serialNo']}"),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedJobId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Materials",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._materials.map((material) {
                    final id = _materialId(material);
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${material['type']} - ${material['subtype']}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _qtyControllers[id],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                        labelText: "Indent Quantity"),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _descControllers[id],
                                    decoration: const InputDecoration(
                                        labelText: "Description"),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _submitIndent,
                    icon: const Icon(Icons.save),
                    label: const Text("Submit Indent"),
                  ),
                ],
              ),
            ),
    );
  }
}
