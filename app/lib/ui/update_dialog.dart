import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/strings.dart';
import '../update/app_update.dart';

/// Offers to install [update]: an Update button downloads it with a progress
/// bar and opens the Android installer. Works with a TV remote: the Update
/// button has focus when the dialog opens.
Future<void> showUpdateDialog(BuildContext context, AppUpdate update) {
  return showDialog<void>(
    context: context,
    builder: (_) => _UpdateDialog(update: update, updater: AppServices.of(context).updater),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update, required this.updater});

  final AppUpdate update;
  final AppUpdater updater;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  bool _failed = false;

  Future<void> _install() async {
    setState(() {
      _downloading = true;
      _failed = false;
      _progress = 0;
    });
    final ok = await widget.updater.install(widget.update, onProgress: (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (!mounted) return;
    if (ok) {
      // The Android installer is now on top; nothing more to do here.
      Navigator.of(context).pop();
    } else {
      setState(() {
        _downloading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return AlertDialog(
      title: Text(t.updateAvailable(widget.update.build)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_downloading ? t.downloadingUpdate : t.updateHint, style: const TextStyle(fontSize: 16)),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 8),
            const SizedBox(height: 8),
            Text('${(_progress * 100).round()}%', textAlign: TextAlign.center),
          ],
          if (_failed) ...[
            const SizedBox(height: 12),
            Text(t.updateFailed, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 16)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _downloading ? null : () => Navigator.of(context).pop(), child: Text(t.later)),
        FilledButton.icon(
          autofocus: true,
          onPressed: _downloading ? null : _install,
          icon: const Icon(Icons.system_update_rounded),
          label: Text(t.updateNow),
        ),
      ],
    );
  }
}

/// A card at the top of the home screen when a newer build was found.
///
/// With a TV remote the Update button takes the focus as soon as the card
/// appears (the check finishes a moment after the app starts), so the card
/// cannot be missed and does not have to be reached with the arrows.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, required this.update, required this.onDismiss});

  final AppUpdate update;
  final VoidCallback onDismiss;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  final _updateButton = FocusNode(debugLabel: 'update now');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only while the home screen is the one on the screen: a song that is
      // open must keep the remote's focus.
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) _updateButton.requestFocus();
    });
  }

  @override
  void dispose() {
    _updateButton.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final update = widget.update;
    // The whole card is one big button for the remote (it spans the width,
    // so Up from the search box always finds it); the Update button inside
    // is for a finger. "Later" sits beside it as a second stop.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(children: [
        Expanded(
          child: Material(
            color: scheme.primaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              focusNode: _updateButton,
              onTap: () => showUpdateDialog(context, update),
              focusColor: Colors.white.withValues(alpha: 0.22),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.system_update_rounded, color: scheme.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Text(t.updateAvailable(update.build),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer)),
                    ]),
                    ExcludeFocus(
                      child: FilledButton(
                        onPressed: () => showUpdateDialog(context, update),
                        child: Text(t.updateNow),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        TextButton(onPressed: widget.onDismiss, child: Text(t.later)),
      ]),
    );
  }
}
