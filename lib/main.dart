// main.dart - Touchmatik Glide V1.1.0 (Agragamee, Oct-2026): app entry point.
// V1.1.0: the window title comes from app_version.dart, and every debugPrint
// line also goes into the app's own log (app_log.dart), which the upload
// dialog can save for a bench report.
import 'package:flutter/foundation.dart' show DebugPrintCallback;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_version.dart';
import 'login/login_view.dart';
import 'localization/app_localizations.dart';
import 'localization/locale_provider.dart';
import 'localization/language_switcher.dart';
import 'localization/app_navigator.dart';
import 'services/app_log.dart';

final _localeProvider = LocaleProvider();

// true while a debugPrint line is being copied into the log (no loop, whatever appLog does)
bool _routingToLog = false;

/// Routes debugPrint into appLog as well, and names the app at the top of a
/// saved log. Called once from main(); the tests may call it too.
void installAppLog() {
  appLogHeader = kAppAbout;
  final DebugPrintCallback consolePrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && !_routingToLog) {
      _routingToLog = true;
      try {
        appLog(message);
      } finally {
        _routingToLog = false;
      }
    }
    consolePrint(message, wrapWidth: wrapWidth);
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installAppLog();
  appLog('$kAppAbout - started');
  await _localeProvider.loadSavedLocale();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: _localeProvider.locale,
      builder: (context, locale, _) {
        return MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          navigatorKey: AppNavigator.navigatorKey,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          ),
          locale: locale,
          supportedLocales: const [
            Locale('en'),
            Locale('hi'),
            Locale('mr'),
            Locale('gu'),
            Locale('pa'),
            Locale('ta'),
            Locale('te'),
            Locale('bn'),
          ],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (deviceLocale, supportedLocales) {
            // If an explicit locale is provided via the provider, use it.
            if (locale != null) return locale;
            // Otherwise try to match device locale by languageCode
            if (deviceLocale != null) {
              for (final supported in supportedLocales) {
                if (supported.languageCode == deviceLocale.languageCode) return supported;
              }
            }
            // Fallback to first supported locale (English)
            return supportedLocales.first;
          },
          // Use builder to overlay the company logo on top-left and language switcher on top-right of every page
          builder: (context, child) {
            return Stack(
              children: [
                if (child != null) child,
                Positioned(
                  top: 10,
                  left: 5,
                  child: SafeArea(
                    child: IgnorePointer(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/logo4.png',
                            width: 160,
                            height: 30,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 3),
                          const Text(
                            'Glide',
                            style: TextStyle(
                              fontFamily: 'Segoe UI',
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Color(0xFF3C3C3C),
                              height: 1.0,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 36,
                  right: 0,
                  child: IgnorePointer(
                      ignoring: false,
                      child: Container(
                        // ensure dropdown receives taps
                        color: Colors.transparent,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: LanguageSwitcher(),
                        ),
                      ),
                    ),
                ),
              ],
            );
          },
          home: const LoginView(),
        );
      },
    );
  }
}

// LanguageSwitcher is provided from lib/localization/language_switcher.dart
