/*
 * =============================================================================
 *  config_uploader.dart  -  Touchmatik Glide 1.1.0 (Agragamee, Oct-2026)
 *
 *  Sends a GUI HEX file to a TPF01-ESP-PANEL in its BLE configuration window
 *  (V0.6.0 contract C-4): '<:record>\n' per line, split at MTU-3, one line at
 *  a time, OK / ERR n token / INFO / VER answers.
 *
 *  Protocol v2 (panel firmware 0.6.0 and later): the app asks '#VER' first,
 *  the panel answers 'VER 0.6.0', every record 'OK', and the EOF record
 *  'INFO ... crc=XXXXXXXX ...' then 'OK'. The INFO crc proves that the panel
 *  stored exactly this file.
 *  Protocol v1 (other peripherals): 'OK' or 'ACK' per record and nothing
 *  else; the upload works but cannot be verified.
 *
 *  Rules (design 3.5, C8): a line is never sent twice inside one upload; any
 *  failure closes the link (the panel then abandons the upload and keeps its
 *  old program); one automatic whole-file retry for transient failures, none
 *  for file errors.
 *
 *  Once the EOF line has gone out the panel may already have stored the file
 *  (C-4.6: it stores, then answers INFO and OK). From then on (phase 'store'):
 *    - Cancel is ignored: the app waits for the panel's answer;
 *    - an INFO with a crc proves the store even if the final OK is lost;
 *    - no answer / a lost link sets upMaybeStored (outcome unknown): no
 *      automatic retry, and the UI must not say "unchanged";
 *    - a CRC mismatch means the panel stored a different program and
 *      restarts with it: 'crc', never retried automatically; the manual
 *      Retry of design 3.5 stays, and the UI says the window must be opened
 *      again first (review_glide finding 2).
 *
 *  The link is passed in (PanelLink), so the tests drive this file with a
 *  fake panel; flutter_blue_plus lives only in ble_manager.dart. The state of
 *  the running / last upload is kept in the up* variables below, which the
 *  upload dialog reads in its onProgress callback.
 * =============================================================================
 */
import 'dart:async';
import 'dart:convert';

import '../services/app_log.dart';
import '../services/hex_file_check.dart';

/// One connection to a panel's configuration service.
abstract class PanelLink {
  /// Bytes per write: ATT MTU - 3.
  int get maxWrite;

  /// True for 'KIPL-2M-' panels: send '#VER' first. Other peripherals (V3
  /// BLE modules) get protocol v1 directly; their reaction to '#VER' is unknown.
  bool get probeVersion;

  /// Each notification as trimmed text. The stream closes when the link drops.
  Stream<String> get replies;

  /// False once disconnected.
  bool get isUp;

  /// One ATT Write Request (with response) of at most [maxWrite] bytes.
  Future<void> write(List<int> bytes);

  /// Disconnects: the panel abandons an open upload. Safe to call twice.
  Future<void> close();
}

/// A connect that did not give a usable link. [reason]:
///   not-in-window  the panel is there but its configuration service is not
///                  (it is not in its configuration window)
///   bad-service    the service lacks the RX or TX characteristic
///   connect        the connection itself failed (range, GATT error)
///   no-device      no panel chosen
///   bluetooth-off  Bluetooth is off or not permitted
class LinkError implements Exception {
  final String reason;
  final String detail;
  LinkError(this.reason, [this.detail = '']);
  @override
  String toString() => detail.isEmpty ? 'LinkError($reason)' : 'LinkError($reason: $detail)';
}

// ---- timings (the panel answers a data line and the EOF in < 5 s, C-4.8)
Duration upLineTimeout = const Duration(seconds: 6);
Duration upEofTimeout = const Duration(seconds: 10);
Duration upProbeTimeout = const Duration(milliseconds: 1500);
Duration upInfoGrace = const Duration(milliseconds: 500);
Duration upRetryPause = const Duration(milliseconds: 1500);
int upAutoRetries = 1;

