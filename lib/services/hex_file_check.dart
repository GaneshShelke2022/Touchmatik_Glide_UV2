/*
 * =============================================================================
 *  hex_file_check.dart  -  Touchmatik Glide 1.1.0 (Agragamee, Oct-2026)
 *
 *  The pre-flight of a GUI HEX file before it goes to a panel (V0.6.0
 *  contract C-5.3) and the program CRC the panel reports back (C-5.4).
 *
 *  Every line is checked with the same rules, in the same order, as the
 *  firmware's hex_record_parse() and config_store_line(), so a file the panel
 *  would refuse is refused here, before connecting, with the panel's own
 *  ERR token and the record number the panel would have named:
 *      too-long, start, length, char, checksum, after-eof, ext-address,
 *      bytes, too-many, type, empty
 *  plus two of the app's own: no-eof (the file has no EOF record, the panel
 *  would wait for it until its 30 s idle limit) and no-file (unreadable).
 *
 *  Pure Dart (dart:io only): the tests run it on the Windows host.
 * =============================================================================
 */
import 'dart:convert';
import 'dart:io';

// ---- limits of the firmware (config_store.h, net_internal.h, hex_record.h)
const int hexMaxRecords = 2048; // CFG_MAX_RECORDS: data records per program
const int hexRecordData = 16; // CFG_RECORD_DATA: data bytes per record
const int hexLineMax = 600; // NET_CFGWIN_LINE_MAX: a line this long is refused
const int hexMaxLineBytes = 5 + hexRecordData; // C-5.3: at most 21 bytes per line
const int _parseBuffer = 4 + 255 + 1; // hex_record_parse() byte buffer (HEX_MAX_DATA 255)
const String _bomUtf8 = '\u{FEFF}'; // a byte-order mark, decoded as UTF-8
const String _bomLatin1 = '\u{EF}\u{BB}\u{BF}'; // the same three bytes, decoded as latin1

