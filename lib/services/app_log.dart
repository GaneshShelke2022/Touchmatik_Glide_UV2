/*
 * =============================================================================
 *  app_log.dart  -  Touchmatik Glide 1.1.0 (Agragamee, Oct-2026)
 *
 *  The app's own debug log. The phone has no console the installer can read,
 *  so the BLE uploader (and, from main.dart, every debugPrint) writes here:
 *  the last 2000 lines, each with a time stamp, kept in memory only.
 *  "Save log" in the upload dialog writes them to Documents as
 *  glide_log_<yyyyMMdd_HHmmss>.txt, to be sent along with the panel's UART
 *  log of the same bench step (design decision C15).
 *
 *  appLog() never calls debugPrint: main.dart routes debugPrint into appLog,
 *  and a call back would loop forever.
 * =============================================================================
 */
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lines kept; the oldest line is dropped when a new one would exceed this.
const int appLogMax = 2000;

/// First line of a saved log. main.dart may put the About text here
/// (`appLogHeader = kAppAbout;`) so a saved log names the app version.
String appLogHeader = 'Touchmatik Glide';

/// Also print every line on the developer console (debug runs only; off by
/// default because main.dart already prints what it routes through debugPrint).
bool appLogEcho = false;

final Queue<String> _lines = Queue<String>();

String _two(int v) => v.toString().padLeft(2, '0');
String _three(int v) => v.toString().padLeft(3, '0');

// "14:03:27.512" - the date is in the saved file's name and header
String _clock(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${_three(t.millisecond)}';

/// Adds [text] to the log. A text with several lines becomes several log
/// lines, each with the same time stamp; empty lines are skipped.
void appLog(String text) {
  final stamp = _clock(DateTime.now());
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    _lines.addLast('$stamp $line');
    while (_lines.length > appLogMax) {
      _lines.removeFirst();
    }
    if (appLogEcho) {
      // ignore: avoid_print
      print('[glide] $line');
    }
  }
}

/// A copy of the kept lines, oldest first.
List<String> appLogLines() => List<String>.unmodifiable(_lines);

/// Empties the log (tests; the app never needs it).
void appLogClear() => _lines.clear();

/// The file name of a log saved at [t]: glide_log_20261015_140327.txt
String appLogFileName(DateTime t) =>
    'glide_log_${t.year}${_two(t.month)}${_two(t.day)}_'
    '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}.txt';

// The folder the TXT and HEX files go to (as 1.0.0 and file_helper.dart):
// the shared Documents folder on Android, the app's documents folder elsewhere.
Future<Directory> _documentsDir() async {
  if (Platform.isAndroid) {
    return Directory('/storage/emulated/0/Documents');
  }
  return getApplicationDocumentsDirectory();
}

/// Writes the log to [dir] (default: Documents) and returns the file's path.
/// Throws a FileSystemException when the folder cannot be written; the
/// caller shows that to the user.
Future<String> saveAppLog({String? dir, DateTime? now}) async {
  final when = now ?? DateTime.now();
  final folder = dir != null ? Directory(dir) : await _documentsDir();
  if (!await folder.exists()) {
    await folder.create(recursive: true);
  }
  final path = p.join(folder.path, appLogFileName(when));
  final text = StringBuffer()
    ..writeln(appLogHeader)
    ..writeln('Log saved ${when.year}-${_two(when.month)}-${_two(when.day)} '
        '${_clock(when)}, ${_lines.length} lines')
    ..writeln('----');
  for (final line in _lines) {
    text.writeln(line);
  }
  await File(path).writeAsString(text.toString(), flush: true);
  appLog('log saved to $path');
  return path;
}
