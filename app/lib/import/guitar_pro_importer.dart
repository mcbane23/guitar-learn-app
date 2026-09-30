/// Reads Guitar Pro 3, 4 and 5 files (.gp3, .gp4, .gp5).
///
/// The layout follows the format as documented by the PyGuitarPro and
/// TuxGuitar projects. Only what the app needs is kept: tuning, capo, notes
/// with string and fret, chord names, tempo, time signature and repeats;
/// everything else (effects, page setup, lyrics) is read and skipped.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'score.dart';

class _Reader {
  _Reader(this.bytes) : _data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData _data;
  int pos = 0;

  void _need(int n) {
    if (pos + n > bytes.length) throw ImportException('The file ends too early (damaged file?)');
  }

  int u8() {
    _need(1);
    return bytes[pos++];
  }

  int i8() {
    _need(1);
    return _data.getInt8(pos++);
  }

  bool boolean() => u8() != 0;

  int i16() {
    _need(2);
    final v = _data.getInt16(pos, Endian.little);
    pos += 2;
    return v;
  }

  int i32() {
    _need(4);
    final v = _data.getInt32(pos, Endian.little);
    pos += 4;
    return v;
  }

  double f64() {
    _need(8);
    final v = _data.getFloat64(pos, Endian.little);
    pos += 8;
    return v;
  }

  void skip(int n) {
    _need(n);
    pos += n;
  }

  /// One length byte, then [count] bytes of which the first `length` are text.
  String byteSizeString(int count) {
    final size = u8();
    if (count < 0) throw ImportException('Bad text in file');
    _need(count);
    final s = latin1.decode(bytes.sublist(pos, pos + size.clamp(0, count)));
    pos += count;
    return s;
  }

  String intSizeString() {
    final count = i32();
    if (count < 0) throw ImportException('Bad text in file');
    _need(count);
    final s = latin1.decode(bytes.sublist(pos, pos + count));
    pos += count;
    return s;
  }

  String intByteSizeString() {
    final count = i32();
    return byteSizeString(count - 1);
  }
}

class _Note {
  _Note({
    required this.offset,
    required this.duration,
    required this.string,
    required this.fret,
    required this.type,
    required this.finger,
  });

  /// Quarter notes from the start of the measure.
  final double offset;
  final double duration;
  final int string;
  final int fret;

  /// 1 normal, 2 tied to the previous note, 3 dead (muted).
  final int type;
  final int? finger;
}

class _Header {
  int numerator = 4;
  int denominator = 4;
  bool repeatOpen = false;
  int repeatClose = -1;
  double get quarters => numerator * 4 / denominator;
}

class _Track {
  String name = '';
  bool percussion = false;
  final tuning = <int>[];
  int stringCount = 6;
  int program = 0;
  int capo = 0;

  /// Per measure: notes and chord names, in quarter notes from the measure start.
  final measures = <List<_Note>>[];
  final chords = <List<(double, String)>>[];
}

/// Parses a Guitar Pro 3/4/5 file.
ImportedScore importGuitarPro(Uint8List bytes) {
  final r = _Reader(bytes);
  final version = r.byteSizeString(30);
  final m = RegExp(r'^FICHIER GUITAR PRO v(\d)\.(\d\d)').firstMatch(version);
  if (m == null) {
    if (version.startsWith('CLIPBOARD')) throw ImportException('Guitar Pro clipboard files are not supported');
    if (version.startsWith('FICHIER GUITARE PRO')) throw ImportException('Guitar Pro 1 and 2 files are not supported');
    throw ImportException('Not a Guitar Pro 3, 4 or 5 file');
  }
  final major = int.parse(m.group(1)!);
  final minor = int.parse(m.group(2)!);
  if (major < 3 || major > 5) throw ImportException('Guitar Pro version $major.$minor is not supported');
  final v510 = major == 5 && minor >= 10;
  return _GpParser(r, major, v510).read();
}

class _GpParser {
  _GpParser(this.r, this.major, this.v510);

  final _Reader r;
  final int major;
  final bool v510;
  final score = ImportedScore(format: '');
  final headers = <_Header>[];
  final tracks = <_Track>[];
  final channelPrograms = List<int>.filled(64, 0);

