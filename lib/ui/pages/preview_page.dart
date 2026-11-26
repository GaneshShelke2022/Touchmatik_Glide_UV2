/*
 * =============================================================================
 *  preview_page.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  OverviewPage: a read-only summary before the configuration page.
 *  V1.1.0: the panel number is shown once (it is the one number of the whole
 *  configuration, B2); keys keep their SW numbers (a cleared key is a gap);
 *  the result of checkConfig is listed on top: errors (Generate will refuse)
 *  and warnings (Generate will ask).
 * =============================================================================
 */
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/app_data.dart';
import '../../localization/app_localizations.dart';
import '../../services/config_check.dart';
import 'configuration_page.dart';
import '../../themes/app_theme.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // fills configErrors / configWarnings (config_check.dart) for the list on top
    try {
      checkConfig(AppDataManager());
    } catch (e) {
      debugPrint('checkConfig: $e');
    }
    _animationController = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _animationController.forward();
  }

  @override
  void dispose() {
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

  bool _filled(dynamic v) => v != null && v.toString().trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final data = AppDataManager();
    final loc = AppLocalizations.of(context);
    // keys by their own number: row index 2 is SW-03 even when SW-02 is empty
    final keyLines = <String>[];
    for (int i = 0; i < data.panelSwitchRows.length; i++) {
      final r = data.panelSwitchRows[i];
      if (!_filled(r['function']) && !_filled(r['number'])) continue;
      keyLines.add("SW-${(i + 1).toString().padLeft(2, '0')},${r['function'] ?? ''},${r['number'] ?? ''}");
    }
    final outputRows = data.relayOutputRows.where((r) => _filled(r['number']) || _filled(r['output'])).toList();
    final inputRows = data.inputAssignRows.where((r) => _filled(r['deviceNo']) || _filled(r['outputDevice'])).toList();
    return Scaffold(
      backgroundColor: AppBrandColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 68, 12, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Text(loc.t('project_preview'),
                          style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary))),
                      const SizedBox(height: 20),

                      // checkConfig: errors and warnings
                      if (configErrors.isNotEmpty)
                        _buildIssueCard(key: const ValueKey('preview_errors'), title: loc.t('config_errors_title'), lines: configErrors, color: Colors.red, icon: Icons.error_outline),
                      if (configWarnings.isNotEmpty)
                        _buildIssueCard(key: const ValueKey('preview_warnings'), title: loc.t('config_warnings_title'), lines: configWarnings, color: Colors.orange, icon: Icons.warning_amber_rounded),

                      // Project Information
                      if (data.customerName != null && data.customerName!.isNotEmpty)
                        _buildSectionCard(title: loc.t('project_information'), children: [
                          _buildDetailRow(loc.t('customer_name'), data.customerName),
                          _buildDetailRow(loc.t('address'), data.customerAddress),
                        ]),

                      // Panel: its number once, for keys, outputs, inputs and the network page
                      if (data.panelSwitchPanel != null)
                        _buildSectionCard(title: data.panelSwitchPanel!, titleKey: const ValueKey('preview_panel_title'), children: [
                          _buildDetailRow(loc.t('location'), data.panelSwitchLocation),
                          _buildDetailRow(loc.t('module'), data.panelSwitchModule),
                          _buildDetailRow(loc.t('board_type'), data.boardType),
                          if (keyLines.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(loc.t('switch'), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppBrandColors.textPrimary)),
                            const SizedBox(height: 4),
                            _buildIndented(keyLines.map((l) => Text(l, style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textSecondary))).toList()),
                          ],
                          if (outputRows.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(loc.t('output'), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppBrandColors.textPrimary)),
                            const SizedBox(height: 4),
                            _buildIndented(outputRows.map((r) => Text("${r['serialNumber']},${r['type'] ?? ''},${r['output'] ?? ''},${r['number'] ?? ''},${r['time'] ?? ''}", style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textSecondary))).toList()),
                          ],
                          if (inputRows.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(loc.t('input_assign_title'), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppBrandColors.textPrimary)),
                            const SizedBox(height: 4),
                            _buildIndented(inputRows.map((r) => Text("${r['sr']},${r['type'] ?? ''},${r['inputState'] ?? ''},${r['outputDevice'] ?? ''},${r['deviceNo'] ?? ''},${r['outputState'] ?? ''},${r['time'] ?? ''},${r['defaultState'] ?? ''}", style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textSecondary))).toList()),
                          ],
                        ]),

                      // Scene Assign
                      if (data.sceneAssignRows.any((r) => _filled(r['number'])))
                        ..._buildSceneSections(data.sceneAssignRows),

                      // Connectivity
                      _buildSectionCard(title: loc.t('connectivity_title'), children: [
                        if (data.connectivityType == 0) ...[
                          _buildDetailRow(loc.t('type'), loc.t('modbus')),
                          _buildDetailRow(loc.t('baud_rate'), data.modbusBaudRate),
                          _buildDetailRow(loc.t('data_bit'), data.modbusDataBit),
                          _buildDetailRow(loc.t('stop_bit'), data.modbusStopBit),
                          _buildDetailRow(loc.t('parity'), data.modbusParity),
                        ] else ...[
                          _buildDetailRow(loc.t('select_mode'), data.wifiMode),
                          if (data.wifiMode == 'Mqtt-HA') ...[
                            _buildDetailRow(loc.t('mqtt_broker_address'), data.mqttBroker),
                            _buildDetailRow(loc.t('mqtt_port'), data.mqttPort),
                            _buildDetailRow(loc.t('user_name'), data.mqttUser),
                            _buildDetailRow(loc.t('password'), _filled(data.mqttPassword) ? '*' * data.mqttPassword!.length : null),
                          ],
                          if (data.wifiMode == 'Tuya-wifi' || data.wifiMode == 'Tuya-BLE') _buildDetailRow(loc.t('pid'), data.tuyaPid),
                          ...() {
                            final dps = (data.wifiMode == 'Mqtt-HA' ? data.mqttDevices : data.tuyaDevices).where((r) => _filled(r['deviceNo'])).toList();
                            if (dps.isEmpty) return <Widget>[];
                            return <Widget>[
                              const SizedBox(height: 8),
                              Text(loc.t('device_configuration'), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: AppBrandColors.textPrimary)),
                              _buildIndented(dps.map((r) => Text("${r['parameter'] ?? ''},${r['deviceNo']},${r['dpId'] ?? ''}", style: GoogleFonts.inter(fontSize: 13, color: AppBrandColors.textSecondary))).toList()),
                            ];
                          }(),
                        ],
                      ]),
                      const SizedBox(height: 40),
                    ],
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

  Widget _buildIndented(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppBrandColors.accent, width: 2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildIssueCard({Key? key, required String title, required List<String> lines, required Color color, required IconData icon}) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          ]),
          const SizedBox(height: 6),
          ...lines.map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('-  $l', style: GoogleFonts.inter(fontSize: 12.5, color: AppBrandColors.textPrimary)),
              )),
        ],
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
            onTap: () => Navigator.of(context).push(_createRoute(const ConfigurationPage())),
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

  List<Widget> _buildSceneSections(List<Map<String, dynamic>> rows) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var row in rows) {
      if (_filled(row['number'])) {
        final type = row['type']?.toString() ?? '';
        grouped.putIfAbsent(type, () => []).add(row);
      }
    }
    return grouped.entries.map((e) => _buildSectionCard(title: e.key, children: e.value.map((r) => Text("${r['sr_no']},${r['output'] ?? ''},${r['number']},${r['state'] ?? ''},${r['temp'] ?? ''},${r['panel_no'] ?? ''}", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppBrandColors.textSecondary))).toList())).toList();
  }

  Widget _buildSectionCard({required String title, Key? titleKey, required List<Widget> children}) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppBrandColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppBrandColors.border), boxShadow: const [BoxShadow(color: Color(0x0AF28C33), blurRadius: 8, offset: Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, key: titleKey, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: AppBrandColors.accent)),
        const SizedBox(height: 12),
        Divider(color: AppBrandColors.divider, thickness: 1),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("$label:", style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: AppBrandColors.textPrimary)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 13, color: AppBrandColors.textSecondary))),
      ]),
    );
  }
}
