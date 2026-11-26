/*
 * =============================================================================
 *  process_config.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  "Process": sets the 0x0000 header record (panel number, board type) of an
 *  existing GUI HEX file, and builds the RS485 (Modbus FC21) packets.
 *
 *  V1.1.0: every existing 0x0000 record is dropped before the new header is
 *  put first, so re-processing never leaves two headers (B1b; the firmware
 *  keeps the LAST one, config_store.c:117-128); the header comes from the
 *  shared headerRecord() (hex_tools.dart); hexPagePanels() tells which
 *  panels the file's pages are for (the Process dialog warns on a mismatch,
 *  B2d); getNodeInfoFromHex() reads the panel and board bytes (B1c).
 * =============================================================================
 */
import 'dart:convert';
import 'dart:typed_data';
import 'hex_tools.dart';

/// A class that encapsulates the logic for processing a hex file based on user configuration.
/// This is a Dart translation of the logic from the provided Python script.
class ProcessConfig {
  // Headers from the Python script
  final Uint8List _header =
      Uint8List.fromList([0x15, 0x32, 0x06, 0x00, 0x01, 0x10, 0x00, 0x00, 0x16]);
  final Uint8List _header1 =
      Uint8List.fromList([0x15, 0x12, 0x06, 0x00, 0x01, 0x10, 0x00, 0x00, 0x06]);

  // NOTE: In the Python script, `headerusb` and `headerusb1` are used but not defined.
  // We are assuming they are the same as the other headers for this translation.
  // The user should verify and update these values if they are different.
  final Uint8List _headerusb = 
      Uint8List.fromList([0x15, 0x32, 0x06, 0x00, 0x01, 0x10, 0x00, 0x00, 0x16]);
  final Uint8List _headerusb1 = 
      Uint8List.fromList([0x15, 0x12, 0x06, 0x00, 0x01, 0x10, 0x00, 0x00, 0x06]);

  /// Returns [originalHexContent] with exactly one 0x0000 header record, first:
  /// [panelText] 'Panel-05' (1..48, else ConfigRangeError), [boardText] 'STANDALONE' (default) or 'RCU'.
  /// Every old header record is dropped; the other lines are kept in order; LF line ends.
  /// [isBroadcast] does not change the record (the header address is 0x0000 either way).
  String generateModifiedHex({
    required String originalHexContent,
    required bool isBroadcast,
    required String panelText,
    required String boardText,
    // The following serial port parameters are accepted for compatibility with the UI,
    // but they are not used in the hex generation logic itself. This makes the
    // COM port details effectively optional for this function.//
    String? baudRateStr,
    String? parityStr,
    String? dataBitsStr,
    String? stopBitsStr,
  }) {
    // the shared header (hex_tools.dart): [panel][00][00][board][12 x 00] at 0x0000, also for broadcast
    final configRecord = headerRecord(panelNumberOf(panelText) ?? 0, boardByteOf(boardText));

    // V1.1.0 (B1b): drop every old header, keep the rest in order
    final kept = originalHexContent
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !isHeaderRecord(line))
        .toList();
    return '${[configRecord, ...kept].join('\n')}\n';
  }

  /// Prepares the data packets for serial transmission from the modified hex content.
  ///
  /// The Python script sends the file twice; this function prepares the data once.
  /// The calling code can decide if it needs to send the data multiple times.
  List<Uint8List> prepareDataForSerial({
    required String modifiedHexContent,
    required bool isBroadcast,
    required String panelText,
  }) {
    int slaveAdd;
    if (isBroadcast) {
      slaveAdd = 0;
    } else {
      slaveAdd = int.tryParse(panelText.replaceAll('Panel-', '').trim()) ?? 0;
    }

    final List<Uint8List> packets = [];
    final lines = modifiedHexContent.split('\n');

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      final lineBytes = utf8.encode(trimmedLine);
      final data = BytesBuilder();
      Uint8List crc;

      if (slaveAdd == 256) { // Special USB case
        if (lineBytes.length == 43) {
          data.add(_headerusb);
        } else if (lineBytes.length == 11) {
          data.add(_headerusb1);
        } else {
          data.add(_headerusb);
        }
        data.add(lineBytes);
        crc = _calculateMod256(data.toBytes());
      } else {
        data.addByte(slaveAdd);
        if (lineBytes.length == 43) {
          data.add(_header);
        } else if (lineBytes.length == 11) {
          data.add(_header1);
        } else {
          data.add(_header);
        }
        data.add(lineBytes);
        crc = _calculateCrc(data.toBytes());
      }
      
      data.add(crc);
      packets.add(data.toBytes());
    }
    return packets;
  }

  /// Calculates CRC-16/MODBUS.
  Uint8List _calculateCrc(Uint8List data) {
    int crc = 0xFFFF;
    for (int byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc = crc >> 1;
        }
      }
    }
    final crcBytes = ByteData(2)..setUint16(0, crc, Endian.little);
    return crcBytes.buffer.asUint8List();
  }

  /// Calculates a MOD256 checksum.
  Uint8List _calculateMod256(Uint8List data) {
    int checksum = 0;
    for (int byte in data) {
      checksum = (checksum + byte) % 256;
    }
    return Uint8List.fromList([checksum]);
  }
}

