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
import 'themes.dart';

/// Every chord used in the songs, shown on the same neck.
class ChordsScreen extends StatefulWidget {
  const ChordsScreen({super.key});

  @override
  State<ChordsScreen> createState() => _ChordsScreenState();
}

class _ChordsScreenState extends State<ChordsScreen> with SingleTickerProviderStateMixin, LandscapeScreen {
  /// Redraws the neck while the strings still ring, then stops, so an open
  /// chord page does not keep the device busy at 60 frames a second.
  late final Ticker _ticker;
  final _clock = Stopwatch()..start();
  double _strummedAt = -10;
  String? _selected;

  /// How long the strings glow after a strum.
  static const _ringSeconds = 1.3;

  double get _now => _clock.elapsedMicroseconds / 1e6;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      setState(() {});
      if (_now - _strummedAt > _ringSeconds) _ticker.stop();
    });
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
    if (!_ticker.isActive) _ticker.start();
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
      fretNumbers: settings.dotLabel == DotLabel.fret,
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
              for (final (k, s) in shape.playedStrings.indexed)
                if (age - k * 0.025 < _ringSeconds) s: age - k * 0.025,
            },
            strum: Strum.down,
            strumProgress: age / 0.3,
            time: age,
          );

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: AppBackground(
        theme: settings.colorTheme,
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
                Text(t.chords, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    shape == null
                        ? t.tapChord
                        : settings.dotLabel == DotLabel.fret
                            ? t.fretNumbersLegend
                            : t.fingers,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (shape != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.45), blurRadius: 18)],
                    ),
                    child: Text(shape.name, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: scheme.onPrimary)),
                  ),
              ]),
            ),
            // All chords as cards with a small diagram each. On a TV or a
            // tablet they sit in two rows, so up and down on the remote
            // move between them too; on a phone one row scrolls sideways.
            LayoutBuilder(builder: (context, box) {
              final rows = box.maxWidth >= 720 ? 2 : 1;
              const card = 104.0;
              return SizedBox(
                height: rows * card + (rows - 1) * 8 + 8,
                child: GridView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: rows,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: card / (card + 16),
                  ),
                  itemCount: chords.names.length,
                  itemBuilder: (context, i) {
                    final n = chords.names[i];
                    final selected = n == _selected;
                    return FocusCard(
                      autofocus: i == 0,
                      radius: 16,
                      color: selected ? scheme.primary.withValues(alpha: 0.22) : null,
                      onTap: () => _pick(chords[n]!),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                        child: Column(children: [
                          Text(
                            n,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: selected ? scheme.primary : null,
                            ),
                          ),
                          Expanded(
                            child: ChordDiagram(
                              shape: chords[n]!,
                              leftHanded: settings.leftHanded,
                              color: Colors.white,
                              fingerColors: style.fingerColors,
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              );
            }),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: GlassPanel(
                  color: glassLow,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                  child: FretboardView(scene: scene, style: style),
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

/// A small chord box like in a songbook: strings as vertical lines, the
/// first few frets as horizontal ones, a dot for each finger, and an x or o
/// above a string that is muted or open. Drawn from the thick string on the
/// left (the other way round for a left-handed player).
class ChordDiagram extends StatelessWidget {
  const ChordDiagram({super.key, required this.shape, this.leftHanded = false, this.color = Colors.white, this.fingerColors});

  final ChordShape shape;
  final bool leftHanded;
  final Color color;

  /// One color per finger (index 0 unused); without it every dot is [color].
  final List<Color>? fingerColors;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.infinite, painter: _ChordDiagramPainter(shape, leftHanded, color, fingerColors));
  }
}

class _ChordDiagramPainter extends CustomPainter {
  _ChordDiagramPainter(this.shape, this.leftHanded, this.color, this.fingerColors);

  final ChordShape shape;
  final bool leftHanded;
  final Color color;
  final List<Color>? fingerColors;

  static const _frets = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final played = [for (var s = 1; s <= 6; s++) if (shape.fretOn(s) > 0) shape.fretOn(s)];
    final highest = played.isEmpty ? 1 : played.reduce((a, b) => a > b ? a : b);
    // The box starts at the first fret unless the chord sits higher up.
    final base = highest <= _frets ? 1 : played.reduce((a, b) => a < b ? a : b);
    final top = size.height * 0.2;
    final left = size.width * 0.14;
    final right = size.width * 0.86;
    final bottom = size.height * 0.96;
    final stringGap = (right - left) / 5;
    final fretGap = (bottom - top) / _frets;
    final line = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = color;

    double x(int string) {
      // String 6 (thick) on the left; the thin one on the right.
      final i = leftHanded ? string - 1 : 6 - string;
      return left + i * stringGap;
    }

    for (var s = 1; s <= 6; s++) {
      canvas.drawLine(Offset(x(s), top), Offset(x(s), bottom), line);
    }
    for (var f = 0; f <= _frets; f++) {
      final y = top + f * fretGap;
      canvas.drawLine(Offset(left, y), Offset(right, y), f == 0 && base == 1 ? (Paint()..color = color..strokeWidth = 3) : line);
    }
    final dotRadius = stringGap * 0.34;
    final textStyle = TextStyle(color: color, fontSize: size.height * 0.16, fontWeight: FontWeight.w700);
    for (var s = 1; s <= 6; s++) {
      final fret = shape.fretOn(s);
      if (fret > 0) {
        final finger = shape.fingerOn(s);
        final colors = fingerColors;
        final dot = colors == null || finger <= 0 ? fill : (Paint()..color = colors[finger.clamp(0, colors.length - 1)]);
        canvas.drawCircle(Offset(x(s), top + (fret - base + 0.5) * fretGap), dotRadius, dot);
      } else {
        _text(canvas, fret == 0 ? 'o' : 'x', Offset(x(s), top * 0.45), textStyle);
      }
    }
    if (base > 1) {
      _text(canvas, '$base', Offset(left - size.width * 0.08, top + fretGap * 0.5), textStyle.copyWith(fontSize: size.height * 0.14));
    }
  }

  void _text(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_ChordDiagramPainter old) =>
      old.shape != shape || old.leftHanded != leftHanded || old.color != color || old.fingerColors != fingerColors;
}
