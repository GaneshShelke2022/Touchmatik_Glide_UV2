/*
 * =============================================================================
 *  relay_output_page.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  The outputs OD-01..OD-16 of the panel: type, function, number, time.
 *  V1.1.0: a new row takes the lowest free OD label and the table stops at 16
 *  rows (M3); the THERMOSTAT-VALV function is shown as THERMOSTAT-VALVE (the
 *  stored TXT value stays THERMOSTAT-VALV, B5); numbers are digits only.
 * =============================================================================
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'input_assign_page.dart';
import '../../localization/app_localizations.dart';
import '../../data/app_data.dart';
import '../../themes/app_theme.dart';
import '../widgets/add_new_row_button.dart';

class RelayOutputPage extends StatefulWidget {
  const RelayOutputPage({super.key});

  @override
  State<RelayOutputPage> createState() => _RelayOutputPageState();
}

class _RelayOutputPageState extends State<RelayOutputPage> with SingleTickerProviderStateMixin {
  static const int _maxOutputs = 16;      // V3: 4 relay cards x 4 relays (config_store.h)
  static const List<String> _types = ['RLY', 'DIM'];
  // TXT values; 'THERMOSTAT-VALV' is the stored spelling, shown as THERMOSTAT-VALVE
  static const List<String> _outputs = ['LAMP', 'BELL', 'OCCUPANCY', 'FAN-LOW', 'FAN-MID', 'FAN-HIGH', 'CURTAIN-OPEN', 'CURTAIN-CLOSE', 'THERMOSTAT-LOW', 'THERMOSTAT-MID', 'THERMOSTAT-HIGH', 'THERMOSTAT-VALV', 'DIMMER'];

  final _formKey = GlobalKey<FormState>();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late List<Map<String, dynamic>> _rows;

  @override
  void initState() {
    super.initState();
    final data = AppDataManager();
    if (data.relayOutputRows.isNotEmpty) {
      _rows = data.relayOutputRows.map((r) => <String, dynamic>{
        'serialNumber': r['serialNumber'], 'type': r['type'],
        // an older file may carry the long spelling: keep one value per function
        'output': r['output'] == 'THERMOSTAT-VALVE' ? 'THERMOSTAT-VALV' : r['output'],
        'numberController': TextEditingController(text: r['number']?.toString() ?? ''),
        'timeController': TextEditingController(text: r['time']?.toString() ?? ''),
      }).toList();
    } else {
      final defaultCount = _defaultRowsForModule(data.panelSwitchModule);
      _rows = List.generate(defaultCount, (index) => _createNewRow(index + 1));
    }
    _animationController = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _animationController.forward();
  }

  Map<String, dynamic> _createNewRow(int serial) => {
    'serialNumber': 'OD-${serial.toString().padLeft(2, '0')}', 'type': null, 'output': null,
    'numberController': TextEditingController(), 'timeController': TextEditingController(),
  };

  int _serialOf(Map<String, dynamic> row) =>
      int.tryParse((row['serialNumber'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  // V1.1.0 (M3): the lowest OD number not in use, so delete + add never duplicates a label
  int _nextSerial() {
    final used = _rows.map(_serialOf).toSet();
    for (int n = 1; n <= _maxOutputs; n++) {
      if (!used.contains(n)) return n;
    }
    return 0;
  }

  int _defaultRowsForModule(String? module) {
    switch (module) {
      case '2M':
        return 4;
      case '4M':
        return 8;
      case '6M':
        return 12;
      case '8M':
        return 16;
      default:
        return 4;
    }
  }

  @override
  void dispose() {
    for (var row in _rows) { row['numberController'].dispose(); row['timeController'].dispose(); }
    _animationController.dispose();
    super.dispose();
  }

  void _addRow() {
    if (_rows.length >= _maxOutputs) return;
    final serial = _nextSerial();
    if (serial == 0) return;
    setState(() {
      // keep the table in OD order
      final at = _rows.indexWhere((r) => _serialOf(r) > serial);
      final row = _createNewRow(serial);
      if (at < 0) {
        _rows.add(row);
      } else {
        _rows.insert(at, row);
      }
    });
  }

  void _deleteRow(int index) {
    setState(() {
      _rows[index]['numberController'].dispose();
      _rows[index]['timeController'].dispose();
      _rows.removeAt(index);
    });
  }

  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
        final offset = Tween<Offset>(begin: const Offset(0.0, 0.04), end: Offset.zero).animate(fade);
        return FadeTransition(opacity: fade, child: SlideTransition(position: offset, child: child));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final atCap = _rows.length >= _maxOutputs;
    return Scaffold(
      backgroundColor: AppBrandColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 55, 12, 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Center(child: Text(AppLocalizations.of(context).t('relay_output_title'),
                              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary))),
                        ),
                        Container(
                          decoration: AppBrandColors.tableContainerDecoration,
                          child: Column(children: [
                            _buildHeader(),
                            ListView.builder(
                              shrinkWrap: true, padding: EdgeInsets.zero, physics: const NeverScrollableScrollPhysics(),
                              itemCount: _rows.length,
                              itemBuilder: (context, index) => _buildDataRow(_rows[index], index),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Opacity(
                              opacity: atCap ? 0.4 : 1.0,
                              child: IgnorePointer(
                                key: const ValueKey('add_row_gate'),
                                ignoring: atCap,
                                child: AddNewRowButton(onPressed: _addRow),
                              ),
                            ),
                            if (atCap)
                              Text(AppLocalizations.of(context).t('row_limit', params: {'max': '$_maxOutputs'}),
                                  style: GoogleFonts.inter(fontSize: 12, color: AppBrandColors.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final headerTextStyle = GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppBrandColors.textPrimary);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      decoration: AppBrandColors.tableHeaderDecoration,
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(AppLocalizations.of(context).t('s_no'), style: headerTextStyle)),
          Expanded(flex: 4, child: Text(AppLocalizations.of(context).t('type'), style: headerTextStyle)),
          const SizedBox(width: 8),
          Expanded(flex: 5, child: Text(AppLocalizations.of(context).t('output'), style: headerTextStyle)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: Text(AppLocalizations.of(context).t('number'), style: headerTextStyle)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: Text(AppLocalizations.of(context).t('time'), style: headerTextStyle)),
          const SizedBox(width: 8),
          SizedBox(width: 32, child: Text(AppLocalizations.of(context).t('del'), style: headerTextStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  // the text shown for a stored output value (B5: the valve keeps its TXT spelling)
  String _outputLabel(String value) =>
      value == 'THERMOSTAT-VALV' ? AppLocalizations.of(context).t('thermostat_valve') : value;

  Widget _buildDataRow(Map<String, dynamic> row, int index) {
    final String serial = row['serialNumber']?.toString() ?? '';
    return Container(
      key: ValueKey('od_row_$serial'),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: index.isEven ? AppBrandColors.background : AppBrandColors.card,
        border: Border(top: BorderSide(color: AppBrandColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 3, child: Text(serial, style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14, color: AppBrandColors.textPrimary))),
          Expanded(flex: 4, child: _buildDropdown(value: row['type'], items: _types, onChanged: (value) => setState(() => row['type'] = value), hint: AppLocalizations.of(context).t('select'))),
          const SizedBox(width: 6),
          Expanded(flex: 7, child: _buildDropdown(value: row['output'], items: _outputs, label: _outputLabel, onChanged: (value) => setState(() => row['output'] = value), hint: AppLocalizations.of(context).t('select'))),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: _buildTextField(row['numberController'], maxDigits: 3, max: 255)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: _buildTextField(row['timeController'], maxDigits: 5, max: 65535)),
          const SizedBox(width: 8),
          SizedBox(width: 32, child: Center(child: IconButton(key: ValueKey('od_delete_$serial'), padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20), onPressed: () => _deleteRow(index), tooltip: AppLocalizations.of(context).t('delete_row')))),
        ],
      ),
    );
  }

  Widget _buildDropdown({required String? value, required List<String> items, required Function(String?) onChanged, required String hint, String Function(String)? label}) {
    // a value from an old TXT that is not offered any more stays visible instead of crashing the dropdown
    final shown = (value != null && !items.contains(value)) ? [...items, value] : items;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppBrandColors.inputFieldBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppBrandColors.border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true, isDense: true, menuMaxHeight: 300,
          hint: Text(hint, style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textSecondary)),
          onChanged: onChanged,
          dropdownColor: AppBrandColors.dropdownMenuBg,
          items: shown.map<DropdownMenuItem<String>>((String item) => DropdownMenuItem<String>(value: item, child: Text(label != null ? label(item) : item, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary)))).toList(),
          icon: const Icon(Icons.keyboard_arrow_down, color: AppBrandColors.textSecondary, size: 18),
        ),
      ),
    );
  }

  // digits only; out of range is marked here and refused again by checkConfig before Generate
  Widget _buildTextField(TextEditingController controller, {required int maxDigits, required int max}) {
    return SizedBox(
      height: 40,
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(maxDigits)],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) {
          final n = int.tryParse((v ?? '').trim());
          return (n != null && n > max) ? '0..$max' : null;
        },
        decoration: InputDecoration(
          filled: true, fillColor: AppBrandColors.inputFieldBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          errorStyle: const TextStyle(fontSize: 0, height: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppBrandColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppBrandColors.accent, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
        ),
        style: GoogleFonts.inter(color: AppBrandColors.textPrimary),
        cursorColor: AppBrandColors.accent,
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 10),
      decoration: AppBrandColors.footerDecoration,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: () { if (Navigator.of(context).canPop()) Navigator.of(context).pop(); },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 28),
              decoration: BoxDecoration(color: AppBrandColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppBrandColors.border)),
              child: Text(AppLocalizations.of(context).t('back'), style: GoogleFonts.inter(color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500)),
            ),
          ),
          InkWell(
            onTap: () async {
              if (!(_formKey.currentState?.validate() ?? true)) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).t('fix_fields_first'))));
                return;
              }
              AppDataManager().relayOutputRows = _rows.map((r) => {
                'serialNumber': r['serialNumber'], 'type': r['type'], 'output': r['output'],
                'number': (r['numberController'] as TextEditingController).text,
                'time': (r['timeController'] as TextEditingController).text,
              }).toList();
              Navigator.of(context).push(_createRoute(const InputAssignPage()));
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 28),
              decoration: BoxDecoration(
                color: AppBrandColors.accent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Color(0x33F28C33), blurRadius: 12, offset: Offset(0, 6))],
              ),
              child: Text(AppLocalizations.of(context).t('next'), style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
