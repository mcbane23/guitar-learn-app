/// Helpers for turning note names, strings and frets into MIDI pitches.
library;

import 'dart:math' as math;

const _noteIndex = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

/// Parses a note name such as `E2`, `F#3` or `Bb4` into a MIDI note number.
int parsePitch(String name) {
  final m = RegExp(r'^([A-Ga-g])([#b]*)(-?\d+)$').firstMatch(name.trim());
  if (m == null) throw FormatException('Bad note name: $name');
  var value = _noteIndex[m.group(1)!.toUpperCase()]!;
  for (final c in m.group(2)!.split('')) {
    value += c == '#' ? 1 : -1;
  }
  return (int.parse(m.group(3)!) + 1) * 12 + value;
}

const _sharpNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// Serbian (and German) music naming calls B natural "H" and B flat "B".
const _serbianNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'B', 'H'];

/// The note's letter name without the octave, e.g. 64 -> "E".
String noteName(int midi, {bool serbian = false}) =>
    (serbian ? _serbianNames : _sharpNames)[midi % 12];

/// Frequency in Hz of a MIDI note.
double midiToHz(int midi) => 440.0 * math.pow(2, (midi - 69) / 12.0);

/// Standard guitar tuning, string 1 (thin, high E) to string 6 (thick, low E).
const standardTuning = [64, 59, 55, 50, 45, 40];