// ---- the running / last upload (read by the UI through onProgress)
String upPhase = ''; // connect, probe, send, store, done, failed
int upSent = 0; // records answered OK
int upTotal = 0; // ':' lines of the file, EOF included
int upAttempt = 0;
String upFirmware = ''; // '0.6.0'; '' = protocol v1
Map<String, String> upInfo = {}; // INFO keys of the stored program
String upError = ''; // firmware ERR token, or link / no-answer / bad-reply / cancelled / crc
int upErrorRecord = 0; // 1-based record of the failure (0 = before the first record)
bool upVerified = false; // INFO crc == the file's CRC-32
bool upCancel = false; // set by cancelUpload() (the UI's Cancel)
String upLinkError = ''; // LinkError.reason when upError == 'link' came from the connect
String upLinkDetail = ''; // LinkError.detail of the same (e.g. the GATT error text)
bool upEofSent = false; // the EOF line has gone out in this attempt: the panel may store the file
bool upMaybeStored = false; // failed after the EOF line without an ERR: the panel may have stored the file

/// Tokens of the file itself: never retried, automatically or by hand.
const Set<String> fileTokens = {
  'start', 'char', 'length', 'checksum', 'bytes', 'type', 'ext-address', //
  'too-many', 'after-eof', 'too-long', 'empty', 'command', 'no-eof', 'no-file',
};

/// Tokens worth one automatic retry: reconnect, probe, send from record 1.
const Set<String> transientTokens = {'link', 'no-answer', 'bad-reply', 'no-memory', 'nvs', 'timeout'};

// connect failures a retry cannot cure
const Set<String> _hopelessLinks = {'not-in-window', 'bad-service', 'no-device', 'bluetooth-off'};

bool isTransient(String token) => transientTokens.contains(token);
bool isFileToken(String token) => fileTokens.contains(token);

/// A manual Retry is offered for everything except the file's own errors
/// (design 3.5). After 'crc' or a failure with upMaybeStored the panel may
/// have restarted out of its window: the dialog says so, and the Retry then
/// works once the window is open again (or tells the user it is not).
bool retryAllowed(String token) => token.isNotEmpty && !isFileToken(token);

/// English meaning of a token (C-4.9 plus the app's own), for the log and
/// as a fallback where app_en.arb has no `err_<token>` text.
String upTokenText(String token) {
  const texts = {
    'start': 'line does not start with ":"',
    'char': 'character that is not a hex digit',
    'length': 'length does not match the length byte',
    'checksum': 'checksum error',
    'bytes': 'more than 16 data bytes',
    'type': 'unknown record type',
    'ext-address': 'address above 64 KB',
    'too-many': 'more than 2048 records',
    'too-long': 'line of 600 or more characters',
    'empty': 'no data record',
    'no-memory': 'the panel is short of memory',
    'nvs': 'the panel could not store the program',
    'timeout': 'the panel waited 30 s for the next line',
    'busy': 'the panel is busy (already stored, closing, or loading from its console)',
    'command': 'unknown command',
    'after-eof': 'data after the end-of-file record',
    'no-eof': 'the file has no end-of-file record',
    'no-file': 'the file cannot be read',
    'link': 'the Bluetooth link was lost',
    'no-answer': 'no answer from the panel',
    'bad-reply': 'an answer the app does not understand',
    'cancelled': 'cancelled',
    'crc': 'the panel stored a different program CRC',
  };
  return texts[token] ?? token;
}

// ---- notifications of the current link
final List<String> replyQueue = [];
Completer<String>? replyWaiter;
bool replyClosed = false; // the link's reply stream ended (disconnected)
Completer<void>? _pauseWaiter;

void takeReply(String text) {
  final t = text.trim();
  if (t.isEmpty) return;
  if (replyWaiter != null && !replyWaiter!.isCompleted) {
    replyWaiter!.complete(t);
  } else {
    replyQueue.add(t);
  }
}

// the reply stream closed: the link is gone, nobody needs to wait any longer
void _repliesEnded() {
  replyClosed = true;
  if (replyWaiter != null && !replyWaiter!.isCompleted) replyWaiter!.complete('');
}

/// Cancel from the UI: the running upload stops at once (the waiting is cut
/// short), closes the link and ends with 'cancelled'. In the 'store' phase
/// (the EOF line is going out or out) it is ignored: the panel may already
/// have stored the file, so the app waits for its answer instead.
void cancelUpload() {
  if (upPhase == 'store') {
    appLog('cancel ignored: the panel is storing the file');
    return;
  }
  upCancel = true;
  if (replyWaiter != null && !replyWaiter!.isCompleted) replyWaiter!.complete('');
  if (_pauseWaiter != null && !_pauseWaiter!.isCompleted) _pauseWaiter!.complete();
}

