import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class IndentViewScreen extends StatefulWidget {
  const IndentViewScreen({super.key});

  @override
  State<IndentViewScreen> createState() => _IndentViewScreenState();
}

class _IndentViewScreenState extends State<IndentViewScreen> {
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _indents = [];
  List<Map<String, dynamic>> _materials = [];
  Map<String, dynamic>? _selectedJob;
  bool _isLoading = false;

  // The only valid groups, all uppercase for case-insensitive matching
  final List<String> _groups = ['CCA', 'TANKING', 'MOUNTING', 'ACC', 'SUNDRY'];

  @override
  void initState() {
    super.initState();
    _loadMaterialsAndJobs();
  }

  Future<void> _loadMaterialsAndJobs() async {
    setState(() => _isLoading = true);
    await _loadMaterials();
    await _loadJobs();
    setState(() => _isLoading = false);
  }

  Future<void> _loadMaterials() async {
    try {
      final materials = await ApiService.getMaterials();
      _materials = List<Map<String, dynamic>>.from(materials);
    } catch (e) {
      _materials = [];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading materials: $e')));
    }
  }

  String _getCategoryForIndent(Map<String, dynamic> indent) {
    final material = _materials.firstWhere(
      (mat) =>
          mat['type'].toString().toUpperCase() ==
              (indent['type'] ?? '').toString().toUpperCase() &&
          mat['subtype'].toString().toUpperCase() ==
              (indent['subtype'] ?? '').toString().toUpperCase(),
      orElse: () => {},
    );
    final category = material['category']?.toString().toUpperCase();
    if (category != null && _groups.contains(category)) {
      return category;
    }
    return 'SUNDRY';
  }

  double _calculateTotalPrice() {
    return _indents.fold(0.0, (sum, item) {
      final value =
          double.tryParse(item['issuedValue']?.toString() ?? '0') ?? 0.0;
      return sum + value;
    });
  }

  double _calculateGroupTotal(String group) {
    final groupIndents = _getGroupIndents(group);
    return groupIndents.fold(0.0, (sum, item) {
      final value =
          double.tryParse(item['issuedValue']?.toString() ?? '0') ?? 0.0;
      return sum + value;
    });
  }

  List<Map<String, dynamic>> _getGroupIndents(String group) {
    final items = _indents.where((i) {
      String indentGroup = (i['category'] ?? '').toString().toUpperCase();
      return indentGroup == group;
    }).toList();
    // Sort alphabetically by 'type', then 'subtype'
    items.sort((a, b) {
      final typeA = (a['type'] ?? '').toString();
      final typeB = (b['type'] ?? '').toString();
      final cmpType = typeA.compareTo(typeB);
      if (cmpType != 0) return cmpType;
      final subtypeA = (a['subtype'] ?? '').toString();
      final subtypeB = (b['subtype'] ?? '').toString();
      return subtypeA.compareTo(subtypeB);
    });
    return items;
  }

  Future<void> _loadJobs() async {
    try {
      final jobs = await ApiService.getJobs();
      setState(() {
        _jobs = List<Map<String, dynamic>>.from(
          jobs.where((job) => job['status'] != 'isFinal').toList(),
        );
      });
    } catch (e) {
      _jobs = [];
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading jobs: $e')));
    }
  }

