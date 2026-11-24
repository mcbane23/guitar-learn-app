import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/song.dart';

/// A finger dot to draw on the neck.
class NeckDot {
  const NeckDot({
    required this.string,
    required this.fret,
    required this.finger,
    this.opacity = 1,
    this.approach = 1,
    this.label,
  });

  final int string;
  final int fret;
  final int finger;
  final double opacity;

  /// 0 = far in the future, 1 = press now. Upcoming dots show a closing ring.
  final double approach;

  /// Optional note name shown under the finger number.
  final String? label;
}

/// Everything the neck shows in one frame.
class NeckScene {
  const NeckScene({
    this.dots = const [],
    this.pluckAge = const {},
    this.openStrings = const {},
    this.mutedStrings = const {},
    this.openLabels = const {},
    this.strum,
    this.strumProgress = 0,
    this.pulse = false,
    this.time = 0,
    this.cursor,
  });

  final List<NeckDot> dots;

  /// Seconds since each string was plucked (only recently plucked strings).
  final Map<int, double> pluckAge;

  /// Strings to play open (shown with O at the nut).
  final Set<int> openStrings;

  /// Strings not to play (shown with X at the nut).
  final Set<int> mutedStrings;

  /// Note names for open strings, when note names are on.
  final Map<int, String> openLabels;

  final Strum? strum;

  /// 0..1 progress of the strum sweep arrow.
  final double strumProgress;

  /// Pulse the active dots (wait mode is waiting for the player).
  final bool pulse;

  /// Seconds, for animations.
  final double time;

  /// The string and fret picked with the remote's arrows (fret 0 = open
  /// string), drawn as a white ring. Null when there is none.
  final (int string, int fret)? cursor;

  /// Whether something on the neck is moving (glowing strings, a strum
  /// arrow, pulsing dots), so a new frame would look different.
  bool get animates => pluckAge.isNotEmpty || pulse || (strum != null && strumProgress < 1);

  /// True when drawing [other] would give the same picture as this scene,
  /// so the neck can skip a repaint (for example while paused).
  bool looksLike(NeckScene other) {
    if (animates || other.animates) return false;
    if (dots.length != other.dots.length ||
        strum != other.strum ||
        openStrings.length != other.openStrings.length ||
        mutedStrings.length != other.mutedStrings.length ||
        openLabels.length != other.openLabels.length ||
        cursor != other.cursor) {
      return false;
    }
    for (var i = 0; i < dots.length; i++) {
      final a = dots[i], b = other.dots[i];
      if (a.string != b.string ||
          a.fret != b.fret ||
          a.finger != b.finger ||
          a.opacity != b.opacity ||
          a.approach != b.approach ||
          a.label != b.label) {
        return false;
      }
    }
    if (!openStrings.containsAll(other.openStrings) || !mutedStrings.containsAll(other.mutedStrings)) return false;
    for (final e in openLabels.entries) {
      if (other.openLabels[e.key] != e.value) return false;
    }
    return true;
  }
}

class NeckStyle {
  const NeckStyle({
    this.leftHanded = false,
    this.thinOnTop = true,
    this.highContrast = false,
    this.frets = 12,
    this.fretNumbers = false,
  });

  final bool leftHanded;
  final bool thinOnTop;
  final bool highContrast;

  /// Write the fret number in each dot instead of the finger number.
  final bool fretNumbers;

  /// How many frets the neck shows (12 for the built-in songs, up to 24
  /// for songs that go higher).
  final int frets;

  @override
  bool operator ==(Object other) =>
      other is NeckStyle &&
      other.leftHanded == leftHanded &&
      other.thinOnTop == thinOnTop &&
      other.highContrast == highContrast &&
      other.frets == frets &&
      other.fretNumbers == fretNumbers;

  @override
  int get hashCode => Object.hash(leftHanded, thinOnTop, highContrast, frets, fretNumbers);

  List<Color> get fingerColors => highContrast
      ? const [Color(0xFFFFFFFF), Color(0xFF00B7FF), Color(0xFF00E676), Color(0xFFFFEA00), Color(0xFFFF1744)]
      : const [Color(0xFFF2C94C), Color(0xFF2F80ED), Color(0xFF27AE60), Color(0xFFF2994A), Color(0xFFEB5757)];

  Color fingerColor(int finger) => fingerColors[finger.clamp(0, 4)];

  Color fingerTextColor(int finger) =>
      highContrast && (finger == 0 || finger == 2 || finger == 3) ? Colors.black : Colors.white;

