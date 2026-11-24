import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../settings/settings.dart';
import 'themes.dart';

import '../app.dart';
import '../l10n/strings.dart';
import '../share/song_receiver.dart';

/// Full-screen QR code and address a phone uses to send song files here.
/// The server runs only while this screen is open.
class ReceiveSongsScreen extends StatefulWidget {
  const ReceiveSongsScreen({super.key, this.receiver});

  /// A receiver to show (tests); otherwise one is started for the songs of the app.
  final SongReceiver? receiver;

  @override
  State<ReceiveSongsScreen> createState() => _ReceiveSongsScreenState();
}

class _ReceiveSongsScreenState extends State<ReceiveSongsScreen> {
  SongReceiver? _receiver;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_receiver != null) return;
    final t = Strings.of(context);
    final r = widget.receiver ??
        SongReceiver(
          AppServices.of(context).songs,
          deviceName: t.appTitle,
          uploadPageLanguage: t.language == AppLanguage.en ? 'en' : (t.language == AppLanguage.srCyrl ? 'sr-Cyrl' : 'sr'),
        );
    _receiver = r;
    if (!r.running) r.start();
  }

  @override
  void dispose() {
    final r = _receiver;
    if (r != null && widget.receiver == null) r.stop().then((_) => r.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final r = _receiver!;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(t.receiveSongs)),
      body: AppBackground(
        theme: SettingsScope.of(context).colorTheme,
        child: SafeArea(
        child: ListenableBuilder(
          listenable: r,
          builder: (context, _) => LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth > 760;
              final qrSize = wide ? (box.maxHeight * 0.6).clamp(200.0, 420.0) : (box.maxWidth * 0.6).clamp(160.0, 320.0);
              final qr = _QrPanel(receiver: r, size: qrSize);
              final steps = _Steps(receiver: r);
              final files = _ReceivedList(receiver: r);
              final done = Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FilledButton.icon(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(t.done),
                ),
              );
              if (wide) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Column(mainAxisAlignment: MainAxisAlignment.center, children: [qr]),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        steps,
                        const SizedBox(height: 16),
                        Expanded(child: files),
                        done,
                      ]),
                    ),
                  ]),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, kToolbarHeight + 12, 20, 20),
                children: [Center(child: qr), const SizedBox(height: 20), steps, const SizedBox(height: 16), files, done],
              );
            },
          ),
        ),
        ),
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  const _QrPanel({required this.receiver, required this.size});
  final SongReceiver receiver;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final url = receiver.url;
    Widget inner;
    if (!receiver.running) {
      inner = receiver.error != null
          ? Padding(padding: const EdgeInsets.all(24), child: Text(t.receiveFailed, textAlign: TextAlign.center))
          : const Center(child: CircularProgressIndicator());
    } else if (url == null || receiver.addresses.isEmpty) {
      inner = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.black54),
          const SizedBox(height: 12),
          Text(t.receiveNoNetwork, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87, fontSize: 18)),
        ]),
      );
    } else {
      inner = QrImageView(
        data: url,
        version: QrVersions.auto,
        padding: const EdgeInsets.all(20),
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: inner,
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.receiver});
  final SongReceiver receiver;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 15, backgroundColor: scheme.primary, child: Text('$n', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800))),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 18))),
          ]),
        );
    final url = receiver.addresses.isEmpty ? null : receiver.url;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      step(1, t.receiveStep1),
      step(2, t.receiveStep2),
      if (url != null)
        Padding(
          padding: const EdgeInsets.only(left: 42, bottom: 12),
          child: SelectableText(url, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: scheme.primary, fontFamily: 'monospace')),
        ),
      step(3, t.receiveStep3),
    ]);
  }
}

class _ReceivedList extends StatelessWidget {
  const _ReceivedList({required this.receiver});
  final SongReceiver receiver;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final files = receiver.received.reversed.toList();
    if (files.isEmpty) {
      return Row(children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Text(t.waitingForPhone, style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t.receivedFiles, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.primary)),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final f in files)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: !f.done
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                    : f.outcome!.ok
                        ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                        : Icon(Icons.error_rounded, color: scheme.error),
                title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17)),
                subtitle: Text(!f.done
                    ? t.receiving
                    : f.outcome!.ok
                        ? (f.outcome!.alreadyAdded ? t.resultAlreadyAdded(1) : t.songsAdded(1))
                        : t.fileError(f.outcome!.errorCode)),
              ),
          ],
        ),
      ),
    ]);
  }
}