  ImportedScore read() {
    final s = ImportedScore(format: 'Guitar Pro $major');
    _readInfo(s);
    if (major == 3) {
      r.boolean(); // triplet feel
      s.tempo = r.i32().toDouble();
      r.i32(); // key
    } else if (major == 4) {
      r.boolean(); // triplet feel
      _readLyrics();
      s.tempo = r.i32().toDouble();
      r.i32(); // key
      r.i8(); // octave
    } else {
      _readLyrics();
      if (v510) r.skip(19); // master effect: volume, reserved, 11 equalizer knobs
      _readPageSetup();
      r.intByteSizeString(); // tempo name
      s.tempo = r.i32().toDouble();
      if (v510) r.boolean(); // hide tempo
      r.i8(); // key
      r.i32(); // octave
    }
    _readChannels();
    if (major == 5) {
      r.skip(38); // directions: 19 shorts
      r.i32(); // master reverb
    }
    final measureCount = r.i32();
    final trackCount = r.i32();
    if (measureCount < 0 || measureCount > 5000 || trackCount < 0 || trackCount > 64) {
      throw ImportException('Bad measure or track count in file');
    }
    for (var i = 0; i < measureCount; i++) {
      _readMeasureHeader(i);
    }
    for (var i = 0; i < trackCount; i++) {
      _readTrack(i);
    }
    if (major == 5) r.skip(v510 ? 1 : 2);
    for (var mi = 0; mi < measureCount; mi++) {
      for (final t in tracks) {
        _readMeasure(t, mi);
      }
    }
    if (headers.isNotEmpty) {
      s.beatsPerBar = headers.first.numerator;
      s.beatUnit = headers.first.denominator;
    }
    if (s.tempo <= 0) s.tempo = 120;
    _assemble(s);
    return s;
  }

  void _readInfo(ImportedScore s) {
    s.title = r.intByteSizeString();
    r.intByteSizeString(); // subtitle
    s.artist = r.intByteSizeString();
    r.intByteSizeString(); // album
    r.intByteSizeString(); // words
    if (major == 5) r.intByteSizeString(); // music
    r.intByteSizeString(); // copyright
    r.intByteSizeString(); // tabbed by
    r.intByteSizeString(); // instructions
    final notes = r.i32();
    if (notes < 0 || notes > 10000) throw ImportException('Bad file header');
    for (var i = 0; i < notes; i++) {
      r.intByteSizeString();
    }
  }

  void _readLyrics() {
    r.i32(); // track
    for (var i = 0; i < 5; i++) {
      r.i32(); // starting measure
      r.intSizeString();
    }
  }

  void _readPageSetup() {
    r.skip(7 * 4); // page size, margins, score size
    r.i16(); // header and footer flags
    for (var i = 0; i < 10; i++) {
      r.intByteSizeString();
    }
  }

  void _readChannels() {
    for (var i = 0; i < 64; i++) {
      channelPrograms[i] = r.i32();
      r.skip(8); // volume, balance, chorus, reverb, phaser, tremolo, 2 blank
    }
  }

  void _readMeasureHeader(int index) {
    final prev = headers.isEmpty ? null : headers.last;
    if (major == 5 && index > 0) r.skip(1);
    final flags = r.u8();
    final h = _Header();
    h.numerator = flags & 0x01 != 0 ? r.i8() : (prev?.numerator ?? 4);
    h.denominator = flags & 0x02 != 0 ? r.i8() : (prev?.denominator ?? 4);
    if (h.numerator <= 0 || h.numerator > 32) h.numerator = 4;
    if (![1, 2, 4, 8, 16, 32].contains(h.denominator)) h.denominator = 4;
    h.repeatOpen = flags & 0x04 != 0;
    if (flags & 0x08 != 0) h.repeatClose = r.i8();
    if (major < 5) {
      if (flags & 0x10 != 0) r.u8(); // alternate ending
      if (flags & 0x20 != 0) _readMarker();
      if (flags & 0x40 != 0) r.skip(2); // key signature
    } else {
      if (flags & 0x20 != 0) _readMarker();
      if (flags & 0x40 != 0) r.skip(2);
      if (flags & 0x10 != 0) r.u8();
      if (flags & 0x03 != 0) r.skip(4); // beams
      if (flags & 0x10 == 0) r.skip(1);
      r.u8(); // triplet feel
    }
    headers.add(h);
  }

  void _readMarker() {
    r.intByteSizeString();
    r.skip(4); // color
  }

  void _readTrack(int index) {
    final t = _Track();
    if (major == 5 && (index == 0 || !v510)) r.skip(1);
    final flags = r.u8();
    t.percussion = flags & 0x01 != 0;
    t.name = r.byteSizeString(40);
    t.stringCount = r.i32();
    if (t.stringCount < 0 || t.stringCount > 7) throw ImportException('Bad string count in file');
    for (var i = 0; i < 7; i++) {
      final tuning = r.i32();
      if (i < t.stringCount) t.tuning.add(tuning);
    }
    r.i32(); // port
    final channel = r.i32() - 1;
    r.i32(); // effect channel
    if (channel >= 0 && channel < 64) {
      t.program = channelPrograms[channel].clamp(0, 127);
      if (channel % 16 == 9) t.percussion = true;
    }
    r.i32(); // fret count
    t.capo = r.i32();
    r.skip(4); // color
    if (major == 5) {
      r.skip(v510 ? 49 : 44);
      if (v510) {
        r.intByteSizeString(); // RSE effect
        r.intByteSizeString(); // RSE effect category
      }
    }
    tracks.add(t);
  }

