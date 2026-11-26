/*
 * =============================================================================
 *  ble_manager.dart  -  Touchmatik Glide 1.1.0 (Agragamee, Oct-2026)
 *
 *  The Bluetooth side of "Upload over Bluetooth" (design 3.5): permissions,
 *  scan, connect, and BleConfigLink, the flutter_blue_plus adapter behind
 *  config_uploader.dart's PanelLink. The protocol itself (OK / ERR / INFO /
 *  VER, retries, CRC verification) lives in config_uploader.dart.
 *
 *  1.1.0 changes against 1.0.0:
 *   - the scan asks the phone's OS for the panel's service UUID only, so a
 *     panel in mesh mode (same name, no service) is not listed; an empty
 *     scan is followed by one short unfiltered scan that names a KIPL-2M
 *     panel outside its window;
 *   - "connected" means discovered and subscribed (linkState 'ready'), never
 *     before; a missing service is an error message, not an exception;
 *   - one MTU exchange (connect(mtu: 247)), lines split at MTU-3 by the
 *     uploader, so it also works at MTU 23;
 *   - one connectionState listener per connection, cancelled at its
 *     disconnect; dispose() releases everything;
 *   - every step goes to the app log (app_log.dart) instead of print();
 *   - review fixes: '#VER' and '#CLOSE' go by the device's real name (a
 *     device without a name is never taken for a KIPL-2M panel, C10); the
 *     diagnosis scan lists a device that advertises the configuration service
 *     but was missed by the phone's service filter, instead of calling it
 *     "not in configuration mode".
 *  The class name, the UUIDs, bleHexFilePath, hexFilePathStream,
 *  progressStream and transferStatusStream are unchanged.
 * =============================================================================
 */
import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../localization/app_localizations.dart';
import '../services/app_log.dart';
import '../services/hex_file_check.dart';
import 'config_uploader.dart';

// =============================================================================
//  BleConfigLink - one GATT connection to the panel's configuration service
// =============================================================================
class BleConfigLink implements PanelLink {
  final BluetoothDevice device;
  final BluetoothCharacteristic rx; // the phone writes here
  final BluetoothCharacteristic tx; // the panel notifies here

  @override
  final bool probeVersion;

  final StreamController<String> _replies = StreamController<String>.broadcast();
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  bool _up = true;

  BleConfigLink(this.device, this.rx, this.tx, {required this.probeVersion}) {
    _valueSub = tx.onValueReceived.listen((value) {
      final text = String.fromCharCodes(value).trim();
      if (text.isNotEmpty && !_replies.isClosed) _replies.add(text);
    });
    _stateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) _dropped();
    });
  }

  @override
  int get maxWrite => device.mtuNow - 3 >= 20 ? device.mtuNow - 3 : 20;

  @override
  Stream<String> get replies => _replies.stream;

  @override
  bool get isUp => _up && device.isConnected;

  @override
  Future<void> write(List<int> bytes) async {
    if (!isUp) throw LinkError('connect', 'not connected');
    await rx.write(bytes, withoutResponse: false, timeout: 5);
  }

  // the link is gone: stop listening and end the reply stream, which wakes
  // an uploader waiting for an answer
  void _dropped() {
    if (!_up) return;
    _up = false;
    _valueSub?.cancel();
    _stateSub?.cancel();
    _replies.close();
  }

  @override
  Future<void> close() async {
    _dropped();
    if (device.isConnected) {
      await device.disconnect(timeout: 5);
    }
  }
}

// =============================================================================
//  BLEManager
// =============================================================================
class BLEManager {
  // ================= UUIDs (MUST MATCH ESP32) =================
  static const String serviceUUID = "12345678-1234-1234-1234-1234567890ab"; // Service UUID to scan for ESP32 devices
  static const String rxUUID = "12345678-1234-1234-1234-1234567890ac"; // Characteristic UUID for receiving data (RX)
  static const String txUUID = "12345678-1234-1234-1234-1234567890ad"; // Characteristic UUID for transmitting data (TX)

  /// Advertised name of a TPF01-ESP-PANEL: KIPL-2M-XXYYZZ (C-0).
  static const String namePrefix = 'KIPL-2M-';

