/// What every file importer produces: the notes of a piece of music before
/// they are arranged on the guitar neck. Times are in quarter notes from the
/// start of the song, pitches are MIDI note numbers.
library;

/// One sounding note. [string] and [fret] are set when the file says where
/// to play it (tabs); otherwise the arranger picks a position from [pitch].
class ImportedNote {
  ImportedNote({
    required this.start,
    required this.duration,
    required this.pitch,
    this.string,
    this.fret,
    this.finger,
  });

  /// Quarter notes from the start of the song.
  double start;

  /// Length in quarter notes.
  double duration;

  /// Sounding MIDI pitch.
  final int pitch;

  /// 1 = thinnest string, when known.
  final int? string;
  final int? fret;

  /// Left-hand finger 1..4 when the file gives one.
  final int? finger;

  double get end => start + duration;
}

/// One instrument part of the piece.
class ImportedTrack {
  ImportedTrack({
    required this.name,
    this.tuning,
    this.capo = 0,
    this.program = 0,
    this.percussion = false,
  });

  String name;

  /// Open-string pitches, index 0 = string 1 (thin), when the file says.
  List<int>? tuning;
  int capo;

  /// General MIDI program, 0-based (24..31 are guitars, 32..39 basses).
  int program;
  bool percussion;
  final List<ImportedNote> notes = [];

  bool get isGuitar => program >= 24 && program <= 31;
  bool get isBass => program >= 32 && program <= 39;
}

/// A chord name written over the music at some moment.
class ImportedChord {
  const ImportedChord({required this.start, required this.name});

  /// Quarter notes from the start of the song.
  final double start;
  final String name;
}

/// A whole imported piece of music.
class ImportedScore {
  ImportedScore({required this.format});

  /// Human-readable file format, e.g. "Guitar Pro 5".
  final String format;
  String title = '';
  String artist = '';

  /// Quarter notes per minute.
  double tempo = 120;
  int beatsPerBar = 4;

  /// Note value of one beat (4 = quarter note, 8 = eighth note).
  int beatUnit = 4;
  final List<ImportedTrack> tracks = [];
  final List<ImportedChord> chords = [];

  /// Tracks that have something to play, drums left out.
  List<ImportedTrack> get playable => [
        for (final t in tracks)
          if (!t.percussion && t.notes.isNotEmpty) t,
      ];
}

/// Why a file could not be read, for a translated message in the app.
enum ImportError { unsupported, empty, tooLarge, damaged, noNotes }

/// Thrown when a file cannot be read as a song.
class ImportException implements Exception {
  ImportException(this.message, {this.code = ImportError.damaged});
  final String message;
  final ImportError code;

  /// A file with nothing to play in it.
  ImportException.noNotes(this.message) : code = ImportError.noNotes;

  @override
  String toString() => message;
}
