import '../models/song.dart';

const _cyrToLat = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'ђ': 'dj', 'е': 'e', 'ж': 'z',
  'з': 'z', 'и': 'i', 'ј': 'j', 'к': 'k', 'л': 'l', 'љ': 'lj', 'м': 'm', 'н': 'n',
  'њ': 'nj', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'ћ': 'c', 'у': 'u',
  'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'c', 'џ': 'dz', 'ш': 's',
};
const _latFold = {
  'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'đ': 'dj', 'é': 'e', 'è': 'e', 'ê': 'e',
  'ü': 'u', 'ö': 'o', 'ä': 'a', 'à': 'a', 'á': 'a', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'ç': 'c',
};

/// Lower case, Cyrillic to Latin, no accents, so "Tiha noć", "tiha noc" and
/// "Тиха ноћ" all match each other.
String normalizeForSearch(String text) {
  final out = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    out.write(_cyrToLat[ch] ?? _latFold[ch] ?? ch);
  }
  return out.toString().replaceAll(RegExp(r"[^a-z0-9 ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Songs whose title (in any language) or artist contains every word of [query].
List<SongInfo> searchSongs(List<SongInfo> songs, String query, {Difficulty? difficulty}) {
  final words = normalizeForSearch(query).split(' ').where((w) => w.isNotEmpty).toList();
  return [
    for (final s in songs)
      if ((difficulty == null || s.difficulty == difficulty) && _matches(s, words)) s,
  ];
}

bool _matches(SongInfo s, List<String> words) {
  if (words.isEmpty) return true;
  final hay = normalizeForSearch([...s.title.values, s.artist, ...s.tags].join(' '));
  return words.every(hay.contains);
}
