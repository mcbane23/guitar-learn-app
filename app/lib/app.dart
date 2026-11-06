import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'audio/synth.dart';
import 'data/song_repository.dart';
import 'l10n/strings.dart';
import 'settings/settings.dart';
import 'ui/add_songs.dart';
import 'ui/home_screen.dart';
import 'ui/themes.dart';

/// Shared services for every screen.
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.songs,
    required this.synth,
    required this.pickFiles,
    required this.pickFolder,
    required super.child,
  });

  final SongRepository songs;
  final Synth synth;

  /// Opens the device's file chooser for song files.
  final SongFilePicker pickFiles;

  /// Opens the device's folder chooser and lists the song files in it.
  final SongFilePicker pickFolder;

  static AppServices of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppServices>()!;

  @override
  bool updateShouldNotify(AppServices oldWidget) =>
      songs != oldWidget.songs || synth != oldWidget.synth || pickFiles != oldWidget.pickFiles || pickFolder != oldWidget.pickFolder;
}

class GuitarApp extends StatelessWidget {
  const GuitarApp({
    super.key,
    required this.settings,
    required this.songs,
    required this.synth,
    this.filePicker = pickSongFilesFromDevice,
    this.folderPicker = pickSongFolderFromDevice,
  });

  final AppSettings settings;
  final SongRepository songs;
  final Synth synth;

  /// How song files are chosen (replaced in tests).
  final SongFilePicker filePicker;

  /// How a folder of song files is chosen (replaced in tests).
  final SongFilePicker folderPicker;

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
            pickFiles: filePicker,
            pickFolder: folderPicker,
            child: StringsScope(
              strings: strings,
              child: MaterialApp(
                title: strings.appTitle,
                debugShowCheckedModeBanner: false,
                theme: buildTheme(settings.colorTheme),
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
