// widget_test.dart - Touchmatik Glide 1.1.0 (Agragamee, Oct-2026)
// The page tests of package GA-3 (V0.6.0 design 5.4), replacing 1.0.0's
// counter smoke test, which never matched this app:
//   W1   the About line is on the login page; clearing SW-02 keeps SW-03
//        (label and function)
//   W2   deleting OD-02 and adding a row gives OD-02 again; Add stops at 16
//   B2   the panel number is required and is the one used by the input and
//        network pages; B5 the valve keeps its TXT spelling; M8 / B8 the
//        network page; 3.6 the upload dialog against the fake panel and the
//        INFO hints; the English texts every token / hint / link state needs.
// fix_glide (review_glide): Cancel is off once the EOF line is out; a failure
// after it says "may have stored", a CRC mismatch "stored a different
// program"; Retry / Save log wait for "Exit configuration mode"; no Exit for
// a device without a KIPL-2M name; the Panel page keeps unknown functions;
// every text key the code uses exists; M6 in every language.
//
// google_fonts fetches its fonts over HTTP; in a widget test the binding
// answers 400 and google_fonts turns that into a test failure. The overrides
// below make every HTTP request wait forever instead, so the pages render
// with the fallback font and nothing leaves the PC.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:progswitches/app_version.dart';
import 'package:progswitches/comporotocol/ble_manager.dart';
import 'package:progswitches/comporotocol/config_uploader.dart';
import 'package:progswitches/data/app_data.dart';
import 'package:progswitches/localization/app_localizations.dart';
import 'package:progswitches/login/login_view.dart';
import 'package:progswitches/main.dart' show installAppLog;
import 'package:progswitches/services/app_log.dart';
import 'package:progswitches/services/hex_file_check.dart';
import 'package:progswitches/ui/pages/configuration_page.dart';
import 'package:progswitches/ui/pages/connectivity_page.dart';
import 'package:progswitches/ui/pages/input_assign_page.dart';
import 'package:progswitches/ui/pages/panel_switch_assign_page.dart';
import 'package:progswitches/ui/pages/preview_page.dart';
import 'package:progswitches/ui/pages/relay_output_page.dart';
import 'package:progswitches/ui/pages/scene_assign_page.dart';
import 'package:progswitches/ui/widgets/add_new_row_button.dart';

import 'support/fake_panel.dart';

// ---- no network in tests (google_fonts) -------------------------------------
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _SilentHttpClient();
}

