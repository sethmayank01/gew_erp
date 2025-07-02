import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MaterialListScreen extends StatefulWidget {
  const MaterialListScreen({super.key});

  @override
  State<MaterialListScreen> createState() => _MaterialListScreenState();
}

class _MaterialListScreenState extends State<MaterialListScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(); // Material Type
  final _subtypeController = TextEditingController(); // New field
  final _minQtyController = TextEditingController();
  final _searchController = TextEditingController();

  final List<String> _units = ['Nos', 'Kgs', 'Sets', 'Mtrs', 'Ltrs'];
  final List<String> _categories = [
    'CCA',
    'Tanking',
    'Mounting',
    'Accessory',
    'Sundry',
  ];
  bool _isJobSpecific = false;
  String? _selectedUnit;
  String? _selectedCategory;
  String _currentUser = '';
  String _role = '';
  List<Map<String, dynamic>> _materials = [];
  List<Map<String, dynamic>> _filteredMaterials = [];

  bool isAdmin = false; // TODO: Replace with actual role-based logic

  // NEW: Loading and error state
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMaterials();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUser = prefs.getString('username') ?? '';
      _role = prefs.getString('role') ?? '';
      if (_role == 'admin') isAdmin = true;
    });
  }

  Future<void> _loadMaterials() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final materials = await ApiService.getMaterials();
      List<Map<String, dynamic>> sortedMaterials =
          List<Map<String, dynamic>>.from(materials)..sort((a, b) {
            final typeA = (a['type'] ?? '').toString().toLowerCase();
            final typeB = (b['type'] ?? '').toString().toLowerCase();
            final subtypeA = (a['subtype'] ?? '').toString().toLowerCase();
            final subtypeB = (b['subtype'] ?? '').toString().toLowerCase();
            final cmp = typeA.compareTo(typeB);
            return cmp != 0 ? cmp : subtypeA.compareTo(subtypeB);
          });
      setState(() {
        _materials = sortedMaterials;
        _filteredMaterials = _materials;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load materials. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _addMaterial() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'type': _nameController.text,
      'subtype': _subtypeController.text,
      'unit': _selectedUnit,
      'category': _selectedCategory,
      'minQty': _minQtyController.text.isEmpty ? null : _minQtyController.text,
      'jobSpecific': _isJobSpecific,
    };

    await ApiService.addMaterial(data);
    _nameController.clear();
    _subtypeController.clear();
    _minQtyController.clear();
    setState(() {
      _selectedUnit = null;
      _selectedCategory = null;
    });
    _loadMaterials();
  }

  Future<void> _deleteMaterial(String type, String subtype) async {
    await ApiService.deleteMaterial(type, subtype);
    _loadMaterials();
  }

  void _filterMaterials(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredMaterials =
          _materials.where((mat) {
              final type = mat['type']?.toString().toLowerCase() ?? '';
              final subtype = mat['subtype']?.toString().toLowerCase() ?? '';
              // Combine type and subtype with and without space
              final combined1 = '$type $subtype';
              final combined2 = '$type$subtype';
              return type.contains(q) ||
                  subtype.contains(q) ||
                  combined1.contains(q) ||
                  combined2.contains(q);
            }).toList()
            // Also sort the filtered list
            ..sort((a, b) {
              final typeA = (a['type'] ?? '').toString().toLowerCase();
              final typeB = (b['type'] ?? '').toString().toLowerCase();
              final subtypeA = (a['subtype'] ?? '').toString().toLowerCase();
              final subtypeB = (b['subtype'] ?? '').toString().toLowerCase();
              final cmp = typeA.compareTo(typeB);
              return cmp != 0 ? cmp : subtypeA.compareTo(subtypeB);
            });
    });
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    String? value,
    Function(String?) onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
      validator: (val) => val == null || val.isEmpty ? 'Required' : null,
    );
  }

  Widget _buildInputRow(Widget child1, Widget child2) {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: child1,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: child2,
          ),
        ),
      ],
    );
  }

  Widget _buildTripleInputRow(Widget child1, Widget child2, Widget child3) {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: child1,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: child2,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: child3,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Material List')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            if (isAdmin)
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildInputRow(
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Material Type',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                        validator: (val) =>
                            val == null || val.isEmpty ? 'Required' : null,
                      ),
                      TextFormField(
                        controller: _subtypeController,
                        decoration: const InputDecoration(
                          labelText: 'Material Subtype',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                        validator: (val) =>
                            val == null || val.isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildTripleInputRow(
                      _buildDropdown(
                        'Unit',
                        _units,
                        _selectedUnit,
                        (val) => setState(() => _selectedUnit = val),
                      ),
                      _buildDropdown(
                        'Category',
                        _categories,
                        _selectedCategory,
                        (val) => setState(() => _selectedCategory = val),
                      ),
                      TextFormField(
                        controller: _minQtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Min Qty (optional)',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    CheckboxListTile(
                      title: const Text('Job Specific'),
                      contentPadding: EdgeInsets.zero,
                      value: _isJobSpecific,
                      onChanged: (val) =>
                          setState(() => _isJobSpecific = val ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _addMaterial,
                      child: const Text('Add Material'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search Material',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: _filterMaterials,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : _filteredMaterials.isEmpty
                  ? const Center(child: Text('No materials found.'))
                  : ListView.builder(
                      itemCount: _filteredMaterials.length,
                      itemBuilder: (_, index) {
                        final mat = _filteredMaterials[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(
                              '${mat['type'] ?? ''} - ${mat['subtype'] ?? ''}',
                            ),
                            subtitle: Text(
                              'Unit: ${mat['unit']}, Category: ${mat['category']}, Min Qty: ${mat['minQty'] ?? '-'}, '
                              'Job Specific: ${mat['jobSpecific'] == true ? 'Yes' : 'No'}',
                            ),
                            trailing: isAdmin
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('Confirm Delete'),
                                          content: Text(
                                            'Delete ${mat['type']} - ${mat['subtype']}?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pop(context);
                                                _deleteMaterial(
                                                  mat['type'],
                                                  mat['subtype'],
                                                );
                                              },
                                              child: const Text(
                                                'Delete',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