/// The next notification; '' after [limit], after a disconnect or (when
/// [cancellable], i.e. inside an upload) a cancel.
Future<String> nextReply(Duration limit, {bool cancellable = true}) async {
  if (replyQueue.isNotEmpty) return replyQueue.removeAt(0);
  if (replyClosed || (cancellable && upCancel)) return '';
  replyWaiter = Completer<String>();
  try {
    return await replyWaiter!.future.timeout(limit);
  } on TimeoutException {
    return '';
  } finally {
    replyWaiter = null;
  }
}

/// One line in the app's framing `<line>\n`, split at the link's write size
/// (the panel reassembles: write boundaries carry no meaning, C-4.4).
Future<void> sendLine(PanelLink link, String line) async {
  final packet = utf8.encode('<$line>\n');
  final size = link.maxWrite > 0 ? link.maxWrite : 20;
  var start = 0;
  while (start < packet.length) {
    final end = (start + size < packet.length) ? start + size : packet.length;
    await link.write(packet.sublist(start, end));
    start = end;
  }
}

/// The answer to a line: OK / ACK / ERR..., storing any INFO on the way;
/// '' = none in time (or the link dropped, or - when [cancellable] - a cancel).
Future<String> lineAnswer(Duration limit, {bool cancellable = true}) async {
  final end = DateTime.now().add(limit);
  while (true) {
    final left = end.difference(DateTime.now());
    if (left <= Duration.zero) return '';
    final r = await nextReply(left, cancellable: cancellable);
    if (r.startsWith('INFO')) {
      upInfo = parseInfo(r);
      appLog('panel: $r');
      continue;
    }
    if (r.startsWith('VER ')) continue; // a late answer to the probe
    return r; // '', OK, ACK, ERR ..., or something unknown
  }
}

/// 'INFO panel=5 hdr=1 crc=1A2B3C4D' -> {panel: 5, hdr: 1, crc: 1A2B3C4D}.
/// Unknown keys are kept (and ignored by the app); 'INFO none' -> {}.
Map<String, String> parseInfo(String text) {
  final info = <String, String>{};
  final words = text.trim().split(RegExp(r'\s+'));
  for (final w in words.skip(1)) {
    final eq = w.indexOf('=');
    if (eq > 0) info[w.substring(0, eq)] = w.substring(eq + 1);
  }
  return info;
}

/// 'ERR 5 checksum' -> 'checksum'.
String errToken(String text) {
  final words = text.trim().split(RegExp(r'\s+'));
  if (words.length >= 3) return words[2];
  if (words.length == 2 && int.tryParse(words[1]) == null) return words[1];
  return 'bad-reply';
}

/// 'ERR 5 checksum' -> 5; [fallback] when the panel gave no record number.
int errLine(String text, int fallback) {
  final words = text.trim().split(RegExp(r'\s+'));
  final n = words.length >= 2 ? int.tryParse(words[1]) : null;
  return (n == null || n <= 0) ? fallback : n;
}

bool failed(String token, int record, void Function() onProgress) {
  upError = token;
  upErrorRecord = record;
  upPhase = 'failed';
  appLog('upload failed: $token (${upTokenText(token)}) at record $record');
  onProgress();
  return false;
}

// a pause that a cancel cuts short
Future<void> _pause(Duration d) async {
  _pauseWaiter = Completer<void>();
  try {
    await _pauseWaiter!.future.timeout(d);
  } on TimeoutException {
    // the normal end of the pause
  } finally {
    _pauseWaiter = null;
  }
}

