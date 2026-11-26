/*
 * =============================================================================
 *  in_main_th.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  Inputs of every <InputAssign-NN> block -> 0x4000 + (NN - 1) * 0x80,
 *  32 bytes per input IP-01..IP-04:
 *    [0D|0A][11|22|33][FF|00|11][00][action][00][devNo][type][state][00]
 *    [time lo][time hi][default][00]
 *  All-zero records are left out (as in 1.0.0).
 *
 *  V1.1.0: every input block, at its own panel's address (B3; 1.0.0 wrote the
 *  first block at 0x4000 = panel 1 whatever its number); ON-L-1 / ON-L-01 /
 *  on_l1 levels (B4); DIMMER as an output device (B6); range-checked numbers
 *  and times (B7); errors are not swallowed (M4).
 * =============================================================================
 */
import 'package:flutter/foundation.dart';
import 'hex_tools.dart';

class InMainTH {
  static const Map<String, List<String>> typeMap = {
    "DIGITAL-LATCH": ["0D", "11"],
    "DIGITAL-PULSE": ["0D", "22"],
    "DIGITAL-INTLOCK": ["0D", "33"],
    "ANALOG": ["0A", "00"],
  };

  static const Map<String, String> inputStateMap = {"HIGH": "FF", "LOW": "00", "TOGGLE": "11"};

  static const Map<String, String> actionMap = {
    "LAMP": "01",
    "FAN-ON/OFF": "06",
    "CURTAIN-OPEN": "04",
    "CURTAIN-CLOSE": "05",
    "OCCUPANCY": "0C",
    "SCENE": "10",
    "DIMMER": "15", // V1.1.0 (B6)
  };

  static const Map<String, String> deviceTypeMap = {
    "LAMP": "00",
    "FAN-ON/OFF": "51",
    "CURTAIN-OPEN": "41",
    "CURTAIN-CLOSE": "42",
    "OCCUPANCY": "03",
    "SCENE": "81",
    "DIMMER": "61", // V1.1.0 (B6)
  };

  static final RegExp _blockStart = RegExp(r'^<Input(?:Assign)?(?:-(\d{1,2}))?>$');

  // the input records of every input block, in file order
  static List<String> records(List<String> content) {
    final out = <String>[];
    int i = 0;
    while (i < content.length) {
      final m = _blockStart.firstMatch(content[i].trim());
      if (m == null) {
        i++;
        continue;
      }
      final tag = content[i].trim();
      int? end;
      for (int j = i + 1; j < content.length; j++) {
        if (content[j].trim().startsWith('</Input')) {
          end = j;
          break;
        }
      }
      if (end == null) {
        debugPrint('in_main_th: no closing tag for $tag');
        break;
      }
      // V1.1.0: a tagged block uses its own number, a legacy untagged block the file's panel
      final panel = m.group(1) != null ? int.parse(m.group(1)!) : txtPanelNumber(content);
      if (panel < 1 || panel > 48) {
        debugPrint('in_main_th: skipping $tag - not panel 1..48');
      } else {
        out.addAll(_blockRecords(content, i, end, panel, tag.substring(1, tag.length - 1)));
      }
      i = end + 1;
    }
    return out;
  }

  // V1.1.0: panel N's inputs at 0x4000 + (N-1) * 0x80 (TV13 GUI_program.c:119, config_store.c:163)
  static List<String> _blockRecords(List<String> content, int start, int end, int panel, String blockName) {
    final base = 0x4000 + (panel - 1) * 0x80;
    final data = List.generate(8, (_) => List<String>.filled(16, '00'));

    for (int i = start + 1; i < end; i++) {
      final row = content[i];
      if (row.trim().isEmpty) continue;
      final parts = row.split(',').map((p) => p.trim()).toList();
      if (parts.length < 8) continue;

      final device = parts[0];
      final m = RegExp(r'^IP-(\d\d)$').firstMatch(device);
      final input = m == null ? 0 : int.parse(m.group(1)!);
      if (input < 1 || input > 4) {
        if (device.isNotEmpty) debugPrint('in_main_th: $blockName: skipping input "$device"');
        continue;
      }
      final what = '$blockName $device';
      final typeData = typeMap[parts[1]] ?? const ["00", "00"];
      final action = parts[3];
      final time = hexWordOf(parts[6], '$what time');
      final bytes = [
        typeData[0],
        typeData[1],
        inputStateMap[parts[2]] ?? "00",
        "00",
        actionMap[action] ?? "00",
        "00",
        hexByteOf(parts[4], '$what device no'),
        deviceTypeMap[action] ?? "00",
        stateByte(parts[5], '$what output state'),
        "00",
        time[0],
        time[1],
        stateByte(parts[7], '$what default state'),
        "00",
      ];
      final offset = (input - 1) * 32;            // 14 bytes used, then 18 bytes of zeros
      data[offset ~/ 16].setRange(0, bytes.length, bytes);
    }

    final out = <String>[];
    for (int r = 0; r < data.length; r++) {
      if (data[r].every((b) => b == '00')) continue;
      out.add(dataRecord(base + r * 0x10, data[r]));
    }
    return out;
  }
}
