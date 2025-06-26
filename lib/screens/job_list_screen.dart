import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'package:go_router/go_router.dart';

class JobListScreen extends StatefulWidget {
  const JobListScreen({super.key});

  @override
  State<JobListScreen> createState() => _JobListScreenState();
}

class _JobListScreenState extends State<JobListScreen> {
  List<Map<String, dynamic>> _jobs = [];
  String _filter = 'All';
  String _userRole = '';

  final List<String> _filterOptions = [
    'All',
    'New',
    'Repair',
    'New - Under Process',
    'New - Dispatched',
    'Repair - Under Process',
    'Repair - Dispatched',
  ];

  // Search feature
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _loadJobs();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('role') ?? 'user';
    });
  }

  Future<void> _loadJobs() async {
    final jobs = await ApiService.getJobs();
    // Sort jobs in descending order by serialNo (assuming serialNo is numeric or sortable correctly as string)
    List<Map<String, dynamic>> sortedJobs = List<Map<String, dynamic>>.from(
      jobs,
    );
    sortedJobs.sort((a, b) {
      // If serialNo is numeric, compare as int, else as string
      final aVal = int.tryParse(a['serialNo']?.toString() ?? '');
      final bVal = int.tryParse(b['serialNo']?.toString() ?? '');
      if (aVal != null && bVal != null) {
        return bVal.compareTo(aVal);
      } else {
        // fallback to string compare
        return (b['serialNo']?.toString() ?? '').compareTo(
          a['serialNo']?.toString() ?? '',
        );
      }
    });
    setState(() {
      _jobs = sortedJobs;
    });
  }

  Future<void> _updateJob(Map<String, dynamic> job) async {
    await ApiService.updateJob(job);
    await _loadJobs();
  }

  // Filter + Search together
  List<Map<String, dynamic>> get _filteredJobs {
    List<Map<String, dynamic>> jobs = _jobs.where((job) {
      final jobType = job['jobType'] ?? '';
      final dispatched =
          job['dispatchDate'] != null && job['dispatchDate'] != '';

      switch (_filter) {
        case 'New':
          return jobType == 'New';
        case 'Repair':
          return jobType == 'Repair';
        case 'New - Under Process':
          return jobType == 'New' && !dispatched;
        case 'New - Dispatched':
          return jobType == 'New' && dispatched;
        case 'Repair - Under Process':
          return jobType == 'Repair' && !dispatched;
        case 'Repair - Dispatched':
          return jobType == 'Repair' && dispatched;
        default:
          return true;
      }
    }).toList();

    if (_searchQuery.isNotEmpty) {
      jobs = jobs.where((job) {
        return (job['serialNo'] ?? '').toString().toLowerCase().contains(
              _searchQuery,
            ) ||
            (job['purchaserName'] ?? '').toString().toLowerCase().contains(
              _searchQuery,
            ) ||
            (job['purchaserReference'] ?? '').toString().toLowerCase().contains(
              _searchQuery,
            ) ||
            (job['jobType'] ?? '').toString().toLowerCase().contains(
              _searchQuery,
            );
      }).toList();
    }
    return jobs;
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '-';
    final date = DateTime.tryParse(isoDate);
    return date != null ? DateFormat('yyyy-MM-dd').format(date) : '-';
  }

  Future<void> _selectDispatchDate(Map<String, dynamic> job) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        job['dispatchDate'] = picked.toIso8601String();
      });
      await _updateJob(job);
    }
  }

  Future<void> _toggleFinal(Map<String, dynamic> job, bool? newVal) async {
    setState(() {
      job['isFinal'] = newVal ?? false;
    });
    await _updateJob(job);
  }

  // Responsive build
  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 850;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/dashboard'),
          ),
          DropdownButton<String>(
            value: _filter,
            underline: const SizedBox(),
            icon: const Icon(Icons.filter_list, color: Colors.white),
            dropdownColor: Colors.white,
            onChanged: (value) => setState(() => _filter = value!),
            items: _filterOptions
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar always visible
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: 350,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search jobs',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          Expanded(
            child: isWideScreen ? _buildWideTable() : _buildMobileList(),
          ),
        ],
      ),
    );
  }

  // Desktop/tablet (wide) layout: table
  Widget _buildWideTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _buildHeaderRow(),
                    ),
                  ),
                  const Divider(height: 0),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _filteredJobs.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                "No jobs found.",
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : Column(
                              children: _filteredJobs.map((job) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: _buildJobRow(job),
                                );
                              }).toList(),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Mobile layout: card view
  Widget _buildMobileList() {
    final jobs = _filteredJobs;
    if (jobs.isEmpty) {
      return const Center(child: Text('No jobs found.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final job = jobs[idx];
        return Card(
          child: InkWell(
            onTap: () {
              showModalBottomSheet(
                context: context,
                builder: (_) => _buildJobDetailSheet(job),
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Serial No: ${job['serialNo'] ?? '-'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_userRole == 'admin')
                        Checkbox(
                          value: job['isFinal'] == true,
                          onChanged: (val) => _toggleFinal(job, val),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Purchaser: ${job['purchaserName'] ?? '-'}'),
                  Text(
                    'Purchaser Reference: ${job['purchaserReference'] ?? '-'}',
                  ),
                  Text('Quantity: ${job['quantity'] ?? '-'}'),
                  Text('Job Type: ${job['jobType'] ?? '-'}'),
                  Text(
                    'KVA: ${job['kva'] ?? '-'} | Phases: ${job['phases'] ?? '-'}',
                  ),
                  Text(
                    'HV: ${job['hvVoltage'] ?? '-'} | LV: ${job['lvVoltage'] ?? '-'}',
                  ),
                  Text('Dispatched: ${_formatDate(job['dispatchDate'])}'),
                  Text('Final: ${job['isFinal'] == true ? 'Yes' : 'No'}'),
                  if (_userRole == 'admin')
                    Row(
                      children: [
                        const Text(
                          'Dispatch Date:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          onPressed: () => _selectDispatchDate(job),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildJobDetailSheet(Map<String, dynamic> job) {
    // Show all fields in a bottom sheet for mobile
    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Serial No: ${job['serialNo'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Divider(),
            _buildDetailRow('Purchaser Name', job['purchaserName']),
            _buildDetailRow('Purchaser Reference', job['purchaserReference']),
            _buildDetailRow('Quantity', job['quantity']),
            _buildDetailRow('Job Type', job['jobType']),
            _buildDetailRow('KVA', job['kva']),
            _buildDetailRow('Phases', job['phases']),
            _buildDetailRow('HV Voltage', job['hvVoltage']),
            _buildDetailRow('LV Voltage', job['lvVoltage']),
            _buildDetailRow('Vector Group', job['vectorGroup']),
            _buildDetailRow('IS', job['relevantIS']),
            _buildDetailRow('Tapping Type', job['tappingType']),
            _buildDetailRow('Tapping Range Max', job['tappingRangeMax']),
            _buildDetailRow('Tapping Range Min', job['tappingRangeMin']),
            _buildDetailRow('Step Voltage', job['stepVoltage']),
            if (_userRole == 'admin') _buildDetailRow('Remark', job['remark']),
            _buildDetailRow('Dispatched', _formatDate(job['dispatchDate'])),
            _buildDetailRow('Final', job['isFinal'] == true ? 'Yes' : 'No'),
            _buildDetailRow(
              'Created',
              '${_formatDate(job['entryDateTime'])} by ${job['createdBy'] ?? '-'}',
            ),
            if (_userRole == 'admin')
              Row(
                children: [
                  const Text(
                    'Dispatch Date:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _selectDispatchDate(job);
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value?.toString() ?? '-', style: const TextStyle()),
          ),
        ],
      ),
    );
  }

  // Wide table headers for desktop/tablet
  Widget _buildHeaderRow() {
    return Row(
      children: [
        _buildHeaderCell('Serial No', narrowWidth),
        _buildHeaderCell('Purchaser Name', colWidth),
        _buildHeaderCell('Purchaser Ref', colWidth),
        _buildHeaderCell('Quantity', narrowWidth),
        _buildHeaderCell('Job Type', narrowWidth),
        _buildHeaderCell('KVA', narrowWidth),
        _buildHeaderCell('Phases', narrowWidth),
        _buildHeaderCell('HV', narrowWidth),
        _buildHeaderCell('LV', narrowWidth),
        _buildHeaderCell('Vector', narrowWidth),
        _buildHeaderCell('IS', narrowWidth),
        _buildHeaderCell('Tapping Type', narrowWidth),
        _buildHeaderCell('Max', narrowWidth),
        _buildHeaderCell('Min', narrowWidth),
        _buildHeaderCell('Step', narrowWidth),
        if (_userRole == 'admin') _buildHeaderCell('Remark', colWidth),
        _buildHeaderCell(
          'Dispatched',
          dispatchColWidth,
        ), // Here, no action column!
        _buildHeaderCell('Final', narrowWidth),
        _buildHeaderCell('Created', colWidth),
        // (No more actions column)
      ],
    );
  }

  Widget _buildHeaderCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        textAlign: TextAlign.left,
      ),
    );
  }

  Widget _buildCell(dynamic value, double width, {bool wrap = false}) {
    return SizedBox(
      width: width,
      child: Text(
        value?.toString() ?? '-',
        style: const TextStyle(fontSize: 12),
        textAlign: TextAlign.left,
        softWrap: wrap,
        overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
        maxLines: wrap ? 3 : 1,
      ),
    );
  }

  Widget _buildJobRow(Map<String, dynamic> job) {
    return Row(
      children: [
        _buildCell(job['serialNo'], narrowWidth),
        _buildCell(job['purchaserName'], colWidth, wrap: true),
        _buildCell(job['purchaserReference'], colWidth, wrap: true),
        _buildCell(job['quantity'], narrowWidth),
        _buildCell(job['jobType'], narrowWidth),
        _buildCell(job['kva'], narrowWidth),
        _buildCell(job['phases'], narrowWidth),
        _buildCell(job['hvVoltage'], narrowWidth),
        _buildCell(job['lvVoltage'], narrowWidth),
        _buildCell(job['vectorGroup'], narrowWidth),
        _buildCell(job['relevantIS'], narrowWidth),
        _buildCell(job['tappingType'], narrowWidth),
        _buildCell(job['tappingRangeMax'], narrowWidth),
        _buildCell(job['tappingRangeMin'], narrowWidth),
        _buildCell(job['stepVoltage'], narrowWidth),
        if (_userRole == 'admin')
          _buildCell(job['remark'], colWidth, wrap: true),
        // Dispatched column: show date and date selector for admin
        SizedBox(
          width: dispatchColWidth,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _formatDate(job['dispatchDate']),
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_userRole == 'admin')
                IconButton(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  tooltip: 'Change Dispatch Date',
                  onPressed: () => _selectDispatchDate(job),
                ),
            ],
          ),
        ),
        SizedBox(
          width: narrowWidth,
          child: _userRole == 'admin'
              ? Checkbox(
                  value: job['isFinal'] == true,
                  onChanged: (val) => _toggleFinal(job, val),
                )
              : Text(job['isFinal'] == true ? 'Yes' : 'No'),
        ),
        _buildCell(
          '${_formatDate(job['entryDateTime'])} by ${job['createdBy'] ?? '-'}',
          colWidth,
          wrap: true,
        ),
        // (No more actions column)
      ],
    );
  }

  final double colWidth = 80;
  final double narrowWidth = 60;
  final double dispatchColWidth = 110;
}