/// Sends one '#' command outside an upload (C-4.7) and returns the panel's
/// first answer, '' when none came within [limit] (or the link dropped).
/// Never used while an upload runs: it shares the reply queue.
Future<String> panelCommand(PanelLink link, String command, Duration limit) async {
  if (!link.isUp) return '';
  replyQueue.clear();
  replyClosed = false;
  final sub = link.replies.listen(takeReply, onDone: _repliesEnded);
  try {
    await sendLine(link, command);
    final answer = await nextReply(limit, cancellable: false); // a cancelled upload must not mute it
    appLog('$command -> ${answer.isEmpty ? '(no answer)' : answer}');
    return answer;
  } catch (e) {
    appLog('$command failed: $e');
    return '';
  } finally {
    replyQueue.clear();
    await sub.cancel();
  }
}

/// Asks a freshly connected panel for its firmware ('#VER'). Returns '0.6.0'
/// or '' (protocol v1, or not a KIPL-2M panel: then nothing is sent).
/// The connect step of ble_manager.dart uses it for "Ready - firmware 0.6.0".
Future<String> probeFirmware(PanelLink link) async {
  if (!link.probeVersion) return '';
  final answer = await panelCommand(link, '#VER', upProbeTimeout);
  return answer.startsWith('VER ') ? answer.substring(4).trim() : '';
}

/// Uploads [file]: the pre-flight result first (a refused file never opens a
/// link), then up to 1 + [upAutoRetries] attempts. True = stored (and, with
/// protocol v2, verified). [openLink] connects (or hands over the link that
/// is already open) and throws LinkError when it cannot.
Future<bool> uploadFile(HexCheck file, Future<PanelLink> Function() openLink, void Function() onProgress) async {
  var ok = false;

  upCancel = false;
  upAttempt = 0;
  upFirmware = '';
  upInfo = {};
  upSent = 0;
  upTotal = file.lines.length;
  upVerified = false;
  upLinkError = '';
  upLinkDetail = '';
  upEofSent = false;
  upMaybeStored = false;
  if (!file.ok) {
    final where = file.errorLine > 0 ? ' (file line ${file.errorLine})' : '';
    appLog('${file.name}: refused before connecting, ${file.error}$where');
    return failed(file.error, file.errorRecord, onProgress);
  }
  appLog('upload ${file.describe()}');
  for (upAttempt = 1; upAttempt <= 1 + upAutoRetries; upAttempt++) {
    ok = await uploadOnce(file, openLink, onProgress);
    if (ok || upCancel || !isTransient(upError)) break;
    if (upMaybeStored) break; // the panel may have stored the file: never send it again by itself
    if (upError == 'link' && _hopelessLinks.contains(upLinkError)) break;
    if (upAttempt == 1 + upAutoRetries) break; // keeps upAttempt = the last attempt
    appLog('transient failure ($upError): whole file again in ${upRetryPause.inMilliseconds} ms');
    await _pause(upRetryPause);
    if (upCancel) {
      failed('cancelled', 0, onProgress);
      break;
    }
  }
  if (ok) {
    appLog('upload done: $upSent/$upTotal lines, attempt $upAttempt, '
        '${upVerified ? 'verified CRC ${file.crcHex}' : 'not verified (protocol v1)'}');
  } else {
    final n = upErrorRecord;
    final where = (n >= 1 && n <= file.fileLine.length) ? ', file line ${file.fileLine[n - 1]}' : '';
    appLog('upload failed after $upAttempt attempt(s): $upError at record $n$where'
        '${upMaybeStored ? ' - the EOF line was sent, the panel may have stored the file' : ''}');
  }
  return ok;
}

// The panel has stored the file (the EOF was answered OK, or its INFO came):
// wait briefly for a late INFO, then check its CRC against the file's.
Future<bool> _storedResult(HexCheck file, void Function() onProgress) async {
  if (upInfo.isEmpty && upFirmware.isNotEmpty) {
    // INFO normally comes before the final OK; not cancellable (the panel has stored)
    final r = await nextReply(upInfoGrace, cancellable: false);
    if (r.startsWith('INFO')) {
      upInfo = parseInfo(r);
      appLog('panel: $r');
    }
  }
  if (upInfo['crc'] != null) {
    upVerified = int.tryParse(upInfo['crc']!, radix: 16) == file.crc;
    if (!upVerified) {
      appLog('CRC mismatch: panel ${upInfo['crc']}, file ${file.crcHex} - the panel stored a different program');
      return failed('crc', file.lines.length, onProgress);
    }
  }
  upPhase = 'done';
  onProgress();
  return true;
}

