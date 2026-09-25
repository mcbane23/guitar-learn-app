import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app.dart';
import '../audio/synth.dart';
import '../l10n/strings.dart';
import '../music/pitch.dart';
import '../settings/settings.dart';
import 'common.dart';
import 'fretboard.dart';

/// Tap any fret to hear that note.
class FreePlayScreen extends StatefulWidget {
  const FreePlayScreen({super.key});

  @override
  State<FreePlayScreen> createState() => _FreePlayScreenState();
}

class _FreePlayScreenState extends State<FreePlayScreen> with SingleTickerProviderStateMixin, LandscapeScreen {
  late final Ticker _ticker;
  double _now = 0;

  /// Last touch per string: (fret, time).
  final _touches = <int, (int, double)>{};

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => setState(() => _now = e.inMicroseconds / 1e6))..start();
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
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final settings = SettingsScope.of(context);
    final recent = {
      for (final e in _touches.entries)
        if (_now - e.value.$2 < 1.5) e.key: e.value,
    };
    final scene = NeckScene(
      dots: [
        for (final e in recent.entries)
          if (e.value.$1 > 0)
            NeckDot(
              string: e.key,
              fret: e.value.$1,
              finger: 0,
              opacity: (1.5 - (_now - e.value.$2)) / 1.5,
              label: noteName(standardTuning[e.key - 1] + e.value.$1, serbian: t.language.isSerbian),
            ),
      ],
      openStrings: {for (final e in recent.entries) if (e.value.$1 == 0) e.key},
      openLabels: {
        for (final e in recent.entries)
          if (e.value.$1 == 0) e.key: noteName(standardTuning[e.key - 1], serbian: t.language.isSerbian),
      },
      pluckAge: {for (final e in recent.entries) e.key: _now - e.value.$2},
      time: _now,
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(children: [
                IconButton(
                  autofocus: true,
                  tooltip: t.back,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(t.freePlay, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(t.freePlayHint, style: const TextStyle(fontSize: 15, color: Colors.white70)),
                ),
              ]),
            ),
            Expanded(
              child: FretboardView(
                scene: scene,
                style: NeckStyle(
                  leftHanded: settings.leftHanded,
                  thinOnTop: settings.thinStringOnTop,
                  highContrast: settings.highContrast,
                ),
                onTap: _tap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
