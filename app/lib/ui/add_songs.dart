import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import '../app.dart';
import '../data/song_repository.dart';
import '../l10n/strings.dart';

/// Asks the user for song files. Null when nothing was chosen.
typedef SongFilePicker = Future<List<ImportFile>?> Function();

/// The device's file chooser, with several files allowed at once.
Future<List<ImportFile>?> pickSongFilesFromDevice() async {
  final result = await fp.FilePicker.platform.pickFiles(
    allowMultiple: true,
    withData: true,
    type: fp.FileType.any,
  );
  if (result == null) return null;
  final files = <ImportFile>[];
  for (final f in result.files) {
    var bytes = f.bytes;
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes != null) files.add(ImportFile(name: f.name, bytes: bytes));
  }
  return files;
}

/// Lets the user pick tab files and adds them to "My songs", then says
/// how it went: a short message when every file was read, a list of the
/// files that could not be read otherwise.
Future<void> addSongsFlow(BuildContext context) async {
  final t = Strings.of(context);
  final services = AppServices.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final rootNavigator = Navigator.of(context, rootNavigator: true);

  List<ImportFile>? files;
  try {
    files = await services.pickFiles();
  } catch (e) {
    debugPrint('File picker: $e');
    messenger.showSnackBar(SnackBar(content: Text(t.filePickerUnavailable)));
    return;
  }
  if (files == null || files.isEmpty || !context.mounted) return;

  // ignore: unawaited_futures
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 20),
          Expanded(child: Text(t.readingFiles(files!.length), style: const TextStyle(fontSize: 18))),
        ]),
      ),
    ),
  );
  List<ImportOutcome> outcomes;
  try {
    outcomes = await services.songs.importFiles(files);
  } finally {
    rootNavigator.pop();
  }
  final added = outcomes.where((o) => o.ok).length;
  final failed = outcomes.where((o) => !o.ok).toList();
  if (failed.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(t.songsAdded(added))));
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(added > 0 ? t.songsAdded(added) : t.filesNotRead(failed.length)),
      content: SizedBox(
        width: 480,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (added > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(t.filesNotRead(failed.length), style: Theme.of(context).textTheme.titleMedium),
              ),
            for (final f in failed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.error_outline_rounded),
                title: Text(f.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.fileError(f.errorCode)),
              ),
          ],
        ),
      ),
      actions: [FilledButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: Text(t.ok))],
    ),
  );
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
