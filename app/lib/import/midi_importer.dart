/// Reads Standard MIDI Files (.mid, .midi, .kar): formats 0, 1 and 2.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'score.dart';

const _gmNames = [
  'Piano', 'Piano', 'Piano', 'Piano', 'Electric piano', 'Electric piano', 'Harpsichord', 'Clavinet', //
  'Celesta', 'Glockenspiel', 'Music box', 'Vibraphone', 'Marimba', 'Xylophone', 'Bells', 'Dulcimer',
  'Organ', 'Organ', 'Organ', 'Church organ', 'Reed organ', 'Accordion', 'Harmonica', 'Accordion',
  'Nylon guitar', 'Steel guitar', 'Jazz guitar', 'Clean guitar', 'Muted guitar', 'Overdrive guitar', 'Distortion guitar', 'Guitar harmonics',
  'Acoustic bass', 'Bass', 'Bass', 'Fretless bass', 'Slap bass', 'Slap bass', 'Synth bass', 'Synth bass',
  'Violin', 'Viola', 'Cello', 'Contrabass', 'Strings', 'Strings', 'Harp', 'Timpani',
  'Strings', 'Strings', 'Synth strings', 'Synth strings', 'Choir', 'Voice', 'Synth voice', 'Orchestra hit',
  'Trumpet', 'Trombone', 'Tuba', 'Muted trumpet', 'French horn', 'Brass', 'Synth brass', 'Synth brass',
  'Soprano sax', 'Alto sax', 'Tenor sax', 'Baritone sax', 'Oboe', 'English horn', 'Bassoon', 'Clarinet',
  'Piccolo', 'Flute', 'Recorder', 'Pan flute', 'Bottle', 'Shakuhachi', 'Whistle', 'Ocarina',
  'Lead', 'Lead', 'Lead', 'Lead', 'Lead', 'Lead', 'Lead', 'Lead',
  'Pad', 'Pad', 'Pad', 'Pad', 'Pad', 'Pad', 'Pad', 'Pad',
  'FX', 'FX', 'FX', 'FX', 'FX', 'FX', 'FX', 'FX',
  'Sitar', 'Banjo', 'Shamisen', 'Koto', 'Kalimba', 'Bagpipe', 'Fiddle', 'Shanai',
  'Bell', 'Agogo', 'Steel drums', 'Woodblock', 'Taiko', 'Tom', 'Synth drum', 'Cymbal',
  'FX', 'FX', 'FX', 'FX', 'FX', 'FX', 'FX', 'FX',
];

class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  int pos = 0;

  bool get eof => pos >= bytes.length;

  int u8() {
    if (pos >= bytes.length) throw ImportException('MIDI file ends too early');
    return bytes[pos++];
  }

  int u16() => (u8() << 8) | u8();
  int u32() => (u16() << 16) | u16();

  int varLen() {
    var v = 0;
    for (var i = 0; i < 4; i++) {
      final b = u8();
      v = (v << 7) | (b & 0x7f);
      if (b & 0x80 == 0) return v;
    }
    throw ImportException('Bad MIDI variable-length number');
  }

  String ascii(int n) {
    final s = latin1.decode(bytes.sublist(pos, pos + n));
    pos += n;
    return s;
  }
}

class _Pending {
  _Pending(this.startTick, this.velocity);
  final int startTick;
  final int velocity;
}

/// Notes of one MIDI track (or, in a format 0 file, of one channel).
class _RawTrack {
  _RawTrack(this.index);
  final int index;
  String name = '';
  final Map<int, int> programByChannel = {};
  final List<(int tick, int channel, int pitch, int length)> notes = [];
  final Set<int> channels = {};
}

