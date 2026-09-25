/// Where to put the fingers for a chord.
class ChordShape {
  const ChordShape({required this.name, required this.frets, required this.fingers});

  final String name;

  /// Fret per string, index 0 = string 1 (thin) ... 5 = string 6 (thick).
  /// -1 means the string is not played.
  final List<int> frets;

  /// Finger per string in the same order; 0 = open or not played.
  final List<int> fingers;

  bool plays(int string) => frets[string - 1] >= 0;
  int fretOn(int string) => frets[string - 1];
  int fingerOn(int string) => fingers[string - 1];

  /// Strings played by this chord, from the thick string to the thin one.
  List<int> get playedStrings => [for (var s = 6; s >= 1; s--) if (plays(s)) s];
}

class ChordLibrary {
  ChordLibrary(this.chords);

  final Map<String, ChordShape> chords;

  ChordShape? operator [](String name) => chords[name];

  List<String> get names => chords.keys.toList();

  /// Parses songs/chords.json, where lists run from string 6 to string 1.
  factory ChordLibrary.fromJson(Map<String, dynamic> j) {
    final raw = (j['chords'] as Map).cast<String, dynamic>();
    return ChordLibrary({
      for (final e in raw.entries)
        e.key: ChordShape(
          name: e.key,
          frets: ((e.value as Map)['frets'] as List).cast<int>().reversed.toList(),
          fingers: ((e.value as Map)['fingers'] as List).cast<int>().reversed.toList(),
        ),
    });
  }

  void addAll(ChordLibrary other) => chords.addAll(other.chords);
}
