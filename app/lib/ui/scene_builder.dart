import 'dart:math' as math;

import '../models/song.dart';
import '../music/pitch.dart';
import '../playback/cue.dart';
import '../playback/playback_controller.dart';
import '../settings/settings.dart';
import 'fretboard.dart';

/// Works out what the neck shows at the controller's current position:
/// solid dots for what to hold now, small dim dots for what comes next
/// (as many as [preview] asks for), glowing strings for what was just
/// played.
///
/// By default it draws the controller's own part. With [second] it draws the
/// part on the second neck ([PlaybackController.secondSong]) at the same
/// moment of the song.
NeckScene buildScene(
  PlaybackController c, {
  required double time,
  bool noteNames = false,
  bool serbianNames = false,
  bool second = false,
  NotePreview preview = NotePreview.several,
}) {
  final cues = second ? c.secondCues : c.cues;
  final song = second ? c.secondSong ?? c.song : c.song;
  final pos = c.position;
  final bps = c.beatsPerSecond;
  // "The next few" looks about 1.2 seconds ahead (at least half a beat).
  final lookAhead = math.max(0.5, 1.2 * bps);

  String? label(int string, int fret) =>
      noteNames ? noteName(song.pitch(string, fret), serbian: serbianNames) : null;

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

  // What comes next: the next cue, or everything within the look-ahead,
  // as small dim dots that keep still. The next cue is a little brighter
  // than the ones after it, and nothing flickers: a note is either the
  // one to play now (big and bright) or one that is coming.
  final seen = <(int, int)>{};
  var upcoming = 0;
  for (var i = idx; i < cues.length && preview != NotePreview.none; i++) {
    final cue = cues[i];
    if (identical(cue, current)) continue;
    if (upcoming > 0 && (preview == NotePreview.next || cue.beat > pos + lookAhead)) break;
    upcoming++;
    for (final p in cue.presses) {
      final key = (p.string, p.fret);
      if (held.contains(key) || !seen.add(key)) continue;
      dots.add(NeckDot(
        string: p.string,
        fret: p.fret,
        finger: p.finger,
        opacity: upcoming == 1 ? 0.6 : 0.35,
        scale: upcoming == 1 ? 0.72 : 0.6,
        label: label(p.string, p.fret),
      ));
    }
    if (current == null && upcoming == 1) {
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
    pulse: c.waiting && !second,
    time: time,
  );
}