// ---- CRC-32 as zlib / esp_rom_crc32_le(0, ...): reflected 0xEDB88320,
//      init 0xFFFFFFFF, xorout 0xFFFFFFFF; crc32('123456789') = 0xCBF43926
final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// CRC-32 of [bytes]; pass the previous result as [crc] to continue a sum.
int crc32(List<int> bytes, [int crc = 0]) {
  var c = crc ^ 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// The result of checking one HEX file. [lines] are exactly the records the
/// uploader sends, one per panel line, the EOF record last.
class HexCheck {
  /// File name (no folder), for the dialog and the log.
  final String name;

  /// The ':' records to send, as found in the file without surrounding blanks.
  final List<String> lines;

  /// 1-based file line of each entry of [lines]: the panel's "ERR n" is
  /// record n, which is file line fileLine[n - 1].
  final List<int> fileLine;

  /// Type-00 (data) records.
  final int records;

  /// Program CRC (C-5.4) = the `crc` the panel reports in its INFO line.
  final int crc;

  /// True when the file has a 0x0000 header record (the last one counts, as
  /// in the firmware).
  final bool hasHeader;

  /// Panel number of the header (1..255; a 00 byte means panel 1); 0 = no header.
  final int headerPanel;

  /// Board byte of the header: 1 STANDALONE, 2 RCU; 1 when there is no header.
  final int board;

  /// Panels whose pages (keys/outputs 0x10.., inputs 0x4000.., network
  /// 0x70..) are in the file. Scenes and the header belong to no panel.
  final Set<int> pagePanels;

  /// Panels with a network page (0x70 + (P - 1)).
  final Set<int> networkPanels;

  /// '' = the file can be sent; else the refusal token (see the file header).
  final String error;

  /// Record number the panel would name in its ERR (0 = the file as a whole).
  final int errorRecord;

  /// 1-based file line of the refusal (0 = the file as a whole).
  final int errorLine;

  /// Warnings (C-5.3), as codes: no-header, header-not-in-pages,
  /// several-panels, no-network-page. The upload may go on after a Continue.
  final List<String> warnings;

  const HexCheck({
    required this.name,
    required this.lines,
    required this.fileLine,
    required this.records,
    required this.crc,
    required this.hasHeader,
    required this.headerPanel,
    required this.board,
    required this.pagePanels,
    required this.networkPanels,
    required this.error,
    required this.errorRecord,
    required this.errorLine,
    required this.warnings,
  });

  bool get ok => error.isEmpty;

  /// The panel number the panel will use: the header's, else 1.
  int get panel => hasHeader ? headerPanel : 1;

  /// The CRC as the panel prints it: 8 upper-case hex digits.
  String get crcHex => crc.toRadixString(16).toUpperCase().padLeft(8, '0');

  String get boardName => board == 2 ? 'RCU' : (board == 1 ? 'STANDALONE' : 'board $board');

  static String panelLabel(int panel) => 'Panel-${panel.toString().padLeft(2, '0')}';

  /// One line for the upload dialog:
  /// "panel_05.hex, Panel-05, STANDALONE, 37 records, CRC 1A2B3C4D"
  String describe() {
    final who = hasHeader ? '${panelLabel(headerPanel)}, $boardName' : 'no header (Panel-01 assumed)';
    return '$name, $who, $records records, CRC $crcHex';
  }

  /// The warnings as English sentences, in the order of [warnings].
  List<String> get warningTexts => warnings.map(_warningText).toList();

  String _warningText(String code) {
    final pages = (pagePanels.toList()..sort()).map(panelLabel).join(', ');
    switch (code) {
      case 'no-header':
        return 'The file has no panel header: the panel will assume Panel-01.';
      case 'header-not-in-pages':
        return 'The header says ${panelLabel(headerPanel)}, but the pages in the file are for $pages: '
            'the panel ignores them.';
      case 'several-panels':
        return 'The file has pages for several panels ($pages): '
            'the panel uses only those of ${panelLabel(panel)}.';
      case 'no-network-page':
        return 'No network page for ${panelLabel(panel)}: the panel runs without WiFi and BLE Mesh.';
      default:
        return code;
    }
  }

  /// Checks a HEX file on disk. An unreadable file gives error 'no-file'.
  static Future<HexCheck> ofFile(String path) async {
    final name = path.split(RegExp(r'[\\/]')).last;
    try {
      final bytes = await File(path).readAsBytes();
      // latin1 never throws, so a binary file is refused by the line rules
      return ofText(latin1.decode(bytes), name: name);
    } on FileSystemException {
      return _refused(name, 'no-file', 0, 0);
    }
  }

  static HexCheck _refused(String name, String token, int record, int line) => HexCheck(
        name: name,
        lines: const [],
        fileLine: const [],
        records: 0,
        crc: 0,
        hasHeader: false,
        headerPanel: 0,
        board: 1,
        pagePanels: const {},
        networkPanels: const {},
        error: token,
        errorRecord: record,
        errorLine: line,
        warnings: const [],
      );

  /// Checks the text of a HEX file (any line ends).
  static HexCheck ofText(String text, {String name = ''}) {
    final sent = <String>[];
    final fileLine = <int>[];
    final pagePanels = <int>{};
    final networkPanels = <int>{};
    final block = List<int>.filled(3 + hexRecordData, 0);
    var records = 0;
    var crc = 0;
    var eofSeen = false;
    var extended = 0;
    var hasHeader = false;
    var headerPanel = 0;
    var board = 1;
    var error = '';
    var errorRecord = 0;
    var errorLine = 0;

    if (text.startsWith(_bomUtf8) || text.startsWith(_bomLatin1)) {
      text = text.substring(text.startsWith(_bomUtf8) ? 1 : 3); // a byte-order mark
    }
    final rows = const LineSplitter().convert(text);
    for (var k = 0; k < rows.length && error.isEmpty; k++) {
      final token = _recordText(rows[k]);
      if (token.isEmpty) continue; // blank lines never reach the panel
      // the record number the panel would name (net_cfgwin.c line_index()):
      // the next line of an open upload; 1 for a ':' line that would open
      // one; 0 for anything else before the first record
      final n = sent.isNotEmpty ? sent.length + 1 : (token.startsWith(':') ? 1 : 0);

      final rec = _Record();
      var refusal = token.length >= hexLineMax ? 'too-long' : _parse(token, rec);
      if (refusal.isEmpty && eofSeen) refusal = 'after-eof';
      if (refusal.isEmpty) {
        switch (rec.type) {
          case 0x00:
            if (extended != 0) {
              refusal = 'ext-address';
            } else if (rec.length > hexRecordData) {
              refusal = 'bytes';
            } else if (records >= hexMaxRecords) {
              refusal = 'too-many';
            }
            break;
          case 0x01:
            if (rec.length > hexRecordData) refusal = 'length'; // C-5.3: at most 21 bytes
            break;
          case 0x02:
          case 0x04:
            if (rec.length != 2) {
              refusal = 'ext-address';
            } else {
              extended = (rec.data[0] << 8) | rec.data[1];
            }
            break;
          case 0x03:
          case 0x05:
            if (rec.length > hexRecordData) refusal = 'length'; // C-5.3: at most 21 bytes
            break;
          default:
            refusal = 'type';
        }
      }
      if (refusal.isNotEmpty) {
        error = refusal;
        errorRecord = n;
        errorLine = k + 1;
        break;
      }

      sent.add(token);
      fileLine.add(k + 1);
      if (rec.type == 0x01) {
        eofSeen = true;
        continue;
      }
      if (rec.type != 0x00) continue;

      // a data record: CRC block [addr hi][addr lo][len][16 data bytes, zero padded]
      records++;
      block.fillRange(0, block.length, 0);
      block[0] = rec.address >> 8;
      block[1] = rec.address & 0xFF;
      block[2] = rec.length;
      block.setRange(3, 3 + rec.length, rec.data);
      crc = crc32(block, crc);

      final a = rec.address;
      final page = a >> 8;
      if (a == 0x0000 && rec.length >= 4) {
        hasHeader = true; // config_store.c decode(): the last header wins
        headerPanel = rec.data[0] != 0 ? rec.data[0] : 1;
        board = rec.data[3] != 0 ? rec.data[3] : 1;
      } else if (a >= 0x1000 && a < 0x4000) {
        pagePanels.add(page - 0x10 + 1); // keys and outputs
      } else if (a >= 0x4000 && a < 0x5800) {
        pagePanels.add(((a - 0x4000) >> 7) + 1); // inputs, 0x80 per panel
      } else if (a >= 0x7000 && a < 0xA000) {
        pagePanels.add(page - 0x70 + 1); // network page and DP map
        networkPanels.add(page - 0x70 + 1);
      }
    }

    if (error.isEmpty) {
      if (sent.isEmpty) {
        error = 'empty'; // no record at all: an empty or blank file
      } else if (!eofSeen) {
        error = 'no-eof';
      } else if (records == 0) {
        error = 'empty'; // the panel answers "ERR n empty" at the EOF record
        errorRecord = sent.length;
        errorLine = fileLine.last;
      }
    }

    final warnings = <String>[];
    if (error.isEmpty) {
      final panel = hasHeader ? headerPanel : 1;
      if (!hasHeader) warnings.add('no-header');
      if (hasHeader && pagePanels.isNotEmpty && !pagePanels.contains(headerPanel)) {
        warnings.add('header-not-in-pages');
      }
      if (pagePanels.length > 1) warnings.add('several-panels');
      if (!networkPanels.contains(panel)) warnings.add('no-network-page');
    }

    return HexCheck(
      name: name,
      lines: List.unmodifiable(sent),
      fileLine: List.unmodifiable(fileLine),
      records: records,
      crc: crc,
      hasHeader: hasHeader,
      headerPanel: headerPanel,
      board: board,
      pagePanels: Set.unmodifiable(pagePanels),
      networkPanels: Set.unmodifiable(networkPanels),
      error: error,
      errorRecord: errorRecord,
      errorLine: errorLine,
      warnings: List.unmodifiable(warnings),
    );
  }
}

class _Record {
  int type = 0;
  int address = 0;
  int length = 0;
  List<int> data = const [];
}

// The record of a file line as hex_record_parse() sees it: leading blanks
// skipped, up to the first blank or the line end. Anything after a blank is
// ignored by the panel, so it is not sent either.
String _recordText(String row) {
  var start = 0;
  while (start < row.length && (row[start] == ' ' || row[start] == '\t')) {
    start++;
  }
  var end = start;
  while (end < row.length && row[end] != ' ' && row[end] != '\t' && row[end] != '\r' && row[end] != '\n') {
    end++;
  }
  return row.substring(start, end);
}

int _hexDigit(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30; // 0-9
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10; // A-F
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10; // a-f
  return -1;
}

// hex_record_parse() in Dart, same checks in the same order; '' = parsed.
// The firmware's buffer takes up to 260 bytes per line; C-5.3 then allows 21.
String _parse(String token, _Record out) {
  if (!token.startsWith(':')) return 'start';
  final chars = token.length - 1;
  if (chars < 10 || chars.isOdd) return 'length';
  final count = chars ~/ 2;
  if (count > _parseBuffer) return 'length';
  final bytes = List<int>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    final hi = _hexDigit(token.codeUnitAt(1 + i * 2));
    final lo = _hexDigit(token.codeUnitAt(2 + i * 2));
    if (hi < 0 || lo < 0) return 'char';
    bytes[i] = (hi << 4) | lo;
  }
  if (bytes[0] + 5 != count) return 'length';
  var sum = 0;
  for (final b in bytes) {
    sum = (sum + b) & 0xFF;
  }
  if (sum != 0) return 'checksum';
  out.length = bytes[0];
  out.address = (bytes[1] << 8) | bytes[2];
  out.type = bytes[3];
  out.data = bytes.sublist(4, 4 + bytes[0]);
  return '';
}
