/*
 * =============================================================================
 *  fake_panel.dart  -  Touchmatik Glide 1.1.0 test support (Agragamee, Oct-2026)
 *
 *  A TPF01-ESP-PANEL configuration window in Dart, for uploader_test.dart.
 *  It is an independent port of the firmware rules (V0.6.0 contract C-4.4 to
 *  C-4.9), written from net_cfgwin.c / hex_record.c / config_store.c and not
 *  from the app's own hex_file_check.dart, so a mistake in the app is not
 *  copied into its test:
 *    - the line assembler: '<' ':' '#' start a line, '>' CR LF end it, write
 *      boundaries mean nothing, a line of 600+ characters is "too-long";
 *    - the dispatcher: '#' = command, ':' = record, anything else "start";
 *    - hex_record_parse() and config_store_line() acceptance with the
 *      firmware's ERR tokens; the first ':' line opens an upload, any ERR or
 *      a disconnect abandons it, the EOF record stores it (INFO, then OK);
 *    - #VER / #INFO / #CLOSE;
 *    - notifications truncated to MTU-3 (= maxWrite); INFO in its long form
 *      only when it fits, else 'INFO crc=XXXXXXXX'.
 *  Knobs make it misbehave the ways a real link does: a refused line, a lost
 *  answer, a dropped link, protocol v1, a wrong CRC, a link lost just after
 *  the store (fix_glide: dropLinkAtStore).
 * =============================================================================
 */
import 'dart:async';
import 'dart:convert';

import 'package:progswitches/comporotocol/config_uploader.dart';

/// One upload as the fake panel saw it.
class FakeUpload {
  int lines = 0; // ':' lines received in this upload
  String result = 'open'; // open, stored, abandoned
  String why = '';
  @override
  String toString() => 'FakeUpload($lines lines, $result${why.isEmpty ? '' : ': $why'})';
}

class FakePanel {
  // ---- knobs
  int maxWrite; // ATT MTU - 3: biggest write accepted, longest notification
  String name; // advertised name: 'KIPL-2M-...' makes the uploader probe #VER
  int failAtLine; // > 0: answer 'ERR n <failToken>' to upload line n (and abandon)
  String failToken;
  int failTimes; // ... in this many uploads (-1 = always)
  int dropAnswerAt; // > 0: the answer to upload line n is lost (the line itself is taken)
  int dropAnswerTimes; // ... in this many uploads (-1 = always)
  int disconnectAt; // > 0: the link drops when upload line n arrives
  int disconnectTimes; // ... in this many uploads (-1 = always)
  bool v1Mode; // protocol v1: 'OK' per accepted line and nothing else
  bool legacyAck; // 'ACK' instead of 'OK' (v1 peripherals)
  bool wrongCrc; // INFO reports a CRC that is one off
  Duration answerDelay; // time from a line to its notification
  Duration? dropAfterStored; // the panel disconnects this long after the final OK
  bool dropLinkAtStore; // the link is lost right after the EOF is stored, before INFO and OK go out
  String firmware;
  String wifiStored; // INFO wifi=
  String meshVerdict; // INFO mesh=
  void Function(int line)? onLine; // called when upload line n arrives (tests: cancel)

  // ---- what happened (all connections)
  final List<List<int>> writes = []; // every write, in order
  final List<String> lines = []; // every assembled line, in order
  final List<String> notifications = []; // every notification as sent
  final List<FakeUpload> uploads = [];
  int connects = 0;
  int closeCalls = 0;
  int subscriptionCount = 0; // reply-stream listeners right now
  int maxSubscriptions = 0;
  DateTime? lastErrAt; // when the last ERR notification was sent

  // ---- the stored program: 19-byte records [addr hi][addr lo][len][16 data]
  List<List<int>> stored = [];
  int storedCrc = 0;

  // ---- the window
  FakeLink? _link;
  String _state = 'waiting'; // waiting, connected, loading, stored, closing
  final StringBuffer _line = StringBuffer();
  bool _lineLong = false;
  FakeUpload? _upload;
  List<List<int>> _records = [];
  int _extended = 0;
  bool _eof = false;

