import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../data/song_repository.dart';
import '../import/score.dart' show ImportError;
import '../l10n/strings.dart';

/// One song file the user chose. It is read only when its turn comes, so a
/// big folder never has to fit in memory at once.
class PickedFile {
  const PickedFile({required this.name, required this.read, this.size});

  /// Simple bytes, mostly for tests.
  PickedFile.bytes(ImportFile file)
      : name = file.name,
        size = file.bytes.length,
        read = (() async => file.bytes);

  /// The file name; for a folder, the path inside it ("Rock/song.gp5").
  final String name;

  /// Size in bytes, when the device knows it.
  final int? size;
  final Future<Uint8List> Function() read;
}

/// What the user chose: some files, or the song files of a folder.
class PickedSongs {
  const PickedSongs({required this.files, this.folderName, this.otherFiles = 0, this.limit});

  PickedSongs.ofFiles(List<ImportFile> files) : this(files: [for (final f in files) PickedFile.bytes(f)]);

  final List<PickedFile> files;

  /// Set when a folder was chosen.
  final String? folderName;

  /// Files in the folder that are not song files (pictures, ...), left out.
  final int otherFiles;

  /// Set when the folder had more song files than this; only the first ones are read.
  final int? limit;

  bool get isFolder => folderName != null;
}

/// Asks the user for song files or a folder. Null when nothing was chosen.
typedef SongFilePicker = Future<PickedSongs?> Function();

