/*
 * =============================================================================
 *  config_check.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  Validation before Generate (V0.6.0 design 3.3). checkConfig() fills
 *  configErrors (hard limits: nothing may be generated) and configWarnings
 *  (soft limits of the firmware: "Generate anyway?"); the configuration and
 *  preview pages show them.
 *
 *  Hard limits are the field sizes of the GUI HEX (bytes 0..255, words
 *  0..65535, string lengths of net_gui.c, row counts of the V3 arrays).
 *  Soft limits are what TPF01-ESP-PANEL uses (engine_internal.h: 32 lamps,
 *  4 bells, 4 fans, 16 dimmers, 8 curtains, 4 thermostats, 16 scenes;
 *  thermostat set point 16..32; net_gui.c keeps one byte of a DP id and
 *  ignores id 0). Finally the converters run in memory, so a configuration
 *  that passes here also converts.
 *  The messages are plain English (like the converters' ConfigRangeError).
 *
 *  Review fixes (review_glide findings 5-7): row labels must be the two-digit
 *  form the converters read ('OD-05', not 'OD-5', which they would drop
 *  silently); a row without its type / output / parameter, or with a value
 *  the converters do not know, is a warning, because the converters write
 *  00 for it (LAMP for a scene output, an output function or a DP
 *  parameter). The look-ups use the converters' own tables.
 * =============================================================================
 */
import '../data/app_data.dart';
import 'bms_info_th.dart';
import 'convert_manager.dart';
import 'hex_tools.dart';
import 'in_main_th.dart';
import 'panel_th.dart';
import 'scene_th.dart';
import 'txt_reader.dart';
import 'wifi_conn_th.dart';

const int maxKeys = 20;
const int maxOutputs = 16;
const int maxInputs = 4;
const int maxSceneRows = 16;
const int maxDpRows = 24;

// the result of the last checkConfig()
List<String> configErrors = [];
List<String> configWarnings = [];

// the firmware's device count for a key / output / input device name; null = no limit checked
int? deviceCountOf(String? device) {
  final d = (device ?? '').trim().toUpperCase();
  if (d.isEmpty) return null;
  if (d == 'LAMP') return 32;
  if (d == 'BELL') return 4;
  if (d.startsWith('FAN')) return 4;
  if (d.startsWith('DIMMER')) return 16;
  if (d.startsWith('CURTAIN')) return 8;
  if (d.startsWith('THERMOSTAT')) return 4;
  if (d.startsWith('SCENE')) return 16;
  return null;
}

class _Checker {
  final List<String> errors = [];
  final List<String> warnings = [];

  String text(dynamic v) => v?.toString().trim() ?? '';

  // a number field: '' -> null; out of [min..max] or not a number -> error
  int? number(dynamic value, int min, int max, String what) {
    final t = text(value);
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null) {
      errors.add('$what = "$t" is not a number');
      return null;
    }
    if (v < min || v > max) {
      errors.add('$what = $v (allowed $min..$max)');
      return null;
    }
    return v;
  }

  // the soft device range of a numbered device
  void deviceRange(String? device, int? n, String what) {
    final count = deviceCountOf(device);
    if (count == null || n == null) return;
    if (n < 1 || n > count) {
      warnings.add('$what: ${device!.trim()} $n - the panel knows ${device.trim()} 1..$count');
    }
  }

  // a row label 'OD-05' -> 5 (null = no label). Exactly two digits, as the
  // converters read it: 'OD-5' would pass a looser check and then be left out
  // of the HEX without a word (review_glide finding 6).
  int? labelNumber(dynamic label, String prefix) {
    final m = RegExp('^$prefix-(\\d\\d)\$').firstMatch(text(label));
    return m == null ? null : int.parse(m.group(1)!);
  }

  // a dropdown value the converter looks up in [table]: missing or unknown is
  // a warning, because the converter then writes [fallback] (review_glide finding 5)
  void known(String value, Map<String, Object> table, String key, String what, String field, String fallback) {
    if (value.isEmpty) {
      warnings.add('$what has no $field - it is written as $fallback');
    } else if (!table.containsKey(key)) {
      warnings.add('$what: $field "$value" is not known to the converter - it is written as $fallback');
    }
  }

  // ON / OFF / TOGGLE / ON-L-1..10 (any spelling the converters accept)
  void state(dynamic value, String what) {
    try {
      stateByte(text(value), what);
    } on ConfigRangeError catch (e) {
      errors.add(e.message);
    }
  }

  // a network-page string: at most [max] printable ASCII characters without '"'
  void field(String? value, int max, String what) {
    final t = (value ?? '').trim();
    if (t.isEmpty) return;
    if (t.length > max) errors.add('$what has ${t.length} characters (at most $max)');
    if (!isFieldText(t)) errors.add('$what: only printable ASCII without a double quote (") is allowed');
  }
}

