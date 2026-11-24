/// The phone side: finds a device that shows the "Send songs from a phone"
/// screen on the same Wi-Fi network and uploads song files to it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../import/score.dart' show ImportError;
import 'song_receiver.dart';

/// A device ready to receive songs.
class Receiver {
  const Receiver({required this.host, required this.port, required this.code, this.name = ''});
  final String host;
  final int port;
  final String code;

  /// The name the device shows, when it was found on the network.
  final String name;

  Uri get pageUrl => Uri(scheme: 'http', host: host, port: port, path: '/$code');
  Uri uploadUrl(String fileName) => Uri(scheme: 'http', host: host, port: port, path: '/$code/upload', queryParameters: {'name': fileName});

  /// The address as shown on the receiving screen.
  String get address => pageUrl.toString();

  /// Reads an address typed by hand: the link from the TV screen, or
  /// "192.168.1.5:8765/1234". Null when it is not a receiver address.
  static Receiver? parse(String text) {
    var s = text.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;
    final code = uri.pathSegments.where((p) => p.isNotEmpty).firstOrNull;
    if (code == null || !RegExp(r'^\d{4}$').hasMatch(code)) return null;
    return Receiver(host: uri.host, port: uri.hasPort ? uri.port : defaultReceivePort, code: code);
  }

  @override
  bool operator ==(Object other) => other is Receiver && other.host == host && other.port == port && other.code == code;

  @override
  int get hashCode => Object.hash(host, port, code);
}

/// Asks the local network who can receive songs, for [timeout].
/// Devices answer while their receiving screen is open.
Future<List<Receiver>> findReceivers({
  Duration timeout = const Duration(seconds: 2),
  @visibleForTesting List<InternetAddress>? targets,
  @visibleForTesting int port = discoveryPort,
}) async {
  final found = <Receiver>[];
  RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  } catch (e) {
    debugPrint('Discovery socket: $e');
    return found;
  }
  try {
    socket.broadcastEnabled = true;
    final done = Completer<void>();
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = socket.receive();
      if (d == null) return;
      try {
        final text = utf8.decode(d.data);
        if (!text.startsWith(discoveryAnswer)) return;
        final j = jsonDecode(text.substring(discoveryAnswer.length)) as Map<String, dynamic>;
        if (j['app'] != 'guitar_learn' || j['port'] is! int || j['code'] is! String) return;
        final r = Receiver(host: d.address.address, port: j['port'] as int, code: j['code'] as String, name: (j['name'] as String?) ?? '');
        if (!found.contains(r)) found.add(r);
      } catch (_) {}
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    });
    final question = utf8.encode(discoveryQuestion);
    // Ask twice: a broadcast packet is sometimes lost on Wi-Fi.
    for (var i = 0; i < 2; i++) {
      for (final target in targets ?? [InternetAddress('255.255.255.255')]) {
        try {
          socket.send(question, target, port);
        } catch (e) {
          debugPrint('Discovery send: $e');
        }
      }
      await Future.any([done.future, Future<void>.delayed(timeout ~/ 2)]);
    }
  } finally {
    socket.close();
  }
  return found;
}

/// A file to send: read only when its turn comes.
class OutgoingFile {
  const OutgoingFile({required this.name, required this.read});
  final String name;
  final Future<Uint8List> Function() read;
}

/// What the receiver said about one file.
class SendResult {
  const SendResult({required this.name, required this.ok, this.alreadyAdded = false, this.title, this.error});
  final String name;
  final bool ok;
  final bool alreadyAdded;
  final String? title;

  /// Why it was not added; null when it was, [ImportError.damaged] when the
  /// receiver could not be reached.
  final ImportError? error;

  /// Set when the receiver did not answer at all.
  bool get unreachable => !ok && error == null;
}

/// Progress of a [sendSongs] call.
class SendProgress extends ChangeNotifier {
  SendProgress(this.total);
  final int total;
  final List<SendResult> results = [];
  bool stopped = false;
  String? current;

  void started(String name) {
    current = name;
    notifyListeners();
  }

  void finished(SendResult result) {
    results.add(result);
    current = null;
    notifyListeners();
  }

  void stop() {
    stopped = true;
    notifyListeners();
  }
}

/// Uploads [files] to [receiver] one by one and reports what became of each.
Future<List<SendResult>> sendSongs(Receiver receiver, List<OutgoingFile> files, {SendProgress? progress, http.Client? client}) async {
  final c = client ?? http.Client();
  final results = progress?.results ?? <SendResult>[];
  try {
    for (final f in files) {
      if (progress?.stopped ?? false) break;
      progress?.started(f.name);
      SendResult result;
      try {
        final bytes = await f.read();
        final res = await c.put(receiver.uploadUrl(f.name), body: bytes).timeout(const Duration(minutes: 2));
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        result = SendResult(
          name: f.name,
          ok: j['ok'] == true,
          alreadyAdded: j['alreadyAdded'] == true,
          title: j['title'] as String?,
          error: j['ok'] == true ? null : ImportError.values.where((e) => e.name == j['error']).firstOrNull ?? ImportError.damaged,
        );
      } catch (e) {
        debugPrint('Sending ${f.name}: $e');
        result = SendResult(name: f.name, ok: false);
      }
      if (progress != null) {
        progress.finished(result);
      } else {
        results.add(result);
      }
      if (result.unreachable) break; // no point in trying the rest: the TV is gone
    }
    return results;
  } finally {
    if (client == null) c.close();
  }
}
