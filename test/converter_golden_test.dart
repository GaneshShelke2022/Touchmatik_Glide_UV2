/*
 * =============================================================================
 *  converter_golden_test.dart  -  Touchmatik Glide 1.1.0 tests (GA-1, Oct-2026)
 *  The TXT -> HEX converters against their goldens (V0.6.0 design 5.4):
 *    G0  a panel-1 file without the new features = Glide 1.0.0's output with
 *        the header first, byte for byte (golden made with the untouched
 *        1.0.0 converters)
 *    G1  p5_full.txt (panel 5, every fixed bug) = golden/p5_full.hex, and the
 *        panel's decoder gives every 'word' of p5_full.expect
 *    G2  bench_mesh4.txt decodes like the bench file bench_mesh4.hex
 *    G5  values that do not fit throw ConfigRangeError naming the field and
 *        leave no .hex and no .part
 *  plus the hex_tools helpers and checkConfig (design 3.3, 3.4), with the
 *  fix_glide checks for review_glide findings 5-7 (missing / unknown values,
 *  two-digit labels).
 *  Files are written to build/test_tmp only.
 * =============================================================================
 */
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:progswitches/data/app_data.dart';
import 'package:progswitches/services/config_check.dart';
import 'package:progswitches/services/convert_manager.dart';
import 'package:progswitches/services/hex_tools.dart';
import 'package:progswitches/services/txt_reader.dart';

import 'fixtures/golden_decoder.dart';

const String fixtures = 'test/fixtures';
const String golden = 'test/golden';

