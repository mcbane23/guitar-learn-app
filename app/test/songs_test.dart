import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_learn/models/chord.dart';
import 'package:guitar_learn/models/song.dart';

/// Checks every song file that ships with the app.
void main() {
  final dir = Directory('assets/songs');
  final chords = ChordLibrary.fromJson(
    jsonDecode(File('${dir.path}/chords.json').readAsStringSync()) as Map<String, dynamic>,
  );
  final index = jsonDecode(File('${dir.path}/index.json').readAsStringSync()) as Map<String, dynamic>;
  final entries = [for (final s in index['songs'] as List) SongInfo.fromJson((s as Map).cast<String, dynamic>())];

  test('catalog lists at least 10 songs with English and Serbian titles', () {
    expect(entries.length, greaterThanOrEqualTo(10));
    for (final e in entries) {
      expect(e.title['en'], isNotEmpty, reason: e.id);
      expect(e.title['sr'], isNotEmpty, reason: e.id);
    }
  });

  for (final e in entries) {
    test('song ${e.id} is playable', () {
      final song = Song.fromJson(jsonDecode(File('${dir.path}/${e.file}').readAsStringSync()) as Map<String, dynamic>);
      expect(song.id, e.id);
      expect(song.hasFull, isTrue);
      expect(song.hasEasy, isTrue);
      expect(song.totalBeats % song.beatsPerBar, 0, reason: 'song should end on a bar line');
      for (final n in song.full) {
        expect(n.string, inInclusiveRange(1, 6));
        expect(n.fret, inInclusiveRange(0, 12));
        expect(n.finger, inInclusiveRange(0, 4));
        expect(n.fret == 0, n.finger == 0, reason: 'open strings need no finger');
        expect(n.length, greaterThan(0));
      }
      for (final c in song.easy) {
        expect(chords[c.chord], isNotNull, reason: 'chord ${c.chord} missing from chords.json');
      }
    });
  }

  test('chord shapes are valid', () {
    for (final shape in chords.chords.values) {
      expect(shape.frets.length, 6);
      expect(shape.playedStrings, isNotEmpty);
      for (var s = 1; s <= 6; s++) {
        if (shape.fretOn(s) > 0) expect(shape.fingerOn(s), inInclusiveRange(1, 4), reason: shape.name);
      }
    }
    // C major: x32010
    final c = chords['C']!;
    expect([for (var s = 6; s >= 1; s--) c.fretOn(s)], [-1, 3, 2, 0, 1, 0]);
  });
}
