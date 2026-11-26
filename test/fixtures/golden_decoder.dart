/*
 * =============================================================================
 *  golden_decoder.dart  -  Touchmatik Glide 1.1.0 tests (GA-1, Oct-2026)
 *  What the panel makes of a GUI HEX file, for the converter goldens:
 *    - decodeProgram(): a port of TPF01-ESP-PANEL config_store.c decode()
 *      (header pass, then the records of this panel's pages, later wins)
 *    - netField() / netPort(): net_gui.c's quoted string fields
 *    - programCrc(): cfg_program_crc (V0.6.0 C-5.4: CRC-32 / zlib over every
 *      type-00 record as 19 bytes [addr hi][addr lo][len][16 data, zero padded])
 *    - readExpect(): the <name>.expect files of test/golden (C-14)
 *  Not a test itself (no _test suffix); the *_test.dart files import it.
 * =============================================================================
 */

// one type-00 record of a file: address, length, 16 data bytes (zero padded)
class HexRecord {
  final int address;
  final int length;
  final List<int> data;
  HexRecord(this.address, this.length, this.data);
}

// the type-00 records of an Intel HEX text, checked line by line (throws FormatException)
List<HexRecord> dataRecords(String text) {
  final out = <HexRecord>[];
  var eof = false;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (eof) throw FormatException('data after the EOF record: $line');
    if (!line.startsWith(':') || line.length < 11 || line.length.isEven) {
      throw FormatException('not a HEX record: $line');
    }
    final bytes = <int>[];
    for (int i = 1; i < line.length; i += 2) {
      final b = int.tryParse(line.substring(i, i + 2), radix: 16);
      if (b == null) throw FormatException('not hex: $line');
      bytes.add(b);
    }
    if (bytes[0] + 5 != bytes.length) throw FormatException('length mismatch: $line');
    if (bytes.fold<int>(0, (s, b) => s + b) & 0xFF != 0) throw FormatException('checksum: $line');
    final type = bytes[3];
    if (type == 0x01) {
      eof = true;
    } else if (type == 0x00) {
      final data = List<int>.filled(16, 0);
      for (int i = 0; i < bytes[0] && i < 16; i++) {
        data[i] = bytes[4 + i];
      }
      out.add(HexRecord((bytes[1] << 8) | bytes[2], bytes[0], data));
    }
  }
  if (!eof) throw const FormatException('no EOF record');
  return out;
}

// the decoded program (config_store.h arrays) and the header values
class Program {
  final List<int> action = List<int>.filled(40, 0);
  final List<int> output = List<int>.filled(64, 0);
  final List<int> input = List<int>.filled(64, 0);
  final List<int> scene = List<int>.filled(512, 0);
  final List<int> mqtt = List<int>.filled(128, 0);
  final List<int> param = List<int>.filled(128, 0);
  int records = 0;
  int crc = 0;
  int headerPanel = 0;   // 0 = no header record
  int panel = 1;         // the page in use
  int board = 1;

  List<int> array(String name) {
    switch (name) {
      case 'action':
        return action;
      case 'output':
        return output;
      case 'input':
        return input;
      case 'scene':
        return scene;
      case 'mqtt':
        return mqtt;
      case 'param':
        return param;
    }
    throw ArgumentError('no array "$name"');
  }

  static const List<String> arrayNames = ['action', 'output', 'input', 'scene', 'mqtt', 'param'];
}

void _wordsFrom(List<int> words, int first, List<int> bytes) {
  for (int i = 0; i < 8; i++) {
    words[first + i] = bytes[2 * i] | (bytes[2 * i + 1] << 8);
  }
}

