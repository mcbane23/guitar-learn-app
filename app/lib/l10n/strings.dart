import 'package:flutter/widgets.dart';

import '../import/score.dart' show ImportError;
import '../models/song.dart' show SongInfo;

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

  /// A song's title in the app language. Only a Serbian title is written in
  /// Cyrillic: an English title, or one that came from a file, stays as it
  /// is instead of being spelled out letter by letter.
  String songTitle(SongInfo song) {
    final sr = song.title['sr'];
    if (language.isSerbian && sr != null) return script(sr);
    return song.titleFor(language.songLang);
  }

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
  String get slower => _t('slower');
  String get faster => _t('faster');
  String get more => _t('more');
  String get speed => _t('speed');
  String get soundSong => _t('soundSong');
  String get soundAccompany => _t('soundAccompany');
  String get soundMute => _t('soundMute');
  String get metronome => _t('metronome');
  String get easyMode => _t('easyMode');
  String get fullMode => _t('fullMode');
  String get easyModeShort => _t('easyModeShort');
  String get fullModeShort => _t('fullModeShort');
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
  String get dotLabel => _t('dotLabel');
  String get dotLabelFinger => _t('dotLabelFinger');
  String get dotLabelFingerHint => _t('dotLabelFingerHint');
  String get dotLabelFret => _t('dotLabelFret');
  String get dotLabelFretHint => _t('dotLabelFretHint');
  String get back1Bar => _t('back1Bar');
  String get secondPart => _t('secondPart');
  String get none => _t('none');
  String get forward1Bar => _t('forward1Bar');
  String get showChordName => _t('showChordName');
  String get colors => _t('colors');
  String get colorsBright => _t('colorsBright');
  String get colorsHighContrast => _t('colorsHighContrast');
  String get theme => _t('theme');
  String themeName(String name) => _t('theme_$name');
  String get defaultSpeed => _t('defaultSpeed');
  String get volume => _t('volume');
  String get countIn => _t('countIn');
  String get onlineSongs => _t('onlineSongs');
  String get updateSongs => _t('updateSongs');
  String get updating => _t('updating');
  String get offline => _t('offline');
  String get songsUpToDate => _t('songsUpToDate');
  String newSongs(int n) => _t('newSongs', {'n': '$n'});
  String get songSources => _t('songSources');
  String get songSourcesHint => _t('songSourcesHint');
  String get addSongSource => _t('addSongSource');
  String get songSourceLink => _t('songSourceLink');
  String get removeSongSource => _t('removeSongSource');
  String get cancel => _t('cancel');
  String get add => _t('add');
  String get checking => _t('checking');
  String songSourceAdded(int n) => _t('songSourceAdded', {'n': '$n'});
  String get songSourceNotFound => _t('songSourceNotFound');
  String get privacy => _t('privacy');
  String get about => _t('about');
  String get appUpdate => _t('appUpdate');
  String get checkForUpdate => _t('checkForUpdate');
  String get checkingForUpdate => _t('checkingForUpdate');
  String get appUpToDate => _t('appUpToDate');
  String get updateCheckFailed => _t('updateCheckFailed');
  String updateAvailable(int build) => _t('updateAvailable', {'n': '$build'});
  String get updateHint => _t('updateHint');
  String get updateNow => _t('updateNow');
  String get later => _t('later');
  String get downloadingUpdate => _t('downloadingUpdate');
  String get updateFailed => _t('updateFailed');
  String currentBuild(int build) => _t('currentBuild', {'n': '$build'});
  String get tapChord => _t('tapChord');
  String get fingers => _t('fingers');
  String get songNotFound => _t('songNotFound');
  String get back => _t('back');
  String get mySongs => _t('mySongs');
  String get addSongs => _t('addSongs');
  String get addSongsHint => _t('addSongsHint');
  String songsAdded(int n) => n == 1 ? _t('oneSongAdded') : _t('songsAdded', {'n': '$n'});
  String filesNotRead(int n) => _t('filesNotRead', {'n': '$n'});
  String get filePickerUnavailable => _t('filePickerUnavailable');
  String get folderPickerUnavailable => _t('folderPickerUnavailable');
  String get chooseFiles => _t('chooseFiles');
  String get chooseFilesHint => _t('chooseFilesHint');
  String get chooseFolder => _t('chooseFolder');
  String get chooseFolderHint => _t('chooseFolderHint');
  String readingFilesProgress(int done, int n) => _t('readingFilesProgress', {'done': '$done', 'n': '$n'});
  String get stop => _t('stop');
  String get importDone => _t('importDone');
  String get noSongFilesInFolder => _t('noSongFilesInFolder');
  String resultAdded(int n) => _t('resultAdded', {'n': '$n'});
  String resultAlreadyAdded(int n) => _t('resultAlreadyAdded', {'n': '$n'});
  String resultFailed(int n) => _t('resultFailed', {'n': '$n'});
  String resultOtherFiles(int n) => _t('resultOtherFiles', {'n': '$n'});
  String resultTooMany(int n) => _t('resultTooMany', {'n': '$n'});
  String resultStopped(int n) => _t('resultStopped', {'n': '$n'});
  String get removeSong => _t('removeSong');
  String get removeSongConfirm => _t('removeSongConfirm');
  String get songRemoved => _t('songRemoved');
  String get part => _t('part');
  String get tuning => _t('tuning');
  String capo(int n) => _t('capo', {'n': '$n'});
  String get recentlyPlayed => _t('recentlyPlayed');
  String get fromFile => _t('fromFile');
  String get songFiles => _t('songFiles');
  String get songFilesHint => _t('songFilesHint');
  String get ok => _t('ok');
  String loopBars(int n) => _t('loopBars', {'n': '$n'});
  String get receiveSongs => _t('receiveSongs');
  String get receiveSongsHint => _t('receiveSongsHint');
  String get sendToTv => _t('sendToTv');
  String get sendToTvHint => _t('sendToTvHint');
  String get receiveStep1 => _t('receiveStep1');
  String get receiveStep2 => _t('receiveStep2');
  String get receiveStep3 => _t('receiveStep3');
  String get receiveNoNetwork => _t('receiveNoNetwork');
  String get receiveFailed => _t('receiveFailed');
  String get receivedFiles => _t('receivedFiles');
  String get waitingForPhone => _t('waitingForPhone');
  String get receiving => _t('receiving');
  String get done => _t('done');
  String get searchingDevices => _t('searchingDevices');
  String get noDevicesFound => _t('noDevicesFound');
  String get devicesFound => _t('devicesFound');
  String get searchAgain => _t('searchAgain');
  String get enterAddress => _t('enterAddress');
  String get invalidAddress => _t('invalidAddress');
  String get connect => _t('connect');
  String get whatToSend => _t('whatToSend');
  String sendMySongs(int n) => _t('sendMySongs', {'n': '$n'});
  String get sendMySongsHint => _t('sendMySongsHint');
  String get sendFiles => _t('sendFiles');
  String get sendFilesHint => _t('sendFilesHint');
  String get noMySongs => _t('noMySongs');
  String sendingProgress(int done, int n) => _t('sendingProgress', {'done': '$done', 'n': '$n'});
  String get sendDone => _t('sendDone');
  String resultSent(int n) => _t('resultSent', {'n': '$n'});
  String resultAlreadyOnTv(int n) => _t('resultAlreadyOnTv', {'n': '$n'});
  String get deviceUnreachable => _t('deviceUnreachable');
  String get sendMore => _t('sendMore');
  String get sendingTo => _t('sendingTo');

  /// Why a song file could not be opened.
  String fileError(ImportError? code) => switch (code) {
        ImportError.unsupported => _t('fileUnsupported'),
        ImportError.empty => _t('fileEmpty'),
        ImportError.tooLarge => _t('fileTooLarge'),
        ImportError.noNotes => _t('fileNoNotes'),
        _ => _t('fileDamaged'),
      };

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
    'freePlayHint': 'Tap the neck, or move with the remote arrows and press OK, to hear a note',
    'settings': 'Settings',
    'play': 'Play',
    'pause': 'Pause',
    'restart': 'Start over',
    'loop': 'Repeat part',
    'waitMode': 'Wait for me',
    'next': 'Next',
    'slower': 'Slower',
    'faster': 'Faster',
    'more': 'More',
    'speed': 'Speed',
    'soundSong': 'Play song',
    'soundAccompany': 'Accompany me',
    'soundMute': 'Sound off',
    'metronome': 'Click',
    'easyMode': 'Easy: chords',
    'fullMode': 'Full: every note',
    'easyModeShort': 'Chords',
    'fullModeShort': 'Notes',
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
    'dotLabel': 'Number in the circles',
    'dotLabelFinger': 'Finger number',
    'dotLabelFingerHint': '1 index, 2 middle, 3 ring, 4 pinky',
    'dotLabelFret': 'Fret number',
    'dotLabelFretHint': 'The same number that is written under the neck',
    'back1Bar': 'Bar back',
    'secondPart': 'Second instrument underneath',
    'none': 'None',
    'forward1Bar': 'Bar forward',
    'showChordName': 'Show chord name',
    'colors': 'Colors',
    'colorsBright': 'Bright',
    'colorsHighContrast': 'High contrast',
    'theme': 'Theme',
    'theme_classic': 'Classic',
    'theme_frost': 'Frost',
    'theme_forest': 'Forest',
    'theme_plum': 'Plum',
    'defaultSpeed': 'Starting speed',
    'volume': 'Volume',
    'countIn': 'Count 3-2-1 before playing',
    'onlineSongs': 'Online songs',
    'updateSongs': 'Get new songs',
    'updating': 'Looking for new songs...',
    'offline': 'No Internet. Songs on this device still work.',
    'songsUpToDate': 'You have all the songs',
    'newSongs': '{n} new songs added',
    'songSources': 'Song sources',
    'songSourcesHint': 'Songs come from the Guitar Learn song list. Add other song lists by their link.',
    'addSongSource': 'Add a song source',
    'songSourceLink': 'Link to a song list (GitHub repository or web address)',
    'removeSongSource': 'Remove',
    'cancel': 'Cancel',
    'add': 'Add',
    'checking': 'Checking...',
    'songSourceAdded': 'Song source added ({n} songs)',
    'songSourceNotFound': 'No song list found at this link',
    'privacy': 'This app collects no personal data. No accounts, no ads.',
    'about': 'About',
    'appUpdate': 'App update',
    'checkForUpdate': 'Check for a new version',
    'checkingForUpdate': 'Checking...',
    'appUpToDate': 'You have the newest version',
    'updateCheckFailed': 'Could not check. Is the Internet on?',
    'updateAvailable': 'New version available (build {n})',
    'updateHint': 'The new version downloads and Android asks you to install it. Your songs and settings stay.',
    'updateNow': 'Update',
    'later': 'Later',
    'downloadingUpdate': 'Downloading the new version...',
    'updateFailed': 'The update could not be installed. Try again later.',
    'currentBuild': 'Installed version: build {n}',
    'tapChord': 'Pick a chord to see and hear it',
    'fingers': 'Fingers: 1 index, 2 middle, 3 ring, 4 little',
    'songNotFound': 'This song could not be opened',
    'back': 'Back',
    'mySongs': 'My songs',
    'addSongs': 'Add songs',
    'addSongsHint': 'Open your own tabs from this device: Guitar Pro, MIDI, MusicXML or text tabs. You can pick several files at once or a whole folder.',
    'oneSongAdded': '1 song added',
    'songsAdded': '{n} songs added',
    'filesNotRead': '{n} files could not be read',
    'filePickerUnavailable': 'Choosing files is not possible on this device',
    'folderPickerUnavailable': 'Choosing a folder is not possible on this device',
    'chooseFiles': 'Choose files',
    'chooseFilesHint': 'One song file or several at once',
    'chooseFolder': 'Choose a folder',
    'chooseFolderHint': 'Every song file in a folder and its subfolders',
    'readingFilesProgress': 'Reading files: {done} of {n}',
    'stop': 'Stop',
    'importDone': 'Songs added',
    'noSongFilesInFolder': 'No song files in this folder',
    'resultAdded': 'New songs in My songs: {n}',
    'resultAlreadyAdded': 'Already in My songs: {n}',
    'resultFailed': 'Files that could not be read: {n}',
    'resultOtherFiles': 'Other files left out (not songs): {n}',
    'resultTooMany': 'Only the first {n} song files were read',
    'resultStopped': 'Stopped: {n} files were not read',
    'removeSong': 'Remove from my songs',
    'removeSongConfirm': 'Remove this song from the device?',
    'songRemoved': 'Song removed',
    'part': 'Part',
    'tuning': 'Tuning',
    'capo': 'Capo {n}',
    'recentlyPlayed': 'Recently played',
    'receiveSongs': 'Send songs from a phone',
    'receiveSongsHint': 'Shows a QR code. The phone sends song files from its browser or from the Guitar Learn app.',
    'sendToTv': 'Send to a TV',
    'sendToTvHint': 'Send songs from this device to a TV or another device on the same Wi-Fi.',
    'receiveStep1': 'Connect the phone to the same Wi-Fi network as this device.',
    'receiveStep2': 'Scan the QR code with the phone camera, or type this address in its browser:',
    'receiveStep3': 'Or, in the Guitar Learn app on the phone: Add songs, then Send to a TV.',
    'receiveNoNetwork': 'This device is not connected to a Wi-Fi network.',
    'receiveFailed': 'Receiving songs could not start on this device.',
    'receivedFiles': 'Received files',
    'waitingForPhone': 'Waiting for the phone...',
    'receiving': 'Receiving...',
    'done': 'Done',
    'searchingDevices': 'Looking for a TV on the network...',
    'noDevicesFound': 'No TV found. On the TV open Add songs, then Send songs from a phone, and search again. You can also type the address from the TV screen.',
    'devicesFound': 'Send to',
    'searchAgain': 'Search again',
    'enterAddress': 'Address from the TV screen',
    'invalidAddress': 'This is not the address from the TV screen',
    'connect': 'Connect',
    'whatToSend': 'What to send',
    'sendMySongs': 'My songs ({n})',
    'sendMySongsHint': 'Every song you added from files on this device',
    'sendFiles': 'Files from this device',
    'sendFilesHint': 'Choose song files to send',
    'noMySongs': 'There are no songs in My songs yet.',
    'sendingProgress': 'Sending: {done} of {n}',
    'sendDone': 'Sent',
    'resultSent': 'Added on the other device: {n}',
    'resultAlreadyOnTv': 'Already on the other device: {n}',
    'deviceUnreachable': 'The TV did not answer. Is its screen with the QR code still open?',
    'sendMore': 'Send more',
    'sendingTo': 'Sending to',
    'fromFile': 'From a file',
    'songFiles': 'Song files',
    'songFilesHint':
        'Supported files: Guitar Pro (gp3, gp4, gp5, gpx, gp), MIDI (mid, midi), MusicXML (musicxml, mxl, xml) and text tabs (txt, tab). Songs you add stay on this device.',
    'ok': 'OK',
    'loopBars': 'Repeat {n} bars',
    'fileUnsupported': 'This kind of file is not supported',
    'fileEmpty': 'The file is empty',
    'fileTooLarge': 'The file is too large',
    'fileNoNotes': 'No notes to play were found in the file',
    'fileDamaged': 'The file could not be read',
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
    'freePlayHint': 'Dodirni vrat gitare, ili se pomeraj strelicama na daljinskom i pritisni OK, da čuješ ton',
    'settings': 'Podešavanja',
    'play': 'Sviraj',
    'pause': 'Pauza',
    'restart': 'Ispočetka',
    'loop': 'Ponavljaj deo',
    'waitMode': 'Čekaj me',
    'next': 'Dalje',
    'slower': 'Sporije',
    'faster': 'Brže',
    'more': 'Više',
    'speed': 'Brzina',
    'soundSong': 'Sviraj pesmu',
    'soundAccompany': 'Prati me',
    'soundMute': 'Bez zvuka',
    'metronome': 'Takt',
    'easyMode': 'Lako: akordi',
    'fullMode': 'Sve: svaki ton',
    'easyModeShort': 'Akordi',
    'fullModeShort': 'Tonovi',
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
    'dotLabel': 'Broj u kružićima',
    'dotLabelFinger': 'Broj prsta',
    'dotLabelFingerHint': '1 kažiprst, 2 srednji, 3 domali, 4 mali',
    'dotLabelFret': 'Broj praga',
    'dotLabelFretHint': 'Isti broj koji piše ispod vrata gitare',
    'back1Bar': 'Takt nazad',
    'secondPart': 'Drugi instrument ispod',
    'none': 'Nijedan',
    'forward1Bar': 'Takt napred',
    'showChordName': 'Prikaži ime akorda',
    'colors': 'Boje',
    'colorsBright': 'Vesele',
    'colorsHighContrast': 'Jak kontrast',
    'theme': 'Tema',
    'theme_classic': 'Klasična',
    'theme_frost': 'Mraz',
    'theme_forest': 'Šuma',
    'theme_plum': 'Šljiva',
    'defaultSpeed': 'Početna brzina',
    'volume': 'Jačina zvuka',
    'countIn': 'Odbrojavanje 3-2-1 pre sviranja',
    'onlineSongs': 'Pesme sa interneta',
    'updateSongs': 'Preuzmi nove pesme',
    'updating': 'Tražim nove pesme...',
    'offline': 'Nema interneta. Pesme na uređaju i dalje rade.',
    'songsUpToDate': 'Imaš sve pesme',
    'newSongs': 'Dodato novih pesama: {n}',
    'songSources': 'Izvori pesama',
    'songSourcesHint': 'Pesme stižu sa spiska pesama aplikacije. Dodaj druge spiskove pomoću linka.',
    'addSongSource': 'Dodaj izvor pesama',
    'songSourceLink': 'Link do spiska pesama (GitHub repozitorijum ili veb adresa)',
    'removeSongSource': 'Ukloni',
    'cancel': 'Otkaži',
    'add': 'Dodaj',
    'checking': 'Proveravam...',
    'songSourceAdded': 'Izvor pesama je dodat (pesama: {n})',
    'songSourceNotFound': 'Na ovom linku nema spiska pesama',
    'privacy': 'Aplikacija ne prikuplja lične podatke. Bez naloga, bez reklama.',
    'about': 'O aplikaciji',
    'appUpdate': 'Ažuriranje aplikacije',
    'checkForUpdate': 'Proveri da li ima nova verzija',
    'checkingForUpdate': 'Proveravam...',
    'appUpToDate': 'Imaš najnoviju verziju',
    'updateCheckFailed': 'Provera nije uspela. Da li ima interneta?',
    'updateAvailable': 'Dostupna je nova verzija (build {n})',
    'updateHint': 'Nova verzija se preuzima, a Android te pita da je instaliraš. Pesme i podešavanja ostaju.',
    'updateNow': 'Ažuriraj',
    'later': 'Kasnije',
    'downloadingUpdate': 'Preuzimam novu verziju...',
    'updateFailed': 'Ažuriranje nije uspelo. Probaj kasnije.',
    'currentBuild': 'Instalirana verzija: build {n}',
    'tapChord': 'Izaberi akord da ga vidiš i čuješ',
    'fingers': 'Prsti: 1 kažiprst, 2 srednji, 3 domali, 4 mali',
    'songNotFound': 'Ova pesma ne može da se otvori',
    'back': 'Nazad',
    'mySongs': 'Moje pesme',
    'addSongs': 'Dodaj pesme',
    'addSongsHint': 'Otvori svoje tabulature sa ovog uređaja: Guitar Pro, MIDI, MusicXML ili tekst. Možeš izabrati više fajlova odjednom ili ceo folder.',
    'oneSongAdded': 'Dodata je 1 pesma',
    'songsAdded': 'Dodato pesama: {n}',
    'filesNotRead': 'Fajlova koji nisu mogli da se pročitaju: {n}',
    'filePickerUnavailable': 'Na ovom uređaju nije moguće izabrati fajlove',
    'folderPickerUnavailable': 'Na ovom uređaju nije moguće izabrati folder',
    'chooseFiles': 'Izaberi fajlove',
    'chooseFilesHint': 'Jedan fajl sa pesmom ili više njih odjednom',
    'chooseFolder': 'Izaberi folder',
    'chooseFolderHint': 'Sve pesme iz foldera i njegovih podfoldera',
    'readingFilesProgress': 'Čitam fajlove: {done} od {n}',
    'stop': 'Zaustavi',
    'importDone': 'Pesme su dodate',
    'noSongFilesInFolder': 'U ovom folderu nema fajlova sa pesmama',
    'resultAdded': 'Novih pesama u mojim pesmama: {n}',
    'resultAlreadyAdded': 'Već su u mojim pesmama: {n}',
    'resultFailed': 'Fajlova koji nisu mogli da se pročitaju: {n}',
    'resultOtherFiles': 'Preskočeni drugi fajlovi (nisu pesme): {n}',
    'resultTooMany': 'Pročitano je samo prvih {n} fajlova sa pesmama',
    'resultStopped': 'Zaustavljeno: {n} fajlova nije pročitano',
    'removeSong': 'Ukloni iz mojih pesama',
    'removeSongConfirm': 'Ukloniti ovu pesmu sa uređaja?',
    'songRemoved': 'Pesma je uklonjena',
    'part': 'Deonica',
    'tuning': 'Štim',
    'capo': 'Kapodaster {n}',
    'recentlyPlayed': 'Nedavno svirano',
    'receiveSongs': 'Pošalji pesme sa telefona',
    'receiveSongsHint': 'Pokazuje QR kod. Telefon šalje fajlove sa pesmama iz pretraživača ili iz aplikacije Guitar Learn.',
    'sendToTv': 'Pošalji na TV',
    'sendToTvHint': 'Pošalji pesme sa ovog uređaja na TV ili drugi uređaj na istoj Wi-Fi mreži.',
    'receiveStep1': 'Poveži telefon na istu Wi-Fi mrežu kao ovaj uređaj.',
    'receiveStep2': 'Skeniraj QR kod kamerom telefona ili ukucaj ovu adresu u pretraživač:',
    'receiveStep3': 'Ili u aplikaciji Guitar Learn na telefonu: Dodaj pesme, pa Pošalji na TV.',
    'receiveNoNetwork': 'Ovaj uređaj nije povezan na Wi-Fi mrežu.',
    'receiveFailed': 'Prijem pesama nije mogao da se pokrene na ovom uređaju.',
    'receivedFiles': 'Primljeni fajlovi',
    'waitingForPhone': 'Čeka se telefon...',
    'receiving': 'Prima se...',
    'done': 'Gotovo',
    'searchingDevices': 'Traži se TV na mreži...',
    'noDevicesFound': 'TV nije pronađen. Na TV-u otvori Dodaj pesme, pa Pošalji pesme sa telefona, i potraži ponovo. Možeš i da ukucaš adresu sa TV ekrana.',
    'devicesFound': 'Pošalji na',
    'searchAgain': 'Potraži ponovo',
    'enterAddress': 'Adresa sa TV ekrana',
    'invalidAddress': 'Ovo nije adresa sa TV ekrana',
    'connect': 'Poveži',
    'whatToSend': 'Šta da se pošalje',
    'sendMySongs': 'Moje pesme ({n})',
    'sendMySongsHint': 'Sve pesme koje si dodao iz fajlova na ovom uređaju',
    'sendFiles': 'Fajlovi sa ovog uređaja',
    'sendFilesHint': 'Izaberi fajlove sa pesmama za slanje',
    'noMySongs': 'U Mojim pesmama još nema pesama.',
    'sendingProgress': 'Šalje se: {done} od {n}',
    'sendDone': 'Poslato',
    'resultSent': 'Dodato na drugom uređaju: {n}',
    'resultAlreadyOnTv': 'Već postoji na drugom uređaju: {n}',
    'deviceUnreachable': 'TV ne odgovara. Da li je ekran sa QR kodom na njemu još otvoren?',
    'sendMore': 'Pošalji još',
    'sendingTo': 'Šalje se na',
    'fromFile': 'Iz fajla',
    'songFiles': 'Fajlovi pesama',
    'songFilesHint':
        'Podržani fajlovi: Guitar Pro (gp3, gp4, gp5, gpx, gp), MIDI (mid, midi), MusicXML (musicxml, mxl, xml) i tekstualne tabulature (txt, tab). Dodate pesme ostaju na ovom uređaju.',
    'ok': 'U redu',
    'loopBars': 'Ponavljaj {n} takta',
    'fileUnsupported': 'Ovaj tip fajla nije podržan',
    'fileEmpty': 'Fajl je prazan',
    'fileTooLarge': 'Fajl je prevelik',
    'fileNoNotes': 'U fajlu nema nota za sviranje',
    'fileDamaged': 'Fajl ne može da se pročita',
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
