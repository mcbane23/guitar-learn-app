import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../import/importer.dart';
import '../models/chord.dart';
import '../models/song.dart';

export '../import/importer.dart' show ImportFile, ImportOutcome, supportedExtensions, supportedFormatNames;

/// Where new songs are published. The folder holds index.json (the catalog),
/// chords.json and one JSON file per song, the same layout as songs/ in the
/// repository. It can be overridden at build time with
/// `--dart-define=SONGS_URL=https://.../songs/`.
const defaultSongsUrl = String.fromEnvironment(
  'SONGS_URL',
  defaultValue: 'https://mcbane23.github.io/guitar-learn-songs/',
);

enum RefreshResult { upToDate, added, offline }

/// Turns what a person types as a song source into the folder URL the app
/// reads index.json from. A GitHub repository link becomes its GitHub Pages
/// address: github.com/user/repo/tree/main/extra -> user.github.io/repo/extra/.
String normalizeSongSource(String input) {
  var url = input.trim();
  if (url.isEmpty) return url;
  if (!url.contains('://')) url = 'https://$url';
  var uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  if ((uri.host == 'github.com' || uri.host == 'www.github.com') && parts.length >= 2) {
    final owner = parts[0].toLowerCase();
    final repo = parts[1].replaceAll(RegExp(r'\.git$'), '');
    // .../tree/<branch>/<folder> or .../blob/<branch>/<folder>/index.json
    var rest = parts.length > 4 && (parts[2] == 'tree' || parts[2] == 'blob') ? parts.sublist(4) : <String>[];
    if (rest.isNotEmpty && rest.last == 'index.json') rest = rest.sublist(0, rest.length - 1);
    final path = repo.toLowerCase() == '$owner.github.io' ? rest : [repo, ...rest];
    uri = Uri(scheme: 'https', host: '$owner.github.io', pathSegments: [...path, '']);
  } else if (parts.isNotEmpty && parts.last == 'index.json') {
    uri = uri.replace(pathSegments: [...parts.sublist(0, parts.length - 1), '']);
  }
  final text = uri.toString();
  return text.endsWith('/') ? text : '$text/';
}

/// Songs that ship with the app plus songs downloaded from the Internet.
/// Downloaded songs are kept on the device so they work offline.
///
/// Songs come from [baseUrl] and from any [extraSources] the user added in
/// settings. When two sources have a song with the same id, the first wins.
class SongRepository extends ChangeNotifier {
  SongRepository({
    AssetBundle? bundle,
    http.Client? client,
    Future<Directory?> Function()? cacheDir,
    this.baseUrl = defaultSongsUrl,
    List<String> extraSources = const [],
  })  : _bundle = bundle ?? rootBundle,
        _client = client ?? http.Client(),
        _cacheDirFn = cacheDir ?? _defaultCacheDir,
        _extra = [for (final s in extraSources) normalizeSongSource(s)];

  final AssetBundle _bundle;
  final http.Client _client;
  final Future<Directory?> Function() _cacheDirFn;
  final String baseUrl;
  List<String> _extra;

  static const _assetDir = 'assets/songs/';

  final Map<String, SongInfo> _bundled = {};
  final Map<String, SongInfo> _downloaded = {};
  final Map<String, SongInfo> _imported = {}; // songs the user opened from files
  final Map<String, String> _sourceOf = {}; // downloaded song id -> source URL
  final Map<String, Song> _songCache = {};
  ChordLibrary chords = ChordLibrary({});
  Directory? _dir;
  bool refreshing = false;
  bool importing = false;

  static Future<Directory?> _defaultCacheDir() async {
    try {
      final base = await getApplicationSupportDirectory();
      return Directory('${base.path}/songs');
    } catch (_) {
      return null;
    }
  }

  /// Song sources the user added, as folder URLs.
  List<String> get extraSources => List.unmodifiable(_extra);

  List<String> get _sources => [baseUrl, ..._extra.where((s) => s != baseUrl)];

  /// Replaces the user's song sources. Songs from removed sources disappear
  /// at the next [refresh].
  set extraSources(List<String> sources) {
    _extra = [for (final s in sources) normalizeSongSource(s)];
  }

  /// All songs, in catalog order (bundled first, the user's own files last).
  List<SongInfo> get songs => [
        ..._bundled.values,
        for (final s in _downloaded.values)
          if (!_bundled.containsKey(s.id)) s,
        ..._imported.values,
      ];