// zlib CRC-32 (reflected 0xEDB88320, init and xorout 0xFFFFFFFF)
int crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (int k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

// cfg_program_crc of a file
int programCrc(List<HexRecord> records) {
  final bytes = <int>[];
  for (final r in records) {
    bytes
      ..add(r.address >> 8)
      ..add(r.address & 0xFF)
      ..add(r.length)
      ..addAll(r.data);
  }
  return crc32(bytes);
}

// config_store.c decode(); [override] = the console's panel override (0 = none)
Program decodeProgram(String text, {int override = 0}) {
  final records = dataRecords(text);
  final p = Program()
    ..records = records.length
    ..crc = programCrc(records);
  for (final r in records) {
    if (r.address == 0x0000 && r.length >= 4) {
      p.headerPanel = r.data[0] != 0 ? r.data[0] : 1;
      p.board = r.data[3] != 0 ? r.data[3] : 1;
    }
  }
  p.panel = override != 0 ? override : (p.headerPanel != 0 ? p.headerPanel : 1);
  for (final r in records) {
    if (r.length != 16) continue;
    final page = r.address >> 8;
    final offset = r.address & 0xFF;
    if (r.address >= 0x1000 && r.address < 0x4000) {
      if (page != p.panel - 1 + 0x10) continue;
      if (offset < 0x50) {
        _wordsFrom(p.action, (offset >> 4) * 8, r.data);
      } else if (offset < 0xD0) {
        _wordsFrom(p.output, ((offset - 0x50) >> 4) * 8, r.data);
      }
    } else if (r.address >= 0x4000 && r.address < 0x5800) {
      final start = 0x4000 + (p.panel - 1) * 0x80;
      if (r.address >= start && r.address < start + 0x80) {
        _wordsFrom(p.input, ((r.address - start) >> 4) * 8, r.data);
      }
    } else if (r.address >= 0x6000 && r.address < 0x6400) {
      _wordsFrom(p.scene, ((r.address >> 4) & 0xFF) * 8, r.data);
    } else if (r.address >= 0x7000 && r.address < 0xA000) {
      if (page != p.panel - 1 + 0x70) continue;
      if (offset < 0xA0) {
        _wordsFrom(p.mqtt, (offset >> 4) * 8, r.data);
      } else if (offset < 0xFF) {
        _wordsFrom(p.param, ((offset - 0xA0) >> 4) * 8, r.data);
      }
    }
  }
  return p;
}

// net_gui.c net_gui_field(): the quoted string in words [first, end), '' when absent
String netField(List<int> words, int first, int end) {
  if ((words[first] & 0xFF) != 0x22) return '';
  final out = StringBuffer();
  var opening = true;
  for (int w = first; w < end; w++) {
    for (int half = 0; half < 2; half++) {
      final c = half == 0 ? words[w] & 0xFF : words[w] >> 8;
      if (opening) {
        opening = false;
        continue;
      }
      if (c == 0x22 || c == 0) return out.toString();
      if (c < 0x20 || c > 0x7E) continue;
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

// net_gui.c port_field(): 1..65535, else 0
int netPort(List<int> mqtt) {
  final text = netField(mqtt, 40, 48);
  if (text.isEmpty || text.length > 5 || !RegExp(r'^\d+$').hasMatch(text)) return 0;
  final port = int.parse(text);
  return port >= 1 && port <= 65535 ? port : 0;
}

// a test/golden/<name>.expect file
class Expect {
  int? records;
  int? crc;
  int? panel;
  int? board;
  String? broker;
  String? user;
  int? port;
  final Map<String, Map<int, int>> words = {for (final n in Program.arrayNames) n: <int, int>{}};
}

Expect readExpect(String text) {
  final e = Expect();
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('word ')) {
      final f = line.split(RegExp(r'\s+'));
      e.words[f[1]]![int.parse(f[2])] = int.parse(f[3], radix: 16);
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final key = line.substring(0, eq);
    final value = line.substring(eq + 1);
    switch (key) {
      case 'records':
        e.records = int.parse(value);
        break;
      case 'crc':
        e.crc = int.parse(value, radix: 16);
        break;
      case 'panel':
        e.panel = int.parse(value);
        break;
      case 'board':
        e.board = int.parse(value);
        break;
      case 'broker':
        e.broker = value;
        break;
      case 'user':
        e.user = value;
        break;
      case 'port':
        e.port = int.parse(value);
        break;
    }
  }
  return e;
}

// every difference between a decoded program and an .expect ('' lines = none);
// a word the .expect does not list must be 0
List<String> expectDiff(Program p, Expect e) {
  final diff = <String>[];
  void same(String what, Object? want, Object got) {
    if (want != null && want != got) diff.add('$what: expected $want, got $got');
  }

  same('records', e.records, p.records);
  same('crc', e.crc, p.crc);
  same('panel', e.panel, p.panel);
  same('board', e.board, p.board);
  same('broker', e.broker, netField(p.mqtt, 8, 40));
  same('user', e.user, netField(p.mqtt, 48, 64));
  same('port', e.port, netPort(p.mqtt));
  for (final name in Program.arrayNames) {
    final got = p.array(name);
    final want = e.words[name]!;
    for (int i = 0; i < got.length; i++) {
      final w = want[i] ?? 0;
      if (got[i] != w) {
        diff.add('word $name $i: expected ${hex4(w)}, got ${hex4(got[i])}');
      }
    }
  }
  return diff;
}

String hex4(int v) => v.toRadixString(16).toUpperCase().padLeft(4, '0');
String hex8(int v) => v.toRadixString(16).toUpperCase().padLeft(8, '0');
