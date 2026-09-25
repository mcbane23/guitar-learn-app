import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../audio/synth.dart';
import '../l10n/strings.dart';
import '../playback/playback_controller.dart';
import '../settings/settings.dart';
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
      setState(() {
        _controller = PlaybackController(
          song: song,
          chords: services.songs.chords,
          synth: services.synth,
          speed: settings.defaultSpeed,
          countIn: settings.countIn,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
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
              _TopBar(controller: c),
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
  const _TopBar({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final settings = SettingsScope.of(context);
    final song = controller.song;
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
                child: Text(
                  t.script(song.info.titleFor(t.language.songLang)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              if (settings.showChordName && chord != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(chord,
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onPrimary)),
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
            if (controller.waiting)
              Positioned(
                right: 16,
                bottom: 16,
                child: FilledButton.icon(
                  autofocus: true,
                  onPressed: controller.next,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text(t.next),
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

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final (soundIcon, soundLabel) = switch (c.soundMode) {
          SoundMode.song => (Icons.volume_up_rounded, t.soundSong),
          SoundMode.accompany => (Icons.queue_music_rounded, t.soundAccompany),
          SoundMode.mute => (Icons.volume_off_rounded, t.soundMute),
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              SizedBox(
                width: 150,
                child: FilledButton.icon(
                  autofocus: true,
                  onPressed: c.togglePlay,
                  icon: Icon(c.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32),
                  label: Text(c.isPlaying ? t.pause : t.play),
                ),
              ),
              const SizedBox(width: 8),
              LabeledToggle(icon: Icons.replay_rounded, label: t.restart, selected: false, onPressed: c.restart),
              LabeledToggle(icon: Icons.repeat_rounded, label: t.loop, selected: c.loop != null, onPressed: c.toggleLoop),
              LabeledToggle(
                icon: Icons.front_hand_rounded,
                label: t.waitMode,
                selected: c.waitMode,
                onPressed: () => c.setWaitMode(!c.waitMode),
              ),
              LabeledToggle(
                icon: soundIcon,
                label: soundLabel,
                selected: c.soundMode != SoundMode.mute,
                onPressed: c.nextSoundMode,
              ),
              LabeledToggle(
                icon: Icons.timer_outlined,
                label: t.metronome,
                selected: c.metronome,
                onPressed: () => c.setMetronome(!c.metronome),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.speed_rounded),
              Expanded(
                child: Slider(
                  value: c.speed,
                  min: PlaybackController.minSpeed,
                  max: 1,
                  divisions: 15,
                  label: '${(c.speed * 100).round()}%',
                  onChanged: c.setSpeed,
                ),
              ),
              SizedBox(
                width: 56,
                child: Text('${(c.speed * 100).round()}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      },
    );
  }
}