/// Thrown by a picker when this device has no file or folder chooser.
class PickerUnavailable implements Exception {
  const PickerUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The device's file chooser, with several files allowed at once.
Future<PickedSongs?> pickSongFilesFromDevice() async {
  final result = await fp.FilePicker.platform.pickFiles(
    allowMultiple: true,
    withData: false,
    type: fp.FileType.any,
  );
  if (result == null) return null;
  return PickedSongs(files: [
    for (final f in result.files)
      if (f.bytes != null || f.path != null)
        PickedFile(
          name: f.name,
          size: f.size,
          read: () async => f.bytes ?? await File(f.path!).readAsBytes(),
        ),
  ]);
}

const _filesChannel = MethodChannel('guitar_learn/files');

/// The device's folder chooser. Lists the song files in the folder and its
/// subfolders (see SongFolders.kt); each one is read when it is imported.
Future<PickedSongs?> pickSongFolderFromDevice() async {
  Map<Object?, Object?>? listing;
  try {
    listing = await _filesChannel.invokeMapMethod<Object?, Object?>('pickFolder', {'extensions': supportedExtensions});
  } on PlatformException catch (e) {
    if (e.code == 'unavailable') throw PickerUnavailable(e.message ?? e.code);
    rethrow;
  } on MissingPluginException catch (e) {
    throw PickerUnavailable(e.message ?? 'No folder chooser');
  }
  if (listing == null) return null;
  final files = [
    for (final f in (listing['files'] as List? ?? const []).cast<Map<Object?, Object?>>())
      PickedFile(
        name: f['name'] as String,
        size: (f['size'] as num?)?.toInt(),
        read: () async => (await _filesChannel.invokeMethod<Uint8List>('readFile', {'uri': f['uri']}))!,
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return PickedSongs(
    files: files,
    folderName: listing['folder'] as String? ?? '',
    otherFiles: (listing['otherFiles'] as num?)?.toInt() ?? 0,
    limit: listing['tooMany'] == true ? (listing['limit'] as num?)?.toInt() : null,
  );
}

/// How the user wants to add songs.
enum _AddKind { files, folder }

/// Asks whether to add some files or a whole folder, then adds them to
/// "My songs" and shows what happened to every file.
Future<void> addSongsFlow(BuildContext context) async {
  final t = Strings.of(context);
  final services = AppServices.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final kind = await showDialog<_AddKind>(context: context, builder: (_) => const _AddKindDialog());
  if (kind == null || !context.mounted) return;

  PickedSongs? picked;
  try {
    picked = await (kind == _AddKind.files ? services.pickFiles() : services.pickFolder());
  } catch (e) {
    debugPrint('Picker: $e');
    messenger.showSnackBar(SnackBar(content: Text(kind == _AddKind.files ? t.filePickerUnavailable : t.folderPickerUnavailable)));
    return;
  }
  if (picked == null || !context.mounted) return;
  if (picked.files.isEmpty) {
    if (picked.isFolder) {
      await showDialog<void>(context: context, builder: (_) => _ResultDialog(picked: picked!, outcomes: const [], notRead: 0));
    }
    return;
  }

  final progress = ImportProgress(picked.files.length);
  // ignore: unawaited_futures
  final progressDialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(progress: progress),
  );
  final outcomes = await importPicked(services.songs, picked.files, progress);
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  await progressDialog;
  if (!context.mounted) return;

  final notRead = picked.files.length - outcomes.length;
  final ok = outcomes.where((o) => o.ok).length;
  // One file that worked: a short message is enough.
  if (!picked.isFolder && outcomes.length == 1 && ok == 1 && notRead == 0) {
    messenger.showSnackBar(SnackBar(content: Text(t.songsAdded(1))));
    return;
  }
  await showDialog<void>(context: context, builder: (_) => _ResultDialog(picked: picked!, outcomes: outcomes, notRead: notRead));
}

/// How far an import has come; the user can stop it between batches.
class ImportProgress extends ChangeNotifier {
  ImportProgress(this.total);
  final int total;
  int done = 0;
  bool stopped = false;

  void advance(int n) {
    done += n;
    notifyListeners();
  }

  void stop() {
    stopped = true;
    notifyListeners();
  }
}

/// Files are read and imported a few at a time.
const _batchFiles = 10;
const _batchBytes = 8 * 1024 * 1024;
const _maxFileBytes = 50 * 1024 * 1024;

/// Reads and imports [files] in small batches. Stops early when
/// [progress] is stopped; the files after that get no outcome.
@visibleForTesting
Future<List<ImportOutcome>> importPicked(SongRepository songs, List<PickedFile> files, [ImportProgress? progress]) async {
  final outcomes = <ImportOutcome>[];
  var i = 0;
  while (i < files.length && !(progress?.stopped ?? false)) {
    final batch = <ImportFile>[];
    final slots = <int, ImportOutcome>{}; // files that failed before importing, by position in the batch
    var bytes = 0;
    final start = outcomes.length;
    var count = 0;
    while (i < files.length && count < _batchFiles && bytes < _batchBytes) {
      final f = files[i++];
      final position = count++;
      if ((f.size ?? 0) > _maxFileBytes) {
        slots[position] = ImportOutcome(fileName: f.name, error: 'The file is too large', errorCode: ImportError.tooLarge);
        continue;
      }
      try {
        final data = await f.read();
        bytes += data.length;
        batch.add(ImportFile(name: f.name, bytes: data));
      } catch (e) {
        debugPrint('Reading ${f.name}: $e');
        slots[position] = ImportOutcome(fileName: f.name, error: 'Could not read this file', errorCode: ImportError.damaged);
      }
    }
    final imported = (await songs.importFiles(batch)).iterator;
    for (var p = 0; p < count; p++) {
      final failed = slots[p];
      if (failed != null) {
        outcomes.add(failed);
      } else {
        imported.moveNext();
        outcomes.add(imported.current);
      }
    }
    progress?.advance(outcomes.length - start);
  }
  return outcomes;
}

class _AddKindDialog extends StatelessWidget {
  const _AddKindDialog();

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    Widget option(_AddKind kind, IconData icon, String title, String hint, {bool autofocus = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _FocusTile(
            autofocus: autofocus,
            onTap: () => Navigator.of(context).pop(kind),
            child: Row(children: [
              Icon(icon, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(hint, style: Theme.of(context).textTheme.bodyMedium),
                ]),
              ),
            ]),
          ),
        );
    return AlertDialog(
      title: Text(t.addSongs),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            option(_AddKind.files, Icons.file_open_rounded, t.chooseFiles, t.chooseFilesHint, autofocus: true),
            option(_AddKind.folder, Icons.folder_open_rounded, t.chooseFolder, t.chooseFolderHint),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel))],
    );
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.progress});
  final ImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return PopScope(
      canPop: false,
      // The Back button of a remote stops the import instead of hiding it.
      onPopInvokedWithResult: (didPop, _) => progress.stop(),
      child: ListenableBuilder(
        listenable: progress,
        builder: (context, _) => AlertDialog(
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.readingFilesProgress(progress.done, progress.total), style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress.total == 0 ? null : progress.done / progress.total, minHeight: 8),
            ]),
          ),
          actions: [
            if (progress.total > 1)
              TextButton(
                autofocus: true,
                onPressed: progress.stopped ? null : progress.stop,
                child: Text(t.stop),
              ),
          ],
        ),
      ),
    );
  }
}

