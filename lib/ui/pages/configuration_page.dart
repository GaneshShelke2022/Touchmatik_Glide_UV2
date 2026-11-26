/*
 * =============================================================================
 *  configuration_page.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  The output stage: Generate HEX (TXT + converters), Process (a new header
 *  for a picked HEX), and the upload to the panel over Bluetooth (the
 *  TPF01-ESP-PANEL 0.6.0 configuration window) or RS485.
 *
 *  V1.1.0 (design 3.2, 3.3, 3.6):
 *   - Generate checks the configuration first (checkConfig: errors block,
 *     warnings ask), writes ONE panel number into every TXT tag (B2c) and the
 *     HEX always starts with its header (ConvertManager, B1);
 *   - after Generate and Process the new file is preselected for the upload;
 *   - one Bluetooth section (scan, connect, file, upload) instead of two;
 *     "connected" only once the panel's service is ready;
 *   - the upload dialog shows the panel firmware, the file, the record count,
 *     the phase and the attempt, can be cancelled, and stays open with the
 *     result: the verified CRC and the panel's INFO hints, or the refused
 *     record with its file line; Retry / Save log / Exit configuration mode /
 *     Close;
 *   - Process defaults to the Panel page's panel and the board type, and
 *     warns when the file's pages are for another panel (B2d);
 *   - About; every setState / Navigator after an await checks mounted;
 *   - review fixes (review_glide): Cancel is off once the EOF line is out (the
 *     panel may be storing); a failure after the EOF line says the panel may
 *     have stored the file, a CRC mismatch that it stored a different program
 *     (never "unchanged"); Retry and Save log wait while "Exit configuration
 *     mode" runs; '#VER' / Exit only for a device whose real name is KIPL-2M.
 * =============================================================================
 */
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:usb_serial/usb_serial.dart';
import '../../app_version.dart';
import '../../comporotocol/ble_manager.dart';
import '../../comporotocol/config_uploader.dart';
import '../../comporotocol/rs485_com.dart';
import '../../data/app_data.dart';
import '../../localization/app_localizations.dart';
import '../../permissions/storage_permission.dart';
import '../../permissions/textfile_saver.dart';
import '../../services/app_log.dart';
import '../../services/config_check.dart';
import '../../services/convert_manager.dart';
import '../../services/hex_file_check.dart';
import '../../services/hex_tools.dart' show panelNumberOf, panelLabel;
import '../../services/process_config.dart';
import '../../services/txt_reader.dart' show buildTxt;
import '../../themes/app_theme.dart';

enum CommunicationMode { ble, rs485 }

// =============================================================================
//  Texts shared by the page and the upload dialog (pure, unit-testable)
// =============================================================================

/// One line under a stored upload (design 3.6, INFO table): an app_en.arb
/// key, its parameters, and whether it is shown in the warning style.
class UploadHint {
  final String key;
  final Map<String, String> params;
  final bool warning;
  const UploadHint(this.key, [this.params = const {}, this.warning = false]);

  @override
  String toString() => 'UploadHint($key, $params${warning ? ', warning' : ''})';
}

/// The hints for the INFO line the panel sent after storing a file whose
/// panel is [filePanel] (header panel, 1 without a header). Unknown INFO keys
/// are ignored and missing ones accepted (C-4.9). An empty [info] (protocol
/// v1) gives no hints; the dialog then says "Stored (the panel did not report
/// a CRC)".
List<UploadHint> uploadInfoHints(Map<String, String> info, {required int filePanel}) {
  final hints = <UploadHint>[];
  if (info.isEmpty) return hints;
  final panel = int.tryParse(info['panel'] ?? '');
  if (info['hdr'] == '0') hints.add(const UploadHint('info_hdr0'));
  if (panel != null && panel != filePanel) {
    hints.add(UploadHint('info_panel_override', {'x': '$panel', 'y': '$filePanel'}));
  }
  if (info['keys'] == '0' && info['outputs'] == '0') {
    hints.add(UploadHint('info_nothing_for_panel', {'n': '${panel ?? filePanel}'}, true));
  }
  final mode = info['mode'];
  if (mode == 'off' || info['net'] == '00') {
    hints.add(const UploadHint('info_mode_off'));
  } else if (mode == 'wifi') {
    if (info['wifi'] == '0') {
      hints.add(UploadHint('info_wifi_setup', {'ap': info['ap'] ?? 'provisioning-XXYYZZ'}));
    } else if (info['wifi'] == '1') {
      hints.add(const UploadHint('info_wifi_joins'));
    }
  } else if (mode == 'mesh') {
    switch (info['mesh']) {
      case 'none':
        hints.add(const UploadHint('info_mesh_none'));
        break;
      case 'same':
        hints.add(const UploadHint('info_mesh_same'));
        break;
      case 'new':
        hints.add(const UploadHint('info_mesh_new', {}, true));
        break;
    }
  }
  return hints;
}

/// Failures that are the app's own and not a refusal by the panel.
const Set<String> appSideTokens = {'link', 'no-answer', 'bad-reply', 'cancelled', 'crc'};

/// The user's text for an uploader / firmware token ('checksum' -> "checksum
/// error"): app_en.arb err_TOKEN, else the uploader's English text.
String uploadErrorText(AppLocalizations loc, String token) {
  final key = 'err_${token.replaceAll('-', '_')}';
  final text = loc.t(key);
  return text == key ? upTokenText(token) : text;
}

/// The manager's last link message in the user's language (link_* keys).
String linkMessageText(AppLocalizations loc, BLEManager m) {
  if (m.linkMessageKey.isEmpty) return m.linkMessage;
  final text = loc.t(m.linkMessageKey, params: m.linkMessageParams);
  return text == m.linkMessageKey ? m.linkMessage : text;
}

/// A pre-flight warning (C-5.3) of [check] in the user's language.
String hexWarningText(AppLocalizations loc, HexCheck check, int index) {
  final code = check.warnings[index];
  final key = 'hexwarn_${code.replaceAll('-', '_')}';
  final pages = (check.pagePanels.toList()..sort()).map(HexCheck.panelLabel).join(', ');
  final text = loc.t(key, params: {'panel': HexCheck.panelLabel(check.panel), 'pages': pages});
  return text == key ? check.warningTexts[index] : text;
}

