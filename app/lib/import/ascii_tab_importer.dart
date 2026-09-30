/// Reads text tablature (.txt, .tab), the kind found on tab websites:
///
/// ```
///     Am        C
/// e|--0---0---|--0---0---|
/// B|--1---1---|--1---1---|
/// G|--2---2---|--0---0---|
/// D|--2---2---|--2---2---|
/// A|--0---0---|--3---3---|
/// E|----------|----------|
/// ```
///
/// Text tabs carry no rhythm, so the timing is guessed from the spacing:
/// each bar between `|` marks lasts one bar of the song.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../music/pitch.dart';
import 'score.dart';

final _tabLine = RegExp(r'^\s*(?:[A-Ga-g][#b]?)?\s*[|:]?\s*[-0-9|hpb/\\~xX^*()\[\]<>.,rstv\s]*-[-0-9|hpb/\\~xX^*()\[\]<>.,rstv\s]*$');
final _chordToken = RegExp(r'^[A-H][#b]?(?:m|min|maj|M|dim|aug|sus|add|\d|-|\+|/[A-H][#b]?)*$');
final _tempoHint = RegExp(r'(?:tempo|bpm|♩\s*=|q\s*=)\D{0,6}(\d{2,3})', caseSensitive: false);

class _Line {
  _Line(this.text, this.index);
  final String text;
  final int index;

  /// The string name written before the tab, e.g. "e" or "D".
  String? get label {
    final m = RegExp(r'^\s*([A-Ga-g][#b]?)\s*[|:-]').firstMatch(text);
    return m?.group(1);
  }

  /// Where the fret characters start (after the label and the first bar line).
  int get contentStart {
    final m = RegExp(r'^\s*(?:[A-Ga-g][#b]?)?\s*[|:]?').firstMatch(text);
    return m?.end ?? 0;
  }

  bool get isTab => _tabLine.hasMatch(text) && text.contains('-') && RegExp(r'-{2,}').hasMatch(text);
}