Directory tmpDir(String name) {
  final dir = Directory('build/test_tmp/converter_golden/$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir;
}

String fixture(String name) => File('$fixtures/$name').readAsStringSync();

// convert TXT text in a fresh folder; returns the HEX text
Future<String> convertText(String txt, String name, {String board = 'STANDALONE'}) async {
  final dir = tmpDir(name);
  final txtFile = File('${dir.path}/$name.txt')..writeAsStringSync(txt);
  final hexPath = await ConvertManager.convertTxtToHex(txtFile.path, boardType: board, outputDir: dir.path);
  return File(hexPath).readAsStringSync();
}

List<String> hexLines(String hex) => hex.split('\n').where((l) => l.isNotEmpty).toList();

void main() {
  group('hex_tools (design 3.4)', () {
    test('hexByte / hexWord / numberOf ranges', () {
      expect(hexByte(0, 'x'), '00');
      expect(hexByte(255, 'x'), 'FF');
      expect(() => hexByte(256, 'Panel-05 SW-02 number'),
          throwsA(isA<ConfigRangeError>().having((e) => e.message, 'message', 'Panel-05 SW-02 number = 256 (allowed 0..255)')));
      expect(() => hexByte(-1, 'x'), throwsA(isA<ConfigRangeError>()));
      expect(hexWord(65535, 'x'), ['FF', 'FF']);
      expect(hexWord(300, 'x'), ['2C', '01']);
      expect(() => hexWord(65536, 'OD-01 time'), throwsA(isA<ConfigRangeError>()));
      expect(numberOf('', 'x'), 0);
      expect(numberOf(' 42 ', 'x'), 42);
      expect(() => numberOf('abc', 'Welcome OD-01 temp'),
          throwsA(isA<ConfigRangeError>().having((e) => e.message, 'message', contains('Welcome OD-01 temp'))));
    });

    test('levelOf and stateByte accept every spelling of a level (B4)', () {
      for (final t in ['ON-L-1', 'ON-L-01', 'on_l1', 'ON_L1', 'on-l-1', 'ON L 1']) {
        expect(levelOf(t), 1, reason: t);
      }
      expect(levelOf('ON_L10'), 10);
      expect(levelOf('on_l10'), 10);
      expect(levelOf('ON-L-11'), 0);
      expect(levelOf('ON'), 0);
      expect(stateByte('on', 's'), 'FF');
      expect(stateByte('OFF', 's'), '00');
      expect(stateByte('', 's'), '00');
      expect(stateByte('TOGGLE', 's'), '11');
      expect(stateByte('on_l5', 's'), '05');
      expect(stateByte('ON-L-10', 's'), '0A');
      expect(() => stateByte('HALF', 'Welcome OD-01 state'), throwsA(isA<ConfigRangeError>()));
    });

    test('headerRecord / isHeaderRecord / boardByteOf', () {
      expect(headerRecord(1, 1), ':1000000001000001000000000000000000000000EE');
      expect(headerRecord(5, 2), ':1000000005000002000000000000000000000000E9');
      expect(() => headerRecord(0, 1), throwsA(isA<ConfigRangeError>()));
      expect(() => headerRecord(49, 1), throwsA(isA<ConfigRangeError>()));
      expect(isHeaderRecord(':1000000005000002000000000000000000000000E9'), isTrue);
      expect(isHeaderRecord(':0400000001000001FA'), isTrue);
      expect(isHeaderRecord(':10140000010001000600015115000261100003810F'), isFalse);
      expect(isHeaderRecord(':00000001FF'), isFalse);
      expect(boardByteOf('STANDALONE'), 1);
      expect(boardByteOf('rcu'), 2);
      expect(boardByteOf(null), 1);
    });

    test('txtPanelNumber: Panel, else WiFiInfo, else InputAssign, else 1', () {
      expect(txtPanelNumber(['<InputAssign-03>', '<WiFiInfo-02>', '<Panel-05>']), 5);
      expect(txtPanelNumber(['<InputAssign-03>', ' <WiFiInfo-02>']), 2);
      expect(txtPanelNumber(['<InputAssign-03>']), 3);
      expect(txtPanelNumber(['<Welcome>']), 1);
      expect(txtPanelNumber(['<Panel-49>', '<WiFiInfo-07>']), 7);
      expect(panelNumberOf('Panel-05'), 5);
      expect(panelNumberOf('panel_12'), 12);
      expect(panelNumberOf(null), isNull);
      expect(panelNumberOf('Panel-00'), isNull);
      expect(panelLabel(5), 'Panel-05');
    });

    test('quotedFieldHex: length and characters (B8)', () {
      expect(quotedFieldHex('1883', 16, 14, 'port'), '22313838332200000000000000000000');
      expect(quotedFieldHex('a' * 62, 64, 62, 'broker').length, 128);
      expect(() => quotedFieldHex('a' * 63, 64, 62, 'MQTT broker address'), throwsA(isA<ConfigRangeError>()));
      expect(() => quotedFieldHex('pa"ss', 32, 30, 'MQTT password'), throwsA(isA<ConfigRangeError>()));
      expect(() => quotedFieldHex('pässword', 32, 30, 'MQTT password'), throwsA(isA<ConfigRangeError>()));
    });
  });

  group('converters against the goldens (design 5.4)', () {
    test('G0: p1_legacy.txt = Glide 1.0.0 output with headerRecord(1,1) first, byte for byte', () async {
      final hex = await convertText(fixture('p1_legacy.txt'), 'p1_legacy');
      final want = File('$golden/p1_legacy.v100.hex').readAsStringSync();
      expect(hex, want);
      expect(hexLines(hex).first, headerRecord(1, 1));
    });

    test('G1: p5_full.txt = golden/p5_full.hex and decodes to every word of p5_full.expect', () async {
      final hex = await convertText(fixture('p5_full.txt'), 'p5_full');
      expect(hex, File('$golden/p5_full.hex').readAsStringSync());
      final program = decodeProgram(hex);
      final e = readExpect(File('$golden/p5_full.expect').readAsStringSync());
      expect(expectDiff(program, e), isEmpty);
      expect(e.records, 22);
      expect(program.panel, 5);
      // the fixed bugs, word by word
      expect(program.output[5], 0x7401, reason: 'B5 THERMOSTAT-VALV -> 74');
      expect(program.input[0], 0x110D, reason: 'B3 inputs of panel 5 at 0x4200');
      expect(program.input[3], 0x6102, reason: 'B6 DIMMER input -> action 15, type 61');
      expect(program.input[2], 0x0015);
      expect(program.input[4], 0x0003, reason: 'B4 ON-L-3');
      expect(program.input[20], 0x0011, reason: 'TOGGLE');
      expect(program.scene[3], 0x0005, reason: 'B4 on_l5');
      expect(program.param[4], 0x0102, reason: 'M8 BELL -> 01');
      expect(netField(program.mqtt, 8, 40), 'broker-01.keetronics-automation.example.co.in');
      expect(netField(program.mqtt, 64, 80), 'Pa,ss word#1');
      expect(netPort(program.mqtt), 8883);
    });

    test('the decoder CRC is the firmware CRC (C-5.4, C-14 golden table)', () {
      expect(hex8(crc32('123456789'.codeUnits)), 'CBF43926');
      final mesh = decodeProgram(File('$fixtures/bench_mesh.hex').readAsStringSync());
      expect([mesh.records, hex8(mesh.crc)], [22, '536812C0']);
      final mesh4 = decodeProgram(File('$fixtures/bench_mesh4.hex').readAsStringSync());
      expect([mesh4.records, hex8(mesh4.crc)], [22, '4AB63DBF']);
      final wifi = decodeProgram(File('$fixtures/bench_wifi.hex').readAsStringSync());
      expect([wifi.records, hex8(wifi.crc)], [22, 'B6AB8A04']);
    });

    test('every golden decodes to its .expect (records, CRC, panel, board, strings, words)', () {
      final goldens = Directory(golden).listSync().whereType<File>().where((f) => f.path.endsWith('.hex')).toList();
      expect(goldens.length, greaterThanOrEqualTo(3));
      for (final f in goldens) {
        final expectFile = File(f.path.replaceAll(RegExp(r'\.hex$'), '.expect'));
        expect(expectFile.existsSync(), isTrue, reason: '${f.path} needs an .expect');
        final diff = expectDiff(decodeProgram(f.readAsStringSync()), readExpect(expectFile.readAsStringSync()));
        expect(diff, isEmpty, reason: f.path);
      }
    });

    test('G2: bench_mesh4.txt decodes like bench_mesh4.hex (except mqtt[1], the panel byte)', () async {
      final hex = await convertText(fixture('bench_mesh4.txt'), 'bench_mesh4');
      expect(hex, File('$golden/glide_mesh4.hex').readAsStringSync());
      final ours = decodeProgram(hex);
      final bench = decodeProgram(File('$fixtures/bench_mesh4.hex').readAsStringSync());
      for (final name in Program.arrayNames) {
        final a = ours.array(name);
        final b = bench.array(name);
        for (int i = 0; i < a.length; i++) {
          if (name == 'mqtt' && i == 1) continue;
          expect(a[i], b[i], reason: 'word $name $i');
        }
      }
      expect(ours.mqtt[1], 0x0001, reason: 'Glide writes the panel number in network line 0');
      expect(bench.mqtt[1], 0x0000);
      expect(ours.panel, bench.panel);
      expect(hex.contains(':107010'), isFalse, reason: 'an empty PID writes nothing');
    });

    test('B1: header always line 1, the only 0x0000 record; EOF last; board type from the call', () async {
      final hex = await convertText(fixture('p5_full.txt'), 'p5_rcu', board: 'RCU');
      final lines = hexLines(hex);
      expect(lines.first, headerRecord(5, 2));
      expect(lines.where(isHeaderRecord).length, 1);
      expect(lines.last, ':00000001FF');
      expect(lines.every((l) => l == ':00000001FF' || (l.length == 43 && l.startsWith(':10'))), isTrue,
          reason: 'only 16-byte type-00 records (C-5.2)');
      expect(lines.every((l) => l == l.toUpperCase()), isTrue);
      expect(hex.contains('\r'), isFalse, reason: 'LF line ends');
      expect(decodeProgram(hex).board, 2);
    });

    test('B3: every input block at its own panel; an untagged block uses the file panel', () async {
      const txt = '<Panel-04>\n'
          ' <Switch>\n\tSW-01,LAMP,1\n </Switch>\n'
          '</Panel-04>\n'
          '<InputAssign-02>\n\tIP-01,DIGITAL-LATCH,HIGH,LAMP,1,ON,0,OFF\n</InputAssign-02>\n'
          '<InputAssign-03>\n\tIP-02,DIGITAL-LATCH,HIGH,LAMP,2,ON,0,OFF\n</InputAssign-03>\n'
          '<InputAssign>\n\tIP-04,DIGITAL-PULSE,LOW,LAMP,4,OFF,0,OFF\n</InputAssign>\n';
      final lines = hexLines(await convertText(txt, 'inputs'));
      expect(lines.where((l) => l.startsWith(':104080')).length, 1, reason: 'panel 2: 0x4080');
      expect(lines.where((l) => l.startsWith(':104120')).length, 1, reason: 'panel 3, IP-02: 0x4100 + 0x20');
      expect(lines.where((l) => l.startsWith(':1041E0')).length, 1, reason: 'untagged = panel 4, IP-04: 0x4180 + 0x60');
      expect(lines.where((l) => l.startsWith(':1040') && !l.startsWith(':104080')), isEmpty);
    });

    test('B8: brokers up to 62 characters fill 4 records; 30 or less stay as in 1.0.0', () async {
      String txt(String broker) => '<Panel-01>\n</Panel-01>\n<Connectivity>\n MQTTBrokerAddress,$broker\n'
          ' <WiFiInfo-01>\n  <WiFi-config>\n   Mode,Mqtt-HA\n  </WiFi-config>\n </WiFiInfo-01>\n</Connectivity>\n';
      final long = 'b' * 62;
      final p = decodeProgram(await convertText(txt(long), 'broker62'));
      expect(netField(p.mqtt, 8, 40), long);
      final shortHex = await convertText(txt('b' * 30), 'broker30');
      expect(hexLines(shortHex).where((l) => l.startsWith(':107030') || l.startsWith(':107040')), isEmpty);
      await expectLater(convertText(txt('b' * 63), 'broker63'), throwsA(isA<ConfigRangeError>()));
    });

    group('G5: a value that does not fit throws ConfigRangeError naming the field; no .hex, no .part', () {
      final base = fixture('p5_full.txt');
      final cases = <String, List<String>>{
        'key_number_300': ['\tSW-02,FAN-ON/OFF,1', '\tSW-02,FAN-ON/OFF,300', 'Panel-05 SW-02 number'],
        'time_70000': ['\tOD-01,RLY,LAMP,1,0', '\tOD-01,RLY,LAMP,1,70000', 'Panel-05 OD-01 time'],
        'temp_abc': ['\tOD-01,thermostat,1,on,24,panel_5', '\tOD-01,thermostat,1,on,abc,panel_5', 'NoOccupancy OD-01 temp'],
        'password_31': [' Password,Pa,ss word#1', ' Password,${'p' * 31}', 'MQTT password'],
      };
      cases.forEach((name, c) {
        test(name, () async {
          expect(base.contains(c[0]), isTrue);
          final dir = tmpDir('g5_$name');
          final txtFile = File('${dir.path}/$name.txt')..writeAsStringSync(base.replaceFirst(c[0], c[1]));
          await expectLater(
            ConvertManager.convertTxtToHex(txtFile.path, outputDir: dir.path),
            throwsA(isA<ConfigRangeError>().having((e) => e.message, 'message', contains(c[2]))),
          );
          final left = dir.listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last).toList();
          expect(left, ['$name.txt'], reason: 'no .hex and no .part may be left');
        });
      });
    });

    test('a key without a number, a non-numeric DP row and a 25th DP row', () async {
      final base = fixture('p5_full.txt');
      await expectLater(convertText(base.replaceFirst('   BELL,2,7', '   BELL,two,7'), 'dp_text'),
          throwsA(isA<ConfigRangeError>().having((e) => e.message, 'message', contains('device no'))));
      final many = List.generate(25, (i) => '   LAMP,${i + 1},${i + 1}').join('\n');
      await expectLater(convertText(base.replaceFirst('   LAMP,1,1', many), 'dp_25'),
          throwsA(isA<ConfigRangeError>().having((e) => e.message, 'message', contains('more than 24'))));
      final p = decodeProgram(await convertText(base.replaceFirst('\tSW-01,LAMP,1', '\tSW-01,LAMP,'), 'key_empty'));
      expect(p.action[1], 0x0000, reason: 'an empty number is 00, as in 1.0.0');
    });
  });

  group('checkConfig (design 3.3)', () {
    setUp(() => AppDataManager().clear());

    void load(String txt) => loadTxt(txt);

    test('p5_full: no error; the soft limits of the firmware are warnings', () {
      load(fixture('p5_full.txt'));
      expect(checkConfig(AppDataManager()), isTrue);
      expect(configErrors, isEmpty);
      expect(configWarnings.where((w) => w.contains('SW-09') && w.contains('1..32')).length, 1);
      expect(configWarnings.where((w) => w.contains('DP id 300')).length, 1);
      expect(configWarnings.length, 2, reason: configWarnings.join('\n'));
    });

    test('no panel number is an error', () {
      load(fixture('p5_full.txt'));
      AppDataManager().panelSwitchPanel = null;
      expect(checkConfig(AppDataManager()), isFalse);
      expect(configErrors.first, contains('Panel number'));
    });

    test('hard limits are errors', () {
      final d = AppDataManager();
      load(fixture('p5_full.txt'));
      d.panelSwitchRows[1]['number'] = '300';
      d.relayOutputRows[0]['time'] = '70000';
      d.sceneAssignRows[3]['temp'] = 'abc';
      d.mqttPassword = 'p' * 31;
      d.mqttBroker = 'broker"quoted';
      d.mqttPort = '70000';
      d.inputAssignRows[0]['outputState'] = 'HALF';
      expect(checkConfig(d), isFalse);
      String joined() => configErrors.join('\n');
      expect(joined(), contains('Panel-05 SW-02 number = 300'));
      expect(joined(), contains('Panel-05 OD-01 time = 70000'));
      expect(joined(), contains('NoOccupancy OD-01 temp = "abc"'));
      expect(joined(), contains('MQTT password has 31 characters'));
      expect(joined(), contains('MQTT broker address: only printable ASCII'));
      expect(joined(), contains('MQTT port = "70000"'));
      expect(joined(), contains('IP-01 output state'));
    });

    test('row caps: 17 outputs, 5 inputs, 25 DP rows', () {
      final d = AppDataManager();
      load(fixture('p5_full.txt'));
      d.relayOutputRows = List.generate(17, (i) => {
            'serialNumber': 'OD-${(i + 1).toString().padLeft(2, '0')}', 'type': 'RLY', 'output': 'LAMP', 'number': '1', 'time': '0'});
      d.inputAssignRows = List.generate(5, (i) => {
            'sr': 'IP-0${i + 1}', 'type': 'DIGITAL-LATCH', 'inputState': 'HIGH', 'outputDevice': 'LAMP',
            'deviceNo': '1', 'outputState': 'ON', 'time': '0', 'defaultState': 'OFF'});
      d.mqttDevices = List.generate(25, (i) => {'parameter': 'LAMP', 'deviceNo': '${i + 1}', 'dpId': '${i + 1}'});
      expect(checkConfig(d), isFalse);
      expect(configErrors, contains('Panel-05: 17 outputs (at most 16)'));
      expect(configErrors, contains('Panel-05 OD-17: outputs are OD-01 .. OD-16'));
      expect(configErrors, contains('Panel-05: 5 inputs (at most 4)'));
      expect(configErrors, contains('DP map: 25 rows (at most 24)'));
    });

    test('soft limits: thermostat set point, fan speed, duplicate DP, MQTT without broker, Modbus', () {
      final d = AppDataManager();
      load(fixture('p5_full.txt'));
      d.sceneAssignRows[3]['temp'] = '40';
      d.sceneAssignRows[2]['state'] = 'on_l6';
      d.mqttDevices.add({'parameter': 'LAMP', 'deviceNo': '1', 'dpId': '9'});
      d.mqttBroker = '';
      d.relayOutputRows[0]['number'] = '';
      expect(checkConfig(d), isTrue);
      final w = configWarnings.join('\n');
      expect(w, contains('thermostat set point 40'));
      expect(w, contains('fan speed 6'));
      expect(w, contains('LAMP 1 is listed twice'));
      expect(w, contains('No MQTT broker'));
      expect(w, contains('Panel-05 OD-01 has a function but no number'));

      d.connectivityType = 0;
      expect(checkConfig(d), isTrue);
      expect(configWarnings, contains('No network page: the panel will run without WiFi and BLE Mesh'));
    });

    // review_glide finding 5: the converters write 00 for a missing type, and
    // a scene output / DP parameter of 00 is LAMP - silently, until now
    test('review 5: a row without its type, output or parameter is a warning', () {
      final d = AppDataManager();
      load(fixture('p5_full.txt'));
      d.relayOutputRows[0]['type'] = null;
      d.sceneAssignRows[0]['output'] = null;
      d.mqttDevices[0]['parameter'] = '';
      d.inputAssignRows[1]['type'] = null;
      d.inputAssignRows[2]['outputDevice'] = null;
      expect(checkConfig(d), isTrue, reason: configErrors.join('\n'));
      final w = configWarnings.join('\n');
      expect(w, contains('Panel-05 OD-01 has no type (RLY / DIM) - it is written as 00'));
      expect(w, contains('Welcome OD-01 has no output - it is written as LAMP (00)'));
      expect(w, contains('DP row 1 has no parameter - it is written as LAMP (00)'));
      expect(w, contains('Panel-05 IP-02 has no type - it is written as 00 00'));
      expect(w, contains('Panel-05 IP-03 has no output device - it is written as 00 (no action)'));
      expect(configWarnings.length, 2 + 5, reason: w); // p5_full's own 2 + these
    });

    test('review 5/7: a value the converters do not know is a warning; their old spellings are not', () {
      final d = AppDataManager();
      load(fixture('p5_full.txt'));
      d.panelSwitchRows[0]['function'] = 'LAMP-DOUBLE';
      d.relayOutputRows[1]['output'] = 'HEATER';
      d.sceneAssignRows[1]['output'] = 'blinds';
      d.mqttDevices[1]['parameter'] = 'SPRINKLER';
      d.inputAssignRows[0]['outputDevice'] = 'BELL';
      expect(checkConfig(d), isTrue, reason: configErrors.join('\n'));
      final w = configWarnings.join('\n');
      expect(w, contains('Panel-05 SW-01: function "LAMP-DOUBLE" is not known to the converter - it is written as 00 (no function)'));
      expect(w, contains('Panel-05 OD-02: function "HEATER" is not known to the converter - it is written as LAMP (00)'));
      expect(w, contains('Welcome OD-02: output "blinds" is not known to the converter - it is written as LAMP (00)'));
      expect(w, contains('DP row 2 (SPRINKLER): parameter "SPRINKLER" is not known to the converter'));
      expect(w, contains('Panel-05 IP-01: output device "BELL" is not known to the converter'));
      expect(configWarnings.length, 2 + 5, reason: w);

      // spellings panel_th / scene_th / wifi_conn_th do map stay silent
      load(fixture('p5_full.txt'));
      d.panelSwitchRows[0]['function'] = 'SCENE-OFF';
      d.panelSwitchRows[1]['function'] = 'DND-STATUS';
      d.sceneAssignRows[1]['output'] = 'CURTAIN_OPEN';
      d.mqttDevices[1]['parameter'] = 'scene-toggle';
      expect(checkConfig(d), isTrue);
      expect(configWarnings.length, 2, reason: configWarnings.join('\n'));
    });

    // review_glide finding 6: the converters read two-digit labels only
    test('review 6: a one-digit label is an error, as the converters would leave the row out', () {
      final d = AppDataManager();
      load(fixture('p5_full.txt'));
      d.relayOutputRows[0]['serialNumber'] = 'OD-1';
      d.inputAssignRows[0]['sr'] = 'IP-1';
      d.sceneAssignRows[0]['sr_no'] = 'OD-1';
      expect(checkConfig(d), isFalse);
      expect(configErrors, containsAll([
        'Panel-05 OD-1: outputs are OD-01 .. OD-16',
        'Panel-05 IP-1: inputs are IP-01 .. IP-04',
        'Welcome OD-1: scene rows are OD-01 .. OD-16',
      ]));
    });
  });
}
