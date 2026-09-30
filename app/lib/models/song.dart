import '../music/pitch.dart';

/// One note in a "full" track: press [fret] on [string] with [finger].
///
/// Strings are numbered 1 (thin, high E) to 6 (thick, low E). Fret 0 is an
/// open string. Finger 1 = index ... 4 = pinky, 0 = no finger.
class NoteEvent {
  const NoteEvent({
    required this.beat,
    required this.string,
    required this.fret,
    required this.finger,
    required this.length,
  });

  final double beat;
  final int string;
  final int fret;
  final int finger;
  final double length;

  factory NoteEvent.fromJson(Map<String, dynamic> j) => NoteEvent(
        beat: (j['beat'] as num).toDouble(),
        string: j['string'] as int,
        fret: j['fret'] as int,
        finger: (j['finger'] as int?) ?? 0,
        length: (j['length'] as num?)?.toDouble() ?? 1,
      );
}

enum Strum { down, up }

/// One chord strum in an "easy" track.
class ChordEvent {
  const ChordEvent({
    required this.beat,
    required this.chord,
    required this.length,
    this.strum = Strum.down,
  });

  final double beat;
  final String chord;
  final double length;
  final Strum strum;

  factory ChordEvent.fromJson(Map<String, dynamic> j) => ChordEvent(
        beat: (j['beat'] as num).toDouble(),
        chord: j['chord'] as String,
        length: (j['length'] as num?)?.toDouble() ?? 1,
        strum: j['strum'] == 'up' ? Strum.up : Strum.down,
      );
}

enum Difficulty { easy, medium, hard }

Difficulty _parseDifficulty(String? s) => switch (s) {
      'medium' => Difficulty.medium,
      'hard' => Difficulty.hard,
      _ => Difficulty.easy,
    };

/// What the song list needs to know about a song, without its notes.
/// This is also one entry of the online catalog (songs/index.json).
class SongInfo {
  const SongInfo({
    required this.id,
    required this.title,
    required this.artist,
    required this.difficulty,
    required this.language,
    required this.tags,
    this.file,
    this.version = 1,
    this.format,
    this.fileName,
  });

  final String id;
  final Map<String, String> title;
  final String artist;
  final Difficulty difficulty;
  final String language;
  final List<String> tags;
  final String? file;
  final int version;

  /// For songs imported from a file: the file format and name.
  final String? format;
  final String? fileName;

  /// Title in the given language code, falling back to English.
  String titleFor(String lang) => title[lang] ?? title['en'] ?? title.values.first;

  factory SongInfo.fromJson(Map<String, dynamic> j) => SongInfo(
        id: j['id'] as String,
        title: _stringMap(j['title']),
        artist: (j['artist'] as String?) ?? '',
        difficulty: _parseDifficulty(j['difficulty'] as String?),
        language: (j['language'] as String?) ?? 'instrumental',
        tags: ((j['tags'] as List?) ?? const []).cast<String>(),
        file: j['file'] as String?,
        version: (j['version'] as int?) ?? 1,
        format: j['format'] as String?,
        fileName: j['fileName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'difficulty': difficulty.name,
        'language': language,
        'tags': tags,
        if (file != null) 'file': file,
        'version': version,
        if (format != null) 'format': format,
        if (fileName != null) 'fileName': fileName,
      };
}

Map<String, String> _stringMap(Object? v) {
  if (v is String) return {'en': v};
  if (v is Map) return v.map((k, v) => MapEntry(k as String, v as String));
  return const {'en': ''};
}

/// One instrument part of an imported song (a file may hold several guitars).
class SongPart {
  const SongPart({required this.name, required this.tuning, required this.capo, required this.notes});

  final String name;

  /// Open-string MIDI pitches, index 0 = string 1 (thin).
  final List<int> tuning;
  final int capo;
  final List<NoteEvent> notes;
}

/// A complete song with its note tracks.
class Song {
  Song({
    required this.info,
    required this.tempo,
    required this.beatsPerBar,
    required this.tuning,
    required this.capo,
    required this.full,
    required this.easy,
    this.source = '',
    this.parts = const [],
    this.partIndex = 0,
  }) : totalBeats = _totalBeats(full, easy, beatsPerBar);

