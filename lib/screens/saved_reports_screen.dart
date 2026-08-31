import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dropdown_search/dropdown_search.dart';

import '../services/api_service.dart';

class SavedReportsScreen extends StatefulWidget {
  const SavedReportsScreen({super.key});

  @override
  State<SavedReportsScreen> createState() => _SavedReportsScreenState();
}

class _SavedReportsScreenState extends State<SavedReportsScreen> {
  List<Map<String, dynamic>> _reports = [];

  // Unique jobs for which reports are available
  List<Map<String, dynamic>> _jobs = [];

  // Currently selected job
  Map<String, dynamic>? _selectedJob;

  String _userRole = 'user';
  String _username = '';

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _loadUserInfo();
    _loadReports();
  }

  // ============================================================
  // USER INFO
  // ============================================================

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _userRole = prefs.getString('role')?.toLowerCase() ?? 'user';
      _username = prefs.getString('username') ?? '';
    });
  }

  // ============================================================
  // LOAD REPORTS
  // ============================================================

  Future<void> _loadReports() async {
    try {
      final reports = await ApiService.getReports();

      final reportList = List<Map<String, dynamic>>.from(reports);

      // ----------------------------------------------------------
      // Create unique job list from reports
      //
      // Therefore ONLY jobs having at least one report
      // will appear in the dropdown.
      //
      // Latest report is used to obtain job details.
      // ----------------------------------------------------------

      final Map<String, Map<String, dynamic>> jobMap = {};

      for (final report in reportList) {
        final serialNo = report['serialNo']?.toString().trim() ?? '';

        if (serialNo.isEmpty) continue;

        final existing = jobMap[serialNo];

        if (existing == null) {
          jobMap[serialNo] = report;
          continue;
        }

        final existingTime =
            DateTime.tryParse(existing['timestamp']?.toString() ?? '') ??
            DateTime(2000);

        final currentTime =
            DateTime.tryParse(report['timestamp']?.toString() ?? '') ??
            DateTime(2000);

        // Use latest report for displaying job information
        if (currentTime.isAfter(existingTime)) {
          jobMap[serialNo] = report;
        }
      }

      final jobs = jobMap.values.toList();

      jobs.sort((a, b) {
        final serialA = a['serialNo']?.toString() ?? '';

        final serialB = b['serialNo']?.toString() ?? '';

        return serialA.compareTo(serialB);
      });

      if (!mounted) return;

      setState(() {
        _reports = reportList;
        _jobs = jobs;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading reports: $e');

      if (!mounted) return;

      setState(() {
        _reports = [];
        _jobs = [];
        _isLoading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading reports: $e')));
    }
  }

  // ============================================================
  // DROPDOWN DISPLAY TEXT
  // ============================================================

  String _jobDisplayText(Map<String, dynamic> job) {
    final serialNo = job['serialNo']?.toString() ?? '';

    final kva = job['kva'] ?? job['KVA'] ?? job['kVA'] ?? '';

    final purchaser = job['purchaserName']?.toString() ?? '';

    final tappingType = job['tappingType']?.toString() ?? '';

    final hvVoltage = job['hvVoltage']?.toString() ?? '';

    final lvVoltage = job['lvVoltage']?.toString() ?? '';

    final vectorGroup = job['vectorGroup']?.toString() ?? '';

    return [
      serialNo,
      if (kva.toString().isNotEmpty) '$kva kVA',
      if (tappingType.isNotEmpty) tappingType,
      if (hvVoltage.isNotEmpty) '$hvVoltage V',
      if (lvVoltage.isNotEmpty) '$lvVoltage V',
      if (vectorGroup.isNotEmpty) vectorGroup,
      if (purchaser.isNotEmpty) purchaser,
    ].join(' - ');
  }

  // ============================================================
  // DELETE REPORT
  // ============================================================

  Future<void> _deleteReport(Map<String, dynamic> report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text('Are you sure you want to delete this report?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final retVal = await ApiService.deleteReport(report);

    if (!mounted) return;

    if (retVal == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report deleted.')));

      // Reload reports and rebuild the dropdown.
      await _loadReports();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error deleting report')));
    }
  }

  // ============================================================
  // EDIT REPORT
  // ============================================================

  void _editReport(Map<String, dynamic> report) {
    final maxValue = report['tappingRangeMax'];

    final minValue = report['tappingRangeMin'];

    final stepValue = report['stepVoltage'];

    final max = double.tryParse(maxValue?.toString() ?? '') ?? 0;

    final min = double.tryParse(minValue?.toString() ?? '') ?? 0;

    final step = double.tryParse(stepValue?.toString() ?? '') ?? 0;

    if (step == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid tap voltage configuration.')),
      );

      return;
    }

    final tapCount = ((max - min) / step).round() + 1;

    context.push(
      '/test_input_form',
      extra: {
        'generalData': report,
        'tapCount': tapCount,
        'isEdit': true,
        'testData': report['testData'],
      },
    );
  }

  // ============================================================
  // GET REPORTS FOR SELECTED JOB
  // ============================================================

  List<Map<String, dynamic>> _getSelectedJobReports() {
    if (_selectedJob == null) {
      return [];
    }

    final selectedSerial = _selectedJob!['serialNo']?.toString().trim() ?? '';

    if (selectedSerial.isEmpty) {
      return [];
    }

    final reports = _reports.where((report) {
      final serial = report['serialNo']?.toString().trim() ?? '';

      return serial == selectedSerial;
    }).toList();

    // Newest first
    reports.sort((a, b) {
      final timeA =
          DateTime.tryParse(a['timestamp']?.toString() ?? '') ?? DateTime(2000);

      final timeB =
          DateTime.tryParse(b['timestamp']?.toString() ?? '') ?? DateTime(2000);

      return timeB.compareTo(timeA);
    });

    return reports;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final selectedReports = _getSelectedJobReports();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              context.go('/dashboard');
            },
          ),
        ],
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ==================================================
                  // SEARCHABLE JOB DROPDOWN
                  // ==================================================
                  DropdownSearch<Map<String, dynamic>>(
                    items: _jobs,

                    selectedItem: _selectedJob,

                    itemAsString: (job) {
                      return _jobDisplayText(job);
                    },

                    popupProps: PopupProps.menu(
                      showSearchBox: true,

                      searchFieldProps: const TextFieldProps(
                        decoration: InputDecoration(
                          hintText: 'Search job, KVA, purchaser...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),

                    dropdownDecoratorProps: const DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        labelText: 'Search / Select Job',
                        hintText: 'Select a job with saved reports',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),

                    clearButtonProps: const ClearButtonProps(isVisible: true),

                    onChanged: (job) {
                      setState(() {
                        _selectedJob = job;
                      });
                    },
                  ),

                  // ==================================================
                  // IMPORTANT:
                  // Do NOT show anything below until a job is selected
                  // ==================================================
                  if (_selectedJob != null) ...[
                    const SizedBox(height: 20),

                    // ------------------------------------------------
                    // SELECTED JOB INFORMATION
                    // ------------------------------------------------
                    Text(
                      'Serial No: ${_selectedJob!['serialNo'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ------------------------------------------------
                    // REPORT VERSIONS
                    // ------------------------------------------------
                    Expanded(
                      child: selectedReports.isEmpty
                          ? const Center(child: Text('No saved reports found.'))
                          : ListView.builder(
                              itemCount: selectedReports.length,
                              itemBuilder: (context, index) {
                                final report = selectedReports[index];

                                final time = report['timestamp'] ?? '';

                                final formatted = time
                                    .toString()
                                    .split('T')
                                    .join(' @ ');

                                final savedBy = report['savedBy'] ?? 'Unknown';

                                final remark = report['remark'] ?? 'Unknown';

                                // Since reports are newest first:
                                //
                                // latest = highest version
                                // oldest = Version 1
                                final versionNumber =
                                    selectedReports.length - index;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    title: Text(
                                      'Version $versionNumber: $formatted',
                                    ),

                                    subtitle: Text(
                                      'Saved by: $savedBy, Remark: $remark',
                                    ),

                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // PDF PREVIEW
                                        IconButton(
                                          icon: const Icon(
                                            Icons.picture_as_pdf,
                                          ),
                                          tooltip: 'Preview Report',
                                          onPressed: () {
                                            context.push(
                                              '/preview',
                                              extra: report,
                                            );
                                          },
                                        ),

                                        // EDIT
                                        if (savedBy == _username ||
                                            _userRole == 'admin')
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            tooltip: 'Edit Report',
                                            onPressed: () {
                                              _editReport(report);
                                            },
                                          ),

                                        // DELETE
                                        if (_userRole == 'admin')
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                            ),
                                            tooltip: 'Delete Report',
                                            onPressed: () {
                                              _deleteReport(report);
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ] else ...[
                    // ------------------------------------------------
                    // NOTHING SELECTED
                    // ------------------------------------------------
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Select a job to view saved reports.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
