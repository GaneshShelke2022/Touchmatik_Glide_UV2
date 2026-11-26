/*
 * =============================================================================
 *  scene_assign_page.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  The scenes (Welcome, NoOccupancy, Scene-03..06) and their OD rows.
 *  V1.1.0: a new row takes the lowest free OD label and a scene stops at 16
 *  rows (M3); the dropdowns use initialValue (each row has its own widget key,
 *  so a deleted row never leaves its value on the next one); numbers are
 *  digits only. The scene output "dimmer_open/close" is labelled CURTAIN-OPEN/
 *  CLOSE in app_en.arb (M6); the stored values are unchanged.
 * =============================================================================
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'connectivity_page.dart';
import '../../localization/app_localizations.dart';
import '../../data/app_data.dart';
import '../../themes/app_theme.dart';
import '../widgets/add_new_row_button.dart';

class SceneAssignPage extends StatefulWidget {
  const SceneAssignPage({super.key});

  @override
  State<SceneAssignPage> createState() => _SceneAssignPageState();
}

class _SceneAssignPageState extends State<SceneAssignPage> with SingleTickerProviderStateMixin {
  static const int _maxSceneRows = 16;    // V3: 16 entries of 4 B per scene (0x6000 + j * 0x40)

  final _formKey = GlobalKey<FormState>();
  String? _selectedSceneType;
  int _uid = 0;                           // a unique id per row, for its widget key

  final List<String> _sceneKeys = ['Welcome', 'NoOccupancy', 'Scene-03', 'Scene-04', 'Scene-05', 'Scene-06'];
  final Map<String, String> _sceneLocaleKeys = {
    'Welcome': 'welcome', 'NoOccupancy': 'no_occupancy', 'Scene-03': 'scene_3',
    'Scene-04': 'scene_4', 'Scene-05': 'scene_5', 'Scene-06': 'scene_6',
  };
  final Map<String, List<Map<String, dynamic>>> _sceneRows = {};

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    final data = AppDataManager();
    for (var sceneType in _sceneKeys) {
      _sceneRows[sceneType] = [];
      var existingRowsForScene = data.sceneAssignRows.where((r) {
        final type = r['type'];
        if (type == sceneType) return true;
        if (sceneType == 'Welcome' && type == 'Scene-01') return true;
        if (sceneType == 'NoOccupancy' && type == 'Scene-02') return true;
        return false;
      }).toList();
      for (var r in existingRowsForScene) {
        _sceneRows[sceneType]!.add(_row(
          r['sr_no']?.toString() ?? 'OD-01',
          output: r['output']?.toString(),
          number: r['number']?.toString() ?? '',
          state: r['state']?.toString(),
          temp: r['temp']?.toString() ?? '',
          panelNo: r['panel_no']?.toString(),
        ));
      }
      if (_sceneRows[sceneType]!.isEmpty) {
        _sceneRows[sceneType]!.add(_row('OD-01'));
        _sceneRows[sceneType]!.add(_row('OD-02'));
      }
    }
    if (_selectedSceneType == null && _sceneKeys.isNotEmpty) _selectedSceneType = _sceneKeys.first;
    _animationController = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _animationController.forward();
  }

  Map<String, dynamic> _row(String srNo, {String? output, String number = '', String? state, String temp = '', String? panelNo}) => {
    'uid': _uid++, 'sr_no': srNo, 'output': output, 'number': TextEditingController(text: number),
    'state': state, 'temp': TextEditingController(text: temp), 'panel_no': panelNo,
  };

  final List<String> _outputOptions = ['lamp', 'fan', 'curtain', 'dimmer_open', 'dimmer_close', 'dimmer', 'thermostat'];
  final List<String> _stateOptions = ['on', 'off', ...List.generate(10, (i) => 'on_l${i + 1}')];
  final List<String> _panelNoOptions = List.generate(48, (i) => 'panel_${i + 1}');

  int _serialOf(Map<String, dynamic> row) =>
      int.tryParse((row['sr_no'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  // V1.1.0 (M3): the lowest OD number not in use in this scene
  int _nextSerial(List<Map<String, dynamic>> rows) {
    final used = rows.map(_serialOf).toSet();
    for (int n = 1; n <= _maxSceneRows; n++) {
      if (!used.contains(n)) return n;
    }
    return 0;
  }

  void _addNewRow() {
    if (_selectedSceneType == null) return;
    final rows = _sceneRows[_selectedSceneType]!;
    if (rows.length >= _maxSceneRows) return;
    final serial = _nextSerial(rows);
    if (serial == 0) return;
    setState(() {
      final at = rows.indexWhere((r) => _serialOf(r) > serial);
      final row = _row('OD-${serial.toString().padLeft(2, '0')}');
      if (at < 0) {
        rows.add(row);
      } else {
        rows.insert(at, row);
      }
    });
  }

  void _deleteRow(int index) {
    if (_selectedSceneType == null) return;
    setState(() {
      _sceneRows[_selectedSceneType]![index]['number'].dispose();
      _sceneRows[_selectedSceneType]![index]['temp'].dispose();
      _sceneRows[_selectedSceneType]!.removeAt(index);
    });
  }

  @override
  void dispose() {
    for (var sceneType in _sceneKeys) {
      for (var data in _sceneRows[sceneType]!) { data['number'].dispose(); data['temp'].dispose(); }
    }
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
    return Scaffold(
      backgroundColor: AppBrandColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              const SizedBox(height: 58),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: <Widget>[
                          Center(child: Text(AppLocalizations.of(context).t('scene_assign_title'),
                              style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary))),
                          const SizedBox(height: 12),
                          GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.5),
                            itemCount: _sceneKeys.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) => _buildSceneButton(_sceneKeys[index]),
                          ),
                          const SizedBox(height: 12),
                          if (_selectedSceneType != null) _buildSceneDetails(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _buildBottomNavigationBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSceneButton(String type) {
    final isSelected = _selectedSceneType == type;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? AppBrandColors.accent : AppBrandColors.toggleInactive,
        foregroundColor: isSelected ? Colors.white : AppBrandColors.textPrimary,
        elevation: isSelected ? 4 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSelected ? AppBrandColors.accent : AppBrandColors.border)),
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onPressed: () {
        setState(() {
          _selectedSceneType = type;
          final rows = _sceneRows[type]!;
          if (rows.isEmpty) { rows.add(_row('OD-01')); rows.add(_row('OD-02')); }
        });
      },
      child: Text(AppLocalizations.of(context).t(_sceneLocaleKeys[type] ?? type),
          style: GoogleFonts.inter(color: isSelected ? Colors.white : AppBrandColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 12),
          textAlign: TextAlign.center),
    );
  }

  Widget _buildSceneDetails() {
    final rows = _sceneRows[_selectedSceneType]!;
    final atCap = rows.length >= _maxSceneRows;
    return Column(
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            var data = rows[index];
            return Container(
              key: ValueKey('scene_row_${data['uid']}'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(color: AppBrandColors.card, border: Border.all(color: AppBrandColors.border), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x0AF28C33), blurRadius: 6, offset: Offset(0, 2))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [_buildHeaderCell(AppLocalizations.of(context).t('s_no'), flex: 1), _buildHeaderCell(AppLocalizations.of(context).t('output'), flex: 2), _buildHeaderCell(AppLocalizations.of(context).t('number'), flex: 2)]),
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _buildDataCell(Center(child: Text(data['sr_no'], style: GoogleFonts.inter(fontSize: 12, color: AppBrandColors.accent, fontWeight: FontWeight.bold))), flex: 1),
                    _buildDataCell(_buildStyledDropdown(data, 'output', _outputOptions), flex: 2),
                    _buildDataCell(_buildTextFormField(data, 'number'), flex: 2),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [_buildHeaderCell(AppLocalizations.of(context).t('state'), flex: 2), _buildHeaderCell(AppLocalizations.of(context).t('temp'), flex: 2), _buildHeaderCell(AppLocalizations.of(context).t('panel_no'), flex: 3)]),
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _buildDataCell(_buildStyledDropdown(data, 'state', _stateOptions), flex: 2),
                    _buildDataCell(_buildTextFormField(data, 'temp'), flex: 2),
                    _buildDataCell(_buildStyledDropdown(data, 'panel_no', _panelNoOptions), flex: 3),
                  ]),
                  Align(alignment: Alignment.centerRight, child: IconButton(icon: Icon(Icons.delete_outline, color: Colors.red.shade400), tooltip: AppLocalizations.of(context).t('delete_row'), onPressed: () => _deleteRow(index), padding: EdgeInsets.zero, constraints: const BoxConstraints())),
                ],
              ),
            );
          },
          separatorBuilder: (context, index) => const SizedBox(height: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Opacity(
              opacity: atCap ? 0.4 : 1.0,
              child: IgnorePointer(
                key: const ValueKey('add_row_gate'),
                ignoring: atCap,
                child: AddNewRowButton(onPressed: _addNewRow),
              ),
            ),
            if (atCap)
              Text(AppLocalizations.of(context).t('row_limit', params: {'max': '$_maxSceneRows'}),
                  style: GoogleFonts.inter(fontSize: 12, color: AppBrandColors.textSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(flex: flex, child: Text(text, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: AppBrandColors.textSecondary), textAlign: TextAlign.center));
  }

  Widget _buildDataCell(Widget child, {int flex = 1}) {
    return Expanded(flex: flex, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: child));
  }

  Widget _buildStyledDropdown(Map<String, dynamic> data, String key, List<String> options) {
    final String? value = data[key]?.toString();
    // a value from an older TXT that is not offered any more stays visible instead of crashing the dropdown
    final shown = (value != null && !options.contains(value)) ? [...options, value] : options;
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: AppBrandColors.styledInputDecoration(radius: 8).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
      isDense: true, isExpanded: true, menuMaxHeight: 200,
      icon: const Icon(Icons.arrow_drop_down, color: AppBrandColors.textSecondary, size: 18),
      style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500),
      dropdownColor: AppBrandColors.dropdownMenuBg,
      hint: Text(AppLocalizations.of(context).t('select'), style: GoogleFonts.inter(color: AppBrandColors.textSecondary, fontSize: 12)),
      items: shown.map((v) => DropdownMenuItem(value: v, child: Text(AppLocalizations.of(context).t(v), style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary)))).toList(),
      onChanged: (val) => setState(() => data[key] = val),
      selectedItemBuilder: (BuildContext context) => shown.map<Widget>((String item) => Align(alignment: Alignment.centerLeft, child: Text(AppLocalizations.of(context).t(item), overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500)))).toList(),
    );
  }

  // number and temperature: digits only, 0..255 (checkConfig warns about thermostat 16..32 and fan levels)
  TextFormField _buildTextFormField(Map<String, dynamic> data, String key) {
    return TextFormField(
      controller: data[key],
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) {
        final n = int.tryParse((v ?? '').trim());
        return (n != null && n > 255) ? '0..255' : null;
      },
      decoration: AppBrandColors.styledInputDecoration(radius: 8).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
      style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500),
      textAlign: TextAlign.center,
      cursorColor: AppBrandColors.accent,
    );
  }

  bool _allNumbersValid() {
    for (final rows in _sceneRows.values) {
      for (final r in rows) {
        for (final k in ['number', 'temp']) {
          final n = int.tryParse((r[k] as TextEditingController).text.trim());
          if (n != null && n > 255) return false;
        }
      }
    }
    return true;
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: AppBrandColors.footerDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: () { if (Navigator.of(context).canPop()) Navigator.of(context).pop(); },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 30),
              decoration: BoxDecoration(color: AppBrandColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppBrandColors.border)),
              child: Text(AppLocalizations.of(context).t('back'), style: GoogleFonts.inter(color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 16)),
            ),
          ),
          InkWell(
            onTap: () {
              // every scene is checked, not only the one on screen
              if (!_allNumbersValid()) {
                _formKey.currentState?.validate();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).t('fix_fields_first'))));
                return;
              }
              List<Map<String, dynamic>> allRows = [];
              _sceneRows.forEach((sceneType, rows) {
                for (var row in rows) {
                  allRows.add({'type': sceneType, 'sr_no': row['sr_no'], 'output': row['output'], 'number': (row['number'] as TextEditingController).text, 'state': row['state'], 'temp': (row['temp'] as TextEditingController).text, 'panel_no': row['panel_no']});
                }
              });
              AppDataManager().sceneAssignRows = allRows;
              Navigator.of(context).push(_createRoute(const ConnectivityPage()));
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 30),
              decoration: BoxDecoration(
                color: AppBrandColors.accent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Color(0x33F28C33), blurRadius: 12, offset: Offset(0, 6))],
              ),
              child: Text(AppLocalizations.of(context).t('next'), style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
