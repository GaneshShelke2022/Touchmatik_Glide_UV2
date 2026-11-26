/*
 * =============================================================================
 *  scene_th.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  Scenes 1..16 (<Welcome>, <NoOccupancy>, <Scene-03> .. <Scene-16>) ->
 *  0x6000 + j * 0x40, 4 bytes per entry OD-01..OD-16:
 *    [number][type][state FF|00|01..0A][temp]
 *  The panel_N column is not part of the V3 format and is dropped (as in 1.0.0).
 *  All-zero records are left out (as in 1.0.0).
 *
 *  V1.1.0: on_l1..on_l10 / ON-L-1 / ON-L-01 levels (B4; 1.0.0 wrote 00 = OFF
 *  for the values the scene page stores); numbers and temperatures are
 *  range-checked (B7); errors are not swallowed (M4).
 * =============================================================================
 */
import 'hex_tools.dart';

class SceneTH {
  static const List<String> sceneTags = [
    'Welcome', 'NoOccupancy', 'Scene-03', 'Scene-04',
    'Scene-05', 'Scene-06', 'Scene-07', 'Scene-08',
    'Scene-09', 'Scene-10', 'Scene-11', 'Scene-12',
    'Scene-13', 'Scene-14', 'Scene-15', 'Scene-16',
  ];

  // scene output (upper case, '_' and blanks as '-') -> device type byte
  static const Map<String, String> sceneTypeMap = {
    'LAMP': '00',
    'FAN': '51',
    'FAN-ON/OFF': '51',
    'CURTAIN': '41',
    'CURTAIN-OPEN': '41',
    'CURTAIN-CLOSE': '42',
    'DIMMER': '61',
    'DIMMER-OPEN': '41',   // the scene page's 'dimmer_open' (shown as CURTAIN-OPEN, M6)
    'DIMMER-CLOSE': '42',  // the scene page's 'dimmer_close' (shown as CURTAIN-CLOSE, M6)
    'THERMOSTAT': '71',
  };

  // the sceneTypeMap key of a scene output: upper case, '_' and blanks as '-'
  // ('dimmer_open' -> 'DIMMER-OPEN'); checkConfig looks values up the same way
  static String typeKeyOf(String output) => output.trim().toUpperCase().replaceAll(RegExp(r'[_\s]+'), '-');

  // the scene records, scene 1..16 in order
  static List<String> records(List<String> content) {
    final out = <String>[];
    for (int j = 0; j < 16; j++) {
      int start = -1;
      int end = -1;
      for (int i = 0; i < content.length; i++) {
        final row = content[i].trim();
        if (row == '<${sceneTags[j]}>') {
          start = i;
        } else if (row == '</${sceneTags[j]}>') {
          end = i;
        }
      }
      if (start < 0 || end < 0) continue;

      final data = List.generate(4, (_) => List<String>.filled(16, '00'));
      for (int lineIdx = start + 1; lineIdx < end; lineIdx++) {
        final parts = content[lineIdx].split(',').map((e) => e.trim()).toList();
        if (parts.isEmpty || parts[0].isEmpty) continue;
        if (parts[0].startsWith("Panel No")) {
          parts.removeAt(0);
        }
        if (parts.length < 4) continue;

        final device = parts[0];
        final m = RegExp(r'^OD-(\d\d)$').firstMatch(device);
        final entry = m == null ? 0 : int.parse(m.group(1)!);
        if (entry < 1 || entry > 16) continue;

        final what = '${sceneTags[j]} $device';
        final typeKey = typeKeyOf(parts[1]);
        final bytes = [
          hexByteOf(parts[2], '$what number'),
          sceneTypeMap[typeKey] ?? '00',
          stateByte(parts[3], '$what state'),
          hexByteOf(parts.length > 4 ? parts[4] : '', '$what temp'),
        ];
        final offset = (entry - 1) * 4;
        data[offset ~/ 16].setRange(offset % 16, offset % 16 + 4, bytes);
      }

      final base = 0x6000 + j * 0x40;
      for (int r = 0; r < data.length; r++) {
        if (data[r].every((b) => b == '00')) continue;
        out.add(dataRecord(base + r * 0x10, data[r]));
      }
    }
    return out;
  }
}
