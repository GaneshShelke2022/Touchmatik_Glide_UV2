/*
 * =============================================================================
 *  process_test.dart  -  Touchmatik Glide 1.1.0 tests (GA-1, Oct-2026)
 *  "Process" (ProcessConfig.generateModifiedHex), V0.6.0 design 5.4:
 *    G6  processing p5_full with Panel-05 / STANDALONE and then again with
 *        Panel-07 / RCU leaves exactly one 0x0000 record each time, first;
 *        the second header does not match the file's pages (mismatch flag)
 *  plus B1c (getNodeInfoFromHex reads panel and board) and hexPagePanels.
 * =============================================================================
 */
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:progswitches/services/hex_tools.dart';
import 'package:progswitches/services/process_config.dart';

import 'fixtures/golden_decoder.dart';

List<String> hexLines(String hex) => hex.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

void main() {
  final p5 = File('test/golden/p5_full.hex').readAsStringSync();
  final processor = ProcessConfig();

  String process(String hex, String panel, String board) => processor.generateModifiedHex(
        originalHexContent: hex,
        isBroadcast: false,
        panelText: panel,
        boardText: board,
      );

  test('G6: Process 05/STANDALONE, then 07/RCU: exactly one header line each time; mismatch for 07', () {
    final first = process(p5, 'Panel-05', 'STANDALONE');
    var lines = hexLines(first);
    expect(lines.where((l) => l.startsWith(':10000000')).length, 1);
    expect(lines.first, headerRecord(5, 1));
    expect(lines.sublist(1), hexLines(p5).sublist(1), reason: 'every other line kept, in order');
    expect(processPanelMismatch(first, 5), isFalse);
    expect(first.endsWith(':00000001FF\n'), isTrue);

    final second = process(first, 'Panel-07', 'RCU');
    lines = hexLines(second);
    expect(lines.where((l) => l.startsWith(':10000000')).length, 1);
    expect(lines.first, headerRecord(7, 2));
    expect(lines.sublist(1), hexLines(p5).sublist(1));
    expect(processPanelMismatch(second, 7), isTrue, reason: "the file's pages are for panel 5");
    expect(hexPagePanels(second), {5});

    // what the panel then does: with header 7 it ignores panel 5's pages (config_store.c)
    final decoded = decodeProgram(second);
    expect(decoded.panel, 7);
    expect(decoded.board, 2);
    expect(decoded.action.every((w) => w == 0), isTrue);
  });

  test('a header-less file (1.0.0 Generate) gets the header first; isBroadcast changes nothing', () {
    final body = hexLines(File('test/golden/p1_legacy.v100.hex').readAsStringSync()).sublist(1).join('\n');
    final out = processor.generateModifiedHex(
        originalHexContent: '$body\n', isBroadcast: true, panelText: 'Panel-01', boardText: 'STANDALONE');
    expect(out, File('test/golden/p1_legacy.v100.hex').readAsStringSync());
  });

  test('CRLF input and an unknown board text (STANDALONE is the default)', () {
    final out = process(p5.replaceAll('\n', '\r\n'), 'Panel-05', '');
    expect(out.contains('\r'), isFalse);
    expect(hexLines(out).first, headerRecord(5, 1));
  });

  test('a panel that is not 1..48 is refused', () {
    expect(() => process(p5, '', 'RCU'), throwsA(isA<ConfigRangeError>()));
    expect(() => process(p5, 'Panel-49', 'RCU'), throwsA(isA<ConfigRangeError>()));
  });

  test('B1c: getNodeInfoFromHex reads the panel byte and the board byte', () {
    expect(getNodeInfoFromHex(':1000000005000002000000000000000000000000E9\n:00000001FF\n'),
        {'nodeId': '5', 'boardType': 'RCU'});
    expect(getNodeInfoFromHex(p5), {'nodeId': '5', 'boardType': 'Stand Alone'});
    expect(getNodeInfoFromHex(':00000001FF\n'), {'nodeId': 'Not found', 'boardType': 'Not found'});
  });

  test('hexPagePanels: keys/outputs, inputs and network pages count; header and scenes do not', () {
    expect(hexPagePanels(p5), {5});
    expect(hexPagePanels(File('test/fixtures/bench_mesh4.hex').readAsStringSync()), {1});
    expect(hexPagePanels('${headerRecord(5, 1)}\n:106000000100FF0000000000000000000000000090\n'), isEmpty);
    expect(hexPagePanels('${dataRecord(0x4080, ['01', ...List.filled(15, '00')])}\n'), {2});
    expect(hexPagePanels('${dataRecord(0x7A00, ['33', ...List.filled(15, '00')])}\n'), {11});
    expect(processPanelMismatch(':106000000100FF0000000000000000000000000090\n', 9), isFalse,
        reason: 'no pages, nothing to ignore');
  });
}
