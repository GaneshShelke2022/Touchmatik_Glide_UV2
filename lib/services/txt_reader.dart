/*
 * =============================================================================
 *  txt_reader.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  Opens a configuration TXT into AppDataManager (loadTxt), and writes
 *  AppDataManager back as TXT (buildTxt). The TXT format is unchanged from
 *  1.0.0 ('<PS configuration V0.7>'), so files stay readable both ways.
 *
 *  loadTxt (moved here from customer_info_page.dart _parseAndLoadData):
 *   - one panel number (C2, B2b): the first <Panel-NN> wins, else the first
 *     <WiFiInfo-NN>, else the first <InputAssign-NN>. Later <Panel-..> blocks
 *     are skipped; input and WiFi blocks of another number are relabelled to
 *     the panel. Every such change is returned as a warning (one dialog).
 *   - keys keep their place (M1): 'SW-03' goes to row 3, gaps are empty rows;
 *     the module (2M/4M/6M/8M) is raised when a key needs it (warning).
 *   - a value containing ',' is kept whole (B8): "Password,a,b" -> "a,b".
 *   - output, input and scene row labels get the two-digit form the
 *     converters read: 'OD-5' -> 'OD-05' (review_glide finding 6).
 *  buildTxt is the writer of 1.0.0's configuration page, with B2(c): every
 *  panel tag uses the Panel page's number.
 * =============================================================================
 */
import '../data/app_data.dart';
import 'hex_tools.dart';

class TxtLoadResult {
  final int? panel;                  // the panel the file was read for; null = no tag names one
  final List<String> warnings;       // what moved or was skipped (empty = read as it is)
  const TxtLoadResult(this.panel, this.warnings);
}

const List<String> txtSceneTags = ['Welcome', 'NoOccupancy', 'Scene-03', 'Scene-04', 'Scene-05', 'Scene-06'];
const Map<String, int> txtModuleKeys = {'2M': 5, '4M': 10, '6M': 15, '8M': 20};
const int txtMaxKeys = 20;

// the configuration fields an opened file replaces (Process / board settings stay)
void _resetConfiguration(AppDataManager data) {
  data.panelSwitchRows = [];
  data.relayOutputRows = [];
  data.inputAssignRows = [];
  data.sceneAssignRows = [];
  data.mqttDevices = [];
  data.tuyaDevices = [];
  data.panelSwitchPanel = null;
  data.panelSwitchLocation = null;
  data.panelSwitchModule = null;
  data.inputAssignPanel = null;
  data.wifiPanel = null;
  data.wifiMode = null;
  data.tuyaPid = null;
  data.mqttBroker = null;
  data.mqttPort = null;
  data.mqttUser = null;
  data.mqttPassword = null;
  data.modbusBaudRate = null;
  data.modbusDataBit = null;
  data.modbusStopBit = null;
  data.modbusParity = null;
  data.connectivityType = 0;
}

String? _nullIfEmpty(String text) => text.trim().isEmpty ? null : text.trim();

// "Key,a,b" -> "a,b" (B8: commas inside a value are kept)
String _valueOf(List<String> parts) => parts.sublist(1).join(',').trim();

/// A row label in the two-digit form the converters read: 'OD-5', 'od-05' or
/// 'OD 5' -> 'OD-05' (review_glide finding 6: a hand-edited 'OD-5' passed the
/// check and was then left out of the HEX). Anything else is kept as it is;
/// checkConfig reports it.
String txtRowLabel(String text, String prefix) {
  final t = text.trim();
  final m = RegExp('^$prefix[-_ ]?0*(\\d{1,2})\$', caseSensitive: false).firstMatch(t);
  return m == null ? t : '$prefix-${m.group(1)!.padLeft(2, '0')}';
}

