import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_learn/app.dart';
import 'package:guitar_learn/audio/synth.dart';
import 'package:guitar_learn/data/song_repository.dart';
import 'package:guitar_learn/import/score.dart' show ImportError;
import 'package:guitar_learn/l10n/strings.dart';
import 'package:guitar_learn/settings/settings.dart';
import 'package:guitar_learn/share/song_receiver.dart';
import 'package:guitar_learn/share/song_sender.dart';
import 'package:guitar_learn/ui/receive_songs_screen.dart';
import 'package:guitar_learn/ui/send_songs_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';

final _song = utf8.encode(jsonEncode({
  'id': 'x',
  'title': {'en': 'Sent Song'},
  'tracks': {
    'full': [
      {'beat': 0, 'string': 1, 'fret': 0, 'finger': 0, 'length': 1},
    ],
  },
}));

/// The test binding answers every HTTP request with 400; these tests talk
/// to a real server on the loopback address, so they need a real client.
Future<T> _real<T>(Future<T> Function() body) => HttpOverrides.runWithHttpOverrides(body, _RealHttp());

class _RealHttp extends HttpOverrides {}

Future<SongRepository> _repo(Directory dir) async {
  final repo = SongRepository(client: MockClient((_) async => http.Response('offline', 503)), cacheDir: () async => dir);
  await repo.load();
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('receiver', () {
    late Directory dir;
    late SongRepository repo;
    late SongReceiver receiver;
    late Uri base;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('share');
      repo = await _repo(dir);
      receiver = SongReceiver(repo, deviceName: 'Test TV', bindAddress: InternetAddress.loopbackIPv4, port: 0);
      await receiver.start();
      expect(receiver.running, isTrue);
      base = Uri.parse('http://127.0.0.1:${receiver.port}/');
    });
    tearDown(() async {
      await receiver.stop();
      dir.deleteSync(recursive: true);
    });

    test('the page needs the code from the screen, in the phone\'s language', () => _real(() async {
      final noCode = await http.get(base);
      expect(noCode.statusCode, 200);
      expect(noCode.body, contains('4-digit code'));
      expect(noCode.body, isNot(contains('type="file"')));

      final wrong = await http.get(base.resolve('0000'));
      expect(wrong.statusCode, 403);

      final page = await http.get(base.resolve(receiver.code));
      expect(page.statusCode, 200);
      expect(page.body, contains('type="file"'));
      expect(page.body, contains('Choose song files'));
      expect(page.body, contains('Test TV'));

      final sr = await http.get(base.resolve(receiver.code), headers: {'Accept-Language': 'sr-RS,sr;q=0.9'});
      expect(sr.body, contains('Izaberi fajlove'));
      final cyr = await http.get(base.resolve(receiver.code), headers: {'Accept-Language': 'sr-Cyrl-RS'});
      expect(cyr.body, contains('Изабери фајлове'));
    }));

    test('uploads become songs in My songs; bad files are refused', () => _real(() async {
      final res = await http.put(base.resolve('${receiver.code}/upload?name=song.json'), body: _song);
      expect(res.statusCode, 200);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      expect(j['ok'], isTrue);
      expect(j['title'], 'Sent Song');
      expect(repo.importedSongs.map((s) => s.title['en']), ['Sent Song']);
      expect(receiver.received.single.outcome!.ok, isTrue);

      final again = await http.put(base.resolve('${receiver.code}/upload?name=song.json'), body: _song);
      expect(jsonDecode(again.body)['alreadyAdded'], isTrue);

      final pdf = await http.put(base.resolve('${receiver.code}/upload?name=notes.pdf'), body: [0x25, 0x50, 0x44, 0x46, 1, 2]);
      expect(jsonDecode(pdf.body)['ok'], isFalse);
      expect(jsonDecode(pdf.body)['error'], 'unsupported');

      final noName = await http.put(base.resolve('${receiver.code}/upload'), body: _song);
      expect(noName.statusCode, 400);
      final wrongCode = await http.put(base.resolve('0000/upload?name=song.json'), body: _song);
      expect(wrongCode.statusCode, 403);
      expect(repo.importedSongs.length, 1);
    }));

    test('a phone finds the receiver and sends songs to it', () => _real(() async {
      final found = await findReceivers(targets: [InternetAddress.loopbackIPv4], timeout: const Duration(milliseconds: 600));
      final r = found.where((r) => r.code == receiver.code).single;
      expect(r.port, receiver.port);
      expect(r.name, 'Test TV');

      final progress = SendProgress(2);
      final results = await sendSongs(
        r,
        [
          OutgoingFile(name: 'song.json', read: () async => _song),
          OutgoingFile(name: 'empty.gp5', read: () async => Uint8List(0)),
        ],
        progress: progress,
      );
      expect(results.map((r) => r.ok), [true, false]);
      expect(results[0].title, 'Sent Song');
      expect(results[1].error, ImportError.empty);
      expect(progress.results.length, 2);
      expect(repo.importedSongs.length, 1);
    }));

    test('a receiver that went away is reported, and the rest is not sent', () => _real(() async {
      final port = receiver.port!;
      await receiver.stop();
      final results = await sendSongs(
        Receiver(host: '127.0.0.1', port: port, code: '1234'),
        [OutgoingFile(name: 'a.json', read: () async => _song), OutgoingFile(name: 'b.json', read: () async => _song)],
      );
      expect(results.length, 1);
      expect(results.single.unreachable, isTrue);
    }));
  });

  test('typed addresses', () {
    expect(Receiver.parse('http://192.168.1.5:8765/1234'), const Receiver(host: '192.168.1.5', port: 8765, code: '1234'));
    expect(Receiver.parse(' 192.168.1.5:8765/1234 '), const Receiver(host: '192.168.1.5', port: 8765, code: '1234'));
    expect(Receiver.parse('192.168.1.5/1234'), const Receiver(host: '192.168.1.5', port: defaultReceivePort, code: '1234'));
    expect(Receiver.parse('192.168.1.5'), isNull);
    expect(Receiver.parse('192.168.1.5/abc'), isNull);
    expect(Receiver.parse(''), isNull);
  });

  testWidgets('the TV screen shows a QR code, the address and received files', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('share');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = await tester.runAsync(() => _repo(dir));
    final receiver = SongReceiver(repo!, bindAddress: InternetAddress.loopbackIPv4, port: 0);
    await tester.runAsync(receiver.start);
    addTearDown(receiver.stop);
    final settings = AppSettings.inMemory()..language = AppLanguage.srLatn;
    await tester.pumpWidget(_app(settings, repo, ReceiveSongsScreen(receiver: receiver)));
    await tester.pump();

    expect(find.text('Pošalji pesme sa telefona'), findsOneWidget);
    expect(find.text('Čeka se telefon...'), findsOneWidget);
    // Loopback is not a Wi-Fi address, so the screen says so; the QR code needs a network address.
    if (receiver.addresses.isEmpty) {
      expect(find.text('Ovaj uređaj nije povezan na Wi-Fi mrežu.'), findsOneWidget);
    } else {
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining(receiver.code), findsWidgets);
    }

    await tester.runAsync(() => receiver.receive('song.json', Uint8List.fromList(_song)));
    await tester.pump();
    expect(find.text('song.json'), findsOneWidget);
    expect(find.text('Dodata je 1 pesma'), findsOneWidget);
  });

  testWidgets('the phone screen lists the TVs it found and what to send', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = await tester.runAsync(() => _repo(Directory.systemTemp.createTempSync('share')));
    final settings = AppSettings.inMemory()..language = AppLanguage.en;
    const tv = Receiver(host: '192.168.1.7', port: 8765, code: '4321', name: 'Living room');
    await tester.pumpWidget(_app(settings, repo!, SendSongsScreen(finder: () async => [tv])));
    await tester.pump();
    await tester.pump();

    expect(find.text('Living room'), findsOneWidget);
    expect(find.text('http://192.168.1.7:8765/4321'), findsOneWidget);
    await tester.tap(find.text('Living room'));
    await tester.pump();
    expect(find.text('What to send'), findsOneWidget);
    expect(find.text('My songs (0)'), findsOneWidget);
    expect(find.text('Files from this device'), findsOneWidget);
  });

  testWidgets('a typed address that is not from the TV is refused', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = await tester.runAsync(() => _repo(Directory.systemTemp.createTempSync('share')));
    final settings = AppSettings.inMemory()..language = AppLanguage.en;
    await tester.pumpWidget(_app(settings, repo!, SendSongsScreen(finder: () async => [])));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('No TV found'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nonsense');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('This is not the address from the TV screen'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '192.168.1.9:8765/1111');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('What to send'), findsOneWidget);
  });
}

Widget _app(AppSettings settings, SongRepository repo, Widget home) {
  final strings = Strings(settings.language ?? AppLanguage.en);
  return SettingsScope(
    settings: settings,
    child: AppServices(
      songs: repo,
      synth: RecordingSynth(),
      pickFiles: () async => null,
      pickFolder: () async => null,
      child: StringsScope(strings: strings, child: MaterialApp(home: home)),
    ),
  );
}