/// Fills configErrors and configWarnings for [d]; true when there is no error.
bool checkConfig(AppDataManager d) {
  final c = _Checker();
  final panel = d.panelNo;
  final page = panel == null ? 'Panel' : panelLabel(panel);

  // ---- panel number (C2)
  if (panel == null) {
    c.errors.add('Panel number: choose Panel-01 .. Panel-48 on the Panel page');
  }

  // ---- keys
  int keys = 0;
  for (int i = 0; i < d.panelSwitchRows.length; i++) {
    final row = d.panelSwitchRows[i];
    final function = c.text(row['function']);
    final numberText = c.text(row['number']);
    if (function.isEmpty && numberText.isEmpty) continue;
    keys++;
    final what = '$page SW-${(i + 1).toString().padLeft(2, '0')}';
    if (i >= maxKeys) {
      c.errors.add('$what: a panel has at most $maxKeys keys');
      continue;
    }
    final n = c.number(numberText, 0, 255, '$what number');
    if (function.isEmpty) {
      c.warnings.add('$what has a number but no function');
    } else {
      // a function from an old or hand-edited TXT that panel_th does not map
      c.known(function, PanelCombinedTH.keyActionMap, function, what, 'function', '00 (no function)');
      if (numberText.isEmpty || n != null) c.deviceRange(function, n ?? 0, what); // no number = device 0, which no device has
    }
  }
  if (keys > maxKeys) c.errors.add('$page: $keys keys (at most $maxKeys)');

  // ---- outputs
  int outputs = 0;
  for (final row in d.relayOutputRows) {
    final output = c.text(row['output']);
    final numberText = c.text(row['number']);
    final used = [row['type'], row['output'], row['number'], row['time']].any((v) => c.text(v).isNotEmpty);
    if (!used) continue;
    outputs++;
    final label = c.text(row['serialNumber']);
    final what = '$page ${label.isEmpty ? 'output' : label}';
    final index = c.labelNumber(label, 'OD');
    if (index == null || index < 1 || index > maxOutputs) {
      c.errors.add('$what: outputs are OD-01 .. OD-$maxOutputs');
    }
    final n = c.number(numberText, 0, 255, '$what number');
    c.number(row['time'], 0, 65535, '$what time');
    if (output.isEmpty && numberText.isNotEmpty) {
      c.warnings.add('$what has a number but no function');
    } else if (output.isNotEmpty && numberText.isEmpty) {
      c.warnings.add('$what has a function but no number');
    }
    if (output.isNotEmpty || numberText.isNotEmpty) {
      final type = c.text(row['type']);
      c.known(type, PanelCombinedTH.outputKindMap, type, what, 'type (RLY / DIM)', '00');
    }
    if (output.isNotEmpty) {
      c.known(output, PanelCombinedTH.outputFunctionMap, output, what, 'function', 'LAMP (00)');
      c.deviceRange(output, n, what);
    }
  }
  if (outputs > maxOutputs) c.errors.add('$page: $outputs outputs (at most $maxOutputs)');

  // ---- inputs
  int inputs = 0;
  for (final row in d.inputAssignRows) {
    final fields = ['type', 'inputState', 'outputDevice', 'deviceNo', 'outputState', 'time', 'defaultState'];
    if (!fields.any((k) => c.text(row[k]).isNotEmpty)) continue;
    inputs++;
    final label = c.text(row['sr']);
    final what = '$page ${label.isEmpty ? 'input' : label}';
    final index = c.labelNumber(label, 'IP');
    if (index == null || index < 1 || index > maxInputs) {
      c.errors.add('$what: inputs are IP-01 .. IP-0$maxInputs');
    }
    final n = c.number(row['deviceNo'], 0, 255, '$what device no');
    c.number(row['time'], 0, 65535, '$what time');
    c.state(row['outputState'], '$what output state');
    c.state(row['defaultState'], '$what default state');
    final type = c.text(row['type']);
    c.known(type, InMainTH.typeMap, type, what, 'type', '00 00');
    final inputState = c.text(row['inputState']);
    if (inputState.isNotEmpty) c.known(inputState, InMainTH.inputStateMap, inputState, what, 'input state', 'LOW (00)');
    final device = c.text(row['outputDevice']);
    c.known(device, InMainTH.actionMap, device, what, 'output device', '00 (no action)');
    c.deviceRange(device, n, what);
  }
  if (inputs > maxInputs) c.errors.add('$page: $inputs inputs (at most $maxInputs)');

  // ---- scenes
  final sceneRows = <String, int>{};
  for (final row in d.sceneAssignRows) {
    final used = ['output', 'number', 'state', 'temp'].any((k) => c.text(row[k]).isNotEmpty);
    if (!used) continue;
    final scene = c.text(row['type']).isEmpty ? 'Scene' : c.text(row['type']);
    sceneRows[scene] = (sceneRows[scene] ?? 0) + 1;
    final label = c.text(row['sr_no']);
    final what = '$scene ${label.isEmpty ? 'row' : label}';
    final index = c.labelNumber(label, 'OD');
    if (index == null || index < 1 || index > maxSceneRows) {
      c.errors.add('$what: scene rows are OD-01 .. OD-$maxSceneRows');
    }
    c.number(row['number'], 0, 255, '$what number');
    final temp = c.number(row['temp'], 0, 255, '$what temp');
    c.state(row['state'], '$what state');
    final outputValue = c.text(row['output']);
    c.known(outputValue, SceneTH.sceneTypeMap, SceneTH.typeKeyOf(outputValue), what, 'output', 'LAMP (00)');
    final output = outputValue.toUpperCase();
    if (output.startsWith('THERMOSTAT') && temp != null && temp != 0 && (temp < 16 || temp > 32)) {
      c.warnings.add('$what: thermostat set point $temp - the panel uses 16..32 (0 = keep)');
    }
    if (output.startsWith('FAN') && levelOf(c.text(row['state'])) > 4) {
      c.warnings.add('$what: fan speed ${levelOf(c.text(row['state']))} - fans have speeds 1..4');
    }
  }
  sceneRows.forEach((scene, rows) {
    if (rows > maxSceneRows) c.errors.add('$scene: $rows rows (at most $maxSceneRows)');
  });

  // ---- connectivity: network page, strings, DP map
  if (d.connectivityType != 1 || (d.wifiMode ?? '').trim().isEmpty) {
    c.warnings.add('No network page: the panel will run without WiFi and BLE Mesh');
  } else {
    final mqtt = d.wifiMode == 'Mqtt-HA';
    c.field(d.mqttBroker, BMSInfoTH.brokerMax, 'MQTT broker address');
    c.field(d.mqttUser, BMSInfoTH.userMax, 'MQTT user name');
    c.field(d.mqttPassword, BMSInfoTH.passwordMax, 'MQTT password');
    if (mqtt) {
      final port = c.text(d.mqttPort);
      if (port.isNotEmpty && (!RegExp(r'^\d{1,5}$').hasMatch(port) || int.parse(port) < 1 || int.parse(port) > 65535)) {
        c.errors.add('MQTT port = "$port" (allowed 1..65535)');
      }
      if (c.text(d.mqttBroker).isEmpty) {
        c.warnings.add('No MQTT broker: set it on the WiFi set-up page of the panel');
      }
    } else {
      c.field(d.tuyaPid, BMSInfoTH.pidMax, 'Tuya PID');
    }

    final devices = mqtt ? d.mqttDevices : d.tuyaDevices;
    final seen = <String>{};
    int dpRows = 0;
    for (final row in devices) {
      final parameter = c.text(row['parameter']);
      final devNo = c.text(row['deviceNo']);
      final dpId = c.text(row['dpId']);
      if (parameter.isEmpty && devNo.isEmpty && dpId.isEmpty) continue;
      dpRows++;
      final what = 'DP row $dpRows${parameter.isEmpty ? '' : ' ($parameter)'}';
      if (devNo.isEmpty || dpId.isEmpty) {
        c.warnings.add('$what: without a device no and a DP id the row is left out');
        continue;
      }
      c.known(parameter, WIFIConnTH.devTypeMap, parameter.toUpperCase(), what, 'parameter', 'LAMP (00)');
      final n = c.number(devNo, 0, 255, '$what device no');
      final id = c.number(dpId, 0, 65535, '$what DP id');
      if (id != null && (id < 1 || id > 255)) {
        c.warnings.add('$what: DP id $id - the panel uses ids 1..255 (one byte; 0 is ignored)');
      }
      if (n != null && !seen.add('${parameter.toUpperCase()}/$n')) {
        c.warnings.add('$what: $parameter $n is listed twice - the panel uses the first');
      }
    }
    if (dpRows > maxDpRows) c.errors.add('DP map: $dpRows rows (at most $maxDpRows)');
  }

  // ---- last: the converters themselves, on the TXT this configuration writes
  if (c.errors.isEmpty) {
    try {
      ConvertManager.hexLinesOfTxt(buildTxt(d).split('\n'), boardType: d.boardType);
    } on ConfigRangeError catch (e) {
      c.errors.add(e.message);
    }
  }

  configErrors
    ..clear()
    ..addAll(c.errors);
  configWarnings
    ..clear()
    ..addAll(c.warnings);
  return c.errors.isEmpty;
}
