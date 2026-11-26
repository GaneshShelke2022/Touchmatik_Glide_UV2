/*
 * =============================================================================
 *  ble_manager_test.dart  -  Touchmatik Glide 1.1.0 tests (fix_glide, Oct-2026)
 *  The parts of ble_manager.dart that decide something without a radio:
 *    - review_glide finding 4: '#VER' (C10) and "Exit configuration mode"
 *      go by the name a device really carries; a device without a name is
 *      shown as 'KIPL-2M-?' but never treated as a KIPL-2M panel;
 *    - review_glide finding 8: the unfiltered diagnosis scan lists a device
 *      that advertises the configuration service as connectable, and calls
 *      only KIPL-2M panels WITHOUT the service "not in configuration mode".
 *  Scan results are built by hand; nothing here talks to Bluetooth (the
 *  connect in the last test fails at once on the PC, which is the point).
 * =============================================================================
 */
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:progswitches/comporotocol/ble_manager.dart';

// a scan result as flutter_blue_plus would report it
ScanResult scanResult(String id, {String name = '', bool service = false}) => ScanResult(
      device: BluetoothDevice.fromId(id),
      advertisementData: AdvertisementData(
        advName: name,
        txPowerLevel: null,
        appearance: null,
        connectable: true,
        manufacturerData: const {},
        serviceData: const {},
        serviceUuids: service ? [Guid(BLEManager.serviceUUID)] : const [],
      ),
      rssi: -60,
      timeStamp: DateTime(2026, 10, 16),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('review 4: names', () {
    test('a device without a name is shown as KIPL-2M-? but is not a KIPL-2M panel', () {
      final nameless = scanResult('AA:BB:CC:DD:EE:FF', service: true);
      expect(BLEManager.displayName(nameless), 'KIPL-2M-?'); // the list (design 3.5)
      expect(BLEManager.advertisedName(nameless), ''); // what connectTo gets
      expect(BLEManager.isPanelName(BLEManager.advertisedName(nameless)), isFalse);
      expect(BLEManager.isPanelName(BLEManager.displayName(nameless)), isFalse); // not even the fallback
    });

    test('a panel name is KIPL-2M-XXYYZZ; other peripherals are not panels', () {
      final panel = scanResult('11:22:33:44:55:66', name: 'KIPL-2M-79C846', service: true);
      expect(BLEManager.displayName(panel), 'KIPL-2M-79C846');
      expect(BLEManager.advertisedName(panel), 'KIPL-2M-79C846');
      expect(BLEManager.isPanelName('KIPL-2M-79C846'), isTrue);
      expect(BLEManager.isPanelName('ESP32-V3'), isFalse);
      expect(BLEManager.isPanelName('KIPL-2M-'), isFalse);
      expect(BLEManager.isPanelName(''), isFalse);
    });

    test('connectTo a device without a name: shown by its id, no KIPL treatment, no #CLOSE', () async {
      final m = BLEManager();
      final ok = await m.connectTo(BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF'), advName: '');
      expect(ok, isFalse); // no Bluetooth on the test PC
      expect(m.linkDeviceName, 'AA:BB:CC:DD:EE:FF');
      expect(m.isPanel, isFalse);
      expect(BLEManager.isPanelName(m.linkDeviceName), isFalse); // the upload dialog offers no Exit
      expect(await m.exitConfigMode(), isFalse); // and sends nothing

      final ok2 = await m.connectTo(BluetoothDevice.fromId('11:22:33:44:55:66'), advName: 'KIPL-2M-79C846');
      expect(ok2, isFalse);
      expect(m.linkDeviceName, 'KIPL-2M-79C846');
      expect(m.isPanel, isTrue);
    });
  });

  group('review 8: diagnosis scan', () {
    test('a device with the configuration service is connectable, whatever its name', () {
      final missedNoName = scanResult('01', service: true); // the phone's service filter missed it
      final missedNamed = scanResult('02', name: 'KIPL-2M-79C846', service: true);
      final meshMode = scanResult('03', name: 'KIPL-2M-0A0B0C'); // same name, no service: outside its window
      final other = scanResult('04', name: 'Mi Band');
      final sorted = BLEManager.sortDiagnosis([missedNoName, missedNamed, meshMode, other]);
      expect(sorted.inWindow, [missedNoName, missedNamed]);
      expect(sorted.outside, ['KIPL-2M-0A0B0C']);
    });

    test('only panels without the service are "not in configuration mode"; nothing found is nothing', () {
      final sorted = BLEManager.sortDiagnosis([
        scanResult('05', name: 'KIPL-2M-0A0B0C'),
        scanResult('06', name: 'KIPL-2M-010203'),
        scanResult('07', name: 'HMSoft'),
      ]);
      expect(sorted.inWindow, isEmpty);
      expect(sorted.outside, ['KIPL-2M-010203', 'KIPL-2M-0A0B0C']);
      final empty = BLEManager.sortDiagnosis(const []);
      expect(empty.inWindow, isEmpty);
      expect(empty.outside, isEmpty);
    });
  });
}
