import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:math';
import 'dart:async';
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
  String? _initialError;
  bool _isLoadingSelection = false;
  bool _selectionReady = false;
  String? _selectionError;
  int _selectionRequest = 0;
  bool _isSubmitting = false;
  Map<String, dynamic>? _pendingOutgoingData;

  // FIFO Stock entries for selected material
  List<Map<String, dynamic>> _matchingStockEntries = [];

  // Outgoing materials table data
  List<Map<String, dynamic>> _outgoingList = [];
  bool _isLoadingOutgoing = false;
  int _outgoingRequest = 0;
  String? _outgoingError;

  // Search feature
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _outgoingSearchTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadUser();
    _loadOutgoingList();
    _searchController.addListener(() {
      final search = _searchController.text.trim();

      _outgoingSearchTimer?.cancel();
      _outgoingRequest++;
      setState(() {
        _searchQuery = search;
        _outgoingList = [];
        _outgoingError = null;
        _isLoadingOutgoing = true;
      });

      _outgoingSearchTimer = Timer(const Duration(milliseconds: 400), () {
        _loadOutgoingList(search: search);
      });
    });
  }

  @override
  void dispose() {
    _outgoingSearchTimer?.cancel();
    _searchController.dispose();
    _issueQtyController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _role = prefs.getString('role')?.toLowerCase() ?? 'user';
      _username = prefs.getString('username') ?? '';
    });
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _initialError = null;
    });
    try {
      final jobs = await ApiService.getJobs();
      final materials = await ApiService.getMaterials();
      // Sort materials alphabetically by type-subtype
      materials.sort((a, b) {
        final aKey = (a['type'] ?? '') + '-' + (a['subtype'] ?? '');
        final bKey = (b['type'] ?? '') + '-' + (b['subtype'] ?? '');
        return aKey.toLowerCase().compareTo(bKey.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _jobs = List<Map<String, dynamic>>.from(
          jobs.where((job) => job['isFinal'] != true),
        );
        _materials = List<Map<String, dynamic>>.from(materials);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _initialError = 'Could not load jobs and materials: $error';
      });
    }
  }

  Future<void> _loadOutgoingList({String search = ''}) async {
    if (!mounted) return;
    final request = ++_outgoingRequest;
    setState(() {
      _isLoadingOutgoing = true;
      _outgoingError = null;
    });

    try {
      final outgoing = await ApiService.getOutgoingMaterials(search: search);

      // Backend already returns newest first using the indexed out_time.
      final outgoingList = List<Map<String, dynamic>>.from(outgoing);

      if (!mounted || request != _outgoingRequest) return;

      setState(() {
        _outgoingList = outgoingList;
        _isLoadingOutgoing = false;
      });
    } catch (e) {
      if (!mounted || request != _outgoingRequest) return;

      setState(() {
        _outgoingList = [];
        _isLoadingOutgoing = false;
        _outgoingError = 'Could not load outgoing entries: $e';
      });
    }
  }

  Future<void> _onMaterialSelected(Map<String, dynamic>? material) async {
    final request = ++_selectionRequest;
    final serialNo = _selectedJob?['serialNo'];
    setState(() {
      _selectedMaterial = material;
      _selectionReady = false;
      _selectionError = null;
      _matchingStockEntries = [];
      _availableQty = 0;
      _indentQty = 0;
      _selectedIndent = null;
      _issueQtyController.clear();
      _isLoadingSelection = material != null && serialNo != null;
    });
    if (material == null || serialNo == null) return;

    try {
      final stock = await ApiService.getStock(material['jobSpecific']);
      if (!mounted || request != _selectionRequest) return;
      List<Map<String, dynamic>> matching = stock
          .where(
            (s) =>
                s['type'] == material['type'] &&
                s['subtype'] == material['subtype'] &&
                (material['jobSpecific'] != true || s['serialNo'] == serialNo),
          )
          .toList()
          .cast<Map<String, dynamic>>();

      matching.sort((a, b) {
        final dateA = _receiptDate(a);
        final dateB = _receiptDate(b);
        final order = dateA == null
            ? (dateB == null ? 0 : 1)
            : (dateB == null ? -1 : dateA.compareTo(dateB));
        return order != 0
            ? order
            : a['id'].toString().compareTo(b['id'].toString());
      });

      final totalAvailable = matching.fold<double>(
        0.0,
        (sum, e) => sum + (double.tryParse(e['quantity'].toString()) ?? 0.0),
      );

      final indentData = await ApiService.getIndentsForJob(serialNo);
      if (!mounted || request != _selectionRequest) return;
      final matchedIndent = indentData.firstWhere(
        (i) =>
            i['type'] == material['type'] &&
            i['subtype'] == material['subtype'] &&
            (material['jobSpecific'] != true || i['serialNo'] == serialNo),
        orElse: () => {'quantity': 0.0},
      );

      setState(() {
        _matchingStockEntries = matching;
        _availableQty = totalAvailable;
        _indentQty = (matchedIndent['quantity'] ?? 0).toDouble();
        _selectedIndent = matchedIndent;
        _isLoadingSelection = false;
        _selectionReady = true;
      });
    } catch (error) {
      if (!mounted || request != _selectionRequest) return;
      setState(() {
        _isLoadingSelection = false;
        _selectionError = 'Could not load stock and indent: $error';
      });
    }
  }

  DateTime? _receiptDate(Map<String, dynamic> lot) {
    final date = DateTime.tryParse(lot['entryDate']?.toString().trim() ?? '');
    if (date == null || date.isUtc) return date;
    // Older receipts store local Indian time without an offset.
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    ).subtract(const Duration(hours: 5, minutes: 30));
  }

  List<Map<String, dynamic>> _allocateLots(double quantity) {
    final lots = <Map<String, dynamic>>[];
    if (!quantity.isFinite || quantity <= 0) return lots;
    var remaining = quantity;
    for (final entry in _matchingStockEntries) {
      if (remaining <= 0) break;
      final available = double.tryParse(entry['quantity'].toString()) ?? 0.0;
      if (!available.isFinite || available <= 0) continue;
      final take = min(remaining, available);
      lots.add({
        ...entry,
        'consumedQty': take,
        'consumedPrice': double.tryParse(entry['price'].toString()) ?? 0.0,
      });
      remaining -= take;
    }
    return lots;
  }

  Future<void> _submitIssue() async {
    if (_isSubmitting) return;
    if (_pendingOutgoingData != null) {
      await _savePendingIssue();
      return;
    }
    final issueQty = double.tryParse(_issueQtyController.text) ?? 0.0;
    if (!_selectionReady ||
        _selectedJob == null ||
        _selectedMaterial == null ||
        !issueQty.isFinite ||
        issueQty <= 0)
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

    final consumedStocks = _allocateLots(issueQty);
    if (consumedStocks.isEmpty) return;
    final issuedValue = consumedStocks.fold<double>(
      0,
      (sum, lot) =>
          sum +
          (lot['consumedQty'] as double) * (lot['consumedPrice'] as double),
    );

    final material = _selectedMaterial!;
    final uuid = Uuid().v4();

    final outgoingData = {
      'id': uuid,
      'serialNo': _selectedJob!['serialNo'],
      'material': material['type'] + ' - ' + material['subtype'],
      'type': material['type'],
      'subtype': material['subtype'],
      'issuedQty': issueQty,
      'weightedAvgPrice': issuedValue / issueQty,
      'issuedValue': issuedValue,
      'details': consumedStocks,
      'user_out': _username,
      'out_time': DateTime.now().toIso8601String(),
      'jobSpecific': material['jobSpecific'],
    };

    _pendingOutgoingData = outgoingData;
    await _savePendingIssue();
  }

  Future<void> _savePendingIssue() async {
    setState(() => _isSubmitting = true);
    try {
      await ApiService.saveOutgoingMaterial(_pendingOutgoingData!);
      _pendingOutgoingData = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material issued successfully!')),
      );
      _issueQtyController.clear();
      await _onMaterialSelected(_selectedMaterial);
      await _loadOutgoingList(search: _searchQuery);
    } catch (error) {
      if (error is OutgoingIssueRejected) _pendingOutgoingData = null;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
      if (error is OutgoingIssueRejected) {
        await _onMaterialSelected(_selectedMaterial);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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

    final filteredOutgoingList = _outgoingList;

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Outgoing Material Entries",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          if (_isLoadingOutgoing) const LinearProgressIndicator(),
          if (_outgoingError != null)
            Row(
              children: [
                Expanded(child: Text(_outgoingError!)),
                IconButton(
                  tooltip: 'Retry outgoing entries',
                  onPressed: () => _loadOutgoingList(search: _searchQuery),
                  icon: const Icon(Icons.refresh),
                ),
              ],
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
          if (!_isLoadingOutgoing &&
              _outgoingError == null &&
              filteredOutgoingList.isEmpty)
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
          : _initialError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_initialError!),
                  IconButton(
                    tooltip: 'Retry jobs and materials',
                    onPressed: _loadInitialData,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownSearch<Map<String, dynamic>>(
                        key: const Key('outgoing-job'),
                        enabled: !_isSubmitting && _pendingOutgoingData == null,
                        items: _jobs,

                        selectedItem: _selectedJob,

                        itemAsString: (job) {
                          final serialNo = job['serialNo'] ?? 'Unknown Job';
                          final kva = job['kva'] ?? job['KVA'] ?? '';
                          final purchaser = job['purchaserName'] ?? '';
                          final tappingType = job['tappingType'] ?? '';
                          final hvVolt = job['hvVoltage'] ?? '';
                          final lvVolt = job['lvVoltage'] ?? '';

                          return [
                            serialNo,
                            if (kva.toString().isNotEmpty) '${kva} kVA',
                            if (tappingType.toString().isNotEmpty) tappingType,
                            if (hvVolt.toString().isNotEmpty) '${hvVolt} V',
                            if (lvVolt.toString().isNotEmpty) '${lvVolt} V',
                            if (purchaser.toString().isNotEmpty) purchaser,
                          ].join(' - ');
                        },

                        popupProps: PopupProps.menu(
                          showSearchBox: true,
                          searchFieldProps: TextFieldProps(
                            decoration: const InputDecoration(
                              hintText: 'Search job, KVA, purchaser...',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),

                        dropdownDecoratorProps: const DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            labelText: 'Select Job',
                            border: OutlineInputBorder(),
                          ),
                        ),

                        onChanged: (val) async {
                          setState(() {
                            _selectedJob = val;
                          });

                          await _onMaterialSelected(_selectedMaterial);
                        },

                        validator: (val) {
                          return val == null ? 'Please select a job' : null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Updated Material Dropdown with search and alphabetic sort
                      DropdownSearch<String>(
                        key: const Key('outgoing-material'),
                        enabled: !_isSubmitting && _pendingOutgoingData == null,
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
                          await _onMaterialSelected(mat.isEmpty ? null : mat);
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_isLoadingSelection) const LinearProgressIndicator(),
                      if (_selectionError != null)
                        Row(
                          children: [
                            Expanded(child: Text(_selectionError!)),
                            IconButton(
                              tooltip: 'Retry stock and indent',
                              onPressed: () =>
                                  _onMaterialSelected(_selectedMaterial),
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                      Text('Available Qty (FIFO): $_availableQty'),
                      Text(
                        'Indent Qty: $_indentQty (Allowed upto ${indentQtyWithTolerance.toStringAsFixed(2)})',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _issueQtyController,
                        onChanged: (_) => setState(() {}),
                        enabled:
                            _selectionReady &&
                            !_isSubmitting &&
                            _pendingOutgoingData == null,
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
                          if (parsed == null || !parsed.isFinite)
                            return 'Enter valid number';
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
                            final batches = _allocateLots(reqQty);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "FIFO Batches to be Consumed:",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                for (final lot in batches)
                                  Text(
                                    'Take ${lot['consumedQty']} from batch @ ₹${lot['price']} (StockID: ${lot['id']})',
                                  ),
                              ],
                            );
                          },
                        ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed:
                            _isSubmitting ||
                                (!_selectionReady &&
                                    _pendingOutgoingData == null)
                            ? null
                            : () {
                                if (_pendingOutgoingData != null ||
                                    _formKey.currentState!.validate()) {
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
