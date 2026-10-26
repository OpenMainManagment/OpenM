import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppLocaleNotifier extends StateNotifier<Locale> {
  AppLocaleNotifier() : super(const Locale('en'));

  void setGerman() {
    state = const Locale('de');
  }

  void setEnglish() {
    state = const Locale('en');
  }
}

final appLocaleProvider = StateNotifierProvider<AppLocaleNotifier, Locale>((
  ref,
) {
  return AppLocaleNotifier();
});

bool isGermanLocale(Locale locale) {
  return locale.languageCode == 'de';
}