  /// Songs the user opened from files, newest first.
  List<SongInfo> get importedSongs => _imported.values.toList().reversed.toList();

  bool isDownloaded(String id) => _downloaded.containsKey(id) && !_bundled.containsKey(id);
  bool isImported(String id) => _imported.containsKey(id);

  Directory? get _importDir => _dir == null ? null : Directory('${_dir!.path}/imported');

  Future<void> _loadImported() async {
    final dir = _importDir;
    if (dir == null) return;
    try {
      final index = File('${dir.path}/index.json');
      if (!await index.exists()) return;
      final j = jsonDecode(await index.readAsString()) as Map<String, dynamic>;
      for (final s in (j['songs'] as List)) {
        final info = SongInfo.fromJson((s as Map).cast<String, dynamic>());
        if (await File('${dir.path}/${_importedFile(info.id)}').exists()) _imported[info.id] = info;
      }
    } catch (e) {
      debugPrint('Imported songs unreadable, ignoring them: $e');
    }
  }

  String _importedFile(String id) => '${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json';

  Future<void> _saveImportedIndex() async {
    final dir = _importDir;
    if (dir == null) return;
    await dir.create(recursive: true);
    await File('${dir.path}/index.json').writeAsString(jsonEncode({
      'version': 1,
      'songs': [for (final s in _imported.values) s.toJson()],
    }));
  }

  /// Reads song files the user picked (Guitar Pro, MIDI, MusicXML, text tabs)
  /// and adds the ones that could be read to the library, kept on the device.
  /// Returns one outcome per file, in the same order.
  Future<List<ImportOutcome>> importFiles(List<ImportFile> files) async {
    if (files.isEmpty) return const [];
    importing = true;
    notifyListeners();
    try {
      final request = ImportRequest(files: files, knownChords: chords.names.toSet());
      final outcomes = files.length == 1 && files.first.bytes.length < 64 * 1024
          ? importFilesInIsolate(request)
          : await compute(importFilesInIsolate, request);
      final dir = _importDir;
      for (final o in outcomes) {
        final json = o.song;
        if (json == null) continue;
        final song = Song.fromJson(json);
        final info = SongInfo.fromJson(json);
        if (dir != null) {
          await dir.create(recursive: true);
          await File('${dir.path}/${_importedFile(info.id)}').writeAsString(jsonEncode(json));
        }
        _imported.remove(info.id); // re-importing a file moves it to the front
        _imported[info.id] = info;
        _songCache[info.id] = song;
      }
      await _saveImportedIndex();
      return outcomes;
    } finally {
      importing = false;
      notifyListeners();
    }
  }

  /// Forgets a song the user imported and deletes its file.
  Future<void> removeImported(String id) async {
    if (_imported.remove(id) == null) return;
    _songCache.remove(id);
    final dir = _importDir;
    if (dir != null) {
      final f = File('${dir.path}/${_importedFile(id)}');
      if (await f.exists()) await f.delete();
    }
    await _saveImportedIndex();
    notifyListeners();
  }

