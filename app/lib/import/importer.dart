/// Turns a song file from the device into the app's song format.
///
/// Supported: Guitar Pro (.gp3, .gp4, .gp5, .gpx, .gp), MIDI (.mid, .midi,
/// .kar), MusicXML (.musicxml, .xml, .mxl), text tabs (.txt, .tab) and the
/// app's own JSON song files.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/song.dart';
import 'arrange.dart';
import 'ascii_tab_importer.dart';
import 'gpif_importer.dart';
import 'guitar_pro_importer.dart';
import 'midi_importer.dart';
import 'musicxml_importer.dart';
import 'score.dart';

/// File name extensions the app can open, lower case without the dot.
const supportedExtensions = [
  'gp3', 'gp4', 'gp5', 'gpx', 'gp', //
  'mid', 'midi', 'kar', 'smf',
  'musicxml', 'mxl', 'xml',
  'txt', 'tab', 'crd',
  'json',
];

/// Human-readable format groups, for the help text.
const supportedFormatNames = ['Guitar Pro (gp3, gp4, gp5, gpx, gp)', 'MIDI (mid, midi)', 'MusicXML (musicxml, mxl, xml)', 'Text tabs (txt, tab)'];

/// A file picked by the user.
class ImportFile {
  const ImportFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// What became of one file.
class ImportOutcome {
  const ImportOutcome({required this.fileName, this.song, this.error, this.errorCode});
  final String fileName;

  /// The song JSON, ready to save and play, when the file could be read.
  final Map<String, dynamic>? song;
  final String? error;
  final ImportError? errorCode;

  bool get ok => song != null;
}

String extensionOf(String name) {
  final base = name.split('/').last.split('\\').last;
  final dot = base.lastIndexOf('.');
  return dot < 0 ? '' : base.substring(dot + 1).toLowerCase();
}

String _sniff(Uint8List b) {
  if (b.length >= 4) {
    final tag = String.fromCharCodes(b, 0, 4);
    if (tag == 'MThd') return 'mid';
    if (tag == 'BCFZ' || tag == 'BCFS') return 'gpx';
    if (b[0] == 0x50 && b[1] == 0x4B && b[2] == 3 && b[3] == 4) return 'zip';
  }
  if (b.length >= 20 && String.fromCharCodes(b, 1, 20).startsWith('FICHIER GUITAR')) return 'gp5';
  var i = 0;
  while (i < b.length && i < 4 && (b[i] == 0xEF || b[i] == 0xBB || b[i] == 0xBF || b[i] == 0xFE || b[i] == 0xFF)) {
    i++; // byte order marks
  }
  final head = String.fromCharCodes(b, i, i + 512 < b.length ? i + 512 : b.length).trimLeft();
  if (head.startsWith('<')) return 'xml';
  if (head.startsWith('{')) return 'json';
  return 'txt';
}

/// Reads one file. Throws [ImportException] with a message for the user.
Map<String, dynamic> importSongFile(ImportFile file, {required Set<String> knownChords}) {
  final bytes = file.bytes;
  if (bytes.isEmpty) throw ImportException('The file is empty', code: ImportError.empty);
  if (bytes.length > 50 * 1024 * 1024) throw ImportException('The file is too large', code: ImportError.tooLarge);
  var ext = extensionOf(file.name);
  final sniffed = _sniff(bytes);
  // A file of another kind (.pdf, .jpg, ...) unless its contents are clearly a known format.
  if (!supportedExtensions.contains(ext) && sniffed == 'txt') {
    throw ImportException('Files of type .$ext are not supported', code: ImportError.unsupported);
  }
  // Trust the contents over the name when they disagree (a .txt that is really XML, ...).
  if (!supportedExtensions.contains(ext) || ext == 'xml' || ext == 'txt' || ext == 'json') ext = sniffed == 'zip' ? (ext == 'mxl' ? 'mxl' : 'gp') : sniffed;
  if (ext == 'gp' && sniffed != 'zip') ext = sniffed;
  if ((ext == 'mid' || ext == 'midi' || ext == 'kar' || ext == 'smf') && sniffed != 'mid') ext = sniffed;

  final id = 'file-${fnv1a(bytes)}';
  ImportedScore score;
  switch (ext) {
    case 'json':
      return _fromAppJson(bytes, id, file.name);
    case 'mid' || 'midi' || 'kar' || 'smf':
      score = importMidi(bytes);
    case 'gp3' || 'gp4' || 'gp5':
      score = importGuitarPro(bytes);
    case 'gpx':
      score = importGpx(bytes);
    case 'gp' || 'zip':
      score = _zipped(bytes);
    case 'mxl':
      score = importMxl(bytes);
    case 'musicxml' || 'xml':
      score = _xml(bytes);
    case 'txt' || 'tab' || 'crd':
      score = importAsciiTab(bytes, fileName: file.name);
    default:
      throw ImportException('Files of type .$ext are not supported', code: ImportError.unsupported);
  }
  final json = arrangeScore(score, id: id, fileName: file.name, knownChords: knownChords);
  Song.fromJson(json); // makes sure the app can play it
  return json;
}

/// A zip is a Guitar Pro 7/8 file or a compressed MusicXML file.
ImportedScore _zipped(Uint8List bytes) {
  try {
    return importGp7(bytes);
  } on ImportException {
    return importMxl(bytes);
  }
}

/// An .xml file is MusicXML, or the music of a Guitar Pro 6/7 file.
ImportedScore _xml(Uint8List bytes) {
  final head = String.fromCharCodes(bytes, 0, bytes.length < 2048 ? bytes.length : 2048);
  if (head.contains('<GPIF')) return importGpif(bytes, format: 'Guitar Pro');
  return importMusicXml(bytes);
}

Map<String, dynamic> _fromAppJson(Uint8List bytes, String id, String fileName) {
  Map<String, dynamic> j;
  try {
    j = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
  } catch (_) {
    throw ImportException('Not a song file');
  }
  if (j['tracks'] is! Map) throw ImportException('Not a song file');
  j = {...j, 'id': id, 'fileName': fileName, 'format': 'Song file', 'tags': const ['my-songs']};
  j.putIfAbsent('source', () => 'Imported from $fileName');
  final song = Song.fromJson(j);
  if (!song.hasFull && !song.hasEasy) throw ImportException.noNotes('This song file has no notes');
  return j;
}

/// A short, stable fingerprint of a file's contents.
String fnv1a(List<int> bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  // Mix in the length so files of different sizes never share an id.
  h = ((h ^ bytes.length) * 0x01000193) & 0xffffffff;
  return h.toRadixString(16).padLeft(8, '0');
}

/// Arguments for [importFilesInIsolate].
class ImportRequest {
  const ImportRequest({required this.files, required this.knownChords});
  final List<ImportFile> files;
  final Set<String> knownChords;
}

/// Reads every file; never throws, each outcome carries its own error.
/// Meant to run in a background isolate with `compute`.
List<ImportOutcome> importFilesInIsolate(ImportRequest request) {
  return [
    for (final f in request.files)
      () {
        try {
          return ImportOutcome(fileName: f.name, song: importSongFile(f, knownChords: request.knownChords));
        } on ImportException catch (e) {
          return ImportOutcome(fileName: f.name, error: e.message, errorCode: e.code);
        } catch (e) {
          return ImportOutcome(fileName: f.name, error: 'Could not read this file', errorCode: ImportError.damaged);
        }
      }(),
  ];
}
