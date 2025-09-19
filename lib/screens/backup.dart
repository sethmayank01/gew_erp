import 'package:flutter/material.dart';

class CostingItem {
  final String specification;
  double rateUnit;
  double quantity;
  bool isDropdown;
  List<String>? dropdownOptions;
  String? dropdownValue;

  CostingItem({
    required this.specification,
    this.rateUnit = 0,
    this.quantity = 0,
    this.isDropdown = false,
    this.dropdownOptions,
    this.dropdownValue,
  });

  double get rm => rateUnit * quantity;
}

class CostingEntryScreen extends StatefulWidget {
  const CostingEntryScreen({Key? key}) : super(key: key);

  @override
  State<CostingEntryScreen> createState() => _CostingEntryScreenState();
}

class _CostingEntryScreenState extends State<CostingEntryScreen> {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  late List<CostingItem> items;

  // Percentage controllers
  final sundryController = TextEditingController(text: "3");
  final overheadController = TextEditingController(text: "3");
  final labourController = TextEditingController(text: "3");
  final profitController = TextEditingController(text: "15");
  final remarkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    items = [
      CostingItem(specification: "PICC", rateUnit: 945),
      CostingItem(specification: "AL", rateUnit: 330, quantity: 41),
      CostingItem(specification: "Enameled", rateUnit: 900),
      CostingItem(specification: "Insulation", rateUnit: 340, quantity: 5),
      // This is the CRGO dropdown row
      CostingItem(
        specification: "CRGO",
        rateUnit: 290,
        quantity: 93,
        isDropdown: true,
        dropdownOptions: [
          'CRGO M5',
          'CRGO M4',
          'CRGO MOH',
          'CRGO HP90',
          'CRGO HP85',
          'CRGO HP80',
        ],
        dropdownValue: 'CRGO M5',
      ),
      CostingItem(specification: "YC", rateUnit: 95, quantity: 20),
      CostingItem(
        specification: "TR",
        rateUnit: 120,
        isDropdown: true,
        dropdownOptions: ['Option 1', 'Option 2', 'Option 3'],
        dropdownValue: 'Option 1',
      ),
      CostingItem(specification: "Tank", rateUnit: 128, quantity: 50),
      CostingItem(specification: "Radiator", rateUnit: 138, quantity: 51.3),
      CostingItem(specification: "Oil", rateUnit: 74, quantity: 120),
      CostingItem(specification: "Cu Bar/Flexible", rateUnit: 995),
      CostingItem(specification: "PI Cable", rateUnit: 1045),
      CostingItem(specification: "OCTC 11KV", rateUnit: 4000),
      CostingItem(specification: "CT", rateUnit: 2200),
      CostingItem(specification: "NCT", rateUnit: 0),
      CostingItem(specification: "WTI", rateUnit: 4500),
      CostingItem(specification: "OTI", rateUnit: 4000),
      CostingItem(specification: "MOG", rateUnit: 3500),
      CostingItem(
        specification: "HV Bushings 11KV",
        rateUnit: 250,
        quantity: 3,
      ),
      CostingItem(
        specification: "HV Bushing Fitting",
        rateUnit: 900,
        quantity: 3,
      ),
      CostingItem(specification: "LV Bushings", rateUnit: 50, quantity: 4),
      CostingItem(
        specification: "LV MetalPart 230A",
        rateUnit: 300,
        quantity: 4,
      ),
      CostingItem(specification: "HV Connector", rateUnit: 0),
      CostingItem(specification: "Drain Value", rateUnit: 1245),
      CostingItem(specification: "Silica Gel Breather", rateUnit: 1700),
      CostingItem(specification: "Filter Value", rateUnit: 1245),
      CostingItem(specification: "Sampling Value", rateUnit: 0),
      CostingItem(specification: "Relay Shut off value", rateUnit: 800),
      CostingItem(specification: "Thermometer", rateUnit: 325),
      CostingItem(
        specification: "Air Release Plug",
        rateUnit: 100,
        quantity: 1,
      ),
      CostingItem(
        specification: "Rating & Dia Plate",
        rateUnit: 750,
        quantity: 1,
      ),
      CostingItem(specification: "Logo Plate", rateUnit: 500, quantity: 1),
      CostingItem(specification: "BR GOR1", rateUnit: 3500),
      CostingItem(specification: "Gasket", rateUnit: 1200, quantity: 0.5),
      CostingItem(specification: "Oil Level Guage", rateUnit: 400, quantity: 1),
      CostingItem(specification: "Pr. Relief Valve", rateUnit: 4500),
      CostingItem(specification: "Roller Assembly", rateUnit: 2200),
    ];
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    sundryController.dispose();
    overheadController.dispose();
    labourController.dispose();
    profitController.dispose();
    remarkController.dispose();
    super.dispose();
  }

  // ---- Calculations ----
  double get materialCost => items.fold(0, (sum, item) => sum + item.rm);
  double get sundryPercent => double.tryParse(sundryController.text) ?? 0;
  double get sundryValue => (materialCost * sundryPercent / 100);
  double get total => materialCost + sundryValue;
  double get overheadPercent => double.tryParse(overheadController.text) ?? 0;
  double get overheadValue => (total * overheadPercent / 100);
  double get labourPercent => double.tryParse(labourController.text) ?? 0;
  double get labourValue => (total * labourPercent / 100);
  double get homeCost => total + overheadValue + labourValue;
  double get profitPercent => double.tryParse(profitController.text) ?? 0;
  double get profitValue => (homeCost * profitPercent / 100);
  double get price => homeCost + profitValue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Costing Entry')),
      body: Column(
        children: [
          // Excel-like Data Table
          Expanded(
            child: Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _verticalController,
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 700,
                    child: DataTable(
                      headingRowHeight: 38,
                      dataRowHeight: 38,
                      headingRowColor: MaterialStateColor.resolveWith(
                        (_) => const Color(0xFFe2efda),
                      ), // Excel header green
                      dataRowColor: MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.lightBlue[100]!;
                        }
                        return Colors.white;
                      }),
                      border: TableBorder.all(
                        color: Colors.grey[350]!,
                        width: 1,
                      ),
                      columns: [
                        DataColumn(label: _excelHeader('Specification')),
                        DataColumn(label: _excelHeader('Rate/Unit')),
                        DataColumn(label: _excelHeader('Kgs/Nos')),
                        DataColumn(label: _excelHeader('RM')),
                      ],
                      rows: [
                        ...items.map(
                          (item) => DataRow(
                            cells: [
                              DataCell(
                                item.isDropdown
                                    ? _excelDropdownCell(item)
                                    : Text(
                                        item.specification,
                                        style: _excelCellStyle(),
                                      ),
                              ),
                              DataCell(
                                _excelEditableCell(
                                  value: item.rateUnit > 0
                                      ? item.rateUnit.toString()
                                      : '',
                                  onChanged: (val) => setState(() {
                                    item.rateUnit = double.tryParse(val) ?? 0;
                                  }),
                                ),
                              ),
                              DataCell(
                                _excelEditableCell(
                                  value: item.quantity > 0
                                      ? item.quantity.toString()
                                      : '',
                                  onChanged: (val) => setState(() {
                                    item.quantity = double.tryParse(val) ?? 0;
                                  }),
                                ),
                              ),
                              DataCell(
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    item.rm > 0
                                        ? item.rm.toStringAsFixed(0)
                                        : '-',
                                    style: _excelCellStyle(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The summary/sundry area
          Card(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 2),
            color: Colors.grey[50],
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 4,
                children: [
                  _summaryField('Sundry (%)', sundryController, sundryValue),
                  _summaryLabel('Material Cost', materialCost),
                  _summaryLabel('Total', total),
                  _summaryField(
                    'Overhead (%)',
                    overheadController,
                    overheadValue,
                  ),
                  _summaryField('Labour (%)', labourController, labourValue),
                  _summaryLabel('Home Cost', homeCost, bold: true),
                  _summaryField('Profit (%)', profitController, profitValue),
                  _summaryLabel('Price', price, bold: true),
                ],
              ),
            ),
          ),
          // Remarks and Save
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: remarkController,
                    decoration: const InputDecoration(
                      labelText: 'Remarks',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 8,
                      ),
                    ),
                    minLines: 1,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(100, 40),
                  ),
                  onPressed: () {
                    // TODO: Save logic
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Saved!')));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // Excel-like DataTable header style
  Widget _excelHeader(String text) => Container(
    color: const Color(0xFFe2efda), // Excel header green
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Color(0xFF1d6f42),
        fontSize: 15,
        letterSpacing: 0.5,
      ),
    ),
  );

  TextStyle _excelCellStyle() => const TextStyle(
    fontSize: 13,
    fontFamily: 'Consolas',
    color: Colors.black87,
  );

  // Editable cell for numbers
  Widget _excelEditableCell({
    required String value,
    required Function(String) onChanged,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      alignment: Alignment.centerLeft,
      child: TextFormField(
        initialValue: value,
        keyboardType: TextInputType.number,
        style: _excelCellStyle(),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.all(0),
        ),
        onChanged: onChanged,
      ),
    );
  }

  // Dropdown for excel-style cell
  Widget _excelDropdownCell(CostingItem item) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      alignment: Alignment.centerLeft,
      child: DropdownButton<String>(
        value: item.dropdownValue,
        underline: Container(),
        style: _excelCellStyle(),
        borderRadius: BorderRadius.circular(4),
        items: item.dropdownOptions
            ?.map(
              (o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: _excelCellStyle()),
              ),
            )
            .toList(),
        onChanged: (val) {
          setState(() {
            item.dropdownValue = val;
          });
        },
      ),
    );
  }

  Widget _summaryField(
    String label,
    TextEditingController controller,
    double value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 70,
            child: TextFormField(
              controller: controller,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: label,
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value.toStringAsFixed(0),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _summaryLabel(String label, double value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value.toStringAsFixed(0),
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
