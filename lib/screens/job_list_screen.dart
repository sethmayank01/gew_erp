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

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _loadJobs();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('role') ?? 'user';
    });
  }

  Future<void> _loadJobs() async {
    final jobs = await ApiService.getJobs();
    setState(() {
      _jobs = List<Map<String, dynamic>>.from(jobs);
    });
  }

  Future<void> _updateJob(Map<String, dynamic> job) async {
    await ApiService.updateJob(job);
    await _loadJobs();
  }

  List<Map<String, dynamic>> get _filteredJobs {
    return _jobs.where((job) {
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

  @override
  Widget build(BuildContext context) {
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
          )
        ],
      ),
      body: LayoutBuilder(
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
                        child: Column(
                          children: _filteredJobs.map((job) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
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
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        _buildHeaderCell('Serial No', narrowWidth),
        _buildHeaderCell('Purchaser Name', colWidth),
        _buildHeaderCell('Purchaser Ref', colWidth),
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
        _buildHeaderCell('Dispatched', colWidth),
        _buildHeaderCell('Final', narrowWidth),
        _buildHeaderCell('Created', colWidth),
        if (_userRole == 'admin') _buildHeaderCell('Actions', narrowWidth),
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
        _buildCell(_formatDate(job['dispatchDate']), colWidth),
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
            wrap: true),
        if (_userRole == 'admin')
          SizedBox(
            width: narrowWidth,
            child: IconButton(
              icon: const Icon(Icons.calendar_today, size: 16),
              onPressed: () => _selectDispatchDate(job),
            ),
          ),
      ],
    );
  }

  final double colWidth = 80;
  final double narrowWidth = 60;

  Widget _buildField(String label, dynamic value, {bool wrap = false}) {
    return Container(
      constraints: wrap ? const BoxConstraints(maxWidth: 80) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
          ),
          Text(
            value?.toString() ?? '-',
            style: const TextStyle(fontSize: 10),
            softWrap: wrap,
            overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
            maxLines: wrap ? 3 : 1,
          ),
        ],
      ),
    );
  }
}
