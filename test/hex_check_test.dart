/*
 * =============================================================================
 *  hex_check_test.dart  -  Touchmatik Glide 1.1.0 (Agragamee, Oct-2026)
 *  The pre-flight of a GUI HEX file (V0.6.0 C-5.3) and the program CRC the
 *  panel reports (C-5.4): design 5.4 cases U1..U4 and the CRC check value.
 * =============================================================================
 */
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:progswitches/services/hex_file_check.dart';

// an Intel HEX record with its checksum, upper case
String rec(int address, List<int> data, [int type = 0]) {
  final bytes = [data.length, address >> 8, address & 0xFF, type, ...data];
  final sum = bytes.fold<int>(0, (s, b) => s + b);
  final all = [...bytes, (-sum) & 0xFF];
  return ':${all.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
}

List<int> sixteen(List<int> head) => [...head, ...List<int>.filled(16 - head.length, 0)];

const String eof = ':00000001FF';

// a small panel-5 program: header, keys, outputs, a scene, network page, DP map
List<String> panel5Lines({int panel = 5, int board = 1, bool header = true}) => [
      if (header) rec(0x0000, sixteen([panel, 0, 0, board])),
      rec(0x1000 + (panel - 1) * 0x100, sixteen([0x01, 0x00, 0x01, 0x50, 0x07, 0x00, 0x01, 0x50])),
      rec(0x1050 + (panel - 1) * 0x100, sixteen([0x11, 0x00, 0x01, 0x00])),
      rec(0x6000, sixteen([0x01, 0x00, 0xFF, 0x00])),
      rec(0x7000 + (panel - 1) * 0x100, sixteen([0x33, 0x00, panel])),
      rec(0x70A0 + (panel - 1) * 0x100, sixteen([0x01, 0x00, 0x01, 0x51])),
      eof,
    ];

String fixture(String name) {
  // GA-1 keeps copies of the bench files in test/fixtures; the originals are
  // in SoftwareBuild\Tests\bench (two levels up from this package)
  for (final path in ['test/fixtures/$name', '../../Tests/bench/$name']) {
    final f = File(path);
    if (f.existsSync()) return f.readAsStringSync();
  }
  throw StateError('fixture $name not found');
}

