/*
 * =============================================================================
 *  bms_info_th.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  The mqtt_array part of the network page of every <WiFiInfo-NN> block:
 *  page 0x70 + (NN - 1), offsets 0x00-0x9F, laid out as the firmware's
 *  net_gui.c reads it (TV13 extract_mqtt_info):
 *    line 0x00   [11 Mqtt-HA | 22 Tuya-wifi | 33 Tuya-BLE][00][NN]  (always written)
 *    0x10-0x4F   broker, quoted ASCII, <= 62 characters (words 8..39)
 *                or the Tuya PID, <= 30 characters (words 8..)
 *    0x50-0x5F   port, quoted digits 1..65535 (words 40..47)
 *    0x60-0x7F   user name, <= 30 characters (words 48..63)
 *    0x80-0x9F   password, <= 30 characters (words 64..79)
 *  Broker, user and password come from the <Connectivity> block and go into
 *  every network page. All-zero records other than line 0 are left out.
 *
 *  V1.1.0 (B8): brokers up to 62 characters (4 records; the last two stay
 *  zero, so omitted, for brokers up to 30 - byte-identical to 1.0.0); every
 *  string is checked (length, printable ASCII without '"') and a bad one
 *  throws ConfigRangeError instead of losing its closing quote; an empty
 *  value writes nothing; errors are not swallowed (M4).
 * =============================================================================
 */
import 'hex_tools.dart';

class BMSInfoTH {
  static const Map<String, String> clientTypeMap = {"MQTT-HA": "11", "TUYA-WIFI": "22", "TUYA-BLE": "33"};

  // field limits (net_gui.c / net_internal.h)
  static const int brokerMax = 62;
  static const int userMax = 30;
  static const int passwordMax = 30;
  static const int pidMax = 30;

  // the network-page records 0x00-0x9F of every <WiFiInfo-NN> block, panel 1..48 in order
  static List<String> records(List<String> content) {
    final out = <String>[];

    // ---- the <WiFiInfo-NN> blocks
    final blocks = <int, List<int>>{};
    for (int panelNum = 1; panelNum <= 48; panelNum++) {
      final tagStart = '<WiFiInfo-${panelNum.toString().padLeft(2, '0')}>';
      final tagEnd = '</WiFiInfo-${panelNum.toString().padLeft(2, '0')}>';
      int? wifiInfoStart, wifiInfoEnd;
      for (int i = 0; i < content.length; i++) {
        final r = content[i].trim();
        if (r == tagStart) wifiInfoStart = i;
        if (r == tagEnd) {
          wifiInfoEnd = i;
          break;
        }
      }
      if (wifiInfoStart != null && wifiInfoEnd != null) blocks[panelNum] = [wifiInfoStart, wifiInfoEnd];
    }
    if (blocks.isEmpty) return out;

    // ---- the global <Connectivity> values (outside the WiFiInfo blocks)
    String? brokerHex, usernameHex, passwordHex;
    int? globalStart, globalEnd;
    for (int i = 0; i < content.length; i++) {
      final r = content[i].trim();
      if (r == '<Connectivity>') {
        globalStart = i;
      } else if (r == '</Connectivity>') {
        globalEnd = i;
        break;
      }
    }
    if (globalStart != null && globalEnd != null) {
      for (int i = globalStart + 1; i < globalEnd; i++) {
        final parts = content[i].trim().split(',');
        if (parts.length < 2) continue;
        final key = parts[0].trim();
        final value = parts.sublist(1).join(',').trim();
        if (value.isEmpty) continue;
        switch (key) {
          case "MQTTBrokerAddress":
            brokerHex = quotedFieldHex(value, 64, brokerMax, 'MQTT broker address');
            break;
          case "UserName":
            usernameHex = quotedFieldHex(value, 32, userMax, 'MQTT user name');
            break;
          case "Password":
            passwordHex = quotedFieldHex(value, 32, passwordMax, 'MQTT password');
            break;
        }
      }
    }

    blocks.forEach((panelNum, range) {
      final wifiInfoStart = range[0];
      final wifiInfoEnd = range[1];
      final blockName = 'WiFiInfo-${panelNum.toString().padLeft(2, '0')}';

      // 10 records of 16 data bytes: 0x00 .. 0x90
      final lines = List.generate(10, (_) => List<String>.filled(16, '00'));
      void put(int firstLine, String hex) {
        for (int b = 0; b < hex.length ~/ 2; b++) {
          lines[firstLine + b ~/ 16][b % 16] = hex.substring(b * 2, b * 2 + 2);
        }
      }

      if (brokerHex != null) put(1, brokerHex);       // 0x10-0x4F
      if (usernameHex != null) put(6, usernameHex);   // 0x60-0x7F
      if (passwordHex != null) put(8, passwordHex);   // 0x80-0x9F

      int? wifiConfigStart, wifiConfigEnd;
      for (int i = wifiInfoStart; i <= wifiInfoEnd; i++) {
        final r = content[i].trim();
        if (r == '<WiFi-config>') wifiConfigStart = i;
        if (r == '</WiFi-config>') wifiConfigEnd = i;
      }
      if (wifiConfigStart != null && wifiConfigEnd != null) {
        for (int i = wifiConfigStart + 1; i < wifiConfigEnd; i++) {
          final parts = content[i].trim().split(',');
          if (parts.length < 2) continue;
          final key = parts[0].trim();
          final value = parts.sublist(1).join(',').trim();

          if (key == "Mode") {
            lines[0][0] = clientTypeMap[value.toUpperCase()] ?? "00";
            lines[0][1] = "00";
            lines[0][2] = hexByte(panelNum, 'panel number');
          } else if (key == "MQTTPort" && value.isNotEmpty) {
            final port = int.tryParse(value);
            if (port == null || port < 1 || port > 65535 || !RegExp(r'^\d{1,5}$').hasMatch(value)) {
              throw ConfigRangeError('$blockName MQTT port = "$value" (allowed 1..65535)');
            }
            put(5, quotedFieldHex(value, 16, 14, '$blockName MQTT port'));   // 0x50-0x5F
          } else if (key == "PID" && value.isNotEmpty) {
            put(1, quotedFieldHex(value, 32, pidMax, '$blockName Tuya PID'));   // 0x10-0x2F
            put(3, '0' * 64);                                                  // 0x30-0x4F: no broker tail
          }
        }
      }

      for (int r = 0; r < lines.length; r++) {
        if (r == 0 || !lines[r].every((b) => b == '00')) {
          out.add(dataRecord(((0x70 + panelNum - 1) << 8) + r * 0x10, lines[r]));
        }
      }
    });
    return out;
  }
}
