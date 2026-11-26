/*
 * =============================================================================
 *  convert_manager.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  TXT configuration -> GUI HEX file (V0.6.0 contract C-5.1), in this order:
 *    1. header 0x0000 [panel][00][00][board]  - always line 1 (B1)
 *    2. keys and outputs        (panel_th.dart)
 *    3. inputs                  (in_main_th.dart)
 *    4. scenes                  (scene_th.dart)
 *    5. network page 0x00-0x9F  (bms_info_th.dart)
 *    6. DP map 0xA0-0xFF        (wifi_conn_th.dart)
 *    7. EOF :00000001FF
 *  The file is written as <name>.hex.part and renamed only when every
 *  converter succeeded; on any error the .part is deleted and the error
 *  (ConfigRangeError for a value that does not fit) is rethrown (M4, C4).
 * =============================================================================
 */
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/file_helper.dart';
import 'hex_tools.dart';
import 'panel_th.dart';
import 'in_main_th.dart';
import 'scene_th.dart';
import 'bms_info_th.dart';
import 'wifi_conn_th.dart';

class ConvertManager {
  static const String eofRecord = ':00000001FF';

  // the records of a TXT configuration, header first and EOF last (no file I/O)
  static List<String> hexLinesOfTxt(List<String> txtLines, {String boardType = 'STANDALONE'}) {
    final panel = txtPanelNumber(txtLines);
    return [
      headerRecord(panel, boardByteOf(boardType)),
      ...PanelCombinedTH.records(txtLines),
      ...InMainTH.records(txtLines),
      ...SceneTH.records(txtLines),
      ...BMSInfoTH.records(txtLines),
      ...WIFIConnTH.records(txtLines),
      eofRecord,
    ];
  }

  // TXT file -> <outputDir or the documents folder>/<name>.hex; returns its path
  static Future<String> convertTxtToHex(String txtPath, {String boardType = 'STANDALONE', String? outputDir}) async {
    debugPrint('Starting TXT to HEX conversion for: $txtPath ($boardType)');
    final hexFile = await FileHelper.createHexFile(txtPath, outputDir: outputDir);
    final partFile = File('${hexFile.path}.part');
    try {
      final txtLines = await File(txtPath).readAsLines();
      final lines = hexLinesOfTxt(txtLines, boardType: boardType);
      await partFile.writeAsString(lines.map((l) => '$l\n').join(), flush: true);
      if (await hexFile.exists()) {
        await hexFile.delete();
      }
      await partFile.rename(hexFile.path);
    } catch (e) {
      debugPrint('TXT to HEX conversion failed: $e');
      try {
        if (await partFile.exists()) await partFile.delete();
      } catch (_) {}
      rethrow;
    }
    debugPrint('Conversion complete. HEX file saved at: ${hexFile.path}');
    return hexFile.path;
  }
}
