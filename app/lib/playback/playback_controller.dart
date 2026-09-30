import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../audio/synth.dart';
import '../models/chord.dart';
import '../models/song.dart';
import 'cue.dart';

enum TrackKind { easy, full }

/// How a cue is voiced when it is played.
enum _Voice { lead, melody, backing, accompany }

/// What the app plays out loud.
enum SoundMode {
  /// "Play the song for me": the app plays everything shown on the neck.
  song,

  /// "I play, app accompanies": the app plays only chords (or bass notes in
  /// chord mode) and the player plays the rest.
  accompany,

  /// No sound.
  mute,
}

/// A MIDI-style sequencer: moves through the song at the song's tempo times
/// the speed setting, sends notes to the synthesizer slightly ahead of time,
/// and tells the neck view what to draw.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.song,
    required this.chords,
    required this.synth,
    TrackKind track = TrackKind.full,
    double speed = 1,
    this.countIn = true,
    double Function()? clock,
    this.autoTick = true,
  }) : _clock = clock ?? _stopwatchClock() {
    _speed = speed.clamp(minSpeed, 1.0);
    // Note by note is the default; chords are the alternative when the song has them.
    _track = (track == TrackKind.easy && !song.hasEasy) || (track == TrackKind.full && !song.hasFull)
        ? (song.hasFull ? TrackKind.full : TrackKind.easy)
        : track;
    _easyCues = cuesFromChords(song.easy, chords);
    _fullCues = cuesFromNotes(song.full);
  }

  static const minSpeed = 0.25;

  /// How far ahead notes are handed to the synthesizer.
  static const _lookaheadSeconds = 0.12;

  static const countInBeats = 3;

  final Song song;
  final ChordLibrary chords;
  final Synth synth;
  final bool autoTick;
  bool countIn;
  final double Function() _clock;

  late final List<Cue> _easyCues;
  late final List<Cue> _fullCues;
  late TrackKind _track;
  late double _speed;

  double _position = 0;
  bool _playing = false;
  int? _countdown;
  double _countdownStart = 0;
  double _anchorBeat = 0;
  double _anchorTime = 0;
  double _scheduledUntil = 0;
  bool _finished = false;

  SoundMode _soundMode = SoundMode.song;
  bool _metronome = false;
  bool _waitMode = false;
  bool _waiting = false;
  int _waitIndex = 0;
  ({double start, double end})? _loop;
  Timer? _timer;

  static double Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMicroseconds / 1e6;
  }

  // ---- State for the UI --------------------------------------------------

  TrackKind get track => _track;
  List<Cue> get cues => _track == TrackKind.easy ? _easyCues : _fullCues;
  double get position => _position;
  double get totalBeats => song.totalBeats;
  bool get isPlaying => _playing || _countdown != null;
  int? get countdown => _countdown;
  bool get finished => _finished;
  double get speed => _speed;
  SoundMode get soundMode => _soundMode;
  bool get metronome => _metronome;
  bool get waitMode => _waitMode;
  bool get waiting => _waiting;
  ({double start, double end})? get loop => _loop;

  double get beatsPerSecond => song.tempo / 60 * _speed;
  int get beatInBar => (_position.floor()) % song.beatsPerBar;

  /// Name of the chord at the current position (from the chord track).
  String? get currentChord {
    final i = firstCueAtOrAfter(_easyCues, _position + 1e-6) - 1;
    if (i < 0) return _easyCues.isNotEmpty && _position <= 0 ? _easyCues.first.chord : null;
    return _easyCues[i].chord;
  }

  // ---- Controls ----------------------------------------------------------

  void play() {
    if (isPlaying) return;
    if (_finished || _position >= totalBeats) seek(0);
    _finished = false;
    if (countIn && !_waitMode) {
      _countdownStart = _clock();
      _countdown = countInBeats;
      final spb = 1000 / beatsPerSecond;
      for (var i = 0; i < countInBeats; i++) {
        synth.click(accent: i == 0, delayMs: i * spb);
      }
    } else {
      _startClock();
    }
    _ensureTimer();
    notifyListeners();
  }

  void pause() {
    if (!isPlaying && !_waiting) return;
    _playing = false;
    _countdown = null;
    _waiting = false;
    _timer?.cancel();
    _timer = null;
    synth.stopAll();
    _scheduledUntil = _position;
    notifyListeners();
  }

  void togglePlay() => isPlaying ? pause() : play();

  void restart() {
    final wasPlaying = isPlaying;
    pause();
    seek(_loop?.start ?? 0);
    if (wasPlaying) play();
  }

  void seek(double beat) {
    _position = beat.clamp(0.0, totalBeats);
    _finished = false;
    _waiting = false;
    _waitIndex = firstCueAtOrAfter(cues, _position);
    _anchorBeat = _position;
    _anchorTime = _clock();
    _scheduledUntil = _position;
    if (_playing) synth.stopAll();
    notifyListeners();
  }

  void setSpeed(double value) {
    final s = value.clamp(minSpeed, 1.0);
    if (s == _speed) return;
    _reanchor();
    _speed = s;
    notifyListeners();
  }

  void setTrack(TrackKind kind) {
    if (kind == _track) return;
    if (kind == TrackKind.easy && !song.hasEasy) return;
    if (kind == TrackKind.full && !song.hasFull) return;
    final wasPlaying = isPlaying;
    pause();
    _track = kind;
    seek(_position);
    if (wasPlaying) play();
  }

  /// Sound modes this song offers: accompaniment needs chords.
  List<SoundMode> get soundModes => [
        for (final m in SoundMode.values)
          if (m != SoundMode.accompany || song.hasEasy) m,
      ];

  /// Moves to the next sound mode this song offers.
  void nextSoundMode() {
    final modes = soundModes;
    setSoundMode(modes[(modes.indexOf(_soundMode) + 1) % modes.length]);
  }

  void setSoundMode(SoundMode mode) {
    if (mode == SoundMode.accompany && !song.hasEasy) return;
    _soundMode = mode;
    synth.stopAll();
    _scheduledUntil = _position;
    notifyListeners();
  }

  void setMetronome(bool on) {
    _metronome = on;
    notifyListeners();
  }

  void setWaitMode(bool on) {
    _waitMode = on;
    _waiting = false;
    _waitIndex = firstCueAtOrAfter(cues, _position);
    _reanchor();
    notifyListeners();
  }

  /// Loops the two bars around the current position; tapped again the loop
  /// grows to four bars, and once more it is cleared.
  void toggleLoop() {
    final bpb = song.beatsPerBar;
    final loop = _loop;
    if (loop == null) {
      final start = (_position / bpb).floor() * bpb.toDouble();
      final end = math.min(start + 2 * bpb, totalBeats);
      _loop = (start: start, end: end);
      if (_position < start || _position >= end) seek(start);
    } else if (loop.end - loop.start <= 2 * bpb + 1e-9 && loop.end < totalBeats) {
      _loop = (start: loop.start, end: math.min(loop.start + 4 * bpb, totalBeats));
    } else {
      _loop = null;
    }
    notifyListeners();
  }

  /// How many bars the loop covers (0 without a loop).
  int get loopBars => _loop == null ? 0 : ((_loop!.end - _loop!.start) / song.beatsPerBar).ceil();

  /// In wait mode: the player played the note, move on to the next one.
  void next() {
    if (!_waiting) {
      if (!isPlaying) play();
      return;
    }
    _waiting = false;
    _waitIndex++;
    _anchorBeat = _position;
    _anchorTime = _clock();
    _scheduledUntil = _position + 1e-6;
    _ensureTimer();
    notifyListeners();
  }

  // ---- Clock -------------------------------------------------------------

  void _startClock() {
    _playing = true;
    _anchorBeat = _position;
    _anchorTime = _clock();
    _scheduledUntil = _position;
    _waitIndex = firstCueAtOrAfter(cues, _position);
  }

  void _reanchor() {
    _anchorBeat = _position;
    _anchorTime = _clock();
  }

  void _ensureTimer() {
    if (!autoTick || _timer != null) return;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => tick());
  }

  /// Advances the song to the current time. Called about 60 times a second.
  @visibleForTesting
  void tick() {
    final now = _clock();
    if (_countdown != null) {
      final beats = (now - _countdownStart) * beatsPerSecond;
      if (beats >= countInBeats) {
        _countdown = null;
        _startClock();
        _anchorTime = _countdownStart + countInBeats / beatsPerSecond;
      } else {
        final c = countInBeats - beats.floor();
        if (c != _countdown) {
          _countdown = c;
          notifyListeners();
        }
        return;
      }
    }
    if (!_playing || _waiting) return;

    var pos = _anchorBeat + (now - _anchorTime) * beatsPerSecond;

    if (_waitMode && _waitIndex < cues.length && pos >= cues[_waitIndex].beat) {
      // Stop on the next note and play it, then wait for the player.
      final cue = cues[_waitIndex];
      _position = cue.beat;
      _waiting = true;
      _sound(cue, 0, _Voice.lead);
      notifyListeners();
      return;
    }

    final loop = _loop;
    if (loop != null && pos >= loop.end) {
      pos = loop.start + (pos - loop.end) % (loop.end - loop.start);
      _anchorBeat = pos;
      _anchorTime = now;
      _scheduledUntil = loop.start;
      _waitIndex = firstCueAtOrAfter(cues, loop.start);
    }

    if (pos >= totalBeats) {
      _position = totalBeats;
      _playing = false;
      _finished = true;
      _timer?.cancel();
      _timer = null;
      notifyListeners();
      return;
    }

    _position = pos;
    if (!_waitMode) _schedule(pos, loop);
    notifyListeners();
  }

  /// Hands the synthesizer everything due within the lookahead window.
  void _schedule(double pos, ({double start, double end})? loop) {
    var until = pos + _lookaheadSeconds * beatsPerSecond;
    if (loop != null) until = math.min(until, loop.end);
    until = math.min(until, totalBeats);
    if (until <= _scheduledUntil) return;

    final from = _scheduledUntil;
    final msPerBeat = 1000 / beatsPerSecond;

    for (final (cues, voice) in _soundTracks()) {
      for (var i = firstCueAtOrAfter(cues, from); i < cues.length && cues[i].beat < until; i++) {
        _sound(cues[i], (cues[i].beat - pos) * msPerBeat, voice);
      }
    }

    if (_metronome) {
      for (var b = from.ceilToDouble(); b < until; b++) {
        synth.click(accent: b.toInt() % song.beatsPerBar == 0, delayMs: (b - pos) * msPerBeat);
      }
    }
    _scheduledUntil = until;
  }

  List<(List<Cue>, _Voice)> _soundTracks() => switch (_soundMode) {
        SoundMode.mute => const [],
        SoundMode.song => _track == TrackKind.full || !song.hasFull
            ? [(cues, _Voice.lead)]
            // Chords alone do not tell which song it is: play the melody on
            // top and the strums softly underneath, like a singer with a guitar.
            : [(_easyCues, _Voice.backing), (_fullCues, _Voice.melody)],
        SoundMode.accompany => [(_easyCues, _Voice.accompany)],
      };

  void _sound(Cue cue, double delayMs, _Voice voice) {
    if (_soundMode == SoundMode.mute) return;
    final msPerBeat = 1000 / beatsPerSecond;
    final duration = cue.length * msPerBeat;
    final notes = <SynthNote>[];
    final strings = voice == _Voice.accompany && _track == TrackKind.easy
        // Chords shown on the neck and the app accompanies: play just the bass note.
        ? (cue.strum == Strum.down ? cue.strings.take(1).toList() : const <int>[])
        : cue.strings;
    final isStrum = cue.strum != null && strings.length > 1;
    final spacing = isStrum ? 14.0 : 0.0;
    final baseVelocity = switch (voice) {
      _Voice.accompany => 0.45,
      _Voice.backing => cue.strum == Strum.up ? 0.3 : 0.45,
      _Voice.melody => 0.95,
      _Voice.lead => cue.strum == Strum.up ? 0.6 : 0.85,
    };
    for (var k = 0; k < strings.length; k++) {
      final s = strings[k];
      notes.add(SynthNote(
        midi: song.pitch(s, cue.fretOn(s)),
        velocity: baseVelocity,
        delayMs: math.max(0, delayMs) + k * spacing,
        durationMs: duration,
        // Backing strums are not tied to a string, so they never cut off a
        // melody note that happens to be on the same string.
        string: voice == _Voice.backing ? 0 : s,
      ));
    }
    synth.play(notes);
  }

  @override
  void dispose() {
    _timer?.cancel();
    synth.stopAll();
    super.dispose();
  }
}
