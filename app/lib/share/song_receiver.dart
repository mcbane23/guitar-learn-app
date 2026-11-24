/// Receives song files from a phone on the same Wi-Fi network.
///
/// The TV (or any device) runs a small web server. A phone opens its address
/// in a browser, by scanning a QR code or typing it, and uploads song files
/// from a web page. The Guitar Learn app on a phone finds the server with a
/// UDP broadcast and uploads the same way, without the browser.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:flutter/foundation.dart';

import '../data/song_repository.dart';
import '../import/importer.dart' show extensionOf;
import '../import/score.dart' show ImportError;
import 'upload_page.dart';

/// The port the server tries first; the QR code carries the real one.
const defaultReceivePort = 8765;

/// The port the server listens on for phones looking for it.
const discoveryPort = 8766;

/// What a phone sends to find receivers, and the start of every answer.
const discoveryQuestion = 'GUITAR_LEARN_RECEIVER?';
const discoveryAnswer = 'GUITAR_LEARN_RECEIVER ';

/// Files bigger than this are refused before they are read.
const maxUploadBytes = 50 * 1024 * 1024;

/// One file a phone sent, and what became of it.
class ReceivedFile {
  ReceivedFile({required this.name, required this.from, this.outcome});
  final String name;

  /// Who sent it: the phone's address.
  final String from;
  ImportOutcome? outcome;

  bool get done => outcome != null;
}

/// A web server that adds the songs phones upload to [songs].
class SongReceiver extends ChangeNotifier {
  SongReceiver(
    this.songs, {
    this.deviceName = 'Guitar Learn',
    this.uploadPageLanguage = 'en',
    Random? random,
    @visibleForTesting this.bindAddress,
    @visibleForTesting int? port,
  })  : _random = random ?? Random.secure(),
        _preferredPort = port ?? defaultReceivePort;

  final SongRepository songs;

  /// Shown on phones when they find this device.
  final String deviceName;

  /// Language of the upload page when the phone's browser asks for none we have.
  final String uploadPageLanguage;
  final Random _random;
  final int _preferredPort;

  /// Where the server listens; every address of the device when null.
  final InternetAddress? bindAddress;

  HttpServer? _server;
  RawDatagramSocket? _discovery;

  /// A short code in every link, so only someone who sees the screen can send songs.
  late final String code = (1000 + _random.nextInt(9000)).toString();

  /// The port the server got, or null before [start].
  int? get port => _server?.port;

  /// The device's addresses on the local network, filled by [start].
  List<InternetAddress> addresses = const [];

  final List<ReceivedFile> received = [];

  /// Set when the server could not start; the message is for the log.
  String? error;

  bool get running => _server != null;

  /// The address a phone opens, for the first network address.
  String? get url => urlFor(addresses.isEmpty ? null : addresses.first);

  String? urlFor(InternetAddress? address) {
    final p = port;
    if (p == null) return null;
    final host = address?.address ?? bindAddress?.address ?? '127.0.0.1';
    return 'http://$host${p == 80 ? '' : ':$p'}/$code';
  }

