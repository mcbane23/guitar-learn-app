/// Reads the XML music of Guitar Pro 6, 7 and 8 (`score.gpif` inside .gpx
/// and .gp files).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'gpx_container.dart';
import 'score.dart';
import 'zip.dart';

/// A Guitar Pro 7/8 file: a zip with Content/score.gpif inside.
ImportedScore importGp7(Uint8List bytes) {
  final entries = readZip(bytes);
  final gpif = entries.where((e) => e.name.toLowerCase().endsWith('score.gpif')).firstOrNull ??
      entries.where((e) => e.name.toLowerCase().endsWith('.gpif')).firstOrNull;
  if (gpif == null) throw ImportException('No music found in this Guitar Pro file');
  return importGpif(gpif.read(), format: 'Guitar Pro 7');
}

/// A Guitar Pro 6 file (.gpx).
ImportedScore importGpx(Uint8List bytes) => importGpif(readGpxScore(bytes), format: 'Guitar Pro 6');

const _noteValues = {
  'Whole': 4.0,
  'Half': 2.0,
  'Quarter': 1.0,
  'Eighth': 0.5,
  '16th': 0.25,
  '32nd': 0.125,
  '64th': 0.0625,
  '128th': 0.03125,
  '256th': 0.015625,
};

const _fingers = {'I': 1, 'M': 2, 'A': 3, 'C': 4, 'P': 0, 'Open': 0};

class _Rhythm {
  _Rhythm(this.quarters);
  final double quarters;
}

class _Beat {
  _Beat({required this.rhythm, required this.noteIds, this.chordId, this.grace = false});
  final String rhythm;
  final List<String> noteIds;
  final String? chordId;
  final bool grace;
}

class _GNote {
  _GNote({this.string, this.fret, this.midi, this.tieDestination = false, this.muted = false, this.finger});
  final int? string; // 0 = lowest string
  final int? fret;
  final int? midi;
  final bool tieDestination;
  final bool muted;
  final int? finger;
}

class _GTrack {
  _GTrack(this.id);
  final String id;
  String name = '';
  List<int>? tuning; // low to high
  int capo = 0;
  int program = 0;
  bool percussion = false;
  final chordNames = <String, String>{};
}

class _MasterBar {
  int numerator = 4;
  int denominator = 4;
  final barIds = <String>[];
  bool repeatStart = false;
  int repeatCount = 0;
  double get quarters => numerator * 4 / denominator;
}

String? _childText(XmlElement e, String name) => e.getElement(name)?.innerText.trim();

XmlElement? _property(XmlElement? props, String name) {
  if (props == null) return null;
  for (final p in props.findElements('Property')) {
    if (p.getAttribute('name') == name) return p;
  }
  return null;
}

List<int> _ints(String? text) => [
      for (final s in (text ?? '').trim().split(RegExp(r'\s+')))
        if (s.isNotEmpty && int.tryParse(s) != null) int.parse(s),
    ];

