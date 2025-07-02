import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'saved_reports_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _role = '';
  String _username = '';
  Timer? _updateTimer;
  int timerDuration = 300;

  @override
  void initState() {
    super.initState();
    _loadUser();
    checkForUpdatesIfNeeded();

    // Then check every hour
    _updateTimer = Timer.periodic(Duration(seconds: timerDuration), (timer) {
      checkForUpdatesIfNeeded();
    });
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _role = prefs.getString('role')?.toLowerCase() ?? 'user';
      _username = prefs.getString('username') ?? '';
    });
  }

  Future<void> checkForUpdatesIfNeeded() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final versionInfo = await ApiService.fetchVersionInfo();
    if (versionInfo == null) return;

    timerDuration = versionInfo['interval_seconds'];

    await prefs.setInt('last_update_check', now);

    final String platform = Platform.isAndroid ? 'android' : 'windows';
    final String latestVersion = versionInfo[platform]['version'];
    final String currentVersion = await ApiService.getCurrentAppVersion();

    if (currentVersion != latestVersion) {
      showUpdateDialog(
        context,
        downloadUrl:
            versionInfo[platform]['apk_url'] ??
            versionInfo[platform]['installer_url'],
        changelog: versionInfo['changelog'] ?? '',
        latestVersion: latestVersion,
      );
    }
  }

  void showUpdateDialog(
    BuildContext context, {
    required String downloadUrl,
    required String changelog,
    required String latestVersion,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Update Available!"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("A new version ($latestVersion) is available."),
            if (changelog.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text("What's new:"),
              Text(changelog),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            child: const Text("Update"),
            onPressed: () async {
              // Launch the update link
              await launchUrl(
                Uri.parse(downloadUrl),
                mode: LaunchMode.externalApplication,
              );
              // Pop the dialog
              Navigator.pop(context);
              // Logout: clear prefs and go to login page
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (context.mounted) {
                context.go('/'); // Or your login route
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel(); // This disposes the timer!
    super.dispose();
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
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
          widthFactor: 0.8,
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
