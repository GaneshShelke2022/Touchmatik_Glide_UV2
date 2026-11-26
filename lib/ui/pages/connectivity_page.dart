/*
 * =============================================================================
 *  connectivity_page.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  The network page of the panel: Modbus (no network page) or WiFi/BLE with
 *  Mqtt-HA (broker, port, user, password) or Tuya (PID), and the DP map.
 *  V1.1.0: the panel is shown read-only (the Panel page's number, B2); the DP
 *  parameter list matches the firmware's types (M8) and stops at 24 rows; the
 *  number fields are digits only; the strings are checked against the
 *  firmware limits (B8: broker <= 62, user / password / PID <= 30 printable
 *  ASCII characters without '"', port 1..65535).
 * =============================================================================
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'preview_page.dart';
import '../../data/app_data.dart';
import '../../localization/app_localizations.dart';
import '../../themes/app_theme.dart';
import '../widgets/add_new_row_button.dart';

class MqttDeviceRow {
  String? parameter;
  final TextEditingController deviceNoController = TextEditingController();
  final TextEditingController dpIdController = TextEditingController();
  MqttDeviceRow({this.parameter});
}

class TuyaDeviceRow {
  String? parameter;
  final TextEditingController deviceNoController = TextEditingController();
  final TextEditingController dpIdController = TextEditingController();
  TuyaDeviceRow({this.parameter});
}

// Firmware string limits (net_gui.c): the broker spans 4 HEX lines, the others 2.
const int kBrokerMaxChars = 62;
const int kUserMaxChars = 30;
const int kPasswordMaxChars = 30;
const int kPidMaxChars = 30;
const int kDpRowsMax = 24;                // 0xA0..0xFF = 96 B = 24 pairs of 4 B

// DP parameters offered (V1.1.0, M8): one per type code the firmware handles
// (C-5.2). Not offered: MASTER, SCENE-OFF, SCENE-TOGGLE, INPUT-TW.
const List<String> kDpParameters = [
  'LAMP', 'BELL', 'OCCUPANCY', 'DND', 'MMR', 'LAUNDRY',
  'FAN-ON-OFF', 'FAN-SPEED', 'FAN-REG-LOCK',
  'DIMMER-ON-OFF', 'DIMMER-BRIGHTNESS', 'CURTAIN', 'SCENE',
  'THERMOSTAT-ON-OFF', 'THERMOSTAT-FAN', 'THERMOSTAT-STEMP', 'THERMOSTAT-ATEMP', 'THERMOSTAT-MODE',
  'PROXY-SWITCH', 'CHILD-LOCK', 'DEVICE-RESTART', 'PANEL-BACKLIGHTMIN',
];

// printable ASCII 0x20..0x7E without the double quote (it ends the quoted field in the HEX)
final RegExp _allowedChar = RegExp(r'[\x20\x21\x23-\x7E]');
final RegExp _allowedText = RegExp(r'^[\x20\x21\x23-\x7E]*$');

class ConnectivityPage extends StatefulWidget {
  const ConnectivityPage({super.key});

  @override
  State<ConnectivityPage> createState() => _ConnectivityPageState();
}

class _ConnectivityPageState extends State<ConnectivityPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  int _selectedConnectivity = 0;
  String? _selectedBaudRate;
  String? _selectedDataBit;
  String? _selectedStopBit;
  String? _selectedParity;
  String? _selectedPanel;
  String? _selectedWifiMode;

  final _mqttBrokerAddressController = TextEditingController();
  final _mqttPortController = TextEditingController();
  final _userNameController = TextEditingController();
  final _passwordController = TextEditingController();
  List<MqttDeviceRow> _mqttDeviceRows = [];

  final _pidController = TextEditingController();
  List<TuyaDeviceRow> _tuyaDeviceRows = [];

  final List<bool> _connectivitySelection = <bool>[true, false];

  // Define valid dropdown items
  final List<String> _validWifiModes = ['Mqtt-HA', 'Tuya-wifi', 'Tuya-BLE'];
  final List<String> _validBaudRates = ['300', '600', '1200', '2400', '4800', '9600', '14400', '19200', '38400', '56000', '57600', '115200', '128000', '230400', '256000', '460800', '921600'];
  final List<String> _validDataBits = ['5', '8'];
  final List<String> _validStopBits = ['1', '2'];
  final List<String> _validParities = ['None', 'Odd', 'Even'];

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    final data = AppDataManager();
    // V1.1.0 (B2): the network page always belongs to the Panel page's panel
    _selectedPanel = data.panelSwitchPanel;
    _selectedConnectivity = data.connectivityType;
    _connectivitySelection[0] = _selectedConnectivity == 0;
    _connectivitySelection[1] = _selectedConnectivity == 1;
    _selectedBaudRate = _validateValue(data.modbusBaudRate, _validBaudRates);
    _selectedDataBit = _validateValue(data.modbusDataBit, _validDataBits);
    _selectedStopBit = _validateValue(data.modbusStopBit, _validStopBits);
    _selectedParity = _validateValue(data.modbusParity, _validParities);
    _selectedWifiMode = _validateValue(data.wifiMode, _validWifiModes);
    // both WiFi variants are prefilled, so switching the mode back and forth loses nothing
    _mqttBrokerAddressController.text = data.mqttBroker ?? '';
    _mqttPortController.text = data.mqttPort ?? '';
    _userNameController.text = data.mqttUser ?? '';
    _passwordController.text = data.mqttPassword ?? '';
    if (data.mqttDevices.isNotEmpty) {
      _mqttDeviceRows = data.mqttDevices.map((r) { final row = MqttDeviceRow(parameter: r['parameter']?.toString()); row.deviceNoController.text = r['deviceNo']?.toString() ?? ''; row.dpIdController.text = r['dpId']?.toString() ?? ''; return row; }).toList();
    } else { _mqttDeviceRows = [MqttDeviceRow(), MqttDeviceRow()]; }
    _pidController.text = data.tuyaPid ?? '';
    if (data.tuyaDevices.isNotEmpty) {
      _tuyaDeviceRows = data.tuyaDevices.map((r) { final row = TuyaDeviceRow(parameter: r['parameter']?.toString()); row.deviceNoController.text = r['deviceNo']?.toString() ?? ''; row.dpIdController.text = r['dpId']?.toString() ?? ''; return row; }).toList();
    } else { _tuyaDeviceRows = [TuyaDeviceRow(), TuyaDeviceRow()]; }
    _animationController = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _animationController.forward();
  }

  String? _validateValue(String? value, List<String> validItems) {
    if (value == null) return null;
    return validItems.contains(value.trim()) ? value.trim() : null;
  }

  @override
  void dispose() {
    _mqttBrokerAddressController.dispose(); _mqttPortController.dispose();
    _userNameController.dispose(); _passwordController.dispose();
    for (var row in _mqttDeviceRows) { row.deviceNoController.dispose(); row.dpIdController.dispose(); }
    _pidController.dispose();
    for (var row in _tuyaDeviceRows) { row.deviceNoController.dispose(); row.dpIdController.dispose(); }
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

  // ---- validators (B8) ------------------------------------------------------

  String? _textRule(String? v, int maxChars) {
    final t = v ?? '';
    final loc = AppLocalizations.of(context);
    if (t.length > maxChars) return loc.t('field_max_chars', params: {'max': '$maxChars'});
    if (!_allowedText.hasMatch(t)) return loc.t('field_ascii_only');
    return null;
  }

  String? _portRule(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;                        // empty: the firmware default port
    final n = int.tryParse(t);
    if (n == null || n < 1 || n > 65535) return AppLocalizations.of(context).t('field_port_range');
    return null;
  }

  String? Function(String?) _numberRule(int max) => (String? v) {
    final n = int.tryParse((v ?? '').trim());
    return (n != null && n > max) ? '0..$max' : null;
  };

  List<TextInputFormatter> _textFormatters(int maxChars) => [
    FilteringTextInputFormatter.allow(_allowedChar),
    LengthLimitingTextInputFormatter(maxChars),
  ];

  List<TextInputFormatter> _digitFormatters(int maxDigits) => [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(maxDigits),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppBrandColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 58, 12, 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Center(child: Text(AppLocalizations.of(context).t('connectivity_title'),
                            style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary))),
                        const SizedBox(height: 20),
                        _buildConnectivityToggle(),
                        const SizedBox(height: 20),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _selectedConnectivity == 0 ? _buildModbusSettings() : _buildWifiBleSettings(),
                        ),
                      ],
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

  Widget _buildConnectivityToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppBrandColors.toggleInactive, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppBrandColors.border)),
      child: Row(
        children: [
          Expanded(child: GestureDetector(
            onTap: () => setState(() { _selectedConnectivity = 0; _connectivitySelection[0] = true; _connectivitySelection[1] = false; }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: _selectedConnectivity == 0 ? AppBrandColors.accent : Colors.transparent, borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(AppLocalizations.of(context).t('modbus'), style: GoogleFonts.inter(color: _selectedConnectivity == 0 ? Colors.white : AppBrandColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13))),
            ),
          )),
          const SizedBox(width: 4),
          Expanded(child: GestureDetector(
            onTap: () => setState(() { _selectedConnectivity = 1; _connectivitySelection[0] = false; _connectivitySelection[1] = true; }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: _selectedConnectivity == 1 ? AppBrandColors.accent : Colors.transparent, borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(AppLocalizations.of(context).t('wifi_ble'), style: GoogleFonts.inter(color: _selectedConnectivity == 1 ? Colors.white : AppBrandColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13))),
            ),
          )),
        ],
      ),
    );
  }

  // the read-only panel (B2)
  Widget _buildPanelLabel() {
    final loc = AppLocalizations.of(context);
    final text = _selectedPanel == null
        ? loc.t('panel_not_chosen')
        : loc.t('panel_from_panel_page', params: {'panel': _selectedPanel!});
    return InputDecorator(
      decoration: _styledInputDecoration(loc.t('select_panel')).copyWith(
        prefixIcon: Icon(_selectedPanel == null ? Icons.warning_amber_rounded : Icons.lock_outline, size: 18,
            color: _selectedPanel == null ? Colors.orange : AppBrandColors.textSecondary),
      ),
      child: Text(text, key: const ValueKey('wifi_panel_label'), maxLines: 2, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildWifiBleSettings() {
    return _buildSettingsCard(
      key: const ValueKey('wifi'),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildPanelLabel()),
              const SizedBox(height: 58, child: VerticalDivider(color: Colors.transparent, thickness: 1)),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _selectedWifiMode,
                decoration: _styledInputDecoration(AppLocalizations.of(context).t('select_mode')),
                isExpanded: true,
                items: _validWifiModes.map((v) {
                  final map = {'Mqtt-HA': 'mqtt_ha', 'Tuya-wifi': 'tuya_wifi', 'Tuya-BLE': 'tuya_ble'};
                  return DropdownMenuItem<String>(value: v, child: Text(AppLocalizations.of(context).t(map[v] ?? v), style: GoogleFonts.inter(fontSize: 14, color: AppBrandColors.textPrimary)));
                }).toList(),
                onChanged: (value) => setState(() => _selectedWifiMode = value),
                icon: const Icon(Icons.arrow_drop_down, color: AppBrandColors.textSecondary),
                dropdownColor: AppBrandColors.dropdownMenuBg,
              )),
            ],
          ),
          const SizedBox(height: 8),
          if (_selectedWifiMode == 'Mqtt-HA') ...[ const SizedBox(height: 20), _buildMqttHaSettings() ],
          if (_selectedWifiMode == 'Tuya-wifi' || _selectedWifiMode == 'Tuya-BLE') ...[ const SizedBox(height: 20), _buildTuyaSettings() ],
        ],
      ),
    );
  }

  Widget _buildMqttHaSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _buildStyledTextField(key: const ValueKey('mqtt_broker'), label: AppLocalizations.of(context).t('mqtt_broker_address'), controller: _mqttBrokerAddressController,
              formatters: _textFormatters(kBrokerMaxChars), validator: (v) => _textRule(v, kBrokerMaxChars))),
          const SizedBox(width: 8),
          Expanded(child: _buildStyledTextField(key: const ValueKey('mqtt_port'), label: AppLocalizations.of(context).t('mqtt_port'), controller: _mqttPortController,
              keyboardType: TextInputType.number, formatters: _digitFormatters(5), validator: _portRule)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _buildStyledTextField(key: const ValueKey('mqtt_user'), label: AppLocalizations.of(context).t('user_name'), controller: _userNameController,
              formatters: _textFormatters(kUserMaxChars), validator: (v) => _textRule(v, kUserMaxChars))),
          const SizedBox(width: 8),
          Expanded(child: _buildStyledTextField(key: const ValueKey('mqtt_password'), label: AppLocalizations.of(context).t('password'), controller: _passwordController, obscureText: true,
              formatters: _textFormatters(kPasswordMaxChars), validator: (v) => _textRule(v, kPasswordMaxChars))),
        ]),
        const SizedBox(height: 24),
        _buildDeviceTable(title: AppLocalizations.of(context).t('device_configuration'), rows: _mqttDeviceRows, onAddRow: () => setState(() { if (_mqttDeviceRows.length < kDpRowsMax) _mqttDeviceRows.add(MqttDeviceRow()); }), onDeleteRow: (index) => setState(() { _mqttDeviceRows[index].deviceNoController.dispose(); _mqttDeviceRows[index].dpIdController.dispose(); _mqttDeviceRows.removeAt(index); })),
      ],
    );
  }

  Widget _buildTuyaSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStyledTextField(key: const ValueKey('tuya_pid'), label: AppLocalizations.of(context).t('pid'), controller: _pidController,
            formatters: _textFormatters(kPidMaxChars), validator: (v) => _textRule(v, kPidMaxChars)),
        const SizedBox(height: 24),
        _buildDeviceTable(title: AppLocalizations.of(context).t('device_configuration'), rows: _tuyaDeviceRows, onAddRow: () => setState(() { if (_tuyaDeviceRows.length < kDpRowsMax) _tuyaDeviceRows.add(TuyaDeviceRow()); }), onDeleteRow: (index) => setState(() { _tuyaDeviceRows[index].deviceNoController.dispose(); _tuyaDeviceRows[index].dpIdController.dispose(); _tuyaDeviceRows.removeAt(index); })),
      ],
    );
  }

  Widget _buildDeviceTable({required String title, required List<dynamic> rows, required VoidCallback onAddRow, required Function(int) onDeleteRow}) {
    final atCap = rows.length >= kDpRowsMax;
    return Container(
      decoration: AppBrandColors.tableContainerDecoration,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: AppBrandColors.tableHeaderDecoration,
            child: Row(
              children: [
                SizedBox(width: 40, child: Text(AppLocalizations.of(context).t('s_no'), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary))),
                const SizedBox(width: 8),
                Expanded(flex: 5, child: Text(AppLocalizations.of(context).t('parameter'), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: Text(AppLocalizations.of(context).t('device_no'), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: Text(AppLocalizations.of(context).t('dp_id'), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary))),
                const SizedBox(width: 8),
                const SizedBox(width: 32),
              ],
            ),
          ),
          ...List.generate(rows.length, (index) {
            final row = rows[index];
            return Container(
              key: ObjectKey(row),            // each row keeps its own dropdown state after a delete
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: index < rows.length - 1 ? AppBrandColors.divider : Colors.transparent))),
              child: Row(
                children: [
                  SizedBox(width: 40, child: Text('${index + 1}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400, color: AppBrandColors.textSecondary))),
                  const SizedBox(width: 8),
                  Expanded(flex: 5, child: _buildStyledTableDropdown(value: row.parameter, items: kDpParameters, onChanged: (value) => setState(() => row.parameter = value))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _buildStyledTableTextField(controller: row.deviceNoController, formatters: _digitFormatters(3), validator: _numberRule(255))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _buildStyledTableTextField(controller: row.dpIdController, formatters: _digitFormatters(5), validator: _numberRule(65535))),
                  const SizedBox(width: 8),
                  SizedBox(width: 32, child: IconButton(onPressed: () => onDeleteRow(index), tooltip: AppLocalizations.of(context).t('delete_row'), icon: const Icon(Icons.delete_outline, size: 20), color: const Color.fromARGB(255, 212, 75, 75), padding: EdgeInsets.zero, constraints: const BoxConstraints())),
                ],
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Opacity(
                  opacity: atCap ? 0.4 : 1.0,
                  child: IgnorePointer(
                    key: const ValueKey('add_row_gate'),
                    ignoring: atCap,
                    child: AddNewRowButton(
                      onPressed: onAddRow,
                      iconSize: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                    ),
                  ),
                ),
                if (atCap)
                  Text(AppLocalizations.of(context).t('row_limit', params: {'max': '$kDpRowsMax'}),
                      style: GoogleFonts.inter(fontSize: 12, color: AppBrandColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledTableDropdown({required String? value, required List<String> items, required ValueChanged<String?> onChanged}) {
    // a parameter from an older TXT that is not offered any more stays visible instead of crashing the dropdown
    final shown = (value != null && !items.contains(value)) ? [...items, value] : items;
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: shown.map((String item) => DropdownMenuItem<String>(value: item, child: Text(item, style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
      isExpanded: true,
      decoration: _styledInputDecoration(null).copyWith(hintText: AppLocalizations.of(context).t('select'), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      icon: const Icon(Icons.arrow_drop_down, size: 20, color: AppBrandColors.textSecondary),
      menuMaxHeight: 250,
      style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500),
      dropdownColor: AppBrandColors.dropdownMenuBg,
      hint: Text(AppLocalizations.of(context).t('select'), style: GoogleFonts.inter(color: AppBrandColors.textSecondary, fontSize: 13)),
      selectedItemBuilder: (BuildContext context) => shown.map<Widget>((String item) => Align(alignment: Alignment.centerLeft, child: Text(item, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500)))).toList(),
    );
  }

  Widget _buildStyledTableTextField({required TextEditingController controller, List<TextInputFormatter>? formatters, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: formatters,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator,
      style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500),
      decoration: _styledInputDecoration(null).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      cursorColor: AppBrandColors.accent,
    );
  }

  Widget _buildStyledTextField({Key? key, required String label, required TextEditingController controller, bool obscureText = false,
      TextInputType? keyboardType, List<TextInputFormatter>? formatters, String? Function(String?)? validator}) {
    return TextFormField(
      key: key,
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator,
      style: GoogleFonts.inter(fontSize: 14, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500),
      decoration: _styledInputDecoration(label).copyWith(errorMaxLines: 2),
      cursorColor: AppBrandColors.accent,
    );
  }

  Widget _buildModbusSettings() {
    return _buildSettingsCard(
      key: const ValueKey('modbus'),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: _buildStyledDropdown(label: AppLocalizations.of(context).t('baud_rate'), value: _selectedBaudRate, items: _validBaudRates, onChanged: (value) => setState(() => _selectedBaudRate = value))),
            const SizedBox(height: 58, child: VerticalDivider(color: Colors.transparent, thickness: 1)),
            Expanded(child: _buildStyledDropdown(label: AppLocalizations.of(context).t('data_bit'), value: _selectedDataBit, items: _validDataBits, onChanged: (value) => setState(() => _selectedDataBit = value))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _buildStyledDropdown(label: AppLocalizations.of(context).t('stop_bit'), value: _selectedStopBit, items: _validStopBits, onChanged: (value) => setState(() => _selectedStopBit = value))),
            const SizedBox(height: 58, child: VerticalDivider(color: Colors.transparent, thickness: 1)),
            Expanded(child: _buildStyledDropdown(label: AppLocalizations.of(context).t('parity'), value: _selectedParity, items: _validParities, onChanged: (value) => setState(() => _selectedParity = value))),
          ]),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({required Widget child, required Key key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppBrandColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppBrandColors.border), boxShadow: const [BoxShadow(color: Color(0x0AF28C33), blurRadius: 8, offset: Offset(0, 3))]),
      child: child,
    );
  }

  Widget _buildStyledDropdown({required String label, required String? value, required List<String> items, required ValueChanged<String?> onChanged}) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items.map((String item) => DropdownMenuItem<String>(value: item, child: Text(item, style: GoogleFonts.inter(fontSize: 14, color: AppBrandColors.textPrimary), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
      decoration: _styledInputDecoration(label),
      icon: const Icon(Icons.arrow_drop_down, size: 20, color: AppBrandColors.textSecondary),
      menuMaxHeight: 250,
      style: GoogleFonts.inter(fontSize: 14, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500),
      dropdownColor: AppBrandColors.dropdownMenuBg,
      hint: Text(AppLocalizations.of(context).t('select'), style: GoogleFonts.inter(color: AppBrandColors.textSecondary)),
      selectedItemBuilder: (BuildContext context) => items.map<Widget>((String item) => Text(item, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500))).toList(),
    );
  }

  InputDecoration _styledInputDecoration(String? label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textSecondary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppBrandColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppBrandColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppBrandColors.accent, width: 1.5)),
      filled: true,
      fillColor: AppBrandColors.inputFieldBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        margin: const EdgeInsets.fromLTRB(40, 0, 40, 24),
        duration: const Duration(seconds: 2),
        elevation: 4,
      ),
    );
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
              if (_selectedConnectivity == 1 && (_selectedWifiMode == 'Tuya-wifi' || _selectedWifiMode == 'Tuya-BLE')) {
                if (_pidController.text.trim().isEmpty) {
                  _snack(AppLocalizations.of(context).t('pid_required'));
                  return;
                }
              }
              if (_selectedConnectivity == 1 && !(_formKey.currentState?.validate() ?? true)) {
                _snack(AppLocalizations.of(context).t('fix_fields_first'));
                return;
              }

              final manager = AppDataManager();
              manager.connectivityType = _selectedConnectivity;
              if (_selectedConnectivity == 0) {
                manager.modbusBaudRate = _selectedBaudRate;
                manager.modbusDataBit = _selectedDataBit;
                manager.modbusStopBit = _selectedStopBit;
                manager.modbusParity = _selectedParity;
              } else {
                // V1.1.0 (B2): the network page is the Panel page's panel
                manager.wifiPanel = manager.panelSwitchPanel;
                manager.wifiMode = _selectedWifiMode;
                if (_selectedWifiMode == 'Mqtt-HA') {
                  manager.mqttBroker = _mqttBrokerAddressController.text;
                  manager.mqttPort = _mqttPortController.text;
                  manager.mqttUser = _userNameController.text;
                  manager.mqttPassword = _passwordController.text;
                  manager.mqttDevices = _mqttDeviceRows.map((r) => {'parameter': r.parameter, 'deviceNo': r.deviceNoController.text, 'dpId': r.dpIdController.text}).toList();
                } else {
                  manager.tuyaPid = _pidController.text;
                  manager.tuyaDevices = _tuyaDeviceRows.map((r) => {'parameter': r.parameter, 'deviceNo': r.deviceNoController.text, 'dpId': r.dpIdController.text}).toList();
                }
              }
              Navigator.of(context).push(_createRoute(const OverviewPage()));
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
