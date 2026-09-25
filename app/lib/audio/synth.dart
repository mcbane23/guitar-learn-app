import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One note for the synthesizer to play.
class SynthNote {
  const SynthNote({
    required this.midi,
    this.velocity = 0.8,
    this.delayMs = 0,
    this.durationMs = 1000,
    this.string = 0,
  });

  final int midi;
  final double velocity;

  /// How long from now until the note should sound.
  final double delayMs;
  final double durationMs;

  /// Guitar string 1-6, or 0 if not tied to a string. A new note on a string
  /// stops the previous one on the same string, like a real guitar.
  final int string;

  Map<String, Object> toMap() => {
        'midi': midi,
        'velocity': velocity,
        'delayMs': delayMs,
        'durationMs': durationMs,
        'string': string,
      };
}

/// Plays guitar notes generated live (no recordings).
abstract class Synth {
  void play(List<SynthNote> notes);
  void click({bool accent = false, double delayMs = 0});
  void stopAll();
  void setVolume(double volume);
}

/// The Android synthesizer (see android/.../GuitarSynth.kt).
class PlatformSynth implements Synth {
  static const _channel = MethodChannel('guitar_learn/synth');

  void _call(String method, [Object? args]) {
    _channel.invokeMethod<void>(method, args).catchError((Object e) {
      // No sound on this platform (e.g. widget tests); the app still works.
      if (kDebugMode && e is! MissingPluginException) debugPrint('synth: $e');
    });
  }

  @override
  void play(List<SynthNote> notes) {
    if (notes.isEmpty) return;
    _call('play', {'notes': [for (final n in notes) n.toMap()]});
  }

  @override
  void click({bool accent = false, double delayMs = 0}) =>
      _call('click', {'accent': accent, 'delayMs': delayMs});

  @override
  void stopAll() => _call('stopAll');

  @override
  void setVolume(double volume) => _call('setVolume', {'volume': volume});
}

/// Records what would be played; used in tests.
class RecordingSynth implements Synth {
  final notes = <SynthNote>[];
  final clicks = <({bool accent, double delayMs})>[];
  int stops = 0;
  double volume = 1;

  @override
  void play(List<SynthNote> n) => notes.addAll(n);

  @override
  void click({bool accent = false, double delayMs = 0}) =>
      clicks.add((accent: accent, delayMs: delayMs));

  @override
  void stopAll() => stops++;

  @override
  void setVolume(double v) => volume = v;
}
