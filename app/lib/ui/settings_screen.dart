import 'package:flutter/material.dart';

import '../app.dart';
import '../data/song_repository.dart';
import '../l10n/strings.dart';
import '../settings/settings.dart';
import '../update/app_update.dart';
import 'add_songs.dart';
import 'receive_songs_screen.dart';
import 'send_songs_screen.dart';
import 'common.dart';
import 'themes.dart';
import 'update_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final s = SettingsScope.of(context);
    final services = AppServices.of(context);

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
        );

    Widget toggle(String title, String? subtitle, bool value, void Function(AppSettings, bool) set) =>
        SwitchListTile(
          title: Text(title, style: const TextStyle(fontSize: 18)),
          subtitle: subtitle == null ? null : Text(subtitle),
          value: value,
          onChanged: (v) => s.update((x) => set(x, v)),
        );

    // On a TV the sliders take only left and right from the remote; up and
    // down move on to the next setting instead of changing the value, so
    // everything under the sliders stays reachable.
    Widget slider(Slider slider) => MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: slider,
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
          // The choices with a few options sit side by side as cards, so
          // the list is short and a remote reaches everything in a few presses.
          header(t.language_),
          _ChoiceRow(
            autofocus: true,
            options: [
              for (final (lang, label) in languages)
                _Choice(label: label, selected: s.language == lang, onTap: () => s.update((x) => x.language = lang)),
            ],
          ),
          header(t.theme),
          _ChoiceRow(options: [
            for (final theme in AppColorTheme.values)
              _Choice(
                label: t.themeName(theme.name),
                leading: _ThemeSwatch(theme),
                selected: s.colorTheme == theme,
                onTap: () => s.update((x) => x.colorTheme = theme),
              ),
          ]),
          header(t.dotLabel),
          _ChoiceRow(options: [
            for (final (label, hint, value) in [
              (t.dotLabelFinger, t.dotLabelFingerHint, DotLabel.finger),
              (t.dotLabelFret, t.dotLabelFretHint, DotLabel.fret),
            ])
              _Choice(label: label, hint: hint, selected: s.dotLabel == value, onTap: () => s.update((x) => x.dotLabel = value)),
          ]),
          header(t.settings),
          toggle(t.leftHanded, t.leftHandedHint, s.leftHanded, (x, v) => x.leftHanded = v),
          toggle(t.thinStringTop, t.thinStringTopHint, s.thinStringOnTop, (x, v) => x.thinStringOnTop = v),
          toggle(t.showNoteNames, null, s.showNoteNames, (x, v) => x.showNoteNames = v),
          toggle(t.showChordName, null, s.showChordName, (x, v) => x.showChordName = v),
          toggle(t.countIn, null, s.countIn, (x, v) => x.countIn = v),
          toggle('${t.colors}: ${t.colorsHighContrast}', null, s.highContrast, (x, v) => x.highContrast = v),
          ListTile(
            title: Text(t.defaultSpeed, style: const TextStyle(fontSize: 18)),
            subtitle: slider(Slider(
              value: s.defaultSpeed,
              min: 0.25,
              max: 1,
              divisions: 15,
              label: '${(s.defaultSpeed * 100).round()}%',
              onChanged: (v) => s.update((x) => x.defaultSpeed = v),
            )),
            trailing: Text('${(s.defaultSpeed * 100).round()}%', style: const TextStyle(fontSize: 18)),
          ),
          ListTile(
            title: Text(t.volume, style: const TextStyle(fontSize: 18)),
            subtitle: slider(Slider(
              value: s.volume,
              divisions: 20,
              onChanged: (v) {
                s.update((x) => x.volume = v);
                services.synth.setVolume(v);
              },
            )),
            trailing: Text('${(s.volume * 100).round()}%', style: const TextStyle(fontSize: 18)),
          ),
          header(t.songFiles),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(t.songFilesHint, style: Theme.of(context).textTheme.bodyMedium),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_rounded),
            title: Text(t.addSongs, style: const TextStyle(fontSize: 18)),
            onTap: () => addSongsFlow(context),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_2_rounded),
            title: Text(t.receiveSongs, style: const TextStyle(fontSize: 18)),
            subtitle: Text(t.receiveSongsHint),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReceiveSongsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.cast_rounded),
            title: Text(t.sendToTv, style: const TextStyle(fontSize: 18)),
            subtitle: Text(t.sendToTvHint),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SendSongsScreen())),
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
          header(t.songSources),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(t.songSourcesHint, style: Theme.of(context).textTheme.bodyMedium),
          ),
          for (final source in s.songSources)
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: Text(source, style: const TextStyle(fontSize: 16)),
              trailing: IconButton(
                tooltip: t.removeSongSource,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  s.update((x) => x.songSources = [...x.songSources]..remove(source));
                  services.songs.extraSources = s.songSources;
                  services.songs.refresh();
                },
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add_link_rounded),
            title: Text(t.addSongSource, style: const TextStyle(fontSize: 18)),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final added = await showDialog<(String, int)>(context: context, builder: (_) => const _AddSourceDialog());
              if (added == null) return;
              final (url, count) = added;
              if (!s.songSources.contains(url)) s.update((x) => x.songSources = [...x.songSources, url]);
              services.songs.extraSources = s.songSources;
              messenger.showSnackBar(SnackBar(content: Text(t.songSourceAdded(count))));
              await services.songs.refresh();
            },
          ),
          header(t.appUpdate),
          _UpdateTile(updater: services.updater),
          header(t.about),
          ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: Text(t.privacy)),
        ],
      ),
    );
  }
}

