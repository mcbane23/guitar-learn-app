import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_learn/app.dart';
import 'package:guitar_learn/audio/synth.dart';
import 'package:guitar_learn/data/song_repository.dart';
import 'package:guitar_learn/l10n/strings.dart';
import 'package:guitar_learn/settings/settings.dart';
import 'package:guitar_learn/update/app_update.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An updater that finds build [newest] and records what the app asked for.
class FakeUpdater implements AppUpdater {
  FakeUpdater({this.newest, this.installOk = true});

  final int? newest;
  final bool installOk;
  int checks = 0;
  AppUpdate? installed;

  @override
  Future<int> currentBuild() async => 29;

  @override
  Future<AppUpdate?> check() async {
    checks++;
    final n = newest;
    return n == null ? null : AppUpdate(build: n, apkUrl: 'https://example.com/guitar-learn.apk');
  }

  @override
  Future<bool> install(AppUpdate update, {void Function(double progress)? onProgress}) async {
    installed = update;
    onProgress?.call(0.5);
    onProgress?.call(1);
    return installOk;
  }
}

void main() {
  Future<SongRepository> repo(WidgetTester tester) async => (await tester.runAsync(() async {
        final r = SongRepository(client: MockClient((_) async => http.Response('offline', 503)), cacheDir: () async => null);
        await r.load();
        return r;
      }))!;

  Future<void> start(WidgetTester tester, AppUpdater updater, {AppLanguage language = AppLanguage.en}) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final settings = AppSettings.inMemory()..language = language;
    await tester.pumpWidget(GuitarApp(settings: settings, songs: await repo(tester), synth: RecordingSynth(), updater: updater));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a newer build shows a card on the home screen and installs from the dialog', (tester) async {
    final updater = FakeUpdater(newest: 31);
    await start(tester, updater);

    expect(updater.checks, 1);
    expect(find.text('New version available (build 31)'), findsOneWidget);
    // The remote's focus moves to the card as soon as it appears, and the
    // arrows can leave it (down: the search row) and come back.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'update now');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('update now'));
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'update now');

    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Android asks you to install it'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Update')));
    await tester.pumpAndSettle();
    expect(updater.installed?.build, 31);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Later hides the card; a failed install says so', (tester) async {
    final updater = FakeUpdater(newest: 31, installOk: false);
    await start(tester, updater, language: AppLanguage.srLatn);
    expect(find.text('Dostupna je nova verzija (build 31)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Ažuriraj'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Ažuriraj')));
    await tester.pumpAndSettle();
    expect(find.text('Ažuriranje nije uspelo. Probaj kasnije.'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Kasnije')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kasnije'));
    await tester.pump();
    expect(find.text('Dostupna je nova verzija (build 31)'), findsNothing);
  });

  testWidgets('settings check for a new version and show the installed build', (tester) async {
    final updater = FakeUpdater();
    await start(tester, updater);
    expect(find.textContaining('New version available'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Check for a new version'), 300);
    expect(find.text('Installed version: build 29'), findsOneWidget);

    await tester.tap(find.text('Check for a new version'));
    await tester.pumpAndSettle();
    expect(updater.checks, 2);
    expect(find.text('You have the newest version'), findsOneWidget);
  });

  test('GitHubAppUpdater reads version.json and skips builds that are not newer', () async {
    // The platform channel is missing in tests, so currentBuild is 0 and check gives up quietly.
    final updater = GitHubAppUpdater(
      client: MockClient((req) async => http.Response('{"build": 40, "apk": "https://x/guitar-learn.apk"}', 200)),
    );
    expect(await updater.currentBuild(), 0);
    expect(await updater.check(), isNull);
    expect(defaultUpdateUrl, 'https://github.com/mcbane23/guitar-learn-app/releases/latest/download/');
  });
}
