import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_learn/app.dart';
import 'package:guitar_learn/audio/synth.dart';
import 'package:guitar_learn/data/song_repository.dart';
import 'package:guitar_learn/l10n/strings.dart';
import 'package:guitar_learn/settings/settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The app used with only a TV remote: arrows and OK, no touch.
void main() {
  Future<(AppSettings, RecordingSynth)> start(WidgetTester tester) async {
    // A 1080p TV: 960 x 540 logical pixels.
    tester.view.physicalSize = const Size(1920, 1080);
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
      ..countIn = false;
    final synth = RecordingSynth();
    await tester.pumpWidget(GuitarApp(settings: settings, songs: repo!, synth: synth));
    await tester.pump();
    await tester.pump();
    return (settings, synth);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  String? focusedText(WidgetTester tester) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    final texts = <String>[];
    void visit(Element e) {
      final w = e.widget;
      if (w is Text && w.data != null) texts.add(w.data!);
      e.visitChildren(visit);
    }

    (ctx as Element).visitChildren(visit);
    if (texts.isNotEmpty) return texts.join(' | ');
    // An icon button: its name is in the tooltip around it.
    return ctx.findAncestorWidgetOfExactType<Tooltip>()?.message ?? '';
  }

  testWidgets('home starts on a beginner song and moving up passes the search without typing', (tester) async {
    await start(tester);
    expect(focusedText(tester), contains('Easy'));
    await press(tester, LogicalKeyboardKey.arrowUp);
    // The search box is selected like a button; the keyboard is not open.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search');
    expect(tester.testTextInput.isVisible, isFalse);
    // Up again goes on to the buttons at the top, down comes back to the songs.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('search'));
    await press(tester, LogicalKeyboardKey.arrowDown, 2);
    expect(focusedText(tester), contains('Easy'));

    // OK on the search box starts typing; down leaves it again.
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.select);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search field');
    await tester.enterText(find.byType(TextField), 'joy');
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedText(tester), contains('Ode to Joy'));
  });

  testWidgets('a song is played and slowed down with arrows and OK only', (tester) async {
    final (_, synth) = await start(tester);
    final song = focusedText(tester);
    await press(tester, LogicalKeyboardKey.select);
    await waitFor(tester, find.text('Play'));
    expect(song, isNotNull);

    // The big Play button has the focus; OK starts the song.
    expect(focusedText(tester), 'Play');
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('Pause'), findsOneWidget);
    expect(focusedText(tester), 'Pause');
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('Play'), findsOneWidget);

    // Back and Forward move a bar at a time; the song stays paused.
    await press(tester, LogicalKeyboardKey.arrowRight, 2);
    expect(focusedText(tester), 'Bar back');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedText(tester), 'Bar forward');
    double position() => tester.widget<Slider>(find.byType(Slider)).value;
    // The song played for a moment before Pause, so it is just past the start.
    expect(position(), lessThan(1));
    await press(tester, LogicalKeyboardKey.select, 2);
    expect(position(), greaterThanOrEqualTo(8));
    expect(find.text('Play'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedText(tester), 'Bar back');
    await press(tester, LogicalKeyboardKey.select, 2);
    expect(position(), 0);

    // The remote's rewind/forward keys do the same wherever the focus is.
    await press(tester, LogicalKeyboardKey.mediaFastForward, 2);
    expect(position(), greaterThanOrEqualTo(8));
    await press(tester, LogicalKeyboardKey.mediaRewind, 2);
    expect(position(), 0);
    expect(focusedText(tester), 'Bar back');

    // Slower: to the right along the row, the speed goes down by 5%.
    await press(tester, LogicalKeyboardKey.arrowRight, 3);
    expect(focusedText(tester), 'Slower');
    expect(find.text('75%'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.select, 2);
    expect(find.text('65%'), findsOneWidget);

    // Wait for me: the big button turns into Next and keeps the focus.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedText(tester), 'Wait for me');
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowLeft, 4);
    expect(focusedText(tester), 'Play');
    await press(tester, LogicalKeyboardKey.select);
    // The song clock runs in real time.
    for (var i = 0; i < 100 && find.text('Next').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(focusedText(tester), 'Next');
    final before = synth.notes.length;
    await press(tester, LogicalKeyboardKey.select);
    for (var i = 0; i < 100 && synth.notes.length == before; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(synth.notes.length, greaterThan(before));
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);

    // More opens the extra options, also reachable with the remote.
    await press(tester, LogicalKeyboardKey.arrowRight, 10);
    expect(focusedText(tester), 'More');
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('Sound off'), findsOneWidget);
    expect(focusedText(tester), contains('Play song'));
  });

  testWidgets('back from a song returns the focus to the card that was opened', (tester) async {
    await start(tester);
    // The second beginner song, so "Recently played" (which appears above)
    // and the row's order both change while it is open.
    await press(tester, LogicalKeyboardKey.arrowRight);
    final card = focusedText(tester);
    expect(card, contains('Easy'));
    await press(tester, LogicalKeyboardKey.select);
    await waitFor(tester, find.text('Play'));
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Recently played'), findsOneWidget);
    expect(focusedText(tester), card);
  });

  testWidgets('settings: the sliders take left and right; up and down move on', (tester) async {
    await start(tester);
    await press(tester, LogicalKeyboardKey.arrowUp, 2);
    for (var i = 0; i < 8 && focusedText(tester) != 'Settings'; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(focusedText(tester), 'Settings');
    await press(tester, LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Language'), findsOneWidget);

    Slider? focusedSlider() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Slider>();
    for (var i = 0; i < 30 && focusedSlider() == null; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    final speed = focusedSlider();
    expect(speed, isNotNull);
    expect(speed!.value, 0.75);
    // Left and right change the value.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedSlider()!.value, closeTo(0.7, 1e-9));
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedSlider()!.value, closeTo(0.75, 1e-9));
    // Down goes on to the volume, and then past the sliders to the rest.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedSlider(), isNotNull);
    expect(focusedSlider()!.value, isNot(0.75));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedSlider(), isNull);
    for (var i = 0; i < 20 && !(focusedText(tester) ?? '').contains('Check for a new version'); i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focusedText(tester), contains('Check for a new version'));
    // Up comes back through the sliders without changing them.
    for (var i = 0; i < 20 && focusedSlider() == null; i++) {
      await press(tester, LogicalKeyboardKey.arrowUp);
    }
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedSlider()!.value, 0.75);
  });

  testWidgets('add songs: all four choices fit on the TV screen', (tester) async {
    await start(tester);
    await press(tester, LogicalKeyboardKey.arrowUp, 2);
    // "Add songs" is the third of the big cards under the title.
    for (var i = 0; i < 8 && focusedText(tester) != 'Add songs'; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(focusedText(tester), 'Add songs');
    await press(tester, LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 500));
    final t = Strings(AppLanguage.en);
    // The last choice, hint and all, is on the screen without scrolling.
    final hint = find.text(t.sendToTvHint);
    expect(hint, findsOneWidget);
    expect(tester.getBottomLeft(hint).dy, lessThan(540));
    expect(tester.takeException(), isNull);
  });

  testWidgets('free play: arrows walk the neck and OK plays the note', (tester) async {
    final (_, synth) = await start(tester);
    await press(tester, LogicalKeyboardKey.arrowUp, 2);
    while (focusedText(tester) != 'Free play') {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text(Strings(AppLanguage.en).freePlayHint), findsOneWidget);

    // Starts on the open G string.
    await press(tester, LogicalKeyboardKey.select);
    expect(synth.notes.last.midi, 55); // open G
    await press(tester, LogicalKeyboardKey.arrowRight, 2);
    await press(tester, LogicalKeyboardKey.select);
    expect(synth.notes.last.midi, 57); // A, 2nd fret of G
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.select);
    expect(synth.notes.last.string, 2);
    expect(synth.notes.last.midi, 61); // C#, 2nd fret of B
  });
}
