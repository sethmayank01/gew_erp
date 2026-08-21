import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'dart:convert';

class StockViewScreen extends StatefulWidget {
  const StockViewScreen({super.key});

  @override
  State<StockViewScreen> createState() => _StockViewScreenState();
}

class _StockViewScreenState extends State<StockViewScreen> {
  List<Map<String, dynamic>> _generalStock = [];
  List<Map<String, dynamic>> _jobStock = [];
  List<String> _jobNumbers = [];
  Map<String, Map<String, dynamic>> _allIndentStocks = {};
  Map<String, double> _indentQtyMap = {};
  String _role = 'user';
  bool _isLoading = false;
  Map<String, bool> _expandedGeneralKeys = {};
  Map<String, bool> _expandedJobKeys = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _indentSortByValue = true;
  bool _indentSortAsc = true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    await _loadUser();
    await _loadStock();
    await _loadJobs();
    await _loadIndentQtys();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _role = prefs.getString('role')?.toLowerCase() ?? 'user';
    });
  }

  Future<void> _loadStock() async {
    setState(() => _isLoading = true);
    final general = await ApiService.getStock(false);
    final job = await ApiService.getStock(true);

    setState(() {
      _generalStock = List<Map<String, dynamic>>.from(general);
      _jobStock = List<Map<String, dynamic>>.from(job);
    });
  }
  /*
  Future<void> _loadJobs() async {
    final jobs = await ApiService.getOpenJobs();
    Map<String, Map<String, dynamic>> jobStockData = {};

    for (var job in jobs) {
      final jobNo = job['serialNo'].toString();
      final purchaserName = job['purchaserName']?.toString() ?? '';
      final kva = job['kva']?.toString() ?? '';
      final tappingType = job['tappingType']?.toString() ?? '';
      final hvVolts = job['hvVoltage']?.toString() ?? '';
      final lvVolts = job['lvVoltage']?.toString() ?? '';
      final indents = await ApiService.getIndentsForJob(jobNo);

      jobStockData[jobNo] = {
        'purchaserName': purchaserName,
        'kVA': kva,
        'tappingType': tappingType,
        'hvVoltage': hvVolts,
        'lvVoltage': lvVolts,
        'entries': List<Map<String, dynamic>>.from(indents),
      };
    }

    setState(() {
      _jobNumbers = jobStockData.keys.toList();
      _allIndentStocks = jobStockData;
    });
  }
  */

  Future<void> _loadJobs() async {
    try {
      final jobs = await ApiService.getOpenJobIndents();

      Map<String, Map<String, dynamic>> jobStockData = {};

      for (final job in jobs) {
        final jobNo = job['serialNo']?.toString() ?? '';

        if (jobNo.isEmpty) continue;

        jobStockData[jobNo] = {
          'purchaserName': job['purchaserName']?.toString() ?? '',

          'kVA': job['kVA']?.toString() ?? '',

          'tappingType': job['tappingType']?.toString() ?? '',

          'hvVoltage': job['hvVoltage']?.toString() ?? '',

          'lvVoltage': job['lvVoltage']?.toString() ?? '',

          'entries': List<Map<String, dynamic>>.from(job['entries'] ?? []),
        };
      }

      if (!mounted) return;

      setState(() {
        _jobNumbers = jobStockData.keys.toList();
        _allIndentStocks = jobStockData;
      });
    } catch (e) {
      print('Error loading jobs: $e');

      if (!mounted) return;

      setState(() {
        _allIndentStocks = {};
      });
    }
  }

  Future<void> _loadIndentQtys() async {
    try {
      final rawList = await ApiService.getIndentStockList();
      Map<String, double> qtyMap = {};
      for (var row in rawList) {
        if (row.length < 2) continue;
        final key = row[0] as String;
        final jsonStr = row[1] as String;
        final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;
        final quantity = (jsonMap['indentQuantity'] ?? 0.0).toDouble();
        qtyMap[key] = quantity;
      }
      setState(() {
        _indentQtyMap = qtyMap;
      });
    } catch (e) {
      setState(() {
        _indentQtyMap = {};
      });
    }
    setState(() => _isLoading = false);
  }

  Map<String, Map<String, dynamic>> _groupGeneralStock() {
    Map<String, Map<String, dynamic>> grouped = {};
    for (var entry in _generalStock) {
      final key = '${entry['type']} - ${entry['subtype']}';
      final qty = double.tryParse(entry['quantity'].toString()) ?? 0.0;
      final price = double.tryParse(entry['price'].toString()) ?? 0.0;
      if (!grouped.containsKey(key)) {
        grouped[key] = {
          'key': key,
          'type': entry['type'],
          'subtype': entry['subtype'],
          'quantity': qty,
          'priceSum': price * qty,
          'entries': [entry],
        };
      } else {
        grouped[key]!['quantity'] += qty;
        grouped[key]!['priceSum'] += price * qty;
        grouped[key]!['entries'].add(entry);
      }
    }
    grouped.forEach((key, value) {
      double totalQty = value['quantity'];
      double totalPriceSum = value['priceSum'];
      value['weightedPrice'] = totalQty != 0 ? totalPriceSum / totalQty : 0.0;
      value['finalValue'] = totalQty * value['weightedPrice'];
    });
    return grouped;
  }

  Map<String, Map<String, dynamic>> _groupJobStock() {
    Map<String, Map<String, dynamic>> grouped = {};
    for (var entry in _jobStock) {
      final key =
          '${entry['type']} - ${entry['subtype']} - ${entry['serialNo']}';
      final qty = double.tryParse(entry['quantity'].toString()) ?? 0.0;
      final price = double.tryParse(entry['price'].toString()) ?? 0.0;
      if (!grouped.containsKey(key)) {
        grouped[key] = {
          'key': key,
          'type': entry['type'],
          'subtype': entry['subtype'],
          'serialNo': entry['serialNo'],
          'quantity': qty,
          'priceSum': price * qty,
          'entries': [entry],
        };
      } else {
        grouped[key]!['quantity'] += qty;
        grouped[key]!['priceSum'] += price * qty;
        grouped[key]!['entries'].add(entry);
      }
    }
    grouped.forEach((key, value) {
      double totalQty = value['quantity'];
      double totalPriceSum = value['priceSum'];
      value['weightedPrice'] = totalQty != 0 ? totalPriceSum / totalQty : 0.0;
      value['finalValue'] = totalQty * value['weightedPrice'];
    });
    return grouped;
  }

  Future<void> _deleteStockEntry(
    Map<String, dynamic> entry,
    bool isJobStock,
  ) async {
    await ApiService.removeStock(data: entry);
    setState(() {
      if (isJobStock) {
        _jobStock.remove(entry);
      } else {
        _generalStock.remove(entry);
      }
    });
  }

  Future<void> _editStockEntry(
    Map<String, dynamic> entry,
    bool isJobStock,
  ) async {
    final qtyController = TextEditingController(
      text: entry['quantity']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: entry['price']?.toString() ?? '',
    );
    bool updated = false;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Stock Entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: qtyController,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: priceController,
              decoration: const InputDecoration(labelText: 'Price'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newQty = double.tryParse(qtyController.text) ?? 0.0;
              final newPrice = double.tryParse(priceController.text) ?? 0.0;
              Map<String, dynamic> updatedEntry = Map.of(entry);
              updatedEntry['quantity'] = newQty;
              updatedEntry['price'] = newPrice;
              final result = await ApiService.updateStockQuantity(
                data: updatedEntry,
                quantity: newQty,
                price: newPrice,
                editFlag: true,
              );
              if (result == true) {
                setState(() {
                  entry['quantity'] = newQty;
                  entry['price'] = newPrice;
                });
                updated = true;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Stock entry updated')),
                );
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(result.toString())));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated) {
      await _loadStock();
      await _loadJobs();
      await _loadIndentQtys();
    }
  }

  Widget _buildGroupedStockSection({
    required String sectionTitle,
    required Map<String, Map<String, dynamic>> grouped,
    required bool isJobStock,
    required Map<String, bool> expandedKeys,
    required void Function(String) onToggleExpand,
  }) {
    double total = grouped.values.fold<double>(
      0.0,
      (a, b) => a + (b['finalValue'] as double),
    );

    return ExpansionTile(
      title: Text(
        "$sectionTitle (Total ₹${total.toStringAsFixed(2)})",
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      children: [
        ...grouped.values.map((group) {
          final isExpanded = expandedKeys[group['key']] ?? false;
          final indentQty = _indentQtyMap[group['key']] ?? 0.0;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
            child: Column(
              children: [
                ListTile(
                  title: isJobStock
                      ? Text(
                          '${group['type']} - ${group['subtype']} - ${group['serialNo']}',
                        )
                      : Text('${group['type']} - ${group['subtype']}'),
                  subtitle: Text(
                    'Quantity: ${group['quantity'].toStringAsFixed(2)}   '
                    'Weighted Price: ₹${group['weightedPrice'].toStringAsFixed(2)}   '
                    'Final Value: ₹${group['finalValue'].toStringAsFixed(2)}   '
                    'Indent Qty: ${indentQty.toStringAsFixed(2)}',
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onPressed: () => onToggleExpand(group['key']),
                  ),
                  onTap: () => onToggleExpand(group['key']),
                ),
                if (isExpanded)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Entries:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        ...(() {
                          final entries = group['entries'];
                          List<Map<String, dynamic>> sortedEntries =
                              (entries is List)
                              ? entries.cast<Map<String, dynamic>>()
                              : <Map<String, dynamic>>[];

                          sortedEntries.sort((a, b) {
                            final aDate = a['entryDate'] != null
                                ? DateTime.parse(a['entryDate'])
                                : DateTime(1970);
                            final bDate = b['entryDate'] != null
                                ? DateTime.parse(b['entryDate'])
                                : DateTime(1970);
                            return bDate.compareTo(aDate);
                          });

                          return sortedEntries.map<Widget>((entry) {
                            final qty =
                                double.tryParse(entry['quantity'].toString()) ??
                                0.0;
                            final price =
                                double.tryParse(entry['price'].toString()) ??
                                0.0;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 0,
                              ),
                              title: Row(
                                children: [
                                  Text('Qty: ${qty.toStringAsFixed(2)}'),
                                  const SizedBox(width: 6),
                                  Text('Price: ₹${price.toStringAsFixed(2)}'),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Value: ₹${(qty * price).toStringAsFixed(2)}',
                                  ),
                                ],
                              ),
                              subtitle: entry['note'] != null
                                  ? Text('Note: ${entry['note']}')
                                  : null,
                              trailing: (_role == 'admin')
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                          ),
                                          onPressed: () => _editStockEntry(
                                            entry,
                                            isJobStock,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () async {
                                            final confirm =
                                                await showDialog<bool>(
                                                  context: context,
                                                  builder: (context) =>
                                                      AlertDialog(
                                                        title: const Text(
                                                          "Confirm Deletion",
                                                        ),
                                                        content: const Text(
                                                          "Delete this entry?",
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  context,
                                                                ).pop(false),
                                                            child: const Text(
                                                              "Cancel",
                                                            ),
                                                          ),
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  context,
                                                                ).pop(true),
                                                            child: const Text(
                                                              "Delete",
                                                              style: TextStyle(
                                                                color:
                                                                    Colors.red,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                );
                                            if (confirm == true) {
                                              await _deleteStockEntry(
                                                entry,
                                                isJobStock,
                                              );
                                            }
                                          },
                                        ),
                                      ],
                                    )
                                  : null,
                            );
                          }).toList();
                        })(),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildIndentList() {
    List<Map<String, dynamic>> jobSummary = [];

    final q = _searchQuery.trim().toLowerCase();

    for (var jobNo in _jobNumbers) {
      final jobData = _allIndentStocks[jobNo];

      if (jobData == null) continue;

      final customer = jobData['purchaserName']?.toString() ?? '';
      final kva = jobData['kVA']?.toString() ?? '';
      final tappingType = jobData['tappingType']?.toString() ?? '';
      final hvVoltage = jobData['hvVoltage']?.toString() ?? '';
      final lvVoltage = jobData['lvVoltage']?.toString() ?? '';

      // Apply search filter to Indent Stock
      if (q.isNotEmpty) {
        final matches =
            jobNo.toLowerCase().contains(q) ||
            customer.toLowerCase().contains(q) ||
            kva.toLowerCase().contains(q) ||
            tappingType.toLowerCase().contains(q) ||
            hvVoltage.toLowerCase().contains(q) ||
            lvVoltage.toLowerCase().contains(q);

        if (!matches) {
          continue;
        }
      }

      final entries =
          (jobData['entries'] as List?)?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[];

      double totalValue = 0.0;

      for (var entry in entries) {
        final qty =
            double.tryParse(entry['issuedQty']?.toString() ?? '0') ?? 0.0;

        final price = double.tryParse(entry['price']?.toString() ?? '0') ?? 0.0;

        totalValue += qty * price;
      }

      jobSummary.add({
        'job': jobNo,
        'customer': customer,
        'kva': kva,
        'tappingType': tappingType,
        'hvVoltage': hvVoltage,
        'lvVoltage': lvVoltage,
        'value': totalValue,
      });
    }
    // Sorting
    if (_indentSortByValue) {
      jobSummary.sort(
        (a, b) => _indentSortAsc
            ? a['value'].compareTo(b['value'])
            : b['value'].compareTo(a['value']),
      );
    } else {
      jobSummary.sort(
        (a, b) => _indentSortAsc
            ? a['job'].compareTo(b['job'])
            : b['job'].compareTo(a['job']),
      );
    }

    final totalIndentValue = jobSummary.fold(
      0.0,
      (a, b) => a + (b['value'] as double),
    );

    return ExpansionTile(
      title: Text(
        "Indent Stock for Non-Finalized Jobs (Total ₹${totalIndentValue.toStringAsFixed(2)})",
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _indentSortByValue = false;
                          _indentSortAsc = !_indentSortAsc;
                        });
                      },
                      child: Row(
                        children: [
                          const Text(
                            "Job No.",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            !_indentSortByValue
                                ? (_indentSortAsc
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward)
                                : Icons.unfold_more,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      "Customer",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      "kVA",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      "Tapping Type",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      "HT Volts",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      "LT Volts",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _indentSortByValue = true;
                          _indentSortAsc = !_indentSortAsc;
                        });
                      },
                      child: Row(
                        children: [
                          const Text(
                            "Issued Value",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _indentSortByValue
                                ? (_indentSortAsc
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward)
                                : Icons.unfold_more,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(),
              ...jobSummary.map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(entry['job'])),
                      Expanded(child: Text(entry['customer'] ?? '')),
                      Expanded(child: Text(entry['kva'] ?? '')),
                      Expanded(child: Text(entry['tappingType'] ?? '')),
                      Expanded(child: Text(entry['hvVoltage'] ?? '')),
                      Expanded(child: Text(entry['lvVoltage'] ?? '')),
                      Expanded(
                        child: Text(
                          "₹${(entry['value'] as double).toStringAsFixed(2)}",
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, Map<String, dynamic>> _filterGrouped(
    Map<String, Map<String, dynamic>> grouped,
  ) {
    if (_searchQuery.isEmpty) return grouped;
    final q = _searchQuery.toLowerCase();
    return Map.fromEntries(
      grouped.entries.where(
        (e) =>
            e.value['type'].toString().toLowerCase().contains(q) ||
            e.value['subtype'].toString().toLowerCase().contains(q) ||
            (e.value['serialNo']?.toString().toLowerCase().contains(q) ??
                false) ||
            e.key.toLowerCase().contains(q),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupedGeneral = _filterGrouped(_groupGeneralStock());
    final groupedJob = _filterGrouped(_groupJobStock());
    final generalTotal = groupedGeneral.values.fold<double>(
      0.0,
      (a, b) => a + (b['finalValue'] as double),
    );
    final jobTotal = groupedJob.values.fold<double>(
      0.0,
      (a, b) => a + (b['finalValue'] as double),
    );

    // Calculate indent total
    double indentTotal = 0.0;
    for (var jobNo in _jobNumbers) {
      final jobData = _allIndentStocks[jobNo];
      if (jobData != null) {
        final entries = jobData['entries'] as List<Map<String, dynamic>>;
        for (var entry in entries) {
          final qty = entry['issuedQty'] ?? 0.0;
          final price = entry['price'] ?? 0.0;
          indentTotal += qty * price;
        }
      }
    }

    final grandTotal = generalTotal + jobTotal + indentTotal;

    return Scaffold(
      appBar: AppBar(title: const Text('Stock View')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- NEW TOTAL SUMMARY SECTION ---
                  Card(
                    //color: Colors.blueGrey.shade50,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Total Stock: ₹${grandTotal.toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ----------------------------------
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                  const SizedBox(height: 10),
                  _buildGroupedStockSection(
                    sectionTitle: 'General Stock',
                    grouped: groupedGeneral,
                    isJobStock: false,
                    expandedKeys: _expandedGeneralKeys,
                    onToggleExpand: (key) {
                      setState(() {
                        _expandedGeneralKeys[key] =
                            !(_expandedGeneralKeys[key] ?? false);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildGroupedStockSection(
                    sectionTitle: 'Job Stock',
                    grouped: groupedJob,
                    isJobStock: true,
                    expandedKeys: _expandedJobKeys,
                    onToggleExpand: (key) {
                      setState(() {
                        _expandedJobKeys[key] =
                            !(_expandedJobKeys[key] ?? false);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildIndentList(),
                ],
              ),
            ),
    );
  }
}
