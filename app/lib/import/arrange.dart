/// Turns an [ImportedScore] into a song file the app can play: picks a
/// string and fret for every note that has none, chooses fingers, builds a
/// chord track from chord names, and writes the song JSON (docs/PLAN.md, 5).
library;

import 'dart:math' as math;

import '../music/pitch.dart';
import 'score.dart';

/// The neck the app can show.
const maxFret = 24;

/// Time grid for note starts: 1/48 of a quarter note fits 16ths and triplets.
const _grid = 48;

double _snap(double quarters) => (quarters * _grid).round() / _grid;

/// Chord names the song files use, from a name written in a tab: "Amin" and
/// "A-" become "Am", "Cmaj7" becomes "C" when only "C" is known, "G/B" becomes
/// "G". Returns null when nothing close is in [known].
String? matchChordName(String raw, Set<String> known) {
  var name = raw.trim().replaceAll('♯', '#').replaceAll('♭', 'b');
  if (name.isEmpty) return null;
  final slash = name.indexOf('/');
  if (slash > 0) name = name.substring(0, slash);
  name = name.replaceAll(RegExp(r'\s+'), '');
  final m = RegExp(r'^([A-Ha-h])([#b]?)(.*)$').firstMatch(name);
  if (m == null) return null;
  var root = m.group(1)!.toUpperCase();
  final accidental = m.group(2)!;
  var rest = m.group(3)!;
  if (root == 'H') root = 'B'; // German / Serbian naming
  final minor = RegExp(r'^(min|m(?!aj)|-)').hasMatch(rest);
  rest = rest.replaceFirst(RegExp(r'^(min|maj|m(?!aj)|-|M)'), '');
  final base = '$root$accidental${minor ? 'm' : ''}';
  final candidates = <String>[
    '$base$rest',
    if (rest.isNotEmpty) '$base${_stripExtension(rest)}',
    base,
  ];
  for (final c in candidates) {
    if (known.contains(c)) return c;
  }
  return null;
}

/// "7sus4" -> "7", "add9" -> "", "9" -> "7".
String _stripExtension(String ext) {
  if (ext.startsWith('7') || ext.startsWith('9') || ext.startsWith('11') || ext.startsWith('13')) return '7';
  return '';
}

/// Sizes of a part after it has been placed on the neck.
class ArrangedPart {
  ArrangedPart({
    required this.name,
    required this.tuning,
    required this.capo,
    required this.notes,
  });

  final String name;
  final List<int> tuning;
  final int capo;

  /// Song-file note events (beat, string, fret, finger, length).
  final List<Map<String, num>> notes;
}

/// Places every note of [track] on the neck and picks fingers.
ArrangedPart arrangeTrack(ImportedTrack track, ImportedScore score) {
  final tuning = _tuningFor(track);
  final capo = track.capo.clamp(0, 12);
  final factor = _beatFactor(score);
  final notes = track.notes.toList()..sort((a, b) => a.start.compareTo(b.start));

  final out = <Map<String, num>>[];
  var hand = 1; // fret under the index finger
  int? prevString;
  var i = 0;
  while (i < notes.length) {
    // Notes that start together are one chord and share the hand position.
    final start = _snap(notes[i].start);
    final group = <ImportedNote>[];
    while (i < notes.length && _snap(notes[i].start) == start) {
      group.add(notes[i++]);
    }
    group.sort((a, b) => a.pitch.compareTo(b.pitch));
    final used = <int>{};
    final placed = <(ImportedNote, int, int)>[];
    for (final n in group) {
      final pos = _place(n, tuning, capo, used, hand, prevString);
      if (pos == null) continue;
      used.add(pos.$1);
      placed.add((n, pos.$1, pos.$2));
    }
    if (placed.isEmpty) continue;

    final fretted = [for (final p in placed) if (p.$3 > 0) p.$3];
    if (fretted.isNotEmpty) {
      final lo = fretted.reduce(math.min), hi = fretted.reduce(math.max);
      if (lo < hand || hi > hand + 3) hand = lo;
    }
    for (final (n, string, fret) in placed) {
      final finger = fret == 0
          ? 0
          : (n.finger != null && n.finger! >= 1 && n.finger! <= 4 ? n.finger! : (fret - hand + 1).clamp(1, 4));
      out.add({
        'beat': _round(start * factor),
        'string': string,
        'fret': fret,
        'finger': finger,
        'length': _round(math.max(n.duration, 1 / _grid) * factor),
      });
    }
    prevString = placed.last.$2;
  }
  return ArrangedPart(name: track.name, tuning: tuning, capo: capo, notes: out);
}