/// The panels a GUI HEX file has pages for (V0.6.0 C-5.1): keys/outputs on page
/// 0x10 + (P-1), inputs at 0x4000 + (P-1) * 0x80, the network page 0x70 + (P-1).
/// The header and the panel-independent scenes do not count.
Set<int> hexPagePanels(String hexContent) {
  final panels = <int>{};
  for (final raw in hexContent.split('\n')) {
    final line = raw.trim();
    if (line.length < 9 || !line.startsWith(':') || line.substring(7, 9) != '00') continue;
    final address = int.tryParse(line.substring(3, 7), radix: 16);
    if (address == null) continue;
    if (address >= 0x1000 && address < 0x4000) {
      panels.add((address >> 8) - 0x10 + 1);
    } else if (address >= 0x4000 && address < 0x5800) {
      panels.add((address - 0x4000) ~/ 0x80 + 1);
    } else if (address >= 0x7000 && address < 0xA000) {
      panels.add((address >> 8) - 0x70 + 1);
    }
  }
  return panels;
}

/// true when the file has pages, but none for [panel]: with that header the panel would ignore them
bool processPanelMismatch(String hexContent, int panel) {
  final pages = hexPagePanels(hexContent);
  return pages.isNotEmpty && !pages.contains(panel);
}

/// A helper function to extract Node ID and Board Type from a hex file.
/// This can be used to display information to the user before processing.
/// V1.1.0 (B1c): node id = header byte 0 (the panel number), board = header byte 3.
Map<String, String> getNodeInfoFromHex(String hexContent) {
  String? nodeId;
  String? boardTypeStr;

  final lines = hexContent.split('\n');
  for (var line in lines) {
    final trimmedLine = line.trim();
    if (trimmedLine.startsWith(':10000000')) {
      try {
        final dataBytesHex = trimmedLine.substring(9, 25); // the first 8 data bytes
        nodeId = int.parse(dataBytesHex.substring(0, 2), radix: 16).toString();

        switch (dataBytesHex.substring(6, 8).toUpperCase()) {
          case "01":
            boardTypeStr = "Stand Alone";
            break;
          case "02":
            boardTypeStr = "RCU";
            break;
          default:
            boardTypeStr = "Unknown";
            break;
        }
      } catch (e) {
        nodeId = "0";
        boardTypeStr = "Error parsing";
      }
      break; 
    }
  }

  if (nodeId != null && boardTypeStr != null) {
    return {'nodeId': nodeId, 'boardType': boardTypeStr};
  } else {
    return {'nodeId': 'Not found', 'boardType': 'Not found'};
  }
}