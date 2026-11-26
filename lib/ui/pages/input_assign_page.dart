/*
 * =============================================================================
 *  input_assign_page.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  The digital inputs IP-01..IP-04 of the panel.
 *  V1.1.0: the panel is shown read-only (it is the one chosen on the Panel
 *  page, B2); a new row takes the lowest free IP label and the table stops at
 *  4 rows (M3); TOGGLE is offered as output state; numbers are digits only.
 * =============================================================================
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'scene_assign_page.dart';
import '../../localization/app_localizations.dart';
import '../../data/app_data.dart';
import '../../themes/app_theme.dart';
import '../widgets/add_new_row_button.dart';

class InputAssignPage extends StatefulWidget {
  const InputAssignPage({super.key});

  @override
  State<InputAssignPage> createState() => _InputAssignPageState();
}

class _InputAssignPageState extends State<InputAssignPage> with SingleTickerProviderStateMixin {
  static const int _maxInputs = 4;        // V3: 4 inputs per panel, 32 B each at 0x4000 + (N-1) * 0x80
  static final List<String> _levels = List.generate(10, (i) => 'ON-L-${i + 1}');

  final _formKey = GlobalKey<FormState>();
  String? selectedPanel;
  List<Map<String, dynamic>> rows = [];

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    final data = AppDataManager();
    // V1.1.0 (B2): one panel number, chosen on the Panel page
    selectedPanel = data.panelSwitchPanel;
    if (data.inputAssignRows.isNotEmpty) {
      rows = data.inputAssignRows.map((r) => <String, dynamic>{
        'sr': r['sr'], 'type': r['type'], 'inputState': r['inputState'],
        'outputDevice': r['outputDevice'], 'deviceNoController': TextEditingController(text: r['deviceNo']?.toString() ?? ''),
        'outputState': r['outputState'], 'timeController': TextEditingController(text: r['time']?.toString() ?? ''),
        'defaultState': r['defaultState'],
      }).toList();
    } else {
      rows = List.generate(_maxInputs, (index) => _newRow(index + 1));
    }
    _animationController = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _animationController.forward();
  }

  Map<String, dynamic> _newRow(int serial) => {
    'sr': 'IP-${serial.toString().padLeft(2, '0')}', 'type': null, 'inputState': null,
    'outputDevice': null, 'deviceNoController': TextEditingController(),
    'outputState': null, 'timeController': TextEditingController(), 'defaultState': null,
  };

  int _serialOf(Map<String, dynamic> row) =>
      int.tryParse((row['sr'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  // V1.1.0 (M3): the lowest IP number not in use
  int _nextSerial() {
    final used = rows.map(_serialOf).toSet();
    for (int n = 1; n <= _maxInputs; n++) {
      if (!used.contains(n)) return n;
    }
    return 0;
  }

  @override
  void dispose() {
    for (var r in rows) { r['deviceNoController'].dispose(); r['timeController'].dispose(); }
    _animationController.dispose();
    super.dispose();
  }

  void _addRow() {
    if (rows.length >= _maxInputs) return;
    final serial = _nextSerial();
    if (serial == 0) return;
    setState(() {
      final at = rows.indexWhere((r) => _serialOf(r) > serial);
      final row = _newRow(serial);
      if (at < 0) {
        rows.add(row);
      } else {
        rows.insert(at, row);
      }
    });
  }

  void _deleteRow(int index) {
    if (index < 0) return;
    setState(() {
      rows[index]['deviceNoController'].dispose();
      rows[index]['timeController'].dispose();
      rows.removeAt(index);
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

  // the read-only panel line (B2)
  Widget _buildPanelLabel() {
    final loc = AppLocalizations.of(context);
    final text = selectedPanel == null
        ? loc.t('panel_not_chosen')
        : loc.t('panel_from_panel_page', params: {'panel': selectedPanel!});
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppBrandColors.cardDecoration,
      child: Row(
        children: [
          Icon(selectedPanel == null ? Icons.warning_amber_rounded : Icons.lock_outline, size: 18,
              color: selectedPanel == null ? Colors.orange : AppBrandColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, key: const ValueKey('input_panel_label'),
                style: GoogleFonts.inter(fontSize: 14, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final atCap = rows.length >= _maxInputs;
    return Scaffold(
      backgroundColor: AppBrandColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 60, 12, 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 15.0),
                          child: Center(child: Text(AppLocalizations.of(context).t('input_assign_title'),
                              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary))),
                        ),
                        _buildPanelLabel(),
                        const SizedBox(height: 15),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: rows.map((row) => _buildIpSection(row)).toList(),
                        ),
                        // Add Row (disabled at 4)
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
                              Text(AppLocalizations.of(context).t('row_limit', params: {'max': '$_maxInputs'}),
                                  style: GoogleFonts.inter(fontSize: 12, color: AppBrandColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 12),
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
                        final manager = AppDataManager();
                        // V1.1.0 (B2): inputs always belong to the Panel page's panel
                        manager.inputAssignPanel = manager.panelSwitchPanel;
                        manager.inputAssignRows = rows.map((r) => {
                          'sr': r['sr'], 'type': r['type'], 'inputState': r['inputState'],
                          'outputDevice': r['outputDevice'], 'deviceNo': (r['deviceNoController'] as TextEditingController).text,
                          'outputState': r['outputState'], 'time': (r['timeController'] as TextEditingController).text,
                          'defaultState': r['defaultState'],
                        }).toList();
                        Navigator.of(context).push(_createRoute(const SceneAssignPage()));
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 25),
                        decoration: BoxDecoration(
                          color: AppBrandColors.accent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Color(0x33F28C33), blurRadius: 12, offset: Offset(0, 6))],
                        ),
                        child: Text(AppLocalizations.of(context).t('next'), style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIpSection(Map<String, dynamic> row) {
    final String sr = row['sr']?.toString() ?? '';
    return Container(
      key: ValueKey('ip_row_$sr'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppBrandColors.card,
        border: Border.all(color: AppBrandColors.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0AF28C33), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 45,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            decoration: BoxDecoration(color: AppBrandColors.accentLight, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppBrandColors.border)),
            child: Text(sr, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppBrandColors.accent)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: _buildStyledDropdownField(AppLocalizations.of(context).t('type'), row, 'type', ['DIGITAL-LATCH', 'DIGITAL-PULSE'])),
                  const SizedBox(width: 6),
                  Expanded(child: _buildStyledDropdownField(AppLocalizations.of(context).t('input_state'), row, 'inputState', ['LOW', 'HIGH'])),
                  const SizedBox(width: 6),
                  Expanded(child: _buildStyledDropdownField(AppLocalizations.of(context).t('output_device'), row, 'outputDevice', ['LAMP', 'FAN-ON/OFF', 'CURTAIN-OPEN', 'CURTAIN-CLOSE', 'DIMMER', 'OCCUPANCY', 'SCENE'])),
                  const SizedBox(width: 6),
                  Expanded(child: _buildStyledTextField(AppLocalizations.of(context).t('device_no'), row, 'deviceNoController', maxDigits: 3, max: 255)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  // V1.1.0: TOGGLE as output state (stateByte 0x11)
                  Expanded(child: _buildStyledDropdownField(AppLocalizations.of(context).t('output_state'), row, 'outputState', ['ON', 'OFF', 'TOGGLE', ..._levels])),
                  const SizedBox(width: 6),
                  Expanded(child: _buildStyledTextField(AppLocalizations.of(context).t('time'), row, 'timeController', maxDigits: 5, max: 65535)),
                  const SizedBox(width: 6),
                  Expanded(child: _buildStyledDropdownField(AppLocalizations.of(context).t('default_state'), row, 'defaultState', ['ON', 'OFF', 'TOGGLE', ..._levels])),
                  const SizedBox(width: 6),
                  Expanded(child: Align(alignment: Alignment.centerRight, child: IconButton(key: ValueKey('ip_delete_$sr'), icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20), onPressed: () => _deleteRow(rows.indexOf(row)), tooltip: AppLocalizations.of(context).t('delete_row'), padding: EdgeInsets.zero, constraints: const BoxConstraints()))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledDropdownField(String label, Map<String, dynamic> row, String key, List<String> items) {
    final String? value = row[key]?.toString();
    // a value from an older TXT that is not offered any more stays visible instead of crashing the dropdown
    final shown = (value != null && !items.contains(value)) ? [...items, value] : items;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppBrandColors.textSecondary, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: AppBrandColors.styledInputDecoration(radius: 8).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        isExpanded: true, isDense: true, menuMaxHeight: 200,
        icon: const Icon(Icons.arrow_drop_down, color: AppBrandColors.textSecondary, size: 18),
        style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500),
        dropdownColor: AppBrandColors.dropdownMenuBg,
        hint: Text(AppLocalizations.of(context).t('select'), style: GoogleFonts.inter(color: AppBrandColors.textSecondary, fontSize: 12)),
        items: shown.map((v) => DropdownMenuItem(value: v, child: Text(v, style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary)))).toList(),
        onChanged: (v) => setState(() => row[key] = v),
        selectedItemBuilder: (context) => shown.map((item) => Container(alignment: Alignment.centerLeft, child: Text(item, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w600)))).toList(),
      ),
    ]);
  }

  // digits only; out of range is marked here and refused again by checkConfig before Generate
  Widget _buildStyledTextField(String label, Map<String, dynamic> row, String key, {required int maxDigits, required int max}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppBrandColors.textSecondary, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      TextFormField(
        controller: row[key],
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(maxDigits)],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) {
          final n = int.tryParse((v ?? '').trim());
          return (n != null && n > max) ? '0..$max' : null;
        },
        decoration: AppBrandColors.styledInputDecoration(radius: 8).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500),
        cursorColor: AppBrandColors.accent,
      ),
    ]);
  }
}