// =============================================================================
//  ConfigurationPage
// =============================================================================
class ConfigurationPage extends StatefulWidget {
  const ConfigurationPage({super.key});

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _selectedTxtFilePath;
  String? _generatedHexFilePath;
  String? _modifiedHexFilePath;
  bool _isHexFilePreselected = false;
  bool _onlyFlashMode = false;
  CommunicationMode _selectedMode = CommunicationMode.ble;
  final BLEManager _bleManager = BLEManager();
  StreamSubscription<BluetoothDevice?>? _connectionSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<String?>? _scanErrorSubscription;
  StreamSubscription<String?>? _hexFileSubscription;
  List<ScanResult> _panels = const [];

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // "BLE Connected" only when the panel's service is discovered and subscribed (linkState 'ready')
    _connectionSubscription = _bleManager.connectedDeviceStream.listen((device) {
      if (device != null && mounted) {
        _showNotification(AppLocalizations.of(context).t('ble_connected'));
      }
    });
    _scanSubscription = _bleManager.scanResults.listen((list) {
      if (mounted) setState(() => _panels = list);
    });
    _scanErrorSubscription = _bleManager.scanErrorStream.listen((_) {
      if (mounted) setState(() {});
    });
    _hexFileSubscription = _bleManager.hexFilePathStream.listen((_) {
      if (mounted) setState(() {});
    });