/// One attempt: connect, probe, every line, verify. Always closes the link.
Future<bool> uploadOnce(HexCheck file, Future<PanelLink> Function() openLink, void Function() onProgress) async {
  PanelLink link;
  StreamSubscription<String> sub;
  String answer;

  replyQueue.clear();
  replyClosed = false;
  upInfo = {};
  upSent = 0;
  upError = '';
  upErrorRecord = 0;
  upVerified = false;
  upLinkError = '';
  upLinkDetail = '';
  upFirmware = '';
  upEofSent = false;
  upMaybeStored = false;
  upTotal = file.lines.length;
  upPhase = 'connect';
  onProgress();
  appLog('attempt $upAttempt: connecting');
  try {
    link = await openLink();
  } on LinkError catch (e) {
    upLinkError = e.reason;
    upLinkDetail = e.detail;
    appLog('connect failed: $e');
    return failed('link', 0, onProgress);
  } catch (e) {
    upLinkError = 'connect';
    upLinkDetail = '$e';
    appLog('connect failed: $e');
    return failed('link', 0, onProgress);
  }
  sub = link.replies.listen(takeReply, onDone: _repliesEnded);
  try {
    if (upCancel) return failed('cancelled', 0, onProgress);
    if (link.probeVersion) {
      upPhase = 'probe';
      onProgress();
      await sendLine(link, '#VER');
      answer = await nextReply(upProbeTimeout);
      upFirmware = answer.startsWith('VER ') ? answer.substring(4).trim() : '';
      replyQueue.clear(); // a v1 peripheral's stray answer
      appLog(upFirmware.isEmpty ? 'no VER answer: protocol v1' : 'panel firmware $upFirmware (protocol v2)');
    }
    upPhase = 'send';
    onProgress();
    for (var i = 0; i < file.lines.length; i++) {
      final last = i == file.lines.length - 1;
      if (upCancel) return failed('cancelled', i + 1, onProgress);
      if (!link.isUp) return failed('link', i + 1, onProgress);
      if (last) {
        // from here on the panel may store the file: Cancel is ignored (cancelUpload)
        upPhase = 'store';
        onProgress();
        upEofSent = true;
      }
      await sendLine(link, file.lines[i]);
      answer = await lineAnswer(last ? upEofTimeout : upLineTimeout, cancellable: !last);
      if (upCancel && !last) return failed('cancelled', i + 1, onProgress);
      if (answer == 'OK' || answer == 'ACK') {
        upSent = i + 1;
        if (upSent == 1 || upSent % 64 == 0 || last) appLog('record $upSent/$upTotal answered $answer');
        onProgress();
        continue;
      }
      if (answer.startsWith('ERR')) {
        // a refusal, also of the EOF: the panel abandoned the upload, its program is unchanged (C-4.6)
        appLog('panel: $answer');
        return failed(errToken(answer), errLine(answer, i + 1), onProgress);
      }
      if (last && upInfo['crc'] != null) {
        // the final OK was lost, but the panel sends INFO only after it has stored the file
        appLog('no final OK (${answer.isEmpty ? 'none' : '"$answer"'}), but the panel reported INFO: stored');
        upSent = i + 1;
        onProgress();
        return await _storedResult(file, onProgress);
      }
      if (last) upMaybeStored = true;
      if (answer.isEmpty && (!link.isUp || replyClosed)) return failed('link', i + 1, onProgress);
      if (answer.isNotEmpty) appLog('panel: unexpected "$answer"');
      return failed(answer.isEmpty ? 'no-answer' : 'bad-reply', i + 1, onProgress);
    }
    return await _storedResult(file, onProgress);
  } catch (e) {
    appLog('link error: $e');
    if (upEofSent) {
      if (upInfo['crc'] != null) return await _storedResult(file, onProgress); // INFO: it was stored
      upMaybeStored = true;
    }
    return failed('link', upSent + 1, onProgress); // a write error or a dropped link
  } finally {
    // Always close. After a success the panel would disconnect ~1 s later
    // anyway; after a failure the close makes it abandon the upload (C8).
    await sub.cancel();
    try {
      await link.close();
    } catch (e) {
      appLog('close: $e');
    }
  }
}
