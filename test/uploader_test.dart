/*
 * =============================================================================
 *  uploader_test.dart  -  Touchmatik Glide 1.1.0 (Agragamee, Oct-2026)
 *  The BLE upload protocol (config_uploader.dart, V0.6.0 contract C-4)
 *  against the fake panel (test/support/fake_panel.dart): design 5.4 cases
 *  F1..F12, plus the reply parsers and the app log (app_log.dart), and the
 *  review_glide cases after the EOF line (fix_glide: Cancel ignored once the
 *  EOF is out; a failure after it is "maybe stored", never retried by itself).
 *  Timeouts are injected (50..300 ms), so the whole file runs in seconds.
 * =============================================================================
 */
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:progswitches/comporotocol/config_uploader.dart';
import 'package:progswitches/services/app_log.dart';
import 'package:progswitches/services/hex_file_check.dart';

import 'support/fake_panel.dart';

// an Intel HEX record with its checksum, upper case
String rec(int address, List<int> data, [int type = 0]) {
  final bytes = [data.length, address >> 8, address & 0xFF, type, ...data];
  final sum = bytes.fold<int>(0, (s, b) => s + b);
  final all = [...bytes, (-sum) & 0xFF];
  return ':${all.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
}

List<int> sixteen(List<int> head) => [...head, ...List<int>.filled(16 - head.length, 0)];

// a panel-5 BLE Mesh program of 11 data records + EOF = 12 lines
HexCheck panel5File() {
  final lines = <String>[
    rec(0x0000, sixteen([5, 0, 0, 1])), // header: panel 5, STANDALONE
    rec(0x1400, sixteen([0x01, 0x00, 0x01, 0x50, 0x07, 0x00, 0x01, 0x50])), // keys 1..4
    rec(0x1410, sixteen([0x08, 0x00, 0x01, 0x50])), // keys 5..8
    rec(0x1450, sixteen([0x11, 0x00, 0x01, 0x00, 0, 0, 0, 0, 0x11, 0x00, 0x02, 0x00])), // outputs 1, 2
    rec(0x1460, sixteen([0x22, 0x00, 0x01, 0x00])), // output 3
    rec(0x4200, sixteen([0x0D, 0x11, 0xFF, 0x00, 0x01])), // input 1 of panel 5
    rec(0x6000, sixteen([0x01, 0x00, 0xFF, 0x00])), // scene 1
    rec(0x6040, sixteen([0x02, 0x00, 0x00, 0x00])), // scene 2
    rec(0x7400, sixteen([0x33, 0x00, 0x05])), // network page line 0: BLE Mesh
    rec(0x7410, sixteen([])), // network page line 1 (zeros)
    rec(0x74A0, sixteen([0x01, 0x00, 0x01, 0x51])), // DP map
    ':00000001FF',
  ];
  return HexCheck.ofText(lines.join('\n'), name: 'panel_05.hex');
}

const String kipl = 'KIPL-2M-79C846';
final List<int> verWrite = utf8.encode('<#VER>\n');

// counts the onProgress calls of one upload
int progressCalls = 0;
void onProgress() => progressCalls++;

