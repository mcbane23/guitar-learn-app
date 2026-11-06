import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_learn/app.dart';
import 'package:guitar_learn/audio/synth.dart';
import 'package:guitar_learn/data/song_repository.dart';
import 'package:guitar_learn/l10n/strings.dart';
import 'package:guitar_learn/models/song.dart';
import 'package:guitar_learn/settings/settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The app on a small phone held sideways, and what happens when it is sent
/// to the background while a song plays.
void main() {
  Future<RecordingSynth> start(WidgetTester tester, {required Size physicalSize, bool countIn = true}) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = await tester.runAsync(() async {
      final r = SongRepository(
        client: MockClient((_) async => http.Response('offline', 503)),
        cacheDir: () async => null,
      );
      await r.load();
      return r;
    });
    final settings = AppSettings.inMemory()
      ..language = AppLanguage.en
      ..countIn = countIn;
    final synth = RecordingSynth();
    await tester.pumpWidget(GuitarApp(settings: settings, songs: repo!, synth: synth));
    await tester.pump();
    return synth;
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  testWidgets('a small phone sideways: the player fits without overflowing', (tester) async {
    // 1280 x 720 pixels at 2x: 640 x 360 logical pixels, a common small phone.
    await start(tester, physicalSize: const Size(1280, 720));
    await tester.enterText(find.byType(TextField), 'silent night');
    await tester.pump();
    // On so small a screen the result is below the search bar: scroll to it first.
    await tester.ensureVisible(find.text('Silent Night'));
    await tester.pump();
    await tester.tap(find.text('Silent Night'));
    await waitFor(tester, find.text('Play'));

    // Short names for the two tracks, no words under the small buttons.
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Chords'), findsWidgets); // the home screen's button is still underneath
    expect(find.text('Full: every note'), findsNothing);
    expect(find.text('Slower'), findsNothing);
    expect(find.byTooltip('Slower'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Pause'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tablet keeps the full labels', (tester) async {
    await start(tester, physicalSize: const Size(2400, 1600));
    await tester.tap(find.text('Ode to Joy').first);
    await waitFor(tester, find.text('Play'));
    expect(find.text('Full: every note'), findsOneWidget);
    expect(find.text('Slower'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the song pauses when the app goes to the background', (tester) async {
    final synth = await start(tester, physicalSize: const Size(2400, 1600), countIn: false);
    await tester.tap(find.text('Ode to Joy').first);
    await waitFor(tester, find.text('Play'));
    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Pause'), findsOneWidget);
    final stops = synth.stops;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Play'), findsOneWidget);
    expect(synth.stops, greaterThan(stops));

    // Coming back does not start the song by itself.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Play'), findsOneWidget);
  });

  test('only Serbian titles are written in Cyrillic', () {
    final both = SongInfo.fromJson({'id': 'a', 'title': {'en': 'Silent Night', 'sr': 'Tiha noć'}});
    final fromFile = SongInfo.fromJson({'id': 'b', 'title': 'Nothing Else Matters'});
    expect(Strings(AppLanguage.srCyrl).songTitle(both), 'Тиха ноћ');
    expect(Strings(AppLanguage.srLatn).songTitle(both), 'Tiha noć');
    expect(Strings(AppLanguage.en).songTitle(both), 'Silent Night');
    expect(Strings(AppLanguage.srCyrl).songTitle(fromFile), 'Nothing Else Matters');
    expect(Strings(AppLanguage.en).songTitle(fromFile), 'Nothing Else Matters');
  });
}
