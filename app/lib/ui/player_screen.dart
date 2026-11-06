import 'dart:math' as math;

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

/// The main screen: a full-screen guitar neck that plays a song.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.songId});

  final String songId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with SingleTickerProviderStateMixin, LandscapeScreen {
  PlaybackController? _controller;
  Object? _error;
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _time.value = elapsed.inMicroseconds / 1e6)..start();
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
      setState(() => _controller = _newController(song, speed: settings.defaultSpeed));
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
    final next = _newController(old.song.withPart(index), speed: old.speed, track: old.track);
    old.dispose();
    setState(() => _controller = next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final c = _controller;
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
        const SingleActivator(LogicalKeyboardKey.mediaRewind): c.restart,
        const SingleActivator(LogicalKeyboardKey.mediaFastForward): () => c.setSpeed(c.speed + 0.05),
        const SingleActivator(LogicalKeyboardKey.channelUp): () => c.setSpeed(c.speed + 0.05),
        const SingleActivator(LogicalKeyboardKey.channelDown): () => c.setSpeed(c.speed - 0.05),
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(controller: c, onPart: _selectPart),
              Expanded(child: _Neck(controller: c, time: _time)),
              _Progress(controller: c),
              _Controls(controller: c),
            ],
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
                      t.script(song.info.titleFor(t.language.songLang)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                PopupMenuButton<int>(
                  tooltip: t.part,
                  initialValue: song.partIndex,
                  onSelected: onPart,
                  itemBuilder: (_) => [
                    for (final (i, p) in song.parts.indexed) PopupMenuItem(value: i, child: Text(p.name)),
                  ],
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.queue_music_rounded, size: 20),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
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
              if (settings.showChordName && chord != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(chord, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: scheme.onPrimary)),
                ),
              _BeatDots(controller: controller),
              const SizedBox(width: 12),
              if (song.hasEasy && song.hasFull)
                SegmentedButton<TrackKind>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: TrackKind.full, label: Text(t.fullMode)),
                    ButtonSegment(value: TrackKind.easy, label: Text(t.easyMode)),
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
              color: active && i == beat ? (i == 0 ? Theme.of(context).colorScheme.primary : Colors.white) : Colors.white24,
            ),
          ),
      ],
    );
  }
}

class _Neck extends StatelessWidget {
  const _Neck({required this.controller, required this.time});

  final PlaybackController controller;
  final ValueNotifier<double> time;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final settings = SettingsScope.of(context);
    final synth = AppServices.of(context).synth;
    final style = NeckStyle(
      leftHanded: settings.leftHanded,
      thinOnTop: settings.thinStringOnTop,
      highContrast: settings.highContrast,
      // The built-in songs fit 12 frets; songs from files may go higher.
      frets: math.max(12, controller.song.maxFret).clamp(12, 24),
    );
    return ListenableBuilder(
      listenable: Listenable.merge([controller, time]),
      builder: (context, _) {
        final scene = buildScene(
          controller,
          time: time.value,
          noteNames: settings.showNoteNames,
          serbianNames: t.language.isSerbian,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            FretboardView(
              scene: scene,
              style: style,
              onTap: (string, fret) {
                if (controller.waiting) {
                  controller.next();
                } else {
                  synth.play([SynthNote(midi: controller.song.pitch(string, fret), string: string)]);
                }
              },
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
                child: Card(
                  color: Colors.black.withValues(alpha: 0.8),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.emoji_events_rounded, size: 56, color: Color(0xFFF2C94C)),
                      Text(t.wellDone, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        autofocus: true,
                        onPressed: controller.play,
                        icon: const Icon(Icons.replay_rounded),
                        label: Text(t.playAgain),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final total = controller.totalBeats <= 0 ? 1.0 : controller.totalBeats;
        final loop = controller.loop;
        return SizedBox(
          height: 28,
          child: Stack(
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
                  value: controller.position.clamp(0, total),
                  max: total,
                  onChanged: controller.seek,
                ),
              ),
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              SizedBox(
                width: 170,
                child: FilledButton.icon(
                  autofocus: true,
                  onPressed: mainAction,
                  icon: Icon(mainIcon, size: 32),
                  label: Text(mainLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              LabeledToggle(icon: Icons.replay_rounded, label: t.restart, selected: false, onPressed: c.restart),
              LabeledToggle(
                icon: Icons.front_hand_rounded,
                label: t.waitMode,
                selected: c.waitMode,
                onPressed: () => c.setWaitMode(!c.waitMode),
              ),
              const Spacer(),
              LabeledToggle(
                icon: Icons.remove_rounded,
                label: t.slower,
                selected: false,
                onPressed: c.speed <= PlaybackController.minSpeed + 1e-9 ? null : () => c.setSpeed(c.speed - _speedStep),
              ),
              SizedBox(
                width: 72,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.speed_rounded, size: 20),
                  Text('$percent%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ]),
              ),
              LabeledToggle(
                icon: Icons.add_rounded,
                label: t.faster,
                selected: false,
                onPressed: c.speed >= 1 - 1e-9 ? null : () => c.setSpeed(c.speed + _speedStep),
              ),
              const SizedBox(width: 12),
              LabeledToggle(
                icon: Icons.tune_rounded,
                label: t.more,
                selected: c.loop != null || c.metronome || c.soundMode != SoundMode.song,
                onPressed: () => _showMore(context),
              ),
            ],
          ),
        );
      },
    );
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
              ],
            ),
          );
        },
      ),
    );
  }
}
