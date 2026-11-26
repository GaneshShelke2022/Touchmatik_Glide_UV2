/*
 * =============================================================================
 *  txt_open_test.dart  -  Touchmatik Glide 1.1.0 tests (GA-1, Oct-2026)
 *  "Open TXT" (loadTxt) and the TXT writer (buildTxt), V0.6.0 design 5.4:
 *    G3  a 1.0.0-style file with <Panel-05>, <InputAssign-03>, <WiFiInfo-01>,
 *        a second <Panel-07>, THERMOSTAT-VALV, on_l3 and ON-L-1 opens as one
 *        panel 5 with 3 warnings, and regenerates with valve 74, levels 03/01
 *    G4  keys SW-01, SW-03, SW-05 only keep their places through Open and
 *        regenerate (key words at bytes 0x00, 0x08, 0x10)
 *  plus B8 (commas inside values), M1 (module raised), and the round trip
 *  TXT -> loadTxt -> buildTxt -> the same TXT -> the same HEX; fix_glide:
 *  one-digit row labels are padded (review_glide finding 6).
 *  Files are written to build/test_tmp only.
 * =============================================================================
 */
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:progswitches/data/app_data.dart';
import 'package:progswitches/services/convert_manager.dart';
import 'package:progswitches/services/hex_tools.dart';
import 'package:progswitches/services/txt_reader.dart';

import 'fixtures/golden_decoder.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