  void _readMeasure(_Track t, int measureIndex) {
    final notes = <_Note>[];
    final chords = <(double, String)>[];
    final voices = major == 5 ? 2 : 1;
    for (var v = 0; v < voices; v++) {
      final beats = r.i32();
      if (beats < 0 || beats > 10000) throw ImportException('Bad beat count in file');
      var offset = 0.0;
      for (var b = 0; b < beats; b++) {
        offset += _readBeat(t, offset, notes, chords);
      }
    }
    if (major == 5 && r.pos < r.bytes.length) r.u8(); // line break
    t.measures.add(notes);
    t.chords.add(chords);
  }

  /// Reads one beat and returns its length in quarter notes.
  double _readBeat(_Track t, double offset, List<_Note> notes, List<(double, String)> chords) {
    final flags = r.u8();
    var status = 1;
    if (flags & 0x40 != 0) status = r.u8();
    final durationByte = r.i8();
    var quarters = 4 / (1 << (durationByte + 2).clamp(0, 8));
    if (flags & 0x01 != 0) quarters *= 1.5;
    if (flags & 0x20 != 0) {
      final n = r.i32();
      final times = switch (n) {
        3 => 2,
        5 || 6 || 7 => 4,
        9 || 10 || 11 || 12 || 13 => 8,
        _ => n,
      };
      if (n > 0) quarters *= times / n;
    }
    if (flags & 0x02 != 0) {
      final name = _readChord(t.stringCount);
      if (name.trim().isNotEmpty) chords.add((offset, name.trim()));
    }
    if (flags & 0x04 != 0) r.intByteSizeString(); // text
    if (flags & 0x08 != 0) _readBeatEffects();
    if (flags & 0x10 != 0) _readMixTableChange();
    final stringFlags = r.u8();
    for (var s = 1; s <= t.stringCount; s++) {
      if (stringFlags & (1 << (7 - s)) != 0) {
        final n = _readNote(s, offset, quarters);
        if (status != 0) notes.add(n);
      }
    }
    if (major == 5) {
      final flags2 = r.i16();
      if (flags2 & 0x0800 != 0) r.u8();
    }
    return status == 0 ? 0 : quarters;
  }

  String _readChord(int stringCount) {
    final newFormat = r.boolean();
    if (!newFormat) {
      final name = r.intByteSizeString();
      final firstFret = r.i32();
      if (firstFret != 0) r.skip(6 * 4);
      return name;
    }
    if (major == 3) {
      r.skip(1 + 3 + 5 * 4 + 1); // sharp, blank, root, type, extension, bass, tonality, add
      final name = r.byteSizeString(22);
      r.skip(3 * 4 + 4 + 6 * 4 + 4 + 6 * 4 + 7 + 1);
      return name;
    }
    r.skip(1 + 3 + 3 + 4 + 4 + 1); // sharp, blank, root, type, extension, bass, tonality, add
    final name = r.byteSizeString(22);
    r.skip(3 + 4 + 7 * 4 + 1 + 15 + 7 + 1 + 7 + 1);
    return name;
  }

  void _readBeatEffects() {
    if (major == 3) {
      final flags = r.u8();
      if (flags & 0x20 != 0) {
        r.u8(); // tremolo bar or tap/slap/pop
        r.i32();
      }
      if (flags & 0x40 != 0) r.skip(2); // stroke
      return;
    }
    final flags1 = r.u8();
    final flags2 = r.u8();
    if (flags1 & 0x20 != 0) r.i8(); // tap, slap, pop
    if (flags2 & 0x04 != 0) _readBend();
    if (flags1 & 0x40 != 0) r.skip(2); // stroke
    if (flags2 & 0x02 != 0) r.i8(); // pick stroke
  }

  void _readBend() {
    r.i8(); // type
    r.i32(); // value
    final points = r.i32();
    if (points < 0 || points > 1000) throw ImportException('Bad bend in file');
    r.skip(points * 9);
  }

