import 'package:flutter/material.dart';

import 'app.dart';
import 'audio/synth.dart';
import 'data/song_repository.dart';
import 'settings/settings.dart';
import 'update/app_update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final songs = SongRepository(extraSources: settings.songSources);
  await songs.load();
  final synth = PlatformSynth()..setVolume(settings.volume);
  runApp(GuitarApp(settings: settings, songs: songs, synth: synth, updater: GitHubAppUpdater()));
}
