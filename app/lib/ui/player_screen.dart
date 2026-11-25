import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../audio/synth.dart';
import '../l10n/strings.dart';
import '../models/song.dart';
import '../music/pitch.dart';
import '../playback/playback_controller.dart';
import '../settings/settings.dart';
import 'add_songs.dart';
import 'common.dart';
import 'fretboard.dart';
import 'scene_builder.dart';
import 'themes.dart';

/// The main screen: a full-screen guitar neck that plays a song.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.songId});

  final String songId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin, LandscapeScreen, WidgetsBindingObserver {
  PlaybackController? _controller;
  Object? _error;

  /// On a TV a line under the neck says which keys do what, until the song
  /// is started for the first time.
  bool _tv = false;

  /// Drives the neck animation (glowing strings, pulsing dots). It runs while
  /// the song plays or something still moves, and stops a moment after the
  /// song is paused, so a song left open does not keep the device busy.
  late final Ticker _ticker;
  final _clock = Stopwatch()..start();
  final _time = ValueNotifier<double>(0);
  double _lastChange = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isTelevision().then((tv) {
      if (mounted && tv) setState(() => _tv = true);
    });
    _ticker = createTicker((_) {
      _time.value = _clock.elapsedMicroseconds / 1e6;
      final c = _controller;
      if (c != null && !c.isPlaying && !c.waiting && _time.value - _lastChange > 1.5) _ticker.stop();
    })
      ..start();
  }

  void _controllerChanged() {
    _lastChange = _clock.elapsedMicroseconds / 1e6;
    if (!_ticker.isActive) _ticker.start();
  }

  /// The song stops when the app leaves the screen (Home button, a phone
  /// call, another app on the TV). Without this the sequencer would keep
  /// feeding the synthesizer and the guitar would play on in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pause();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null && _error == null) _load();
  }

  Future<void> _load() async {
    final services = AppServices.of(context);
    final settings = SettingsScope.of(context);
    try {
      final song = await services.songs.loadSong(widget.songId);
      if (!mounted) return;
      setState(() => _controller = _newController(song, speed: settings.defaultSpeed)..addListener(_controllerChanged));
      settings.markPlayed(song.id);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  PlaybackController _newController(Song song, {required double speed, TrackKind? track}) {
    final services = AppServices.of(context);
    final settings = SettingsScope.of(context);
    return PlaybackController(
      song: song,
      chords: services.songs.chords,
      synth: services.synth,
      speed: speed,
      countIn: settings.countIn,
      track: track ?? TrackKind.full,
    );
  }

  /// Shows another part (guitar) of the same song.
  void _selectPart(int index) {
    final old = _controller;
    if (old == null || index == old.song.partIndex) return;
    final next = _newController(old.song.withPart(index), speed: old.speed, track: old.track)
      ..addListener(_controllerChanged)
      // Another guitar takes over mid-song: same place, no restart.
      ..continueFrom(old);
    old.dispose();
    setState(() => _controller = next);
    _controllerChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _controller?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final c = _controller;
    // The count-in switch in settings applies to a song that is already open.
    c?.countIn = SettingsScope.of(context).countIn;
    if (c == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(t.songNotFound, style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 16),
                  FilledButton(autofocus: true, onPressed: () => Navigator.pop(context), child: Text(t.back)),
                ]),
        ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): c.togglePlay,
        const SingleActivator(LogicalKeyboardKey.mediaPlay): c.play,
        const SingleActivator(LogicalKeyboardKey.mediaPause): c.pause,
        const SingleActivator(LogicalKeyboardKey.mediaStop): c.pause,
        // Rewind and forward on the remote step a bar at a time; the
        // previous/next track keys do the same on remotes that have them.
        const SingleActivator(LogicalKeyboardKey.mediaRewind): () => c.seekBars(-1),
        const SingleActivator(LogicalKeyboardKey.mediaFastForward): () => c.seekBars(1),
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () => c.seekBars(-1),
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () => c.seekBars(1),
        const SingleActivator(LogicalKeyboardKey.mediaSkipBackward): () => c.seekBars(-1),
        const SingleActivator(LogicalKeyboardKey.mediaSkipForward): () => c.seekBars(1),
        const SingleActivator(LogicalKeyboardKey.channelUp): () => c.setSpeed(c.speed + 0.05),
        const SingleActivator(LogicalKeyboardKey.channelDown): () => c.setSpeed(c.speed - 0.05),
      },
      child: Scaffold(
        body: AppBackground(
          theme: SettingsScope.of(context).colorTheme,
          child: SafeArea(
            child: Column(
              children: [
                _TopBar(controller: c, onPart: _selectPart),
                Expanded(child: _Neck(controller: c, time: _time, remoteHint: _tv)),
                _Progress(controller: c),
                _Controls(controller: c),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.onPart});

  final PlaybackController controller;
  final void Function(int index) onPart;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final settings = SettingsScope.of(context);
    final songs = AppServices.of(context).songs;
    final song = controller.song;
    final scheme = Theme.of(context).colorScheme;
    final imported = songs.isImported(song.id);
    final tuning = song.isStandardTuning
        ? null
        : song.tuning.reversed.map((p) => noteName(p, serbian: t.language.isSerbian)).join(' ');
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxWidth < _Controls.compactWidth;
      // With two pills in the bar (a song with several parts) the names
      // get long: below this width the second pill is just an icon, the
      // first pill's name is shorter and the mode buttons use short words,
      // so the bar fits a 1080p TV and a tablet.
      final roomy = box.maxWidth >= 1300 || song.parts.length <= 1;
      final shortModes = compact || !roomy;
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final chord = controller.currentChord;
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: t.back,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.songTitle(song.info),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                      ),
                      if (tuning != null || song.capo > 0)
                        Text(
                          [
                            if (tuning != null) '${t.tuning}: $tuning',
                            if (song.capo > 0) t.capo(song.capo),
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: scheme.primary, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                if (song.parts.length > 1)
                  Tooltip(
                    message: t.part,
                    child: Material(
                      color: glass,
                      shape: const StadiumBorder(side: BorderSide(color: glassBorder)),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => _choosePart(context),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.queue_music_rounded, size: 20),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: roomy ? 160 : 110),
                              child: Text(
                                song.parts[song.partIndex].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded),
                          ]),
                        ),
                      ),
                    ),
                  ),
                if (song.parts.length > 1) const SizedBox(width: 8),
                // The second guitar sits right next to the first, so it is
                // added with one press instead of a trip through "More".
                if (song.parts.length > 1)
                  Tooltip(
                    message: t.secondPart,
                    child: Material(
                      color: controller.secondPart == null ? glass : scheme.primary.withValues(alpha: 0.22),
                      shape: const StadiumBorder(side: BorderSide(color: glassBorder)),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => _chooseSecondPart(context),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(10, 6, roomy ? 12 : 10, 6),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(controller.secondPart == null ? Icons.add_rounded : Icons.queue_music_rounded, size: 20),
                            // On a narrow screen the pill is just the icon: a
                            // chosen part is named in the corner of its neck.
                            if (roomy) ...[
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 140),
                                child: Text(
                                  controller.secondSong?.parts[controller.secondPart!].name ?? t.secondGuitar,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                if (song.parts.length > 1) const SizedBox(width: 8),
                // The chord badge keeps its place and size while the song
                // plays, so the eye always finds the chord in the same spot.
                if (settings.showChordName && song.hasEasy)
                  Container(
                    constraints: const BoxConstraints(minWidth: 72),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: chord == null ? glass : scheme.primary,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: chord == null ? glassBorder : Colors.transparent),
                      boxShadow: chord == null
                          ? null
                          : [BoxShadow(color: scheme.primary.withValues(alpha: 0.45), blurRadius: 16)],
                    ),
                    child: Text(
                      chord ?? '\u2013',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: chord == null ? scheme.onSurfaceVariant : scheme.onPrimary),
                    ),
                  ),
                _BeatDots(controller: controller),
                const SizedBox(width: 12),
                if (song.hasEasy && song.hasFull)
                  SegmentedButton<TrackKind>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: TrackKind.full, label: Text(shortModes ? t.fullModeShort : t.fullMode)),
                      ButtonSegment(value: TrackKind.easy, label: Text(shortModes ? t.easyModeShort : t.easyMode)),
                    ],
                    selected: {controller.track},
                    onSelectionChanged: (s) => controller.setTrack(s.first),
                  ),
                if (imported)
                  PopupMenuButton<String>(
                    tooltip: t.removeSong,
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (_) async {
                      final navigator = Navigator.of(context);
                      controller.pause();
                      await removeImportedSongFlow(context, song.id);
                      if (!songs.isImported(song.id) && navigator.canPop()) navigator.pop();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'remove',
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.delete_outline_rounded),
                          const SizedBox(width: 10),
                          Text(t.removeSong),
                        ]),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      );
    });
  }

  /// The other parts, for the second neck underneath: "None" or one of
  /// the parts that is not playing on the main neck. Opens on the current
  /// choice and closes as soon as one is picked.
  void _chooseSecondPart(BuildContext context) {
    final t = Strings.of(context);
    final song = controller.song;
    final scheme = Theme.of(context).colorScheme;
    final current = controller.secondPart;
    Widget tile(IconData icon, String name, bool selected, int? index) => ListTile(
          autofocus: selected,
          leading: Icon(icon),
          title: Text(name, style: const TextStyle(fontSize: 18)),
          trailing: Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: selected ? scheme.primary : null),
          onTap: () {
            Navigator.of(context).pop();
            controller.setSecondPart(index);
          },
        );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(t.secondPart, style: TextStyle(fontSize: 15, color: scheme.primary, fontWeight: FontWeight.w600)),
            ),
            tile(Icons.hide_source_rounded, t.none, current == null, null),
            for (final (i, p) in song.parts.indexed)
              if (i != song.partIndex) tile(Icons.queue_music_rounded, p.name, current == i, i),
          ],
        ),
      ),
    );
  }

  /// The list of parts (guitars) in the file. With a remote the part that
  /// is playing now is selected when the list opens, and choosing one
  /// closes the list.
  void _choosePart(BuildContext context) {
    final t = Strings.of(context);
    final song = controller.song;
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(t.part, style: TextStyle(fontSize: 15, color: scheme.primary, fontWeight: FontWeight.w600)),
            ),
            for (final (i, p) in song.parts.indexed)
              ListTile(
                autofocus: i == song.partIndex,
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(p.name, style: const TextStyle(fontSize: 18)),
                trailing: Icon(
                  i == song.partIndex ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: i == song.partIndex ? scheme.primary : null,
                ),
                onTap: () {
                  Navigator.of(sheet).pop();
                  onPart(i);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// One dot per beat of the bar; the current beat lights up.
class _BeatDots extends StatelessWidget {
  const _BeatDots({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final bpb = controller.song.beatsPerBar;
    final active = controller.isPlaying && controller.countdown == null;
    final beat = controller.beatInBar;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < bpb; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == 0 ? 16 : 12,
            height: i == 0 ? 16 : 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active && i == beat ? (i == 0 ? Theme.of(context).colorScheme.primary : Colors.white) : glassHighest,
              boxShadow: active && i == beat ? [BoxShadow(color: Colors.white.withValues(alpha: 0.5), blurRadius: 8)] : null,
            ),
          ),
      ],
    );
  }
}

