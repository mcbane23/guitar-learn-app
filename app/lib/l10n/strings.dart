import 'package:flutter/widgets.dart';

/// UI languages. Serbian is written in Latin script by default, with Cyrillic
/// available in settings (generated from the Latin text).
enum AppLanguage { en, srLatn, srCyrl }

extension AppLanguageX on AppLanguage {
  Locale get locale => switch (this) {
        AppLanguage.en => const Locale('en'),
        AppLanguage.srLatn => const Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn'),
        AppLanguage.srCyrl => const Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Cyrl'),
      };

  /// Language code used for song titles.
  String get songLang => this == AppLanguage.en ? 'en' : 'sr';

  bool get isSerbian => this != AppLanguage.en;
}

/// All text shown in the app.
class Strings {
  Strings(this.language);

  final AppLanguage language;

  static Strings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StringsScope>()!.strings;

  String _t(String key, [Map<String, String> vars = const {}]) {
    var text = language == AppLanguage.en ? _en[key]! : _sr[key]!;
    vars.forEach((k, v) => text = text.replaceAll('{$k}', v));
    return language == AppLanguage.srCyrl ? toCyrillic(text) : text;
  }

  /// Text that comes from song data (titles) in the chosen script.
  String script(String text) => language == AppLanguage.srCyrl ? toCyrillic(text) : text;

  String get appTitle => _t('appTitle');
  String get searchHint => _t('searchHint');
  String get all => _t('all');
  String get easy => _t('easy');
  String get medium => _t('medium');
  String get hard => _t('hard');
  String get beginner => _t('beginner');
  String get kids => _t('kids');
  String get serbianFolk => _t('serbianFolk');
  String get classical => _t('classical');
  String get folk => _t('folk');
  String get holidays => _t('holidays');
  String get allSongs => _t('allSongs');
  String get comingSoon => _t('comingSoon');
  String get noResults => _t('noResults');
  String get chords => _t('chords');
  String get freePlay => _t('freePlay');
  String get freePlayHint => _t('freePlayHint');
  String get settings => _t('settings');
  String get play => _t('play');
  String get pause => _t('pause');
  String get restart => _t('restart');
  String get loop => _t('loop');
  String get waitMode => _t('waitMode');
  String get next => _t('next');
  String get speed => _t('speed');
  String get soundSong => _t('soundSong');
  String get soundAccompany => _t('soundAccompany');
  String get soundMute => _t('soundMute');
  String get metronome => _t('metronome');
  String get easyMode => _t('easyMode');
  String get fullMode => _t('fullMode');
  String get getReady => _t('getReady');
  String get wellDone => _t('wellDone');
  String get playAgain => _t('playAgain');
  String get language_ => _t('language');
  String get languageSystem => _t('languageSystem');
  String get english => 'English';
  String get serbianLatin => 'Srpski (latinica)';
  String get serbianCyrillic => 'Српски (ћирилица)';
  String get leftHanded => _t('leftHanded');
  String get leftHandedHint => _t('leftHandedHint');
  String get thinStringTop => _t('thinStringTop');
  String get thinStringTopHint => _t('thinStringTopHint');
  String get showNoteNames => _t('showNoteNames');
  String get showChordName => _t('showChordName');
  String get colors => _t('colors');
  String get colorsBright => _t('colorsBright');
  String get colorsHighContrast => _t('colorsHighContrast');
  String get defaultSpeed => _t('defaultSpeed');
  String get volume => _t('volume');
  String get countIn => _t('countIn');
  String get onlineSongs => _t('onlineSongs');
  String get updateSongs => _t('updateSongs');
  String get updating => _t('updating');
  String get offline => _t('offline');
  String get songsUpToDate => _t('songsUpToDate');
  String newSongs(int n) => _t('newSongs', {'n': '$n'});
  String get privacy => _t('privacy');
  String get about => _t('about');
  String get tapChord => _t('tapChord');
  String get fingers => _t('fingers');
  String get songNotFound => _t('songNotFound');
  String get back => _t('back');

