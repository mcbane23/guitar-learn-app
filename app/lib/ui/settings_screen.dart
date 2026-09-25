import 'package:flutter/material.dart';

import '../app.dart';
import '../data/song_repository.dart';
import '../l10n/strings.dart';
import '../settings/settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final s = SettingsScope.of(context);
    final services = AppServices.of(context);

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFFF7A1A))),
        );

    Widget toggle(String title, String? subtitle, bool value, void Function(AppSettings, bool) set) =>
        SwitchListTile(
          title: Text(title, style: const TextStyle(fontSize: 18)),
          subtitle: subtitle == null ? null : Text(subtitle),
          value: value,
          onChanged: (v) => s.update((x) => set(x, v)),
        );

    final languages = <(AppLanguage?, String)>[
      (null, t.languageSystem),
      (AppLanguage.en, t.english),
      (AppLanguage.srLatn, t.serbianLatin),
      (AppLanguage.srCyrl, t.serbianCyrillic),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          header(t.language_),
          for (final (i, (lang, label)) in languages.indexed)
            ListTile(
              autofocus: i == 0,
              title: Text(label, style: const TextStyle(fontSize: 18)),
              leading: Icon(s.language == lang ? Icons.radio_button_checked : Icons.radio_button_off),
              onTap: () => s.update((x) => x.language = lang),
            ),
          header(t.settings),
          toggle(t.leftHanded, t.leftHandedHint, s.leftHanded, (x, v) => x.leftHanded = v),
          toggle(t.thinStringTop, t.thinStringTopHint, s.thinStringOnTop, (x, v) => x.thinStringOnTop = v),
          toggle(t.showNoteNames, null, s.showNoteNames, (x, v) => x.showNoteNames = v),
          toggle(t.showChordName, null, s.showChordName, (x, v) => x.showChordName = v),
          toggle(t.countIn, null, s.countIn, (x, v) => x.countIn = v),
          toggle('${t.colors}: ${t.colorsHighContrast}', null, s.highContrast, (x, v) => x.highContrast = v),
          ListTile(
            title: Text(t.defaultSpeed, style: const TextStyle(fontSize: 18)),
            subtitle: Slider(
              value: s.defaultSpeed,
              min: 0.25,
              max: 1,
              divisions: 15,
              label: '${(s.defaultSpeed * 100).round()}%',
              onChanged: (v) => s.update((x) => x.defaultSpeed = v),
            ),
            trailing: Text('${(s.defaultSpeed * 100).round()}%', style: const TextStyle(fontSize: 18)),
          ),
          ListTile(
            title: Text(t.volume, style: const TextStyle(fontSize: 18)),
            subtitle: Slider(
              value: s.volume,
              onChanged: (v) {
                s.update((x) => x.volume = v);
                services.synth.setVolume(v);
              },
            ),
            trailing: Text('${(s.volume * 100).round()}%', style: const TextStyle(fontSize: 18)),
          ),
          header(t.onlineSongs),
          ListenableBuilder(
            listenable: services.songs,
            builder: (context, _) => ListTile(
              leading: services.songs.refreshing
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Icons.cloud_download_rounded),
              title: Text(services.songs.refreshing ? t.updating : t.updateSongs, style: const TextStyle(fontSize: 18)),
              onTap: services.songs.refreshing
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final (result, count) = await services.songs.refresh();
                      messenger.showSnackBar(SnackBar(
                        content: Text(switch (result) {
                          RefreshResult.added => t.newSongs(count),
                          RefreshResult.upToDate => t.songsUpToDate,
                          RefreshResult.offline => t.offline,
                        }),
                      ));
                    },
            ),
          ),
          header(t.about),
          ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: Text(t.privacy)),
        ],
      ),
    );
  }
}