  FakePanel({
    this.maxWrite = 244,
    this.name = 'KIPL-2M-79C846',
    this.failAtLine = 0,
    this.failToken = 'checksum',
    this.failTimes = -1,
    this.dropAnswerAt = 0,
    this.dropAnswerTimes = 1,
    this.disconnectAt = 0,
    this.disconnectTimes = -1,
    this.v1Mode = false,
    this.legacyAck = false,
    this.wrongCrc = false,
    this.answerDelay = const Duration(milliseconds: 2),
    this.dropAfterStored,
    this.dropLinkAtStore = false,
    this.firmware = '0.6.0',
    this.wifiStored = '0',
    this.meshVerdict = 'none',
    this.onLine,
  });

  bool get isConnected => _link != null && _link!._up;

  /// The uploader's openLink: a new connection (the panel accepts one phone).
  Future<PanelLink> connect() async {
    await Future<void>.delayed(Duration.zero);
    if (_link != null && _link!._up) _disconnect('second phone');
    connects++;
    final link = FakeLink._(this);
    _link = link;
    _state = 'connected';
    _line.clear();
    _lineLong = false;
    return link;
  }

  /// The ':' lines (records) received, over all uploads.
  List<String> get recordLines => lines.where((l) => l.startsWith(':')).toList();

  // ---------------------------------------------------------------------------
  //  notifications
  // ---------------------------------------------------------------------------
  void _notify(String text) {
    final link = _link;
    if (link == null || !link._up) return;
    final sent = text.length > maxWrite ? text.substring(0, maxWrite) : text; // MTU-3
    notifications.add(sent);
    if (sent.startsWith('ERR')) lastErrAt = DateTime.now();
    Timer(answerDelay, () {
      if (link._up) link._emit(sent);
    });
  }

  void _ok() => _notify(legacyAck ? 'ACK' : 'OK');

  void _err(int n, String token) {
    if (v1Mode) return; // a v1 peripheral says nothing on an error
    _notify('ERR $n $token');
  }

  // ---------------------------------------------------------------------------
  //  connection
  // ---------------------------------------------------------------------------
  void _disconnect(String why) {
    final link = _link;
    _abandon(why);
    _state = 'waiting';
    if (link != null) link._down();
  }

  void _abandon(String why) {
    final up = _upload;
    if (up != null && up.result == 'open') {
      up.result = 'abandoned';
      up.why = why;
    }
    _upload = null;
    if (_state == 'loading') _state = 'connected';
  }

  // ---------------------------------------------------------------------------
  //  line assembler (net_cfgwin.c take_bytes)
  // ---------------------------------------------------------------------------
  void _take(List<int> bytes) {
    for (final b in bytes) {
      final c = String.fromCharCode(b);
      if (c == '<' || c == ':' || c == '#') {
        if (_line.isNotEmpty || _lineLong) _lineDone();
        if (c == '<') continue;
      }
      if (c == '>' || c == '\n' || c == '\r') {
        if (_line.isNotEmpty || _lineLong) _lineDone();
        continue;
      }
      if (_line.length < 600 - 1) {
        _line.write(c);
      } else {
        _lineLong = true;
      }
    }
  }

  int _lineIndex(String line) {
    if (_upload != null) return _upload!.lines + 1;
    return line.startsWith(':') ? 1 : 0;
  }

  // dispatcher (net_cfgwin.c line_done)
  void _lineDone() {
    final line = _line.toString();
    final long = _lineLong;
    _line.clear();
    _lineLong = false;
    lines.add(line);
    if (_state == 'stored' || _state == 'closing') {
      _err(_lineIndex(line), 'busy');
    } else if (long) {
      _err(_lineIndex(line), 'too-long');
      _abandon('line too long');
    } else if (line.startsWith('#')) {
      _command(line);
    } else if (line.startsWith(':')) {
      _feed(line);
    } else {
      _err(_lineIndex(line), 'start');
      _abandon("line without ':'");
    }
  }