  String difficulty(String name) => switch (name) {
        'medium' => medium,
        'hard' => hard,
        _ => easy,
      };

  String tag(String name) => switch (name) {
        'kids' => kids,
        'beginner' => beginner,
        'classical' => classical,
        'folk' => folk,
        'holidays' => holidays,
        'serbian-folk' => serbianFolk,
        _ => name,
      };

  static const _en = {
    'appTitle': 'Guitar Learn',
    'searchHint': 'Search songs',
    'all': 'All',
    'easy': 'Easy',
    'medium': 'Medium',
    'hard': 'Hard',
    'beginner': 'Beginner',
    'kids': 'Kids',
    'serbianFolk': 'Serbian folk',
    'classical': 'Classical',
    'folk': 'Folk',
    'holidays': 'Holidays',
    'allSongs': 'All songs',
    'comingSoon': 'Coming soon',
    'noResults': 'No songs found',
    'chords': 'Chords',
    'freePlay': 'Free play',
    'freePlayHint': 'Tap anywhere on the neck to hear that note',
    'settings': 'Settings',
    'play': 'Play',
    'pause': 'Pause',
    'restart': 'Start over',
    'loop': 'Repeat part',
    'waitMode': 'Wait for me',
    'next': 'Next',
    'speed': 'Speed',
    'soundSong': 'Play song',
    'soundAccompany': 'Accompany me',
    'soundMute': 'Sound off',
    'metronome': 'Click',
    'easyMode': 'Easy: chords',
    'fullMode': 'Full: every note',
    'getReady': 'Get ready',
    'wellDone': 'Well done!',
    'playAgain': 'Play again',
    'language': 'Language',
    'languageSystem': 'Same as phone',
    'leftHanded': 'Left-handed',
    'leftHandedHint': 'Mirror the neck for left-handed players',
    'thinStringTop': 'Thin string on top',
    'thinStringTopHint': 'Like written tabs. Turn off to see the guitar as you look down at it.',
    'showNoteNames': 'Show note names',
    'showChordName': 'Show chord name',
    'colors': 'Colors',
    'colorsBright': 'Bright',
    'colorsHighContrast': 'High contrast',
    'defaultSpeed': 'Starting speed',
    'volume': 'Volume',
    'countIn': 'Count 3-2-1 before playing',
    'onlineSongs': 'Online songs',
    'updateSongs': 'Get new songs',
    'updating': 'Looking for new songs...',
    'offline': 'No Internet. Songs on this device still work.',
    'songsUpToDate': 'You have all the songs',
    'newSongs': '{n} new songs added',
    'privacy': 'This app collects no personal data. No accounts, no ads.',
    'about': 'About',
    'tapChord': 'Pick a chord to see and hear it',
    'fingers': 'Fingers: 1 index, 2 middle, 3 ring, 4 little',
    'songNotFound': 'This song could not be opened',
    'back': 'Back',
  };

