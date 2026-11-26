// version_test.dart - Touchmatik Glide 1.1.0 (Agragamee, Oct-2026)
// V1 of the V0.6.0 design (5.4): the version in pubspec.yaml (which becomes the
// Android versionName / versionCode) and the one written in code
// (lib/app_version.dart, shown on the login page and in saved logs) must agree.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:progswitches/app_version.dart';

void main() {
  test('V1: pubspec version = kAppVersion + kAppBuild', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml has no "version: x.y.z+n" line');
    expect(m!.group(1), kAppVersion);
    expect(int.parse(m.group(2)!), kAppBuild);
  });

  test('V1: version 1.1.0 build 2 (contract C-0)', () {
    expect(kAppName, 'Touchmatik Glide');
    expect(kAppVersion, '1.1.0');
    expect(kAppBuild, 2);
  });

  test('V1: About line is the C-0 text and names this version', () {
    expect(kAppAbout, 'Touchmatik Glide 1.1.0 (build 2) - BLE protocol v2 - for TPF01-ESP-PANEL 0.6.0 and later');
    expect(kAppAbout, startsWith('$kAppName $kAppVersion (build $kAppBuild)'));
  });
}
