import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_learn/import/arrange.dart';
import 'package:guitar_learn/import/ascii_tab_importer.dart';
import 'package:guitar_learn/import/gpif_importer.dart';
import 'package:guitar_learn/import/gpx_container.dart';
import 'package:guitar_learn/import/guitar_pro_importer.dart';
import 'package:guitar_learn/import/importer.dart';
import 'package:guitar_learn/import/midi_importer.dart';
import 'package:guitar_learn/import/musicxml_importer.dart';
import 'package:guitar_learn/import/score.dart';
import 'package:guitar_learn/models/song.dart';
import 'package:guitar_learn/music/pitch.dart';

Uint8List _fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

/// (start, pitch, string, fret, duration) of a track's notes.
List<(double, int, int?, int?, double)> _notes(ImportedTrack t) =>
    [for (final n in t.notes) ((n.start * 1000).round() / 1000, n.pitch, n.string, n.fret, (n.duration * 1000).round() / 1000)];

void main() {
  group('Guitar Pro 3/4/5', () {
    for (final file in ['fixture.gp3', 'fixture.gp4', 'fixture.gp5', 'fixture-v500.gp5']) {
      test('$file: title, tempo, tracks, tuning, capo, repeats, ties, chords', () {
        final s = importGuitarPro(_fixture(file));
        expect(s.format, startsWith('Guitar Pro'));
        expect(s.title, 'Fixture Song');
        expect(s.artist, 'Tester');
        expect(s.tempo, 90);
        expect(s.beatsPerBar, 4);
        expect(s.beatUnit, 4);
        expect(s.tracks.map((t) => t.name), ['Lead Guitar', 'Rhythm Guitar', 'Drums']);
        expect(s.tracks[2].percussion, isTrue);
        expect(s.tracks[0].percussion, isFalse);

        // Bar 1 (4/4) and bar 2 (3/4) are inside a repeat, so they play twice: 4+3+4+3 beats.
        final lead = s.tracks[0];
        expect(lead.tuning, standardTuning);
        expect(lead.capo, 0);
        final firstPass = _notes(lead).where((n) => n.$1 < 7).toList();
        expect(firstPass, [
          (0.0, 64, 1, 0, 1.0),
          (1.0, 67, 1, 3, 1.0),
          (2.0, 60, 2, 1, 0.5),
          (3.0, 60, 2, 1, 1.0), // the Am chord: three notes together
          (3.0, 57, 3, 2, 1.0),
          (3.0, 52, 4, 2, 1.0),
          (4.0, 69, 1, 5, 2.0), // a quarter tied to another quarter
          (6.0, 71, 1, 7, 0.333), // triplet (the dead note next to it is skipped)
          (6.333, 72, 1, 8, 0.333),
          (6.667, 71, 1, 7, 0.333),
        ]);
        final secondPass = _notes(lead).where((n) => n.$1 >= 7).toList();
        expect(secondPass.length, firstPass.length);
        expect(secondPass.first.$1, 7.0);
        expect(secondPass.last.$1, closeTo(13.667, 0.001));

        expect(s.chords.map((c) => (c.start, c.name)), [(3.0, 'Am'), (10.0, 'Am')]);

        final rhythm = s.tracks[1];
        expect(rhythm.tuning, [64, 59, 55, 50, 45, 38]); // drop D
        expect(rhythm.capo, 2);
        expect(_notes(rhythm).where((n) => n.$1 < 7), [
          (0.0, 59, 3, 2, 4.0),
          (0.0, 52, 4, 0, 4.0),
          (0.0, 40, 6, 0, 4.0), // low D string, capo 2 -> E2
        ]);
        expect(rhythm.program, 25); // the channel table of the fixture file (written by PyGuitarPro) holds 25 here
      });
    }

    test('a damaged file gives a clear error', () {
      final bytes = _fixture('fixture.gp5').sublist(0, 400);
      expect(() => importGuitarPro(bytes), throwsA(isA<ImportException>()));
      expect(() => importGuitarPro(Uint8List.fromList(utf8.encode('hello world, this is not a tab'))),
          throwsA(isA<ImportException>()));
    });

    test('arranges the file into a song with parts, fingers and a chord track', () {
      final s = importGuitarPro(_fixture('fixture.gp5'));
      final json = arrangeScore(s, id: 'file-1', fileName: 'fixture.gp5', knownChords: {'Am', 'C', 'G'});
      final song = Song.fromJson(json);
      expect(song.info.titleFor('en'), 'Fixture Song');
      expect(json['format'], 'Guitar Pro 5');
      expect(song.tempo, 90);
      expect(song.beatsPerBar, 4);
      expect(song.parts.map((p) => p.name), ['Lead Guitar', 'Rhythm Guitar']); // drums left out
      expect(song.isStandardTuning, isTrue);
      final full = song.full;
      expect(full.first.string, 1);
      expect(full.first.fret, 0);
      expect(full.first.finger, 0);
      expect(full[1].fret, 3);
      expect(full[1].finger, 3);
      // The Am chord: index on fret 1, middle and ring on fret 2.
      final chord = full.where((n) => n.beat == 3).toList()..sort((a, b) => a.string.compareTo(b.string));
      expect(chord.map((n) => (n.string, n.fret, n.finger)), [(2, 1, 1), (3, 2, 2), (4, 2, 2)]);
      expect(song.totalBeats, 14);
      expect(song.hasEasy, isTrue);
      expect(song.easy.first.beat, 3);
      expect(song.easy.first.chord, 'Am');
      expect(song.easy.first.strum, Strum.up); // beat 4 of the bar
      expect(song.easy.last.beat, 13);

      final rhythm = song.withPart(1);
      expect(rhythm.partIndex, 1);
      expect(rhythm.tuning, [64, 59, 55, 50, 45, 38]);
      expect(rhythm.capo, 2);
      expect(rhythm.full.length, 6);
      expect(rhythm.isStandardTuning, isFalse);
    });
  });

  group('MIDI', () {
    test('reads tempo, time signature, track names and notes', () {
      final bytes = _midiFile(format: 1, tracks: [
        _track([
          _meta(0, 0x51, [0x07, 0xA1, 0x20]), // 500000 us per quarter = 120 bpm
          _meta(0, 0x58, [3, 2, 24, 8]), // 3/4
          _meta(0, 0x03, utf8.encode('Test MIDI')),
          _meta(0, 0x2F, []),
        ]),
        _track([
          _meta(0, 0x03, utf8.encode('Guitar')),
          [0, 0xC0, 25], // steel guitar
          [0, 0x90, 64, 100],
          [480, 0x80, 64, 0],
          [0, 0x90, 67, 100],
          [0, 0x90, 60, 100], // two notes together
          [240, 0x90, 67, 0], // running status note-off (velocity 0)
          [240, 0x80, 60, 0],
          [0, 0x99, 36, 100], // a drum hit on channel 10
          [120, 0x89, 36, 0],
          _meta(0, 0x2F, []),
        ]),
      ]);
      final s = importMidi(bytes);
      expect(s.format, 'MIDI');
      expect(s.title, 'Test MIDI');
      expect(s.tempo, 120);
      expect(s.beatsPerBar, 3);
      expect(s.beatUnit, 4);
      expect(s.tracks.map((t) => t.name), ['Guitar (1)', 'Drums']);
      expect(s.tracks[0].program, 25);
      expect(s.tracks[1].percussion, isTrue);
      expect(_notes(s.tracks[0]), [
        (0.0, 64, null, null, 1.0),
        (1.0, 67, null, null, 0.5),
        (1.0, 60, null, null, 1.0),
      ]);

      final json = arrangeScore(s, id: 'file-2', fileName: 'x.mid', knownChords: const {});
      final song = Song.fromJson(json);
      expect(song.beatsPerBar, 3);
      expect(song.parts, isEmpty); // drums are not a part
      expect(song.full.map((n) => (n.beat, n.string, n.fret)), [
        (0.0, 1, 0), // E4 open high string
        (1.0, 2, 1), // C4 on the B string, first fret
        (1.0, 1, 3), // G4 on the high string, third fret (the B string is taken)
      ]);
      expect(song.hasEasy, isFalse);
    });

    test('a format 0 file with several channels becomes several parts', () {
      final bytes = _midiFile(format: 0, tracks: [
        _track([
          [0, 0xC0, 0], // piano on channel 1
          [0, 0xC1, 33], // bass on channel 2
          [0, 0x90, 72, 90],
          [0, 0x91, 40, 90],
          [960, 0x80, 72, 0],
          [0, 0x81, 40, 0],
          _meta(0, 0x2F, []),
        ]),
      ]);
      final s = importMidi(bytes);
      expect(s.tracks.map((t) => t.name), ['Piano (1)', 'Bass (2)']);
      final json = arrangeScore(s, id: 'file-3', fileName: 'x.mid', knownChords: const {});
      expect((json['parts'] as List).length, 2);
      expect((json['parts'] as List).first['name'], 'Piano (1)'); // basses rank below other instruments
    });

    test('rejects other files', () {
      expect(() => importMidi(Uint8List.fromList([1, 2, 3])), throwsA(isA<ImportException>()));
    });
  });

  group('Guitar Pro 6/7', () {
    test('reads score.gpif from a .gp zip: tuning, capo, rhythms, tuplets, ties, chords, repeats', () {
      final gp = _zip({'VERSION': utf8.encode('7.0'), 'Content/score.gpif': utf8.encode(_gpif)});
      final s = importGp7(Uint8List.fromList(gp));
      expect(s.format, 'Guitar Pro 7');
      expect(s.title, 'Gpif Song');
      expect(s.artist, 'Someone');
      expect(s.tempo, 100);
      expect(s.beatsPerBar, 4);
      expect(s.tracks.map((t) => t.name), ['Guitar', 'Kit']);
      expect(s.tracks[1].percussion, isTrue);
      final g = s.tracks[0];
      expect(g.tuning, [64, 59, 55, 50, 45, 38]);
      expect(g.capo, 1);
      expect(g.program, 27);
      // Bar 1 repeats (count 2): 4 quarters, played twice.
      expect(_notes(g).where((n) => n.$1 < 4), [
        (0.0, 65, 1, 0, 1.0), // string index 5 = thinnest, capo 1
        (1.0, 43, 6, 4, 1.5), // a quarter on the low D string, tied over an eighth
        (2.5, 63, 2, 3, 0.5),
        (3.0, 56, 3, 0, 0.333), // triplet eighths (the grace note before them takes no time)
        (3.333, 58, 3, 2, 0.333),
        (3.667, 60, 3, 4, 0.333),
      ]);
      expect(_notes(g).where((n) => n.$1 >= 4).length, 6);
      expect(g.notes.where((n) => n.finger != null).map((n) => n.finger), [3, 3]); // once per pass of the bar
      expect(s.chords.map((c) => (c.start, c.name)), [(0.0, 'Dm'), (4.0, 'Dm')]);
    });

    test('a .gpx file is a compressed file system holding score.gpif', () {
      final fs = _bcfs({'score.gpif': utf8.encode(_gpif), 'other.txt': utf8.encode('x')});
      final files = readBcfs(Uint8List.fromList(fs));
      expect(utf8.decode(files['score.gpif']!), _gpif);
      expect(utf8.decode(files['other.txt']!), 'x');

      final gpx = _bcfz(fs);
      expect(String.fromCharCodes(gpx, 0, 4), 'BCFZ');
      final s = importGpif(readGpxScore(Uint8List.fromList(gpx)), format: 'Guitar Pro 6');
      expect(s.title, 'Gpif Song');
      expect(s.tracks[0].notes.length, 12);

      // An uncompressed file system works too.
      expect(importGpif(readGpxScore(Uint8List.fromList(fs)), format: 'x').title, 'Gpif Song');
    });

    test('BCFZ back references copy earlier output', () {
      // Raw "abc", then copy 3 bytes from 3 back, then raw "d": "abcabcd".
      final w = _BitWriter();
      w.bits(0, 1);
      w.bitsReversed(3, 2);
      for (final c in 'abc'.codeUnits) {
        w.bits(c, 8);
      }
      w.bits(1, 1);
      w.bits(4, 4); // word size
      w.bitsReversed(3, 4); // offset
      w.bitsReversed(3, 4); // size
      w.bits(0, 1);
      w.bitsReversed(1, 2);
      w.bits('d'.codeUnitAt(0), 8);
      final body = w.bytes;
      final block = [...utf8.encode('BCFZ'), 7, 0, 0, 0, ...body];
      expect(utf8.decode(decompressBcfz(Uint8List.fromList(block), 4)), 'abcabcd');
    });
  });

  group('MusicXML', () {
    test('reads tab staff, ties, chords, harmony and tempo', () {
      final s = importMusicXml(Uint8List.fromList(utf8.encode(_musicXml)));
      expect(s.format, 'MusicXML');
      expect(s.title, 'XML Song');
      expect(s.artist, 'A. Composer');
      expect(s.tempo, 100);
      expect(s.beatsPerBar, 3);
      expect(s.tracks.map((t) => t.name), ['Guitar']);
      final g = s.tracks[0];
      expect(g.tuning, standardTuning);
      expect(g.capo, 0);
      expect(_notes(g), [
        (0.0, 64, 1, 0, 1.0),
        (1.0, 60, 2, 1, 3.0), // a half note tied into a quarter of the next bar
        (1.0, 55, 3, 0, 1.0), // played together with the note above (<chord/>)
        (4.0, 67, 1, 3, 1.5), // dotted quarter
        (5.5, 65, 1, 1, 0.5),
      ]);
      expect(g.notes.where((n) => n.finger != null).map((n) => n.finger), [1]);
      expect(s.chords.map((c) => (c.start, c.name)), [(0.0, 'C'), (3.0, 'Am'), (5.0, 'G7')]);
    });

    test('notes without a tab staff are placed by pitch, an octave down for guitars', () {
      final xml = '''<?xml version="1.0"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>Classical Guitar</part-name></score-part></part-list>
  <part id="P1"><measure number="1">
    <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
    <note><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration></note>
  </measure></part>
</score-partwise>''';
      final s = importMusicXml(Uint8List.fromList(utf8.encode(xml)));
      expect(_notes(s.tracks[0]), [(0.0, 52, null, null, 4.0)]); // written E4 sounds E3
      final song = Song.fromJson(arrangeScore(s, id: 'f', fileName: 'a.xml', knownChords: const {}));
      expect(song.full.single.string, 4);
      expect(song.full.single.fret, 2);
    });

    test('compressed .mxl files are unpacked', () {
      final mxl = _zip({
        'META-INF/container.xml':
            utf8.encode('<?xml version="1.0"?><container><rootfiles><rootfile full-path="song.xml"/></rootfiles></container>'),
        'song.xml': utf8.encode(_musicXml),
      });
      expect(importMxl(Uint8List.fromList(mxl)).title, 'XML Song');
    });
  });

  group('text tabs', () {
    test('reads strings, frets, bars, chord names and title', () {
      final s = importAsciiTab(Uint8List.fromList(utf8.encode(_asciiTab)), fileName: 'song.txt');
      expect(s.format, 'Text tab');
      expect(s.title, 'My Tab Song');
      expect(s.artist, 'Somebody');
      expect(s.tempo, 110);
      final g = s.tracks.single;
      expect(g.tuning, standardTuning);
      final notes = _notes(g);
      // Bar 1 is 16 characters wide = 4 beats: a note every 4 characters is a quarter note.
      expect(notes.take(4), [
        (0.0, 64, 1, 0, 1.0),
        (1.0, 67, 1, 3, 1.0),
        (2.0, 60, 2, 1, 1.0),
        (3.0, 52, 4, 2, 1.0),
      ]);
      // Bar 2: the two-digit fret 12 on the thin string, then a chord on three strings.
      expect(notes.where((n) => n.$1 >= 4 && n.$1 < 8).map((n) => (n.$1, n.$3, n.$4)), [
        (4.0, 1, 12),
        (6.0, 2, 1),
        (6.0, 3, 0),
        (6.0, 4, 2),
      ]);
      // The second block continues after the first.
      expect(notes.where((n) => n.$1 >= 8).map((n) => (n.$1, n.$3, n.$4)), [(8.0, 6, 3), (10.0, 5, 2)]);
      expect(s.chords.map((c) => (c.start, c.name)), [(0.0, 'Am'), (4.0, 'C'), (8.0, 'G')]);

      final song = Song.fromJson(arrangeScore(s, id: 'f', fileName: 'song.txt', knownChords: {'Am', 'C', 'G'}));
      expect(song.hasEasy, isTrue);
      expect(song.easy.map((e) => e.chord).toSet(), {'Am', 'C', 'G'});
    });

    test('a drop D tab with labels the other way up', () {
      const tab = '''
E|---0---|
A|-------|
D|-------|
G|-------|
B|-------|
e|---0---|
''';
      final s = importAsciiTab(Uint8List.fromList(utf8.encode(tab)));
      expect(s.tracks.single.tuning, standardTuning);
      expect(_notes(s.tracks.single).map((n) => (n.$3, n.$2)), [(1, 64), (6, 40)]);
      const drop = '''
e|---0---|
B|-------|
G|-------|
D|-------|
A|-------|
D|---0---|
''';
      final d = importAsciiTab(Uint8List.fromList(utf8.encode(drop)));
      expect(d.tracks.single.tuning, [64, 59, 55, 50, 45, 38]);
    });

    test('plain prose is not a tab', () {
      expect(() => importAsciiTab(Uint8List.fromList(utf8.encode('Just some lyrics\nand nothing else'))),
          throwsA(isA<ImportException>()));
    });
  });

  group('importSongFile', () {
    test('picks the reader from the file name or the contents', () {
      final known = {'Am', 'C'};
      expect(importSongFile(ImportFile(name: 'a.gp5', bytes: _fixture('fixture.gp5')), knownChords: known)['format'], 'Guitar Pro 5');
      expect(importSongFile(ImportFile(name: 'renamed.bin', bytes: _fixture('fixture.gp3')), knownChords: known)['format'], 'Guitar Pro 3');
      final gp = Uint8List.fromList(_zip({'Content/score.gpif': utf8.encode(_gpif)}));
      expect(importSongFile(ImportFile(name: 'song.gp', bytes: gp), knownChords: known)['format'], 'Guitar Pro 7');
      final xml = Uint8List.fromList(utf8.encode(_musicXml));
      expect(importSongFile(ImportFile(name: 'song.xml', bytes: xml), knownChords: known)['format'], 'MusicXML');
      expect(importSongFile(ImportFile(name: 'song.txt', bytes: xml), knownChords: known)['format'], 'MusicXML');
      final tab = Uint8List.fromList(utf8.encode(_asciiTab));
      final tabSong = importSongFile(ImportFile(name: 'My Song.tab', bytes: tab), knownChords: known);
      expect(tabSong['format'], 'Text tab');
      expect((tabSong['id'] as String), startsWith('file-'));
      expect(tabSong['id'], importSongFile(ImportFile(name: 'other.txt', bytes: tab), knownChords: known)['id'],
          reason: 'the same contents get the same id');
      final appSong = File('assets/songs/ode-to-joy.json').readAsBytesSync();
      final imported = importSongFile(ImportFile(name: 'ode.json', bytes: appSong), knownChords: known);
      expect(imported['format'], 'Song file');
      expect(Song.fromJson(imported).hasFull, isTrue);
    });

    test('says what is wrong with a file it cannot read', () {
      expect(() => importSongFile(ImportFile(name: 'x.pdf', bytes: Uint8List(0)), knownChords: const {}),
          throwsA(predicate((e) => e is ImportException && e.message.contains('empty'))));
      expect(
          () => importSongFile(ImportFile(name: 'x.pdf', bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 hello'))),
              knownChords: const {}),
          throwsA(isA<ImportException>()));
      final outcomes = importFilesInIsolate(ImportRequest(
        files: [
          ImportFile(name: 'good.gp4', bytes: _fixture('fixture.gp4')),
          ImportFile(name: 'bad.gp5', bytes: Uint8List.fromList([1, 2, 3])),
        ],
        knownChords: const {},
      ));
      expect(outcomes.map((o) => o.ok), [true, false]);
      expect(outcomes[1].error, isNotEmpty);
    });
  });

  test('chord names from tabs are matched to the chords the app knows', () {
    const known = {'A', 'Am', 'C', 'G', 'G7', 'D', 'Dm', 'E', 'Em', 'F'};
    expect(matchChordName('Am', known), 'Am');
    expect(matchChordName('Amin', known), 'Am');
    expect(matchChordName('A-', known), 'Am');
    expect(matchChordName('Amaj7', known), 'A');
    expect(matchChordName('G7', known), 'G7');
    expect(matchChordName('G9', known), 'G7');
    expect(matchChordName('Gsus4', known), 'G');
    expect(matchChordName('C/E', known), 'C');
    expect(matchChordName('Dm7', known), 'Dm');
    expect(matchChordName('H', known), isNull); // B is not in the library
    expect(matchChordName('Bb', known), isNull);
    expect(matchChordName('', known), isNull);
  });
}

// ---- Test file builders -----------------------------------------------------

List<int> _varLen(int v) {
  final out = <int>[v & 0x7f];
  v >>= 7;
  while (v > 0) {
    out.insert(0, (v & 0x7f) | 0x80);
    v >>= 7;
  }
  return out;
}

List<int> _meta(int delta, int type, List<int> data) => [..._varLen(delta), 0xFF, type, ..._varLen(data.length), ...data];

/// Events are [delta, status, data...] lists or ready-made byte lists.
List<int> _track(List<List<int>> events) {
  final body = <int>[];
  for (final e in events) {
    if (e.length >= 2 && e[1] == 0xFF) {
      body.addAll(e); // already a meta event with its delta
    } else {
      body.addAll(_varLen(e[0]));
      body.addAll(e.sublist(1));
    }
  }
  return [...'MTrk'.codeUnits, ..._u32(body.length), ...body];
}

List<int> _u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

Uint8List _midiFile({required int format, required List<List<int>> tracks, int division = 480}) => Uint8List.fromList([
      ...'MThd'.codeUnits,
      ..._u32(6),
      0,
      format,
      0,
      tracks.length,
      (division >> 8) & 0xff,
      division & 0xff,
      for (final t in tracks) ...t,
    ]);

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

/// A zip archive with stored (uncompressed) files.
List<int> _zip(Map<String, List<int>> files) {
  final out = <int>[];
  final central = <int>[];
  for (final e in files.entries) {
    final name = utf8.encode(e.key);
    final offset = out.length;
    out.addAll([
      ..._le32(0x04034b50), ..._le16(20), ..._le16(0), ..._le16(0), ..._le16(0), ..._le16(0), //
      ..._le32(0), ..._le32(e.value.length), ..._le32(e.value.length), ..._le16(name.length), ..._le16(0),
      ...name, ...e.value,
    ]);
    central.addAll([
      ..._le32(0x02014b50), ..._le16(20), ..._le16(20), ..._le16(0), ..._le16(0), ..._le16(0), ..._le16(0), //
      ..._le32(0), ..._le32(e.value.length), ..._le32(e.value.length), ..._le16(name.length), ..._le16(0), ..._le16(0),
      ..._le16(0), ..._le16(0), ..._le32(0), ..._le32(offset), ...name,
    ]);
  }
  final centralOffset = out.length;
  out.addAll(central);
  out.addAll([
    ..._le32(0x06054b50), ..._le16(0), ..._le16(0), ..._le16(files.length), ..._le16(files.length), //
    ..._le32(central.length), ..._le32(centralOffset), ..._le16(0),
  ]);
  return out;
}

/// A BCFS file system image: one directory entry per file at sector 1, 2,
/// ... and the data in the sectors after them.
List<int> _bcfs(Map<String, List<int>> files) {
  const sector = 0x1000;
  final sectors = <List<int>>[];
  sectors.add([...'BCFS'.codeUnits, ...List.filled(sector - 4, 0xFF)]);
  final entries = <int, List<int>>{};
  var next = 1 + files.length;
  for (final e in files.entries) {
    final entry = List<int>.filled(sector, 0);
    entry.setRange(0, 4, _le32(2));
    final name = utf8.encode(e.key);
    entry.setRange(4, 4 + name.length, name);
    entry.setRange(0x8c, 0x90, _le32(e.value.length));
    var p = 0x94;
    for (var i = 0; i < e.value.length; i += sector) {
      entry.setRange(p, p + 4, _le32(next));
      p += 4;
      final chunk = e.value.sublist(i, i + sector > e.value.length ? e.value.length : i + sector);
      entries[next++] = [...chunk, ...List.filled(sector - chunk.length, 0)];
    }
    sectors.add(entry);
  }
  for (var i = 1 + files.length; i < next; i++) {
    sectors.add(entries[i]!);
  }
  return [for (final s in sectors) ...s];
}

class _BitWriter {
  final bytes = <int>[];
  int _bit = 0;

  void bit(int v) {
    if (_bit == 0) bytes.add(0);
    if (v != 0) bytes[bytes.length - 1] |= 1 << (7 - _bit);
    _bit = (_bit + 1) % 8;
  }

  void bits(int v, int count) {
    for (var i = count - 1; i >= 0; i--) {
      bit((v >> i) & 1);
    }
  }

  void bitsReversed(int v, int count) {
    for (var i = 0; i < count; i++) {
      bit((v >> i) & 1);
    }
  }
}

/// Compresses with raw chunks only (3 bytes each).
List<int> _bcfz(List<int> data) {
  final w = _BitWriter();
  for (var i = 0; i < data.length; i += 3) {
    final n = i + 3 <= data.length ? 3 : data.length - i;
    w.bits(0, 1);
    w.bitsReversed(n, 2);
    for (var k = 0; k < n; k++) {
      w.bits(data[i + k], 8);
    }
  }
  return [...'BCFZ'.codeUnits, ..._le32(data.length), ...w.bytes];
}

const _gpif = '''<?xml version="1.0" encoding="UTF-8"?>
<GPIF>
  <Score><Title>Gpif Song</Title><Artist>Someone</Artist></Score>
  <MasterTrack>
    <Tracks>0 1</Tracks>
    <Automations><Automation><Type>Tempo</Type><Bar>0</Bar><Position>0</Position><Value>200 1</Value></Automation></Automations>
  </MasterTrack>
  <Tracks>
    <Track id="0">
      <Name>Guitar</Name>
      <Staves><Staff><Properties>
        <Property name="Tuning"><Pitches>38 45 50 55 59 64</Pitches></Property>
        <Property name="CapoFret"><Fret>1</Fret></Property>
        <Property name="DiagramCollection"><Items><Item id="0" name="Dm"/></Items></Property>
      </Properties></Staff></Staves>
      <Sounds><Sound><MIDI><Program>27</Program></MIDI></Sound></Sounds>
    </Track>
    <Track id="1">
      <Name>Kit</Name>
      <MidiConnection><PrimaryChannel>9</PrimaryChannel></MidiConnection>
      <Staves><Staff><Properties><Property name="PercussionSet"/></Properties></Staff></Staves>
    </Track>
  </Tracks>
  <MasterBars>
    <MasterBar><Time>4/4</Time><Repeat count="2" start="true" end="true"/><Bars>0 1</Bars></MasterBar>
  </MasterBars>
  <Bars>
    <Bar id="0"><Voices>0 -1 -1 -1</Voices></Bar>
    <Bar id="1"><Voices>1 -1 -1 -1</Voices></Bar>
  </Bars>
  <Voices>
    <Voice id="0"><Beats>0 1 2 3 4 5 6 7</Beats></Voice>
    <Voice id="1"><Beats>8</Beats></Voice>
  </Voices>
  <Beats>
    <Beat id="0"><Chord>0</Chord><Rhythm ref="0"/><Notes>0</Notes></Beat>
    <Beat id="1"><Rhythm ref="0"/><Notes>1</Notes></Beat>
    <Beat id="2"><Rhythm ref="2"/><Notes>2</Notes></Beat>
    <Beat id="3"><GraceNotes>BeforeBeat</GraceNotes><Rhythm ref="2"/><Notes>6</Notes></Beat>
    <Beat id="4"><Rhythm ref="2"/><Notes>3</Notes></Beat>
    <Beat id="5"><Rhythm ref="3"/><Notes>4</Notes></Beat>
    <Beat id="6"><Rhythm ref="3"/><Notes>5</Notes></Beat>
    <Beat id="7"><Rhythm ref="3"/><Notes>7</Notes></Beat>
    <Beat id="8"><Rhythm ref="4"/><Notes>8</Notes></Beat>
  </Beats>
  <Notes>
    <Note id="0"><Properties><Property name="String"><String>5</String></Property><Property name="Fret"><Fret>0</Fret></Property></Properties></Note>
    <Note id="1"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>4</Fret></Property></Properties><Tie origin="true" destination="false"/></Note>
    <Note id="2"><Properties><Property name="String"><String>0</String></Property><Property name="Fret"><Fret>4</Fret></Property></Properties><Tie origin="false" destination="true"/></Note>
    <Note id="3"><LeftFingering>A</LeftFingering><Properties><Property name="String"><String>4</String></Property><Property name="Fret"><Fret>3</Fret></Property></Properties></Note>
    <Note id="4"><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>0</Fret></Property></Properties></Note>
    <Note id="5"><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>2</Fret></Property></Properties></Note>
    <Note id="6"><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>1</Fret></Property></Properties></Note>
    <Note id="7"><Properties><Property name="String"><String>3</String></Property><Property name="Fret"><Fret>4</Fret></Property></Properties></Note>
    <Note id="8"><Properties><Property name="Midi"><Number>36</Number></Property></Properties></Note>
  </Notes>
  <Rhythms>
    <Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm>
    <Rhythm id="1"><NoteValue>Quarter</NoteValue><AugmentationDot count="1"/></Rhythm>
    <Rhythm id="2"><NoteValue>Eighth</NoteValue></Rhythm>
    <Rhythm id="3"><NoteValue>Eighth</NoteValue><PrimaryTuplet num="3" den="2"/></Rhythm>
    <Rhythm id="4"><NoteValue>Whole</NoteValue></Rhythm>
  </Rhythms>
</GPIF>
''';

const _musicXml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <work><work-title>XML Song</work-title></work>
  <identification><creator type="composer">A. Composer</creator></identification>
  <part-list>
    <score-part id="P1"><part-name>Guitar</part-name>
      <midi-instrument id="P1-I1"><midi-channel>1</midi-channel><midi-program>25</midi-program></midi-instrument>
    </score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <time><beats>3</beats><beat-type>4</beat-type></time>
        <staves>2</staves>
        <clef number="1"><sign>G</sign><line>2</line></clef>
        <clef number="2"><sign>TAB</sign><line>5</line></clef>
        <staff-details number="2">
          <staff-lines>6</staff-lines>
          <staff-tuning line="1"><tuning-step>E</tuning-step><tuning-octave>2</tuning-octave></staff-tuning>
          <staff-tuning line="2"><tuning-step>A</tuning-step><tuning-octave>2</tuning-octave></staff-tuning>
          <staff-tuning line="3"><tuning-step>D</tuning-step><tuning-octave>3</tuning-octave></staff-tuning>
          <staff-tuning line="4"><tuning-step>G</tuning-step><tuning-octave>3</tuning-octave></staff-tuning>
          <staff-tuning line="5"><tuning-step>B</tuning-step><tuning-octave>3</tuning-octave></staff-tuning>
          <staff-tuning line="6"><tuning-step>E</tuning-step><tuning-octave>4</tuning-octave></staff-tuning>
        </staff-details>
        <transpose><diatonic>0</diatonic><chromatic>0</chromatic><octave-change>-1</octave-change></transpose>
      </attributes>
      <direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>100</per-minute></metronome></direction-type><sound tempo="100"/></direction>
      <harmony><root><root-step>C</root-step></root><kind>major</kind></harmony>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>half</type><staff>1</staff></note>
      <note><chord/><pitch><step>G</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <backup><duration>6</duration></backup>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>2</duration><voice>5</voice><type>quarter</type><staff>2</staff>
        <notations><technical><string>1</string><fret>0</fret></technical></notations></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>5</voice><type>half</type><staff>2</staff><tie type="start"/>
        <notations><tied type="start"/><technical><string>2</string><fret>1</fret><fingering>1</fingering></technical></notations></note>
      <note><chord/><pitch><step>G</step><octave>4</octave></pitch><duration>2</duration><voice>5</voice><type>quarter</type><staff>2</staff>
        <notations><technical><string>3</string><fret>0</fret></technical></notations></note>
    </measure>
    <measure number="2">
      <harmony><root><root-step>A</root-step></root><kind>minor</kind></harmony>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff><tie type="stop"/></note>
      <note><pitch><step>G</step><octave>5</octave></pitch><duration>3</duration><voice>1</voice><type>quarter</type><dot/><staff>1</staff></note>
      <note><pitch><step>F</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice><type>eighth</type><staff>1</staff></note>
      <backup><duration>6</duration></backup>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><voice>5</voice><type>quarter</type><staff>2</staff><tie type="stop"/>
        <notations><tied type="stop"/><technical><string>2</string><fret>1</fret></technical></notations></note>
      <note><pitch><step>G</step><octave>5</octave></pitch><duration>3</duration><voice>5</voice><type>quarter</type><dot/><staff>2</staff>
        <notations><technical><string>1</string><fret>3</fret></technical></notations></note>
      <harmony><root><root-step>G</root-step></root><kind>dominant</kind><offset>-1</offset></harmony>
      <note><pitch><step>F</step><octave>5</octave></pitch><duration>1</duration><voice>5</voice><type>eighth</type><staff>2</staff>
        <notations><technical><string>1</string><fret>1</fret></technical></notations></note>
    </measure>
  </part>
</score-partwise>
''';

const _asciiTab = '''
My Tab Song
Artist: Somebody
Tempo: 110 bpm

Am                 C
e|0---3-----------|12--------------|
B|--------1-------|--------1-------|
G|----------------|--------0-------|
D|------------2---|--------2-------|
A|----------------|----------------|
E|----------------|----------------|

G
e|----------------|
B|----------------|
G|----------------|
D|----------------|
A|--------2-------|
E|3---------------|
''';
