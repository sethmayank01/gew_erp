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
  List<Map<String, dynamic>> _filteredMaterials = [];
  String? _selectedJobId;
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _descControllers = {};
  String _role = '';
  String _username = '';
  bool _isLoading = true;
  String _searchText = '';
  String? _error;
  Map<String, Map<String, dynamic>> _existingIndents = {};

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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final jobs = await ApiService.getJobs();
      final materials = await ApiService.getMaterials();

      final filteredJobs = jobs.where((job) => job['isFinal'] != true).toList();

      for (var mat in materials) {
        final id = _materialId(mat);
        _qtyControllers[id] = TextEditingController();
        _descControllers[id] = TextEditingController();
      }

      // Sort materials alphabetically by type+subtype combined
      materials.sort((a, b) {
        final aCombined = ('${a['type']} ${a['subtype']}').toLowerCase();
        final bCombined = ('${b['type']} ${b['subtype']}').toLowerCase();
        return aCombined.compareTo(bCombined);
      });

      setState(() {
        _jobs = List<Map<String, dynamic>>.from(filteredJobs);
        _materials = List<Map<String, dynamic>>.from(materials);
        _filteredMaterials = List<Map<String, dynamic>>.from(materials);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load data. Please try again.';
        _isLoading = false;
      });
    }
  }

  String _materialId(Map<String, dynamic> material) {
    return "${material['type']}_${material['subtype']}";
  }

  void _onSearchChanged(String text) {
    setState(() {
      _searchText = text;
      final searchWords = _searchText
          .toLowerCase()
          .split(' ')
          .where((w) => w.isNotEmpty)
          .toList();
      _filteredMaterials = _materials.where((mat) {
        final combined = ('${mat['type']} ${mat['subtype']}').toLowerCase();
        return searchWords.every((word) => combined.contains(word));
      }).toList();
    });
  }

  Future<void> _fetchExistingIndentsForJob() async {
    _existingIndents.clear();
    if (_selectedJobId != null) {
      final existingIndents = List<Map<String, dynamic>>.from(
        await ApiService.getIndentsForJob(_selectedJobId!),
      );
      for (var indent in existingIndents) {
        final key = _materialId({
          'type': indent['type'],
          'subtype': indent['subtype'],
        });
        _existingIndents[key] = indent;
      }
    }
  }

  Future<void> _submitIndent() async {
    if (_selectedJobId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select a job.")));
      return;
    }
    await _fetchExistingIndentsForJob();

    List<Map<String, dynamic>> indentsToCreate = [];
    List<Map<String, dynamic>> indentsToUpdate = [];

    for (var material in _materials) {
      final id = _materialId(material);
      final qty = double.tryParse(_qtyControllers[id]?.text ?? '');
      final desc = _descControllers[id]?.text;

      final existingIndent = _existingIndents[id];

      if (qty != null && qty > 0) {
        final type = material['type'];
        final subtype = material['subtype'];
        final materialKey = "$type - $subtype";

        final alreadyExists = existingIndent != null;

        if (alreadyExists && _role != 'admin') {
          // Block duplicate entry for user
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Indent for $materialKey already exists for this job. Only admins can update.",
              ),
            ),
          );
          continue;
        }
        Map<String, dynamic> indentItem = {
          'serialNo': _selectedJobId,
          'material': material['type'] + ' - ' + material['subtype'],
          'type': material['type'],
          'subtype': material['subtype'],
          'quantity': qty,
          'description': desc ?? '',
          'jobSpecific': material['jobSpecific'],
          'user_ind': _username,
          'ind_time': DateTime.now().toString(),
        };
        if (alreadyExists && _role == 'admin') {
          // For admin, update existing indent
          indentItem['id'] = existingIndent['id'];
          indentsToUpdate.add(indentItem);
        } else if (!alreadyExists) {
          indentsToCreate.add(indentItem);
        }
      }
    }

    if (indentsToCreate.isEmpty && indentsToUpdate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter at least one valid indent."),
        ),
      );
      return;
    }

    bool allSuccess = true;

    // Update existing indents (for admin)
    for (var indent in indentsToUpdate) {
      try {
        await ApiService.updateExistingJobIndent(data: indent);
      } catch (e) {
        allSuccess = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update indent for ${indent['material']}"),
          ),
        );
      }
    }

    // Submit new indents
    if (indentsToCreate.isNotEmpty) {
      final success = await ApiService.submitJobIndent(indentsToCreate);
      allSuccess = allSuccess && success;
    }

    if (allSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Indent(s) submitted/updated successfully!"),
        ),
      );
      _qtyControllers.values.forEach((c) => c.clear());
      _descControllers.values.forEach((c) => c.clear());
      await _fetchExistingIndentsForJob();
      setState(() {});
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Some indents failed.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Job Indent Entry")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
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
                    onChanged: (value) async {
                      setState(() {
                        _selectedJobId = value;
                      });
                      await _fetchExistingIndentsForJob();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Materials",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search Material (type and subtype)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  _filteredMaterials.isEmpty
                      ? const Center(child: Text('No materials found.'))
                      : Column(
                          children: _filteredMaterials.map((material) {
                            final id = _materialId(material);
                            final existingIndent = _existingIndents[id];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "${material['type']} - ${material['subtype']}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (existingIndent != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4.0,
                                          top: 2.0,
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.info,
                                              color: Colors.blue,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                "Existing Indent: Qty = ${existingIndent['quantity']}  Desc: ${existingIndent['description'] ?? ''}",
                                                style: const TextStyle(
                                                  color: Colors.blue,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _qtyControllers[id],
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            decoration: const InputDecoration(
                                              labelText: "Indent Quantity",
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: TextField(
                                            controller: _descControllers[id],
                                            decoration: const InputDecoration(
                                              labelText: "Description",
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
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
