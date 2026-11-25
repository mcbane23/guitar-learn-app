import 'package:flutter/material.dart';

import '../app.dart';
import '../data/song_repository.dart';
import '../l10n/strings.dart';
import '../settings/settings.dart';
import '../update/app_update.dart';
import 'add_songs.dart';
import 'receive_songs_screen.dart';
import 'send_songs_screen.dart';
import '../music/pitch.dart';
import 'common.dart';
import 'fretboard.dart';
import 'themes.dart';
import 'update_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final s = SettingsScope.of(context);
    final services = AppServices.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Every row gets the remote's white ring when it is selected: a list
    // tile only tints itself, which cannot be seen on the glass.
    Widget toggle(String title, String? subtitle, bool value, void Function(AppSettings, bool) set) =>
        FocusHighlight(
          child: SwitchListTile(
            title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            subtitle: subtitle == null ? null : Text(subtitle),
            value: value,
            onChanged: (v) => s.update((x) => set(x, v)),
          ),
        );

    // On a TV the sliders take only left and right from the remote; up and
    // down move on to the next setting instead of changing the value, so
    // everything under the sliders stays reachable.
    Widget slider(String title, double value, Slider widget) => FocusHighlight(
          child: ListTile(
            title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            subtitle: MediaQuery(
              data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
              child: widget,
            ),
            trailing: _ValuePill('${(value * 100).round()}%'),
          ),
        );

    Widget action(IconData icon, String title, {String? subtitle, VoidCallback? onTap, Widget? trailing, bool busy = false}) =>
        FocusHighlight(
          child: ListTile(
            leading: busy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                : Icon(icon),
            title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right_rounded, color: Colors.white38)),
            onTap: onTap,
          ),
        );

    Widget note(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(text, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
        );

    final languages = <(AppLanguage?, String)>[
      (null, t.languageSystem),
      (AppLanguage.en, t.english),
      (AppLanguage.srLatn, t.serbianLatin),
      (AppLanguage.srCyrl, t.serbianCyrillic),
    ];

    final sections = <Widget>[
      // The choices with a few options sit side by side as cards, so the
      // list is short and a remote reaches everything in a few presses.
      _Section(icon: Icons.language_rounded, title: t.language_, children: [
        _ChoiceRow(
          autofocus: true,
          options: [
            for (final (lang, label) in languages)
              _Choice(label: label, selected: s.language == lang, onTap: () => s.update((x) => x.language = lang)),
          ],
        ),
      ]),
      _Section(icon: Icons.palette_rounded, title: t.lookSection, children: [
        // A small neck shows every choice below as soon as it is made.
        const _NeckPreview(),
        _Label(t.theme),
        _ChoiceRow(options: [
          for (final theme in AppColorTheme.values)
            _Choice(
              label: t.themeName(theme.name),
              leading: _ThemeSwatch(theme),
              selected: s.colorTheme == theme,
              onTap: () => s.update((x) => x.colorTheme = theme),
            ),
        ]),
        _Label(t.dotLabel),
        _ChoiceRow(options: [
          for (final (label, hint, value) in [
            (t.dotLabelFinger, t.dotLabelFingerHint, DotLabel.finger),
            (t.dotLabelFret, t.dotLabelFretHint, DotLabel.fret),
          ])
            _Choice(label: label, hint: hint, selected: s.dotLabel == value, onTap: () => s.update((x) => x.dotLabel = value)),
        ]),
        const SizedBox(height: 6),
        toggle(t.leftHanded, t.leftHandedHint, s.leftHanded, (x, v) => x.leftHanded = v),
        toggle(t.thinStringTop, t.thinStringTopHint, s.thinStringOnTop, (x, v) => x.thinStringOnTop = v),
        toggle(t.showNoteNames, null, s.showNoteNames, (x, v) => x.showNoteNames = v),
        toggle('${t.colors}: ${t.colorsHighContrast}', null, s.highContrast, (x, v) => x.highContrast = v),
      ]),
      _Section(icon: Icons.play_circle_rounded, title: t.playingSection, children: [
        toggle(t.showChordName, null, s.showChordName, (x, v) => x.showChordName = v),
        toggle(t.countIn, null, s.countIn, (x, v) => x.countIn = v),
        slider(
          t.defaultSpeed,
          s.defaultSpeed,
          Slider(
            value: s.defaultSpeed,
            min: 0.25,
            max: 1,
            divisions: 15,
            label: '${(s.defaultSpeed * 100).round()}%',
            onChanged: (v) => s.update((x) => x.defaultSpeed = v),
          ),
        ),
        slider(
          t.volume,
          s.volume,
          Slider(
            value: s.volume,
            divisions: 20,
            onChanged: (v) {
              s.update((x) => x.volume = v);
              services.synth.setVolume(v);
            },
          ),
        ),
      ]),
      _Section(icon: Icons.library_music_rounded, title: t.songFiles, children: [
        note(t.songFilesHint),
        action(Icons.file_open_rounded, t.addSongs, onTap: () => addSongsFlow(context)),
        action(
          Icons.qr_code_2_rounded,
          t.receiveSongs,
          subtitle: t.receiveSongsHint,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReceiveSongsScreen())),
        ),
        action(
          Icons.cast_rounded,
          t.sendToTv,
          subtitle: t.sendToTvHint,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SendSongsScreen())),
        ),
      ]),
      _Section(icon: Icons.cloud_rounded, title: t.onlineSongs, children: [
        ListenableBuilder(
          listenable: services.songs,
          builder: (context, _) => action(
            Icons.cloud_download_rounded,
            services.songs.refreshing ? t.updating : t.updateSongs,
            busy: services.songs.refreshing,
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
        _Label(t.songSources),
        note(t.songSourcesHint),
        for (final source in s.songSources)
          FocusHighlight(
            child: ListTile(
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
          ),
        action(Icons.add_link_rounded, t.addSongSource, onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final added = await showDialog<(String, int)>(context: context, builder: (_) => const _AddSourceDialog());
          if (added == null) return;
          final (url, count) = added;
          if (!s.songSources.contains(url)) s.update((x) => x.songSources = [...x.songSources, url]);
          services.songs.extraSources = s.songSources;
          messenger.showSnackBar(SnackBar(content: Text(t.songSourceAdded(count))));
          await services.songs.refresh();
        }),
      ]),
      _Section(icon: Icons.info_rounded, title: t.about, children: [
        FocusHighlight(child: _UpdateTile(updater: services.updater)),
        ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: Text(t.privacy)),
      ]),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(t.settings)),
      body: AppBackground(
        theme: s.colorTheme,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 8, 16, 32),
                children: sections,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pane of glass with a title row and the settings that belong together.
