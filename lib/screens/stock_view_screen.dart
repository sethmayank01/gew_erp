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
  Map<String, List<Map<String, dynamic>>> _allIndentStocks = {};
  Map<String, double> _indentQtyMap = {}; // New: stores indentQty per group key
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
    await _loadIndentQtys(); // new
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

  Future<void> _loadJobs() async {
    final jobs = await ApiService.getOpenJobs();
    final nonFinalizedJobs =
        jobs.map<String>((job) => job['serialNo'].toString()).toList();
    setState(() => _jobNumbers = nonFinalizedJobs);
    for (var jobNo in nonFinalizedJobs) {
      final indents = await ApiService.getIndentsForJob(jobNo);
      _allIndentStocks[jobNo] = List<Map<String, dynamic>>.from(indents);
    }
  }

  Future<void> _loadIndentQtys() async {
    try {
      // This will be List<List<dynamic>>
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
      Map<String, dynamic> entry, bool isJobStock) async {
    await ApiService.removeStock(data: entry);
    setState(() {
      if (isJobStock) {
        _jobStock.remove(entry);
      } else {
        _generalStock.remove(entry);
      }
    });
  }

  Widget _buildGroupedStockSection({
    required String sectionTitle,
    required Map<String, Map<String, dynamic>> grouped,
    required bool isJobStock,
    required Map<String, bool> expandedKeys,
    required void Function(String) onToggleExpand,
  }) {
    double total = grouped.values
        .fold<double>(0.0, (a, b) => a + (b['finalValue'] as double));
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
                          '${group['type']} - ${group['subtype']} - ${group['serialNo']}')
                      : Text('${group['type']} - ${group['subtype']}'),
                  subtitle: Text(
                    // Indent Qty is now in the same row as Final Value
                    'Quantity: ${group['quantity'].toStringAsFixed(2)}   '
                    'Weighted Price: ₹${group['weightedPrice'].toStringAsFixed(2)}   '
                    'Final Value: ₹${group['finalValue'].toStringAsFixed(2)}   '
                    'Indent Qty: ${indentQty.toStringAsFixed(2)}',
                  ),
                  trailing: IconButton(
                    icon: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more),
                    onPressed: () => onToggleExpand(group['key']),
                  ),
                  onTap: () => onToggleExpand(group['key']),
                ),
                if (isExpanded)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Entries:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        ...group['entries'].map<Widget>((entry) {
                          final qty =
                              double.tryParse(entry['quantity'].toString()) ??
                                  0.0;
                          final price =
                              double.tryParse(entry['price'].toString()) ?? 0.0;
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 0),
                            title: Row(
                              children: [
                                Text('Qty: ${qty.toStringAsFixed(2)}'),
                                const SizedBox(width: 6),
                                Text('Price: ₹${price.toStringAsFixed(2)}'),
                                const SizedBox(width: 6),
                                Text(
                                    'Value: ₹${(qty * price).toStringAsFixed(2)}'),
                              ],
                            ),
                            subtitle: entry['note'] != null
                                ? Text('Note: ${entry['note']}')
                                : null,
                            trailing: (_role == 'admin')
                                ? IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text("Confirm Deletion"),
                                          content:
                                              const Text("Delete this entry?"),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .pop(false),
                                              child: const Text("Cancel"),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .pop(true),
                                              child: const Text("Delete",
                                                  style: TextStyle(
                                                      color: Colors.red)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await _deleteStockEntry(
                                            entry, isJobStock);
                                      }
                                    },
                                  )
                                : null,
                          );
                        }).toList(),
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

  double _calculateTotalIndentAllJobs() {
    double total = 0.0;
    _allIndentStocks.forEach((jobNo, entries) {
      for (var entry in entries) {
        final qty = entry['issuedQty'] ?? 0.0;
        final price = entry['price'] ?? 0.0;
        total += qty * price;
      }
    });
    return total;
  }

  Widget _buildIndentList() {
    Map<String, double> jobIssuedValues = {};
    for (var job in _jobNumbers) {
      jobIssuedValues[job] = 0.0;
    }
    for (var job in _jobNumbers) {
      final indents = _allIndentStocks[job] ?? [];
      for (var entry in indents) {
        final qty = entry['issuedQty'] ?? 0.0;
        final price = entry['price'] ?? 0.0;
        jobIssuedValues[job] = jobIssuedValues[job]! + qty * price;
      }
    }
    List<Map<String, dynamic>> jobSummary = jobIssuedValues.entries
        .map((e) => {'job': e.key, 'value': e.value})
        .toList();
    if (_indentSortByValue) {
      jobSummary.sort((a, b) => _indentSortAsc
          ? a['value'].compareTo(b['value'])
          : b['value'].compareTo(a['value']));
    } else {
      jobSummary.sort((a, b) => _indentSortAsc
          ? a['job'].compareTo(b['job'])
          : b['job'].compareTo(a['job']));
    }

    return ExpansionTile(
      title: Text(
        "Indent Stock for Non-Finalized Jobs (Total ₹${jobIssuedValues.values.fold(0.0, (a, b) => a + b).toStringAsFixed(2)})",
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
                          const Text("Job No.",
                              style: TextStyle(fontWeight: FontWeight.bold)),
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
                          const Text("Issued Value",
                              style: TextStyle(fontWeight: FontWeight.bold)),
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
              ...jobSummary.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(entry['job'])),
                      Expanded(
                          child: Text(
                              "₹${(entry['value'] as double).toStringAsFixed(2)}")),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, Map<String, dynamic>> _filterGrouped(
      Map<String, Map<String, dynamic>> grouped) {
    if (_searchQuery.isEmpty) return grouped;
    final q = _searchQuery.toLowerCase();
    return Map.fromEntries(grouped.entries.where((e) =>
        e.value['type'].toString().toLowerCase().contains(q) ||
        e.value['subtype'].toString().toLowerCase().contains(q) ||
        (e.value['serialNo']?.toString().toLowerCase().contains(q) ?? false) ||
        e.key.toLowerCase().contains(q)));
  }

  @override
  Widget build(BuildContext context) {
    final groupedGeneral = _filterGrouped(_groupGeneralStock());
    final groupedJob = _filterGrouped(_groupJobStock());
    final indentTotal = _calculateTotalIndentAllJobs();
    final generalTotal = groupedGeneral.values
        .fold<double>(0.0, (a, b) => a + (b['finalValue'] as double));
    final jobTotal = groupedJob.values
        .fold<double>(0.0, (a, b) => a + (b['finalValue'] as double));
    final grandTotal = generalTotal + jobTotal + indentTotal;

    return Scaffold(
      appBar: AppBar(title: const Text('Stock Overview')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadStock();
                await _loadIndentQtys();
              },
              child: ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: "Search stock...",
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text("Grand Total"),
                      subtitle: Text("₹${grandTotal.toStringAsFixed(2)}",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildGroupedStockSection(
                    sectionTitle: "General Stock",
                    grouped: groupedGeneral,
                    isJobStock: false,
                    expandedKeys: _expandedGeneralKeys,
                    onToggleExpand: (key) => setState(() {
                      _expandedGeneralKeys[key] =
                          !(_expandedGeneralKeys[key] ?? false);
                    }),
                  ),
                  const SizedBox(height: 10),
                  _buildGroupedStockSection(
                    sectionTitle: "Job-Specific Stock",
                    grouped: groupedJob,
                    isJobStock: true,
                    expandedKeys: _expandedJobKeys,
                    onToggleExpand: (key) => setState(() {
                      _expandedJobKeys[key] = !(_expandedJobKeys[key] ?? false);
                    }),
                  ),
                  const SizedBox(height: 10),
                  _buildIndentList(),
                  const SizedBox(height: 10),
                ],
              ),
            ),
    );
  }
}
