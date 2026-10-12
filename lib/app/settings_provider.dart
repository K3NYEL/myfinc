import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/app_preferences.dart';

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.light,
    this.animationsEnabled = true,
    this.languageCode = 'es',
  });

  final ThemePreference theme;
  final bool animationsEnabled;
  final String languageCode;

  AppSettings copyWith({
    ThemePreference? theme,
    bool? animationsEnabled,
    String? languageCode,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      languageCode: languageCode ?? this.languageCode,
    );
  }

  ThemeMode get themeMode {
    switch (theme) {
      case ThemePreference.system:
        return ThemeMode.system;
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
    }
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  int _themeRevision = 0;
  int _animationsRevision = 0;
  int _languageRevision = 0;

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final themeRevisionAtStart = _themeRevision;
    final animationsRevisionAtStart = _animationsRevision;
    final languageRevisionAtStart = _languageRevision;
    final values = await Future.wait<Object>([
      AppPreferences.getTheme(),
      AppPreferences.getAnimations(),
      AppPreferences.getLanguage(),
    ]);

    // A late preference read must not overwrite a setting changed by the user.
    state = state.copyWith(
      theme: themeRevisionAtStart == _themeRevision
          ? values[0] as ThemePreference
          : state.theme,
      animationsEnabled: animationsRevisionAtStart == _animationsRevision
          ? values[1] as bool
          : state.animationsEnabled,
      languageCode: languageRevisionAtStart == _languageRevision
          ? values[2] as String
          : state.languageCode,
    );
  }

  Future<void> setTheme(ThemePreference theme) async {
    _themeRevision++;
    state = state.copyWith(theme: theme);
    await AppPreferences.setTheme(theme);
  }

  Future<void> setLanguage(String languageCode) async {
    if (!const {'es', 'en'}.contains(languageCode)) {
      throw ArgumentError.value(languageCode, 'languageCode', 'Idioma no compatible');
    }
    _languageRevision++;
    state = state.copyWith(languageCode: languageCode);
    await AppPreferences.setLanguage(languageCode);
  }

  Future<void> setAnimations(bool enabled) async {
    _animationsRevision++;
    state = state.copyWith(animationsEnabled: enabled);
    await AppPreferences.setAnimations(enabled);
  }
}