List<int> _tuningFor(ImportedTrack track) {
  final t = track.tuning;
  if (t != null && t.length >= 6) return t.sublist(0, 6);
  return standardTuning;
}

/// The song's beat as a fraction of a quarter note: 1 in 4/4, 2 in 6/8
/// counted in eighths, 2/3 in 6/8 counted in dotted quarters.
double _beatFactor(ImportedScore s) {
  if (s.beatUnit == 8 && s.beatsPerBar % 3 == 0 && s.beatsPerBar >= 6) return 2 / 3;
  return s.beatUnit / 4;
}

int _beatsPerBar(ImportedScore s) {
  if (s.beatUnit == 8 && s.beatsPerBar % 3 == 0 && s.beatsPerBar >= 6) return s.beatsPerBar ~/ 3;
  return s.beatsPerBar;
}

double _round(double v) => (v * 10000).round() / 10000;

/// Where to play [n]: the position the file gives when it fits, otherwise
/// the easiest fret near the hand. Tries other octaves when the pitch is
/// off the neck. Returns (string, fret) or null.
(int, int)? _place(ImportedNote n, List<int> tuning, int capo, Set<int> used, int hand, int? prevString) {
  if (n.string != null && n.fret != null) {
    final s = n.string!, f = n.fret!;
    if (s >= 1 && s <= 6 && f >= 0 && f <= maxFret && !used.contains(s)) return (s, f);
  }
  for (final shift in const [0, -12, 12, -24, 24]) {
    final pitch = n.pitch + shift;
    (int, int)? best;
    var bestCost = double.infinity;
    for (var s = 1; s <= 6; s++) {
      if (used.contains(s)) continue;
      final fret = pitch - tuning[s - 1] - capo;
      if (fret < 0 || fret > maxFret) continue;
      var cost = fret * 0.15 + shift.abs() * 0.05;
      if (fret > 0) {
        if (fret < hand) cost += (hand - fret) * 1.5;
        if (fret > hand + 3) cost += (fret - hand - 3) * 1.5;
      }
      if (prevString != null) cost += (s - prevString).abs() * 0.3;
      if (cost < bestCost) {
        bestCost = cost;
        best = (s, fret);
      }
    }
    if (best != null) return best;
  }
  return null;
}

/// Down and up strums, one per beat, for chord names over the song.
List<Map<String, Object>> _chordTrack(ImportedScore score, Set<String> known, double totalBeats) {
  final factor = _beatFactor(score);
  final bpb = _beatsPerBar(score);
  final chords = <(double, String)>[];
  for (final c in score.chords..sort((a, b) => a.start.compareTo(b.start))) {
    final name = matchChordName(c.name, known);
    if (name == null) continue;
    final beat = _round(_snap(c.start) * factor);
    if (chords.isNotEmpty && chords.last.$1 == beat) {
      chords[chords.length - 1] = (beat, name);
    } else {
      chords.add((beat, name));
    }
  }
  if (chords.isEmpty) return const [];
  final out = <Map<String, Object>>[];
  for (var k = 0; k < chords.length; k++) {
    final (start, name) = chords[k];
    final end = k + 1 < chords.length ? chords[k + 1].$1 : math.max(totalBeats, start + 1);
    var b = start;
    while (b < end - 1e-6) {
      final step = math.min(1.0, end - b);
      final inBar = b - (b / bpb).floor() * bpb;
      out.add({
        'beat': _round(b),
        'chord': name,
        'strum': inBar.round() % 2 == 0 ? 'down' : 'up',
        'length': _round(step),
      });
      b += step;
    }
  }
  return out;
}

