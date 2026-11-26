/*
 * =============================================================================
 *  panel_th.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  Keys and outputs of every <Panel-NN> block -> page 0x10 + (NN - 1):
 *    0x00-0x4F  4 bytes per key     [action][00|01 STATUS][number][type]
 *    0x50-0xCF  8 bytes per output  [11 RLY|22 DIM][00][number][function][time lo][time hi][00][00]
 *  All-zero records are left out (as in 1.0.0).
 *
 *  V1.1.0: THERMOSTAT-VALV (the UI's stored value) -> 0x74 (B5); numbers and
 *  times are range-checked and a bad value throws ConfigRangeError instead of
 *  writing a 3-digit field or a wrapped time (B7); errors are no longer
 *  swallowed (M4).
 * =============================================================================
 */
import 'package:flutter/foundation.dart';
import 'hex_tools.dart';

class PanelCombinedTH {
  // key functions -> [action, 00 | 01 for *-STATUS]
  static const Map<String, List<String>> keyActionMap = {
    "LAMP": ["01", "00"],
    "BELL": ["03", "00"],
    "FAN-ON/OFF": ["06", "00"],
    "FAN-UP": ["07", "00"],
    "FAN-DOWN": ["08", "00"],
    "CURTAIN-OPEN": ["04", "00"],
    "CURTAIN-CLOSE": ["05", "00"],
    "DIMMER-ON/OFF": ["15", "00"],
    "DIMMER-UP": ["09", "00"],
    "DIMMER-DOWN": ["0A", "00"],
    "DIMMER-RLOVR": ["0B", "00"],
    "MASTER": ["02", "00"],
    "OCCUPANCY": ["0C", "00"],
    "DND": ["0D", "00"],
    "MMR": ["0E", "00"],
    "LAUNDRY": ["0F", "00"],
    "SCENE": ["10", "00"],
    "SCENE-OFF": ["17", "00"],
    "SCENE OFF": ["17", "00"],
    "SCENE-TOGGLE": ["18", "00"],
    "SCENE TOGGLE": ["18", "00"],
    "THERMOSTAT-ON/OFF": ["11", "00"],
    "THERMOSTAT-FAN": ["12", "00"],
    "THERMOSTAT-T-UP": ["13", "00"],
    "THERMOSTAT-T-DN": ["14", "00"],
    "THERMOSTAT-MODE": ["16", "00"],
    "DND-STATUS": ["0D", "01"],
    "MMR-STATUS": ["0E", "01"],
    "LAUNDRY-STATUS": ["0F", "01"],
    "OCCUPANCY-STATUS": ["0C", "01"],
  };

  // key functions -> device type byte
  static const Map<String, String> keyTypeMap = {
    "LAMP": "00",
    "BELL": "03",
    "FAN-ON/OFF": "51",
    "FAN-UP": "52",
    "FAN-DOWN": "52",
    "CURTAIN-OPEN": "41",
    "CURTAIN-CLOSE": "42",
    "DIMMER-ON/OFF": "61",
    "DIMMER-UP": "62",
    "DIMMER-DOWN": "62",
    "DIMMER-RLOVR": "62",
    "MASTER": "02",
    "OCCUPANCY": "03",
    "DND": "04",
    "MMR": "05",
    "LAUNDRY": "06",
    "SCENE": "81",
    "SCENE-OFF": "81",
    "SCENE OFF": "81",
    "SCENE-TOGGLE": "81",
    "SCENE TOGGLE": "81",
    "THERMOSTAT-ON/OFF": "71",
    "THERMOSTAT-FAN": "72",
    "THERMOSTAT-T-UP": "73",
    "THERMOSTAT-T-DN": "73",
    "THERMOSTAT-MODE": "75",
    "DND-STATUS": "08",
    "MMR-STATUS": "09",
    "LAUNDRY-STATUS": "0A",
    "OCCUPANCY-STATUS": "07",
  };

  static const Map<String, String> outputKindMap = {"RLY": "11", "DIM": "22", "ANA": "33"};

  // output functions -> function byte
  static const Map<String, String> outputFunctionMap = {
    "LAMP": "00",
    "BELL": "01",
    "OCCUPANCY": "03",
    "FAN-BLDC": "50",
    "FAN-LOW": "51",
    "FAN-MID": "52",
    "FAN-HIGH": "53",
    "CURTAIN-OPEN": "41",
    "CURTAIN-CLOSE": "42",
    "THERMOSTAT-LOW": "71",
    "THERMOSTAT-MID": "72",
    "THERMOSTAT-HIGH": "73",
    "THERMOSTAT-VALVE": "74",
    "THERMOSTAT-VALV": "74", // V1.1.0 (B5): the value the output page stores
    "DIMMER": "61",
  };