/// Reads a configuration TXT [content] into AppDataManager() (see the file header).
TxtLoadResult loadTxt(String content) {
  final data = AppDataManager();
  _resetConfiguration(data);

  final lines = content.split('\n').map((l) => l.trim()).toList();
  final tagPanel = txtPanelTag(lines);
  final panel = tagPanel ?? 1;
  final label = panelLabel(panel);
  final warnings = <String>[];

  final tagRegex = RegExp(r'^<(/)?([^>]+)>$');
  final keyRows = <int, Map<String, dynamic>>{};
  int nextKey = 0;

  String? section;          // ProjectInformation, Panel, Input, Scene, Connectivity, Skip
  String? sectionTag;       // the tag that opened it
  String? sceneTag;         // Welcome .. Scene-06 while section == Scene
  String? sub;              // Switch / Output inside the panel block
  String? wifiBlock;        // read / skip inside a <WiFiInfo-NN>
  String? wifiSub;          // WiFi-config / WiFi-parameter
  bool panelRead = false;
  bool inputRead = false;
  bool wifiRead = false;

  for (final line in lines) {
    if (line.isEmpty) continue;

    final match = tagRegex.firstMatch(line);
    if (match != null) {
      final isEndTag = match.group(1) == '/';
      final tagName = match.group(2)!.trim();

      if (isEndTag) {
        if (section == 'Skip') {
          if (tagName == sectionTag) section = sectionTag = null;
        } else if (tagName == 'Switch' || tagName == 'Output') {
          sub = null;
        } else if (tagName == 'WiFi-config' || tagName == 'WiFi-parameter') {
          wifiSub = null;
        } else if (tagName.startsWith('WiFiInfo')) {
          wifiBlock = null;
          wifiSub = null;
        } else if (tagName == sectionTag ||
            (section == 'Panel' && tagName.startsWith('Panel-')) ||
            (section == 'Input' && tagName.startsWith('Input'))) {
          section = sectionTag = sceneTag = sub = null;
        }
        continue;
      }

      if (tagName.contains('PS configuration') || section == 'Skip') continue;

      final panelTag = RegExp(r'^Panel-(\d{1,2})$').firstMatch(tagName);
      final inputTag = RegExp(r'^Input(?:Assign)?(?:-(\d{1,2}))?$').firstMatch(tagName);
      final wifiTag = RegExp(r'^WiFiInfo-(\d{1,2})$').firstMatch(tagName);

      if (tagName == 'ProjectInformation' || tagName == 'Connectivity') {
        section = sectionTag = tagName;
      } else if (panelTag != null) {
        sectionTag = tagName;
        if (panelRead) {
          section = 'Skip';
          warnings.add('Skipped <$tagName>: Glide edits one panel per file, this file is read as $label.');
        } else {
          section = 'Panel';
          panelRead = true;
          if (int.parse(panelTag.group(1)!) != panel) {
            warnings.add('Keys and outputs of $tagName moved to $label.');
          }
        }
      } else if (inputTag != null) {
        sectionTag = tagName;
        if (inputRead) {
          section = 'Skip';
          warnings.add('Skipped a second input block <$tagName>.');
        } else {
          section = 'Input';
          inputRead = true;
          final own = inputTag.group(1);
          if (own != null && int.parse(own) != panel) {
            warnings.add('Inputs of ${panelLabel(int.parse(own))} moved to $label.');
          }
        }
      } else if (txtSceneTags.contains(tagName)) {
        section = 'Scene';
        sectionTag = sceneTag = tagName;
      } else if (RegExp(r'^Scene-(0[7-9]|1[0-6])$').hasMatch(tagName)) {
        section = 'Skip';
        sectionTag = tagName;
        warnings.add('Skipped <$tagName>: Glide 1.1 edits scenes 1 to 6 only.');
      } else if (section == 'Panel' && (tagName == 'Switch' || tagName == 'Output')) {
        sub = tagName;
      } else if (section == 'Connectivity' && wifiTag != null) {
        if (wifiRead) {
          wifiBlock = 'skip';
          warnings.add('Skipped a second WiFi / BLE block <$tagName>.');
        } else {
          wifiBlock = 'read';
          wifiRead = true;
          data.connectivityType = 1;
          final own = int.parse(wifiTag.group(1)!);
          if (own != panel) {
            warnings.add('WiFi / BLE settings of ${panelLabel(own)} moved to $label.');
          }
        }
      } else if (section == 'Connectivity' && (tagName == 'WiFi-config' || tagName == 'WiFi-parameter')) {
        wifiSub = tagName;
      }
      continue;
    }

    // ---- a data line
    if (section == 'ProjectInformation') {
      if (line.startsWith('CustomerName:')) {
        data.customerName = line.substring('CustomerName:'.length).trim();
      } else if (line.startsWith('Address:')) {
        data.customerAddress = line.substring('Address:'.length).trim();
      }
    } else if (section == 'Panel') {
      final parts = line.split(',');
      if (sub == 'Switch') {
        if (parts.length < 3) continue;
        final sw = RegExp(r'^SW-(\d{1,2})$').firstMatch(parts[0].trim());
        final index = sw != null ? int.parse(sw.group(1)!) - 1 : nextKey;
        if (index < 0 || index >= txtMaxKeys) {
          warnings.add('Skipped key "${parts[0].trim()}": a panel has at most $txtMaxKeys keys.');
          continue;
        }
        if (keyRows.containsKey(index)) {
          warnings.add('${parts[0].trim()} appears twice: the last one is kept.');
        }
        keyRows[index] = {'function': _nullIfEmpty(parts[1]), 'number': parts[2].trim()};
        if (index + 1 > nextKey) nextKey = index + 1;
      } else if (sub == 'Output') {
        if (parts.length < 5) continue;
        data.relayOutputRows.add({
          'serialNumber': txtRowLabel(parts[0], 'OD'),
          'type': _nullIfEmpty(parts[1]),
          'output': _nullIfEmpty(parts[2]),
          'number': parts[3].trim(),
          'time': parts[4].trim(),
        });
      } else if (line.startsWith('Location:')) {
        data.panelSwitchLocation = line.substring('Location:'.length).trim();
      } else if (line.startsWith('Module:')) {
        data.panelSwitchModule = line.substring('Module:'.length).trim();
      }
    } else if (section == 'Input') {
      final parts = line.split(',');
      if (parts.length < 8) continue;
      data.inputAssignRows.add({
        'sr': txtRowLabel(parts[0], 'IP'),
        'type': _nullIfEmpty(parts[1]),
        'inputState': _nullIfEmpty(parts[2]),
        'outputDevice': _nullIfEmpty(parts[3]),
        'deviceNo': parts[4].trim(),
        'outputState': _nullIfEmpty(parts[5]),
        'time': parts[6].trim(),
        'defaultState': _nullIfEmpty(parts[7]),
      });
    } else if (section == 'Scene') {
      final parts = line.split(',');
      if (parts.length < 4) continue;
      String at(int i) => i < parts.length ? parts[i].trim() : '';
      data.sceneAssignRows.add({
        'type': sceneTag,
        'sr_no': txtRowLabel(at(0), 'OD'),
        'output': _nullIfEmpty(at(1)),
        'number': at(2),
        'state': _nullIfEmpty(at(3)),
        'temp': at(4),
        'panel_no': _nullIfEmpty(at(5)),
      });
    } else if (section == 'Connectivity') {
      final parts = line.split(',');
      if (wifiBlock == 'skip') continue;
      if (wifiBlock == 'read' && wifiSub == 'WiFi-parameter') {
        if (parts.length < 3) continue;
        final device = <String, dynamic>{
          'parameter': parts[0].trim(),
          'deviceNo': parts[1].trim(),
          'dpId': parts[2].trim(),
        };
        if (data.wifiMode == 'Mqtt-HA') {
          data.mqttDevices.add(device);
        } else {
          data.tuyaDevices.add(device);
        }
      } else if (wifiBlock == 'read') {
        if (parts.length < 2) continue;
        final key = parts[0].trim();
        final value = _valueOf(parts);
        if (key == 'Mode') {
          data.wifiMode = value;
          data.connectivityType = 1;
        } else if (key == 'MQTTPort') {
          data.mqttPort = value;
          data.connectivityType = 1;
        } else if (key == 'PID') {
          data.tuyaPid = value;
          data.connectivityType = 1;
        }
      } else {
        if (parts.length < 2) continue;
        final key = parts[0].trim();
        final value = _valueOf(parts);
        switch (key) {
          case 'BaudRate':
            data.modbusBaudRate = value;
            data.connectivityType = 0;
            break;
          case 'DataBit':
            data.modbusDataBit = value;
            break;
          case 'StopBit':
            data.modbusStopBit = value;
            break;
          case 'Parity':
            data.modbusParity = value;
            break;
          case 'MQTTBrokerAddress':
            data.mqttBroker = value;
            data.connectivityType = 1;
            break;
          case 'UserName':
            data.mqttUser = value;
            break;
          case 'Password':
            data.mqttPassword = value;
            break;
        }
      }
    }
  }

  // ---- keys at their own places (M1), gaps as empty rows
  if (keyRows.isNotEmpty) {
    final count = keyRows.keys.reduce((a, b) => a > b ? a : b) + 1;
    data.panelSwitchRows = List.generate(count, (i) => keyRows[i] ?? {'function': null, 'number': ''});
    final module = data.panelSwitchModule;
    final shown = txtModuleKeys[module] ?? txtModuleKeys['2M']!;   // the Panel page treats no module as 2M
    if (count > shown) {
      final needed = txtModuleKeys.entries.firstWhere((e) => e.value >= count).key;
      warnings.add('Module raised from ${module == null || module.isEmpty ? '2M' : module} to $needed: '
          'the file uses SW-${count.toString().padLeft(2, '0')}.');
      data.panelSwitchModule = needed;
    }
  }

  // ---- one panel number everywhere (C2)
  if (tagPanel != null || panelRead) data.panelSwitchPanel = label;
  if (inputRead) data.inputAssignPanel = label;
  if (wifiRead) data.wifiPanel = label;

  return TxtLoadResult(tagPanel, warnings);
}