  Color get glow => highContrast ? const Color(0xFFFFFFFF) : const Color(0xFFFFD54F);
}

/// Layout of the neck inside a given size. Shared by the painter and tap
/// handling so both agree on where each string and fret is.
class NeckGeometry {
  NeckGeometry(this.size, this.style, {int? fretCount})
      : frets = fretCount ?? style.frets {
    nutWidth = math.max(28.0, size.width * 0.07);
    final right = size.width - math.max(8.0, size.width * 0.01);
    neckLeft = nutWidth;
    neckRight = right;
    top = size.height * 0.06;
    bottom = size.height * 0.88;
    final neckLen = neckRight - neckLeft;
    // Real guitar fret spacing: each fret is 2^(1/12) narrower than the last.
    final scale = neckLen / (1 - math.pow(2, -frets / 12));
    fretX = [for (var n = 0; n <= frets; n++) neckLeft + scale * (1 - math.pow(2, -n / 12))];
    spacing = (bottom - top) / 6;
  }

  final Size size;
  final NeckStyle style;
  final int frets;
  late final double nutWidth;
  late final double neckLeft;
  late final double neckRight;
  late final double top;
  late final double bottom;
  late final double spacing;

  /// x of each fret wire in unmirrored layout; index 0 is the nut.
  late final List<double> fretX;

  double mx(double x) => style.leftHanded ? size.width - x : x;

  /// Screen row (0 = top) of a string.
  int row(int string) => style.thinOnTop ? string - 1 : 6 - string;

  double stringY(int string) => top + spacing * (row(string) + 0.5);

  /// Center of the space where a finger presses [fret] (1..frets).
  double fretCenterX(int fret) {
    if (fret <= 0) return mx(nutWidth * 0.5);
    final a = fretX[fret - 1], b = fretX[fret];
    return mx(a + (b - a) * 0.6);
  }

  double dotRadius(int fret) {
    final f = fret.clamp(1, frets);
    final w = fretX[f] - fretX[f - 1];
    return math.min(spacing * 0.46, w * 0.42);
  }

  /// Which string and fret is at [p]; fret 0 when touching the nut area.
  (int string, int fret)? hit(Offset p) {
    if (p.dy < top - spacing * 0.3 || p.dy > bottom + spacing * 0.3) return null;
    final r = ((p.dy - top) / spacing).floor().clamp(0, 5);
    final string = style.thinOnTop ? r + 1 : 6 - r;
    final x = style.leftHanded ? size.width - p.dx : p.dx;
    if (x < neckLeft) return (string, 0);
    for (var n = 1; n <= frets; n++) {
      if (x < fretX[n]) return (string, n);
    }
    return null;
  }
}

class FretboardPainter extends CustomPainter {
  FretboardPainter({required this.scene, required this.style});