  static const _sr = {
    'appTitle': 'Gitara',
    'searchHint': 'Traži pesme',
    'all': 'Sve',
    'easy': 'Lako',
    'medium': 'Srednje',
    'hard': 'Teško',
    'beginner': 'Za početnike',
    'kids': 'Za decu',
    'serbianFolk': 'Srpske narodne',
    'classical': 'Klasika',
    'folk': 'Narodne',
    'holidays': 'Praznici',
    'allSongs': 'Sve pesme',
    'comingSoon': 'Uskoro',
    'noResults': 'Nema pesama',
    'chords': 'Akordi',
    'freePlay': 'Slobodno sviranje',
    'freePlayHint': 'Dodirni vrat gitare da čuješ taj ton',
    'settings': 'Podešavanja',
    'play': 'Sviraj',
    'pause': 'Pauza',
    'restart': 'Ispočetka',
    'loop': 'Ponavljaj deo',
    'waitMode': 'Čekaj me',
    'next': 'Dalje',
    'speed': 'Brzina',
    'soundSong': 'Sviraj pesmu',
    'soundAccompany': 'Prati me',
    'soundMute': 'Bez zvuka',
    'metronome': 'Takt',
    'easyMode': 'Lako: akordi',
    'fullMode': 'Sve: svaki ton',
    'getReady': 'Spremi se',
    'wellDone': 'Bravo!',
    'playAgain': 'Sviraj ponovo',
    'language': 'Jezik',
    'languageSystem': 'Kao na telefonu',
    'leftHanded': 'Levoruki',
    'leftHandedHint': 'Obrni vrat gitare za levoruke',
    'thinStringTop': 'Tanka žica gore',
    'thinStringTopHint': 'Kao u tabulaturama. Isključi da vidiš gitaru kao kad gledaš odozgo.',
    'showNoteNames': 'Prikaži imena tonova',
    'showChordName': 'Prikaži ime akorda',
    'colors': 'Boje',
    'colorsBright': 'Vesele',
    'colorsHighContrast': 'Jak kontrast',
    'defaultSpeed': 'Početna brzina',
    'volume': 'Jačina zvuka',
    'countIn': 'Odbrojavanje 3-2-1 pre sviranja',
    'onlineSongs': 'Pesme sa interneta',
    'updateSongs': 'Preuzmi nove pesme',
    'updating': 'Tražim nove pesme...',
    'offline': 'Nema interneta. Pesme na uređaju i dalje rade.',
    'songsUpToDate': 'Imaš sve pesme',
    'newSongs': 'Dodato novih pesama: {n}',
    'privacy': 'Aplikacija ne prikuplja lične podatke. Bez naloga, bez reklama.',
    'about': 'O aplikaciji',
    'tapChord': 'Izaberi akord da ga vidiš i čuješ',
    'fingers': 'Prsti: 1 kažiprst, 2 srednji, 3 domali, 4 mali',
    'songNotFound': 'Ova pesma ne može da se otvori',
    'back': 'Nazad',
  };
}

class StringsScope extends InheritedWidget {
  const StringsScope({super.key, required this.strings, required super.child});

  final Strings strings;

  @override
  bool updateShouldNotify(StringsScope oldWidget) => oldWidget.strings.language != strings.language;
}

const _cyr = {
  'a': 'а', 'b': 'б', 'c': 'ц', 'č': 'ч', 'ć': 'ћ', 'd': 'д', 'đ': 'ђ', 'e': 'е',
  'f': 'ф', 'g': 'г', 'h': 'х', 'i': 'и', 'j': 'ј', 'k': 'к', 'l': 'л', 'm': 'м',
  'n': 'н', 'o': 'о', 'p': 'п', 'r': 'р', 's': 'с', 'š': 'ш', 't': 'т', 'u': 'у',
  'v': 'в', 'z': 'з', 'ž': 'ж',
  // Letters not in Serbian Latin, for foreign names in song titles.
  'q': 'к', 'w': 'в', 'x': 'кс', 'y': 'ј',
};
const _cyrDigraphs = {'lj': 'љ', 'nj': 'њ', 'dž': 'џ'};

/// Converts Serbian Latin script to Cyrillic (e.g. "Ljubav" -> "Љубав").
String toCyrillic(String latin) {
  final out = StringBuffer();
  var i = 0;
  while (i < latin.length) {
    if (i + 1 < latin.length) {
      final pair = latin.substring(i, i + 2);
      final d = _cyrDigraphs[pair.toLowerCase()];
      if (d != null) {
        out.write(pair[0] == pair[0].toUpperCase() ? d.toUpperCase() : d);
        i += 2;
        continue;
      }
    }
    final ch = latin[i];
    final lower = ch.toLowerCase();
    final c = _cyr[lower];
    if (c == null) {
      out.write(ch);
    } else {
      out.write(ch == lower ? c : c.toUpperCase());
    }
    i++;
  }
  return out.toString();
}