/// The configuration TXT of [data], in 1.0.0's format; every panel tag uses the
/// Panel page's number (B2c) - the configuration page writes the same text.
String buildTxt(AppDataManager data) {
  final content = StringBuffer();
  final String? panelTag =
      (data.panelSwitchPanel != null && data.panelSwitchPanel!.isNotEmpty) ? data.panelSwitchPanel : null;
  String tagNumber(String own) => (panelTag ?? own).replaceAll('Panel-', '');

  content.writeln('<PS configuration V0.7>');
  if (data.customerName != null && data.customerName!.isNotEmpty) {
    content.writeln('<ProjectInformation>');
    content.writeln(' CustomerName:${data.customerName ?? ""}');
    content.writeln(' Address:${data.customerAddress ?? ""}');
    content.writeln('</ProjectInformation>');
  }
  if (panelTag != null) {
    content.writeln('<$panelTag>');
    content.writeln(' Location: ${data.panelSwitchLocation ?? ""}');
    content.writeln(' Module: ${data.panelSwitchModule ?? ""}');
    final keys = <String>[];
    for (int index = 0; index < data.panelSwitchRows.length; index++) {
      final row = data.panelSwitchRows[index];
      final function = row['function'] ?? '';
      final number = row['number'] ?? '';
      if (function.toString().trim().isEmpty && number.toString().trim().isEmpty) continue;
      keys.add('\tSW-${(index + 1).toString().padLeft(2, '0')},$function,$number');
    }
    if (keys.isNotEmpty) {
      content.writeln(' <Switch>');
      keys.forEach(content.writeln);
      content.writeln(' </Switch>');
    }
    final validOutputs = data.relayOutputRows.where((row) {
      final type = row['type']?.toString().trim() ?? '';
      final output = row['output']?.toString().trim() ?? '';
      final number = row['number']?.toString().trim() ?? '';
      final time = row['time']?.toString().trim() ?? '';
      return type.isNotEmpty || output.isNotEmpty || number.isNotEmpty || time.isNotEmpty;
    }).toList();
    if (validOutputs.isNotEmpty) {
      content.writeln(' <Output>');
      for (final row in validOutputs) {
        content.writeln('\t${row['serialNumber'] ?? ''},${row['type'] ?? ''},${row['output'] ?? ''},'
            '${row['number'] ?? ''},${row['time'] ?? ''}');
      }
      content.writeln(' </Output>');
    }
    content.writeln('</$panelTag>');
  }
  if (data.inputAssignPanel != null && data.inputAssignPanel!.isNotEmpty) {
    final panelNum = tagNumber(data.inputAssignPanel!);
    content.writeln('<InputAssign-$panelNum>');
    for (final row in data.inputAssignRows) {
      final fields = [
        row['type'], row['inputState'], row['outputDevice'], row['deviceNo'],
        row['outputState'], row['time'], row['defaultState'],
      ].map((v) => v?.toString().trim() ?? '').toList();
      if (fields.every((f) => f.isEmpty)) continue;
      content.writeln('\t${row['sr'] ?? ''},${fields.join(',')}');
    }
    content.writeln('</InputAssign-$panelNum>');
  }
  if (data.sceneAssignRows.isNotEmpty) {
    final scenesByType = <String, List<Map<String, dynamic>>>{};
    for (final row in data.sceneAssignRows) {
      final type = row['type'] ?? 'Unknown';
      final used = ['output', 'number', 'state', 'temp', 'panel_no']
          .any((k) => (row[k]?.toString().trim() ?? '').isNotEmpty);
      if (!used) continue;
      scenesByType.putIfAbsent(type, () => []).add(row);
    }
    scenesByType.forEach((type, rows) {
      content.writeln('<$type>');
      for (final row in rows) {
        content.writeln('\t${row['sr_no'] ?? ''},${row['output'] ?? ''},${row['number'] ?? ''},'
            '${row['state'] ?? ''},${row['temp'] ?? ''},${row['panel_no'] ?? ''}');
      }
      content.writeln('</$type>');
    });
  }
  content.writeln('<Connectivity>');
  if (data.connectivityType == 0) {
    if (data.modbusBaudRate != null && data.modbusBaudRate!.isNotEmpty) content.writeln(' BaudRate,${data.modbusBaudRate}');
    if (data.modbusDataBit != null && data.modbusDataBit!.isNotEmpty) content.writeln(' DataBit,${data.modbusDataBit}');
    if (data.modbusStopBit != null && data.modbusStopBit!.isNotEmpty) content.writeln(' StopBit,${data.modbusStopBit}');
    if (data.modbusParity != null && data.modbusParity!.isNotEmpty) content.writeln(' Parity,${data.modbusParity}');
  }
  if (data.mqttBroker != null && data.mqttBroker!.isNotEmpty) content.writeln(' MQTTBrokerAddress,${data.mqttBroker}');
  if (data.mqttUser != null && data.mqttUser!.isNotEmpty) content.writeln(' UserName,${data.mqttUser}');
  if (data.mqttPassword != null && data.mqttPassword!.isNotEmpty) content.writeln(' Password,${data.mqttPassword}');
  if (data.connectivityType == 1 && data.wifiPanel != null && data.wifiPanel!.isNotEmpty) {
    final panelNum = tagNumber(data.wifiPanel!);
    content.writeln(' <WiFiInfo-$panelNum>');
    content.writeln('  <WiFi-config>');
    if (data.wifiMode != null) content.writeln('   Mode,${data.wifiMode}');
    if (data.wifiMode == 'Mqtt-HA' && data.mqttPort != null) {
      content.writeln('   MQTTPort,${data.mqttPort}');
    } else if ((data.wifiMode == 'Tuya-wifi' || data.wifiMode == 'Tuya-BLE') && data.tuyaPid != null) {
      content.writeln('   PID,${data.tuyaPid}');
    }
    content.writeln('  </WiFi-config>');
    final devices = data.wifiMode == 'Mqtt-HA' ? data.mqttDevices : data.tuyaDevices;
    final validDevices = devices.where((d) {
      return ['parameter', 'deviceNo', 'dpId'].any((k) => (d[k]?.toString().trim() ?? '').isNotEmpty);
    }).toList();
    if (validDevices.isNotEmpty) {
      content.writeln('  <WiFi-parameter>');
      for (final device in validDevices) {
        content.writeln('   ${device['parameter'] ?? ''},${device['deviceNo'] ?? ''},${device['dpId'] ?? ''}');
      }
      content.writeln('  </WiFi-parameter>');
    }
    content.writeln(' </WiFiInfo-$panelNum>');
  }
  content.writeln('</Connectivity>');
  return content.toString();
}
