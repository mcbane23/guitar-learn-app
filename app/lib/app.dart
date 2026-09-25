import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'audio/synth.dart';
import 'data/song_repository.dart';
import 'l10n/strings.dart';
import 'settings/settings.dart';
import 'ui/home_screen.dart';

/// Shared services for every screen.
class AppServices extends InheritedWidget {
  const AppServices({super.key, required this.songs, required this.synth, required super.child});

  final SongRepository songs;
  final Synth synth;

  static AppServices of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppServices>()!;

  @override
  bool updateShouldNotify(AppServices oldWidget) => songs != oldWidget.songs || synth != oldWidget.synth;
}

class GuitarApp extends StatelessWidget {
  const GuitarApp({super.key, required this.settings, required this.songs, required this.synth});

  final AppSettings settings;
  final SongRepository songs;
  final Synth synth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final language = settings.resolveLanguage(WidgetsBinding.instance.platformDispatcher.locale);
        final strings = Strings(language);
        return SettingsScope(
          settings: settings,
          child: AppServices(
            songs: songs,
            synth: synth,
            child: StringsScope(
              strings: strings,
              child: MaterialApp(
                title: strings.appTitle,
                debugShowCheckedModeBanner: false,
                theme: buildTheme(),
                locale: language.locale,
                supportedLocales: [for (final l in AppLanguage.values) l.locale],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                shortcuts: {
                  ...WidgetsApp.defaultShortcuts,
                  // The OK / center button on TV remotes.
                  const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
                },
                home: const HomeScreen(),
              ),
            ),
          ),
        );
      },
    );
  }
}

ThemeData buildTheme() {
  const seed = Color(0xFFFF7A1A);
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark).copyWith(
    surface: const Color(0xFF141726),
    primary: seed,
    onPrimary: Colors.white,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFF0E1020),
    visualDensity: VisualDensity.comfortable,
    focusColor: Colors.white.withValues(alpha: 0.18),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(52, 52), iconSize: 28),
    ),
  );
}
