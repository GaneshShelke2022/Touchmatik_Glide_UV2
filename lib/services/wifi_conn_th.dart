/*
 * =============================================================================
 *  wifi_conn_th.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  The DP map (mqtt_parameter_array) of every <WiFiInfo-NN> block: page
 *  0x70 + (NN - 1), offsets 0xA0-0xFF, 4 bytes per <WiFi-parameter> row:
 *    [devNo][type][dpId lo][dpId hi]      at most 24 rows
 *  Despite its name this file only generates HEX; it talks to nothing.
 *  All-zero records are left out (as in 1.0.0).
 *
 *  V1.1.0: BELL is type 0x01 (M8; 1.0.0 wrote 0x03 = occupancy); device
 *  numbers and DP ids are range-checked, more than 24 rows is an error (B7);
 *  errors are not swallowed (M4).
 * =============================================================================
 */
import 'hex_tools.dart';

class WIFIConnTH {
  static const int maxPairs = 24;

  // DP parameter -> device type byte
  static const Map<String, String> devTypeMap = {
    'LAMP': '00',
    'BELL': '01', // V1.1.0 (M8): the V3 bell type
    'FAN-ON-OFF': '51',
    'FAN-SPEED': '52',
    'CURTAIN': '41',
    'DIMMER-ON-OFF': '61',
    'DIMMER-BRIGHTNESS': '62',
    'MASTER': '02',
    'OCCUPANCY': '03',
    'DND': '04',
    'MMR': '05',
    'LAUNDRY': '06',
    'SCENE': '81',
    'SCENE-OFF': '80',
    'SCENE-TOGGLE': '82',
    'THERMOSTAT-ON-OFF': '71',
    'THERMOSTAT-FAN': '72',
    'THERMOSTAT-STEMP': '73',
    'THERMOSTAT-ATEMP': '74',
    'THERMOSTAT-MODE': '75',
    'PANEL-BACKLIGHTMIN': '91',
    'DEVICE-RESTART': 'A1',
    'CHILD-LOCK': 'A2',
    'PROXY-SWITCH': 'A3',
    'FAN-REG-LOCK': '53',
    'INPUT-TW': 'B1',
  };

  // the DP-map records 0xA0-0xFF of every <WiFiInfo-NN> block, panel 1..48 in order
  static List<String> records(List<String> content) {
    final out = <String>[];
    for (int panelNum = 1; panelNum <= 48; panelNum++) {
      final blockName = 'WiFiInfo-${panelNum.toString().padLeft(2, '0')}';
      int? wifiInfoStart, wifiInfoEnd;
      for (int i = 0; i < content.length; i++) {
        if (content[i].trim() == '<$blockName>') wifiInfoStart = i;
        if (content[i].trim() == '</$blockName>') {
          wifiInfoEnd = i;
          break;
        }
      }
      if (wifiInfoStart == null || wifiInfoEnd == null) continue;

      int? wifiParamStart, wifiParamEnd;
      for (int i = wifiInfoStart; i <= wifiInfoEnd; i++) {
        if (content[i].trim() == '<WiFi-parameter>') wifiParamStart = i;
        if (content[i].trim() == '</WiFi-parameter>') {
          wifiParamEnd = i;
          break;
        }
      }
      if (wifiParamStart == null || wifiParamEnd == null) continue;

      // 6 records = 96 bytes = 24 pairs
      final data = List.generate(6, (_) => List<String>.filled(16, '00'));
      int pairs = 0;
      for (int i = wifiParamStart + 1; i < wifiParamEnd; i++) {
        final line = content[i].trim();
        if (line.isEmpty) continue;
        final parts = line.split(',');
        if (parts.length != 3) continue;
        final dev = parts[0].trim().toUpperCase();
        // a row without its device number or DP id is incomplete: skipped, as in 1.0.0
        if (parts[1].trim().isEmpty || parts[2].trim().isEmpty) continue;

        final what = '$blockName DP row ${pairs + 1} ($dev)';
        if (pairs >= maxPairs) {
          throw ConfigRangeError('$blockName DP map: more than $maxPairs rows');
        }
        final devNo = hexByteOf(parts[1], '$what device no');
        final dpId = hexWordOf(parts[2], '$what DP id');
        final offset = pairs * 4;
        data[offset ~/ 16].setRange(offset % 16, offset % 16 + 4, [devNo, devTypeMap[dev] ?? '00', dpId[0], dpId[1]]);
        pairs++;
      }

      for (int r = 0; r < data.length; r++) {
        if (data[r].every((b) => b == '00')) continue;
        out.add(dataRecord(((0x70 + panelNum - 1) << 8) + 0xA0 + r * 0x10, data[r]));
      }
    }
    return out;
  }
}
