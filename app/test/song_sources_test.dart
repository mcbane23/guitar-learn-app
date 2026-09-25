import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_learn/data/song_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _main = 'https://songs.example/';
const _extra = 'https://user.github.io/more/extra/';

String _song(String id) => jsonEncode({
      'id': id,
      'title': {'en': id, 'sr': id},
      'tracks': {
        'full': [
          {'beat': 0, 'string': 1, 'fret': 0, 'finger': 0, 'length': 1},
        ],
      },
    });

Map<String, dynamic> _entry(String id, [int version = 1]) =>
    {'id': id, 'file': '$id.json', 'title': {'en': id, 'sr': id}, 'version': version};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GitHub links become GitHub Pages folders', () {
    expect(normalizeSongSource('https://github.com/mcbane23/guitar-learn-songs'),
        'https://mcbane23.github.io/guitar-learn-songs/');
    expect(normalizeSongSource('github.com/User/Repo/tree/main/extra'), 'https://user.github.io/Repo/extra/');
    expect(normalizeSongSource('https://github.com/me/me.github.io'), 'https://me.github.io/');
    expect(normalizeSongSource('https://mcbane23.github.io/guitar-learn-songs/extra'),
        'https://mcbane23.github.io/guitar-learn-songs/extra/');
    expect(normalizeSongSource('https://example.com/songs/index.json'), 'https://example.com/songs/');
  });

  group('refresh', () {
    late Directory dir;
    late Map<String, List<Map<String, dynamic>>> catalogs;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('songs');
      catalogs = {
        _main: [_entry('main-song')],
        _extra: [_entry('extra-song'), _entry('main-song', 5)],
      };
    });
    tearDown(() => dir.deleteSync(recursive: true));

    SongRepository repo(List<String> extra) => SongRepository(
          baseUrl: _main,
          extraSources: extra,
          cacheDir: () async => dir,
          client: MockClient((req) async {
            final url = req.url.toString();
            for (final base in catalogs.keys) {
              if (url == '${base}index.json') {
                return http.Response(jsonEncode({'version': 1, 'songs': catalogs[base]}), 200);
              }
              if (url.startsWith(base) && url.endsWith('.json') && !url.endsWith('chords.json')) {
                final id = url.substring(base.length, url.length - 5);
                if (catalogs[base]!.any((e) => e['id'] == id)) return http.Response(_song(id), 200);
              }
            }
            return http.Response('not found', 404);
          }),
        );

    test('downloads from added sources, the main source wins on the same id', () async {
      final r = repo([_extra]);
      await r.load();
      final (result, count) = await r.refresh();
      expect(result, RefreshResult.added);
      expect(count, 2);
      expect(r.sourceOf('main-song'), _main);
      expect(r.sourceOf('extra-song'), _extra);
      expect((await r.loadSong('extra-song')).id, 'extra-song');

      // Still there after a restart, without the Internet.
      final again = repo([_extra]);
      await again.load();
      expect(again.isDownloaded('extra-song'), isTrue);
    });

    test('removing a source, or a song from a source, removes the song', () async {
      final r = repo([_extra]);
      await r.load();
      await r.refresh();

      r.extraSources = [];
      await r.refresh();
      expect(r.isDownloaded('extra-song'), isFalse);
      expect(r.isDownloaded('main-song'), isTrue);

      catalogs[_main] = [];
      await r.refresh();
      expect(r.isDownloaded('main-song'), isFalse);
      expect(dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last), isNot(contains('main-song.json')));
    });

    test('an unreachable source keeps its songs on the device', () async {
      final r = repo([_extra]);
      await r.load();
      await r.refresh();
      catalogs.remove(_extra);
      await r.refresh();
      expect(r.isDownloaded('extra-song'), isTrue);
    });

    test('checkSource finds a song list and rejects other links', () async {
      final r = repo([]);
      expect(await r.checkSource('https://user.github.io/more/extra'), (_extra, 2));
      expect(await r.checkSource('https://nothing.example/'), isNull);
    });
  });
}