  // ---- the HEX file to upload (unchanged API)
  String? bleHexFilePath;
  final StreamController<String?> _hexFilePathController = StreamController<String?>.broadcast();
  Stream<String?> get hexFilePathStream => _hexFilePathController.stream;

  /// The pre-flight of the last checked file (checkHexFile / upload).
  HexCheck? lastCheck;

  // ---- link state (design 3.5): idle | scanning | connecting | ready | uploading | failed
  final ValueNotifier<String> linkState = ValueNotifier<String>('idle');
  String linkDeviceId = '';
  String linkDeviceName = '';
  String linkFirmware = ''; // '0.6.0' after the probe; '' = protocol v1 / unknown

  /// The last message for the user, in English, and the same message as an
  /// app_en.arb key (link_*) with its parameters, for AppLocalizations.t().
  String linkMessage = '';
  String linkMessageKey = '';
  Map<String, String> linkMessageParams = const {};

  /// The connected panel, set only while linkState is 'ready'.
  BluetoothDevice? connectedDevice;

  final StreamController<BluetoothDevice?> _connectedDeviceController = StreamController<BluetoothDevice?>.broadcast();

  /// Emits the panel when the link is ready, and null when it disconnects.
  Stream<BluetoothDevice?> get connectedDeviceStream => _connectedDeviceController.stream;

  final StreamController<String?> _scanErrorController = StreamController<String?>.broadcast();

  /// Scan problems and hints, in English (also in linkMessage / linkMessageKey).
  Stream<String?> get scanErrorStream => _scanErrorController.stream;

  final StreamController<String> _transferStatusController = StreamController<String>.broadcast();

  /// Upload status lines, in English ("Sending record 12 / 37").
  Stream<String> get transferStatusStream => _transferStatusController.stream;

  final StreamController<int> _progressController = StreamController<int>.broadcast();

  /// Upload progress 0..100.
  Stream<int> get progressStream => _progressController.stream;

  BluetoothDevice? _device; // the chosen panel, kept for a retry and for #CLOSE
  String _deviceName = '';
  BleConfigLink? _link;
  bool _linkUsedForUpload = false; // the panel's disconnect after a stored upload is expected
  bool _disposed = false;

  // ---- scan results: the panels in their configuration window
  List<ScanResult> _found = const [];
  final StreamController<List<ScanResult>> _scanController = StreamController<List<ScanResult>>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;

  /// Panels found by the last scan (their configuration service advertised).
  /// A new listener gets the current list first.
  Stream<List<ScanResult>> get scanResults async* {
    yield _found;
    yield* _scanController.stream;
  }

  List<ScanResult> get foundPanels => _found;

  /// True when a panel has been chosen (connectTo), so upload() can (re)connect.
  bool get hasPanel => _device != null;

  /// The name to show for a scan result: advertised name, else the OS name,
  /// else 'KIPL-2M-?'. For the screen only: what the app does with a device
  /// goes by [advertisedName] (review_glide finding 4).
  static String displayName(ScanResult r) {
    final name = advertisedName(r);
    return name.isNotEmpty ? name : '$namePrefix?';
  }

  /// The name a scan result really carries: its advertised name, else the
  /// name the OS keeps for it; '' when it has none.
  static String advertisedName(ScanResult r) =>
      r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;

  /// True for a TPF01-ESP-PANEL name (KIPL-2M-XXYYZZ, C-4.2). Only such a
  /// device gets '#VER' (C10) and "Exit configuration mode"; a device without
  /// a name is never taken for one.
  static bool isPanelName(String name) => name.startsWith(namePrefix) && name.length > namePrefix.length && !name.endsWith('?');

  /// The unfiltered diagnosis scan, sorted (pure, for the tests): devices that
  /// do advertise the configuration service (the phone's service filter missed
  /// them: they are in their window and can be connected), and the names of
  /// KIPL-2M panels without it (outside their window).
  static ({List<ScanResult> inWindow, List<String> outside}) sortDiagnosis(Iterable<ScanResult> results) {
    final service = Guid(serviceUUID);
    final inWindow = <ScanResult>[];
    final outside = <String>{};
    for (final r in results) {
      if (r.advertisementData.serviceUuids.contains(service)) {
        inWindow.add(r);
      } else if (isPanelName(r.advertisementData.advName)) {
        outside.add(r.advertisementData.advName);
      }
    }
    return (inWindow: inWindow, outside: outside.toList()..sort());
  }

