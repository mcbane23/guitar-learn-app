import '../models/chord.dart';
import '../models/song.dart';

/// A finger on a fret.
class FretPress {
  const FretPress({required this.string, required this.fret, required this.finger});
  final int string;
  final int fret;
  final int finger;
}

/// Everything that happens at one moment of a song: which frets to hold,
/// which strings to play, and (for chords) the strum direction.
class Cue {
  const Cue({
    required this.beat,
    required this.length,
    required this.presses,
    required this.strings,
    this.muted = const [],
    this.chord,
    this.strum,
  });

  final double beat;
  final double length;

  /// Fretted notes (fret > 0) to hold down.
  final List<FretPress> presses;

  /// Strings to play, in playing order (thick to thin for a down strum).
  final List<int> strings;

  /// Strings that must not be played (drawn with an X at the nut).
  final List<int> muted;

  final String? chord;
  final Strum? strum;

  double get end => beat + length;

  int fretOn(int string) {
    for (final p in presses) {
      if (p.string == string) return p.fret;
    }
    return 0;
  }
}

/// One cue per note start in a "full" track; notes starting together form one cue.
List<Cue> cuesFromNotes(List<NoteEvent> notes) {
  final cues = <Cue>[];
  var i = 0;
  while (i < notes.length) {
    final beat = notes[i].beat;
    final group = <NoteEvent>[];
    while (i < notes.length && (notes[i].beat - beat).abs() < 1e-6) {
      group.add(notes[i++]);
    }
    group.sort((a, b) => b.string.compareTo(a.string));
    cues.add(Cue(
      beat: beat,
      length: group.map((n) => n.length).reduce((a, b) => a > b ? a : b),
      presses: [
        for (final n in group)
          if (n.fret > 0) FretPress(string: n.string, fret: n.fret, finger: n.finger),
      ],
      strings: [for (final n in group) n.string],
    ));
  }
  return cues;
}

/// One cue per strum in an "easy" (chords) track.
List<Cue> cuesFromChords(List<ChordEvent> events, ChordLibrary chords) {
  return [
    for (final e in events)
      if (chords[e.chord] case final shape?)
        Cue(
          beat: e.beat,
          length: e.length,
          chord: e.chord,
          strum: e.strum,
          presses: [
            for (var s = 1; s <= 6; s++)
              if (shape.fretOn(s) > 0) FretPress(string: s, fret: shape.fretOn(s), finger: shape.fingerOn(s)),
          ],
          strings: e.strum == Strum.up ? shape.playedStrings.reversed.toList() : shape.playedStrings,
          muted: [for (var s = 1; s <= 6; s++) if (!shape.plays(s)) s],
        ),
  ];
}

/// Index of the first cue that starts at or after [beat].
int firstCueAtOrAfter(List<Cue> cues, double beat) {
  var lo = 0, hi = cues.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (cues[mid].beat < beat - 1e-9) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}
