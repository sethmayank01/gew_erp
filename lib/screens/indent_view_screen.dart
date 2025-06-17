import 'package:flutter/material.dart';
import '../services/api_service.dart';

class IndentViewScreen extends StatefulWidget {
  const IndentViewScreen({super.key});

  @override
  State<IndentViewScreen> createState() => _IndentViewScreenState();
}

class _IndentViewScreenState extends State<IndentViewScreen> {
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _indents = [];
  Map<String, dynamic>? _selectedJob;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  double _calculateTotalPrice() {
    return _indents.fold(0.0, (sum, item) {
      final value =
          double.tryParse(item['issuedValue']?.toString() ?? '0') ?? 0.0;
      return sum + value;
    });
  }

  Future<void> _loadJobs() async {
    setState(() => _isLoading = true);
    try {
      final jobs = await ApiService.getJobs();
      setState(() {
        _jobs = List<Map<String, dynamic>>.from(
            jobs.where((job) => job['status'] != 'isFinal').toList());
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading jobs: $e')),
      );
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
        _indents = List<Map<String, dynamic>>.from(indents);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading indents: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        "Total Price: ₹${_calculateTotalPrice().toStringAsFixed(2)}",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (_indents.isEmpty)
                    const Text('No indents found for selected job.'),
                  if (_indents.isNotEmpty)
                    Expanded(
                      child: ListView.builder(
                        itemCount: _indents.length,
                        itemBuilder: (context, index) {
                          final indent = _indents[index];
                          return Card(
                            child: ListTile(
                              title: Text(
                                  "${indent['type']} - ${indent['subtype']} | Indent Qty: ${indent['quantity']} | Actual Qty: ${indent['issuedQty'] ?? '-'} | Unit Price: ${indent['price'] ?? '-'} | Actual Price: ${indent['issuedValue'] ?? '-'}"),
                              subtitle: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Desc: ${indent['description'] ?? '-'}"),
                                  Text(" | "),
                                  Text(
                                      "User Ind: ${indent['user_ind'] ?? '-'}"),
                                  Text(" | "),
                                  Text(
                                      "Ind Time: ${indent['ind_time'] ?? '-'}"),
                                  Text(" | "),
                                  Text(
                                      "User Out: ${indent['user_out'] ?? '-'}"),
                                  Text(" | "),
                                  Text(
                                      "Out Time: ${indent['time_out'] ?? '-'}"),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    )
                ],
              ),
            ),
    );
  }
}
