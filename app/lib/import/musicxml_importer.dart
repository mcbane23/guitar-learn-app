/// Reads MusicXML files (.musicxml, .xml and the zipped .mxl), as exported
/// by MuseScore, Guitar Pro, Finale, Sibelius and most notation programs.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../music/pitch.dart';
import 'score.dart';
import 'zip.dart';

/// A compressed MusicXML file: a zip whose META-INF/container.xml names the
/// score, or that simply holds one .xml/.musicxml file.
ImportedScore importMxl(Uint8List bytes) {
  final entries = readZip(bytes);
  String? rootFile;
  final container = entries.where((e) => e.name == 'META-INF/container.xml').firstOrNull;
  if (container != null) {
    try {
      final doc = XmlDocument.parse(utf8.decode(container.read(), allowMalformed: true));
      rootFile = doc.findAllElements('rootfile').map((e) => e.getAttribute('full-path')).whereType<String>().firstOrNull;
    } catch (_) {
      rootFile = null;
    }
  }
  final entry = entries.where((e) => e.name == rootFile).firstOrNull ??
      entries.where((e) => !e.name.startsWith('META-INF/') && RegExp(r'\.(musicxml|xml)$', caseSensitive: false).hasMatch(e.name)).firstOrNull;
  if (entry == null) throw ImportException('No music found in this MusicXML file');
  return importMusicXml(entry.read());
}

const _kindNames = {
  'major': '',
  'minor': 'm',
  'dominant': '7',
  'major-seventh': 'maj7',
  'minor-seventh': 'm7',
  'dominant-ninth': '9',
  'major-sixth': '6',
  'minor-sixth': 'm6',
  'suspended-fourth': 'sus4',
  'suspended-second': 'sus2',
  'diminished': 'dim',
  'augmented': 'aug',
  'power': '5',
  'half-diminished': 'm7b5',
  'diminished-seventh': 'dim7',
  'none': '',
};

const _stepIndex = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

String? _text(XmlElement? e, String name) => e?.getElement(name)?.innerText.trim();

int? _int(XmlElement? e, String name) {
  final t = _text(e, name);
  return t == null ? null : int.tryParse(t) ?? double.tryParse(t)?.round();
}

class _Part {
  _Part(this.id);
  final String id;
  String name = '';
  int program = 0;
  bool percussion = false;
}

/// Notes of one staff of a part, so that a TAB staff can be preferred over
/// a duplicated notation staff.
class _Staff {
  final notes = <ImportedNote>[];
  var tabbed = 0;
  List<int>? tuning; // index 0 = string 1
  int capo = 0;
}

