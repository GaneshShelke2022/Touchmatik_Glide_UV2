/*
 * =============================================================================
 *  hex_tools.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  Small helpers every converter uses: range-checked hex fields, the V3
 *  level names, the panel number of a TXT file and the 0x0000 header record.
 *
 *  Contract: V0.6.0 design C-5 (GUI HEX produced by Glide 1.1.0). A value
 *  that does not fit its field throws ConfigRangeError naming the page, row
 *  and field, so a bad configuration never becomes an odd-length record
 *  (the firmware's hex_record.c refuses those and the whole load fails).
 * =============================================================================
 */
import 'cal_checksum.dart';

class ConfigRangeError implements Exception {
  final String message;
  ConfigRangeError(this.message);
  @override
  String toString() => message;
}

// one byte as two upper-case hex digits, 0..255 or ConfigRangeError
String hexByte(int value, String what) {
  if (value < 0 || value > 255) {
    throw ConfigRangeError('$what = $value (allowed 0..255)');
  }
  return value.toRadixString(16).padLeft(2, '0').toUpperCase();
}

// one 16-bit word as [low byte, high byte] (the V3 words are little-endian), 0..65535
List<String> hexWord(int value, String what) {
  if (value < 0 || value > 0xFFFF) {
    throw ConfigRangeError('$what = $value (allowed 0..65535)');
  }
  return [hexByte(value & 0xFF, what), hexByte(value >> 8, what)];
}

String hexWordLo(int value, String what) => hexWord(value, what)[0];
String hexWordHi(int value, String what) => hexWord(value, what)[1];

// a text field as a number: '' -> 0, digits -> value, anything else -> ConfigRangeError
int numberOf(String text, String what) {
  final t = text.trim();
  if (t.isEmpty) return 0;
  final v = int.tryParse(t);
  if (v == null) throw ConfigRangeError('$what = "$t" is not a number');
  return v;
}

// a text field as one hex byte ('' -> '00')
String hexByteOf(String text, String what) => hexByte(numberOf(text, what), what);

// a text field as one little-endian word ('' -> ['00', '00'])
List<String> hexWordOf(String text, String what) => hexWord(numberOf(text, what), what);

// 'ON-L-1', 'ON-L-01', 'on_l1', 'ON_L10' -> 1..10, else 0
int levelOf(String text) {
  final m = RegExp(r'^ON[-_ ]?L[-_ ]?0*([1-9]|10)$').firstMatch(text.trim().toUpperCase());
  return m == null ? 0 : int.parse(m.group(1)!);
}

// V3 output / scene state: ON FF, OFF 00, TOGGLE 11, ON-L-n = n
String stateByte(String text, String what) {
  final t = text.trim().toUpperCase();
  if (t.isEmpty || t == 'OFF') return '00';
  if (t == 'ON') return 'FF';
  if (t == 'TOGGLE') return '11';
  final level = levelOf(t);
  if (level == 0) throw ConfigRangeError('$what = "$text" is not ON / OFF / TOGGLE / ON-L-1..10');
  return hexByte(level, what);
}

// printable ASCII 0x20..0x7E without the double quote (the firmware's field ends at '"')
bool isFieldText(String text) => text.codeUnits.every((c) => c >= 0x20 && c <= 0x7E && c != 0x22);

// a network-page string field (net_gui.c): '"text"' as ASCII hex, zero padded to [bytes] bytes.
// [maxChars] is the longest text that still leaves room for both quotes.
String quotedFieldHex(String text, int bytes, int maxChars, String what) {
  if (text.length > maxChars) {
    throw ConfigRangeError('$what has ${text.length} characters (at most $maxChars)');
  }
  if (!isFieldText(text)) {
    throw ConfigRangeError('$what = "$text": only printable ASCII without a double quote is allowed');
  }
  final quoted = '"$text"';
  final hex = quoted.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
  return hex.padRight(bytes * 2, '0');
}

// 'Panel-05' (or 'panel_5', '5') -> 5; null when it is not a panel 1..48
int? panelNumberOf(String? label) {
  if (label == null) return null;
  final m = RegExp(r'(\d{1,2})\s*$').firstMatch(label.trim());
  if (m == null) return null;
  final n = int.parse(m.group(1)!);
  return (n >= 1 && n <= 48) ? n : null;
}

// 5 -> 'Panel-05'
String panelLabel(int panel) => 'Panel-${panel.toString().padLeft(2, '0')}';

// the panel a TXT describes: <Panel-NN>, else <WiFiInfo-NN>, else <InputAssign-NN>, else 1
int txtPanelNumber(List<String> lines) {
  return txtPanelTag(lines) ?? 1;
}

// as txtPanelNumber, but null when no tag names a panel (the file then means panel 1)
int? txtPanelTag(List<String> lines) {
  for (final pattern in [r'^<Panel-(\d{1,2})>$', r'^<WiFiInfo-(\d{1,2})>$', r'^<InputAssign-(\d{1,2})>$']) {
    final tag = RegExp(pattern);
    for (final line in lines) {
      final m = tag.firstMatch(line.trim());
      if (m == null) continue;
      final n = int.parse(m.group(1)!);
      if (n >= 1 && n <= 48) return n;
    }
  }
  return null;
}

// header byte 3: 01 STANDALONE (the default), 02 RCU
int boardByteOf(String? boardType) => (boardType ?? '').trim().toUpperCase() == 'RCU' ? 2 : 1;

// 1 -> 'STANDALONE', 2 -> 'RCU'
String boardNameOf(int board) => board == 2 ? 'RCU' : 'STANDALONE';

// one 16-byte type-00 record at [address] from 16 hex bytes
String dataRecord(int address, List<String> data) {
  if (data.length != 16) {
    throw ArgumentError('a GUI record carries 16 data bytes, not ${data.length}');
  }
  final line = <String>[
    '10',
    hexByte(address >> 8, 'record address'),
    hexByte(address & 0xFF, 'record address'),
    '00',
    ...data,
    '00',
  ];
  line[20] = CalChecksum.checksum(line);
  return ':${line.join()}';
}

// the 0x0000 header record: [panel][00][00][board][12 x 00] (config_store.c:121-127)
String headerRecord(int panel, int board) {
  if (panel < 1 || panel > 48) {
    throw ConfigRangeError('panel number = $panel (allowed 1..48)');
  }
  if (board < 1 || board > 2) {
    throw ConfigRangeError('board type = $board (allowed 1 STANDALONE, 2 RCU)');
  }
  final data = List<String>.filled(16, '00');
  data[0] = hexByte(panel, 'panel number');
  data[3] = hexByte(board, 'board type');
  return dataRecord(0x0000, data);
}

// address 0000 and type 00, whatever the length byte
bool isHeaderRecord(String line) {
  final t = line.trim();
  return t.length >= 9 && t.startsWith(':') && t.substring(3, 9).toUpperCase() == '000000';
}
