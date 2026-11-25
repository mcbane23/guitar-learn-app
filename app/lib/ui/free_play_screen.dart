import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../audio/synth.dart';
import '../l10n/strings.dart';
import '../music/pitch.dart';
import '../settings/settings.dart';
import 'common.dart';
import 'themes.dart';
import 'fretboard.dart';

/// Tap any fret to hear that note.
class FreePlayScreen extends StatefulWidget {
  const FreePlayScreen({super.key});

  @override
  State<FreePlayScreen> createState() => _FreePlayScreenState();
}

class _FreePlayScreenState extends State<FreePlayScreen> with SingleTickerProviderStateMixin, LandscapeScreen {
  /// Redraws the neck while a string still rings, then stops.
  late final Ticker _ticker;
  final _clock = Stopwatch()..start();

  /// How long a touched string glows.
  static const _ringSeconds = 1.5;

  double get _now => _clock.elapsedMicroseconds / 1e6;

  /// Last touch per string: (fret, time).
  final _touches = <int, (int, double)>{};

  /// Where the remote's arrows point: string 1-6 and fret 0-12.
  var _cursor = (3, 0);
  bool _neckFocused = false;

  static const _frets = 12;

  /// Arrows move along the neck as it is drawn on screen; OK plays the note.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final settings = SettingsScope.of(context);
    final key = e.logicalKey;
    final (string, fret) = _cursor;
    if (isOkKey(key)) {
      if (e is KeyDownEvent) _tap(string, fret);
      return KeyEventResult.handled;
    }
    // Screen rows: the thin string (1) is on top unless the setting flips it.
    final down = settings.thinStringOnTop ? 1 : -1;
    // Frets grow to the right, or to the left for left-handed players.
    final right = settings.leftHanded ? -1 : 1;
    int? s, f;
    if (key == LogicalKeyboardKey.arrowUp) s = string - down;
    if (key == LogicalKeyboardKey.arrowDown) s = string + down;
    if (key == LogicalKeyboardKey.arrowRight) f = fret + right;
    if (key == LogicalKeyboardKey.arrowLeft) f = fret - right;
    if (s == null && f == null) return KeyEventResult.ignored;
    if (s != null && (s < 1 || s > 6)) {
      // Past the top row: let the focus go up to the back button.
      return key == LogicalKeyboardKey.arrowUp ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    setState(() => _cursor = (s ?? string, (f ?? fret).clamp(0, _frets)));
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      setState(() {});
      if (_touches.values.every((t) => _now - t.$2 > _ringSeconds)) _ticker.stop();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tap(int string, int fret) {
    AppServices.of(context).synth.play([
      SynthNote(midi: standardTuning[string - 1] + fret, string: string, durationMs: 2000),
    ]);
    setState(() => _touches[string] = (fret, _now));
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final settings = SettingsScope.of(context);
    final now = _now;
    final recent = {
      for (final e in _touches.entries)
        if (now - e.value.$2 < _ringSeconds) e.key: e.value,
    };
    final scene = NeckScene(
      dots: [
        for (final e in recent.entries)
          if (e.value.$1 > 0)
            NeckDot(
              string: e.key,
              fret: e.value.$1,
              finger: 0,
              opacity: (_ringSeconds - (now - e.value.$2)) / _ringSeconds,
              label: noteName(standardTuning[e.key - 1] + e.value.$1, serbian: t.language.isSerbian),
            ),
      ],
      openStrings: {for (final e in recent.entries) if (e.value.$1 == 0) e.key},
      openLabels: {
        for (final e in recent.entries)
          if (e.value.$1 == 0) e.key: noteName(standardTuning[e.key - 1], serbian: t.language.isSerbian),
      },
      pluckAge: {for (final e in recent.entries) e.key: now - e.value.$2},
      time: now,
      cursor: _neckFocused ? _cursor : null,
    );
    return Scaffold(
      body: AppBackground(
        theme: SettingsScope.of(context).colorTheme,
        child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(children: [
                IconButton(
                  tooltip: t.back,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(t.freePlay, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(t.freePlayHint, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ]),
            ),
            Expanded(
              child: Focus(
                autofocus: true,
                onKeyEvent: _onKey,
                onFocusChange: (f) => setState(() => _neckFocused = f),
                child: FretboardView(
                  scene: scene,
                  style: NeckStyle(
                    leftHanded: settings.leftHanded,
                    thinOnTop: settings.thinStringOnTop,
                    highContrast: settings.highContrast,
                    fretNumbers: settings.dotLabel == DotLabel.fret,
                  ),
                  onTap: _tap,
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
