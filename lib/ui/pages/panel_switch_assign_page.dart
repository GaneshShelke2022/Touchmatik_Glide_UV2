/*
 * =============================================================================
 *  panel_switch_assign_page.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  The Panel page: the ONE panel number of this configuration (required; it is
 *  also used for inputs, the network page and the HEX header), the board
 *  location, the module size and the key rows SW-01..SW-20.
 *  V1.1.0: the panel is required (B2); the row icon clears a key instead of
 *  deleting it, so the following keys keep their SW numbers (M2); numbers are
 *  digits only; a key function from a TXT that the list does not offer is
 *  kept, not dropped (review_glide finding 7).
 * =============================================================================
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'relay_output_page.dart';
import '../../localization/app_localizations.dart';
import '../../data/app_data.dart';
import '../../themes/app_theme.dart';
import '../widgets/add_new_row_button.dart';

class PanelSwitchAssignPage extends StatefulWidget {
  const PanelSwitchAssignPage({super.key});

  @override
  State<PanelSwitchAssignPage> createState() => _PanelSwitchAssignPageState();
}

class _PanelSwitchAssignPageState extends State<PanelSwitchAssignPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  String? _selectedPanel;
  String? _selectedModule = '2M';
  final _boardLocationCtrl = TextEditingController();

  // One map per key row: 'function', 'numberCtrl' and 'gen'. The row index IS the
  // key number (row 0 = SW-01). 'gen' changes when a row is cleared, so the row
  // gets a new widget key and its dropdown forgets the old value.
  final List<Map<String, dynamic>> _rows = [];

  static const int _maxSwitches = 20;
  static const List<String> _functions = [
    'LAMP',
    'BELL',
    'FAN-ON/OFF',
    'FAN-UP',
    'FAN-DOWN',
    'CURTAIN-OPEN',
    'CURTAIN-CLOSE',
    'DIMMER-ON/OFF',
    'DIMMER-UP',
    'DIMMER-DOWN',
    'DIMMER-RLOVR',
    'MASTER',
    'OCCUPANCY',
    'DND',
    'MMR',
    'LAUNDRY',
    'SCENE',
    'SCENE OFF',
    'SCENE TOGGLE',
    'THERMOSTAT-ON/OFF',
    'THERMOSTAT-FAN',
    'THERMOSTAT-T-UP',
    'THERMOSTAT-T-DN',
    'THERMOSTAT-MODE',
  ];

  // Define valid dropdown items
  final List<String> _validPanels = List<String>.generate(48, (i) => 'Panel-${(i + 1).toString().padLeft(2, '0')}');
  final List<String> _validModules = ['2M', '4M', '6M', '8M'];

  final Map<String, String> _functionLocaleKeys = {
    'LAMP': 'lamp_device',
    'BELL': 'bell',
     'FAN-ON/OFF': 'fan_on_off',
    'FAN-UP': 'fan_up',
     'FAN-DOWN': 'fan_down',
     'CURTAIN-OPEN': 'curtain_open',
    'CURTAIN-CLOSE': 'curtain_close',
    'DIMMER-ON/OFF': 'dimmer_on_off',
    'DIMMER-UP': 'dimmer_up',
     'DIMMER-DOWN': 'dimmer_down',
    'DIMMER-RLOVR': 'dimmer_rlover',
    'MASTER': 'master',
    'OCCUPANCY': 'occupancy',
    'DND': 'dnd',
     'MMR': 'mmr',
     'LAUNDRY': 'laundry',
      'SCENE': 'scene',
    'SCENE OFF': 'scene_off',
     'SCENE TOGGLE': 'scene_toggle',
    'THERMOSTAT-ON/OFF': 'thermostat_on_off',
    'THERMOSTAT-FAN': 'thermostat_fan',
    'THERMOSTAT-T-UP': 'thermostat_t_up',
    'THERMOSTAT-T-DN': 'thermostat_t_dn',
    'THERMOSTAT-MODE': 'thermostat_mode',
  };

  String _localizedLabel(String item) {
    final loc = AppLocalizations.of(context);
    final panelMatch = RegExp(r'^Panel-(\d{2})$').firstMatch(item);
    if (panelMatch != null) {
      final num = int.parse(panelMatch.group(1)!);
      return loc.t('panel_$num');
    }
    if (_functionLocaleKeys.containsKey(item)) return loc.t(_functionLocaleKeys[item]!);
    final norm = item.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final translated = loc.t(norm);
    if (translated != norm) return translated;
    return item;
  }

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    final data = AppDataManager();
    if (data.panelSwitchPanel != null) {
      _selectedPanel = _validateValue(data.panelSwitchPanel, _validPanels);
      _boardLocationCtrl.text = data.panelSwitchLocation ?? '';
      _selectedModule = _validateValue(data.panelSwitchModule, _validModules) ?? '2M';
      if (data.panelSwitchRows.isNotEmpty) {
        for (var r in data.panelSwitchRows) {
          // a function this list does not offer (an older TXT's 'SCENE-OFF',
          // 'DND-STATUS', ...) is kept, as the other pages keep theirs; dropping
          // it turned the key into action 00 (review_glide finding 7)
          final function = r['function']?.toString().trim();
          _rows.add(_newRow(
            function: (function == null || function.isEmpty) ? null : function,
            number: r['number']?.toString() ?? '',
          ));
        }
        // An opened TXT may hold more keys than the module's default (txt_reader
        // raises the module then): never cut rows that carry a key here.
        _growModuleToFitRows();
        _adjustRowsForModule();
      } else {
        final count = _defaultRowsForModule(_selectedModule);
        for (var i = 0; i < count; i++) {
          _rows.add(_newRow());
        }
      }
    } else {
      final count = _defaultRowsForModule(_selectedModule);
      for (var i = 0; i < count; i++) {
        _rows.add(_newRow());
      }
    }
    _animationController = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _animationController.forward();
  }

  Map<String, dynamic> _newRow({String? function, String number = ''}) =>
      {'function': function, 'numberCtrl': TextEditingController(text: number), 'gen': 0};

  String? _validateValue(String? value, List<String> validItems) {
    if (value == null) return null;
    return validItems.contains(value.trim()) ? value.trim() : null;
  }

  bool _rowUsed(Map<String, dynamic> row) =>
      row['function'] != null || (row['numberCtrl'] as TextEditingController).text.trim().isNotEmpty;

  void _addRow() {
    if (_rows.length >= _maxSwitches) return;
    setState(() => _rows.add(_newRow()));
  }

  // V1.1.0 (M2): clear the key instead of removing the row, so SW-03 stays SW-03
  void _clearRow(int index) {
    if (index < 0 || index >= _rows.length) return;
    setState(() {
      final row = _rows[index];
      row['function'] = null;
      (row['numberCtrl'] as TextEditingController).clear();
      row['gen'] = (row['gen'] as int) + 1;
    });
  }

  String _swLabel(int index) => 'SW-${(index + 1).toString().padLeft(2, '0')}';

  int _defaultRowsForModule(String? module) {
    switch (module) {
      case '2M':
        return 5;
      case '4M':
        return 10;
      case '6M':
        return 15;
      case '8M':
        return 20;
      default:
        return 4;
    }
  }

  // the smallest module that keeps every row that carries a key
  void _growModuleToFitRows() {
    int lastUsed = -1;
    for (int i = 0; i < _rows.length; i++) {
      if (_rowUsed(_rows[i])) lastUsed = i;
    }
    while (lastUsed + 1 > _defaultRowsForModule(_selectedModule) && _selectedModule != '8M') {
      _selectedModule = _validModules[_validModules.indexOf(_selectedModule ?? '2M') + 1];
    }
  }

  void _adjustRowsForModule() {
    final expectedCount = _defaultRowsForModule(_selectedModule);
    while (_rows.length > expectedCount) {
      final removed = _rows.removeLast();
      (removed['numberCtrl'] as TextEditingController).dispose();
    }
    while (_rows.length < expectedCount) {
      _rows.add(_newRow());
    }
  }

  @override
  void dispose() {
    for (final r in _rows) { (r['numberCtrl'] as TextEditingController).dispose(); }
    _boardLocationCtrl.dispose();
    _animationController.dispose();
    super.dispose();
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
    final panels = _validPanels;
    final atCap = _rows.length >= _maxSwitches;
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Title
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Center(
                            child: Text(
                              AppLocalizations.of(context).t('panel_switch_assign_title'),
                              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary),
                            ),
                          ),
                        ),
                        _buildPanelCard(panels),
                        const SizedBox(height: 20),
                        _buildSwitchesTable(),
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
                              Text(AppLocalizations.of(context).t('row_limit', params: {'max': '$_maxSwitches'}),
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

  Widget _buildPanelCard(List<String> panels) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppBrandColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppBrandColors.border),
        boxShadow: const [BoxShadow(color: Color(0x1AF28C33), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildStyledDropdownField(
                  key: const ValueKey('panel_select'),
                  label: AppLocalizations.of(context).t('select_panel'),
                  value: _selectedPanel,
                  items: panels,
                  onChanged: (v) => setState(() => _selectedPanel = v),
                  // V1.1.0 (B2): the one panel number of this configuration is required
                  validator: (v) => v == null ? AppLocalizations.of(context).t('select_panel_required') : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildStyledInputField(controller: _boardLocationCtrl, label: AppLocalizations.of(context).t('board_location'))),
            ],
          ),
          const SizedBox(height: 16),
          _buildStyledDropdownField(
            label: AppLocalizations.of(context).t('select_module'),
            value: _selectedModule,
            items: _validModules,
            onChanged: (v) => setState(() {
              _selectedModule = v;
              _adjustRowsForModule();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchesTable() {
    return Container(
      decoration: AppBrandColors.tableContainerDecoration,
      child: Column(
        children: [
          _buildTableHeader(),
          ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _rows.length,
            itemBuilder: (context, index) {
              final row = _rows[index];
              final numberCtrl = row['numberCtrl'] as TextEditingController;
              return Container(
                key: ValueKey('sw$index-${row['gen']}'),
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: index.isEven ? AppBrandColors.background : AppBrandColors.card,
                  border: Border(top: BorderSide(color: AppBrandColors.divider)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 3, child: Text(_swLabel(index), style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14, color: AppBrandColors.textPrimary))),
                    Expanded(flex: 5, child: _buildStyledTableDropdown(value: row['function'] as String?, items: _functions, onChanged: (v) => setState(() => row['function'] = v), hint: AppLocalizations.of(context).t('select'))),
                    const SizedBox(width: 8),
                    Expanded(flex: 3, child: _buildStyledTableTextField(numberCtrl)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 32,
                      child: Center(
                        child: IconButton(
                          key: ValueKey('sw_clear_$index'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.backspace_outlined, color: Colors.red.shade400, size: 20),
                          onPressed: () => _clearRow(index),
                          tooltip: AppLocalizations.of(context).t('clear_row'),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    final headerTextStyle = GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppBrandColors.textPrimary);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      decoration: AppBrandColors.tableHeaderDecoration,
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(AppLocalizations.of(context).t('s_no'), style: headerTextStyle)),
          Expanded(flex: 5, child: Text(AppLocalizations.of(context).t('functions'), style: headerTextStyle)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: Text(AppLocalizations.of(context).t('number'), style: headerTextStyle)),
          const SizedBox(width: 8),
          SizedBox(width: 32, child: Text(AppLocalizations.of(context).t('del'), style: headerTextStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildStyledDropdownField({Key? key, required String label, required String? value, required List<String> items, required Function(String?) onChanged, FormFieldValidator<String>? validator}) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: value,
      decoration: AppBrandColors.styledInputDecoration(label: label, radius: 10),
      hint: Text(label, style: GoogleFonts.inter(color: AppBrandColors.textSecondary)),
      dropdownColor: AppBrandColors.dropdownMenuBg,
      style: GoogleFonts.inter(color: AppBrandColors.textPrimary),
      isExpanded: true,
      isDense: true,
      menuMaxHeight: 300,
      onChanged: onChanged,
      validator: validator,
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(_localizedLabel(item), style: GoogleFonts.inter(fontSize: 14, color: AppBrandColors.textPrimary), overflow: TextOverflow.ellipsis))).toList(),
      icon: const Icon(Icons.keyboard_arrow_down, color: AppBrandColors.textSecondary),
      selectedItemBuilder: (BuildContext context) => items.map<Widget>((String item) => Text(_localizedLabel(item), overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: AppBrandColors.textPrimary))).toList(),
    );
  }

  Widget _buildStyledInputField({required TextEditingController controller, required String label}) {
    return TextFormField(
      controller: controller,
      style: GoogleFonts.inter(color: AppBrandColors.textPrimary),
      cursorColor: AppBrandColors.accent,
      decoration: AppBrandColors.styledInputDecoration(label: label, radius: 10),
    );
  }

  Widget _buildStyledTableDropdown({required String? value, required List<String> items, required Function(String?) onChanged, required String hint}) {
    // a value from an old TXT that is not offered any more stays visible (and stored) instead of crashing the dropdown
    final shown = (value != null && !items.contains(value)) ? [...items, value] : items;
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: AppBrandColors.styledInputDecoration(radius: 8).copyWith(hintText: hint, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
      hint: Text(hint, style: GoogleFonts.inter(color: AppBrandColors.textSecondary, fontSize: 12)),
      dropdownColor: AppBrandColors.dropdownMenuBg,
      style: GoogleFonts.inter(color: AppBrandColors.textPrimary),
      isExpanded: true,
      isDense: true,
      menuMaxHeight: 300,
      onChanged: onChanged,
      items: shown.map((item) => DropdownMenuItem(value: item, child: Text(item, style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary), overflow: TextOverflow.ellipsis))).toList(),
      icon: const Icon(Icons.keyboard_arrow_down, color: AppBrandColors.textSecondary, size: 18),
      selectedItemBuilder: (BuildContext context) => shown.map<Widget>((String item) => Text(item, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: AppBrandColors.textPrimary, fontSize: 13))).toList(),
    );
  }

  // key / device number: digits only, 0..255 (the firmware's byte; checkConfig warns about the soft limits)
  Widget _buildStyledTableTextField(TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) {
        final n = int.tryParse((v ?? '').trim());
        if (n != null && n > 255) {
          return AppLocalizations.of(context).t('field_number_range', params: {'min': '0', 'max': '255'});
        }
        return null;
      },
      style: GoogleFonts.inter(color: AppBrandColors.textPrimary),
      cursorColor: AppBrandColors.accent,
      decoration: AppBrandColors.styledInputDecoration(radius: 8).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
    );
  }

  void _saveToManager() {
    final manager = AppDataManager();
    manager.panelSwitchPanel = _selectedPanel;
    manager.panelSwitchLocation = _boardLocationCtrl.text;
    manager.panelSwitchModule = _selectedModule;
    manager.panelSwitchRows = _rows.map((r) => {'function': r['function'], 'number': (r['numberCtrl'] as TextEditingController).text}).toList();
    // V1.1.0 (B2): one panel number for keys, outputs, inputs, the network page and the header
    manager.inputAssignPanel = _selectedPanel;
    manager.wifiPanel = _selectedPanel;
  }

  Widget _buildFooter() {
    return Container(
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
            key: const ValueKey('panel_next'),
            onTap: () async {
              if (!_formKey.currentState!.validate()) return;
              _saveToManager();
              Navigator.of(context).push(_createRoute(const RelayOutputPage()));
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
