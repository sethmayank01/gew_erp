import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  String _currentUser = '';
  String _role = '';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _fetchUsers();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUser = prefs.getString('username') ?? '';
      _role = prefs.getString('role') ?? '';
    });
  }

  Future<void> _fetchUsers() async {
    final users = await ApiService.getUsers();
    setState(() {
      _users = List<Map<String, dynamic>>.from(users);
    });
  }

  void _showAddUserDialog() {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String role = 'user';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add New User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username')),
            TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true),
            DropdownButton<String>(
              value: role,
              onChanged: (val) => setState(() => role = val!),
              items: ['user', 'admin']
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ApiService.addUser(
                  usernameController.text, passwordController.text, role);
              Navigator.pop(context);
              _fetchUsers();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showResetPasswordDialog(String username) {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reset Password for $username'),
        content: TextField(
            controller: passwordController,
            decoration: const InputDecoration(labelText: 'New Password'),
            obscureText: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ApiService.resetPassword(username, passwordController.text);
              Navigator.pop(context);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(String username) async {
    await ApiService.deleteUser(username);
    _fetchUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          if (_role == 'admin')
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddUserDialog,
            ),
        ],
      ),
      body: ListView.builder(
        itemCount: _users.length,
        itemBuilder: (_, index) {
          final user = _users[index];
          final username = user['username'];
          final role = user['role'];
          // Non-admins only see their own entry
          if (_role != 'admin' && username != _currentUser) {
            return const SizedBox.shrink();
          }
          return ListTile(
            title: Text(username),
            subtitle: Text('Role: $role'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_role == 'admin' || username == _currentUser)
                  IconButton(
                    icon: const Icon(Icons.lock_reset),
                    onPressed: () => _showResetPasswordDialog(username),
                  ),
                if (_role == 'admin' && username != _currentUser)
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteUser(username),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