void main() {
  group('CRC-32 (C-5.4)', () {
    test('check value crc32("123456789") = CBF43926', () {
      expect(crc32(ascii.encode('123456789')), 0xCBF43926);
      expect(crc32(const []), 0);
    });

    test('a CRC can be continued block by block', () {
      final all = ascii.encode('123456789');
      expect(crc32(all.sublist(4), crc32(all.sublist(0, 4))), 0xCBF43926);
    });
  });

  group('U1 bench files', () {
    test('bench_mesh.hex: 22 records, CRC 536812C0', () {
      final c = HexCheck.ofText(fixture('bench_mesh.hex'), name: 'bench_mesh.hex');
      expect(c.ok, isTrue, reason: c.error);
      expect(c.records, 22);
      expect(c.crcHex, '536812C0');
      expect(c.lines.length, 23); // EOF included
      expect(c.lines.last, eof);
      expect(c.hasHeader, isTrue);
      expect(c.headerPanel, 1);
      expect(c.boardName, 'STANDALONE');
      expect(c.pagePanels, {1});
      expect(c.warnings, isEmpty);
    });

    test('bench_mesh4.hex: 22 records, CRC 4AB63DBF', () {
      final c = HexCheck.ofText(fixture('bench_mesh4.hex'));
      expect(c.ok, isTrue, reason: c.error);
      expect(c.records, 22);
      expect(c.crc, 0x4AB63DBF);
    });

    test('ofFile reads the same file; a missing file is no-file', () async {
      final dir = Directory('build/test_tmp/hex_check')..createSync(recursive: true);
      final path = '${dir.path}/bench_mesh.hex';
      File(path).writeAsStringSync(fixture('bench_mesh.hex'));
      final c = await HexCheck.ofFile(path);
      expect(c.name, 'bench_mesh.hex');
      expect(c.crcHex, '536812C0');
      final missing = await HexCheck.ofFile('${dir.path}/nothing_here.hex');
      expect(missing.error, 'no-file');
    });
  });

  group('U2 one bad line per firmware token', () {
    // the bad line goes in as file line 3 (record 3)
    HexCheck withBadLine(String bad) {
      final good = panel5Lines();
      return HexCheck.ofText([good[0], good[1], bad, ...good.sublist(2)].join('\n'));
    }

    void expectRefused(HexCheck c, String token, int record, int line) {
      expect(c.ok, isFalse);
      expect(c.error, token);
      expect(c.errorRecord, record, reason: 'record');
      expect(c.errorLine, line, reason: 'file line');
    }

    test('start', () => expectRefused(withBadLine('X0000000000'), 'start', 3, 3));
    test('char', () => expectRefused(withBadLine(':10100000G1000150070001500000000000000000AA'), 'char', 3, 3));
    test('length (odd count)', () => expectRefused(withBadLine(':1010000001'), 'length', 3, 3));
    test('length (byte count differs from LL)', () {
      expectRefused(withBadLine(':0F10000001000150070001500000000000000000AA'), 'length', 3, 3);
    });
    test('checksum', () {
      final good = rec(0x1010, sixteen([0x02, 0x00, 0x01, 0x50]));
      final bad = '${good.substring(0, good.length - 2)}${good.endsWith('00') ? '01' : '00'}';
      expectRefused(withBadLine(bad), 'checksum', 3, 3);
    });
    test('type', () => expectRefused(withBadLine(rec(0x0000, const [], 0x06)), 'type', 3, 3));
    test('bytes (17 data bytes)', () => expectRefused(withBadLine(rec(0x1010, List<int>.filled(17, 1))), 'bytes', 3, 3));
    test('ext-address (upper address 0x1000, then a data record)', () {
      final lines = [rec(0x0000, const [0x10, 0x00], 0x04), ...panel5Lines()];
      expectRefused(HexCheck.ofText(lines.join('\n')), 'ext-address', 2, 2);
    });
    test('after-eof', () {
      final lines = [...panel5Lines(), rec(0x1010, sixteen([1]))];
      expectRefused(HexCheck.ofText(lines.join('\n')), 'after-eof', 8, 8);
    });
    test('too-many (2049 data records)', () {
      final lines = [for (var i = 0; i < 2049; i++) rec(0x6000 + (i % 0x400) * 0x10, sixteen([i & 0xFF])), eof];
      final ok2048 = HexCheck.ofText([...lines.sublist(0, 2048), eof].join('\n'));
      expect(ok2048.ok, isTrue, reason: ok2048.error);
      expect(ok2048.records, 2048);
      expectRefused(HexCheck.ofText(lines.join('\n')), 'too-many', 2049, 2049);
    });
    test('too-long (a line of 600 characters)', () {
      final long = ':${'0' * 599}';
      expect(long.length, 600);
      expectRefused(withBadLine(long), 'too-long', 3, 3);
      final short = withBadLine(':${'0' * 598}'); // 599 characters: parsed, then refused as length
      expect(short.error, 'length');
    });
    test('empty (EOF without a data record)', () => expectRefused(HexCheck.ofText(eof), 'empty', 1, 1));
  });

  group('file-level refusals and tolerances', () {
    test('an empty file and the 1.0.0 junk config.hex are refused', () {
      expect(HexCheck.ofText('').error, 'empty');
      expect(HexCheck.ofText('\n \n').error, 'empty');
      final junk = HexCheck.ofText('00000000');
      expect(junk.error, 'start');
      expect(junk.errorLine, 1);
      expect(junk.errorRecord, 0); // the panel would answer 'ERR 0 start'
    });

    test('no EOF record is no-eof', () {
      final c = HexCheck.ofText(panel5Lines().sublist(0, 6).join('\n'));
      expect(c.error, 'no-eof');
    });

    test('CRLF, blank lines, leading blanks and lower case are accepted; fileLine maps records', () {
      final good = panel5Lines();
      final text = '\r\n  ${good[0].toLowerCase()}\r\n\r\n\t${good.sublist(1).join('\r\n')}\r\n';
      final c = HexCheck.ofText(text);
      expect(c.ok, isTrue, reason: c.error);
      expect(c.lines.first, good[0].toLowerCase());
      expect(c.lines.length, good.length);
      expect(c.fileLine.sublist(0, 3), [2, 4, 5]);
      expect(c.crc, HexCheck.ofText(good.join('\n')).crc);
    });

    test('a byte-order mark at the start is skipped', () {
      final c = HexCheck.ofText(String.fromCharCode(0xFEFF) + panel5Lines().join('\n'));
      expect(c.ok, isTrue, reason: c.error);
      final latin = HexCheck.ofText(String.fromCharCodes(const [0xEF, 0xBB, 0xBF]) + panel5Lines().join('\n'));
      expect(latin.ok, isTrue, reason: latin.error);
    });

    test('text after a blank on a line is not sent (the panel ignores it too)', () {
      final c = HexCheck.ofText('${panel5Lines().join(' ; note\n')} ; note');
      expect(c.ok, isTrue, reason: c.error);
      expect(c.lines.every((l) => !l.contains(' ')), isTrue);
    });

    test('03 and 05 records are passed on; 02 with upper address 0 is fine', () {
      final lines = [rec(0x0000, const [0, 0], 0x02), rec(0x0000, const [0, 0, 0, 0], 0x03), ...panel5Lines()];
      final c = HexCheck.ofText(lines.join('\n'));
      expect(c.ok, isTrue, reason: c.error);
      expect(c.lines.length, 9);
      expect(c.records, 6);
    });
  });

  group('U3 header', () {
    test(':1000000005000002... = panel 5, RCU', () {
      final c = HexCheck.ofText(panel5Lines(board: 2).join('\n'));
      expect(c.lines.first.startsWith(':1000000005000002'), isTrue);
      expect(c.hasHeader, isTrue);
      expect(c.headerPanel, 5);
      expect(c.panel, 5);
      expect(c.board, 2);
      expect(c.boardName, 'RCU');
    });

    test('panel byte 00 means panel 1, board byte 00 STANDALONE (as the firmware)', () {
      final c = HexCheck.ofText([rec(0x0000, sixteen([0, 0, 0, 0])), ...panel5Lines(panel: 1, header: false)].join('\n'));
      expect(c.headerPanel, 1);
      expect(c.board, 1);
    });

    test('describe() is the dialog file line', () {
      final c = HexCheck.ofText(panel5Lines().join('\n'), name: 'panel_05.hex');
      expect(c.describe(), 'panel_05.hex, Panel-05, STANDALONE, 6 records, CRC ${c.crcHex}');
    });
  });

  group('U4 page panels and warnings', () {
    test('a panel-5 file has pagePanels {5} and no warning', () {
      final c = HexCheck.ofText(panel5Lines().join('\n'));
      expect(c.pagePanels, {5});
      expect(c.networkPanels, {5});
      expect(c.warnings, isEmpty);
    });

    test('G1 golden (when GA-1 has made it) has pagePanels {5}', () {
      final f = File('test/golden/p5_full.hex');
      if (!f.existsSync()) {
        markTestSkipped('test/golden/p5_full.hex not there yet (GA-1)');
        return;
      }
      final c = HexCheck.ofText(f.readAsStringSync());
      expect(c.ok, isTrue, reason: c.error);
      expect(c.pagePanels, {5});
    });

    test('header-less file: no-header warning', () {
      final c = HexCheck.ofText(panel5Lines(panel: 1, header: false).join('\n'));
      expect(c.ok, isTrue);
      expect(c.hasHeader, isFalse);
      expect(c.headerPanel, 0);
      expect(c.panel, 1);
      expect(c.warnings, ['no-header']);
      expect(c.warningTexts.single, contains('Panel-01'));
    });

    test('header panel 7 with pages for panel 5: header-not-in-pages, no-network-page', () {
      final lines = panel5Lines();
      lines[0] = rec(0x0000, sixteen([7, 0, 0, 1]));
      final c = HexCheck.ofText(lines.join('\n'));
      expect(c.warnings, ['header-not-in-pages', 'no-network-page']);
      expect(c.warningTexts.first, contains('Panel-07'));
      expect(c.warningTexts.first, contains('Panel-05'));
    });

    test('pages for two panels: several-panels', () {
      final lines = panel5Lines();
      lines.insert(1, rec(0x4000 + 2 * 0x80, sixteen([0x0D, 0x11]))); // inputs of panel 3
      final c = HexCheck.ofText(lines.join('\n'));
      expect(c.pagePanels, {3, 5});
      expect(c.warnings, ['several-panels']);
    });

    test('a Modbus-only program (no network page): no-network-page', () {
      final lines = panel5Lines()..removeWhere((l) => l.startsWith(':1074'));
      final c = HexCheck.ofText(lines.join('\n'));
      expect(c.warnings, ['no-network-page']);
    });
  });
}