  final SongInfo info;

  /// Other parts of the same piece (empty unless the song was imported from
  /// a file with several tracks). [partIndex] says which one [full] shows.
  final List<SongPart> parts;
  final int partIndex;

  /// The same song showing another of its [parts].
  Song withPart(int index) {
    if (index < 0 || index >= parts.length || index == partIndex) return this;
    final p = parts[index];
    return Song(
      info: info,
      tempo: tempo,
      beatsPerBar: beatsPerBar,
      tuning: p.tuning,
      capo: p.capo,
      full: p.notes,
      easy: easy,
      source: source,
      parts: parts,
      partIndex: index,
    );
  }

  /// Highest fret any note uses (0 when there are no fretted notes).
  int get maxFret {
    var m = 0;
    for (final n in full) {
      if (n.fret > m) m = n.fret;
    }
    return m;
  }

  bool get isStandardTuning => tuning.length == 6 && [for (var i = 0; i < 6; i++) tuning[i] == standardTuning[i]].every((x) => x);

  /// Beats per minute at 100% speed.
  final double tempo;
  final int beatsPerBar;

  /// Open-string MIDI pitches, index 0 = string 1 (thin) ... 5 = string 6.
  final List<int> tuning;
  final int capo;
  final List<NoteEvent> full;
  final List<ChordEvent> easy;
  final String source;
  final double totalBeats;

  String get id => info.id;
  bool get hasEasy => easy.isNotEmpty;
  bool get hasFull => full.isNotEmpty;

  /// MIDI pitch of [fret] on [string] (1-6), including the capo.
  int pitch(int string, int fret) => tuning[string - 1] + capo + fret;

  static double _totalBeats(List<NoteEvent> full, List<ChordEvent> easy, int bpb) {
    var end = 0.0;
    for (final e in full) {
      if (e.beat + e.length > end) end = e.beat + e.length;
    }
    for (final e in easy) {
      if (e.beat + e.length > end) end = e.beat + e.length;
    }
    return end;
  }

  factory Song.fromJson(Map<String, dynamic> j) {
    final tracks = (j['tracks'] as Map?)?.cast<String, dynamic>() ?? const {};
    // The file lists tuning low to high (string 6 first), like a chord chart.
    final tuningNames = ((j['tuning'] as List?) ?? const ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']).cast<String>();
    final tuning = tuningNames.map(parsePitch).toList().reversed.toList();
    final ts = (j['timeSignature'] as List?)?.cast<int>() ?? const [4, 4];
    final full = ((tracks['full'] as List?) ?? const [])
        .map((e) => NoteEvent.fromJson((e as Map).cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => a.beat.compareTo(b.beat));
    final easy = ((tracks['easy'] as List?) ?? const [])
        .map((e) => ChordEvent.fromJson((e as Map).cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => a.beat.compareTo(b.beat));
    final parts = <SongPart>[];
    for (final p in (j['parts'] as List?) ?? const []) {
      final m = (p as Map).cast<String, dynamic>();
      final partTuning = ((m['tuning'] as List?) ?? const []).cast<String>().map(parsePitch).toList().reversed.toList();
      parts.add(SongPart(
        name: (m['name'] as String?) ?? 'Part ${parts.length + 1}',
        tuning: partTuning.length == 6 ? partTuning : standardTuning,
        capo: (m['capo'] as int?) ?? 0,
        notes: ((m['notes'] as List?) ?? const [])
            .map((e) => NoteEvent.fromJson((e as Map).cast<String, dynamic>()))
            .toList()
          ..sort((a, b) => a.beat.compareTo(b.beat)),
      ));
    }
    return Song(
      info: SongInfo.fromJson(j),
      tempo: (j['tempo'] as num?)?.toDouble() ?? 100,
      beatsPerBar: (j['beatsPerBar'] as int?) ?? ts.first,
      tuning: tuning.length == 6 ? tuning : standardTuning,
      capo: (j['capo'] as int?) ?? 0,
      full: full,
      easy: easy,
      source: (j['source'] as String?) ?? '',
      parts: parts.length > 1 ? parts : const [],
    );
  }
}
