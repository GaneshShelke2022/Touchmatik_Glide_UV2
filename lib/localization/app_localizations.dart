import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  final Locale locale;
  late Map<String, String> _localizedStrings;
  late Map<String, String> _fallbackStrings;

  AppLocalizations(this.locale);

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  Future<bool> load() async {
    final String jsonString = await rootBundle.loadString('assets/lang/app_en.arb');
    final Map<String, dynamic> fallbackMap = json.decode(jsonString);
    _fallbackStrings = fallbackMap.map((k, v) => MapEntry(k, v.toString()));

    // try to load requested locale, otherwise use fallback only
    try {
      final String localeFile = 'assets/lang/app_${locale.languageCode}.arb';
      final String localeJson = await rootBundle.loadString(localeFile);
      final Map<String, dynamic> jsonMap = json.decode(localeJson);
      _localizedStrings = jsonMap.map((k, v) => MapEntry(k, v.toString()));
    } catch (e) {
      _localizedStrings = {};
    }

    // Merge fallback for missing keys
    _fallbackStrings.forEach((key, value) {
      _localizedStrings.putIfAbsent(key, () => value);
    });

    return true;
  }

  String t(String key, {Map<String, String>? params}) {
    String? value = _localizedStrings[key];
    if (value == null) return key;
    if (params != null) {
      params.forEach((k, v) {
        value = value!.replaceAll('{$k}', v);
      });
    }
    return value!;
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'hi', 'mr', 'gu', 'pa', 'ta', 'te', 'bn'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final AppLocalizations localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => true;
}
