import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_learn/data/search.dart';
import 'package:guitar_learn/l10n/strings.dart';
import 'package:guitar_learn/music/pitch.dart';

void main() {
  test('parses note names', () {
    expect(parsePitch('E2'), 40);
    expect(parsePitch('A4'), 69);
    expect(parsePitch('F#3'), 54);
    expect(parsePitch('Bb3'), 58);
  });

  test('note names use H in Serbian', () {
    expect(noteName(59), 'B');
    expect(noteName(59, serbian: true), 'H');
    expect(noteName(64), 'E');
  });

  test('converts Serbian Latin to Cyrillic', () {
    expect(toCyrillic('Ljubav i Njegoš'), 'Љубав и Његош');
    expect(toCyrillic('Džak'), 'Џак');
    expect(toCyrillic('Tiha noć'), 'Тиха ноћ');
    expect(toCyrillic('Gitara 3-2-1'), 'Гитара 3-2-1');
  });

  test('search ignores script, case and accents', () {
    expect(normalizeForSearch('Тиха ноћ'), 'tiha noc');
    expect(normalizeForSearch('Tiha NOĆ!'), 'tiha noc');
    expect(normalizeForSearch('Für Elise'), 'fur elise');
  });

  test('every UI text exists in both languages', () {
    for (final lang in AppLanguage.values) {
      final s = Strings(lang);
      expect(s.appTitle, isNotEmpty);
      expect(s.newSongs(3), contains('3'));
      expect(s.fingers, isNotEmpty);
    }
  });
}