  final NeckScene scene;
  final NeckStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final g = NeckGeometry(size, style);
    _drawWood(canvas, g);
    _drawStrings(canvas, g);
    _drawNutMarks(canvas, g);
    _drawStrum(canvas, g);
    for (final d in scene.dots) {
      _drawDot(canvas, g, d);
    }
    _drawCursor(canvas, g);
    _drawFretNumbers(canvas, g);
  }

  void _drawCursor(Canvas canvas, NeckGeometry g) {
    final cursor = scene.cursor;
    if (cursor == null) return;
    final (string, fret) = cursor;
    final c = Offset(fret <= 0 ? g.mx(g.nutWidth * 0.45) : g.fretCenterX(fret), g.stringY(string));
    final r = fret <= 0 ? math.min(g.spacing * 0.42, g.nutWidth * 0.45) : g.dotRadius(fret) * 1.1;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(3.0, r * 0.18)
        ..color = Colors.white,
    );
  }

  void _drawWood(Canvas canvas, NeckGeometry g) {
    final left = math.min(g.mx(g.neckLeft), g.mx(g.neckRight));
    final right = math.max(g.mx(g.neckLeft), g.mx(g.neckRight));
    final board = Rect.fromLTRB(left, g.top, right, g.bottom);
    canvas.drawRect(
      board,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: style.highContrast
              ? const [Color(0xFF2B2B2B), Color(0xFF1A1A1A)]
              : const [Color(0xFF6B3F1F), Color(0xFF4A2A14), Color(0xFF5C3519)],
        ).createShader(board),
    );

    // Position markers at frets 3, 5, 7, 9, 15, 17, 19, 21 and double ones at 12 and 24.
    final inlay = Paint()..color = style.highContrast ? const Color(0xFF555555) : const Color(0xFFE9DFC7);
    final midY = (g.top + g.bottom) / 2;
    final r = math.min(g.spacing * 0.18, (g.fretX[g.frets] - g.fretX[g.frets - 1]) * 0.3);
    for (final f in const [3, 5, 7, 9, 15, 17, 19, 21]) {
      if (f > g.frets) break;
      canvas.drawCircle(Offset(g.mx((g.fretX[f - 1] + g.fretX[f]) / 2), midY), r, inlay);
    }
    for (final f in const [12, 24]) {
      if (f > g.frets) break;
      final x = g.mx((g.fretX[f - 1] + g.fretX[f]) / 2);
      canvas.drawCircle(Offset(x, g.top + g.spacing * 1.5), r, inlay);
      canvas.drawCircle(Offset(x, g.bottom - g.spacing * 1.5), r, inlay);
    }

    // Nut.
    final nutW = math.max(6.0, g.spacing * 0.22);
    final nutX = g.mx(g.neckLeft);
    canvas.drawRect(
      Rect.fromLTRB(nutX - nutW / 2, g.top, nutX + nutW / 2, g.bottom),
      Paint()..color = const Color(0xFFF3EBD6),
    );

    // Frets.
    final fret = Paint()
      ..color = const Color(0xFFC9CED6)
      ..strokeWidth = math.max(2.0, g.spacing * 0.08);
    for (var n = 1; n < g.fretX.length; n++) {
      final x = g.mx(g.fretX[n]);
      canvas.drawLine(Offset(x, g.top), Offset(x, g.bottom), fret);
    }
  }

  void _drawStrings(Canvas canvas, NeckGeometry g) {
    final x0 = g.mx(g.neckLeft);
    final x1 = g.mx(g.neckRight);
    for (var s = 1; s <= 6; s++) {
      final y = g.stringY(s);
      final width = (1.2 + (s - 1) * 0.65) * (g.spacing / 40).clamp(0.7, 2.0);
      final wound = s >= 4;
      final base = wound ? const Color(0xFFD8B26A) : const Color(0xFFE8E8E8);
      final age = scene.pluckAge[s];
      if (age != null && age >= 0 && age < 1.2) {
        final strength = math.exp(-age * 2.5);
        // Glow.
        canvas.drawLine(
          Offset(x0, y),
          Offset(x1, y),
          Paint()
            ..color = style.glow.withValues(alpha: 0.75 * strength)
            ..strokeWidth = width + g.spacing * 0.45 * strength
            ..strokeCap = StrokeCap.round
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.spacing * 0.18),
        );
        // Vibration: a standing wave that fades out.
        final amp = g.spacing * 0.16 * math.exp(-age * 5);
        final phase = math.sin(scene.time * 2 * math.pi * 14);
        final path = Path()..moveTo(x0, y);
        const steps = 48;
        for (var k = 1; k <= steps; k++) {
          final t = k / steps;
          path.lineTo(x0 + (x1 - x0) * t, y + amp * phase * math.sin(math.pi * t));
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Color.lerp(base, style.glow, strength)!
            ..strokeWidth = width * (1 + 0.6 * strength),
        );
      } else {
        canvas.drawLine(
          Offset(x0, y),
          Offset(x1, y),
          Paint()
            ..color = base
            ..strokeWidth = width,
        );
      }
    }
  }

  void _drawNutMarks(Canvas canvas, NeckGeometry g) {
    final x = g.mx(g.nutWidth * 0.45);
    final r = math.min(g.spacing * 0.34, g.nutWidth * 0.36);
    for (final s in scene.openStrings) {
      final y = g.stringY(s);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.3
          ..color = style.fingerColor(0),
      );
      final label = scene.openLabels[s];
      if (label != null) _text(canvas, label, Offset(x, y), r * 0.9, style.fingerColor(0));
    }
    final xPaint = Paint()
      ..color = const Color(0xFFBDBDBD)
      ..strokeWidth = r * 0.28
      ..strokeCap = StrokeCap.round;
    for (final s in scene.mutedStrings) {
      final y = g.stringY(s);
      final d = r * 0.65;
      canvas.drawLine(Offset(x - d, y - d), Offset(x + d, y + d), xPaint);
      canvas.drawLine(Offset(x - d, y + d), Offset(x + d, y - d), xPaint);
    }
  }

  void _drawStrum(Canvas canvas, NeckGeometry g) {
    final strum = scene.strum;
    if (strum == null || scene.strumProgress >= 1) return;
    // A down strum goes from the thick string to the thin one.
    final from = strum == Strum.down ? g.stringY(6) : g.stringY(1);
    final to = strum == Strum.down ? g.stringY(1) : g.stringY(6);
    final t = Curves.easeOut.transform(scene.strumProgress.clamp(0, 1));
    final y = from + (to - from) * t;
    final x = g.mx(g.fretX[10] + (g.fretX[12] - g.fretX[10]) / 2);
    final alpha = (1 - scene.strumProgress).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = style.glow.withValues(alpha: 0.85 * alpha)
      ..strokeWidth = g.spacing * 0.22
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, from), Offset(x, y), paint);
    final dir = (to - from).sign;
    final head = g.spacing * 0.55;
    final tip = Offset(x, y + dir * head * 0.3);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(x - head * 0.6, y - dir * head * 0.5)
      ..lineTo(x + head * 0.6, y - dir * head * 0.5)
      ..close();
    canvas.drawPath(path, Paint()..color = style.glow.withValues(alpha: alpha));
  }

  void _drawDot(Canvas canvas, NeckGeometry g, NeckDot d) {
    if (d.fret <= 0 || d.fret > g.frets) return;
    final c = Offset(g.fretCenterX(d.fret), g.stringY(d.string));
    final r = g.dotRadius(d.fret);
    final color = style.fingerColor(d.finger);
    final o = d.opacity.clamp(0.0, 1.0);
    if (d.approach < 1) {
      // Closing ring: the note is coming; it is due when the ring reaches the dot.
      canvas.drawCircle(
        c,
        r * (1 + 1.3 * (1 - d.approach)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16
          ..color = color.withValues(alpha: 0.9 * o),
      );
    }
    var rr = r;
    if (scene.pulse && d.approach >= 1) {
      rr = r * (1 + 0.08 * math.sin(scene.time * 2 * math.pi * 1.5));
      canvas.drawCircle(
        c,
        rr * 1.35,
        Paint()
          ..color = style.glow.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.3),
      );
    }
    canvas.drawCircle(c.translate(0, rr * 0.08), rr, Paint()..color = Colors.black.withValues(alpha: 0.35 * o));
    canvas.drawCircle(c, rr, Paint()..color = color.withValues(alpha: o));
    canvas.drawCircle(
      c,
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rr * 0.1
        ..color = Colors.white.withValues(alpha: 0.9 * o),
    );
    final textColor = style.fingerTextColor(d.finger).withValues(alpha: o);
    // The dot keeps its finger color either way; only the number changes.
    final number = style.fretNumbers ? '${d.fret}' : (d.finger > 0 ? '${d.finger}' : '');
    // Two digits (frets 10 and up) need smaller text to stay inside the dot.
    final fit = number.length > 1 ? 0.78 : 1.0;
    if (d.label != null) {
      _text(canvas, number, c.translate(0, -rr * 0.2), rr * 0.95 * fit, textColor);
      _text(canvas, d.label!, c.translate(0, rr * 0.5), rr * 0.55, textColor);
    } else if (number.isNotEmpty) {
      _text(canvas, number, c, rr * 1.15 * fit, textColor);
    }
  }

  void _drawFretNumbers(Canvas canvas, NeckGeometry g) {
    final y = g.bottom + (g.size.height - g.bottom) * 0.5;
    final size = math.min(g.spacing * 0.42, (g.size.height - g.bottom) * 0.7);
    for (var n = 1; n <= g.frets; n++) {
      final x = g.mx((g.fretX[n - 1] + g.fretX[n]) / 2);
      final marked = n == 3 || n == 5 || n == 7 || n == 9 || n == 12 || n == 15 || n == 17 || n == 19 || n == 21 || n == 24;
      final width = g.fretX[n] - g.fretX[n - 1];
      _text(canvas, '$n', Offset(x, y), math.min(size, width * 0.55), marked ? Colors.white70 : Colors.white38);
    }
  }

  void _text(Canvas canvas, String text, Offset center, double fontSize, Color color) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w800, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(FretboardPainter old) => style != old.style || !scene.looksLike(old.scene);
}

/// The full-width guitar neck. [onTap] gets the string and fret touched.
class FretboardView extends StatelessWidget {
  const FretboardView({super.key, required this.scene, required this.style, this.onTap});

  final NeckScene scene;
  final NeckStyle style;
  final void Function(int string, int fret)? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTap == null
            ? null
            : (d) {
                final hit = NeckGeometry(size, style).hit(d.localPosition);
                if (hit != null) onTap!(hit.$1, hit.$2);
              },
        child: CustomPaint(size: size, painter: FretboardPainter(scene: scene, style: style)),
      );
    });
  }
}
