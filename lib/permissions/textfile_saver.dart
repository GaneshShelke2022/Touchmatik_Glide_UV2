/*
 * =============================================================================
 *  textfile_saver.dart  -  Touchmatik Glide V1.1.0 (Agragamee, Oct-2026)
 *  Saves the configuration TXT.
 *
 *  V1.1.0 (M10): the default folder comes from appDocumentsDir() (Android:
 *  the public Documents folder, as in 1.0.0; elsewhere the app's documents
 *  folder); [directoryPath] + [fileName] still choose any other place.
 *  The context is not used after an await unless it is still mounted.
 * =============================================================================
 */
import 'dart:io';
import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../utils/file_helper.dart';
import 'package:path/path.dart' as p;
import '../localization/app_localizations.dart';

Future<String?> saveTextFile(
  BuildContext context,
  String content, {
  bool showSnackBar = true,
  String? directoryPath, // with fileName: save exactly there
  String? fileName,
}) async {
  try {
    String finalDirectoryPath;
    String finalFileName;

    if (directoryPath != null && fileName != null) {
      finalDirectoryPath = directoryPath;
      finalFileName = fileName;
    } else {
      finalDirectoryPath = await appDocumentsDir();
      finalFileName = AppDataManager().customerName?.isNotEmpty == true
          ? '${AppDataManager().customerName}.txt'
          : 'Configuration.txt';
    }

    final fullFilePath = p.join(finalDirectoryPath, finalFileName);
    final file = File(fullFilePath);

    // Ensure the directory exists
    await file.parent.create(recursive: true);

    await file.writeAsString(content);

    if (showSnackBar && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).t('file_saved_to', params: {'path': fullFilePath})),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    return fullFilePath;
  } catch (e) {
    if (showSnackBar && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).t('error_saving_file', params: {'error': e.toString()})),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ),
      );
    }
    return null;
  }
}