  void _readMixTableChange() {
    r.i8(); // instrument
    if (major == 5) {
      r.skip(16); // RSE instrument
    }
    final values = [for (var i = 0; i < 6; i++) r.i8()]; // volume, balance, chorus, reverb, phaser, tremolo
    if (major == 5) r.intByteSizeString(); // tempo name
    final tempo = r.i32();
    for (final v in values) {
      if (v >= 0) r.i8(); // duration
    }
    if (tempo >= 0) {
      r.i8();
      if (v510) r.boolean(); // hide tempo
    }
    if (major >= 4) r.i8(); // flags
    if (major == 5) {
      r.i8(); // wah
      if (v510) {
        r.intByteSizeString();
        r.intByteSizeString();
      }
    }
  }

  _Note _readNote(int string, double offset, double duration) {
    final flags = r.u8();
    var type = 1;
    var fret = 0;
    int? finger;
    if (flags & 0x20 != 0) type = r.u8();
    if (major < 5 && flags & 0x01 != 0) r.skip(2); // time-independent duration
    if (flags & 0x10 != 0) r.i8(); // dynamics
    if (flags & 0x20 != 0) fret = r.i8();
    if (flags & 0x80 != 0) {
      final left = r.i8();
      r.i8(); // right hand
      if (left >= 1 && left <= 4) finger = left;
    }
    if (major == 5) {
      if (flags & 0x01 != 0) r.f64(); // duration percent
      r.u8(); // swap accidentals
    }
    if (flags & 0x08 != 0) _readNoteEffects();
    return _Note(offset: offset, duration: duration, string: string, fret: fret, type: type, finger: finger);
  }

  void _readNoteEffects() {
    if (major == 3) {
      final flags = r.u8();
      if (flags & 0x01 != 0) _readBend();
      if (flags & 0x10 != 0) r.skip(4); // grace note
      return;
    }
    final flags1 = r.u8();
    final flags2 = r.u8();
    if (flags1 & 0x01 != 0) _readBend();
    if (flags1 & 0x10 != 0) r.skip(major == 5 ? 5 : 4); // grace note
    if (flags2 & 0x04 != 0) r.i8(); // tremolo picking
    if (flags2 & 0x08 != 0) r.i8(); // slide
    if (flags2 & 0x10 != 0) {
      final harmonic = r.i8();
      if (major == 5) {
        if (harmonic == 2) r.skip(3);
        if (harmonic == 3) r.skip(1);
      }
    }
    if (flags2 & 0x20 != 0) r.skip(2); // trill
  }

  /// Order in which measures are played, with repeats unrolled.
  List<int> _playOrder() {
    final order = <int>[];
    var open = 0;
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h.repeatOpen) open = i;
      order.add(i);
      if (h.repeatClose >= 0) {
        final plays = (major == 5 ? h.repeatClose : h.repeatClose + 1).clamp(1, 8);
        for (var k = 1; k < plays && order.length < headers.length * 4 + 64; k++) {
          order.addAll([for (var j = open; j <= i; j++) j]);
        }
        open = i + 1;
      }
    }
    return order;
  }

  void _assemble(ImportedScore s) {
    final order = _playOrder();
    final starts = <double>[];
    var start = 0.0;
    for (final mi in order) {
      starts.add(start);
      start += headers[mi].quarters;
    }
    final seenChords = <double>{};
    for (final t in tracks) {
      final track = ImportedTrack(
        name: t.name,
        tuning: t.stringCount >= 6 ? t.tuning.sublist(0, 6) : null,
        capo: t.capo,
        program: t.program,
        percussion: t.percussion,
      );
      final lastOnString = <int, ImportedNote>{};
      for (var k = 0; k < order.length; k++) {
        final mi = order[k];
        if (mi >= t.measures.length) continue;
        for (final (offset, name) in t.chords[mi]) {
          final at = starts[k] + offset;
          if (seenChords.add(at)) s.chords.add(ImportedChord(start: at, name: name));
        }
        for (final n in t.measures[mi]) {
          if (n.string < 1 || n.string > t.tuning.length) continue;
          final at = starts[k] + n.offset;
          if (n.type == 2) {
            final prev = lastOnString[n.string];
            if (prev != null && (at - prev.end).abs() < 0.26) prev.duration = at + n.duration - prev.start;
            continue;
          }
          if (n.type == 3 || n.fret < 0) continue;
          final pitch = t.tuning[n.string - 1] + t.capo + n.fret;
          final onNeck = t.stringCount >= 6 && n.string <= 6;
          final note = ImportedNote(
            start: at,
            duration: n.duration,
            pitch: pitch,
            string: onNeck ? n.string : null,
            fret: onNeck ? n.fret : null,
            finger: n.finger,
          );
          track.notes.add(note);
          lastOnString[n.string] = note;
        }
      }
      s.tracks.add(track);
    }
  }
}