class _SilentHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ---- helpers -----------------------------------------------------------------
Future<void> pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // AppLocalizations reads app_en.arb through rootBundle: real file I/O, which
  // fake time never waits for. Read it once for real (rootBundle caches it),
  // then give the delegate real time until the page is there (loop below).
  await tester.runAsync(() => rootBundle.loadString('assets/lang/app_en.arb'));
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: page,
  ));
  // the delegate's asset read completes outside fake time: give it real time until the page is there
  for (var i = 0; i < 50 && find.byType(Text).evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

// the dropdowns of one row (keyed container), in screen order
List<DropdownButton<String>> rowDropdowns(WidgetTester tester, String rowKey) => tester
    .widgetList<DropdownButton<String>>(
        find.descendant(of: find.byKey(ValueKey(rowKey)), matching: find.byType(DropdownButton<String>)))
    .toList();

String rowText(WidgetTester tester, String rowKey, [int index = 0]) => tester
    .widgetList<TextField>(find.descendant(of: find.byKey(ValueKey(rowKey)), matching: find.byType(TextField)))
    .elementAt(index)
    .controller!
    .text;

Map<String, dynamic> englishArb() =>
    jsonDecode(File('assets/lang/app_en.arb').readAsStringSync()) as Map<String, dynamic>;

List<String> hintKeys(List<UploadHint> hints) => hints.map((h) => h.key).toList();

// a BLEManager whose upload goes to the fake panel through the real uploader
class _FakeBleManager extends BLEManager {
  final FakePanel panel;
  Completer<bool>? exitAnswer; // set: "Exit configuration mode" waits for it
  int exitCalls = 0;
  _FakeBleManager(this.panel) {
    linkDeviceName = panel.name;
  }

  @override
  Future<bool> upload({HexCheck? file, void Function()? onProgress}) =>
      uploadFile(file!, panel.connect, () => onProgress?.call());

  @override
  Future<bool> exitConfigMode() {
    exitCalls++;
    return exitAnswer?.future ?? Future<bool>.value(true);
  }
}

Future<void> openUploadDialog(WidgetTester tester, BLEManager manager, HexCheck file) async {
  await pumpPage(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => UploadDialog(manager: manager, file: file),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

// One step of the upload: the fake panel's and the uploader's timers run in
// fake time (pump), but a few dart:async futures (a cancelled subscription's
// "done") complete in the root zone, whose microtasks only run when the real
// event loop gets a turn (runAsync).
Future<void> uploadStep(WidgetTester tester, [Duration step = const Duration(milliseconds: 20)]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump(step);
}

// lets the upload run until the dialog shows its result
Future<void> runUpload(WidgetTester tester) async {
  for (var i = 0; i < 400 && find.byKey(const ValueKey('upload_close')).evaluate().isEmpty; i++) {
    await uploadStep(tester);
  }
  await tester.pump(const Duration(seconds: 1)); // late notifications of the fake panel
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = _NoNetwork();
    // short uploader limits, as in uploader_test.dart (the fake panel answers in 2 ms)
    upLineTimeout = const Duration(milliseconds: 200);
    upEofTimeout = const Duration(milliseconds: 300);
    upProbeTimeout = const Duration(milliseconds: 100);
    upInfoGrace = const Duration(milliseconds: 50);
    upRetryPause = const Duration(milliseconds: 50);
  });

  setUp(() => AppDataManager().clear());

  // ---------------------------------------------------------------- W1
  group('W1', () {
    testWidgets('the About line is on the login page', (tester) async {
      await pumpPage(tester, const LoginView());
      expect(find.text(kAppAbout), findsOneWidget);
      expect(kAppAbout, 'Touchmatik Glide 1.1.0 (build 2) - BLE protocol v2 - for TPF01-ESP-PANEL 0.6.0 and later');
    });

    testWidgets('clearing SW-02 keeps SW-03 (label and function)', (tester) async {
      final d = AppDataManager();
      d.panelSwitchPanel = 'Panel-05';
      d.panelSwitchModule = '2M';
      d.panelSwitchRows = [
        {'function': 'LAMP', 'number': '1'},
        {'function': 'BELL', 'number': '2'},
        {'function': 'FAN-UP', 'number': '3'},
      ];
      await pumpPage(tester, const PanelSwitchAssignPage());
      expect(find.text('SW-05'), findsOneWidget); // 2M: 5 key rows
      expect(rowDropdowns(tester, 'sw1-0').single.value, 'BELL');

      await tester.tap(find.byKey(const ValueKey('sw_clear_1')));
      await tester.pumpAndSettle();

      // SW-02: empty, under a new widget key (its dropdown forgot BELL)
      expect(find.byKey(const ValueKey('sw1-0')), findsNothing);
      expect(rowDropdowns(tester, 'sw1-1').single.value, isNull);
      expect(rowText(tester, 'sw1-1'), '');
      expect(find.descendant(of: find.byKey(const ValueKey('sw1-1')), matching: find.text('SW-02')), findsOneWidget);
      // SW-03: same label, same function and number
      expect(find.descendant(of: find.byKey(const ValueKey('sw2-0')), matching: find.text('SW-03')), findsOneWidget);
      expect(rowDropdowns(tester, 'sw2-0').single.value, 'FAN-UP');
      expect(rowText(tester, 'sw2-0'), '3');
      expect(find.text('SW-05'), findsOneWidget); // no row was removed

      // Next keeps the rows by position: the TXT writes SW-01 and SW-03, no SW-02
      await tester.tap(find.byKey(const ValueKey('panel_next')));
      await tester.pumpAndSettle();
      expect(find.byType(RelayOutputPage), findsOneWidget);
      expect(d.panelSwitchRows.length, 5);
      expect(d.panelSwitchRows[0], {'function': 'LAMP', 'number': '1'});
      expect(d.panelSwitchRows[1], {'function': null, 'number': ''});
      expect(d.panelSwitchRows[2], {'function': 'FAN-UP', 'number': '3'});
    });

    testWidgets('a key number is digits only', (tester) async {
      AppDataManager().panelSwitchPanel = 'Panel-01';
      await pumpPage(tester, const PanelSwitchAssignPage());
      final field = find.descendant(of: find.byKey(const ValueKey('sw0-0')), matching: find.byType(TextField));
      await tester.enterText(field, '1a2-34');
      await tester.pump();
      expect(rowText(tester, 'sw0-0'), '123'); // digits only, at most 3
    });

    // fix_glide, review_glide finding 7: the page dropped such a function, so
    // the key went out as action 00 (the other pages keep unknown values)
    testWidgets('review 7: a key function the list does not offer (SCENE-OFF) is kept', (tester) async {
      final d = AppDataManager();
      d.panelSwitchPanel = 'Panel-05';
      d.panelSwitchModule = '2M';
      d.panelSwitchRows = [
        {'function': 'LAMP', 'number': '1'},
        {'function': 'SCENE-OFF', 'number': '4'},
        {'function': 'DND-STATUS', 'number': ''},
      ];
      await pumpPage(tester, const PanelSwitchAssignPage());
      expect(rowDropdowns(tester, 'sw1-0').single.value, 'SCENE-OFF');
      expect(rowDropdowns(tester, 'sw2-0').single.value, 'DND-STATUS');
      expect(find.text('SCENE-OFF'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('panel_next')));
      await tester.pumpAndSettle();
      expect(find.byType(RelayOutputPage), findsOneWidget);
      expect(d.panelSwitchRows[1], {'function': 'SCENE-OFF', 'number': '4'});
      expect(d.panelSwitchRows[2], {'function': 'DND-STATUS', 'number': ''});
    });
  });

  // ---------------------------------------------------------------- B2
  group('B2 one panel number', () {
    testWidgets('the Panel page does not go on without a panel', (tester) async {
      await pumpPage(tester, const PanelSwitchAssignPage());
      await tester.tap(find.byKey(const ValueKey('panel_next')));
      await tester.pumpAndSettle();
      expect(find.text('Choose the panel number (Panel-01 to Panel-48)'), findsOneWidget);
      expect(find.byType(RelayOutputPage), findsNothing);
    });

    testWidgets('Next on the Panel page sets the panel of inputs and network page', (tester) async {
      final d = AppDataManager();
      d.panelSwitchPanel = 'Panel-07';
      d.inputAssignPanel = 'Panel-03';
      d.wifiPanel = 'Panel-01';
      await pumpPage(tester, const PanelSwitchAssignPage());
      await tester.tap(find.byKey(const ValueKey('panel_next')));
      await tester.pumpAndSettle();
      expect(d.panelSwitchPanel, 'Panel-07');
      expect(d.inputAssignPanel, 'Panel-07');
      expect(d.wifiPanel, 'Panel-07');
    });

    testWidgets('inputs: the panel is read-only, TOGGLE is offered, 4 rows at most', (tester) async {
      final d = AppDataManager();
      d.panelSwitchPanel = 'Panel-05';
      d.inputAssignPanel = 'Panel-03'; // an old value: the page shows and stores the Panel page's panel
      await pumpPage(tester, const InputAssignPage());
      expect(find.text('Panel-05 (set on the Panel Switch Assign page)'), findsOneWidget);
      expect(find.text('IP-04'), findsOneWidget);
      // type, input state, output device, output state, default state
      final outputState = rowDropdowns(tester, 'ip_row_IP-01')[3];
      expect(outputState.items!.map((i) => i.value), containsAll(['ON', 'OFF', 'TOGGLE', 'ON-L-1', 'ON-L-10']));
      expect(tester.widget<IgnorePointer>(find.byKey(const ValueKey('add_row_gate'))).ignoring, isTrue);

      // delete IP-02, add: IP-02 again
      await tester.tap(find.byKey(const ValueKey('ip_delete_IP-02')));
      await tester.pumpAndSettle();
      expect(find.text('IP-02'), findsNothing);
      await tester.tap(find.byType(AddNewRowButton));
      await tester.pumpAndSettle();
      expect(find.text('IP-02'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byType(SceneAssignPage), findsOneWidget);
      expect(d.inputAssignPanel, 'Panel-05');
      expect(d.inputAssignRows.map((r) => r['sr']), ['IP-01', 'IP-02', 'IP-03', 'IP-04']);
    });
  });

  // ---------------------------------------------------------------- W2, B5
  group('W2 outputs', () {
    testWidgets('delete OD-02, add: the new row is OD-02; Add stops at 16', (tester) async {
      final d = AppDataManager();
      d.panelSwitchPanel = 'Panel-01';
      d.panelSwitchModule = '2M';
      await pumpPage(tester, const RelayOutputPage());
      expect(find.text('OD-04'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('od_delete_OD-02')));
      await tester.pumpAndSettle();
      expect(find.text('OD-02'), findsNothing);

      await tester.tap(find.byType(AddNewRowButton));
      await tester.pumpAndSettle();
      expect(find.text('OD-02'), findsOneWidget);
      expect(find.text('OD-05'), findsNothing);
      final y = [for (final l in ['OD-01', 'OD-02', 'OD-03', 'OD-04']) tester.getTopLeft(find.text(l)).dy];
      expect(y, List<double>.of(y)..sort()); // shown in OD order

      expect(tester.widget<IgnorePointer>(find.byKey(const ValueKey('add_row_gate'))).ignoring, isFalse);
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.byType(AddNewRowButton));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('OD-16'), findsOneWidget);
      expect(tester.widget<IgnorePointer>(find.byKey(const ValueKey('add_row_gate'))).ignoring, isTrue);
      expect(find.text('At most 16 rows'), findsOneWidget);
      await tester.tap(find.byType(AddNewRowButton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('OD-17'), findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      final labels = d.relayOutputRows.map((r) => r['serialNumber']).toList();
      expect(labels.length, 16);
      expect(labels.toSet().length, 16); // no duplicate label (M3)
    });

    testWidgets('B5: THERMOSTAT-VALV is shown as THERMOSTAT-VALVE and stored unchanged', (tester) async {
      final d = AppDataManager();
      d.relayOutputRows = [
        {'serialNumber': 'OD-01', 'type': 'RLY', 'output': 'THERMOSTAT-VALV', 'number': '1', 'time': ''},
      ];
      await pumpPage(tester, const RelayOutputPage());
      expect(find.text('THERMOSTAT-VALV'), findsNothing);
      expect(find.text('THERMOSTAT-VALVE'), findsWidgets);
      expect(rowDropdowns(tester, 'od_row_OD-01')[1].value, 'THERMOSTAT-VALV');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(d.relayOutputRows.single['output'], 'THERMOSTAT-VALV');
    });
  });

  // ---------------------------------------------------------------- M8, B8
  group('network page', () {
    test('M8: the DP parameters are the firmware types', () {
      expect(kDpParameters.length, 22);
      expect(kDpParameters, containsAll(['BELL', 'OCCUPANCY', 'DND', 'MMR', 'LAUNDRY', 'SCENE',
          'THERMOSTAT-ON-OFF', 'THERMOSTAT-FAN', 'THERMOSTAT-STEMP', 'THERMOSTAT-ATEMP', 'THERMOSTAT-MODE']));
      for (final notOffered in ['MASTER', 'SCENE-OFF', 'SCENE-TOGGLE', 'INPUT-TW']) {
        expect(kDpParameters, isNot(contains(notOffered)));
      }
      expect(kDpRowsMax, 24);
    });

    testWidgets('B8: a broker with a quote and a 31-character password are refused', (tester) async {
      final d = AppDataManager();
      d.panelSwitchPanel = 'Panel-05';
      d.connectivityType = 1;
      d.wifiMode = 'Mqtt-HA';
      d.wifiPanel = 'Panel-02'; // an old value: the page uses the Panel page's panel
      d.mqttBroker = 'broker"x';
      d.mqttPassword = 'p' * 31;
      d.mqttPort = '70000';
      await pumpPage(tester, const ConnectivityPage());
      expect(find.text('Panel-05 (set on the Panel Switch Assign page)'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byType(OverviewPage), findsNothing);
      expect(find.text('Printable ASCII only, no double quote (")'), findsOneWidget);
      expect(find.text('At most 30 characters'), findsOneWidget);
      expect(find.text('Port 1 to 65535'), findsOneWidget);

      // typing: the quote and the 63rd character never get in
      await tester.enterText(find.byKey(const ValueKey('mqtt_broker')), 'mqtt."example".com');
      await tester.enterText(find.byKey(const ValueKey('mqtt_password')), 'secret');
      await tester.enterText(find.byKey(const ValueKey('mqtt_port')), '1883');
      await tester.pump(const Duration(seconds: 3)); // the "fix the fields" snack bar covers the footer
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byType(OverviewPage), findsOneWidget);
      expect(d.mqttBroker, 'mqtt.example.com');
      expect(d.mqttPassword, 'secret');
      expect(d.mqttPort, '1883');
      expect(d.wifiPanel, 'Panel-05');
    });
  });

  // ---------------------------------------------------------------- configuration page
  group('configuration page', () {
    testWidgets('About; Generate checks first and refuses a configuration without a panel', (tester) async {
      await pumpPage(tester, const ConfigurationPage());
      expect(find.text('Not connected'), findsOneWidget); // link state idle, nothing "connected"
      expect(find.byKey(const ValueKey('ble_flash')), findsNothing); // no file chosen yet

      await tester.tap(find.byKey(const ValueKey('about_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about_dialog_text')), findsOneWidget);
      expect(find.text(kAppAbout), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('generate_hex')));
      await tester.pumpAndSettle();
      expect(find.text('Fix these first'), findsOneWidget);
      expect(find.textContaining('Panel number'), findsWidgets);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Fix these first'), findsNothing);
    });
  });

  // ---------------------------------------------------------------- 3.6 upload
  group('3.6 upload dialog (fake panel)', () {
    late HexCheck bench4;
    setUpAll(() {
      bench4 = HexCheck.ofText(File('test/fixtures/bench_mesh4.hex').readAsStringSync(), name: 'bench_mesh4.hex');
    });

    testWidgets('success: firmware, file line, verified CRC and the mesh hint; stays open', (tester) async {
      final panel = FakePanel();
      final manager = _FakeBleManager(panel);
      await openUploadDialog(tester, manager, bench4);
      expect(find.text('Upload to KIPL-2M-79C846'), findsOneWidget);
      await runUpload(tester);

      expect(find.text('Panel firmware 0.6.0 (protocol v2)'), findsOneWidget);
      expect(find.text('bench_mesh4.hex, Panel-01, STANDALONE, 22 records, CRC ${bench4.crcHex}'), findsOneWidget);
      expect(find.text('Record 23 / 23'), findsOneWidget);
      expect(find.text('Stored and verified: panel 1, 22 records, CRC ${bench4.crcHex}. The panel restarts now.'), findsOneWidget);
      expect(find.text('The panel restarts as a BLE Mesh node, ready to be added in Lumflux Swift.'), findsOneWidget);
      expect(upVerified, isTrue);
      expect(find.byKey(const ValueKey('upload_retry')), findsNothing);
      expect(find.byKey(const ValueKey('upload_save_log')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('upload_close')));
      await tester.pumpAndSettle();
      expect(find.byType(UploadDialog), findsNothing);
    });

    testWidgets('refused record: record, file line and token; no Retry for a file error', (tester) async {
      final panel = FakePanel(failAtLine: 5, failToken: 'checksum');
      final manager = _FakeBleManager(panel);
      await openUploadDialog(tester, manager, bench4);
      await runUpload(tester);

      expect(find.text('The panel refused record 5 (file line 5): checksum error. Its stored program is unchanged.'), findsOneWidget);
      expect(find.byKey(const ValueKey('upload_retry')), findsNothing);
      expect(find.text('Exit configuration mode'), findsOneWidget);
      expect(panel.closeCalls, greaterThan(0));
    });

    testWidgets('cancel: the panel keeps its old program; Retry is offered', (tester) async {
      final panel = FakePanel(answerDelay: const Duration(milliseconds: 60));
      final manager = _FakeBleManager(panel);
      upLineTimeout = const Duration(seconds: 2);
      addTearDown(() => upLineTimeout = const Duration(milliseconds: 200));
      await openUploadDialog(tester, manager, bench4);
      for (var i = 0; i < 40 && upSent < 3; i++) {
        await uploadStep(tester, const Duration(milliseconds: 30));
      }
      expect(find.byKey(const ValueKey('upload_cancel')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('upload_cancel')));
      await runUpload(tester);

      expect(upError, 'cancelled');
      expect(find.text('Cancelled, the panel keeps its old program.'), findsOneWidget);
      expect(find.byKey(const ValueKey('upload_retry')), findsOneWidget);
      expect(panel.uploads.every((u) => u.result != 'stored'), isTrue);
    });

    // ---- fix_glide: review_glide findings 1 to 4 ----------------------------
    testWidgets('review 1: Cancel is off once the EOF line is out; the upload ends stored', (tester) async {
      final panel = FakePanel(answerDelay: const Duration(milliseconds: 60));
      final manager = _FakeBleManager(panel);
      upLineTimeout = const Duration(seconds: 2);
      upEofTimeout = const Duration(seconds: 2);
      addTearDown(() {
        upLineTimeout = const Duration(milliseconds: 200);
        upEofTimeout = const Duration(milliseconds: 300);
      });
      await openUploadDialog(tester, manager, bench4);
      for (var i = 0; i < 400 && upPhase != 'store'; i++) {
        await uploadStep(tester, const Duration(milliseconds: 10));
      }
      await tester.pump();
      expect(upPhase, 'store', reason: 'the EOF line is out, its answer not yet in');
      final cancel = find.byKey(const ValueKey('upload_cancel'));
      expect(tester.widget<TextButton>(cancel).onPressed, isNull);
      await tester.tap(cancel, warnIfMissed: false);
      cancelUpload(); // even a direct call is ignored now
      await runUpload(tester);

      expect(upError, '');
      expect(find.text('Stored and verified: panel 1, 22 records, CRC ${bench4.crcHex}. The panel restarts now.'), findsOneWidget);
      expect(find.textContaining('Cancelled'), findsNothing);
      expect(panel.uploads.single.result, 'stored');
    });

    testWidgets('review 2: the link drops after the store: "may have stored", never "unchanged"', (tester) async {
      final panel = FakePanel(dropLinkAtStore: true);
      final manager = _FakeBleManager(panel);
      await openUploadDialog(tester, manager, bench4);
      await runUpload(tester);

      expect(upMaybeStored, isTrue);
      expect(find.text('The last line went out, but the panel\'s answer did not arrive (the Bluetooth link was lost). '
          'The panel may have stored the file and be restarting with it. If its status LED double-flashes again, '
          'it is still in configuration mode with its old program: Retry.'), findsOneWidget);
      expect(find.textContaining('unchanged'), findsNothing);
      expect(find.byKey(const ValueKey('upload_retry')), findsOneWidget);
      expect(panel.connects, 1, reason: 'no automatic retry after the EOF line');
      expect(panel.uploads.single.result, 'stored');
    });

    testWidgets('review 2: wrong CRC: the panel stored a different program, never "unchanged"', (tester) async {
      final panel = FakePanel(wrongCrc: true);
      final manager = _FakeBleManager(panel);
      await openUploadDialog(tester, manager, bench4);
      await runUpload(tester);

      expect(upError, 'crc');
      final panelCrc = upInfo['crc']!;
      expect(panelCrc, isNot(bench4.crcHex));
      expect(find.text('The panel stored a program with CRC $panelCrc, but this file has CRC ${bench4.crcHex}. '
          'The panel restarts with that program now: open its configuration window again (hold SW2+SW3 for 8 s), then Retry.'),
          findsOneWidget);
      expect(find.textContaining('unchanged'), findsNothing);
      expect(find.byKey(const ValueKey('upload_retry')), findsOneWidget); // design 3.5: a manual Retry
      expect(panel.connects, 1);

      // "Exit configuration mode" to the panel, which restarted: no answer - and still no "unchanged"
      manager.exitAnswer = Completer<bool>()..complete(false);
      await tester.tap(find.byKey(const ValueKey('upload_exit')));
      await tester.pump();
      await tester.pump();
      expect(find.text('No answer to Exit configuration mode (the Bluetooth link was lost). A panel still in '
          'configuration mode leaves it by itself when its window ends (5 minutes after it opened).'), findsOneWidget);
      expect(find.textContaining('unchanged'), findsNothing);
    });

    testWidgets('review 3: Retry and Save log wait while "Exit configuration mode" runs', (tester) async {
      final panel = FakePanel(failAtLine: 1, failToken: 'busy');
      final manager = _FakeBleManager(panel)..exitAnswer = Completer<bool>();
      await openUploadDialog(tester, manager, bench4);
      await runUpload(tester);
      final retry = find.byKey(const ValueKey('upload_retry'));
      final saveLog = find.byKey(const ValueKey('upload_save_log'));
      expect(upError, 'busy');
      expect(tester.widget<TextButton>(retry).onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('upload_exit')));
      await tester.pump();
      expect(manager.exitCalls, 1);
      expect(tester.widget<TextButton>(retry).onPressed, isNull);
      expect(tester.widget<TextButton>(saveLog).onPressed, isNull);
      expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('upload_close'))).onPressed, isNull);
      final connects = panel.connects;
      await tester.tap(retry, warnIfMissed: false);
      await uploadStep(tester);
      expect(panel.connects, connects, reason: 'no upload while #CLOSE is under way');

      manager.exitAnswer!.complete(true);
      await tester.pump();
      await tester.pump();
      expect(find.text('Sent: the panel leaves configuration mode and restarts.'), findsOneWidget);
      expect(tester.widget<TextButton>(retry).onPressed, isNotNull);
      expect(tester.widget<TextButton>(saveLog).onPressed, isNotNull);
    });

    testWidgets('review 4: no "Exit configuration mode" for a device whose real name is not KIPL-2M', (tester) async {
      for (final name in ['AA:BB:CC:DD:EE:FF', 'KIPL-2M-?']) {
        final panel = FakePanel(failAtLine: 1, failToken: 'busy');
        final manager = _FakeBleManager(panel)..linkDeviceName = name; // connectTo shows a nameless device by its id
        await openUploadDialog(tester, manager, bench4);
        await runUpload(tester);
        expect(upError, 'busy', reason: name);
        expect(find.byKey(const ValueKey('upload_exit')), findsNothing, reason: name);
        await tester.tap(find.byKey(const ValueKey('upload_close')));
        await tester.pumpAndSettle();
      }
    });
  });

  group('3.6 INFO hints', () {
    test('mesh, no keys in the mesh yet', () {
      final info = parseInfo('INFO panel=1 hdr=1 records=22 crc=536812C0 keys=5 outputs=4 net=33 mode=mesh wifi=0 mesh=none');
      expect(hintKeys(uploadInfoHints(info, filePanel: 1)), ['info_mesh_none']);
    });

    test('mesh same / new (new is a warning)', () {
      expect(hintKeys(uploadInfoHints(parseInfo('INFO panel=1 hdr=1 mode=mesh mesh=same'), filePanel: 1)), ['info_mesh_same']);
      final hints = uploadInfoHints(parseInfo('INFO panel=1 hdr=1 mode=mesh mesh=new'), filePanel: 1);
      expect(hintKeys(hints), ['info_mesh_new']);
      expect(hints.single.warning, isTrue);
    });

    test('no header, nothing for the panel, no network page', () {
      final hints = uploadInfoHints(
          parseInfo('INFO panel=1 hdr=0 records=3 crc=00000000 keys=0 outputs=0 net=00 mode=off wifi=0 mesh=none'),
          filePanel: 1);
      expect(hintKeys(hints), ['info_hdr0', 'info_nothing_for_panel', 'info_mode_off']);
      expect(hints[1].params, {'n': '1'});
    });

    test('console panel override and the WiFi set-up page', () {
      final hints = uploadInfoHints(
          parseInfo('INFO panel=7 hdr=1 records=9 crc=1A2B3C4D keys=2 outputs=1 net=11 mode=wifi wifi=0 mesh=none ap=provisioning-79C846'),
          filePanel: 5);
      expect(hintKeys(hints), ['info_panel_override', 'info_wifi_setup']);
      expect(hints[0].params, {'x': '7', 'y': '5'});
      expect(hints[1].params, {'ap': 'provisioning-79C846'});
      expect(hintKeys(uploadInfoHints(parseInfo('INFO panel=5 mode=wifi wifi=1'), filePanel: 5)), ['info_wifi_joins']);
    });

    test('protocol v1 (no INFO), short INFO and unknown keys give no hint', () {
      expect(uploadInfoHints({}, filePanel: 1), isEmpty);
      expect(uploadInfoHints(parseInfo('INFO crc=1A2B3C4D'), filePanel: 1), isEmpty);
      expect(uploadInfoHints(parseInfo('INFO crc=1A2B3C4D future=yes'), filePanel: 1), isEmpty);
    });
  });

  // ---------------------------------------------------------------- main.dart
  group('main.dart', () {
    test('debugPrint also goes to the app log; a saved log starts with the About line', () async {
      final saved = debugPrint;
      addTearDown(() => debugPrint = saved);
      installAppLog();
      debugPrint('GA-3 log hook check');
      expect(appLogLines().last, endsWith('GA-3 log hook check'));
      expect(appLogHeader, kAppAbout);

      final path = await saveAppLog(dir: 'build/test_tmp/ga3_log', now: DateTime(2026, 10, 15, 14, 3, 27));
      expect(path.replaceAll('\\', '/'), endsWith('build/test_tmp/ga3_log/glide_log_20261015_140327.txt'));
      final lines = File(path).readAsLinesSync();
      expect(lines.first, kAppAbout);
      expect(lines.any((l) => l.endsWith('GA-3 log hook check')), isTrue);
    });
  });

  // ---------------------------------------------------------------- texts
  group('app_en.arb', () {
    test('every uploader and firmware token has an err_ text', () {
      final arb = englishArb();
      final tokens = {...fileTokens, ...transientTokens, 'busy', 'cancelled', 'crc'};
      for (final t in tokens) {
        expect(arb.containsKey('err_${t.replaceAll('-', '_')}'), isTrue, reason: 'err_ text for "$t"');
      }
    });

    test('every INFO hint, pre-flight warning and link message has a text', () {
      final arb = englishArb();
      for (final k in [
        'info_hdr0', 'info_panel_override', 'info_nothing_for_panel', 'info_mode_off', 'info_wifi_setup',
        'info_wifi_joins', 'info_mesh_none', 'info_mesh_same', 'info_mesh_new', 'info_v1',
        'hexwarn_no_header', 'hexwarn_header_not_in_pages', 'hexwarn_several_panels', 'hexwarn_no_network_page',
        'link_permissions', 'link_location_off', 'link_bt_off', 'link_failed', 'link_found_not_config',
        'link_no_panel', 'link_not_in_window', 'link_bad_service', 'link_disconnected', 'link_ready', 'link_ready_v1',
        'select_panel_required', 'panel_from_panel_page', 'clear_row', 'about',
      ]) {
        expect(arb.containsKey(k), isTrue, reason: k);
      }
      for (final phase in ['connect', 'probe', 'send', 'store', 'done', 'failed']) {
        expect(arb.containsKey('upload_phase_$phase'), isTrue, reason: phase);
      }
    });

    test('M6: the scene "dimmer_open/close" options read CURTAIN-OPEN/CLOSE', () {
      final arb = englishArb();
      expect(arb['dimmer_open'], 'CURTAIN-OPEN');
      expect(arb['dimmer_close'], 'CURTAIN-CLOSE');
    });

    // fix_glide (review_glide process items): GA-1's open-TXT dialog keys were
    // missing, and only the English file had the M6 relabel
    test('every literal text key the code asks for is in app_en.arb', () {
      final arb = englishArb();
      final patterns = [
        RegExp(r"""\.t\(\s*'([a-z0-9_]+)'"""),
        RegExp(r"""_tr\(\s*'([a-z0-9_]+)'"""),
        RegExp(r"""_(?:message|scanError)\(\s*'([a-z0-9_]+)'"""),
        RegExp(r"""UploadHint\(\s*'([a-z0-9_]+)'"""),
      ];
      final missing = <String>{};
      var found = 0;
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final source = f.readAsStringSync();
        for (final p in patterns) {
          for (final m in p.allMatches(source)) {
            found++;
            if (!arb.containsKey(m.group(1))) missing.add('${m.group(1)} (${f.path})');
          }
        }
      }
      expect(found, greaterThan(150)); // the scan itself works
      expect(missing, isEmpty);
      for (final k in ['txt_open_changes_title', 'txt_open_changes_intro', 'upload_maybe_stored', 'upload_crc_mismatch']) {
        expect(arb.containsKey(k), isTrue, reason: k);
      }
    });

    test('M6 in every language: the scene "dimmer_open/close" options read like that file\'s curtain open/close', () {
      final files = Directory('assets/lang').listSync().whereType<File>().where((f) => f.path.endsWith('.arb')).toList();
      expect(files.length, 8);
      for (final f in files) {
        final arb = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        expect(arb['dimmer_open'], arb['curtain_open'], reason: f.path);
        expect(arb['dimmer_close'], arb['curtain_close'], reason: f.path);
      }
    });
  });
}
