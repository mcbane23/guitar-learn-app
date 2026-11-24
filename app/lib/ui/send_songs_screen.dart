import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/strings.dart';
import '../share/song_sender.dart';
import 'add_songs.dart';

/// Finder for a receiver.
typedef ReceiverFinder = Future<List<Receiver>> Function();

/// Phone side: find the TV that shows the "Send songs from a phone" screen,
/// choose what to send, send it and show what the TV said.
class SendSongsScreen extends StatefulWidget {
  const SendSongsScreen({super.key, this.finder = findReceivers});

  /// How receivers are looked up on the network (replaced in tests).
  final ReceiverFinder finder;

  @override
  State<SendSongsScreen> createState() => _SendSongsScreenState();
}

enum _Stage { find, choose, sending, done }

class _SendSongsScreenState extends State<SendSongsScreen> {
  _Stage _stage = _Stage.find;
  bool _searching = false;
  List<Receiver> _found = const [];
  Receiver? _receiver;
  final _address = TextEditingController();
  bool _badAddress = false;
  SendProgress? _progress;
  List<SendResult> _results = const [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final found = await widget.finder();
    if (!mounted) return;
    setState(() {
      _found = found;
      _searching = false;
    });
  }

  void _pick(Receiver r) => setState(() {
        _receiver = r;
        _stage = _Stage.choose;
      });

  void _connectTyped() {
    final r = Receiver.parse(_address.text);
    if (r == null) {
      setState(() => _badAddress = true);
      return;
    }
    _pick(r);
  }

  Future<void> _sendMySongs() async {
    final services = AppServices.of(context);
    final t = Strings.of(context);
    final mine = services.songs.importedSongs;
    final files = [
      for (final s in mine)
        OutgoingFile(
          name: s.fileName ?? '${s.titleFor('en')}.json',
          read: () async => (await services.songs.importedSongBytes(s.id))!,
        ),
    ];
    // The TV reads the stored song file (JSON) and keeps the original file name.
    await _send(files, t);
  }

  Future<void> _sendFiles() async {
    final services = AppServices.of(context);
    final t = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    PickedSongs? picked;
    try {
      picked = await services.pickFiles();
    } catch (e) {
      debugPrint('Picker: $e');
      messenger.showSnackBar(SnackBar(content: Text(t.filePickerUnavailable)));
      return;
    }
    if (picked == null || picked.files.isEmpty || !mounted) return;
    await _send([for (final f in picked.files) OutgoingFile(name: f.name, read: f.read)], t);
  }

  Future<void> _send(List<OutgoingFile> files, Strings t) async {
    final progress = SendProgress(files.length);
    setState(() {
      _progress = progress;
      _total = files.length;
      _stage = _Stage.sending;
    });
    final results = await sendSongs(_receiver!, files, progress: progress);
    if (!mounted) return;
    setState(() {
      _results = results;
      _stage = _Stage.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.sendToTv)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: switch (_stage) {
                _Stage.find => _find(t),
                _Stage.choose => _choose(t),
                _Stage.sending => _sending(t),
                _Stage.done => _done(t),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _find(Strings t) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(children: [
      if (_searching)
        Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Expanded(child: Text(t.searchingDevices, style: const TextStyle(fontSize: 18))),
        ])
      else if (_found.isEmpty)
        Text(t.noDevicesFound, style: const TextStyle(fontSize: 18))
      else ...[
        Text(t.devicesFound, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.primary)),
        const SizedBox(height: 8),
        for (final (i, r) in _found.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OptionTile(
              autofocus: i == 0,
              icon: Icons.tv_rounded,
              title: r.name.isEmpty ? r.host : r.name,
              hint: r.address,
              onTap: () => _pick(r),
            ),
          ),
      ],
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(onPressed: _searching ? null : _search, icon: const Icon(Icons.refresh_rounded), label: Text(t.searchAgain)),
      ),
      const Divider(height: 40),
      TextField(
        controller: _address,
        keyboardType: TextInputType.url,
        autocorrect: false,
        onSubmitted: (_) => _connectTyped(),
        onChanged: (_) {
          if (_badAddress) setState(() => _badAddress = false);
        },
        decoration: InputDecoration(
          labelText: t.enterAddress,
          hintText: 'http://192.168.1.5:8765/1234',
          errorText: _badAddress ? t.invalidAddress : null,
          suffixIcon: IconButton(tooltip: t.connect, icon: const Icon(Icons.arrow_forward_rounded), onPressed: _connectTyped),
        ),
      ),
    ]);
  }

  Widget _choose(Strings t) {
    final mine = AppServices.of(context).songs.importedSongs;
    final r = _receiver!;
    return ListView(children: [
      Text('${t.sendingTo}: ${r.name.isEmpty ? r.address : r.name}', style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 16),
      Text(t.whatToSend, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 8),
      OptionTile(
        autofocus: true,
        icon: Icons.library_music_rounded,
        title: t.sendMySongs(mine.length),
        hint: mine.isEmpty ? t.noMySongs : t.sendMySongsHint,
        onTap: mine.isEmpty ? null : _sendMySongs,
      ),
      const SizedBox(height: 12),
      OptionTile(icon: Icons.file_open_rounded, title: t.sendFiles, hint: t.sendFilesHint, onTap: _sendFiles),
    ]);
  }

  Widget _sending(Strings t) {
    final progress = _progress!;
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) => Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.sendingProgress(progress.results.length, _total), style: const TextStyle(fontSize: 20)),
        if (progress.current != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(progress.current!, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: _total == 0 ? null : progress.results.length / _total, minHeight: 8),
        const SizedBox(height: 24),
        if (_total > 1)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(autofocus: true, onPressed: progress.stopped ? null : progress.stop, child: Text(t.stop)),
          ),
      ]),
    );
  }

  Widget _done(Strings t) {
    final scheme = Theme.of(context).colorScheme;
    final sent = _results.where((r) => r.ok && !r.alreadyAdded).length;
    final already = _results.where((r) => r.ok && r.alreadyAdded).length;
    final failed = _results.where((r) => !r.ok && !r.unreachable).toList();
    final unreachable = _results.any((r) => r.unreachable);
    final notSent = _total - _results.length + (unreachable ? 1 : 0);
    Widget line(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 18))),
          ]),
        );
    return ListView(children: [
      Text(t.sendDone, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      if (unreachable) line(Icons.wifi_off_rounded, scheme.error, t.deviceUnreachable),
      line(Icons.check_circle_rounded, Colors.green, t.resultSent(sent)),
      if (already > 0) line(Icons.library_music_rounded, scheme.primary, t.resultAlreadyOnTv(already)),
      if (failed.isNotEmpty) line(Icons.error_rounded, scheme.error, t.resultFailed(failed.length)),
      if (notSent > 0) line(Icons.pause_circle_rounded, scheme.onSurfaceVariant, t.resultStopped(notSent)),
      for (final f in failed)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.error_outline_rounded, color: scheme.error),
          title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(t.fileError(f.error)),
        ),
      const SizedBox(height: 24),
      Row(children: [
        FilledButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: Text(t.done)),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: () => setState(() => _stage = unreachable ? _Stage.find : _Stage.choose),
          child: Text(t.sendMore),
        ),
      ]),
    ]);
  }
}