void main() {
  setUp(() {
    upLineTimeout = const Duration(milliseconds: 200);
    upEofTimeout = const Duration(milliseconds: 300);
    upProbeTimeout = const Duration(milliseconds: 100);
    upInfoGrace = const Duration(milliseconds: 50);
    upRetryPause = const Duration(milliseconds: 20);
    upAutoRetries = 1;
    progressCalls = 0;
    appLogClear();
  });

  test('the test file is a valid panel-5 program', () {
    final f = panel5File();
    expect(f.ok, isTrue, reason: f.error);
    expect(f.lines.length, 12);
    expect(f.records, 11);
    expect(f.headerPanel, 5);
    expect(f.pagePanels, {5});
  });

  test('F1 maxWrite 244, KIPL name: <#VER>, then one 46-byte write per record and 14 bytes for EOF', () async {
    final file = panel5File();
    final panel = FakePanel(maxWrite: 244, name: kipl);
    final ok = await uploadFile(file, panel.connect, onProgress);
    expect(ok, isTrue, reason: upError);
    expect(panel.writes.first, verWrite);
    final records = panel.writes.sublist(1);
    expect(records.length, file.lines.length);
    for (var i = 0; i < file.lines.length - 1; i++) {
      expect(records[i].length, 46);
      expect(utf8.decode(records[i]), '<${file.lines[i]}>\n');
      expect(utf8.decode(records[i]), startsWith('<:10'));
    }
    expect(utf8.decode(records.last), '<:00000001FF>\n');
    expect(records.last.length, 14);
    expect(panel.storedCrc, file.crc);
    expect(progressCalls, greaterThan(file.lines.length));
  });

  test('F2 maxWrite 20: 3 writes per record, 1 for EOF; replies truncated to 20 B still parse', () async {
    final file = panel5File();
    final panel = FakePanel(maxWrite: 20, name: kipl);
    final ok = await uploadFile(file, panel.connect, onProgress);
    expect(ok, isTrue, reason: upError);
    expect(panel.writes.first, verWrite);
    final records = panel.writes.sublist(1);
    expect(records.length, 3 * (file.lines.length - 1) + 1);
    expect(records.map((w) => w.length).toSet(), {20, 6, 14});
    expect(panel.storedCrc, file.crc); // the same program as F1
    expect(panel.notifications.every((n) => n.length <= 20), isTrue);
    expect(panel.notifications, contains('VER 0.6.0'));
    expect(panel.notifications, contains('INFO crc=${file.crcHex}')); // the short form
    expect(upFirmware, '0.6.0');
    expect(upInfo, {'crc': file.crcHex});
    expect(upVerified, isTrue);
  });

  test('F3 v2 success: firmware, INFO, verified', () async {
    final file = panel5File();
    final panel = FakePanel(name: kipl);
    final ok = await uploadFile(file, panel.connect, onProgress);
    expect(ok, isTrue, reason: upError);
    expect(upFirmware, '0.6.0');
    expect(upInfo['panel'], '5');
    expect(upInfo['hdr'], '1');
    expect(upInfo['records'], '11');
    expect(upInfo['keys'], '3');
    expect(upInfo['outputs'], '3');
    expect(upInfo['mode'], 'mesh');
    expect(upInfo['mesh'], 'none');
    expect(upVerified, isTrue);
    expect(upPhase, 'done');
    expect(upSent, upTotal);
    expect(upTotal, 12);
    expect(upAttempt, 1);
    expect(upError, '');
    expect(panel.uploads.single.result, 'stored');
    expect(panel.closeCalls, 1); // closed after success too
  });

  test('F4 ERR 5 checksum: fails at once, record 5, one attempt, no write after it, closed', () async {
    final file = panel5File();
    final panel = FakePanel(name: kipl, failAtLine: 5, failToken: 'checksum');
    final ok = await uploadFile(file, panel.connect, onProgress);
    final returned = DateTime.now();
    expect(ok, isFalse);
    expect(returned.difference(panel.lastErrAt!).inMilliseconds, lessThan(100));
    expect(upError, 'checksum');
    expect(upErrorRecord, 5);
    expect(file.fileLine[upErrorRecord - 1], 5);
    expect(upAttempt, 1);
    expect(upPhase, 'failed');
    expect(panel.recordLines.length, 5);
    expect(panel.writes.length, 1 + 5); // #VER and records 1..5
    expect(utf8.decode(panel.writes.last), '<${file.lines[4]}>\n');
    expect(panel.closeCalls, 1);
    expect(panel.uploads.single.result, 'abandoned');
    expect(retryAllowed(upError), isFalse);
    expect(upMaybeStored, isFalse); // an ERR: the panel abandoned the upload
  });

  test('F5 answer lost at record 7 on attempt 1: closed, attempt 2 succeeds', () async {
    final file = panel5File();
    final panel = FakePanel(name: kipl, dropAnswerAt: 7, dropAnswerTimes: 1);
    final ok = await uploadFile(file, panel.connect, onProgress);
    expect(ok, isTrue, reason: upError);
    expect(upAttempt, 2);
    expect(upVerified, isTrue);
    expect(panel.connects, 2);
    expect(panel.closeCalls, 2);
    expect(panel.uploads.length, 2);
    expect(panel.uploads[0].result, 'abandoned');
    expect(panel.uploads[0].lines, 7);
    expect(panel.uploads[1].result, 'stored');
    expect(panel.storedCrc, file.crc);
  });

  test('F6 link dropped at record 3 on both attempts: false after 2 attempts, link', () async {
    final file = panel5File();
    final panel = FakePanel(name: kipl, disconnectAt: 3);
    final watch = Stopwatch()..start();
    final ok = await uploadFile(file, panel.connect, onProgress);
    expect(ok, isFalse);
    expect(upError, 'link');
    expect(upErrorRecord, 3);
    expect(upAttempt, 2);
    expect(panel.connects, 2);
    expect(panel.uploads.map((u) => u.result), ['abandoned', 'abandoned']);
    // a dropped link is noticed at once, not after the line timeout
    expect(watch.elapsed, lessThan(upLineTimeout * 2));
    expect(retryAllowed(upError), isTrue);
    expect(upMaybeStored, isFalse); // dropped before the EOF line: nothing can have been stored
  });

  group('F7 refused before openLink', () {
    for (final c in [
      ['empty file', '', 'empty'],
      ['no EOF', '${rec(0x0000, sixteen([1]))}\n${rec(0x1000, sixteen([1]))}\n', 'no-eof'],
      ['1.0.0 junk config.hex', '00000000', 'start'],
    ]) {
      test(c[0], () async {
        var opened = 0;
        Future<PanelLink> openLink() async {
          opened++;
          return FakePanel().connect();
        }

        final ok = await uploadFile(HexCheck.ofText(c[1]), openLink, onProgress);
        expect(ok, isFalse);
        expect(opened, 0);
        expect(upError, c[2]);
        expect(upAttempt, 0);
        expect(upPhase, 'failed');
        expect(retryAllowed(upError), isFalse);
      });
    }
  });

  test('F8 legacyAck, v1Mode, non-KIPL name: stored, not verified, no #VER', () async {
    final file = panel5File();
    final panel = FakePanel(name: 'ESP32-V3', v1Mode: true, legacyAck: true);
    final ok = await uploadFile(file, panel.connect, onProgress);
    expect(ok, isTrue, reason: upError);
    expect(upVerified, isFalse);
    expect(upFirmware, '');
    expect(upInfo, isEmpty);
    expect(panel.writes.any((w) => utf8.decode(w).contains('#VER')), isFalse);
    expect(utf8.decode(panel.writes.first), '<${file.lines.first}>\n');
    expect(panel.notifications.toSet(), {'ACK'});
    expect(panel.storedCrc, file.crc);
  });

  test('F8b v1 panel with a KIPL name: the probe goes unanswered, upload as v1', () async {
    final file = panel5File();
    final panel = FakePanel(name: kipl, v1Mode: true);
    final ok = await uploadFile(file, panel.connect, onProgress);
    expect(ok, isTrue, reason: upError);
    expect(panel.writes.first, verWrite);
    expect(upFirmware, '');
    expect(upVerified, isFalse);
  });

  test('F9 wrong CRC in INFO: false, crc, not retried', () async {
    final panel = FakePanel(name: kipl, wrongCrc: true);
    final ok = await uploadFile(panel5File(), panel.connect, onProgress);
    expect(ok, isFalse);
    expect(upError, 'crc');
    expect(upVerified, isFalse);
    expect(upAttempt, 1);
    expect(panel.connects, 1);
    // the panel answered the EOF: it HAS stored (a different program), not "maybe"
    expect(panel.uploads.single.result, 'stored');
    expect(upMaybeStored, isFalse);
    expect(upInfo['crc'], isNot(panel5File().crcHex));
  });

  // review_glide findings 1 and 2: once the EOF line has gone out the panel
  // may already have stored the file, so the app must neither cancel then nor
  // report "unchanged" / retry by itself when the answer does not come.
  group('after the EOF line (review_glide)', () {
    test('Cancel when the EOF line reaches the panel is ignored: stored and verified', () async {
      final file = panel5File();
      final panel = FakePanel(name: kipl, answerDelay: const Duration(milliseconds: 30), onLine: (n) {
        if (n == 12) cancelUpload(); // the EOF line (the reviewer's scratch test)
      });
      final ok = await uploadFile(file, panel.connect, onProgress);
      expect(ok, isTrue, reason: upError);
      expect(upError, '');
      expect(upVerified, isTrue);
      expect(upCancel, isFalse);
      expect(panel.uploads.single.result, 'stored');
      expect(appLogLines().join('\n'), contains('cancel ignored'));
    });

    test('Cancel one line before the EOF still cancels: nothing stored', () async {
      final panel = FakePanel(name: kipl, onLine: (n) {
        if (n == 11) cancelUpload();
      });
      final ok = await uploadFile(panel5File(), panel.connect, onProgress);
      expect(ok, isFalse);
      expect(upError, 'cancelled');
      expect(upErrorRecord, 11);
      expect(upMaybeStored, isFalse);
      expect(panel.recordLines.length, 11); // the EOF line never went out
      expect(panel.uploads.single.result, 'abandoned');
    });

    test('the link drops right after the store: link, maybe stored, no automatic retry', () async {
      final panel = FakePanel(name: kipl, dropLinkAtStore: true);
      final ok = await uploadFile(panel5File(), panel.connect, onProgress);
      expect(ok, isFalse);
      expect(upError, 'link');
      expect(upErrorRecord, 12);
      expect(upMaybeStored, isTrue);
      expect(upAttempt, 1);
      expect(panel.connects, 1, reason: 'the file must not be sent again by itself');
      expect(panel.uploads.single.result, 'stored');
      expect(retryAllowed(upError), isTrue); // by hand, after the dialog says what may have happened
      expect(appLogLines().join('\n'), contains('the panel may have stored the file'));
    });

    test('no answer at all to the EOF (v1 panel): no-answer, maybe stored, no automatic retry', () async {
      final panel = FakePanel(name: 'ESP32-V3', v1Mode: true, dropAnswerAt: 12, dropAnswerTimes: -1);
      final ok = await uploadFile(panel5File(), panel.connect, onProgress);
      expect(ok, isFalse);
      expect(upError, 'no-answer');
      expect(upMaybeStored, isTrue);
      expect(upAttempt, 1);
      expect(panel.connects, 1);
      expect(panel.uploads.single.result, 'stored');
    });

    test('the final OK is lost but INFO came: stored and verified, one attempt', () async {
      final file = panel5File();
      final panel = FakePanel(name: kipl, dropAnswerAt: 12, dropAnswerTimes: 1);
      final ok = await uploadFile(file, panel.connect, onProgress);
      expect(ok, isTrue, reason: upError);
      expect(upVerified, isTrue);
      expect(upAttempt, 1);
      expect(panel.connects, 1);
      expect(upSent, upTotal);
    });

    test('an ERR to the EOF is a refusal: the program is unchanged, not maybe stored', () async {
      upAutoRetries = 0;
      final panel = FakePanel(name: kipl, failAtLine: 12, failToken: 'nvs');
      final ok = await uploadFile(panel5File(), panel.connect, onProgress);
      expect(ok, isFalse);
      expect(upError, 'nvs');
      expect(upErrorRecord, 12);
      expect(upMaybeStored, isFalse);
      expect(panel.uploads.single.result, 'abandoned');
    });
  });

  test('F10 three uploads in a row: at most one reply subscription, none at the end', () async {
    final file = panel5File();
    final panel = FakePanel(name: kipl);
    for (var k = 0; k < 3; k++) {
      final ok = await uploadFile(file, panel.connect, onProgress);
      expect(ok, isTrue, reason: upError);
      expect(panel.subscriptionCount, lessThanOrEqualTo(1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(panel.maxSubscriptions, 1);
    expect(panel.subscriptionCount, 0);
    expect(panel.uploads.length, 3);
  });

  test('F11 cancel at record 4: closed at once, no further writes, cancelled', () async {
    final file = panel5File();
    late FakePanel panel;
    panel = FakePanel(name: kipl, onLine: (n) {
      if (n == 4) cancelUpload();
    });
    final ok = await uploadFile(file, panel.connect, onProgress);
    expect(ok, isFalse);
    expect(upError, 'cancelled');
    expect(upErrorRecord, 4);
    expect(upAttempt, 1);
    expect(panel.closeCalls, 1);
    expect(panel.recordLines.length, 4);
    expect(panel.writes.length, 1 + 4);
    expect(panel.uploads.single.result, 'abandoned');
  });

  for (final ms in [50, 0]) {
    test('F12 the panel disconnects $ms ms after the final OK: success', () async {
      final file = panel5File();
      final panel = FakePanel(name: kipl, dropAfterStored: Duration(milliseconds: ms));
      final ok = await uploadFile(file, panel.connect, onProgress);
      expect(ok, isTrue, reason: upError);
      expect(upVerified, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(upPhase, 'done');
      expect(panel.isConnected, isFalse);
      expect(panel.uploads.single.result, 'stored');
    });
  }

  group('retry rules', () {
    test('a transient panel error (ERR n nvs at the EOF) gets one automatic retry', () async {
      final file = panel5File();
      final panel = FakePanel(name: kipl, failAtLine: 12, failToken: 'nvs', failTimes: 1);
      final ok = await uploadFile(file, panel.connect, onProgress);
      expect(ok, isTrue, reason: upError);
      expect(upAttempt, 2);
      expect(panel.uploads.map((u) => u.result), ['abandoned', 'stored']);
    });

    test('busy is not retried automatically, but may be retried by hand', () async {
      final panel = FakePanel(name: kipl, failAtLine: 1, failToken: 'busy');
      final ok = await uploadFile(panel5File(), panel.connect, onProgress);
      expect(ok, isFalse);
      expect(upError, 'busy');
      expect(upAttempt, 1);
      expect(retryAllowed('busy'), isTrue);
    });

    test('silence on every line: no-answer after two attempts', () async {
      final panel = FakePanel(name: kipl, dropAnswerAt: 2, dropAnswerTimes: -1);
      final ok = await uploadFile(panel5File(), panel.connect, onProgress);
      expect(ok, isFalse);
      expect(upError, 'no-answer');
      expect(upErrorRecord, 2);
      expect(upAttempt, 2);
      expect(panel.closeCalls, 2);
    });

    test('a panel outside its window (LinkError not-in-window) is not retried', () async {
      var opened = 0;
      Future<PanelLink> openLink() async {
        opened++;
        throw LinkError('not-in-window', 'service not found');
      }

      final ok = await uploadFile(panel5File(), openLink, onProgress);
      expect(ok, isFalse);
      expect(upError, 'link');
      expect(upLinkError, 'not-in-window');
      expect(upLinkDetail, 'service not found');
      expect(upErrorRecord, 0);
      expect(opened, 1);
    });

    test('a connect that fails once is retried', () async {
      final panel = FakePanel(name: kipl);
      var opened = 0;
      Future<PanelLink> openLink() async {
        opened++;
        if (opened == 1) throw LinkError('connect', 'GATT 133');
        return panel.connect();
      }

      final ok = await uploadFile(panel5File(), openLink, onProgress);
      expect(ok, isTrue, reason: upError);
      expect(opened, 2);
      expect(upAttempt, 2);
    });

    test('no automatic retry when upAutoRetries = 0', () async {
      upAutoRetries = 0;
      final panel = FakePanel(name: kipl, disconnectAt: 3);
      final ok = await uploadFile(panel5File(), panel.connect, onProgress);
      expect(ok, isFalse);
      expect(upAttempt, 1);
      expect(panel.connects, 1);
    });
  });

  group('the fake panel follows the firmware line rules', () {
    test('a refused record from the panel itself (bad checksum sent anyway) ends the upload', () async {
      // a file the pre-flight would refuse, pushed past it to see the panel's answer
      final good = panel5File();
      final lines = List<String>.of(good.lines);
      lines[2] = '${lines[2].substring(0, lines[2].length - 2)}00';
      final forced = HexCheck(
        name: 'forced.hex',
        lines: lines,
        fileLine: good.fileLine,
        records: good.records,
        crc: good.crc,
        hasHeader: true,
        headerPanel: 5,
        board: 1,
        pagePanels: good.pagePanels,
        networkPanels: good.networkPanels,
        error: '',
        errorRecord: 0,
        errorLine: 0,
        warnings: const [],
      );
      final panel = FakePanel(name: kipl);
      final ok = await uploadFile(forced, panel.connect, onProgress);
      expect(ok, isFalse);
      expect(upError, 'checksum');
      expect(upErrorRecord, 3);
      expect(upAttempt, 1);
    });

    test('#INFO, #CLOSE and an unknown command', () async {
      final panel = FakePanel(name: kipl);
      expect(await uploadFile(panel5File(), panel.connect, onProgress), isTrue);
      final link = await panel.connect();
      expect(await panelCommand(link, '#INFO', const Duration(milliseconds: 100)), startsWith('INFO panel=5 hdr=1'));
      expect(await panelCommand(link, '#XYZ', const Duration(milliseconds: 100)), 'ERR 0 command');
      expect(await panelCommand(link, '#CLOSE', const Duration(milliseconds: 100)), 'OK');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(link.isUp, isFalse);
    });

    test('a cancelled upload does not mute the probe of the next connect', () async {
      final panel = FakePanel(name: kipl, onLine: (n) {
        if (n == 2) cancelUpload();
      });
      expect(await uploadFile(panel5File(), panel.connect, onProgress), isFalse);
      expect(upError, 'cancelled');
      expect(await probeFirmware(await panel.connect()), '0.6.0');
    });

    test('probeFirmware: 0.6.0 from a KIPL panel, nothing sent to another peripheral', () async {
      final kiplPanel = FakePanel(name: kipl);
      expect(await probeFirmware(await kiplPanel.connect()), '0.6.0');
      final other = FakePanel(name: 'HMSoft');
      expect(await probeFirmware(await other.connect()), '');
      expect(other.writes, isEmpty);
      expect(kiplPanel.subscriptionCount, 0);
    });
  });

  group('reply parsers', () {
    test('parseInfo keeps unknown keys, accepts missing ones', () {
      expect(parseInfo('INFO panel=1 hdr=1 records=22 crc=536812C0 keys=5 outputs=4 net=33 mode=mesh wifi=0 mesh=none'), {
        'panel': '1',
        'hdr': '1',
        'records': '22',
        'crc': '536812C0',
        'keys': '5',
        'outputs': '4',
        'net': '33',
        'mode': 'mesh',
        'wifi': '0',
        'mesh': 'none',
      });
      expect(parseInfo('INFO crc=4AB63DBF future=7'), {'crc': '4AB63DBF', 'future': '7'});
      expect(parseInfo('INFO none'), isEmpty);
    });

    test('errToken and errLine', () {
      expect(errToken('ERR 5 checksum'), 'checksum');
      expect(errLine('ERR 5 checksum', 9), 5);
      expect(errToken('ERR 0 command'), 'command');
      expect(errLine('ERR 0 command', 9), 9);
      expect(errToken('ERR 2048 ext-address'), 'ext-address');
      expect(errToken('ERR'), 'bad-reply');
    });

    test('token classes (design 3.5)', () {
      for (final t in ['link', 'no-answer', 'bad-reply', 'no-memory', 'nvs', 'timeout']) {
        expect(isTransient(t), isTrue, reason: t);
        expect(retryAllowed(t), isTrue, reason: t);
      }
      for (final t in ['start', 'char', 'length', 'checksum', 'bytes', 'type', 'ext-address', 'too-many', 'after-eof', 'too-long', 'empty', 'command']) {
        expect(isTransient(t), isFalse, reason: t);
        expect(retryAllowed(t), isFalse, reason: t);
      }
      for (final t in ['busy', 'crc', 'cancelled']) {
        expect(isTransient(t), isFalse, reason: t);
        expect(retryAllowed(t), isTrue, reason: t);
      }
      expect(upTokenText('checksum'), 'checksum error');
    });
  });

  group('app log (C15)', () {
    test('keeps the last 2000 lines with time stamps', () {
      for (var i = 0; i < 2100; i++) {
        appLog('line $i');
      }
      final lines = appLogLines();
      expect(lines.length, appLogMax);
      expect(lines.first, endsWith(' line 100'));
      expect(lines.last, endsWith(' line 2099'));
      expect(RegExp(r'^\d\d:\d\d:\d\d\.\d\d\d line 2099$').hasMatch(lines.last), isTrue);
    });

    test('a multi-line text becomes several lines; blank lines are skipped', () {
      appLog('a\n\nb\r\n');
      expect(appLogLines().map((l) => l.substring(13)), ['a', 'b']);
    });

    test('the uploader writes its steps to the log', () async {
      final panel = FakePanel(name: kipl, failAtLine: 5);
      await uploadFile(panel5File(), panel.connect, onProgress);
      final text = appLogLines().join('\n');
      expect(text, contains('panel firmware 0.6.0'));
      expect(text, contains('panel: ERR 5 checksum'));
      expect(text, contains('upload failed after 1 attempt(s): checksum at record 5, file line 5'));
    });

    test('saveAppLog writes glide_log_<yyyyMMdd_HHmmss>.txt', () async {
      appLog('hello');
      final dir = Directory('build/test_tmp/app_log');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      final when = DateTime(2026, 10, 15, 9, 5, 7);
      expect(appLogFileName(when), 'glide_log_20261015_090507.txt');
      final path = await saveAppLog(dir: dir.path, now: when);
      expect(path.replaceAll('\\', '/'), endsWith('build/test_tmp/app_log/glide_log_20261015_090507.txt'));
      final text = File(path).readAsStringSync();
      expect(text, startsWith(appLogHeader));
      expect(text, contains(' hello'));
    });
  });
}