/// What happened to every file: how many were added, which could not be read and why.
class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.picked, required this.outcomes, required this.notRead});
  final PickedSongs picked;
  final List<ImportOutcome> outcomes;
  final int notRead;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final added = outcomes.where((o) => o.ok && !o.alreadyAdded).length;
    final already = outcomes.where((o) => o.ok && o.alreadyAdded).length;
    final failed = outcomes.where((o) => !o.ok).toList();

    Widget line(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 18))),
          ]),
        );

    final empty = picked.files.isEmpty;
    return AlertDialog(
      title: Text(empty ? t.noSongFilesInFolder : t.importDone),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (picked.isFolder && picked.folderName!.isNotEmpty)
              line(Icons.folder_rounded, scheme.onSurfaceVariant, picked.folderName!),
            if (!empty) line(Icons.check_circle_rounded, Colors.green, t.resultAdded(added)),
            if (already > 0) line(Icons.library_music_rounded, scheme.primary, t.resultAlreadyAdded(already)),
            if (failed.isNotEmpty) line(Icons.error_rounded, scheme.error, t.resultFailed(failed.length)),
            if (picked.otherFiles > 0) line(Icons.block_rounded, scheme.onSurfaceVariant, t.resultOtherFiles(picked.otherFiles)),
            if (picked.limit != null) line(Icons.info_rounded, scheme.onSurfaceVariant, t.resultTooMany(picked.limit!)),
            if (notRead > 0) line(Icons.pause_circle_rounded, scheme.onSurfaceVariant, t.resultStopped(notRead)),
            if (failed.isNotEmpty) const Divider(height: 24),
            // Each row can take the focus, so a TV remote scrolls the list with the arrows.
            for (final f in failed)
              _FocusTile(
                dense: true,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.error_outline_rounded, color: scheme.error),
                  title: Text(f.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(t.fileError(f.errorCode)),
                ),
              ),
          ],
        ),
      ),
      actions: [FilledButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: Text(t.ok))],
    );
  }
}

/// A row with a white outline when a TV remote selects it.
class _FocusTile extends StatefulWidget {
  const _FocusTile({required this.child, this.onTap, this.autofocus = false, this.dense = false});
  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool dense;

  @override
  State<_FocusTile> createState() => _FocusTileState();
}

class _FocusTileState extends State<_FocusTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: _focused ? Colors.white : Colors.transparent, width: 3),
    );
    final padding = EdgeInsets.symmetric(horizontal: widget.dense ? 8 : 16, vertical: widget.dense ? 0 : 14);
    if (widget.onTap == null) {
      return Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: DecoratedBox(decoration: ShapeDecoration(shape: shape), child: Padding(padding: padding, child: widget.child)),
      );
    }
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Padding(padding: padding, child: widget.child),
      ),
    );
  }
}

/// Asks before forgetting a song the user added from a file.
Future<void> removeImportedSongFlow(BuildContext context, String songId) async {
  final t = Strings.of(context);
  final songs = AppServices.of(context).songs;
  final messenger = ScaffoldMessenger.of(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.removeSong),
      content: Text(t.removeSongConfirm),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.cancel)),
        FilledButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(t.removeSongSource)),
      ],
    ),
  );
  if (yes != true) return;
  await songs.removeImported(songId);
  messenger.showSnackBar(SnackBar(content: Text(t.songRemoved)));
}
