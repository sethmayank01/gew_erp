import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedReportsScreen extends StatefulWidget {
  const SavedReportsScreen({super.key});

  @override
  State<SavedReportsScreen> createState() => _SavedReportsScreenState();
}

class _SavedReportsScreenState extends State<SavedReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  String _userRole = 'user';
  String _username = '';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadReports();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('role')?.toLowerCase() ?? 'user';
      _username = prefs.getString('username') ?? '';
    });
  }

  Future<void> _loadReports() async {
    final reports = await ApiService.getReports();
    setState(() {
      _reports = List<Map<String, dynamic>>.from(reports);
    });
  }

  Future<void> _deleteReport(Map<String, dynamic> report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text('Are you sure you want to delete this report?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final retVal = await ApiService.deleteReport(
        report,
      ); // Implement this in your ApiService
      _loadReports();
      if (retVal == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Report deleted.')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error Deleting report')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (var report in _reports) {
      final serial = report['serialNo']?.toString().trim() ?? 'Unknown';
      if (serial.isEmpty) continue;
      grouped.putIfAbsent(serial, () => []).add(report);
    }

    grouped.updateAll((key, list) {
      list.sort((a, b) {
        final timeA = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(2000);
        final timeB = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(2000);
        return timeB.compareTo(timeA);
      });
      return list;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/dashboard'),
          ),
        ],
      ),
      body: grouped.isEmpty
          ? const Center(child: Text('No saved reports found.'))
          : ListView(
              children: grouped.entries.map((entry) {
                final serial = entry.key;
                final versions = entry.value;

                return ExpansionTile(
                  title: Text('Serial No: $serial'),
                  children: versions.asMap().entries.map((verEntry) {
                    final idx = verEntry.key;
                    final report = verEntry.value;
                    final time = report['timestamp'] ?? '';
                    final formatted = time.toString().split('T').join(' @ ');
                    final savedBy = report['savedBy'] ?? 'Unknown';
                    final remark = report['remark'] ?? 'Unknown';

                    // Versioning: version number is 1 for oldest, increases to latest
                    final versionNumber = versions.length - idx;

                    return ListTile(
                      title: Text('Version $versionNumber: $formatted'),
                      subtitle: Text('Saved by: $savedBy, Remark: $remark'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.picture_as_pdf),
                            onPressed: () {
                              context.push('/preview', extra: report);
                            },
                          ),
                          // EDIT: All users (including non-admins) can edit
                          if (savedBy == _username || _userRole == 'admin')
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                final max = report['tappingRangeMax'];
                                final min = report['tappingRangeMin'];
                                final step = report['stepVoltage'];
                                final tapCount =
                                    ((max - min) / step).round() + 1;

                                context.push(
                                  '/test_input_form',
                                  extra: {
                                    'generalData': report,
                                    'tapCount': tapCount,
                                    'isEdit': true,
                                    'testData': report['testData'],
                                  },
                                );
                              },
                            ),
                          // DELETE: Only admins can delete
                          if (_userRole == 'admin')
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteReport(report),
                              tooltip: 'Delete Report',
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
    );
  }
}