class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            ]),
          ),
          ...children,
        ]),
      ),
    );
  }
}

/// A small heading inside a section.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// The value next to a slider, in a pill so it reads like a button's label.
class _ValuePill extends StatelessWidget {
  const _ValuePill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: glassHigh, borderRadius: BorderRadius.circular(14)),
      child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
    );
  }
}

/// A short neck with a C chord on it, drawn with the current choices: the
/// user sees what left-handed, the string order, the numbers in the
/// circles, note names and the colors do, without opening a song.
class _NeckPreview extends StatelessWidget {
  const _NeckPreview();

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final s = SettingsScope.of(context);
    final style = NeckStyle(
      leftHanded: s.leftHanded,
      thinOnTop: s.thinStringOnTop,
      highContrast: s.highContrast,
      fretNumbers: s.dotLabel == DotLabel.fret,
      frets: 5,
    );
    String? name(int string, int fret) =>
        s.showNoteNames ? noteName(standardTuning[string - 1] + fret, serbian: t.language.isSerbian) : null;
    final scene = NeckScene(
      dots: [
        NeckDot(string: 2, fret: 1, finger: 1, label: name(2, 1)),
        NeckDot(string: 4, fret: 2, finger: 2, label: name(4, 2)),
        NeckDot(string: 5, fret: 3, finger: 3, label: name(5, 3)),
      ],
      openStrings: const {1, 3},
      openLabels: {for (final st in const [1, 3]) if (name(st, 0) case final n?) st: n},
      mutedStrings: const {6},
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: ExcludeFocus(
        child: Column(children: [
          SizedBox(height: 150, child: FretboardView(scene: scene, style: style)),
          Text(t.previewHint, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
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
      title: Text(_checking ? t.checkingForUpdate : t.checkForUpdate, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      subtitle: _build != null && _build! > 0 ? Text(t.currentBuild(_build!)) : null,
      onTap: _checking ? null : _check,
    );
  }
}

/// A small preview of a theme: its background with the two glows and the
/// accent color on top, like the real screen in miniature.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch(this.theme);

  final AppColorTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 36,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Stack(children: [
        Positioned(
          left: -14,
          top: -14,
          child: _glow(theme.glowA),
        ),
        Positioned(
          right: -14,
          bottom: -14,
          child: _glow(theme.glowB),
        ),
        Center(
          child: Container(
            width: 26,
            height: 12,
            decoration: BoxDecoration(color: theme.accent, borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ]),
    );
  }

  Widget _glow(Color color) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withValues(alpha: 0.6), color.withValues(alpha: 0)]),
        ),
      );
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
              radius: 16,
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