/// Parses a score.gpif document.
ImportedScore importGpif(Uint8List xmlBytes, {required String format}) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(utf8.decode(xmlBytes, allowMalformed: true));
  } on XmlException catch (e) {
    throw ImportException('Damaged Guitar Pro file: ${e.message}');
  }
  final root = doc.rootElement;
  if (root.name.local != 'GPIF') throw ImportException('Not a Guitar Pro file');
  final s = ImportedScore(format: format);

  final scoreEl = root.getElement('Score');
  if (scoreEl != null) {
    s.title = _childText(scoreEl, 'Title') ?? '';
    s.artist = _childText(scoreEl, 'Artist') ?? '';
  }

  // Tempo: the first tempo automation, "120 2" = 120 quarter notes per minute.
  final master = root.getElement('MasterTrack');
  final automations = master?.getElement('Automations');
  if (automations != null) {
    for (final a in automations.findElements('Automation')) {
      if (_childText(a, 'Type') != 'Tempo') continue;
      final parts = (_childText(a, 'Value') ?? '').split(RegExp(r'\s+'));
      final bpm = double.tryParse(parts.first);
      if (bpm == null || bpm <= 0) continue;
      final unit = parts.length > 1 ? int.tryParse(parts[1]) ?? 2 : 2;
      s.tempo = bpm *
          switch (unit) {
            1 => 0.5,
            3 => 1.5,
            4 => 2,
            5 => 3,
            _ => 1,
          };
      break;
    }
  }

  // Tracks.
  final tracks = <_GTrack>[];
  for (final t in root.getElement('Tracks')?.findElements('Track') ?? const Iterable<XmlElement>.empty()) {
    final track = _GTrack(t.getAttribute('id') ?? '${tracks.length}');
    track.name = _childText(t, 'Name') ?? '';
    // GP6 keeps the properties on the track, GP7 on its staves.
    final propertySets = <XmlElement>[
      ...t.findElements('Properties'),
      for (final staff in t.getElement('Staves')?.findElements('Staff') ?? const Iterable<XmlElement>.empty())
        ...staff.findElements('Properties'),
    ];
    for (final props in propertySets) {
      final tuning = _property(props, 'Tuning');
      if (tuning != null && track.tuning == null) {
        final pitches = _ints(_childText(tuning, 'Pitches'));
        if (pitches.isNotEmpty) track.tuning = pitches;
      }
      final capo = _property(props, 'CapoFret');
      if (capo != null) track.capo = int.tryParse(_childText(capo, 'Fret') ?? '') ?? 0;
      final diagrams = _property(props, 'DiagramCollection') ?? _property(props, 'ChordCollection');
      if (diagrams != null) {
        for (final item in diagrams.getElement('Items')?.findElements('Item') ?? const Iterable<XmlElement>.empty()) {
          final id = item.getAttribute('id');
          final name = item.getAttribute('name');
          if (id != null && name != null) track.chordNames[id] = name;
        }
      }
    }
    final midi = t.getElement('GeneralMidi');
    if (midi != null) {
      track.program = int.tryParse(_childText(midi, 'Program') ?? '') ?? 0;
      if (_childText(midi, 'PrimaryChannel') == '9') track.percussion = true;
    }
    for (final sound in t.getElement('Sounds')?.findElements('Sound') ?? const Iterable<XmlElement>.empty()) {
      final p = int.tryParse(_childText(sound.getElement('MIDI') ?? sound, 'Program') ?? '');
      if (p != null) {
        track.program = p;
        break;
      }
    }
    final playback = t.getElement('PlaybackState')?.innerText ?? '';
    if (playback.contains('Percussion') || t.getElement('InstrumentSet')?.getElement('Type')?.innerText == 'drumKit') {
      track.percussion = true;
    }
    final channel = t.getElement('MidiConnection')?.getElement('PrimaryChannel')?.innerText.trim();
    if (channel == '9') track.percussion = true;
    if (track.tuning == null && !track.percussion) {
      // No tuning: a drum or a non-string instrument.
      track.percussion = t.findAllElements('Property').any((p) => p.getAttribute('name') == 'PercussionSet');
    }
    tracks.add(track);
  }
  if (tracks.isEmpty) throw ImportException.noNotes('This Guitar Pro file has no tracks');

  // Master bars and the bars of each track.
  final masterBars = <_MasterBar>[];
  int? lastNum, lastDen;
  for (final mb in root.getElement('MasterBars')?.findElements('MasterBar') ?? const Iterable<XmlElement>.empty()) {
    final bar = _MasterBar();
    final time = (_childText(mb, 'Time') ?? '').split('/');
    if (time.length == 2) {
      lastNum = int.tryParse(time[0]) ?? lastNum;
      lastDen = int.tryParse(time[1]) ?? lastDen;
    }
    bar.numerator = lastNum ?? 4;
    bar.denominator = lastDen ?? 4;
    bar.barIds.addAll((_childText(mb, 'Bars') ?? '').split(RegExp(r'\s+')).where((x) => x.isNotEmpty));
    final repeat = mb.getElement('Repeat');
    if (repeat != null) {
      bar.repeatStart = repeat.getAttribute('start') == 'true';
      if (repeat.getAttribute('end') == 'true') bar.repeatCount = int.tryParse(repeat.getAttribute('count') ?? '') ?? 2;
    }
    masterBars.add(bar);
  }
  if (masterBars.isEmpty) throw ImportException('This Guitar Pro file has no bars');
  s.beatsPerBar = masterBars.first.numerator;
  s.beatUnit = masterBars.first.denominator;

  final bars = <String, List<String>>{}; // bar id -> voice ids
  for (final b in root.getElement('Bars')?.findElements('Bar') ?? const Iterable<XmlElement>.empty()) {
    bars[b.getAttribute('id') ?? ''] = (_childText(b, 'Voices') ?? '').split(RegExp(r'\s+')).where((v) => v.isNotEmpty && v != '-1').toList();
  }
  final voices = <String, List<String>>{}; // voice id -> beat ids
  for (final v in root.getElement('Voices')?.findElements('Voice') ?? const Iterable<XmlElement>.empty()) {
    voices[v.getAttribute('id') ?? ''] = (_childText(v, 'Beats') ?? '').split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  }
  final rhythms = <String, _Rhythm>{};
  for (final rh in root.getElement('Rhythms')?.findElements('Rhythm') ?? const Iterable<XmlElement>.empty()) {
    var q = _noteValues[_childText(rh, 'NoteValue')] ?? 1.0;
    final dots = int.tryParse(rh.getElement('AugmentationDot')?.getAttribute('count') ?? '') ?? 0;
    if (dots == 1) q *= 1.5;
    if (dots == 2) q *= 1.75;
    final tuplet = rh.getElement('PrimaryTuplet');
    if (tuplet != null) {
      final num = int.tryParse(tuplet.getAttribute('num') ?? '') ?? 1;
      final den = int.tryParse(tuplet.getAttribute('den') ?? '') ?? 1;
      if (num > 0 && den > 0) q *= den / num;
    }
    rhythms[rh.getAttribute('id') ?? ''] = _Rhythm(q);
  }
  final beats = <String, _Beat>{};
  for (final b in root.getElement('Beats')?.findElements('Beat') ?? const Iterable<XmlElement>.empty()) {
    beats[b.getAttribute('id') ?? ''] = _Beat(
      rhythm: b.getElement('Rhythm')?.getAttribute('ref') ?? '',
      noteIds: (_childText(b, 'Notes') ?? '').split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList(),
      chordId: _childText(b, 'Chord'),
      grace: b.getElement('GraceNotes') != null,
    );
  }
  final notes = <String, _GNote>{};
  for (final n in root.getElement('Notes')?.findElements('Note') ?? const Iterable<XmlElement>.empty()) {
    final props = n.getElement('Properties');
    final tie = n.getElement('Tie');
    final fingerText = _childText(n, 'LeftFingering');
    notes[n.getAttribute('id') ?? ''] = _GNote(
      string: int.tryParse(_childText(_property(props, 'String') ?? XmlElement(XmlName('x')), 'String') ?? ''),
      fret: int.tryParse(_childText(_property(props, 'Fret') ?? XmlElement(XmlName('x')), 'Fret') ?? ''),
      midi: int.tryParse(_childText(_property(props, 'Midi') ?? XmlElement(XmlName('x')), 'Number') ?? ''),
      tieDestination: tie?.getAttribute('destination') == 'true',
      muted: _property(props, 'Muted') != null,
      finger: fingerText == null ? null : _fingers[fingerText],
    );
  }

  // Play order with repeats unrolled.
  final order = <int>[];
  var open = 0;
  for (var i = 0; i < masterBars.length; i++) {
    if (masterBars[i].repeatStart) open = i;
    order.add(i);
    final count = masterBars[i].repeatCount;
    if (count > 1) {
      for (var k = 1; k < count.clamp(1, 8) && order.length < masterBars.length * 4 + 64; k++) {
        order.addAll([for (var j = open; j <= i; j++) j]);
      }
      open = i + 1;
    }
  }
  final starts = <double>[];
  var at = 0.0;
  for (final i in order) {
    starts.add(at);
    at += masterBars[i].quarters;
  }

  final seenChords = <double>{};
  for (var ti = 0; ti < tracks.length; ti++) {
    final t = tracks[ti];
    final tuningLowToHigh = t.tuning;
    final track = ImportedTrack(
      name: t.name,
      tuning: tuningLowToHigh != null && tuningLowToHigh.length >= 6 ? tuningLowToHigh.reversed.take(6).toList() : null,
      capo: t.capo,
      program: t.program,
      percussion: t.percussion,
    );
    final stringCount = tuningLowToHigh?.length ?? 0;
    final lastOnString = <int, ImportedNote>{};
    for (var k = 0; k < order.length; k++) {
      final mb = masterBars[order[k]];
      if (ti >= mb.barIds.length) continue;
      for (final voiceId in bars[mb.barIds[ti]] ?? const <String>[]) {
        var offset = 0.0;
        for (final beatId in voices[voiceId] ?? const <String>[]) {
          final beat = beats[beatId];
          if (beat == null) continue;
          if (beat.grace) continue;
          final quarters = rhythms[beat.rhythm]?.quarters ?? 1.0;
          final start = starts[k] + offset;
          if (beat.chordId != null) {
            final name = t.chordNames[beat.chordId] ?? (int.tryParse(beat.chordId!) == null ? beat.chordId! : '');
            if (name.isNotEmpty && seenChords.add(start)) s.chords.add(ImportedChord(start: start, name: name));
          }
          for (final id in beat.noteIds) {
            final n = notes[id];
            if (n == null || n.muted) continue;
            int? string, fret, pitch;
            if (n.string != null && n.fret != null && tuningLowToHigh != null && n.string! < stringCount) {
              string = stringCount - n.string!; // gpif counts from the lowest string
              fret = n.fret;
              pitch = tuningLowToHigh[n.string!] + t.capo + fret!;
            } else if (n.midi != null) {
              pitch = n.midi;
            }
            if (pitch == null) continue;
            final key = string ?? (1000 + pitch);
            if (n.tieDestination) {
              final prev = lastOnString[key];
              if (prev != null && (start - prev.end).abs() < 0.26) prev.duration = start + quarters - prev.start;
              continue;
            }
            final onNeck = string != null && string >= 1 && string <= 6;
            final note = ImportedNote(
              start: start,
              duration: quarters,
              pitch: pitch,
              string: onNeck ? string : null,
              fret: onNeck ? fret : null,
              finger: n.finger != null && n.finger! > 0 ? n.finger : null,
            );
            track.notes.add(note);
            lastOnString[key] = note;
          }
          offset += quarters;
        }
      }
    }
    s.tracks.add(track);
  }
  return s;
}