// buildTxt(AppDataManager()) -> file -> ConvertManager; returns the HEX text
Future<String> regenerate(String name) async {
  final dir = Directory('build/test_tmp/txt_open/$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final txt = File('${dir.path}/$name.txt')..writeAsStringSync(buildTxt(AppDataManager()));
  final hexPath = await ConvertManager.convertTxtToHex(txt.path, outputDir: dir.path);
  return File(hexPath).readAsStringSync();
}

List<String> hexLines(String hex) => hex.split('\n').where((l) => l.isNotEmpty).toList();

void main() {
  setUp(() => AppDataManager().clear());

  test('G3: a mixed-panel 1.0.0 file opens as one panel 5 with 3 warnings and regenerates fixed', () async {
    final d = AppDataManager();
    final result = loadTxt(fixture('v100_mixed_panels.txt'));

    expect(result.panel, 5);
    expect(d.panelSwitchPanel, 'Panel-05');
    expect(d.inputAssignPanel, 'Panel-05');
    expect(d.wifiPanel, 'Panel-05');
    expect(d.panelNo, 5);
    expect(result.warnings.length, 3, reason: result.warnings.join('\n'));
    expect(result.warnings.where((w) => w.contains('<Panel-07>')).length, 1);
    expect(result.warnings.where((w) => w.contains('Inputs of Panel-03 moved to Panel-05')).length, 1);
    expect(result.warnings.where((w) => w.contains('settings of Panel-01 moved to Panel-05')).length, 1);
    // the second panel block is not mixed in (1.0.0 appended its rows)
    expect(d.panelSwitchRows.length, 2);
    expect(d.relayOutputRows.length, 2);
    expect(d.relayOutputRows[1]['output'], 'THERMOSTAT-VALV', reason: 'stored values stay as they are (C1)');

    final txt = buildTxt(d);
    expect(txt, contains('<InputAssign-05>'));
    expect(txt, contains(' <WiFiInfo-05>'));
    expect(txt.contains('Panel-07'), isFalse);
    expect(txt.contains('InputAssign-03'), isFalse);

    final hex = await regenerate('g3');
    final lines = hexLines(hex);
    expect(lines.first, headerRecord(5, 1));
    expect(lines.where((l) => l.startsWith(':1016')), isEmpty, reason: 'no page for panel 7');
    expect(lines.where((l) => l.startsWith(':104200')).length, 1, reason: 'inputs of panel 5 at 0x4200');
    final p = decodeProgram(hex);
    expect(p.panel, 5);
    expect(p.output[5], 0x7401, reason: 'valve 74');
    expect(p.input[4] & 0xFF, 0x01, reason: 'input output state ON-L-1 = 01');
    expect(p.scene[1] & 0xFF, 0x03, reason: 'scene on_l3 = 03');
    expect(p.mqtt[0], 0x0011);
    expect(p.mqtt[1], 0x0005, reason: 'the network page is panel 5');
    expect(netField(p.mqtt, 8, 40), '10.0.0.5');
    expect(p.param[0], 0x0001);
  });

  test('G4: SW-01, SW-03, SW-05 keep their places (key words at 0x00, 0x08, 0x10)', () async {
    final d = AppDataManager();
    final result = loadTxt(fixture('sw_gaps.txt'));
    expect(result.warnings, isEmpty);
    expect(d.panelSwitchRows.length, 5);
    expect(d.panelSwitchRows[0], {'function': 'LAMP', 'number': '1'});
    expect(d.panelSwitchRows[1]['function'], isNull);
    expect(d.panelSwitchRows[1]['number'], '');
    expect(d.panelSwitchRows[2], {'function': 'LAMP', 'number': '3'});
    expect(d.panelSwitchRows[3]['function'], isNull);
    expect(d.panelSwitchRows[4], {'function': 'SCENE', 'number': '2'});

    final txt = buildTxt(d);
    expect(RegExp(r'^\tSW-\d\d', multiLine: true).allMatches(txt).map((m) => m.group(0)!.trim()).toList(),
        ['SW-01', 'SW-03', 'SW-05']);

    final p = decodeProgram(await regenerate('g4'));
    expect(p.panel, 2);
    // bytes 0x00, 0x08, 0x10 of the key page = words 0, 4, 8
    expect([p.action[0], p.action[1]], [0x0001, 0x0001]);
    expect([p.action[4], p.action[5]], [0x0001, 0x0003]);
    expect([p.action[8], p.action[9]], [0x0010, 0x8102]);
    for (final i in [2, 3, 6, 7]) {
      expect(p.action[i], 0, reason: 'SW-02 and SW-04 stay empty');
    }
  });

  test('M1: a key beyond the module raises the module (warning); keys beyond SW-20 are skipped', () {
    final d = AppDataManager();
    final result = loadTxt('<Panel-03>\n Module: 2M\n <Switch>\n\tSW-07,LAMP,7\n\tSW-21,LAMP,21\n\tSW-07,LAMP,8\n </Switch>\n</Panel-03>\n');
    expect(d.panelSwitchModule, '4M');
    expect(d.panelSwitchRows.length, 7);
    expect(d.panelSwitchRows[6], {'function': 'LAMP', 'number': '8'});
    expect(result.warnings.where((w) => w.startsWith('Module raised from 2M to 4M')).length, 1);
    expect(result.warnings.where((w) => w.contains('SW-21')).length, 1);
    expect(result.warnings.where((w) => w.contains('SW-07 appears twice')).length, 1);
  });

  test('B8: a value with commas is read whole (password, broker)', () {
    final d = AppDataManager();
    loadTxt(fixture('p5_full.txt'));
    expect(d.mqttPassword, 'Pa,ss word#1');
    expect(d.mqttBroker, 'broker-01.keetronics-automation.example.co.in');
    expect(d.mqttUser, 'kipl_user');
    expect(d.mqttPort, '8883');
    expect(d.wifiMode, 'Mqtt-HA');
    expect(d.connectivityType, 1);
    expect(d.mqttDevices.length, 5);
    expect(d.mqttDevices[2], {'parameter': 'BELL', 'deviceNo': '2', 'dpId': '7'});
  });

  test('round trip: p5_full.txt -> loadTxt -> buildTxt is the same text, and the same HEX', () async {
    final text = fixture('p5_full.txt');
    final result = loadTxt(text);
    expect(result.warnings, isEmpty);
    expect(buildTxt(AppDataManager()), text);
    expect(await regenerate('roundtrip'), File('test/golden/p5_full.hex').readAsStringSync());
  });

  test('round trip of a Tuya-BLE file with an empty PID (bench_mesh4.txt)', () {
    final text = fixture('bench_mesh4.txt');
    expect(loadTxt(text).warnings, isEmpty);
    expect(AppDataManager().tuyaPid, '');
    expect(AppDataManager().tuyaDevices.length, 4);
    expect(buildTxt(AppDataManager()), text);
  });

  test('later WiFi blocks and scenes 7..16 are skipped with a warning', () {
    final d = AppDataManager();
    final result = loadTxt('<Panel-02>\n</Panel-02>\n<Scene-07>\n\tOD-01,lamp,1,on,,panel_2\n</Scene-07>\n'
        '<Welcome>\n\tOD-01,lamp,1,on,,panel_2\n</Welcome>\n'
        '<Connectivity>\n <WiFiInfo-02>\n  <WiFi-config>\n   Mode,Tuya-wifi\n   PID,abc\n  </WiFi-config>\n </WiFiInfo-02>\n'
        ' <WiFiInfo-09>\n  <WiFi-config>\n   Mode,Mqtt-HA\n  </WiFi-config>\n </WiFiInfo-09>\n</Connectivity>\n');
    expect(result.warnings.length, 2, reason: result.warnings.join('\n'));
    expect(d.sceneAssignRows.length, 1);
    expect(d.sceneAssignRows.first['type'], 'Welcome');
    expect(d.wifiMode, 'Tuya-wifi');
    expect(d.tuyaPid, 'abc');
    expect(d.wifiPanel, 'Panel-02');
  });

  test('a file without panel tags leaves the panel to the Panel page', () {
    final d = AppDataManager();
    final result = loadTxt('<PS configuration V0.7>\n<ProjectInformation>\n CustomerName:A\n Address:B\n</ProjectInformation>\n'
        '<Connectivity>\n BaudRate,19200\n</Connectivity>\n');
    expect(result.panel, isNull);
    expect(d.panelSwitchPanel, isNull);
    expect(d.customerName, 'A');
    expect(d.modbusBaudRate, '19200');
    expect(d.connectivityType, 0);
  });

  test('Windows line ends (CRLF) read the same', () {
    final d = AppDataManager();
    loadTxt(fixture('p5_full.txt').replaceAll('\n', '\r\n'));
    expect(d.panelSwitchRows.length, 10);
    expect(d.mqttPassword, 'Pa,ss word#1');
    expect(buildTxt(d), fixture('p5_full.txt'));
  });

  // review_glide finding 6: checkConfig accepted 'OD-4', the converters only
  // read 'OD-04', so a hand-edited row passed the check and vanished from the HEX
  test('review 6: one-digit labels of a hand-edited TXT are read as OD-04 / IP-02 and reach the HEX', () async {
    final d = AppDataManager();
    final edited = fixture('p5_full.txt')
        .replaceFirst('\tOD-04,RLY,CURTAIN-OPEN,1,70', '\tod-4,RLY,CURTAIN-OPEN,1,70')
        .replaceFirst('\tIP-02,DIGITAL-PULSE', '\tIP-2,DIGITAL-PULSE')
        .replaceFirst('\tOD-05,lamp,4,off', '\tOD 5,lamp,4,off');
    expect(edited, isNot(fixture('p5_full.txt')));
    expect(loadTxt(edited).warnings, isEmpty);
    expect(d.relayOutputRows.map((r) => r['serialNumber']), ['OD-01', 'OD-02', 'OD-03', 'OD-04', 'OD-05', 'OD-06']);
    expect(d.inputAssignRows.map((r) => r['sr']), ['IP-01', 'IP-02', 'IP-03']);
    expect(d.sceneAssignRows.map((r) => r['sr_no']), ['OD-01', 'OD-02', 'OD-03', 'OD-01', 'OD-02', 'OD-05']);
    expect(buildTxt(d), fixture('p5_full.txt'));
    expect(await regenerate('labels'), File('test/golden/p5_full.hex').readAsStringSync());
  });

  test('txtRowLabel pads what the converters would drop and keeps the rest for checkConfig', () {
    expect(txtRowLabel('OD-5', 'OD'), 'OD-05');
    expect(txtRowLabel(' od_05 ', 'OD'), 'OD-05');
    expect(txtRowLabel('IP 3', 'IP'), 'IP-03');
    expect(txtRowLabel('OD-16', 'OD'), 'OD-16');
    expect(txtRowLabel('OD-007', 'OD'), 'OD-07');
    expect(txtRowLabel('OD-100', 'OD'), 'OD-100');
    expect(txtRowLabel('X-1', 'OD'), 'X-1');
    expect(txtRowLabel('', 'IP'), '');
  });
}
