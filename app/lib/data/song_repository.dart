import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/chord.dart';
import '../models/song.dart';

/// Where new songs are published. The folder holds index.json (the catalog),
/// chords.json and one JSON file per song, the same layout as songs/ in the
/// repository. It can be overridden at build time with
/// `--dart-define=SONGS_URL=https://.../songs/`.
const defaultSongsUrl = String.fromEnvironment(
  'SONGS_URL',
  defaultValue: 'https://mcbane23.github.io/guitar-learn-app/songs/',
);

enum RefreshResult { upToDate, added, offline }

/// Songs that ship with the app plus songs downloaded from the Internet.
/// Downloaded songs are kept on the device so they work offline.
class SongRepository extends ChangeNotifier {
  SongRepository({
    AssetBundle? bundle,
    http.Client? client,
    Future<Directory?> Function()? cacheDir,
    this.baseUrl = defaultSongsUrl,
  })  : _bundle = bundle ?? rootBundle,
        _client = client ?? http.Client(),
        _cacheDirFn = cacheDir ?? _defaultCacheDir;

  final AssetBundle _bundle;
  final http.Client _client;
  final Future<Directory?> Function() _cacheDirFn;
  final String baseUrl;

  static const _assetDir = 'assets/songs/';

  final Map<String, SongInfo> _bundled = {};
  final Map<String, SongInfo> _downloaded = {};
  final Map<String, Song> _songCache = {};
  ChordLibrary chords = ChordLibrary({});
  Directory? _dir;
  bool refreshing = false;

  static Future<Directory?> _defaultCacheDir() async {
    try {
      final base = await getApplicationSupportDirectory();
      return Directory('${base.path}/songs');
    } catch (_) {
      return null;
    }
  }

  /// All songs, in catalog order (bundled first).
  List<SongInfo> get songs => [
        ..._bundled.values,
        for (final s in _downloaded.values)
          if (!_bundled.containsKey(s.id)) s,
      ];

  bool isDownloaded(String id) => _downloaded.containsKey(id) && !_bundled.containsKey(id);

  Future<void> load() async {
    final index = jsonDecode(await _bundle.loadString('${_assetDir}index.json', cache: false)) as Map<String, dynamic>;
    for (final s in (index['songs'] as List)) {
      final info = SongInfo.fromJson((s as Map).cast<String, dynamic>());
      _bundled[info.id] = info;
    }
    chords = ChordLibrary.fromJson(
      jsonDecode(await _bundle.loadString('${_assetDir}chords.json', cache: false)) as Map<String, dynamic>,
    );

    _dir = await _cacheDirFn();
    final dir = _dir;
    if (dir != null) {
      try {
        final cachedChords = File('${dir.path}/chords.json');
        if (await cachedChords.exists()) {
          chords.addAll(ChordLibrary.fromJson(jsonDecode(await cachedChords.readAsString()) as Map<String, dynamic>));
        }
        final cachedIndex = File('${dir.path}/index.json');
        if (await cachedIndex.exists()) {
          final j = jsonDecode(await cachedIndex.readAsString()) as Map<String, dynamic>;
          for (final s in (j['songs'] as List)) {
            final info = SongInfo.fromJson((s as Map).cast<String, dynamic>());
            if (await File('${dir.path}/${_fileName(info)}').exists()) _downloaded[info.id] = info;
          }
        }
      } catch (e) {
        debugPrint('Song cache unreadable, ignoring it: $e');
      }
    }
    notifyListeners();
  }

  static String _fileName(SongInfo info) {
    final f = info.file ?? '${info.id}.json';
    // Never let a catalog entry write outside the cache folder.
    return f.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  Future<Song> loadSong(String id) async {
    final cached = _songCache[id];
    if (cached != null) return cached;
    String text;
    final downloaded = _downloaded[id];
    final bundled = _bundled[id];
    if (downloaded != null && _dir != null && (bundled == null || downloaded.version > bundled.version)) {
      text = await File('${_dir!.path}/${_fileName(downloaded)}').readAsString();
    } else if (bundled != null) {
      text = await _bundle.loadString('$_assetDir${bundled.file ?? '$id.json'}', cache: false);
    } else {
      throw StateError('Unknown song $id');
    }
    final song = Song.fromJson(jsonDecode(text) as Map<String, dynamic>);
    _songCache[id] = song;
    return song;
  }

  /// Downloads the online catalog and any new or updated songs.
  Future<(RefreshResult, int)> refresh() async {
    if (refreshing) return (RefreshResult.upToDate, 0);
    refreshing = true;
    notifyListeners();
    try {
      final dir = _dir;
      final indexRes = await _client.get(Uri.parse('${baseUrl}index.json')).timeout(const Duration(seconds: 15));
      if (indexRes.statusCode != 200) return (RefreshResult.offline, 0);
      final index = jsonDecode(utf8.decode(indexRes.bodyBytes)) as Map<String, dynamic>;
      final remote = [
        for (final s in (index['songs'] as List)) SongInfo.fromJson((s as Map).cast<String, dynamic>()),
      ];

      final chordRes = await _client.get(Uri.parse('${baseUrl}chords.json')).timeout(const Duration(seconds: 15));
      if (chordRes.statusCode == 200) {
        final body = utf8.decode(chordRes.bodyBytes);
        chords.addAll(ChordLibrary.fromJson(jsonDecode(body) as Map<String, dynamic>));
        if (dir != null) {
          await dir.create(recursive: true);
          await File('${dir.path}/chords.json').writeAsString(body);
        }
      }

      var added = 0;
      for (final info in remote) {
        final have = _downloaded[info.id] ?? _bundled[info.id];
        if (have != null && have.version >= info.version) continue;
        final res = await _client
            .get(Uri.parse('$baseUrl${Uri.encodeComponent(info.file ?? '${info.id}.json')}'))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) continue;
        final body = utf8.decode(res.bodyBytes);
        final song = Song.fromJson(jsonDecode(body) as Map<String, dynamic>); // validates it
        if (dir != null) {
          await dir.create(recursive: true);
          await File('${dir.path}/${_fileName(info)}').writeAsString(body);
        }
        if (!_bundled.containsKey(info.id) && !_downloaded.containsKey(info.id)) added++;
        _downloaded[info.id] = info;
        _songCache[info.id] = song;
      }
      if (dir != null) {
        await File('${dir.path}/index.json').writeAsString(jsonEncode({
          'version': 1,
          'songs': [for (final s in _downloaded.values) s.toJson()],
        }));
      }
      return (added > 0 ? RefreshResult.added : RefreshResult.upToDate, added);
    } catch (e) {
      debugPrint('Could not refresh songs: $e');
      return (RefreshResult.offline, 0);
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }
}