  /// Starts the web server and the discovery listener. Safe to call twice.
  Future<void> start() async {
    if (_server != null) return;
    error = null;
    try {
      addresses = await localAddresses();
      final bind = bindAddress ?? InternetAddress.anyIPv4;
      HttpServer server;
      try {
        server = await HttpServer.bind(bind, _preferredPort);
      } on SocketException {
        server = await HttpServer.bind(bind, 0); // the usual port is busy: any port will do
      }
      _server = server;
      server.listen(_handle, onError: (Object e) => debugPrint('Receiver: $e'));
      await _startDiscovery(bind);
    } catch (e) {
      error = '$e';
      debugPrint('Receiver could not start: $e');
      await stop();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _discovery?.close();
    _discovery = null;
    final s = _server;
    _server = null;
    await s?.close(force: true);
    notifyListeners();
  }

  @override
  void dispose() {
    _discovery?.close();
    _server?.close(force: true);
    super.dispose();
  }

  /// Answers phones that broadcast [discoveryQuestion] with where to upload.
  Future<void> _startDiscovery(InternetAddress bind) async {
    try {
      final socket = await RawDatagramSocket.bind(bind, discoveryPort, reuseAddress: true, reusePort: !Platform.isAndroid && !Platform.isWindows);
      _discovery = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final d = socket.receive();
        if (d == null) return;
        String text;
        try {
          text = utf8.decode(d.data);
        } catch (_) {
          return;
        }
        if (!text.startsWith(discoveryQuestion)) return;
        socket.send(utf8.encode(discoveryAnswer + jsonEncode(describe())), d.address, d.port);
      });
    } catch (e) {
      // Without discovery the QR code still works.
      debugPrint('Discovery unavailable: $e');
    }
  }

  /// What phones learn about this receiver.
  Map<String, Object?> describe() => {'app': 'guitar_learn', 'name': deviceName, 'port': port, 'code': code};

  // Uploads are imported one at a time, in the order they arrive.
  Future<void> _queue = Future.value();

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      response.headers.set('Cache-Control', 'no-store');
      if (segments.isEmpty) {
        // No code: tell the person to look at the screen.
        _html(response, HttpStatus.ok, uploadPage(language: _pageLanguage(request), code: null, deviceName: deviceName));
        return;
      }
      if (segments.first == 'ping') {
        _json(response, HttpStatus.ok, {'app': 'guitar_learn', 'name': deviceName});
        return;
      }
      if (segments.first != code) {
        _html(response, HttpStatus.forbidden, uploadPage(language: _pageLanguage(request), code: null, deviceName: deviceName));
        return;
      }
      final action = segments.length > 1 ? segments[1] : '';
      if (action == '' && request.method == 'GET') {
        _html(response, HttpStatus.ok, uploadPage(language: _pageLanguage(request), code: code, deviceName: deviceName));
      } else if (action == 'upload' && (request.method == 'PUT' || request.method == 'POST')) {
        await _upload(request);
      } else if (action == 'status') {
        _json(response, HttpStatus.ok, {
          'files': [
            for (final f in received)
              {'name': f.name, 'ok': f.outcome?.ok, 'error': f.outcome?.errorCode?.name},
          ],
        });
      } else {
        _json(response, HttpStatus.notFound, {'error': 'not found'});
      }
    } catch (e, st) {
      debugPrint('Receiver request failed: $e\n$st');
      try {
        _json(response, HttpStatus.internalServerError, {'error': '$e'});
      } catch (_) {}
    }
  }

  String _pageLanguage(HttpRequest request) {
    final accept = request.headers.value(HttpHeaders.acceptLanguageHeader)?.toLowerCase() ?? '';
    for (final part in accept.split(',')) {
      final lang = part.trim().split(';').first;
      if (lang.startsWith('sr') || lang.startsWith('hr') || lang.startsWith('bs')) return lang.contains('cyrl') ? 'sr-Cyrl' : 'sr';
      if (lang.startsWith('en')) return 'en';
    }
    return uploadPageLanguage;
  }

  /// `PUT /<code>/upload?name=song.gp5` with the file as the body.
  Future<void> _upload(HttpRequest request) async {
    final response = request.response;
    final name = (request.uri.queryParameters['name'] ?? '').split('/').last.split('\\').last.trim();
    if (name.isEmpty) {
      _json(response, HttpStatus.badRequest, {'error': 'name missing'});
      return;
    }
    final length = request.contentLength;
    final from = request.connectionInfo?.remoteAddress.address ?? '?';
    final file = ReceivedFile(name: name, from: from);
    if (length > maxUploadBytes) {
      file.outcome = ImportOutcome(fileName: name, error: 'The file is too large', errorCode: ImportError.tooLarge);
      received.add(file);
      notifyListeners();
      _json(response, HttpStatus.requestEntityTooLarge, _outcomeJson(file.outcome!));
      return;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > maxUploadBytes) {
        file.outcome = ImportOutcome(fileName: name, error: 'The file is too large', errorCode: ImportError.tooLarge);
        received.add(file);
        notifyListeners();
        _json(response, HttpStatus.requestEntityTooLarge, _outcomeJson(file.outcome!));
        return;
      }
    }
    final outcome = await receive(name, builder.takeBytes(), from: from);
    _json(response, HttpStatus.ok, _outcomeJson(outcome));
  }

  /// Adds one received file to the songs, after the ones still being added.
  @visibleForTesting
  Future<ImportOutcome> receive(String name, Uint8List bytes, {String from = '?'}) async {
    final file = ReceivedFile(name: name, from: from);
    received.add(file);
    notifyListeners();
    final done = _queue.then((_) async {
      final outcomes = await songs.importFiles([ImportFile(name: name, bytes: bytes)]);
      file.outcome = outcomes.first;
    }).catchError((Object e) {
      debugPrint('Import of $name failed: $e');
      file.outcome = ImportOutcome(fileName: name, error: '$e', errorCode: ImportError.damaged);
    });
    _queue = done;
    await done;
    notifyListeners();
    return file.outcome!;
  }

  Map<String, Object?> _outcomeJson(ImportOutcome o) => {
        'name': o.fileName,
        'ok': o.ok,
        'alreadyAdded': o.alreadyAdded,
        'title': o.song == null ? null : _title(o.song!),
        'error': o.errorCode?.name,
        'extension': extensionOf(o.fileName),
      };

  static String? _title(Map<String, dynamic> song) {
    final t = song['title'];
    if (t is String) return t;
    if (t is Map) return (t['en'] ?? t.values.firstOrNull)?.toString();
    return null;
  }

  void _html(HttpResponse response, int status, String body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.html;
    response.write(body);
    response.close();
  }

  void _json(HttpResponse response, int status, Object body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    response.close();
  }

  /// The device's IPv4 addresses on local networks, Wi-Fi first.
  static Future<List<InternetAddress>> localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false, includeLoopback: false);
      int rank(NetworkInterface i) {
        final n = i.name.toLowerCase();
        if (n.startsWith('wlan') || n.startsWith('wifi') || n.startsWith('en') || n.startsWith('eth')) return 0;
        if (n.startsWith('rmnet') || n.startsWith('ccmni') || n.startsWith('tun') || n.startsWith('ppp')) return 2; // mobile data, VPN
        return 1;
      }
      final sorted = [...interfaces]..sort((a, b) => rank(a).compareTo(rank(b)));
      return [
        for (final i in sorted)
          for (final a in i.addresses)
            if (rank(i) < 2 && _isPrivate(a)) a,
      ];
    } catch (e) {
      debugPrint('Network interfaces unavailable: $e');
      return const [];
    }
  }

  static bool _isPrivate(InternetAddress a) {
    final b = a.rawAddress;
    if (b.length != 4) return false;
    return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254);
  }
}
