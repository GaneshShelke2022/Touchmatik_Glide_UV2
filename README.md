# Touchmatik Glide (GUI_Config_App)

Touchmatik Glide 1.1.0 (build 2) - Agragamee Technologies for Keetronics, Oct-2026.

Glide is the installer's Android app for the Touchmatik 2M panel. It:

- collects a panel's configuration page by page (keys, relay outputs, inputs, scenes, network);
- writes it as a TXT file and converts it to the V3 GUI HEX the panel loads;
- checks the configuration before it generates anything (hard limits block, soft limits warn);
- uploads the HEX over BLE to a TPF01-ESP-PANEL 0.6.0 (or later) in its configuration window
  (protocol v2, verified by the panel's CRC-32), or over RS485 through a USB adapter;
- "Process" re-stamps an existing HEX with a panel number and board type.

TXT and HEX files live in the phone's Documents folder. "Save log" in the upload dialog writes
`glide_log_<date>_<time>.txt` there as well; send it with any bug report.

| Item | Value |
|---|---|
| Dart package | `progswitches` |
| Android application id | `com.example.flutter_app` (unchanged from 1.0.0) |
| App label | Touchmatik Glide |
| Version | `pubspec.yaml` `version: 1.1.0+2`, mirrored in `lib/app_version.dart` (a test keeps them equal) |
| Firmware for the BLE upload | TPF01-ESP-PANEL 0.6.0 or later (other peripherals get protocol v1) |
| Signing | debug key (a project keystore, kept outside the repo, is needed before distribution) |

## Build and test (this PC)

Every cache stays on drive D:. In PowerShell, dot-source the environment first:

```powershell
. D:\K2M_Tools\k2m_flutter_env.ps1      # Flutter 3.47.7, JDK 21, Android SDK, caches on D:
cd D:\K2M\SoftwareBuild\Apps\GUI_Config_App
flutter pub get
flutter analyze
flutter test                            # converters, TXT reader, uploader (fake panel), pages
flutter build apk --debug
flutter build apk --release             # R8 shrinking, signed with the debug key
```

Or the session helper, which logs every step:

```powershell
powershell -NoProfile -File D:\K2M\SoftwareBuild\Tests\build\session_20261015\tools\build_app.ps1 `
    D:\K2M\SoftwareBuild\Apps\GUI_Config_App 3.47.7 <log file> pubget,analyze,test,apk
```

Do not run `flutter pub upgrade --major-versions`, `flutter create .` or `flutter migrate`: the
dependency versions and the Gradle stack are deliberately unchanged. Built APKs are copied to
`SoftwareBuild\Apps\_builds\` (ignored by git).

**Installing:** 1.0.0 was built and signed on another PC, so uninstall 1.0.0 before installing
1.1.0. No data is lost: the TXT and HEX files stay in Documents.

## Where things are

| Path | What |
|---|---|
| `lib/services/convert_manager.dart`, `*_th.dart` | TXT to HEX converters (pure functions, range checked) |
| `lib/services/txt_reader.dart` | opens a TXT into the pages, writes it back (`loadTxt`, `buildTxt`) |
| `lib/services/config_check.dart` | validation before Generate |
| `lib/services/hex_tools.dart`, `hex_file_check.dart` | shared HEX helpers; the panel's line rules and CRC-32 before upload |
| `lib/services/process_config.dart` | Process (header re-stamp) |
| `lib/comporotocol/config_uploader.dart` | the BLE upload protocol, independent of the radio (unit tested) |
| `lib/comporotocol/ble_manager.dart` | scan, connect and upload through flutter_blue_plus |
| `lib/services/app_log.dart` | in-app log (last 2000 lines) behind "Save log" |
| `test/` | unit and widget tests; `test/golden/` HEX goldens, `test/support/fake_panel.dart` |

## Version history

- **1.1.0+2** (Oct-2026, Agragamee, for firmware V0.6.0):
  - converter fixes for configurations that loaded wrong on the panel (header always first,
    one panel number for every page, input blocks at their panel's address, every level
    spelling, THERMOSTAT-VALVE, DIMMER as input device, range and string checks);
  - validation before Generate; opening a TXT reports what it had to change;
  - new BLE upload: scan by service UUID, configuration-window protocol v2 with CRC proof,
    one automatic retry for transient failures, an upload dialog with phases, Cancel, Retry,
    Save log and "Exit configuration mode";
  - page fixes: required panel, row caps and label reuse, digits-only number fields,
    network page DP list and string limits;
  - Android: permissions for Android 12+ (Nearby devices) and 11 and older (Location),
    USB host optional, Bluetooth LE required; dead code removed; About line; tests.
- **1.0.0+1** (Keetronics, as received 15-Oct-2026): the original app.
