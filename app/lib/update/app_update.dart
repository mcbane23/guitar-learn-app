import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Where the newest build is published. Every push to main releases the APK
/// under the same name, so this link always points at the newest build:
/// https://github.com/mcbane23/guitar-learn-app/releases/latest/download/guitar-learn.apk
/// version.json next to it holds the build number of that APK.
const defaultUpdateUrl = String.fromEnvironment(
  'UPDATE_URL',
  defaultValue: 'https://github.com/mcbane23/guitar-learn-app/releases/latest/download/',
);

/// A newer build of the app that can be installed.
class AppUpdate {
  const AppUpdate({required this.build, required this.apkUrl});

  /// The build number (Android versionCode) of the new APK.
  final int build;
  final String apkUrl;
}

/// Looks for a newer build of the app, downloads it and hands it to the
/// Android installer. Everything here is quiet about errors: an update is a
/// convenience, and the app must keep working when the Internet is down.
abstract class AppUpdater {
  /// The build number of the app that is running, or 0 if unknown.
  Future<int> currentBuild();

  /// The newest build published, or null when offline or when the running
  /// build is already the newest.
  Future<AppUpdate?> check();

  /// Downloads [update] and opens the installer. [onProgress] gets a number
  /// from 0 to 1 while the file downloads. Returns false when the download
  /// or the installer failed.
  Future<bool> install(AppUpdate update, {void Function(double progress)? onProgress});
}

/// An app without updates (tests and platforms without an installer).
class NoAppUpdater implements AppUpdater {
  const NoAppUpdater();

  @override
  Future<int> currentBuild() async => 0;

  @override
  Future<AppUpdate?> check() async => null;

  @override
  Future<bool> install(AppUpdate update, {void Function(double progress)? onProgress}) async => false;
}

/// Updates from GitHub Releases, installed through
/// android/.../AppUpdate.kt.
class GitHubAppUpdater implements AppUpdater {
  GitHubAppUpdater({http.Client? client, this.baseUrl = defaultUpdateUrl}) : _client = client ?? http.Client();

  static const _channel = MethodChannel('guitar_learn/update');

  final http.Client _client;
  final String baseUrl;
  int? _build;

  @override
  Future<int> currentBuild() async {
    if (_build != null) return _build!;
    try {
      _build = await _channel.invokeMethod<int>('versionCode') ?? 0;
    } on PlatformException {
      _build = 0;
    } on MissingPluginException {
      _build = 0;
    }
    return _build!;
  }

  @override
  Future<AppUpdate?> check() async {
    final current = await currentBuild();
    if (current <= 0) return null;
    try {
      final response = await _client.get(Uri.parse('${baseUrl}version.json')).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      final build = (json['build'] as num?)?.toInt() ?? 0;
      if (build <= current) return null;
      final apk = json['apk'] as String? ?? '${baseUrl}guitar-learn.apk';
      return AppUpdate(build: build, apkUrl: apk);
    } catch (e) {
      if (kDebugMode) debugPrint('update check: $e');
      return null;
    }
  }

  @override
  Future<bool> install(AppUpdate update, {void Function(double progress)? onProgress}) async {
    try {
      final dir = Directory('${(await getApplicationCacheDirectory()).path}/updates');
      await dir.create(recursive: true);
      final file = File('${dir.path}/guitar-learn.apk');
      final request = http.Request('GET', Uri.parse(update.apkUrl));
      final response = await _client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return false;
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) return false;
      onProgress?.call(1);
      return await _channel.invokeMethod<bool>('install', {'path': file.path}) ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('update install: $e');
      return false;
    }
  }
}