/// Parses an uncompressed MusicXML document.
ImportedScore importMusicXml(Uint8List bytes) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(_decode(bytes));
  } on XmlException catch (e) {
    throw ImportException('Damaged MusicXML file: ${e.message}');
  }
  var root = doc.rootElement;
  if (root.name.local == 'score-timewise') root = _timewiseToPartwise(root);
  if (root.name.local != 'score-partwise') throw ImportException('Not a MusicXML file');

  final s = ImportedScore(format: 'MusicXML');
  s.title = _text(root.getElement('work'), 'work-title') ?? _text(root, 'movement-title') ?? '';
  for (final c in root.getElement('identification')?.findElements('creator') ?? const Iterable<XmlElement>.empty()) {
    final type = c.getAttribute('type');
    if (s.artist.isEmpty || type == 'composer' || type == 'artist') s.artist = c.innerText.trim();
    if (type == 'composer' || type == 'artist') break;
  }

  final parts = <String, _Part>{};
  for (final sp in root.getElement('part-list')?.findAllElements('score-part') ?? const Iterable<XmlElement>.empty()) {
    final p = _Part(sp.getAttribute('id') ?? '');
    p.name = _text(sp, 'part-name') ?? '';
    final mi = sp.getElement('midi-instrument');
    if (mi != null) {
      p.program = (_int(mi, 'midi-program') ?? 1) - 1;
      if (_int(mi, 'midi-channel') == 10 || _int(mi, 'midi-unpitched') != null) p.percussion = true;
    }
    parts[p.id] = p;
  }

  var tempoSet = false;
  var timeSet = false;
  for (final partEl in root.findElements('part')) {
    final info = parts[partEl.getAttribute('id') ?? ''] ?? _Part('');
    final staves = <int, _Staff>{};
    var divisions = 1;
    var transpose = 0;
    var hasTranspose = false;
    var measureStart = 0.0; // quarters
    final lastByKey = <int, ImportedNote>{};
    final tiedKeys = <int>{};

    for (final measure in partEl.findElements('measure')) {
      var cursor = 0; // divisions from the measure start
      var maxCursor = 0;
      var chordAnchor = 0;
      for (final el in measure.childElements) {
        switch (el.name.local) {
          case 'attributes':
            divisions = _int(el, 'divisions') ?? divisions;
            if (divisions <= 0) divisions = 1;
            final time = el.getElement('time');
            if (time != null && !timeSet) {
              s.beatsPerBar = _int(time, 'beats') ?? 4;
              s.beatUnit = _int(time, 'beat-type') ?? 4;
              timeSet = true;
            }
            final tr = el.getElement('transpose');
            if (tr != null) {
              hasTranspose = true;
              transpose = (_int(tr, 'chromatic') ?? 0) + 12 * (_int(tr, 'octave-change') ?? 0);
            }
            for (final sd in el.findElements('staff-details')) {
              final staffNo = int.tryParse(sd.getAttribute('number') ?? '') ?? 1;
              final staff = staves.putIfAbsent(staffNo, _Staff.new);
              final lines = _int(sd, 'staff-lines') ?? 0;
              final tunings = sd.findElements('staff-tuning').toList();
              if (tunings.isNotEmpty) {
                final byLine = <int, int>{};
                for (final t in tunings) {
                  final line = int.tryParse(t.getAttribute('line') ?? '') ?? 0;
                  final step = _text(t, 'tuning-step') ?? 'E';
                  final alter = _int(t, 'tuning-alter') ?? 0;
                  final octave = _int(t, 'tuning-octave') ?? 2;
                  byLine[line] = (octave + 1) * 12 + (_stepIndex[step.toUpperCase()] ?? 4) + alter;
                }
                final count = lines > 0 ? lines : byLine.length;
                // Line 1 is the bottom line, the thickest string.
                staff.tuning = [for (var string = 1; string <= count; string++) byLine[count - string + 1] ?? standardTuning[(string - 1).clamp(0, 5)]];
              }
              final capo = _int(sd, 'capo');
              if (capo != null) staff.capo = capo;
            }
          case 'direction':
            if (!tempoSet) {
              final sound = el.getElement('sound');
              final tempo = double.tryParse(sound?.getAttribute('tempo') ?? '');
              if (tempo != null && tempo > 0) {
                s.tempo = tempo;
                tempoSet = true;
              } else {
                final metro = el.findAllElements('metronome').firstOrNull;
                final perMinute = double.tryParse(_text(metro, 'per-minute') ?? '');
                if (metro != null && perMinute != null && perMinute > 0) {
                  var unit = switch (_text(metro, 'beat-unit')) {
                    'half' => 2.0,
                    'eighth' => 0.5,
                    '16th' => 0.25,
                    'whole' => 4.0,
                    _ => 1.0,
                  };
                  if (metro.getElement('beat-unit-dot') != null) unit *= 1.5;
                  s.tempo = perMinute * unit;
                  tempoSet = true;
                }
              }
            }
          case 'sound':
            final tempo = double.tryParse(el.getAttribute('tempo') ?? '');
            if (!tempoSet && tempo != null && tempo > 0) {
              s.tempo = tempo;
              tempoSet = true;
            }
          case 'harmony':
            final name = _harmonyName(el);
            final offset = _int(el, 'offset') ?? 0;
            if (name != null) s.chords.add(ImportedChord(start: measureStart + (cursor + offset) / divisions, name: name));
          case 'backup':
            cursor -= _int(el, 'duration') ?? 0;
            if (cursor < 0) cursor = 0;
          case 'forward':
            cursor += _int(el, 'duration') ?? 0;
          case 'note':
            final duration = _int(el, 'duration') ?? 0;
            final isChord = el.getElement('chord') != null;
            final isGrace = el.getElement('grace') != null;
            final isRest = el.getElement('rest') != null;
            final start = isChord ? chordAnchor : cursor;
            if (!isChord) chordAnchor = cursor;
            if (!isGrace && !isChord) cursor += duration;
            if (cursor > maxCursor) maxCursor = cursor;
            if (isRest || isGrace || duration <= 0) continue;
            final staffNo = _int(el, 'staff') ?? 1;
            final staff = staves.putIfAbsent(staffNo, _Staff.new);
            final pitchEl = el.getElement('pitch');
            final technical = el.getElement('notations')?.getElement('technical');
            final string = _int(technical, 'string');
            final fret = _int(technical, 'fret');
            final fingerText = _text(technical, 'fingering');
            final finger = fingerText == null ? null : int.tryParse(fingerText);
            int? pitch;
            if (string != null && fret != null && staff.tuning != null && string >= 1 && string <= staff.tuning!.length) {
              pitch = staff.tuning![string - 1] + staff.capo + fret;
            } else if (pitchEl != null) {
              final step = _text(pitchEl, 'step') ?? 'C';
              final alter = _int(pitchEl, 'alter') ?? 0;
              final octave = _int(pitchEl, 'octave') ?? 4;
              pitch = (octave + 1) * 12 + (_stepIndex[step.toUpperCase()] ?? 0) + alter + transpose;
              if (!hasTranspose && string == null && (info.program >= 24 && info.program <= 31 || _looksLikeGuitar(info.name))) {
                pitch -= 12; // guitar music is written an octave above where it sounds
              }
            }
            if (pitch == null) continue;
            final tieStop = el.findElements('tie').any((t) => t.getAttribute('type') == 'stop') ||
                (el.getElement('notations')?.findElements('tied').any((t) => t.getAttribute('type') == 'stop') ?? false);
            final tieStart = el.findElements('tie').any((t) => t.getAttribute('type') == 'start') ||
                (el.getElement('notations')?.findElements('tied').any((t) => t.getAttribute('type') == 'start') ?? false);
            final key = staffNo * 100000 + (string ?? 0) * 1000 + pitch;
            final at = measureStart + start / divisions;
            final quarters = duration / divisions;
            if (tieStop && tiedKeys.contains(key)) {
              final prev = lastByKey[key];
              if (prev != null) prev.duration = at + quarters - prev.start;
              if (!tieStart) tiedKeys.remove(key);
              continue;
            }
            final note = ImportedNote(
              start: at,
              duration: quarters,
              pitch: pitch,
              string: string,
              fret: fret,
              finger: finger != null && finger >= 1 && finger <= 4 ? finger : null,
            );
            staff.notes.add(note);
            if (string != null && fret != null) staff.tabbed++;
            lastByKey[key] = note;
            if (tieStart) {
              tiedKeys.add(key);
            } else {
              tiedKeys.remove(key);
            }
        }
      }
      final measureLength = maxCursor > 0 ? maxCursor / divisions : s.beatsPerBar * 4 / s.beatUnit;
      measureStart += measureLength;
    }

    // One staff per part: the tablature staff when there is one.
    if (staves.isEmpty) continue;
    final best = staves.values.reduce((a, b) => b.tabbed > a.tabbed || (b.tabbed == a.tabbed && b.notes.length > a.notes.length) ? b : a);
    final tuning = best.tuning;
    final track = ImportedTrack(
      name: info.name,
      tuning: tuning != null && tuning.length >= 6 ? tuning.sublist(0, 6) : null,
      capo: best.capo,
      program: info.program,
      percussion: info.percussion,
    );
    for (final n in best.notes) {
      final onNeck = n.string != null && n.fret != null && tuning != null && tuning.length >= 6 && n.string! <= 6;
      track.notes.add(onNeck
          ? n
          : ImportedNote(start: n.start, duration: n.duration, pitch: n.pitch, finger: n.finger));
    }
    s.tracks.add(track);
  }
  if (s.tracks.isEmpty) throw ImportException.noNotes('This MusicXML file has no notes');
  return s;
}

