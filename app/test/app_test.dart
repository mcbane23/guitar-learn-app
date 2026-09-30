import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_learn/app.dart';
import 'package:guitar_learn/audio/synth.dart';
import 'package:guitar_learn/data/song_repository.dart';
import 'package:guitar_learn/l10n/strings.dart';
import 'package:guitar_learn/settings/settings.dart';
import 'package:guitar_learn/ui/themes.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<SongRepository> _repo() async {
  final repo = SongRepository(
    client: MockClient((_) async => http.Response('offline', 503)),
    cacheDir: () async => null,
  );
  await repo.load();
  return repo;
}

void main() {
  testWidgets('home lists songs, search filters them, a song opens the neck', (tester) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final repo = await tester.runAsync(_repo);
    final settings = AppSettings.inMemory()..language = AppLanguage.en;
    final synth = RecordingSynth();
    await tester.pumpWidget(GuitarApp(settings: settings, songs: repo!, synth: synth));
    await tester.pump();

    expect(find.text('Guitar Learn'), findsOneWidget);
    expect(find.text('Ode to Joy'), findsWidgets);
    expect(find.text('Serbian folk'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tiha noc');
    await tester.pump();
    expect(find.text('Silent Night'), findsOneWidget);
    expect(find.text('Ode to Joy'), findsNothing);

    await tester.tap(find.text('Silent Night'));
    await _waitFor(tester, find.text('Play'));
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Easy: chords'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // count-in

    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('songs from files: added under My songs, parts, tuning, removal', (tester) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = await tester.runAsync(_repo);
    final settings = AppSettings.inMemory()..language = AppLanguage.en;
    var picks = <ImportFile>[
      ImportFile(name: 'fixture.gp5', bytes: File('test/fixtures/fixture.gp5').readAsBytesSync()),
      ImportFile(name: 'notes.pdf', bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 1, 2, 3])),
    ];
    await tester.pumpWidget(GuitarApp(
      settings: settings,
      songs: repo!,
      synth: RecordingSynth(),
      filePicker: () async => picks,
    ));
    await tester.pump();
    expect(find.text('My songs'), findsOneWidget); // the banner inviting to add files
    expect(find.text('Fixture Song'), findsNothing);

    await tester.tap(find.text('Add songs').first);
    await tester.pump();
    await _waitFor(tester, find.text('1 song added'));
    expect(find.text('notes.pdf'), findsOneWidget);
    expect(find.text('This kind of file is not supported'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fixture Song'), findsWidgets);
    expect(find.text('Tester'), findsWidgets); // the artist from the file
    expect(repo.isImported(repo.importedSongs.single.id), isTrue);

    // Open it: the part chooser shows both guitars; the rhythm guitar is in drop D with a capo.
    await tester.tap(find.text('Fixture Song').first);
    await _waitFor(tester, find.text('Play'));
    expect(find.text('Lead Guitar'), findsOneWidget);
    expect(find.textContaining('Tuning'), findsNothing);
    await tester.tap(find.text('Lead Guitar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Rhythm Guitar').last);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200)); // the menu closes
    }
    expect(find.text('Rhythm Guitar'), findsOneWidget);
    expect(find.textContaining('Tuning: D A D G B E'), findsOneWidget);
    expect(find.textContaining('Capo 2'), findsOneWidget);
    expect(settings.recentSongs, [repo.importedSongs.single.id]);

    // The loop grows from 2 bars to 4, then switches off.
    await tester.tap(find.byIcon(Icons.repeat_rounded));
    await tester.pump();
    expect(find.text('Repeat 2 bars'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.repeat_rounded));
    await tester.pump();
    expect(find.text('Repeat 4 bars'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.repeat_rounded));
    await tester.pump();
    expect(find.text('Repeat part'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Recently played'), findsOneWidget);

    // Picking nothing does nothing; holding the card removes the song.
    picks = [];
    await tester.tap(find.text('Add songs').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fixture Song'), findsWidgets);
    await tester.longPress(find.text('Fixture Song').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Remove this song from the device?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Fixture Song'), findsNothing);
    expect(repo.importedSongs, isEmpty);
  });

  testWidgets('Serbian Cyrillic UI', (tester) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = await tester.runAsync(_repo);
    final settings = AppSettings.inMemory()..language = AppLanguage.srCyrl;
    await tester.pumpWidget(GuitarApp(settings: settings, songs: repo!, synth: RecordingSynth()));
    await tester.pump();
    expect(find.text('Гитара'), findsOneWidget);
    expect(find.text('Српске народне'), findsOneWidget);
    expect(find.text('Сијај, сијај, звездице'), findsWidgets);
  });

  testWidgets('picking a theme in settings recolors the app', (tester) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = await tester.runAsync(_repo);
    final settings = AppSettings.inMemory()..language = AppLanguage.en;
    await tester.pumpWidget(GuitarApp(settings: settings, songs: repo!, synth: RecordingSynth()));
    await tester.pump();
    await _openFromHome(tester, 'Settings');

    Color accent() => Theme.of(tester.element(find.text('Frost'))).colorScheme.primary;
    expect(accent(), AppColorTheme.classic.accent);
    await tester.tap(find.text('Frost'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // theme change animates
    expect(settings.colorTheme, AppColorTheme.frost);
    expect(accent(), AppColorTheme.frost.accent);
  });

  for (final lang in [AppLanguage.en, AppLanguage.srLatn]) {
    testWidgets('every screen fits a small phone in landscape ($lang)', (tester) async {
      _phone(tester);
      final repo = await tester.runAsync(_repo);
      final settings = AppSettings.inMemory()
        ..language = lang
        ..showNoteNames = true;
      await tester.pumpWidget(GuitarApp(settings: settings, songs: repo!, synth: RecordingSynth()));
      await tester.pump();
      final t = Strings(lang);

      for (final screen in [t.chords, t.freePlay, t.settings]) {
        await _openFromHome(tester, screen);
        if (screen == t.chords) {
          await tester.tap(find.text('G'));
          await tester.pump(const Duration(milliseconds: 100));
        }
        final nav = tester.state<NavigatorState>(find.byType(Navigator));
        expect(nav.canPop(), isTrue, reason: 'opening $screen');
        nav.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }

      final song = find.text(lang == AppLanguage.en ? 'Ode to Joy' : 'Oda radosti').first;
      await tester.ensureVisible(song);
      await tester.pump();
      await tester.tap(song);
      await _waitFor(tester, find.text(t.play));
      await tester.tap(find.text(t.fullMode));
      await tester.pump();
      await tester.tap(find.text(t.play));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(t.pause), findsOneWidget);
    });
  }
}

void _phone(WidgetTester tester) {
  // A small phone held sideways: 800 x 360.
  tester.view.physicalSize = const Size(1600, 720);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<void> _openFromHome(WidgetTester tester, String button) async {
  final finder = find.text(button).first;
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Lets real async work (loading a song from assets, reading files in the
/// background) finish, then waits for [finder].
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}