/// Parses a text tab.
ImportedScore importAsciiTab(Uint8List bytes, {String fileName = ''}) {
  final text = _decode(bytes).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = [for (final (i, l) in text.split('\n').indexed) _Line(l, i)];
  final s = ImportedScore(format: 'Text tab');

  // Blocks of 6 tab lines: one guitar staff each.
  final blocks = <List<_Line>>[];
  var i = 0;
  while (i < lines.length) {
    if (lines[i].isTab) {
      var j = i;
      while (j < lines.length && lines[j].isTab) {
        j++;
      }
      final run = lines.sublist(i, j);
      if (run.length >= 6) {
        // Long runs (several staffs pasted without blank lines) split into sixes.
        for (var k = 0; k + 6 <= run.length; k += 6) {
          blocks.add(run.sublist(k, k + 6));
        }
      }
      i = j;
    } else {
      i++;
    }
  }
  if (blocks.isEmpty) throw ImportException.noNotes('No tablature found in this text file');

  // Title, artist and tempo from the text around the tabs.
  final tabIndexes = {for (final b in blocks) for (final l in b) l.index};
  final prose = [for (final l in lines) if (!tabIndexes.contains(l.index)) l.text.trim()];
  for (final p in prose) {
    final m = RegExp(r'^(title|song|artist|band|by)\s*[:\-]\s*(.+)$', caseSensitive: false).firstMatch(p);
    if (m == null) continue;
    final key = m.group(1)!.toLowerCase();
    if ((key == 'title' || key == 'song') && s.title.isEmpty) s.title = m.group(2)!.trim();
    if ((key == 'artist' || key == 'band' || key == 'by') && s.artist.isEmpty) s.artist = m.group(2)!.trim();
  }
  if (s.title.isEmpty) {
    final first = prose.where((p) => p.isNotEmpty && p.length < 80 && !_chordLine(p) && !p.contains('=')).firstOrNull;
    if (first != null && blocks.first.first.index > 0 && lines.take(blocks.first.first.index).any((l) => l.text.trim() == first)) {
      s.title = first.replaceFirst(RegExp(r'^(title|song)\s*[:\-]\s*', caseSensitive: false), '');
    }
  }
  final tempo = _tempoHint.firstMatch(text);
  if (tempo != null) s.tempo = double.parse(tempo.group(1)!).clamp(40, 240);
  if (tempo == null) s.tempo = 90;

  // Tuning from the string labels of the first block (top line = thin string,
  // unless the labels read the other way round).
  final labels = [for (final l in blocks.first) l.label];
  var tuning = List<int>.from(standardTuning);
  var topIsThin = true;
  if (labels.every((l) => l != null)) {
    final letters = [for (final l in labels) l![0].toUpperCase()];
    const standardLetters = ['E', 'B', 'G', 'D', 'A', 'E'];
    if (letters.join() == standardLetters.reversed.join() && letters.join() != standardLetters.join()) topIsThin = false;
    final ordered = topIsThin ? labels : labels.reversed.toList();
    tuning = [
      for (var k = 0; k < 6; k++) _nearestPitch(ordered[k]!, standardTuning[k]),
    ];
  } else if (labels.first != null && labels.last != null) {
    if (labels.first!.toUpperCase() == 'E' && labels.first == 'E' && labels.last == 'e') topIsThin = false;
  }

  final track = ImportedTrack(name: 'Guitar', tuning: tuning, program: 25);
  var songQuarters = 0.0;
  final bpb = s.beatsPerBar;
  for (final block in blocks) {
    final rows = topIsThin ? block : block.reversed.toList();
    final start = rows.map((l) => l.contentStart).reduce(math.max);
    final texts = [for (final l in rows) l.text.length > start ? l.text.substring(start) : ''];
    final width = texts.map((t) => t.length).reduce(math.max);
    if (width == 0) continue;

    // Bars: stretches between "|" marks on the top line (or any line).
    final barLine = texts.firstWhere((t) => t.contains('|'), orElse: () => '');
    final barEnds = <int>[];
    for (var c = 0; c < barLine.length; c++) {
      if (barLine[c] == '|') barEnds.add(c);
    }
    if (barEnds.isEmpty || barEnds.last < width - 1) barEnds.add(width);
    final quartersPerBar = bpb * 4 / s.beatUnit;

    // Time of every column.
    final columnTime = List<double>.filled(width + 1, 0);
    var barStart = 0;
    var t = songQuarters;
    for (final end in barEnds) {
      final len = end - barStart;
      if (len <= 0) {
        barStart = end + 1;
        continue;
      }
      // A very short "bar" is a pickup or a spacer: give it proportional time.
      final barQuarters = len < 4 ? quartersPerBar * len / 16 : quartersPerBar;
      for (var c = barStart; c <= end && c <= width; c++) {
        columnTime[c] = t + barQuarters * (c - barStart) / len;
      }
      t += barQuarters;
      barStart = end + 1;
    }
    for (var c = barStart; c <= width; c++) {
      columnTime[c] = t;
    }
    final blockEnd = t;

    // Chord names written above the block.
    final above = block.first.index - 1;
    for (var k = above; k >= 0 && k > above - 3; k--) {
      final line = lines[k].text;
      if (line.trim().isEmpty) continue;
      if (!_chordLine(line)) break;
      for (final m in RegExp(r'\S+').allMatches(line)) {
        if (!_chordToken.hasMatch(m.group(0)!)) continue;
        final col = (m.start - start).clamp(0, width);
        s.chords.add(ImportedChord(start: columnTime[col], name: m.group(0)!));
      }
      break;
    }

    // Notes: a number on a string line, read at its first digit.
    final found = <(int col, int string, int fret)>[];
    for (var string = 1; string <= 6; string++) {
      final row = texts[string - 1];
      var c = 0;
      while (c < row.length) {
        final ch = row[c];
        if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
          var end = c + 1;
          while (end < row.length && end < c + 2 && row.codeUnitAt(end) >= 0x30 && row.codeUnitAt(end) <= 0x39) {
            end++;
          }
          var fret = int.parse(row.substring(c, end));
          if (fret > maxFretOnTab) {
            // "23" spaced as two notes: take the first digit only.
            end = c + 1;
            fret = int.parse(row.substring(c, end));
          }
          found.add((c, string, fret));
          c = end;
        } else {
          c++;
        }
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    final columns = found.map((n) => n.$1).toSet().toList()..sort();
    for (final (col, string, fret) in found) {
      final at = columnTime[col.clamp(0, width)];
      final nextCol = columns.where((c) => c > col).firstOrNull;
      final end = nextCol == null ? blockEnd : columnTime[nextCol.clamp(0, width)];
      final duration = math.max(0.25, math.min(4.0, end - at));
      track.notes.add(ImportedNote(
        start: at,
        duration: duration,
        pitch: tuning[string - 1] + fret,
        string: string,
        fret: fret,
      ));
    }
    songQuarters = blockEnd;
  }
  if (track.notes.isEmpty) throw ImportException.noNotes('No notes were found in this tab');
  s.tracks.add(track);
  return s;
}

/// The highest fret written as one number in a text tab.
const maxFretOnTab = 24;

bool _chordLine(String line) {
  final tokens = line.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return false;
  final chords = tokens.where(_chordToken.hasMatch).length;
  return chords >= math.max(1, (tokens.length * 0.6).ceil());
}

/// The pitch with the letter name of [label] closest to [near].
int _nearestPitch(String label, int near) {
  final index = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11, 'H': 11}[label[0].toUpperCase()] ?? near % 12;
  var value = index;
  if (label.length > 1) value += label[1] == '#' ? 1 : -1;
  final base = near - near % 12;
  final candidates = [base - 12 + value, base + value, base + 12 + value];
  return candidates.reduce((a, b) => (a - near).abs() <= (b - near).abs() ? a : b);
}

String _decode(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}