  void _command(String line) {
    if (v1Mode) return; // v1: commands are not understood and not answered
    switch (line) {
      case '#VER':
        _notify('VER $firmware');
        break;
      case '#INFO':
        _notify(stored.isEmpty ? 'INFO none' : _info());
        break;
      case '#CLOSE':
        _notify('OK');
        _abandon('closed');
        _state = 'closing';
        Timer(answerDelay * 2, () => _disconnect('window closed'));
        break;
      default:
        _err(0, 'command');
    }
  }

  // ---------------------------------------------------------------------------
  //  one record line (net_cfgwin.c feed_line + config_store_line / _end)
  // ---------------------------------------------------------------------------
  void _feed(String line) {
    if (_upload == null) {
      _upload = FakeUpload();
      uploads.add(_upload!);
      _records = [];
      _extended = 0;
      _eof = false;
      _state = 'loading';
    }
    final upload = _upload!;
    upload.lines++;
    final n = upload.lines;
    onLine?.call(n);

    if (disconnectAt == n && disconnectTimes != 0) {
      if (disconnectTimes > 0) disconnectTimes--;
      _disconnect('link dropped at line $n');
      return;
    }
    if (failAtLine == n && failTimes != 0) {
      if (failTimes > 0) failTimes--;
      _err(n, failToken);
      _abandon('ERR $n $failToken');
      return;
    }
    var drop = false;
    if (dropAnswerAt == n && dropAnswerTimes != 0) {
      if (dropAnswerTimes > 0) dropAnswerTimes--;
      drop = true;
    }

    final token = _storeLine(line);
    if (token.isNotEmpty) {
      _err(n, token);
      _abandon('ERR $n $token');
      return;
    }
    if (!_eof) {
      if (!drop) _ok();
      return;
    }
    // EOF: store the whole file (config_store_end), INFO before the OK
    _upload = null;
    if (_records.isEmpty) {
      upload.result = 'abandoned';
      upload.why = 'empty';
      _state = 'connected';
      _err(n, 'empty');
      return;
    }
    stored = _records;
    storedCrc = _crc32(stored.expand((r) => r).toList());
    upload.result = 'stored';
    _state = 'stored';
    if (dropLinkAtStore) {
      _disconnect('link lost after the store'); // stored, but the phone hears nothing
      return;
    }
    if (!v1Mode && !legacyAck) _notify(_info());
    if (!drop) _ok();
    final after = dropAfterStored;
    if (after != null) {
      Timer(answerDelay + after, () {
        if (_state == 'stored') _disconnect('restart after the stored program');
      });
    }
  }

  // hex_record_parse() + config_store_line(): '' = accepted
  String _storeLine(String line) {
    // leading blanks skipped, the record ends at the first blank
    final text = line.replaceFirst(RegExp(r'^[ \t]+'), '').split(RegExp(r'[ \t\r\n]')).first;
    if (!text.startsWith(':')) return 'start';
    final chars = text.length - 1;
    if (chars < 10 || chars.isOdd) return 'length';
    final count = chars ~/ 2;
    if (count > 4 + 255 + 1) return 'length';
    if (RegExp(r'[^0-9A-Fa-f]').hasMatch(text.substring(1))) return 'char';
    final bytes = <int>[];
    for (var i = 0; i < count; i++) {
      bytes.add(int.parse(text.substring(1 + 2 * i, 3 + 2 * i), radix: 16));
    }
    if (bytes[0] + 5 != count) return 'length';
    if (bytes.fold<int>(0, (s, b) => (s + b) & 0xFF) != 0) return 'checksum';
    final length = bytes[0];
    final address = (bytes[1] << 8) | bytes[2];
    final type = bytes[3];
    final data = bytes.sublist(4, 4 + length);
    if (_eof) return 'after-eof';
    switch (type) {
      case 0x00:
        if (_extended != 0) return 'ext-address';
        if (length > 16) return 'bytes';
        if (_records.length >= 2048) return 'too-many';
        _records.add([address >> 8, address & 0xFF, length, ...data, ...List<int>.filled(16 - length, 0)]);
        return '';
      case 0x01:
        _eof = true;
        return '';
      case 0x02:
      case 0x04:
        if (length != 2) return 'ext-address';
        _extended = (data[0] << 8) | data[1];
        return '';
      case 0x03:
      case 0x05:
        return '';
      default:
        return 'type';
    }
  }