/// Ranks tracks: real 6-string guitar parts with many notes first.
int _trackScore(ImportedTrack t) {
  var s = 0;
  if (t.percussion) return -1000;
  if (t.notes.isEmpty) return -500;
  if (t.tuning != null && t.tuning!.length >= 6) s += 100;
  if (t.isGuitar) s += 60;
  if (t.isBass) s -= 40;
  final name = t.name.toLowerCase();
  if (name.contains('guitar') || name.contains('gtr') || name.contains('gitar')) s += 40;
  if (name.contains('lead') || name.contains('melod') || name.contains('solo') || name.contains('vocal')) s += 10;
  if (name.contains('bass')) s -= 30;
  s += math.min(30, t.notes.length ~/ 20);
  return s;
}

String _difficulty(ArrangedPart part, double beatsPerSecond) {
  if (part.notes.isEmpty) return 'easy';
  var maxFret = 0;
  var last = -1.0;
  var starts = 0;
  final presses = <double, int>{};
  for (final n in part.notes) {
    maxFret = math.max(maxFret, n['fret']!.toInt());
    final b = n['beat']!.toDouble();
    if (b != last) {
      starts++;
      last = b;
    }
    if (n['fret']!.toInt() > 0) presses[b] = (presses[b] ?? 0) + 1;
  }
  final total = part.notes.last['beat']!.toDouble() + part.notes.last['length']!.toDouble();
  final notesPerSecond = total <= 0 ? 0 : starts / (total / beatsPerSecond);
  final chordy = presses.values.where((c) => c >= 3).length / math.max(1, starts);
  if (notesPerSecond <= 2.2 && maxFret <= 5 && chordy < 0.2) return 'easy';
  if (notesPerSecond <= 4.5 && maxFret <= 12) return 'medium';
  return 'hard';
}

/// The song JSON for an imported piece. The best track is the main part;
/// the others are kept as extra parts the player can switch to.
Map<String, dynamic> arrangeScore(
  ImportedScore score, {
  required String id,
  required String fileName,
  required Set<String> knownChords,
}) {
  final tracks = score.playable..sort((a, b) => _trackScore(b).compareTo(_trackScore(a)));
  if (tracks.isEmpty) throw ImportException.noNotes('No notes to play were found in this file');
  final parts = [for (final t in tracks.take(12)) arrangeTrack(t, score)].where((p) => p.notes.isNotEmpty).toList();
  if (parts.isEmpty) throw ImportException.noNotes('No notes to play were found in this file');
  final main = parts.first;
  final factor = _beatFactor(score);
  final tempo = _round(score.tempo * factor);
  final bpb = _beatsPerBar(score);
  var total = 0.0;
  for (final n in main.notes) {
    total = math.max(total, n['beat']!.toDouble() + n['length']!.toDouble());
  }
  final easy = _chordTrack(score, knownChords, total);
  final title = score.title.trim().isEmpty ? _titleFromFileName(fileName) : score.title.trim();
  return {
    'id': id,
    'title': {'en': title},
    'artist': score.artist.trim(),
    'license': 'user-file',
    'source': 'Imported from $fileName',
    'format': score.format,
    'fileName': fileName,
    'language': 'instrumental',
    'difficulty': _difficulty(main, tempo / 60),
    'tags': const ['my-songs'],
    'tempo': tempo,
    'timeSignature': [score.beatsPerBar, score.beatUnit],
    'beatsPerBar': bpb,
    'tuning': [for (final p in main.tuning.reversed) pitchName(p)],
    'capo': main.capo,
    'tracks': {'full': main.notes, 'easy': easy},
    if (parts.length > 1)
      'parts': [
        for (final p in parts)
          {
            'name': p.name.trim().isEmpty ? 'Part ${parts.indexOf(p) + 1}' : p.name.trim(),
            'tuning': [for (final t in p.tuning.reversed) pitchName(t)],
            'capo': p.capo,
            'notes': p.notes,
          },
      ],
  };
}

String _titleFromFileName(String fileName) {
  var name = fileName.split('/').last.split('\\').last;
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  name = name.replaceAll(RegExp(r'[_\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return name.isEmpty ? 'Song' : name;
}
