import 'dart:math' as math;

import '../models/song.dart';
import '../music/pitch.dart';
import '../playback/cue.dart';
import '../playback/playback_controller.dart';
import 'fretboard.dart';

/// Works out what the neck shows at the controller's current position:
/// solid dots for what to hold now, fading-in dots for what comes next,
/// glowing strings for what was just played.
NeckScene buildScene(
  PlaybackController c, {
  required double time,
  bool noteNames = false,
  bool serbianNames = false,
}) {
  final cues = c.cues;
  final pos = c.position;
  final bps = c.beatsPerSecond;
  // Show upcoming notes about 1.2 seconds ahead (at least half a beat).
  final preview = math.max(0.5, 1.2 * bps);

  String? label(int string, int fret) =>
      noteNames ? noteName(c.song.pitch(string, fret), serbian: serbianNames) : null;

  final idx = firstCueAtOrAfter(cues, pos + 1e-9);
  // The cue being played now is the last one that has started.
  Cue? current;
  if (idx > 0) {
    final last = cues[idx - 1];
    // Chords stay held until the next strum; single notes until they end.
    final holdUntil = last.chord != null ? double.infinity : last.end + 0.15;
    if (pos < holdUntil || c.waiting) current = last;
  }

  final dots = <NeckDot>[];
  final held = <(int, int)>{};
  if (current != null) {
    for (final p in current.presses) {
      held.add((p.string, p.fret));
      dots.add(NeckDot(string: p.string, fret: p.fret, finger: p.finger, label: label(p.string, p.fret)));
    }
  }

  final openStrings = <int>{};
  final muted = <int>{...?current?.muted};
  final openLabels = <int, String>{};
  if (current != null) {
    for (final s in current.strings) {
      if (current.fretOn(s) == 0) {
        openStrings.add(s);
        final l = label(s, 0);
        if (l != null) openLabels[s] = l;
      }
    }
  }

  // Upcoming notes fade in.
  final seen = <(int, int)>{};
  for (var i = idx; i < cues.length && cues[i].beat <= pos + preview; i++) {
    final cue = cues[i];
    if (identical(cue, current)) continue;
    final approach = (1 - (cue.beat - pos) / preview).clamp(0.0, 1.0);
    for (final p in cue.presses) {
      final key = (p.string, p.fret);
      if (held.contains(key) || !seen.add(key)) continue;
      dots.add(NeckDot(
        string: p.string,
        fret: p.fret,
        finger: p.finger,
        opacity: 0.25 + 0.55 * approach,
        approach: approach * 0.98,
        label: label(p.string, p.fret),
      ));
    }
    if (current == null) {
      // Nothing held yet: show the first chord's open and muted strings too.
      for (final s in cue.strings) {
        if (cue.fretOn(s) == 0) openStrings.add(s);
      }
      muted.addAll(cue.muted);
    }
  }

  // Strings glow when plucked. A strum sweeps across the strings in order.
  final pluckAge = <int, double>{};
  Strum? strum;
  var strumProgress = 1.0;
  final animating = (c.isPlaying && c.countdown == null) || c.waiting;
  for (var i = idx - 1; animating && i >= 0; i--) {
    final cue = cues[i];
    final age = (pos - cue.beat) / bps;
    if (age > 1.2) break;
    final spacing = cue.strum != null ? 0.014 : 0.0;
    for (var k = 0; k < cue.strings.length; k++) {
      final s = cue.strings[k];
      pluckAge.putIfAbsent(s, () => age - k * spacing);
    }
    if (strum == null && cue.strum != null && age < 0.5) {
      strum = cue.strum;
      strumProgress = age / 0.3;
    }
  }

  return NeckScene(
    dots: dots,
    pluckAge: pluckAge,
    openStrings: openStrings,
    mutedStrings: muted,
    openLabels: openLabels,
    strum: strum,
    strumProgress: strumProgress,
    pulse: c.waiting,
    time: time,
  );
}