    // Check for pre-selected file from CustomerInfoPage
    final data = AppDataManager();
    if (data.selectedFile != null) {
      // Only auto-enter flasher mode when the file was set by CustomerInfoPage and is a HEX
      if (data.selectedFileFromCustomerInfo == true && data.selectedFile!.toLowerCase().endsWith('.hex')) {
        _isHexFilePreselected = true;
        _modifiedHexFilePath = data.selectedFile;
        _bleManager.setHexFile(data.selectedFile);
        _selectedMode = CommunicationMode.rs485;
        // Automatically flash the HEX file
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _flashHexFile();
        });
      } else if (data.selectedFile!.toLowerCase().endsWith('.txt')) {
        // Treat plain TXT files as regular selections (not from CustomerInfo)
        _selectedTxtFilePath = data.selectedFile;
        data.selectedFileFromCustomerInfo = false;
      } else {
        // If it's not from CustomerInfo (or not a hex), don't auto-enter flasher mode
        data.selectedFileFromCustomerInfo = false;
      }
    }

    // If user chose "Have HEX" shortcut, enable only-flash mode
    if (data.alreadyHaveHexSelected == true) {
      _onlyFlashMode = true;
      data.alreadyHaveHexSelected = false;
    }

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _scanSubscription?.cancel();
    _scanErrorSubscription?.cancel();
    _hexFileSubscription?.cancel();
    // stops the scan, disconnects, cancels the listeners, closes the streams
    _bleManager.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  Small dialogs and messages
  // ---------------------------------------------------------------------------

  void _showNotification(String message, {bool isError = false, bool isWarning = false}) {
    if (!mounted) return;
    final color = isError
        ? Colors.red
        : isWarning
            ? Colors.orange
            : const Color(0xFF27AE60);
    final icon = isError
        ? Icons.error_outline
        : isWarning
            ? Icons.warning_amber_rounded
            : Icons.check_circle_outline;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 2, textAlign: TextAlign.center),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        margin: const EdgeInsets.fromLTRB(40, 0, 40, 24),
        duration: const Duration(seconds: 2),
        elevation: 4,
      ),
    );
  }

  void _showSuccessDialog(String title, String message, String path) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10.0,
                    offset: Offset(0.0, 10.0)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
                const SizedBox(height: 24),
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(path, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 24),
                ElevatedButton(
                  child: Text(AppLocalizations.of(context).t('ok'), style: const TextStyle(fontSize: 14)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showWarningDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10.0,
                    offset: Offset(0.0, 10.0)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 80),
                const SizedBox(height: 24),
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Color(0xFF7F8C8D))),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  ),
                  child: Text(AppLocalizations.of(context).t('ok'), style: const TextStyle(fontSize: 16)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // A list of lines with OK only ([okLabel] == null) or Cancel / [okLabel]; true = OK.
  Future<bool> _showListDialog({
    required String title,
    String? intro,
    required List<String> lines,
    String? okLabel,
    bool isError = false,
  }) async {
    if (!mounted) return false;
    final loc = AppLocalizations.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.warning_amber_rounded, color: isError ? Colors.red : Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (intro != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(intro, style: const TextStyle(fontWeight: FontWeight.w600))),
                ...lines.map((l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('-  '),
                          Expanded(child: Text(l, style: const TextStyle(fontSize: 14))),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
        actions: okLabel == null
            ? [TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(loc.t('ok')))]
            : [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(loc.t('cancel'))),
                ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: Text(okLabel)),
              ],
      ),
    );
    return answer == true;
  }

  void _showAbout() {
    final loc = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(loc.t('about_title')),
        content: Text(kAppAbout, key: const ValueKey('about_dialog_text')),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(loc.t('ok')))],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  TXT and HEX
  // ---------------------------------------------------------------------------

  // Writes the configuration TXT from the pages. V1.1.0 (B2c): every tag
  // (<Panel-NN>, <InputAssign-NN>, <WiFiInfo-NN>) carries the Panel page's number.
  Future<String?> _generateAndSaveFile({bool showDialog = true}) async {
    bool hasPermission = await requestStoragePermission();
    if (!mounted) return null;
    if (!hasPermission) {
      _showNotification(AppLocalizations.of(context).t('storage_permission_needed'), isError: true);
      return null;
    }

    // the same text checkConfig converted in memory (txt_reader.dart buildTxt; B2c: one panel number in every tag)
    final fileContent = buildTxt(AppDataManager());
    if (fileContent.isEmpty) return null;

    String? path;
    if (_selectedTxtFilePath != null) {
      path = await saveTextFile(
        context,
        fileContent,
        showSnackBar: false,
        directoryPath: p.dirname(_selectedTxtFilePath!),
        fileName: p.basename(_selectedTxtFilePath!),
      );
    } else {
      path = await saveTextFile(context, fileContent, showSnackBar: false);
    }
    if (!mounted) return path;

    if (path != null) {
      setState(() {
        _selectedTxtFilePath = path;
      });
      appLog('TXT saved: $path');
      if (showDialog) {
        _showSuccessDialog(AppLocalizations.of(context).t('congrats'), AppLocalizations.of(context).t('file_saved_success'), path);
      }
    }
    return path;
  }

  // the HEX is now the file to upload, over Bluetooth and over RS485
  void _useHexFile(String path) {
    _bleManager.setHexFile(path);
    setState(() {
      _modifiedHexFilePath = path;
    });
  }

  Future<void> _generateHexFile() async {
    final loc = AppLocalizations.of(context);
    final data = AppDataManager();

    // V1.1.0 (3.3): validate before anything is written (checkConfig fills configErrors / configWarnings)
    try {
      checkConfig(data);
    } catch (e) {
      appLog('checkConfig failed: $e');
      _showWarningDialog(loc.t('config_errors_title'), loc.t('generate_failed', params: {'error': '$e'}));
      return;
    }
    if (configErrors.isNotEmpty) {
      appLog('generate refused: ${configErrors.join(' | ')}');
      await _showListDialog(title: loc.t('config_errors_title'), intro: loc.t('config_errors_intro'), lines: List<String>.of(configErrors), isError: true);
      return;
    }
    if (configWarnings.isNotEmpty) {
      final go = await _showListDialog(
        title: loc.t('config_warnings_title'),
        intro: loc.t('config_warnings_intro'),
        lines: List<String>.of(configWarnings),
        okLabel: loc.t('generate_anyway'),
      );
      if (!go || !mounted) return;
    }

    // Always regenerate the current TXT file from UI data before conversion.
    final path = await _generateAndSaveFile(showDialog: false);
    if (path == null || !mounted) {
      // generation failed or permission denied - abort
      return;
    }

    setState(() => _isLoading = true);
    try {
      final String outputFilePath = await ConvertManager.convertTxtToHex(path, boardType: data.boardType);
      if (!mounted) return;
      setState(() => _generatedHexFilePath = outputFilePath);
      _useHexFile(outputFilePath);
      appLog('HEX generated: $outputFilePath');
      _showSuccessDialog(loc.t('congrats'), loc.t('hex_generated'), outputFilePath);
    } catch (e) {
      // ConfigRangeError names the page, row and field; no .hex is left behind
      appLog('generate failed: $e');
      _showWarningDialog(loc.t('config_errors_title'), loc.t('generate_failed', params: {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _processFile() async {
    final loc = AppLocalizations.of(context);
    final manager = AppDataManager();
    // V1.1.0 (B2d): the dialog starts with the Panel page's panel and the board type
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) => ProcessDialog(
        initialPanel: manager.panelSwitchPanel,
        initialBoardType: manager.boardType,
      ),
    );
    if (result == null || !mounted) return;

    manager.modbusComPort = result['comPort'];
    manager.modbusBaudRate = result['baudRate']?.toString();
    manager.modbusDataBit = result['dataBit']?.toString();
    manager.modbusStopBit = result['stopBit']?.toString();
    manager.modbusParity = result['parity'];
    manager.isBroadcast = result['isBroadcast'] ?? false;
    manager.panelNumber = result['panelNumber'];
    manager.boardType = (result['boardType'] as String?) ?? 'STANDALONE';

    if (_generatedHexFilePath == null) {
      try {
        FilePickerResult? fileResult = await FilePicker.platform.pickFiles(type: FileType.any);
        if (!mounted) return;
        if (fileResult != null && fileResult.files.single.path != null) {
          String path = fileResult.files.single.path!;
          if (p.extension(path).toLowerCase() == '.hex') {
            setState(() {
              _generatedHexFilePath = path;
            });
          } else {
            _showNotification(loc.t('invalid_file_type_hex'), isError: true);
            return;
          }
        } else {
          return;
        }
      } catch (e) {
        _showNotification(loc.t('pick_failed', params: {'error': '$e'}), isError: true);
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final originalHexContent = await File(_generatedHexFilePath!).readAsString();
      if (!mounted) return;

      // B2d: a header for another panel makes the panel ignore every page of this file
      final pages = HexCheck.ofText(originalHexContent).pagePanels;
      final panel = panelNumberOf(result['panelNumber']?.toString());
      if (panel != null && pages.isNotEmpty && !pages.contains(panel)) {
        setState(() => _isLoading = false);
        final pageList = (pages.toList()..sort()).map(panelLabel).join(', ');
        final go = await _showListDialog(
          title: loc.t('process_panel_mismatch_title'),
          lines: [loc.t('process_panel_mismatch', params: {'pages': pageList, 'panel': panelLabel(panel)})],
          okLabel: loc.t('continue'),
        );
        if (!go || !mounted) return;
        setState(() => _isLoading = true);
      }

      final processor = ProcessConfig();
      final modifiedHexContent = processor.generateModifiedHex(
        originalHexContent: originalHexContent,
        isBroadcast: result['isBroadcast'] ?? false,
        panelText: result['panelNumber'] ?? '',
        boardText: result['boardType'] ?? '',
        baudRateStr: (result['baudRate'] ?? '19200').toString(),
        parityStr: result['parity'] ?? 'None',
        dataBitsStr: (result['dataBit'] ?? '8').toString(),
        stopBitsStr: (result['stopBit'] ?? '1').toString(),
      );

      final dir = p.dirname(_generatedHexFilePath!);
      final filename = p.basenameWithoutExtension(_generatedHexFilePath!);
      final ext = p.extension(_generatedHexFilePath!);
      final newPath = p.join(dir, '${filename}_mod$ext');

      final modifiedFile = File(newPath);
      await modifiedFile.writeAsString(modifiedHexContent);
      if (!mounted) return;
      _useHexFile(newPath);
      appLog('processed: $newPath (${result['panelNumber']}, ${result['boardType']})');
      _showSuccessDialog(loc.t('congrats'), loc.t('hex_saved'), newPath);
    } catch (e) {
      appLog('process failed: $e');
      _showNotification(loc.t('process_failed', params: {'error': '$e'}), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickModifiedHexFile() async {
    final loc = AppLocalizations.of(context);
    setState(() => _isLoading = true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (!mounted) return;

      final String? filePath = result?.files.single.path;
      if (filePath == null) {
        setState(() => _isLoading = false);
        return;
      }
      if (p.extension(filePath).toLowerCase() != '.hex') {
        _showNotification(loc.t('invalid_file_type_hex'), isError: true);
        setState(() => _isLoading = false);
        return;
      }
      setState(() {
        _modifiedHexFilePath = filePath;
        _isLoading = false;
      });
      _showNotification(loc.t('selected_file', params: {'file': p.basename(filePath)}));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showNotification(loc.t('pick_failed', params: {'error': '$e'}), isError: true);
    }
  }

  // RS485 (USB serial, Modbus FC21) - unchanged protocol
  Future<void> _flashHexFile() async {
    final loc = AppLocalizations.of(context);
    if (_modifiedHexFilePath == null) {
      _showWarningDialog(loc.t('file_not_selected'), loc.t('please_select_hex'));
      return;
    }

    setState(() => _isLoading = true);

    final manager = AppDataManager();
    if (!(_isHexFilePreselected || _onlyFlashMode) && manager.modbusComPort == null) {
      _showWarningDialog(loc.t('com_port_missing'), loc.t('com_port_missing_msg'));
      setState(() => _isLoading = false);
      return;
    }

    try {
      List<UsbDevice> devices = await RS485Com.getAvailableDevices();
      if (manager.modbusComPort == null && devices.isNotEmpty) {
        manager.modbusComPort = devices.first.deviceName;
      }
      UsbDevice? targetDevice;
      try {
        targetDevice = devices.firstWhere((d) => d.deviceName == manager.modbusComPort);
      } on StateError {
        targetDevice = null;
      }

      if (targetDevice == null) {
        throw Exception("Device ${manager.modbusComPort} not found or not connected.");
      }

      final fileContent = await File(_modifiedHexFilePath!).readAsString();
      final success = await RS485Com.sendHex(
        device: targetDevice,
        hexContent: fileContent,
        baudRate: manager.modbusBaudRate ?? '19200',
        dataBits: manager.modbusDataBit ?? '8',
        parity: manager.modbusParity ?? 'None',
        stopBits: manager.modbusStopBit ?? '1',
        isBroadcast: manager.isBroadcast,
        panelNumber: manager.panelNumber,
      );
      if (!mounted) return;

      if (success) {
        _showSuccessDialog(loc.t('congrats'), loc.t('hex_flash_success'), _modifiedHexFilePath!);
      } else {
        _showNotification(loc.t('transfer_failed'), isError: true);
      }
    } catch (e) {
      appLog('RS485 flash failed: $e');
      _showNotification(loc.t('rs485_flash_failed', params: {'error': '$e'}), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  //  Bluetooth: scan, connect, upload
  // ---------------------------------------------------------------------------

  Future<void> _startScan() async {
    await _bleManager.startScan();
    if (mounted) setState(() {});
  }

  Future<void> _connectTo(ScanResult result) async {
    try {
      // the real name, not the display fallback 'KIPL-2M-?' (C10: only a KIPL-2M name gets '#VER')
      final ok = await _bleManager.connectTo(result.device, advName: BLEManager.advertisedName(result));
      if (!mounted) return;
      if (!ok) _showNotification(linkMessageText(AppLocalizations.of(context), _bleManager), isError: true);
      setState(() {});
    } catch (e) {
      appLog('connect: $e');
      if (mounted) _showNotification('$e', isError: true);
    }
  }

  Future<void> _flashBleHexFile() async {
    final loc = AppLocalizations.of(context);
    if (_bleManager.bleHexFilePath == null) {
      _showWarningDialog(loc.t('file_not_selected'), loc.t('please_select_hex'));
      return;
    }
    if (!_bleManager.hasPanel) {
      _showWarningDialog(loc.t('bluetooth_device_not_connected'), loc.t('connect_first'));
      return;
    }

    // C-5.3: a file the panel would refuse never opens an upload
    final HexCheck check = await _bleManager.checkHexFile();
    if (!mounted) return;
    if (!check.ok) {
      appLog('${check.name}: refused before connecting: ${check.error} (file line ${check.errorLine})');
      _showWarningDialog(
        loc.t('preflight_refused_title'),
        check.errorLine > 0
            ? loc.t('preflight_refused', params: {'line': '${check.errorLine}', 'reason': uploadErrorText(loc, check.error)})
            : loc.t('preflight_refused_file', params: {'reason': uploadErrorText(loc, check.error)}),
      );
      return;
    }
    if (check.warnings.isNotEmpty) {
      final go = await _showListDialog(
        title: loc.t('preflight_warnings_title'),
        lines: List.generate(check.warnings.length, (i) => hexWarningText(loc, check, i)),
        okLabel: loc.t('continue'),
      );
      if (!go || !mounted) return;
    }

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => UploadDialog(manager: _bleManager, file: check),
    );
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  //  Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppBrandColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              const SizedBox(height: 58),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                child: Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Center(
                        child: Text(
                          loc.t('generate_configuration'),
                          style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: AppBrandColors.textPrimary),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('about_button'),
                      tooltip: loc.t('about'),
                      icon: const Icon(Icons.info_outline, color: AppBrandColors.textSecondary),
                      onPressed: _showAbout,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppBrandColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppBrandColors.border),
                      boxShadow: const [BoxShadow(color: Color(0x0AF28C33), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: _isLoading
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: AppBrandColors.accent),
                                const SizedBox(height: 16),
                                Text(loc.t('processing'), style: GoogleFonts.inter(color: AppBrandColors.textSecondary)),
                              ],
                            ),
                          )
                        : _onlyFlashMode
                            ? _buildOnlyFlashUI()
                            : _isHexFilePreselected
                                ? _buildFlasherUI()
                                : _buildFullUI(),
                  ),
                ),
              ),
              // Footer with Back button
              Container(
                decoration: AppBrandColors.footerDecoration,
                padding: const EdgeInsets.all(16),
                child: InkWell(
                  onTap: () { if (Navigator.of(context).canPop()) Navigator.of(context).pop(); },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 30),
                    decoration: BoxDecoration(color: AppBrandColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppBrandColors.border)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_back, color: AppBrandColors.textPrimary, size: 18),
                        const SizedBox(width: 8),
                        Text(loc.t('back'), style: GoogleFonts.inter(color: AppBrandColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppBrandColors.toggleInactive,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppBrandColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModeButton(loc.t('ble'), _selectedMode == CommunicationMode.ble, () {
              setState(() => _selectedMode = CommunicationMode.ble);
            }),
            const SizedBox(width: 4),
            _buildModeButton(loc.t('rs485'), _selectedMode == CommunicationMode.rs485, () {
              setState(() => _selectedMode = CommunicationMode.rs485);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlyFlashUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        _buildModeToggle(),
        const SizedBox(height: 24),
        _selectedMode == CommunicationMode.ble ? _buildBleSection() : _buildRs485Section(showPicker: true),
      ],
    );
  }

  Widget _buildFullUI() {
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top row: Generate HEX (left) and Process (right)
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                key: const ValueKey('generate_hex'),
                onPressed: _generateHexFile,
                label: loc.t('generate_hex'),
                icon: Icons.build_outlined,
                color: const Color(0xFF1ABC9C),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                onPressed: _processFile,
                label: loc.t('process'),
                icon: Icons.settings_outlined,
                color: const Color.fromARGB(255, 233, 148, 49),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildModeToggle(),
        const SizedBox(height: 24),
        _selectedMode == CommunicationMode.ble ? _buildBleSection() : _buildRs485Section(showPicker: !_isHexFilePreselected),
      ],
    );
  }

  Widget _buildFlasherUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLocalizations.of(context).t('ready_to_flash'),
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppBrandColors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        _buildModeToggle(),
        const SizedBox(height: 24),
        _selectedMode == CommunicationMode.ble ? _buildBleSection() : _buildRs485Section(showPicker: !_isHexFilePreselected),
      ],
    );
  }

  Widget _buildModeButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        decoration: BoxDecoration(
          color: isSelected ? AppBrandColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : AppBrandColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    Key? key,
    required VoidCallback? onPressed,
    required String label,
    required IconData icon,
    required Color color,
    bool isSmall = false,
  }) {
    final enabled = onPressed != null;
    return ConstrainedBox(
      key: key,
      constraints: BoxConstraints(minWidth: isSmall ? 120 : 150, minHeight: 48),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: enabled ? color : color.withValues(alpha: 0.45),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: enabled ? 0.35 : 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // V1.1.0: the one Bluetooth section (was _buildBleFlashOnly + _buildBleUI)
  Widget _buildBleSection() {
    final loc = AppLocalizations.of(context);
    return ValueListenableBuilder<String>(
      valueListenable: _bleManager.linkState,
      builder: (context, state, _) {
        final busy = state == 'scanning' || state == 'connecting' || state == 'uploading';
        final path = _bleManager.bleHexFilePath;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row: Scan (left) and Open HEX (right)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildActionButton(
                  key: const ValueKey('ble_scan'),
                  onPressed: busy ? null : _startScan,
                  label: loc.t('scan'),
                  icon: Icons.bluetooth_searching,
                  color: const Color(0xFF3498DB),
                ),
                _buildActionButton(
                  onPressed: busy ? null : () => _bleManager.pickBleHexFile(context),
                  label: path != null ? p.basename(path) : loc.t('open_hex'),
                  icon: Icons.folder_open_outlined,
                  color: const Color.fromARGB(255, 233, 148, 49),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildFileInfo(path, loc.t('no_hex_selected')),
            const SizedBox(height: 12),
            _buildLinkStatus(state),
            const SizedBox(height: 12),
            // Upload, once a file is chosen
            if (path != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildActionButton(
                    key: const ValueKey('ble_flash'),
                    onPressed: (_bleManager.hasPanel && !busy) ? _flashBleHexFile : null,
                    label: loc.t('flash'),
                    icon: Icons.flash_on,
                    color: const Color.fromARGB(255, 46, 121, 46),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            Text(
              loc.t('available_devices'),
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppBrandColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            _buildPanelList(state),
          ],
        );
      },
    );
  }

  // One line: what the Bluetooth link is doing, or the last hint / error
  Widget _buildLinkStatus(String state) {
    final loc = AppLocalizations.of(context);
    final message = linkMessageText(loc, _bleManager);
    late final String text;
    late final IconData icon;
    Color color = AppBrandColors.textSecondary;
    bool spinner = false;
    switch (state) {
      case 'scanning':
        text = loc.t('link_scanning');
        icon = Icons.bluetooth_searching;
        spinner = true;
        break;
      case 'connecting':
        text = loc.t('link_connecting', params: {'name': _bleManager.linkDeviceName});
        icon = Icons.bluetooth;
        spinner = true;
        break;
      case 'ready':
        text = '${_bleManager.linkDeviceName}: ${_bleManager.linkFirmware.isEmpty ? loc.t('link_ready_v1') : loc.t('link_ready', params: {'fw': _bleManager.linkFirmware})}';
        icon = Icons.bluetooth_connected;
        color = const Color(0xFF2E7D2E);
        break;
      case 'uploading':
        text = loc.t('link_uploading');
        icon = Icons.upload;
        spinner = true;
        break;
      case 'failed':
        text = message.isNotEmpty ? message : loc.t('link_failed', params: {'message': '?'});
        icon = Icons.error_outline;
        color = Colors.red.shade400;
        break;
      default:
        text = message.isNotEmpty ? message : loc.t('link_idle');
        icon = message.isNotEmpty ? Icons.info_outline : Icons.bluetooth_disabled;
    }
    return Container(
      key: const ValueKey('ble_link_status'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          spinner
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
              : Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 13, color: color == AppBrandColors.textSecondary ? AppBrandColors.textPrimary : color))),
          if (state == 'ready')
            TextButton(
              onPressed: () async {
                await _bleManager.disconnect();
                if (mounted) setState(() {});
              },
              child: Text(loc.t('disconnect')),
            ),
        ],
      ),
    );
  }

  Widget _buildPanelList(String state) {
    final loc = AppLocalizations.of(context);
    final devices = _panels;
    if (devices.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 48, color: AppBrandColors.textSecondary),
            const SizedBox(height: 16),
            Text(loc.t('no_devices_found'), style: GoogleFonts.inter(color: AppBrandColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 8),
            Text(loc.t('make_sure_ble'), textAlign: TextAlign.center, style: GoogleFonts.inter(color: AppBrandColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }
    return Column(
      children: devices.map((r) {
        final name = BLEManager.displayName(r);
        final isThis = _bleManager.linkDeviceId == r.device.remoteId.str;
        final connected = isThis && state == 'ready';
        final connecting = isThis && state == 'connecting';
        final busy = state == 'connecting' || state == 'uploading' || state == 'scanning';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: AppBrandColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppBrandColors.border)),
          child: ListTile(
            title: Text(name, style: GoogleFonts.inter(color: AppBrandColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Text('${r.device.remoteId}  ${loc.t('rssi', params: {'rssi': '${r.rssi}'})}', style: GoogleFonts.inter(color: AppBrandColors.textSecondary, fontSize: 12)),
            trailing: InkWell(
              onTap: (busy || connected) ? null : () => _connectTo(r),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: connected ? const Color(0xFF2E7D2E) : AppBrandColors.toggleInactive,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: connected ? const Color(0xFF2E7D2E) : AppBrandColors.border),
                ),
                child: connecting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(connected ? loc.t('connected') : loc.t('connect'),
                        style: GoogleFonts.inter(color: connected ? Colors.white : AppBrandColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRs485Section({required bool showPicker}) {
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (showPicker)
              _buildActionButton(
                onPressed: _pickModifiedHexFile,
                label: _modifiedHexFilePath != null ? p.basename(_modifiedHexFilePath!) : loc.t('open_hex'),
                icon: Icons.folder_open_outlined,
                color: const Color.fromARGB(255, 233, 148, 49),
              ),
            _modifiedHexFilePath != null
                ? _buildActionButton(
                    onPressed: _flashHexFile,
                    label: loc.t('flash'),
                    icon: Icons.flash_on_outlined,
                    color: const Color.fromARGB(255, 46, 121, 46),
                  )
                : Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      loc.t('please_select_hex'),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.red[300],
                      ),
                    ),
                  ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildFileInfo(String? filePath, String placeholder) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppBrandColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppBrandColors.border),
      ),
      child: Row(
        children: [
          Icon(
            filePath != null ? Icons.insert_drive_file : Icons.info_outline,
            size: 16,
            color: filePath != null ? AppBrandColors.accent : AppBrandColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filePath != null ? AppLocalizations.of(context).t('selected_hex', params: {'file': p.basename(filePath)}) : placeholder,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: filePath != null ? AppBrandColors.textPrimary : AppBrandColors.textSecondary,
                fontWeight: filePath != null ? FontWeight.w500 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  UploadDialog (design 3.6): runs the upload and stays open with the result
// =============================================================================
class UploadDialog extends StatefulWidget {
  final BLEManager manager;
  final HexCheck file;

  const UploadDialog({super.key, required this.manager, required this.file});

  @override
  State<UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<UploadDialog> {
  bool _running = true;      // the upload starts right after the first frame
  bool _started = false;     // until then the up* values are the last upload's
  bool? _ok;                 // null while running
  bool _cancelling = false;
  bool _exiting = false;
  String _note = '';         // "Log saved: ..." or the answer to Exit configuration mode

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  Future<void> _run() async {
    // never while "Exit configuration mode" runs: both use the uploader's reply queue
    if (!mounted || _exiting) return;
    setState(() {
      _started = true;
      _running = true;
      _ok = null;
      _cancelling = false;
      _note = '';
    });
    bool ok;
    try {
      ok = await widget.manager.upload(file: widget.file, onProgress: _onProgress);
    } catch (e) {
      appLog('upload: $e');
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _ok = ok;
    });
  }

  // Cancel works until the EOF line goes out. From then on (phase 'store') the
  // panel may already have stored the file, so the uploader waits for its
  // answer and the button is off (review_glide finding 1).
  void _cancel() {
    if (upPhase == 'store') return;
    cancelUpload();
    setState(() => _cancelling = true);
  }

  Future<void> _saveLog() async {
    final loc = AppLocalizations.of(context);
    try {
      final path = await saveAppLog();
      if (!mounted) return;
      setState(() => _note = loc.t('log_saved', params: {'path': path}));
    } catch (e) {
      if (!mounted) return;
      setState(() => _note = loc.t('log_save_failed', params: {'error': '$e'}));
    }
  }

  Future<void> _exitConfigMode() async {
    if (_running || _exiting) return;
    final loc = AppLocalizations.of(context);
    setState(() => _exiting = true);
    final ok = await widget.manager.exitConfigMode();
    if (!mounted) return;
    setState(() {
      _exiting = false;
      // not 'upload_failed': its "stored program is unchanged" may not hold after a CRC mismatch or a lost EOF answer
      _note = ok ? loc.t('exit_config_mode_sent') : loc.t('exit_config_mode_failed', params: {'reason': uploadErrorText(loc, 'link')});
    });
  }

  // "Panel firmware 0.6.0 (protocol v2)" / "unknown (protocol v1)"; before this
  // upload's probe, the version the connect step reported
  String _firmwareLine(AppLocalizations loc) {
    final linkFw = widget.manager.linkFirmware;
    final early = !_started ||
        (_running && upFirmware.isEmpty && (upPhase == 'connect' || upPhase == 'probe' || upPhase.isEmpty));
    if (early) {
      return linkFw.isEmpty ? loc.t('panel_firmware_pending') : loc.t('panel_firmware_v2', params: {'fw': linkFw});
    }
    return upFirmware.isNotEmpty ? loc.t('panel_firmware_v2', params: {'fw': upFirmware}) : loc.t('panel_firmware_v1');
  }

  List<Widget> _result(AppLocalizations loc) {
    final file = widget.file;
    if (_ok == true) {
      final hints = uploadInfoHints(upInfo, filePanel: file.panel);
      return [
        _line(
          Icons.check_circle_outline,
          Colors.green,
          upVerified
              ? loc.t('upload_success', params: {
                  'panel': upInfo['panel'] ?? '${file.panel}',
                  'records': upInfo['records'] ?? '${file.records}',
                  'crc': upInfo['crc'] ?? file.crcHex,
                })
              : loc.t('info_v1'),
          bold: true,
          key: const ValueKey('upload_result'),
        ),
        ...hints.map((h) => _line(h.warning ? Icons.warning_amber_rounded : Icons.info_outline, h.warning ? Colors.orange : Colors.blueGrey, loc.t(h.key, params: h.params))),
      ];
    }
    final reason = uploadErrorText(loc, upError);
    final n = upErrorRecord;
    String text;
    if (upError == 'cancelled') {
      text = loc.t('upload_cancelled'); // only before the EOF line: the panel abandoned the upload
    } else if (upError == 'crc') {
      // the panel answered the EOF: it stored a program that is not this file, and restarts with it
      text = loc.t('upload_crc_mismatch', params: {'panel_crc': upInfo['crc'] ?? '?', 'file_crc': file.crcHex});
    } else if (upMaybeStored) {
      // the EOF line went out, its answer never came: stored or not is unknown (review_glide finding 2)
      text = loc.t('upload_maybe_stored', params: {'reason': reason});
    } else if (!appSideTokens.contains(upError) && n >= 1 && n <= file.fileLine.length) {
      text = loc.t('upload_failed_record', params: {'n': '$n', 'line': '${file.fileLine[n - 1]}', 'reason': reason});
    } else {
      text = loc.t('upload_failed', params: {'reason': reason});
    }
    final lines = <Widget>[_line(Icons.error_outline, Colors.red, text, bold: true, key: const ValueKey('upload_result'))];
    final linkText = linkMessageText(loc, widget.manager);
    if (upError == 'link' && widget.manager.linkMessageKey.isNotEmpty && linkText.isNotEmpty) {
      lines.add(_line(Icons.info_outline, Colors.blueGrey, linkText));
    }
    return lines;
  }

  Widget _line(IconData icon, Color color, String text, {bool bold = false, Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w600 : FontWeight.normal))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final m = widget.manager;
    final file = widget.file;
    final total = (_started && upTotal > 0) ? upTotal : file.lines.length;
    final sent = _started ? upSent : 0;
    final attempt = (_started && upAttempt >= 1) ? upAttempt : 1;
    final phase = (!_started || upPhase.isEmpty) ? 'connect' : upPhase;
    final name = m.linkDeviceName.isNotEmpty ? m.linkDeviceName : '${BLEManager.namePrefix}?';
    final failed = _ok == false;
    final canRetry = failed && retryAllowed(upError);
    // '#CLOSE' only to a device whose real name is a KIPL-2M panel's (C10, review_glide finding 4)
    final canExit = failed && BLEManager.isPanelName(m.linkDeviceName) && !_exiting;

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.t('upload_to', params: {'name': name}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(_firmwareLine(loc), key: const ValueKey('upload_firmware'), style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  loc.t('upload_file_line', params: {
                    'file': file.name,
                    'panel': HexCheck.panelLabel(file.panel),
                    'board': file.boardName,
                    'records': '${file.records}',
                    'crc': file.crcHex,
                  }),
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(value: total > 0 ? (sent / total).clamp(0.0, 1.0) : 0, minHeight: 8),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(loc.t('upload_record', params: {'n': '$sent', 'total': '$total'}), style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text(loc.t('upload_attempt', params: {'n': '$attempt', 'max': '${1 + upAutoRetries}'}), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_cancelling && _running ? loc.t('upload_cancelling') : loc.t('upload_phase_$phase'), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (_ok != null) ..._result(loc),
                if (_note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_note, style: const TextStyle(fontSize: 12, color: Colors.black54))),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 4,
                  children: _running
                      ? [
                          TextButton(
                            key: const ValueKey('upload_cancel'),
                            onPressed: (_cancelling || phase == 'store') ? null : _cancel,
                            child: Text(loc.t('cancel')),
                          ),
                        ]
                      : [
                          // Retry and Save log wait while "Exit configuration mode" talks to the panel (review_glide finding 3)
                          if (canRetry) TextButton(key: const ValueKey('upload_retry'), onPressed: _exiting ? null : _run, child: Text(loc.t('retry'))),
                          TextButton(key: const ValueKey('upload_save_log'), onPressed: _exiting ? null : _saveLog, child: Text(loc.t('save_log'))),
                          if (canExit) TextButton(key: const ValueKey('upload_exit'), onPressed: _exitConfigMode, child: Text(loc.t('exit_config_mode'))),
                          ElevatedButton(
                            key: const ValueKey('upload_close'),
                            onPressed: _exiting ? null : () => Navigator.of(context).pop(_ok == true),
                            child: Text(loc.t('close')),
                          ),
                        ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  ProcessDialog: header (panel, board) and the RS485 line settings
// =============================================================================
class ProcessDialog extends StatefulWidget {
  /// V1.1.0 (B2d): the Panel page's panel and the board type are the defaults.
  final String? initialPanel;
  final String? initialBoardType;

  const ProcessDialog({super.key, this.initialPanel, this.initialBoardType});

  @override
  State<ProcessDialog> createState() => _ProcessDialogState();
}

class _ProcessDialogState extends State<ProcessDialog> {
  String? _selectedComPort;
  String? _selectedPanelNumber;
  String? _selectedBoardType;
  int _selectedBaudRate = 19200;
  int _selectedDataBit = 8;
  String _selectedParity = 'None';
  int _selectedStopBit = 1;
  bool _isBroadcast = false;

  List<String> _availablePorts = [];
  final List<String> _panelNumbers =
      List.generate(48, (i) => 'Panel-${(i + 1).toString().padLeft(2, '0')}');
  final List<String> _boardTypes = ['STANDALONE', 'RCU'];
  final List<int> _baudRates = [300, 600, 1200, 2400, 4800, 9600, 19200, 38400];
  final List<int> _dataBits = [7, 8];
  final List<String> _parities = ['None', 'Odd', 'Even'];
  final List<int> _stopBits = [1, 2];

  @override
  void initState() {
    super.initState();
    _selectedComPort = AppDataManager().modbusComPort;
    _selectedPanelNumber = _panelNumbers.contains(widget.initialPanel) ? widget.initialPanel : null;
    _selectedBoardType = _boardTypes.contains(widget.initialBoardType) ? widget.initialBoardType : 'STANDALONE';
    _availablePorts = List.generate(10, (i) => 'COM${i + 1}');
    _initPorts();
  }

  Future<void> _initPorts() async {
    try {
      final devices = await RS485Com.getAvailableDevices();
      if (!mounted) return;
      setState(() {
        _availablePorts = devices.map((d) => d.deviceName).toSet().toList();
      });
    } catch (e) {
      appLog('Error fetching serial ports: $e');
    }
  }

  // the port list, plus the saved port when it is not plugged in now (a dropdown needs its value among the items)
  List<String> get _portItems => [
        ..._availablePorts,
        if (_selectedComPort != null && !_availablePorts.contains(_selectedComPort)) _selectedComPort!,
      ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppBrandColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppBrandColors.border),
          boxShadow: const [BoxShadow(color: Color(0x1AF28C33), blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).t('process_configuration'),
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppBrandColors.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              CheckboxListTile(
                title: Text(
                  AppLocalizations.of(context).t('broadcast'),
                  style: GoogleFonts.inter(color: AppBrandColors.textPrimary, fontWeight: FontWeight.w500),
                ),
                value: _isBroadcast,
                onChanged: (newValue) {
                  setState(() {
                    _isBroadcast = newValue!;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppBrandColors.accent,
                checkColor: Colors.white,
              ),
              const Divider(height: 20, thickness: 1, color: AppBrandColors.divider),
              _buildDropdownRow(
                _buildDialogDropdown(AppLocalizations.of(context).t('board_type'), _boardTypes, _selectedBoardType,
                    (String? val) => setState(() => _selectedBoardType = val)),
                _buildDialogDropdown(AppLocalizations.of(context).t('panel_number'), _panelNumbers, _selectedPanelNumber,
                    (String? val) => setState(() => _selectedPanelNumber = val)),
              ),
              _buildDropdownRow(
                _buildDialogDropdown(AppLocalizations.of(context).t('com_port'), _portItems, _selectedComPort,
                    (String? val) => setState(() => _selectedComPort = val)),
                _buildDialogDropdown(AppLocalizations.of(context).t('baud_rate'), _baudRates, _selectedBaudRate,
                    (val) => setState(() => _selectedBaudRate = val!)),
              ),
              _buildDropdownRow(
                _buildDialogDropdown(AppLocalizations.of(context).t('data_bit'), _dataBits, _selectedDataBit,
                    (val) => setState(() => _selectedDataBit = val!)),
                _buildDialogDropdown(AppLocalizations.of(context).t('parity'), _parities, _selectedParity,
                    (String? val) => setState(() => _selectedParity = val!)),
              ),
              _buildDropdownRow(
                _buildDialogDropdown(AppLocalizations.of(context).t('stop_bit'), _stopBits, _selectedStopBit,
                    (val) => setState(() => _selectedStopBit = val!)),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppBrandColors.toggleInactive,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppBrandColors.border),
                      ),
                      child: Text(
                        AppLocalizations.of(context).t('cancel'),
                        style: GoogleFonts.inter(
                          color: AppBrandColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () {
                      if (_selectedPanelNumber == null || _selectedBoardType == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    AppLocalizations.of(context).t('board_panel_required'),
                                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            margin: const EdgeInsets.fromLTRB(40, 0, 40, 24),
                            duration: const Duration(seconds: 2),
                            elevation: 4,
                          ),
                        );
                        return;
                      }

                      final Map<String, dynamic> result = {
                        'isBroadcast': _isBroadcast,
                        'panelNumber': _selectedPanelNumber,
                        'boardType': _selectedBoardType,
                        'baudRate': _selectedBaudRate,
                        'dataBit': _selectedDataBit,
                        'parity': _selectedParity,
                        'stopBit': _selectedStopBit,
                        'comPort': _selectedComPort,
                      };

                      Navigator.of(context).pop(result);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppBrandColors.accent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33F28C33),
                            blurRadius: 15,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context).t('done'),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownRow(Widget left, [Widget? right]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          if (right != null) ...[
            const SizedBox(width: 16),
            Expanded(child: right),
          ] else ...[
            const Spacer(),
          ],
        ],
      ),
    );
  }

  Widget _buildDialogDropdown<T>(
      String label, List<T> items, T? value, ValueChanged<T?>? onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppBrandColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          onChanged: onChanged,
          menuMaxHeight: 300,
          dropdownColor: AppBrandColors.dropdownMenuBg,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppBrandColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppBrandColors.accent, width: 1.5),
            ),
            filled: true,
            fillColor: AppBrandColors.inputFieldBg,
          ),
          style: GoogleFonts.inter(
            color: AppBrandColors.textPrimary,
            fontSize: 14,
          ),
          iconEnabledColor: AppBrandColors.textSecondary,
          items: items.map((T item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(
                item.toString(),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppBrandColors.textPrimary,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