  // ---------------------------------------------------------------------------
  //  INFO of the stored program (C-4.9)
  // ---------------------------------------------------------------------------
  String _info() {
    var panel = 1;
    var hdr = 0;
    for (final r in stored) {
      if (r[0] == 0 && r[1] == 0 && r[2] >= 4) {
        hdr = 1;
        panel = r[3] != 0 ? r[3] : 1;
      }
    }
    var keys = 0;
    var outputs = 0;
    var net = '00';
    for (final r in stored) {
      final data = r.sublist(3);
      if (r[0] == 0x10 + panel - 1 && r[2] == 16) {
        if (r[1] < 0x50) {
          for (var k = 0; k < 4; k++) {
            if (data.sublist(4 * k, 4 * k + 4).any((b) => b != 0)) keys++;
          }
        } else if (r[1] < 0xD0) {
          for (var k = 0; k < 2; k++) {
            if (data.sublist(8 * k, 8 * k + 8).any((b) => b != 0)) outputs++;
          }
        }
      }
      if (r[0] == 0x70 + panel - 1 && r[1] == 0x00) {
        net = data[0].toRadixString(16).toUpperCase().padLeft(2, '0');
      }
    }
    final mode = (net == '11' || net == '22') ? 'wifi' : (net == '33' ? 'mesh' : 'off');
    final crc = wrongCrc ? storedCrc ^ 1 : storedCrc;
    final crcHex = crc.toRadixString(16).toUpperCase().padLeft(8, '0');
    var text = 'INFO panel=$panel hdr=$hdr records=${stored.length} crc=$crcHex keys=$keys '
        'outputs=$outputs net=$net mode=$mode wifi=$wifiStored mesh=$meshVerdict';
    if (mode == 'wifi') text += ' ap=provisioning-79C846';
    return text.length <= maxWrite ? text : 'INFO crc=$crcHex';
  }

  static int _crc32(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c ^= b;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
      }
    }
    return c ^ 0xFFFFFFFF;
  }
}

/// One connection to the fake panel.
class FakeLink implements PanelLink {
  final FakePanel panel;
  bool _up = true;
  final StreamController<String> _replies = StreamController<String>.broadcast();

  FakeLink._(this.panel);

  @override
  int get maxWrite => panel.maxWrite;

  @override
  bool get probeVersion => panel.name.startsWith('KIPL-2M-');

  @override
  bool get isUp => _up;

  // every listener is counted while it listens (subscriptionCount)
  @override
  Stream<String> get replies => Stream<String>.multi((c) {
        var counted = true;
        panel.subscriptionCount++;
        if (panel.subscriptionCount > panel.maxSubscriptions) panel.maxSubscriptions = panel.subscriptionCount;
        void uncount() {
          if (counted) {
            counted = false;
            panel.subscriptionCount--;
          }
        }

        final sub = _replies.stream.listen(c.add, onDone: () {
          uncount();
          c.close();
        });
        c.onCancel = () {
          uncount();
          return sub.cancel();
        };
      });

  @override
  Future<void> write(List<int> bytes) async {
    if (!_up) throw StateError('fake panel: not connected');
    if (bytes.length > panel.maxWrite) {
      throw StateError('fake panel: write of ${bytes.length} B > ${panel.maxWrite} B');
    }
    panel.writes.add(List<int>.of(bytes));
    panel._take(bytes);
    await Future<void>.delayed(Duration.zero); // the ATT Write Response
  }

  @override
  Future<void> close() async {
    panel.closeCalls++;
    if (_up && identical(panel._link, this)) panel._disconnect('phone disconnected');
    _down();
  }

  void _emit(String text) {
    if (_up && !_replies.isClosed) _replies.add(text);
  }

  void _down() {
    if (!_up) return;
    _up = false;
    _replies.close();
  }

  /// The write of [text] as the uploader frames it.
  static List<int> framed(String text) => utf8.encode('<$text>\n');
}