/// Parses a Standard MIDI File into an [ImportedScore].
ImportedScore importMidi(Uint8List bytes) {
  final r = _Reader(bytes);
  if (bytes.length < 14 || r.ascii(4) != 'MThd') throw ImportException('Not a MIDI file');
  final headerLength = r.u32();
  final format = r.u16();
  final trackCount = r.u16();
  final division = r.u16();
  r.pos += headerLength - 6;
  if (division & 0x8000 != 0) throw ImportException('SMPTE-timed MIDI files are not supported');
  final ticksPerQuarter = division == 0 ? 480 : division;

  final score = ImportedScore(format: 'MIDI');
  final raw = <_RawTrack>[];
  int? tempoMicros;
  int? tsNum, tsDen;
  var trackName = '';
  final programNow = List<int>.filled(16, 0);

  for (var t = 0; t < trackCount && !r.eof; t++) {
    if (r.ascii(4) != 'MTrk') throw ImportException('Bad MIDI track header');
    final length = r.u32();
    final end = r.pos + length;
    final track = _RawTrack(t);
    final pending = <int, List<_Pending>>{}; // channel << 8 | pitch
    var tick = 0;
    var status = 0;
    while (r.pos < end) {
      tick += r.varLen();
      var b = r.u8();
      if (b < 0x80) {
        if (status == 0) throw ImportException('Bad MIDI event');
        r.pos--;
        b = status;
      } else if (b < 0xF0) {
        status = b;
      }
      if (b == 0xFF) {
        final type = r.u8();
        final len = r.varLen();
        final data = bytes.sublist(r.pos, r.pos + len);
        r.pos += len;
        switch (type) {
          case 0x51 when len >= 3:
            tempoMicros ??= (data[0] << 16) | (data[1] << 8) | data[2];
          case 0x58 when len >= 2:
            tsNum ??= data[0];
            tsDen ??= 1 << data[1];
          case 0x03:
            track.name = _text(data);
          case 0x01 when t == 0 && trackName.isEmpty && format == 1:
            trackName = _text(data);
          case 0x02 when score.artist.isEmpty && _text(data).length < 80:
            score.artist = _text(data);
        }
      } else if (b == 0xF0 || b == 0xF7) {
        r.pos += r.varLen();
      } else {
        final kind = b & 0xF0;
        final channel = b & 0x0F;
        switch (kind) {
          case 0x80:
          case 0x90:
            final pitch = r.u8();
            final velocity = r.u8();
            final key = (channel << 8) | pitch;
            if (kind == 0x90 && velocity > 0) {
              (pending[key] ??= []).add(_Pending(tick, velocity));
            } else {
              final list = pending[key];
              if (list != null && list.isNotEmpty) {
                final p = list.removeAt(0);
                track.notes.add((p.startTick, channel, pitch, tick - p.startTick));
                track.channels.add(channel);
              }
            }
          case 0xA0:
          case 0xB0:
          case 0xE0:
            r.pos += 2;
          case 0xC0:
            final program = r.u8();
            programNow[channel] = program;
            track.programByChannel.putIfAbsent(channel, () => program);
          case 0xD0:
            r.pos += 1;
        }
      }
    }
    // Notes still sounding at the end of the track.
    for (final e in pending.entries) {
      for (final p in e.value) {
        track.notes.add((p.startTick, e.key >> 8, e.key & 0xFF, ticksPerQuarter));
        track.channels.add(e.key >> 8);
      }
    }
    r.pos = end;
    if (track.notes.isNotEmpty || track.name.isNotEmpty) raw.add(track);
  }

  score.tempo = tempoMicros == null || tempoMicros <= 0 ? 120 : 60e6 / tempoMicros;
  score.beatsPerBar = tsNum ?? 4;
  score.beatUnit = tsDen ?? 4;
  score.title = trackName;
  if (format == 1 && raw.isNotEmpty && raw.first.notes.isEmpty && raw.first.name.isNotEmpty && score.title.isEmpty) {
    score.title = raw.first.name;
  }

  // A track that plays on several channels (format 0 files) is split per channel.
  final programs = <int, int>{};
  for (final t in raw) {
    programs.addAll(t.programByChannel);
  }
  for (final t in raw) {
    if (t.notes.isEmpty) continue;
    for (final channel in t.channels.toList()..sort()) {
      final notes = t.notes.where((n) => n.$2 == channel).toList()..sort((a, b) => a.$1.compareTo(b.$1));
      if (notes.isEmpty) continue;
      final program = t.programByChannel[channel] ?? programs[channel] ?? 0;
      final track = ImportedTrack(
        name: t.name.isNotEmpty && t.channels.length == 1 ? t.name : _trackName(t, channel, program),
        program: program,
        percussion: channel == 9,
      );
      for (final (tick, _, pitch, length) in notes) {
        track.notes.add(ImportedNote(
          start: tick / ticksPerQuarter,
          duration: length / ticksPerQuarter,
          pitch: pitch,
        ));
      }
      score.tracks.add(track);
    }
  }
  if (score.tracks.isEmpty) throw ImportException.noNotes('This MIDI file has no notes');
  return score;
}

String _text(List<int> data) {
  try {
    return utf8.decode(data).trim();
  } catch (_) {
    return latin1.decode(data).trim();
  }
}

String _trackName(_RawTrack t, int channel, int program) {
  if (channel == 9) return 'Drums';
  final base = t.name.isNotEmpty ? t.name : _gmNames[program.clamp(0, 127)];
  return t.channels.length > 1 ? '$base (${channel + 1})' : base;
}
