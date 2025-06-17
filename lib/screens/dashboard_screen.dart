import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'saved_reports_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _role = '';
  String _username = '';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _role = prefs.getString('role')?.toLowerCase() ?? 'user';
      _username = prefs.getString('username') ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to GEW ERP 1.1'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              context.go('/');
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Welcome $_username',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14, // Optional: adjust size
                ),
              ),
              const SizedBox(height: 20),
              ..._buildDashboardButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDashboardButtons(BuildContext context) {
    List<Map<String, dynamic>> buttons = [
      {'label': 'Incoming Material Entry', 'route': '/incoming-material-entry'},
      {'label': 'Outgoing Material Entry', 'route': '/outgoing-material-entry'},
      {'label': 'Job Indent Entry', 'route': '/job-indent'},
      {'label': 'Job Indent View', 'route': '/get-job-indent'},
      {'label': 'Final Test Report Generation', 'route': '/test_input_form'},
      {'label': 'Saved Test Reports', 'widget': const SavedReportsScreen()},
      {'label': 'User Management', 'route': '/user-management'},
      if (_role == "admin")
        {'label': 'Job Create Entry', 'route': '/job-details'},
      {'label': 'Job List', 'route': '/job-list'},
      {'label': 'Master Material List', 'route': '/material-list'},
      {'label': 'Stock List', 'route': '/stock-list'},
    ];

    return buttons.map((btn) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: FractionallySizedBox(
          widthFactor: 0.8, // 80% of screen width
          child: ElevatedButton(
            onPressed: () {
              if (btn.containsKey('route')) {
                context.push(btn['route']);
              } else if (btn.containsKey('widget')) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => btn['widget']),
                );
              }
            },
            child: Center(child: Text(btn['label'])),
          ),
        ),
      );
    }).toList();
  }
}
