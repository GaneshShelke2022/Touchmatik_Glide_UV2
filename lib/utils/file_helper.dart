/*
 * =============================================================================
 *  file_helper.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  Where the app keeps its TXT and HEX files.
 *
 *  V1.1.0 (M10): one function for the folder instead of a hard-coded path in
 *  every file. Android keeps the public Documents folder of 1.0.0 (installers
 *  copy the files from there); other platforms use the app's documents folder.
 *  Every writer also takes an output folder, so tests write to build/test_tmp.
 * =============================================================================
 */
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String androidDocumentsDir = '/storage/emulated/0/Documents';

// the folder for TXT and HEX files, created when missing
Future<String> appDocumentsDir() async {
  final Directory directory =
      Platform.isAndroid ? Directory(androidDocumentsDir) : await getApplicationDocumentsDirectory();
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory.path;
}

class FileHelper {
  // <outputDir or the documents folder>/<name of the TXT>.hex (the file itself is not created)
  static Future<File> createHexFile(String txtPath, {String? outputDir}) async {
    final directory = Directory(outputDir ?? await appDocumentsDir());
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final filename = p.basenameWithoutExtension(txtPath);
    return File(p.join(directory.path, '$filename.hex'));
  }
}