/// The neck (or two necks, when a second part is shown underneath) with the
/// count-in and the "well done" card on top.
class _Neck extends StatelessWidget {
  const _Neck({required this.controller, required this.time, this.remoteHint = false});

  final PlaybackController controller;
  final ValueNotifier<double> time;

  /// Show the line about the remote's keys while the song waits at the start.
  final bool remoteHint;

  NeckStyle _style(AppSettings settings, Song song) => NeckStyle(
        leftHanded: settings.leftHanded,
        thinOnTop: settings.thinStringOnTop,
        highContrast: settings.highContrast,
        fretNumbers: settings.dotLabel == DotLabel.fret,
        // The built-in songs fit 12 frets; songs from files may go higher.
        // One spare fret after the highest note keeps a dot on the highest
        // fret, and the ring that closes in on it, inside the screen.
        frets: song.maxFret < 12 ? 12 : (song.maxFret + 1).clamp(12, 24),
      );

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final settings = SettingsScope.of(context);
    final synth = AppServices.of(context).synth;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, time]),
      builder: (context, _) {
        final scene = buildScene(
          controller,
          time: time.value,
          noteNames: settings.showNoteNames,
          serbianNames: t.language.isSerbian,
        );
        final second = controller.secondSong;
        final main = FretboardView(
          scene: scene,
          style: _style(settings, controller.song),
          onTap: (string, fret) {
            if (controller.waiting) {
              controller.next();
            } else {
              synth.play([SynthNote(midi: controller.song.pitch(string, fret), string: string)]);
            }
          },
        );
        final neck = second == null
            ? main
            : Column(children: [
                Expanded(child: _Named(controller.song.parts[controller.song.partIndex].name, child: main)),
                Expanded(
                  child: _Named(
                    second.parts[second.partIndex].name,
                    child: FretboardView(
                      scene: buildScene(
                        controller,
                        time: time.value,
                        noteNames: settings.showNoteNames,
                        serbianNames: t.language.isSerbian,
                        second: true,
                      ),
                      style: _style(settings, second),
                      onTap: (string, fret) =>
                          synth.play([SynthNote(midi: second.pitch(string, fret), string: 0)]),
                    ),
                  ),
                ),
              ]);
        return LayoutBuilder(builder: (context, box) {
          // On a TV or tablet the neck sits on a pane of glass with the
          // finger legend underneath; a phone sideways has no room to spare.
          final roomy = box.maxHeight >= 330 && box.maxWidth >= 700;
          final style = _style(settings, controller.song);
          final framed = roomy
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: GlassPanel(
                    color: glassLow,
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
                    child: Column(children: [
                      Expanded(child: neck),
                      if (second == null) NeckLegend(style: style, fretNumbers: settings.dotLabel == DotLabel.fret),
                    ]),
                  ),
                )
              : neck;
          return Stack(
          fit: StackFit.expand,
          children: [
            framed,
            if (remoteHint && !controller.isPlaying && controller.countdown == null && !controller.finished && controller.position <= 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 30,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1022).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: glassBorder),
                      ),
                      child: Text(t.remoteHint, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ),
              ),
            if (controller.countdown != null)
              IgnorePointer(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(t.getReady, style: const TextStyle(fontSize: 22, color: Colors.white70)),
                    Text(
                      '${controller.countdown}',
                      style: const TextStyle(
                        fontSize: 120,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(blurRadius: 18, color: Colors.black)],
                      ),
                    ),
                  ]),
                ),
              ),
            if (controller.finished)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: GlassPanel(
                  color: const Color(0xFF0B1022).withValues(alpha: 0.92),
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.emoji_events_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
                    Text(t.wellDone, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 18),
                    PrimaryButton(
                      autofocus: true,
                      onPressed: controller.play,
                      icon: Icons.replay_rounded,
                      label: t.playAgain,
                    ),
                  ]),
                ),
              ),
          ],
        );
        });
      },
    );
  }
}

