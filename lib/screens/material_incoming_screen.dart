import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dropdown_search/dropdown_search.dart';

class MaterialIncomingScreen extends StatefulWidget {
  const MaterialIncomingScreen({super.key});

  @override
  State<MaterialIncomingScreen> createState() => _MaterialIncomingScreenState();
}

class _MaterialIncomingScreenState extends State<MaterialIncomingScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedMaterial;
  String? _type;
  String? _subtype;
  String? _selectedJob;
  bool _isJobSpecific = false;

  final _qtyController = TextEditingController();
  final _priceController = TextEditingController();
  final _makeController = TextEditingController();
  final _descController = TextEditingController();
  final _invoiceController = TextEditingController();

  List<Map<String, dynamic>> _materialsRaw = [];
  List<String> _materials = [];
  List<String> _jobNumbers = [];
  List<Map<String, dynamic>> _entries = [];

  String _role = '';
  String _username = '';

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadEntries();
    _loadUser();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    _makeController.dispose();
    _descController.dispose();
    _invoiceController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _role = prefs.getString('role')?.toLowerCase() ?? 'user';
      _username = prefs.getString('username') ?? '';
    });
  }

  Future<void> _loadData() async {
    final materials = await ApiService.getMaterials();
    final jobs = await ApiService.getOpenJobs();
    setState(() {
      _materialsRaw = List<Map<String, dynamic>>.from(materials);
      _materials =
          materials
              .map<String>(
                (m) =>
                    "${m['type']} - ${m['subtype']}${m['make'] != null && m['make'].toString().trim().isNotEmpty ? ' - ${m['make']}' : ''}",
              )
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      _jobNumbers =
          jobs.map<String>((job) => job['serialNo'].toString()).toList()
            ..sort();
    });
  }

  Future<void> _loadEntries() async {
    final data = await ApiService.getMaterialIncomingEntries();
    List<Map<String, dynamic>> entries = List<Map<String, dynamic>>.from(data);

    entries.sort((a, b) {
      final dateA = DateTime.tryParse(a['entryDate'] ?? '') ?? DateTime(2000);
      final dateB = DateTime.tryParse(b['entryDate'] ?? '') ?? DateTime(2000);
      return dateB.compareTo(dateA); // Newest first
    });

    setState(() => _entries = entries);
  }

  void _handleMaterialSelection(String? value) {
    if (value == null) return;

    final parts = value.split(" - ");
    final type = parts[0];
    final subtype = parts.length > 1 ? parts[1] : '';

    final material = _materialsRaw.firstWhere(
      (m) => m['type'] == type && m['subtype'] == subtype,
      orElse: () => {},
    );
    setState(() {
      _type = type;
      _subtype = subtype;
      _selectedMaterial = value;
      _isJobSpecific = material['jobSpecific'] ?? false;
      _selectedJob = null; // Reset job on material change
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'material': _selectedMaterial,
      'type': _type,
      'subtype': _subtype,
      'jobSpecific': _isJobSpecific,
      if (_isJobSpecific) 'serialNo': _selectedJob,
      'quantity': _qtyController.text,
      'price': _priceController.text,
      'make': _makeController.text,
      'description': _descController.text,
      'invoice': _invoiceController.text,
      'entryDate': DateTime.now().toIso8601String(),
      'user': _username,
    };

    await ApiService.submitMaterialIncoming(data);
    await _loadEntries();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Material entry submitted")));
    _formKey.currentState!.reset();
    setState(() {
      _selectedMaterial = null;
      _selectedJob = null;
    });
  }

  Future<void> _deleteEntry(String id, String user) async {
    if (_role == "admin" || user == _username) {
      try {
        final entry = await ApiService.getMaterialEntryById(id);
        if (entry != null) {
          await ApiService.removeStock(data: entry);
          await ApiService.deleteMaterialEntry(id);
          await _loadEntries();
        }
      } catch (e) {
        print('Error deleting entry: $e');
      }
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> entry) async {
    final qtyController = TextEditingController(
      text: entry['quantity']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: entry['price']?.toString() ?? '',
    );
    final makeController = TextEditingController(
      text: entry['make']?.toString() ?? '',
    );
    final descController = TextEditingController(
      text: entry['description']?.toString() ?? '',
    );
    final invoiceController = TextEditingController(
      text: entry['invoice']?.toString() ?? '',
    );
    String? selectedMaterial = entry['material'];
    String? selectedJob = entry['serialNo'];

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Incoming Entry'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownSearch<String>(
                  items: _materials,
                  selectedItem: selectedMaterial,
                  filterFn: (item, filter) {
                    if (item == null || filter == null) return false;
                    final filterWords = filter
                        .toLowerCase()
                        .split(' ')
                        .where((w) => w.isNotEmpty);
                    final lowerItem = item.toLowerCase();
                    return filterWords.every(
                      (word) => lowerItem.contains(word),
                    );
                  },
                  dropdownDecoratorProps: const DropDownDecoratorProps(
                    dropdownSearchDecoration: InputDecoration(
                      labelText: "Material Type",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  popupProps: const PopupProps.menu(
                    showSearchBox: true,
                    searchFieldProps: TextFieldProps(
                      decoration: InputDecoration(
                        hintText: "Search type or subtype...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  onChanged: (val) {
                    selectedMaterial = val;
                  },
                ),
                const SizedBox(height: 8),
                if (entry['jobSpecific'] == true)
                  DropdownSearch<String>(
                    items: List<String>.from(_jobNumbers),
                    selectedItem: selectedJob,
                    dropdownDecoratorProps: const DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        labelText: "Job Number",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    popupProps: const PopupProps.menu(
                      showSearchBox: true,
                      searchFieldProps: TextFieldProps(
                        decoration: InputDecoration(
                          hintText: "Search...",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    onChanged: (val) => selectedJob = val,
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Price'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: makeController,
                  decoration: const InputDecoration(labelText: 'Make'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: invoiceController,
                  decoration: const InputDecoration(
                    labelText: 'Invoice Number',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updatedEntry = {
                  ...entry,
                  'material': selectedMaterial,
                  'quantity': qtyController.text,
                  'price': priceController.text,
                  'make': makeController.text,
                  'description': descController.text,
                  'invoice': invoiceController.text,
                  if (entry['jobSpecific'] == true) 'serialNo': selectedJob,
                };
                await ApiService.updateMaterialIncomingEntry(
                  entryId: entry['id'],
                  data: updatedEntry,
                );
                Navigator.pop(context);
                await _loadEntries();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("Entry updated")));
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = _entries.where((entry) {
      final search = _searchQuery;
      if (search.isEmpty) return true;
      final fieldsToSearch = [
        (entry['type'] ?? '').toString().toLowerCase(),
        (entry['subtype'] ?? '').toString().toLowerCase(),
        (entry['make'] ?? '').toString().toLowerCase(),
        (entry['invoice'] ?? '').toString().toLowerCase(),
        (entry['serialNo'] ?? '').toString().toLowerCase(),
      ];
      return fieldsToSearch.any((field) => field.contains(search));
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Material Incoming')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownSearch<String>(
                          selectedItem: _selectedMaterial,
                          items: _materials,
                          filterFn: (item, filter) {
                            if (item == null || filter == null) return false;
                            final filterWords = filter
                                .toLowerCase()
                                .split(' ')
                                .where((w) => w.isNotEmpty);
                            final lowerItem = item.toLowerCase();
                            return filterWords.every(
                              (word) => lowerItem.contains(word),
                            );
                          },
                          dropdownDecoratorProps: const DropDownDecoratorProps(
                            dropdownSearchDecoration: InputDecoration(
                              labelText: "Material Type",
                              border: OutlineInputBorder(),
                            ),
                          ),
                          popupProps: const PopupProps.menu(
                            showSearchBox: true,
                            searchFieldProps: TextFieldProps(
                              decoration: InputDecoration(
                                hintText: "Search type or subtype...",
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          validator: (val) => val == null ? 'Required' : null,
                          onChanged: _handleMaterialSelection,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_isJobSpecific)
                        Expanded(
                          child: DropdownSearch<String>(
                            selectedItem: _selectedJob,
                            items: List<String>.from(_jobNumbers),
                            dropdownDecoratorProps:
                                const DropDownDecoratorProps(
                                  dropdownSearchDecoration: InputDecoration(
                                    labelText: "Job Number",
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                            popupProps: const PopupProps.menu(
                              showSearchBox: true,
                              searchFieldProps: TextFieldProps(
                                decoration: InputDecoration(
                                  hintText: "Search...",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            validator: (val) => val == null ? 'Required' : null,
                            onChanged: (val) =>
                                setState(() => _selectedJob = val),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _qtyController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Required';
                            final parsed = double.tryParse(val);
                            if (parsed == null) return 'Enter valid number';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Price',
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Required';
                            final parsed = double.tryParse(val);
                            if (parsed == null) return 'Enter valid number';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _makeController,
                          decoration: const InputDecoration(
                            labelText: 'Make',
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) => val == null || val.trim().isEmpty
                              ? 'Required'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _descController,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _invoiceController,
                    decoration: const InputDecoration(
                      labelText: 'Invoice Number',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) =>
                        val == null || val.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Submit'),
                  ),
                ],
              ),
            ),
            const Divider(height: 30),
            const Text('Incoming Entries', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search incoming entries',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            ...filteredEntries.map(
              (entry) => Card(
                child: ListTile(
                  title: Text(entry['material'] ?? ''),
                  subtitle: Text(
                    "Qty: ${entry['quantity']} | Serial No: ${entry['serialNo']} | Price: ${entry['price']} | Make: ${entry['make']} | Invoice No: ${entry['invoice']} | Entry Date: ${entry['entryDate']} | User: ${entry['user']} | Approved By: ${entry['approved_by']} | Approved: ${entry['approved'] == true ? 'Yes' : 'No'}",
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((_role == "admin" || entry['user'] == _username) &&
                          entry['approved'] != true)
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showEditDialog(entry),
                        ),
                      if ((_role == "admin" || entry['user'] == _username) &&
                          entry['approved'] != true)
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () =>
                              _deleteEntry(entry['id'], entry['user']),
                        ),
                      if (_role == "admin" && entry['approved'] != true)
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          tooltip: "Approve",
                          onPressed: () async {
                            await ApiService.approveMaterialEntry(
                              entryId: entry['id'],
                              approver: _username,
                            );
                            await ApiService.addStock(data: entry);
                            await _loadEntries();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Entry approved and added to stock",
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
