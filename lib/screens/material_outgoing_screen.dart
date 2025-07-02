import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';
import 'package:dropdown_search/dropdown_search.dart'; // <-- Add this package to pubspec.yaml

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
  double _indentQty = 0.0;
  final TextEditingController _issueQtyController = TextEditingController();

  bool _isLoading = true;

  // FIFO Stock entries for selected material
  List<Map<String, dynamic>> _matchingStockEntries = [];

  // Outgoing materials table data
  List<Map<String, dynamic>> _outgoingList = [];
  bool _isLoadingOutgoing = false;

  // Search feature
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadUser();
    _loadOutgoingList();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _issueQtyController.dispose();
    super.dispose();
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
    // Sort materials alphabetically by type-subtype
    materials.sort((a, b) {
      final aKey = (a['type'] ?? '') + '-' + (a['subtype'] ?? '');
      final bKey = (b['type'] ?? '') + '-' + (b['subtype'] ?? '');
      return aKey.toLowerCase().compareTo(bKey.toLowerCase());
    });
    setState(() {
      _jobs = List<Map<String, dynamic>>.from(
        jobs.where((job) => job['isFinal'] != true),
      );
      _materials = List<Map<String, dynamic>>.from(materials);
      _isLoading = false;
    });
  }

  Future<void> _loadOutgoingList() async {
    setState(() {
      _isLoadingOutgoing = true;
    });
    try {
      final outgoing = await ApiService.getOutgoingMaterials();
      // Sort the outgoing list by issued date (newest first)
      List<Map<String, dynamic>> sortedOutgoing =
          List<Map<String, dynamic>>.from(outgoing);
      sortedOutgoing.sort((a, b) {
        final aDate = a['out_time'] != null
            ? DateTime.tryParse(a['out_time'])
            : null;
        final bDate = b['out_time'] != null
            ? DateTime.tryParse(b['out_time'])
            : null;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate); // Newest to oldest
      });
      setState(() {
        _outgoingList = sortedOutgoing;
        _isLoadingOutgoing = false;
      });
    } catch (e) {
      setState(() {
        _outgoingList = [];
        _isLoadingOutgoing = false;
      });
    }
  }

  Future<void> _onMaterialSelected(Map<String, dynamic>? material) async {
    if (material == null || _selectedJob == null) return;
    setState(() {
      _selectedMaterial = material;
    });

    final stock = await ApiService.getStock(material['jobSpecific']);
    List<Map<String, dynamic>> matching = stock
        .where(
          (s) =>
              s['type'] == material['type'] &&
              s['subtype'] == material['subtype'] &&
              (material['jobSpecific'] != true ||
                  s['serialNo'] == _selectedJob!['serialNo']),
        )
        .toList()
        .cast<Map<String, dynamic>>();

    matching.sort((a, b) {
      if (a['entryDate'] != null && b['entryDate'] != null) {
        return DateTime.parse(
          b['entryDate'],
        ).compareTo(DateTime.parse(a['entryDate'])); // Newest to oldest
      }
      return 0;
    });

    final totalAvailable = matching.fold<double>(
      0.0,
      (sum, e) => sum + (double.tryParse(e['quantity'].toString()) ?? 0.0),
    );

    final indentData = await ApiService.getIndentsForJob(
      _selectedJob!['serialNo'],
    );
    final matchedIndent = indentData.firstWhere(
      (i) =>
          i['type'] == material['type'] &&
          i['subtype'] == material['subtype'] &&
          (material['jobSpecific'] != true ||
              i['serialNo'] == _selectedJob!['serialNo']),
      orElse: () => {'quantity': 0.0},
    );

    setState(() {
      _matchingStockEntries = matching;
      _availableQty = totalAvailable;
      _indentQty = (matchedIndent['quantity'] ?? 0).toDouble();
      _selectedIndent = matchedIndent;
    });
  }

  Future<void> _submitIssue() async {
    final issueQty = double.tryParse(_issueQtyController.text) ?? 0.0;
    if (_selectedJob == null || _selectedMaterial == null || issueQty <= 0)
      return;

    // Calculate 2% tolerance for indent quantity
    final double indentQtyWithTolerance = _indentQty * 1.02;

    // Validation: must not issue more than indentQtyWithTolerance and availableQty
    if (issueQty > indentQtyWithTolerance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot issue more than 2% above indent quantity (${indentQtyWithTolerance.toStringAsFixed(2)})',
          ),
        ),
      );
      return;
    }
    if (issueQty > _availableQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot issue more than available stock ($_availableQty)',
          ),
        ),
      );
      return;
    }

    double qtyRequired = issueQty;
    double totalIssued = 0;
    double weightedPriceSum = 0;
    List<Map<String, dynamic>> consumedStocks = [];
    for (var entry in _matchingStockEntries) {
      if (qtyRequired <= 0) break;
      double available = (double.tryParse(entry['quantity'].toString()) ?? 0.0);
      double price = (double.tryParse(entry['price'].toString()) ?? 0.0);
      double takeQty = min(qtyRequired, available);

      consumedStocks.add({
        ...entry,
        'consumedQty': takeQty,
        'consumedPrice': price,
      });

      weightedPriceSum += takeQty * price;
      totalIssued += takeQty;
      qtyRequired -= takeQty;

      final updateResult = await ApiService.updateStockQuantity(
        data: entry,
        quantity: takeQty,
        price: 0.0,
        editFlag: false,
      );
      if (updateResult != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stock update failed: $updateResult')),
        );
        return; // Exit early on error
      }
    }

    double weightedAvgPrice = totalIssued > 0
        ? weightedPriceSum / totalIssued
        : 0;

    final material = _selectedMaterial!;
    final data = {
      'serialNo': _selectedJob!['serialNo'],
      'material': material['type'] + ' - ' + material['subtype'],
      'type': material['type'],
      'subtype': material['subtype'],
      'price': weightedPriceSum / totalIssued,
      'issuedQty': totalIssued,
      'issuedValue': weightedPriceSum,
      'user_out': _username,
      'out_time': DateTime.now().toString(),
      'jobSpecific': material['jobSpecific'],
    };

    await ApiService.updateJobIndent(data: data);
    final uuid = Uuid().v4();

    final outgoingData = {
      'id': uuid,
      'serialNo': _selectedJob!['serialNo'],
      'material': material['type'] + ' - ' + material['subtype'],
      'type': material['type'],
      'subtype': material['subtype'],
      'issuedQty': totalIssued,
      'weightedAvgPrice': weightedAvgPrice,
      'issuedValue': totalIssued * weightedAvgPrice,
      'details': consumedStocks,
      'user_out': _username,
      'out_time': DateTime.now().toIso8601String(),
      'jobSpecific': material['jobSpecific'],
    };

    final result = await ApiService.saveOutgoingMaterial(outgoingData);
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material issued successfully!')),
      );
      _issueQtyController.clear();
      await _onMaterialSelected(material);
      await _loadOutgoingList();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $result')));
    }
  }

  Widget _buildOutgoingTable() {
    final columns = [
      'Job',
      'Material',
      'Issued Qty',
      'Unit Price',
      'Issued Value',
      'Issued By',
      'Issued On',
    ];

    if (_isLoadingOutgoing) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredOutgoingList = _outgoingList.where((entry) {
      final search = _searchQuery;
      if (search.isEmpty) return true;
      return (entry['serialNo'] ?? '').toString().toLowerCase().contains(
            search,
          ) ||
          (entry['material'] ?? '').toString().toLowerCase().contains(search) ||
          (entry['user_out'] ?? '').toString().toLowerCase().contains(search);
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Outgoing Material Entries",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search outgoing entries',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (filteredOutgoingList.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Text(
                "No outgoing material entries.",
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: columns
                    .map(
                      (c) => DataColumn(
                        label: Text(
                          c,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                    .toList(),
                rows: filteredOutgoingList.map((entry) {
                  return DataRow(
                    cells: [
                      DataCell(Text(entry['serialNo'] ?? '')),
                      DataCell(Text(entry['material'] ?? '')),
                      DataCell(Text('${entry['issuedQty'] ?? ''}')),
                      DataCell(
                        Text(
                          '₹${(entry['weightedAvgPrice'] ?? 0).toStringAsFixed(2)}',
                        ),
                      ),
                      DataCell(
                        Text(
                          '₹${(entry['issuedValue'] ?? 0).toStringAsFixed(2)}',
                        ),
                      ),
                      DataCell(Text(entry['user_out'] ?? '')),
                      DataCell(Text(entry['out_time'] ?? '')),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Prepare material dropdown items sorted and as a string for search
    final materialStringList = _materials
        .map((m) => '${m['type'] ?? ''} - ${m['subtype'] ?? ''}')
        .toList();

    // Calculate 2% tolerance for indent quantity
    final double indentQtyWithTolerance = _indentQty * 1.02;

    return Scaffold(
      appBar: AppBar(title: const Text("Issue Material to Job")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<Map<String, dynamic>>(
                        decoration: const InputDecoration(
                          labelText: 'Select Job',
                        ),
                        value: _selectedJob,
                        items: _jobs
                            .map(
                              (job) => DropdownMenuItem(
                                value: job,
                                child: Text(job['serialNo'] ?? 'Unknown'),
                              ),
                            )
                            .toList(),
                        onChanged: (val) async {
                          setState(() => _selectedJob = val);
                          if (_selectedMaterial != null) {
                            await _onMaterialSelected(_selectedMaterial);
                          }
                        },
                        validator: (val) =>
                            val == null ? 'Please select a job' : null,
                      ),
                      const SizedBox(height: 16),
                      // Updated Material Dropdown with search and alphabetic sort
                      DropdownSearch<String>(
                        items: materialStringList,
                        selectedItem: _selectedMaterial != null
                            ? '${_selectedMaterial!['type'] ?? ''} - ${_selectedMaterial!['subtype'] ?? ''}'
                            : null,
                        dropdownDecoratorProps: const DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            labelText: "Select Material",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        popupProps: const PopupProps.menu(
                          showSearchBox: true,
                          searchFieldProps: TextFieldProps(
                            decoration: InputDecoration(
                              hintText: "Search material...",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        validator: (val) =>
                            val == null ? 'Please select a material' : null,
                        onChanged: (val) async {
                          var mat = _materials.firstWhere(
                            (m) =>
                                '${m['type'] ?? ''} - ${m['subtype'] ?? ''}' ==
                                val,
                            orElse: () => {},
                          );
                          if (mat.isNotEmpty) {
                            await _onMaterialSelected(mat);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Available Qty (FIFO): $_availableQty'),
                      Text(
                        'Indent Qty: $_indentQty (Allowed upto ${indentQtyWithTolerance.toStringAsFixed(2)})',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _issueQtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
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
                          if (parsed > indentQtyWithTolerance)
                            return 'Cannot issue more than 2% above indent quantity (${indentQtyWithTolerance.toStringAsFixed(2)})';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      if ((_issueQtyController.text.isNotEmpty &&
                          double.tryParse(_issueQtyController.text) != null &&
                          double.tryParse(_issueQtyController.text)! > 0 &&
                          _matchingStockEntries.isNotEmpty))
                        Builder(
                          builder: (_) {
                            final reqQty = double.tryParse(
                              _issueQtyController.text,
                            )!;
                            double qtyLeft = reqQty;
                            List<Widget> batches = [];
                            for (var entry in _matchingStockEntries) {
                              if (qtyLeft <= 0) break;
                              final avail =
                                  (double.tryParse(
                                    entry['quantity'].toString(),
                                  ) ??
                                  0.0);
                              final take = min(qtyLeft, avail);
                              batches.add(
                                Text(
                                  'Take $take from batch @ ₹${entry['price']} (StockID: ${entry['id'] ?? entry['key']})',
                                ),
                              );
                              qtyLeft -= take;
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "FIFO Batches to be Consumed:",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                ...batches,
                              ],
                            );
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
                      ),
                      _buildOutgoingTable(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