  Future<void> _loadIndentsForJob(String jobId) async {
    setState(() {
      _isLoading = true;
      _indents = [];
    });
    try {
      final indents = await ApiService.getIndentsForJob(jobId);
      setState(() {
        _indents = List<Map<String, dynamic>>.from(indents).map((indent) {
          return {...indent, 'category': _getCategoryForIndent(indent)};
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading indents: $e')));
    }
  }

  TableRow _buildHeaderRow() {
    return const TableRow(
      decoration: BoxDecoration(color: Color(0xFFDDEEFF)),
      children: [
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Subtype', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'Indent Qty',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'Actual Qty',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'Unit Price',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'Actual Price',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'Description',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'User Ind',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'User Out',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  TableRow _buildIndentRow(Map<String, dynamic> indent) {
    bool highlight =
        (indent['issuedValue'] == null ||
        indent['issuedValue'].toString().isEmpty);

    return TableRow(
      decoration: BoxDecoration(color: highlight ? Colors.red[100] : null),
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(indent['type']?.toString() ?? '-'),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(indent['subtype']?.toString() ?? '-'),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(indent['quantity']?.toString() ?? '-'),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(indent['issuedQty']?.toString() ?? '-'),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(indent['price']?.toString() ?? '-'),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(indent['issuedValue']?.toString() ?? '-'),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(indent['description']?.toString() ?? '-'),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(indent['user_ind']?.toString() ?? '-'),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(indent['user_out']?.toString() ?? '-'),
        ),
      ],
    );
  }

  Widget _buildMobileIndentCard(Map<String, dynamic> indent) {
    bool highlight =
        (indent['issuedValue'] == null ||
        indent['issuedValue'].toString().isEmpty);
    return Card(
      color: highlight ? Colors.red[100] : null,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${indent['type'] ?? '-'} / ${indent['subtype'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text('Indent Qty: ${indent['quantity'] ?? '-'}'),
                Text('Actual Qty: ${indent['issuedQty'] ?? '-'}'),
                Text('Unit Price: ${indent['price'] ?? '-'}'),
                Text('Actual Price: ${indent['issuedValue'] ?? '-'}'),
              ],
            ),
            if ((indent['description'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Description: ${indent['description']}'),
              ),
            Row(
              children: [
                Expanded(child: Text('User Ind: ${indent['user_ind'] ?? '-'}')),
                Expanded(child: Text('User Out: ${indent['user_out'] ?? '-'}')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupMobileList(String group) {
    final items = _getGroupIndents(group);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: items.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$group - Total: ₹${_calculateGroupTotal(group).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No items in this group.'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$group - Total: ₹${_calculateGroupTotal(group).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...items.map(_buildMobileIndentCard),
                ],
              ),
      ),
    );
  }

  Widget _buildTableForGroup(String group) {
    List<Map<String, dynamic>> items = _getGroupIndents(group);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$group - Total: ₹${_calculateGroupTotal(group).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No items in this group.'),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      border: TableBorder.all(color: Colors.grey.shade300),
                      children: [
                        _buildHeaderRow(),
                        ...items.map(_buildIndentRow).toList(),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportIndentsToExcel(BuildContext context) async {
    if (_selectedJob == null) return;
    if (_indents.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No indents to export.')));
      return;
    }

    try {
      // Only support for desktop platforms (Windows/Mac/Linux) via dart:io
      final Excel excel = Excel.createExcel();
      final String sheetName = "Indents";
      final Sheet sheet = excel[sheetName];

      // Write header
      sheet.appendRow([
        'Type',
        'Subtype',
        'Category',
        'Indent Qty',
        'Actual Qty',
        'Unit Price',
        'Actual Price',
        'Description',
        'User Ind',
        'User Out',
      ]);

      // Write indents
      for (final indent in _indents) {
        sheet.appendRow([
          indent['type'] ?? '',
          indent['subtype'] ?? '',
          indent['category'] ?? '',
          indent['quantity'] ?? '',
          indent['issuedQty'] ?? '',
          indent['price'] ?? '',
          indent['issuedValue'] ?? '',
          indent['description'] ?? '',
          indent['user_ind'] ?? '',
          indent['user_out'] ?? '',
        ]);
      }

      // Default file name
      final String jobSerial =
          _selectedJob?['serialNo']?.toString().replaceAll(
            RegExp(r'[\\/:*?"<>|]'),
            '_',
          ) ??
          'job';
      final String defaultFileName = "Indent_$jobSerial.xlsx";

      // Ask user where to save
      String? outputPath;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Indent Excel',
          fileName: defaultFileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );
      }

      if (outputPath == null) {
        // User cancelled the picker
        return;
      }

      final fileBytes = excel.encode();
      if (fileBytes == null) {
        throw Exception('Failed to encode Excel file.');
      }

      final file = File(outputPath);
      await file.writeAsBytes(fileBytes, flush: true);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Excel exported to $outputPath')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to export Excel: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Responsive: mobile if width < 600, else desktop/tablet
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return Scaffold(
      appBar: AppBar(title: const Text('View Indents')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButton<Map<String, dynamic>>(
                    value: _selectedJob,
                    hint: const Text('Select Job'),
                    isExpanded: true,
                    items: _jobs.map((job) {
                      return DropdownMenuItem(
                        value: job,
                        child: Text(job['serialNo'] ?? 'Unknown Job'),
                      );
                    }).toList(),
                    onChanged: (job) {
                      setState(() {
                        _selectedJob = job;
                      });
                      if (job != null) {
                        _loadIndentsForJob(job['serialNo']);
                      }
                    },
                  ),
                  if (_indents.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        "Final Total Price: ₹${_calculateTotalPrice().toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  if (_selectedJob != null && _indents.isNotEmpty && isDesktop)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          onPressed: () => _exportIndentsToExcel(context),
                          icon: const Icon(Icons.download),
                          label: const Text('Download Indents in Excel'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (_indents.isEmpty)
                    const Text('No indents found for selected job.'),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final group in _groups)
                          isMobile
                              ? _buildGroupMobileList(group)
                              : _buildTableForGroup(group),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
