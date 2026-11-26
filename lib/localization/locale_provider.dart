import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider {
  static final LocaleProvider _instance = LocaleProvider._internal();
  factory LocaleProvider() => _instance;
  LocaleProvider._internal();

  final ValueNotifier<Locale> locale = ValueNotifier<Locale>(const Locale('en'));

  Future<void> loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('selected_locale') ?? 'en';
    locale.value = Locale(code);
  }

  Future<void> setLocale(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_locale', languageCode);
    locale.value = Locale(languageCode);
  }
}