  // ---------------------------------------------------------------------------
  void _setState(String state) {
    if (_disposed || linkState.value == state) return;
    linkState.value = state;
    appLog('link: $state');
  }

  void _message(String key, String english, [Map<String, String> params = const {}]) {
    linkMessageKey = key;
    linkMessageParams = params;
    linkMessage = english;
    if (english.isNotEmpty) appLog('link: $english');
  }

  void _scanError(String key, String english, [Map<String, String> params = const {}]) {
    _message(key, english, params);
    if (!_disposed) _scanErrorController.add(english);
  }

  // ================= Bluetooth state and permissions =================

  /// Check if Bluetooth is enabled on the device.
  Future<bool> isBluetoothEnabled() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  // Android 12+ (API 31): "Nearby devices" (scan + connect). Android 11 and
  // older: Location, and Location services must be on for a BLE scan.
  Future<bool> _permissions() async {
    if (!Platform.isAndroid) return true; // iOS asks by itself on first use
    var sdk = 31;
    try {
      sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (e) {
      appLog('Android version unknown ($e): assuming API 31');
    }
    if (sdk >= 31) {
      final r = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
      if (!r.values.every((s) => s.isGranted)) {
        _scanError('link_permissions', 'Bluetooth permissions are required to scan for panels.');
        return false;
      }
      return true;
    }
    final location = await Permission.location.request();
    if (!location.isGranted) {
      _scanError('link_permissions', 'Bluetooth permissions are required to scan for panels.');
      return false;
    }
    if (!await Permission.location.serviceStatus.isEnabled) {
      _scanError('link_location_off',
          'Location services are off. Android 11 and older need them on to find Bluetooth devices.');
      return false;
    }
    return true;
  }

  // Waits up to 3 s for a known adapter state; switches Bluetooth on (Android)
  Future<bool> _bluetoothOn() async {
    var state = BluetoothAdapterState.unknown;
    try {
      state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // still unknown after 3 s
    }
    if (state == BluetoothAdapterState.on) return true;
    if (state == BluetoothAdapterState.unauthorized) {
      _scanError('link_permissions', 'Bluetooth permissions are required to scan for panels.');
      return false;
    }
    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn(timeout: 15);
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 5));
        return true;
      } catch (e) {
        appLog('turnOn: $e');
      }
    }
    _scanError('link_bt_off', 'Bluetooth is off. Switch it on and scan again.');
    return false;
  }

  // ================= Scan =================

  /// Scans 10 s for panels in their configuration window (OS filter on the
  /// service UUID). Nothing found: one 4 s unfiltered scan, only to tell the
  /// user whether a KIPL-2M panel is near but not in its window.
  Future<void> startScan() async {
    if (_disposed) return;
    _message('', '');
    if (!await _permissions()) return;
    if (!await _bluetoothOn()) return;

    final keepState = linkState.value == 'ready' || linkState.value == 'uploading';
    if (!keepState) _setState('scanning');
    _found = const [];
    _scanController.add(_found);
    try {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        if (_disposed) return;
        _found = List.unmodifiable(results);
        _scanController.add(_found);
      });
      appLog('scan: 10 s for service $serviceUUID');
      await FlutterBluePlus.startScan(withServices: [Guid(serviceUUID)], timeout: const Duration(seconds: 10));
      await _scanEnded(const Duration(seconds: 12));
    } catch (e) {
      _scanError('link_failed', 'Bluetooth scan failed: $e', {'message': '$e'});
    } finally {
      await _scanSub?.cancel();
      _scanSub = null;
    }
    if (_disposed) return;
    appLog('scan: ${_found.length} panel(s) in configuration mode'
        '${_found.isEmpty ? '' : ': ${_found.map((r) => '${displayName(r)} ${r.rssi} dBm').join(', ')}'}');
    if (_found.isEmpty && linkMessageKey.isEmpty) await _diagnosisScan();
    if (linkState.value == 'scanning') _setState('idle');
  }

  Future<void> _scanEnded(Duration limit) async {
    try {
      await FlutterBluePlus.isScanning.where((s) => !s).first.timeout(limit);
    } catch (_) {
      await FlutterBluePlus.stopScan();
    }
  }

  // After an empty filtered scan: is a KIPL-2M panel near, outside its window?
  // A device that does advertise the configuration service is listed as
  // connectable instead (some phones' service filters miss 128-bit UUIDs),
  // never reported as "not in configuration mode" (review_glide finding 8).
  Future<void> _diagnosisScan() async {
    final seen = <DeviceIdentifier, ScanResult>{};
    StreamSubscription<List<ScanResult>>? sub;
    try {
      sub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          seen[r.device.remoteId] = r;
        }
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
      await _scanEnded(const Duration(seconds: 6));
    } catch (e) {
      appLog('diagnosis scan: $e');
    } finally {
      await sub?.cancel();
    }
    if (_disposed) return;
    final sorted = sortDiagnosis(seen.values);
    if (sorted.inWindow.isNotEmpty) {
      _found = List.unmodifiable(sorted.inWindow);
      _scanController.add(_found);
      appLog('diagnosis scan: ${_found.length} device(s) with the configuration service that the filtered scan '
          'missed: ${_found.map((r) => '${displayName(r)} ${r.rssi} dBm').join(', ')}');
      return;
    }
    final names = sorted.outside;
    if (names.isNotEmpty) {
      final name = names.join(', ');
      _scanError(
          'link_found_not_config',
          'Found $name, but it is not in configuration mode. Hold SW2+SW3 together for 8 s; '
              'the status LED double-flashes when ready (5 minutes).',
          {'name': name});
    } else {
      _scanError('link_no_panel', 'No panel found. Hold SW2+SW3 for 8 s, or power the panel without a program.');
    }
  }

  /// Stops a running scan.
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      appLog('stopScan: $e');
    }
  }

  // ================= Diagnostics =================
  /// Bluetooth state, permissions and the expected UUIDs, as text (also logged).
  Future<String> runDiagnostics() async {
    final buffer = StringBuffer();
    buffer.writeln("=== BLE DIAGNOSTICS ===");
    try {
      final state = await FlutterBluePlus.adapterState.first;
      buffer.writeln("Bluetooth State: $state");
      buffer.writeln("Bluetooth Enabled: ${state == BluetoothAdapterState.on}");
      buffer.writeln("\nPermissions:");
      buffer.writeln("  BLUETOOTH_SCAN: ${(await Permission.bluetoothScan.status).name}");
      buffer.writeln("  BLUETOOTH_CONNECT: ${(await Permission.bluetoothConnect.status).name}");
      buffer.writeln("  LOCATION (Android 11 and older): ${(await Permission.location.status).name}");
      final connected = FlutterBluePlus.connectedDevices;
      buffer.writeln("\nConnected Devices: ${connected.length}");
      for (final device in connected) {
        buffer.writeln("  - ${device.platformName} (${device.remoteId})");
      }
      buffer.writeln("\nLink: ${linkState.value} $linkDeviceName firmware '$linkFirmware'");
      buffer.writeln("\nUUIDs Expected:");
      buffer.writeln("  Service: $serviceUUID");
      buffer.writeln("  RX: $rxUUID");
      buffer.writeln("  TX: $txUUID");
    } catch (e) {
      buffer.writeln("Error during diagnostics: $e");
    }
    final result = buffer.toString();
    appLog(result);
    return result;
  }

  // ================= File =================

  /// Sets the file to upload (after Generate / Process, or the picker).
  void setHexFile(String? path) {
    bleHexFilePath = path;
    lastCheck = null;
    if (!_disposed) _hexFilePathController.add(path);
  }

  /// Pre-flight of the selected file (C-5.3); also kept in [lastCheck].
  Future<HexCheck> checkHexFile() async {
    final check = await HexCheck.ofFile(bleHexFilePath ?? '');
    lastCheck = check;
    return check;
  }

  /// Opens the file picker for a .hex file.
  Future<void> pickBleHexFile(BuildContext context) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
    final String? filePath = result?.files.single.path;
    if (filePath == null) return;
    if (p.extension(filePath).toLowerCase() != '.hex') {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context).t('select_hex_file'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          width: 200,
        ),
      );
      return;
    }
    setHexFile(filePath);
  }

  // ================= Connect =================

  static BluetoothService? _findService(List<BluetoothService> services) {
    final want = Guid(serviceUUID);
    for (final s in services) {
      if (s.uuid == want) return s;
    }
    return null;
  }

  static BluetoothCharacteristic? _findChar(BluetoothService service, String uuid) {
    final want = Guid(uuid);
    for (final c in service.characteristics) {
      if (c.uuid == want) return c;
    }
    return null;
  }

  static Future<void> _quietDisconnect(BluetoothDevice device) async {
    try {
      await device.disconnect(timeout: 5);
    } catch (e) {
      appLog('disconnect: $e');
    }
  }

  // connect, with one more try after GATT error 133 (Android's catch-all)
  static Future<void> _connect(BluetoothDevice device) async {
    for (var attempt = 1;; attempt++) {
      try {
        await device.connect(timeout: const Duration(seconds: 10), mtu: Platform.isAndroid ? 247 : null);
        return;
      } on FlutterBluePlusException catch (e) {
        if (attempt == 1 && e.code == 133) {
          appLog('connect: GATT 133, one more try in 1 s');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        await _quietDisconnect(device);
        throw LinkError('connect', e.description ?? '$e');
      }
    }
  }

  // V1.1.0: connected = discovered + subscribed; anything less is a failed connect
  static Future<BleConfigLink> openBleLink(BluetoothDevice device, String advName) async {
    BluetoothService? service;
    await FlutterBluePlus.stopScan();
    appLog('connect: ${device.remoteId} $advName');
    await _connect(device);
    try {
      if (Platform.isAndroid) {
        try {
          await device.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
        } catch (e) {
          appLog('connection priority: $e');
        }
      }
      service = _findService(await device.discoverServices(timeout: 10));
      if (service == null && Platform.isAndroid) {
        appLog('service not found: clearing the GATT cache, discovering again');
        await device.clearGattCache(); // a table cached from the panel's mesh mode
        service = _findService(await device.discoverServices(timeout: 10));
      }
    } on LinkError {
      rethrow;
    } catch (e) {
      await _quietDisconnect(device);
      throw LinkError('connect', '$e');
    }
    if (service == null) {
      await _quietDisconnect(device);
      throw LinkError('not-in-window'); // "hold SW2+SW3 for 8 s, then scan again"
    }
    final rx = _findChar(service, rxUUID);
    final tx = _findChar(service, txUUID);
    if (rx == null || tx == null) {
      await _quietDisconnect(device);
      throw LinkError('bad-service');
    }
    try {
      await tx.setNotifyValue(true, timeout: 5);
    } catch (e) {
      await _quietDisconnect(device);
      throw LinkError('connect', 'subscribe: $e');
    }
    final link = BleConfigLink(device, rx, tx, probeVersion: isPanelName(advName));
    appLog('connected: MTU ${device.mtuNow}, ${link.maxWrite} bytes per write, '
        '${link.probeVersion ? 'KIPL panel' : 'other peripheral (protocol v1)'}');
    return link;
  }

  // one connectionState listener per connection, cancelled at its disconnect
  void _watch(BluetoothDevice device) {
    final sub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) _onDisconnected(device);
    });
    device.cancelWhenDisconnected(sub, delayed: true, next: true);
  }

  void _onDisconnected(BluetoothDevice device) {
    if (_disposed) return;
    final wasReady = connectedDevice != null;
    connectedDevice = null;
    if (wasReady) _connectedDeviceController.add(null);
    final reason = device.disconnectReason;
    appLog('link: ${device.remoteId} disconnected'
        '${reason == null ? '' : ' (${reason.code} ${reason.description ?? ''})'}');
    if (_linkUsedForUpload && upPhase == 'done') {
      // the panel stored the file and restarts: expected (design 3.5)
      if (linkState.value != 'idle') _setState('idle');
      return;
    }
    switch (linkState.value) {
      case 'ready':
        _message('link_disconnected', 'Panel disconnected');
        _setState('idle');
        break;
      case 'uploading':
        // the uploader reports it; settle the state once it has finished
        if (upPhase == 'failed') _setState('failed');
        break;
    }
  }

  // closes the current link without a message (the panel stays chosen)
  Future<void> _dropLink() async {
    final link = _link;
    _link = null;
    if (link != null) {
      try {
        await link.close();
      } catch (e) {
        appLog('close: $e');
      }
    }
    if (connectedDevice != null) {
      connectedDevice = null;
      if (!_disposed) _connectedDeviceController.add(null);
    }
  }

  void _linkFailed(LinkError e) {
    switch (e.reason) {
      case 'not-in-window':
        _message('link_not_in_window', '$linkDeviceName is not in configuration mode. Hold SW2+SW3 for 8 s, then scan again.',
            {'name': linkDeviceName});
        break;
      case 'bad-service':
        _message('link_bad_service', 'This device does not offer the Touchmatik configuration service.');
        break;
      default:
        final detail = e.detail.isEmpty ? e.reason : e.detail;
        _message('link_failed', 'Connection failed: $detail', {'message': detail});
    }
    _setState('failed');
  }

  /// True when the chosen device's real name is a KIPL-2M panel's: only then
  /// are '#VER' and '#CLOSE' sent to it (C10).
  bool get isPanel => isPanelName(_deviceName);

  /// Connects to a panel from the scan list: connect, discover, subscribe,
  /// then '#VER' for a KIPL-2M panel. True = 'ready' (linkFirmware set).
  /// [advName] is the device's real name ([advertisedName]), never the
  /// display fallback 'KIPL-2M-?': a device without a name gets protocol v1
  /// and no "Exit configuration mode" (review_glide finding 4).
  Future<bool> connectTo(BluetoothDevice device, {String? advName}) async {
    if (_disposed) return false;
    await stopScan();
    await _dropLink();
    var name = (advName == null || advName.isEmpty) ? device.advName : advName;
    if (name.isEmpty) name = device.platformName;
    _device = device;
    _deviceName = name;
    _linkUsedForUpload = false;
    linkDeviceId = device.remoteId.str;
    linkDeviceName = name.isNotEmpty ? name : device.remoteId.str; // shown in the dialog title
    linkFirmware = '';
    _message('', '');
    _setState('connecting');
    BleConfigLink link;
    try {
      link = await openBleLink(device, name);
    } on LinkError catch (e) {
      appLog('connect failed: $e');
      _linkFailed(e);
      return false;
    } catch (e) {
      appLog('connect failed: $e');
      _linkFailed(LinkError('connect', '$e'));
      return false;
    }
    if (_disposed) {
      await link.close();
      return false;
    }
    _link = link;
    _watch(device);
    linkFirmware = await probeFirmware(link);
    if (!link.isUp) {
      _message('link_disconnected', 'Panel disconnected');
      _setState('failed');
      return false;
    }
    connectedDevice = device;
    _setState('ready');
    _message(linkFirmware.isEmpty ? 'link_ready_v1' : 'link_ready',
        linkFirmware.isEmpty ? 'Ready - protocol v1 (no version reported)' : 'Ready - firmware $linkFirmware',
        {'fw': linkFirmware});
    if (!_disposed) _connectedDeviceController.add(device);
    return true;
  }

  /// 1.0.0 name of connectTo (the scan list's onTap).
  Future<void> selectDevice(BluetoothDevice device) async {
    await connectTo(device);
  }

  /// For uploadFile(): the open link of the chosen panel, or a new connection
  /// to it (the automatic retry and a manual Retry reconnect here).
  Future<PanelLink> openLink() async {
    final device = _device;
    if (device == null) throw LinkError('no-device');
    _linkUsedForUpload = true;
    _setState('uploading');
    final current = _link;
    if (current != null && current.isUp) return current;
    await _dropLink();
    final link = await openBleLink(device, _deviceName);
    _link = link;
    _watch(device);
    return link;
  }

  // ================= Upload =================

  void _reportProgress() {
    if (_disposed) return;
    if (upTotal > 0) _progressController.add((upSent * 100) ~/ upTotal);
    switch (upPhase) {
      case 'connect':
        _transferStatusController.add('Connecting to $linkDeviceName (attempt $upAttempt)...');
        break;
      case 'probe':
        _transferStatusController.add('Asking the panel for its firmware version...');
        break;
      case 'send':
      case 'store':
        _transferStatusController.add('Sending record ${upSent + 1 > upTotal ? upTotal : upSent + 1} / $upTotal');
        break;
      case 'done':
        _transferStatusController.add(upVerified
            ? 'Stored and verified: panel ${upInfo['panel'] ?? '?'}, ${upInfo['records'] ?? '?'} records, '
                'CRC ${upInfo['crc'] ?? '?'}. The panel restarts now.'
            : 'Stored (the panel did not report a CRC).');
        break;
      case 'failed':
        _transferStatusController.add('Error: ${upTokenText(upError)} (record $upErrorRecord)');
        break;
    }
  }

  /// Uploads [file] (default: the pre-flight of bleHexFilePath) to the chosen
  /// panel with config_uploader.dart's uploadFile(). The up* variables hold
  /// the details; [onProgress] is called at every step.
  Future<bool> upload({HexCheck? file, void Function()? onProgress}) async {
    final check = file ?? await checkHexFile();
    lastCheck = check;
    _message('', ''); // "Ready - ..." is no longer true once an upload starts
    final ok = await uploadFile(check, openLink, () {
      _reportProgress();
      onProgress?.call();
    });
    _link = null; // uploadFile closed it
    if (upFirmware.isNotEmpty) linkFirmware = upFirmware;
    if (!_disposed) {
      if (ok) {
        _setState('idle');
      } else {
        if (upError == 'link') {
          // the connect failed (with its reason), or the link dropped on the way
          if (upLinkError.isNotEmpty) {
            _linkFailed(LinkError(upLinkError, upLinkDetail));
          } else {
            _message('link_disconnected', 'Panel disconnected');
          }
        }
        _setState('failed');
      }
    }
    return ok;
  }

  /// 1.0.0 entry point: uploads bleHexFilePath to the chosen panel.
  Future<bool> flashHexFile({int maxRetries = 3}) => upload();

  /// "Exit configuration mode" after a cancel or a failure (P3): sends
  /// '<#CLOSE>\n'; the panel answers OK, closes its window and restarts into
  /// its stored program. True = the panel answered OK.
  Future<bool> exitConfigMode() async {
    final device = _device;
    if (device == null || !isPanel) return false; // C10: '#CLOSE' only to a KIPL-2M panel
    try {
      final current = _link;
      final link = (current != null && current.isUp) ? current : await openBleLink(device, _deviceName);
      _link = link;
      final answer = await panelCommand(link, '#CLOSE', const Duration(seconds: 3));
      await _dropLink();
      _setState('idle');
      return answer == 'OK';
    } catch (e) {
      appLog('exit configuration mode: $e');
      await _dropLink();
      return false;
    }
  }

  /// Disconnects and forgets the chosen panel.
  Future<void> disconnect() async {
    await _dropLink();
    _device = null;
    _deviceName = '';
    linkFirmware = '';
    _setState('idle');
  }

  /// Stops the scan, disconnects, cancels the listeners and closes the
  /// streams (configuration_page dispose). The manager is unusable after it.
  Future<void> dispose() async {
    if (_disposed) return;
    if (const {'connect', 'probe', 'send', 'store'}.contains(upPhase)) cancelUpload();
    _disposed = true;
    await _scanSub?.cancel();
    _scanSub = null;
    await stopScan();
    await _dropLink();
    _device = null;
    await _hexFilePathController.close();
    await _connectedDeviceController.close();
    await _scanErrorController.close();
    await _transferStatusController.close();
    await _progressController.close();
    await _scanController.close();
    linkState.dispose();
  }
}