/// A neck with the name of its part in the corner, for telling two apart.
class _Named extends StatelessWidget {
  const _Named(this.name, {required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      child,
      Positioned(
        left: 8,
        top: 2,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1022).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: glassBorder),
            ),
            child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ),
    ]);
  }
}

/// Seconds as m:ss.
String _clock(double seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _Progress extends StatelessWidget {
  const _Progress({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final total = controller.totalBeats <= 0 ? 1.0 : controller.totalBeats;
        final loop = controller.loop;
        final song = controller.song;
        final bpb = song.beatsPerBar;
        final position = controller.position.clamp(0.0, total);
        // Where you are: the bar on the left, the time on the right. The
        // time is at the chosen speed, so it matches the clock on the wall.
        final bar = (position / bpb).floor() + 1;
        final bars = (total / bpb).ceil();
        final secondsPerBeat = 60 / (song.tempo * controller.speed);
        final labelStyle = TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        final slider = Stack(
          alignment: Alignment.center,
          children: [
            if (loop != null)
              Positioned.fill(
                child: LayoutBuilder(builder: (context, box) {
                  const pad = 24.0;
                  final w = box.maxWidth - pad * 2;
                  return Stack(children: [
                    Positioned(
                      left: pad + w * loop.start / total,
                      width: w * (loop.end - loop.start) / total,
                      top: 6,
                      bottom: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.33),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ]);
                }),
              ),
            ExcludeFocus(
              child: Slider(
                value: position,
                max: total,
                onChanged: controller.seek,
              ),
            ),
          ],
        );
        return SizedBox(
          height: 28,
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(t.barOf(bar.clamp(1, bars), bars), style: labelStyle),
            ),
            Expanded(child: slider),
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Text(
                '${_clock(position * secondsPerBeat)} / ${_clock(total * secondsPerBeat)}',
                style: labelStyle,
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// The buttons under the neck. Only what a beginner needs is shown; the
/// rest is behind "More". The big button keeps the remote's focus the whole
/// time: it plays, pauses, and in "Wait for me" moves on to the next note.
class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final PlaybackController controller;

  static const _speedStep = 0.05;

  /// Below this width (logical pixels) the player uses the short texts.
  static const compactWidth = 700.0;

  /// Below this width the buttons under the neck lose their labels.
  static const labelsWidth = 900.0;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return LayoutBuilder(builder: (context, box) {
      // A phone held sideways is narrow: the words under the small buttons
      // go (they stay as tooltips) so the row never runs off the screen.
      // With nine buttons the words need a little more room than the top bar.
      final compact = box.maxWidth < labelsWidth;
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final (mainIcon, mainLabel, mainAction) = c.waiting
              ? (Icons.skip_next_rounded, t.next, c.next)
              : c.isPlaying
                  ? (Icons.pause_rounded, t.pause, c.pause)
                  : (Icons.play_arrow_rounded, t.play, c.play);
          final percent = (c.speed * 100).round();
          Widget toggle(IconData icon, String label, bool selected, VoidCallback? onPressed) =>
              LabeledToggle(icon: icon, label: label, selected: selected, onPressed: onPressed, showLabel: !compact);
          final gap = SizedBox(width: compact ? 6 : 10);
          // On a wide screen the row keeps clear of the edges, so the ring
          // and the glow around the big button are not cut off.
          final side = compact ? 12.0 : 24.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(side, 2, side, compact ? 4 : 8),
            child: Row(
              children: [
                SizedBox(
                  width: compact ? 120 : 150,
                  child: PrimaryButton(
                    autofocus: true,
                    onPressed: mainAction,
                    icon: mainIcon,
                    label: mainLabel,
                  ),
                ),
                gap,
                // Moving through the song: the three buttons sit together in
                // one pill, so they read as one group. One bar back or forward
                // is the only way to move through the song with a remote,
                // since the progress bar is not focusable. They stay enabled
                // at both ends, so the remote's focus never jumps away when
                // the song reaches the start or the end.
                ControlGroup(children: [
                  toggle(Icons.replay_rounded, t.restart, false, c.restart),
                  toggle(Icons.fast_rewind_rounded, t.back1Bar, false, () => c.seekBars(-1)),
                  toggle(Icons.fast_forward_rounded, t.forward1Bar, false, () => c.seekBars(1)),
                ]),
                gap,
                toggle(Icons.front_hand_rounded, t.waitMode, c.waitMode, () => c.setWaitMode(!c.waitMode)),
                const Spacer(),
                // The speed: minus, the number, plus, in one pill.
                ControlGroup(children: [
                  toggle(
                    Icons.remove_rounded,
                    t.slower,
                    false,
                    c.speed <= PlaybackController.minSpeed + 1e-9 ? null : () => c.setSpeed(c.speed - _speedStep),
                  ),
                  SizedBox(
                    width: compact ? 56 : 64,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$percent%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      if (!compact) Text(t.speed, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                  toggle(
                    Icons.add_rounded,
                    t.faster,
                    false,
                    c.speed >= 1 - 1e-9 ? null : () => c.setSpeed(c.speed + _speedStep),
                  ),
                ]),
                gap,
                toggle(
                  Icons.tune_rounded,
                  t.more,
                  c.loop != null || c.metronome || c.soundMode != SoundMode.song || c.secondPart != null,
                  () => _showMore(context),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  /// Sound, click and repeat: useful later, not needed for the first song.
  void _showMore(BuildContext context) {
    final t = Strings.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final scheme = Theme.of(context).colorScheme;
          Widget option(IconData icon, String label, bool selected, VoidCallback onTap, {bool autofocus = false}) =>
              ListTile(
                autofocus: autofocus,
                leading: Icon(icon),
                title: Text(label, style: const TextStyle(fontSize: 18)),
                trailing: Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? scheme.primary : null,
                ),
                onTap: onTap,
              );
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                for (final (i, m) in c.soundModes.indexed)
                  option(
                    switch (m) {
                      SoundMode.song => Icons.volume_up_rounded,
                      SoundMode.accompany => Icons.queue_music_rounded,
                      SoundMode.mute => Icons.volume_off_rounded,
                    },
                    switch (m) {
                      SoundMode.song => t.soundSong,
                      SoundMode.accompany => t.soundAccompany,
                      SoundMode.mute => t.soundMute,
                    },
                    c.soundMode == m,
                    () => c.setSoundMode(m),
                    autofocus: i == 0,
                  ),
                const Divider(),
                option(Icons.timer_outlined, t.metronome, c.metronome, () => c.setMetronome(!c.metronome)),
                option(
                  Icons.repeat_rounded,
                  c.loop == null ? t.loop : t.loopBars(c.loopBars),
                  c.loop != null,
                  c.toggleLoop,
                ),
                if (c.song.parts.length > 1) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(t.secondPart, style: TextStyle(fontSize: 15, color: scheme.primary, fontWeight: FontWeight.w600)),
                  ),
                  // Choosing a part is the end of the visit: the sheet closes
                  // (with a remote, Back would otherwise be one more press).
                  option(Icons.hide_source_rounded, t.none, c.secondPart == null, () {
                    c.setSecondPart(null);
                    Navigator.of(context).pop();
                  }),
                  for (final (i, p) in c.song.parts.indexed)
                    if (i != c.song.partIndex)
                      option(Icons.queue_music_rounded, p.name, c.secondPart == i, () {
                        c.setSecondPart(i);
                        Navigator.of(context).pop();
                      }),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
