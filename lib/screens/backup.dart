import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OutgoingMaterialScreen extends StatefulWidget {
  const OutgoingMaterialScreen({super.key});

  @override
  State<OutgoingMaterialScreen> createState() => _OutgoingMaterialScreenState();
}

class _OutgoingMaterialScreenState extends State<OutgoingMaterialScreen> {
  final _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _materials = [];

  Map<String, dynamic>? _selectedJob;
  Map<String, dynamic>? _selectedMaterial;
  Map<String, dynamic>? _selectedIndent;
  String _role = '';
  String _username = '';

  double _availableQty = 0.0;
  double _unitPrice = 0.0;
  double _indentQty = 0.0;
  final TextEditingController _issueQtyController = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _role = prefs.getString('role')?.toLowerCase() ?? 'user';
      _username = prefs.getString('username') ?? '';
    });
  }

  Future<void> _loadInitialData() async {
    final jobs = await ApiService.getJobs();
    final materials = await ApiService.getMaterials();

    setState(() {
      _jobs = List<Map<String, dynamic>>.from(
          jobs.where((job) => job['isFinal'] != true));
      _materials = List<Map<String, dynamic>>.from(materials);
      _isLoading = false;
    });
  }

  void _onMaterialSelected(Map<String, dynamic>? material) async {
    if (material == null) return;
    setState(() {
      _selectedMaterial = material;
    });

    if (_selectedJob != null) {
      final materialList = await ApiService.getMaterials();
      final materialSelected = materialList.firstWhere(
        (s) =>
            s['type'] == material['type'] &&
            s['subtype'] == material['subtype'],
      );
      final matchedStock;
      final matchedIndent;
      final stock = await ApiService.getStock(materialSelected['jobSpecific']);
      final indentData =
          await ApiService.getIndentsForJob(_selectedJob!['serialNo']);
      if (materialSelected['jobSpecific']) {
        matchedStock = stock.firstWhere(
          (s) =>
              s['type'] == material['type'] &&
              s['subtype'] == material['subtype'] &&
              s['serialNo'] == _selectedJob!['serialNo'],
          orElse: () => {'quantity': 0.0, 'price': 0.0},
        );
        matchedIndent = indentData.firstWhere(
          (i) =>
              i['type'] == material['type'] &&
              i['subtype'] == material['subtype'] &&
              i['serialNo'] == _selectedJob!['serialNo'],
          orElse: () => {'quantity': 0.0},
        );
      } else {
        matchedStock = stock.firstWhere(
          (s) =>
              s['type'] == material['type'] &&
              s['subtype'] == material['subtype'],
          orElse: () => {'quantity': 0.0, 'price': 0.0},
        );
        matchedIndent = indentData.firstWhere(
          (i) =>
              i['type'] == material['type'] &&
              i['subtype'] == material['subtype'],
          orElse: () => {'quantity': 0.0},
        );
      }

      setState(() {
        _availableQty = (matchedStock['quantity'] ?? 0).toDouble();
        _unitPrice = (matchedStock['price'] ?? 0).toDouble();
        _indentQty = (matchedIndent['quantity'] ?? 0).toDouble();
        _selectedIndent = matchedIndent;
      });
    }
  }

  Future<void> _submitIssue() async {
    final issueQty = double.tryParse(_issueQtyController.text) ?? 0.0;
    if (_selectedJob == null || _selectedMaterial == null || issueQty <= 0)
      return;

    final material = _selectedMaterial!;
    final indentMaterial = _selectedIndent!;
    final data = {
      'serialNo': _selectedJob!['serialNo'],
      'material': material['type'] + ' - ' + material['subtype'],
      'type': material['type'],
      'subtype': material['subtype'],
      'price': _unitPrice,
      'quantity': indentMaterial['quantity'],
      'user_ind': indentMaterial['user_ind'],
      'ind_time': indentMaterial['ind_time'],
      'issuedQty': issueQty,
      'issuedValue': issueQty * _unitPrice,
      'user_out': _username,
      'out_time': DateTime.now().toString(),
      'jobSpecific': material['jobSpecific'],
    };

    final result = await ApiService.issueMaterial(data);
    if (result == "Success") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material issued successfully!')),
      );
      _issueQtyController.clear();
      _onMaterialSelected(material); // refresh stock & indent
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $result')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Issue Material to Job")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<Map<String, dynamic>>(
                      decoration:
                          const InputDecoration(labelText: 'Select Job'),
                      value: _selectedJob,
                      items: _jobs
                          .map((job) => DropdownMenuItem(
                                value: job,
                                child: Text(job['serialNo'] ?? 'Unknown'),
                              ))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedJob = val),
                      validator: (val) =>
                          val == null ? 'Please select a job' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      decoration:
                          const InputDecoration(labelText: 'Select Material'),
                      value: _selectedMaterial,
                      items: _materials.map((mat) {
                        final matKey = mat['type'] + '-' + mat['subtype'];
                        return DropdownMenuItem(
                          value: mat,
                          child: Text(matKey),
                        );
                      }).toList(),
                      onChanged: _onMaterialSelected,
                      validator: (val) =>
                          val == null ? 'Please select a material' : null,
                    ),
                    const SizedBox(height: 16),
                    Text('Available Qty: $_availableQty'),
                    Text('Indent Qty: $_indentQty'),
                    Text('Unit Price: ₹$_unitPrice'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _issueQtyController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Quantity to Issue',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Required';
                        final parsed = double.tryParse(val);
                        if (parsed == null) return 'Enter valid number';
                        if (parsed <= 0) return 'Quantity must be > 0';
                        if (parsed > _availableQty)
                          return 'Cannot issue more than available stock ($_availableQty)';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          _submitIssue();
                        }
                      },
                      child: const Text('Submit Issue'),
                    )
                  ],
                ),
              ),
            ),
    );
  }
}