bool _looksLikeGuitar(String name) {
  final n = name.toLowerCase();
  return n.contains('guitar') || n.contains('gtr') || n.contains('gitar');
}

String? _harmonyName(XmlElement h) {
  final root = h.getElement('root');
  final step = _text(root, 'root-step');
  if (step == null) return null;
  final alter = _int(root, 'root-alter') ?? 0;
  final kindEl = h.getElement('kind');
  final kindText = kindEl?.getAttribute('text');
  final kind = _kindNames[kindEl?.innerText.trim()] ?? kindText ?? '';
  final suffix = kindText != null && kindText.isNotEmpty && kindText.length <= 5 ? kindText : kind;
  return '$step${alter > 0 ? '#' : alter < 0 ? 'b' : ''}$suffix';
}

String _decode(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}

/// Regroups a timewise score (measures containing parts) into a partwise one.
XmlElement _timewiseToPartwise(XmlElement timewise) {
  final partwise = XmlElement(XmlName('score-partwise'));
  final byPart = <String, XmlElement>{};
  for (final child in timewise.childElements) {
    if (child.name.local != 'measure') {
      partwise.children.add(child.copy());
      continue;
    }
    for (final part in child.findElements('part')) {
      final id = part.getAttribute('id') ?? '';
      final target = byPart.putIfAbsent(id, () {
        final p = XmlElement(XmlName('part'), [XmlAttribute(XmlName('id'), id)]);
        partwise.children.add(p);
        return p;
      });
      final m = XmlElement(XmlName('measure'), [for (final a in child.attributes) a.copy()]);
      for (final c in part.children) {
        m.children.add(c.copy());
      }
      target.children.add(m);
    }
  }
  return partwise;
}