/// "Check for a new version": looks up the newest build on GitHub and offers
/// to install it. Shows the installed build number underneath.
class _UpdateTile extends StatefulWidget {
  const _UpdateTile({required this.updater});

  final AppUpdater updater;

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  bool _checking = false;
  int? _build;

  @override
  void initState() {
    super.initState();
    widget.updater.currentBuild().then((b) {
      if (mounted) setState(() => _build = b);
    });
  }

  Future<void> _check() async {
    final t = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    final update = await widget.updater.check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (update != null) {
      await showUpdateDialog(context, update);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(_build == null || _build! <= 0 ? t.updateCheckFailed : t.appUpToDate)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return ListTile(
      leading: _checking
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
          : const Icon(Icons.system_update_rounded),
      title: Text(_checking ? t.checkingForUpdate : t.checkForUpdate, style: const TextStyle(fontSize: 18)),
      subtitle: _build != null && _build! > 0 ? Text(t.currentBuild(_build!)) : null,
      onTap: _checking ? null : _check,
    );
  }
}

/// A small preview of a theme: its background with the accent color on top.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch(this.theme);

  final AppColorTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 32,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(children: [
        Expanded(child: DecoratedBox(decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(width: 4),
        Expanded(child: DecoratedBox(decoration: BoxDecoration(color: theme.accent, borderRadius: BorderRadius.circular(4)))),
      ]),
    );
  }
}

/// Asks for a song list link and checks that there is a song list there
/// before it is added. Pops with (folder URL, number of songs).
class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog();

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _link = TextEditingController();
  bool _checking = false;
  bool _notFound = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_link.text.trim().isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _notFound = false;
    });
    final found = await AppServices.of(context).songs.checkSource(_link.text);
    if (!mounted) return;
    if (found == null) {
      setState(() {
        _checking = false;
        _notFound = true;
      });
    } else {
      Navigator.of(context).pop(found);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return AlertDialog(
      title: Text(t.addSongSource),
      content: TextField(
        controller: _link,
        autofocus: true,
        keyboardType: TextInputType.url,
        autocorrect: false,
        onSubmitted: (_) => _add(),
        decoration: InputDecoration(
          labelText: t.songSourceLink,
          hintText: 'https://github.com/user/songs',
          errorText: _notFound ? t.songSourceNotFound : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(onPressed: _checking ? null : _add, child: Text(_checking ? t.checking : t.add)),
      ],
    );
  }
}

class _Choice {
  const _Choice({required this.label, required this.selected, required this.onTap, this.hint, this.leading});

  final String label;
  final String? hint;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;
}

/// A few options side by side; the chosen one is filled with the accent
/// color. They wrap onto more rows on a narrow phone.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.options, this.autofocus = false});

  final List<_Choice> options;

  /// The first option takes the remote's focus when the screen opens.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (i, o) in options.indexed)
            FocusCard(
              autofocus: autofocus && i == 0,
              onTap: o.onTap,
              color: o.selected ? scheme.primary : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (o.leading case final leading?) ...[leading, const SizedBox(width: 10)],
                  Icon(
                    o.selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 22,
                    color: o.selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      o.label,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: o.selected ? scheme.onPrimary : null),
                    ),
                    if (o.hint case final hint?)
                      Text(hint, style: TextStyle(fontSize: 13, color: o.selected ? scheme.onPrimary.withValues(alpha: 0.85) : scheme.onSurfaceVariant)),
                  ]),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
