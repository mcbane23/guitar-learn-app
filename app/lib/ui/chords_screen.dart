import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app.dart';
import '../audio/synth.dart';
import '../l10n/strings.dart';
import '../models/chord.dart';
import '../models/song.dart';
import '../music/pitch.dart';
import '../settings/settings.dart';
import 'common.dart';
import 'fretboard.dart';

/// Every chord used in the songs, shown on the same neck.
class ChordsScreen extends StatefulWidget {
  const ChordsScreen({super.key});

  @override
  State<ChordsScreen> createState() => _ChordsScreenState();
}

class _ChordsScreenState extends State<ChordsScreen> with SingleTickerProviderStateMixin, LandscapeScreen {
  late final Ticker _ticker;
  double _now = 0;
  double _strummedAt = -10;
  String? _selected;

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

  void _pick(ChordShape shape) {
    setState(() {
      _selected = shape.name;
      _strummedAt = _now;
    });
    final synth = AppServices.of(context).synth;
    final strings = shape.playedStrings;
    synth.play([
      for (var k = 0; k < strings.length; k++)
        SynthNote(
          midi: standardTuning[strings[k] - 1] + shape.fretOn(strings[k]),
          delayMs: k * 25.0,
          durationMs: 2500,
          string: strings[k],
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final settings = SettingsScope.of(context);
    final chords = AppServices.of(context).songs.chords;
    final shape = _selected == null ? null : chords[_selected!];
    final age = _now - _strummedAt;
    final style = NeckStyle(
      leftHanded: settings.leftHanded,
      thinOnTop: settings.thinStringOnTop,
      highContrast: settings.highContrast,
    );
    String? name(int s, int f) =>
        settings.showNoteNames ? noteName(standardTuning[s - 1] + f, serbian: t.language.isSerbian) : null;

    final scene = shape == null
        ? const NeckScene()
        : NeckScene(
            dots: [
              for (var s = 1; s <= 6; s++)
                if (shape.fretOn(s) > 0)
                  NeckDot(string: s, fret: shape.fretOn(s), finger: shape.fingerOn(s), label: name(s, shape.fretOn(s))),
            ],
            openStrings: {for (var s = 1; s <= 6; s++) if (shape.fretOn(s) == 0) s},
            openLabels: {
              for (var s = 1; s <= 6; s++)
                if (shape.fretOn(s) == 0 && name(s, 0) != null) s: name(s, 0)!,
            },
            mutedStrings: {for (var s = 1; s <= 6; s++) if (!shape.plays(s)) s},
            pluckAge: {
              for (final (k, s) in shape.playedStrings.indexed) s: age - k * 0.025,
            },
            strum: Strum.down,
            strumProgress: age / 0.3,
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
                  tooltip: t.back,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(t.chords, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    shape == null ? t.tapChord : t.fingers,
                    style: const TextStyle(fontSize: 15, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (shape != null)
                  Text(shape.name, style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
              ]),
            ),
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final (i, n) in chords.names.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: FocusCard(
                        width: 72,
                        autofocus: i == 0,
                        color: n == _selected ? Theme.of(context).colorScheme.primary : null,
                        onTap: () => _pick(chords[n]!),
                        child: Center(
                          child: Text(n,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: n == _selected ? Theme.of(context).colorScheme.onPrimary : null,
                              )),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: FretboardView(scene: scene, style: style)),
          ],
        ),
      ),
    );
  }
}