  /// Where a downloaded song came from, or null for built-in songs.
  String? sourceOf(String id) => _sourceOf[id];

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
            final m = (s as Map).cast<String, dynamic>();
            final info = SongInfo.fromJson(m);
            final source = (m['source'] as String?) ?? baseUrl;
            if (await File('${dir.path}/${_fileName(info, source)}').exists()) {
              _downloaded[info.id] = info;
              _sourceOf[info.id] = source;
            }
          }
        }
      } catch (e) {
        debugPrint('Song cache unreadable, ignoring it: $e');
      }
      await _loadImported();
    }
    notifyListeners();
  }

  String _fileName(SongInfo info, String source) {
    final f = info.file ?? '${info.id}.json';
    // Never let a catalog entry write outside the cache folder.
    final safe = f.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    // Songs from the main source keep their plain name (as in older versions).
    return source == baseUrl ? safe : 's${_hash(source)}_$safe';
  }

  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in utf8.encode(s)) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  Future<Song> loadSong(String id) async {
    final cached = _songCache[id];
    if (cached != null) return cached;
    String text;
    final downloaded = _downloaded[id];
    final bundled = _bundled[id];
    if (_imported.containsKey(id) && _importDir != null) {
      text = await File('${_importDir!.path}/${_importedFile(id)}').readAsString();
    } else if (downloaded != null && _dir != null && (bundled == null || downloaded.version > bundled.version)) {
      text = await File('${_dir!.path}/${_fileName(downloaded, _sourceOf[id] ?? baseUrl)}').readAsString();
    } else if (bundled != null) {
      text = await _bundle.loadString('$_assetDir${bundled.file ?? '$id.json'}', cache: false);
    } else {
      throw StateError('Unknown song $id');
    }
    final song = Song.fromJson(jsonDecode(text) as Map<String, dynamic>);
    _songCache[id] = song;
    return song;
  }

  Future<List<SongInfo>?> _fetchIndex(String source) async {
    try {
      final res = await _client.get(Uri.parse('${source}index.json')).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final index = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return [for (final s in (index['songs'] as List)) SongInfo.fromJson((s as Map).cast<String, dynamic>())];
    } catch (e) {
      debugPrint('Could not read $source: $e');
      return null;
    }
  }

  /// Checks that [source] (as typed) has a song list. Returns the folder URL
  /// and how many songs it lists, or null when nothing is there.
  Future<(String, int)?> checkSource(String source) async {
    final url = normalizeSongSource(source);
    if (Uri.tryParse(url)?.host.isEmpty ?? true) return null;
    final songs = await _fetchIndex(url);
    return songs == null ? null : (url, songs.length);
  }

  /// Downloads the online catalogs and any new or updated songs, and drops
  /// downloaded songs their source no longer lists.
  Future<(RefreshResult, int)> refresh() async {
    if (refreshing) return (RefreshResult.upToDate, 0);
    refreshing = true;
    notifyListeners();
    try {
      final dir = _dir;
      final wanted = <String, (SongInfo, String)>{};
      final reached = <String>{};
      for (final source in _sources) {
        final remote = await _fetchIndex(source);
        if (remote == null) continue;
        reached.add(source);
        for (final info in remote) {
          wanted.putIfAbsent(info.id, () => (info, source));
        }
        try {
          final chordRes = await _client.get(Uri.parse('${source}chords.json')).timeout(const Duration(seconds: 15));
          if (chordRes.statusCode == 200) {
            final body = utf8.decode(chordRes.bodyBytes);
            chords.addAll(ChordLibrary.fromJson(jsonDecode(body) as Map<String, dynamic>));
            if (dir != null && source == baseUrl) {
              await dir.create(recursive: true);
              await File('${dir.path}/chords.json').writeAsString(body);
            }
          }
        } catch (e) {
          debugPrint('No chords from $source: $e');
        }
      }
      if (reached.isEmpty) return (RefreshResult.offline, 0);

      // Songs whose source was removed, or that a source we reached no longer lists.
      var removed = 0;
      for (final id in _downloaded.keys.toList()) {
        final source = _sourceOf[id] ?? baseUrl;
        final stillListed = wanted[id]?.$2 == source;
        if (!stillListed && (reached.contains(source) || !_sources.contains(source) || wanted.containsKey(id))) {
          if (dir != null) {
            final f = File('${dir.path}/${_fileName(_downloaded[id]!, source)}');
            if (await f.exists()) await f.delete();
          }
          _downloaded.remove(id);
          _sourceOf.remove(id);
          _songCache.remove(id);
          if (!_bundled.containsKey(id)) removed++;
        }
      }

      var added = 0;
      for (final (info, source) in wanted.values) {
        final have = _downloaded[info.id] ?? _bundled[info.id];
        if (have != null && have.version >= info.version) continue;
        try {
          final res = await _client
              .get(Uri.parse('$source${Uri.encodeComponent(info.file ?? '${info.id}.json')}'))
              .timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) continue;
          final body = utf8.decode(res.bodyBytes);
          final song = Song.fromJson(jsonDecode(body) as Map<String, dynamic>); // validates it
          if (dir != null) {
            await dir.create(recursive: true);
            await File('${dir.path}/${_fileName(info, source)}').writeAsString(body);
          }
          if (!_bundled.containsKey(info.id) && !_downloaded.containsKey(info.id)) added++;
          _downloaded[info.id] = info;
          _sourceOf[info.id] = source;
          _songCache[info.id] = song;
        } catch (e) {
          debugPrint('Could not download ${info.id} from $source: $e');
        }
      }
      if (dir != null) {
        await dir.create(recursive: true);
        await File('${dir.path}/index.json').writeAsString(jsonEncode({
          'version': 1,
          'songs': [
            for (final s in _downloaded.values) {...s.toJson(), 'source': _sourceOf[s.id] ?? baseUrl},
          ],
        }));
      }
      if (removed > 0) debugPrint('Removed $removed songs that are no longer offered');
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