  // the key and output records of every <Panel-NN> block, in file order
  static List<String> records(List<String> content) {
    final out = <String>[];
    int i = 0;
    while (i < content.length) {
      final row = content[i].trim();
      if (!row.startsWith('<Panel-') || row.startsWith('</') || !row.endsWith('>')) {
        i++;
        continue;
      }
      final panelName = row.substring(1, row.length - 1);
      int? panelEnd;
      for (int j = i + 1; j < content.length; j++) {
        if (content[j].trim() == '</$panelName>') {
          panelEnd = j;
          break;
        }
      }
      if (panelEnd == null) {
        debugPrint('panel_th: no closing tag for $panelName');
        i++;
        continue;
      }
      final m = RegExp(r'^Panel-(\d\d)$').firstMatch(panelName);
      final panel = m == null ? 0 : int.parse(m.group(1)!);
      if (panel < 1 || panel > 48) {
        debugPrint('panel_th: skipping $panelName - not Panel-01..Panel-48');
        i = panelEnd + 1;
        continue;
      }

      int? switchStart, switchEnd, outputStart, outputEnd;
      for (int k = i + 1; k < panelEnd; k++) {
        final line = content[k].trim();
        if (line == '<Switch>') {
          switchStart = k;
        } else if (line == '</Switch>') {
          switchEnd = k;
        } else if (line == '<Output>') {
          outputStart = k;
        } else if (line == '</Output>') {
          outputEnd = k;
        }
      }

      final base = 0x1000 + (panel - 1) * 0x100;
      if (switchStart != null && switchEnd != null) {
        out.addAll(_keyRecords(content, switchStart, switchEnd, base, panelName));
      }
      if (outputStart != null && outputEnd != null) {
        out.addAll(_outputRecords(content, outputStart, outputEnd, base + 0x50, panelName));
      }
      i = panelEnd + 1;
    }
    return out;
  }

  // 20 keys x 4 bytes = 5 records
  static List<String> _keyRecords(List<String> content, int start, int end, int base, String panelName) {
    final data = List.generate(5, (_) => List<String>.filled(16, '00'));
    for (int lineIndex = start + 1; lineIndex < end; lineIndex++) {
      final parts = content[lineIndex].trim().split(',');
      if (parts.length < 3) continue;

      final switchName = parts[0].trim();
      final action = parts[1].trim();
      final m = RegExp(r'^SW-(\d\d)$').firstMatch(switchName);
      final key = m == null ? 0 : int.parse(m.group(1)!);
      if (key < 1 || key > 20) {
        if (switchName.isNotEmpty) debugPrint('panel_th: $panelName: skipping key "$switchName"');
        continue;
      }

      final actionData = keyActionMap[action] ?? const ["00", "00"];
      final number = hexByteOf(parts[2], '$panelName $switchName number');
      final offset = (key - 1) * 4;
      data[offset ~/ 16].setRange(offset % 16, offset % 16 + 4,
          [actionData[0], actionData[1], number, keyTypeMap[action] ?? "00"]);
    }
    return _nonEmpty(data, base);
  }

  // 16 outputs x 8 bytes = 8 records
  static List<String> _outputRecords(List<String> content, int start, int end, int base, String panelName) {
    final data = List.generate(8, (_) => List<String>.filled(16, '00'));
    for (int lineIndex = start + 1; lineIndex < end; lineIndex++) {
      final row = content[lineIndex].trim();
      if (row.isEmpty) continue;
      final parts = row.split(',');
      if (parts.length < 5) continue;

      final device = parts[0].trim();
      final m = RegExp(r'^OD-(\d\d)$').firstMatch(device);
      final output = m == null ? 0 : int.parse(m.group(1)!);
      if (output < 1 || output > 16) {
        if (device.isNotEmpty) debugPrint('panel_th: $panelName: skipping output "$device"');
        continue;
      }

      final kind = outputKindMap[parts[1].trim()] ?? "00";
      final number = hexByteOf(parts[3], '$panelName $device number');
      final function = outputFunctionMap[parts[2].trim()] ?? "00";
      final time = hexWordOf(parts[4], '$panelName $device time');

      final offset = (output - 1) * 8;
      data[offset ~/ 16].setRange(offset % 16, offset % 16 + 6, [kind, "00", number, function, time[0], time[1]]);
    }
    return _nonEmpty(data, base);
  }

  // the records whose 16 data bytes are not all zero
  static List<String> _nonEmpty(List<List<String>> data, int base) {
    final out = <String>[];
    for (int r = 0; r < data.length; r++) {
      if (data[r].every((b) => b == '00')) continue;
      out.add(dataRecord(base + r * 0x10, data[r]));
    }
    return out;
  }
}
