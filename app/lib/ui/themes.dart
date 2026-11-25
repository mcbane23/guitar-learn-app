import 'package:flutter/material.dart';

/// Color themes the user can pick in settings. All are dark so the guitar
/// neck and white text stay easy to see: the "night scene" look is a deep
/// background with a soft glow in two colors, and translucent cards on top.
enum AppColorTheme { classic, frost, forest, plum }

class _Palette {
  const _Palette({
    required this.accent,
    required this.onAccent,
    required this.secondary,
    required this.background,
    required this.backgroundTop,
    required this.glowA,
    required this.glowB,
  });

  /// The main color: the play button, the chosen option, the title icon.
  final Color accent;
  final Color onAccent;

  /// The second color: the focus glow, a string that rings, upcoming notes.
  final Color secondary;

  /// The screen behind everything, and a lighter shade for the top of it.
  final Color background;
  final Color backgroundTop;

  /// The two soft lights painted over the background (top left, bottom right).
  final Color glowA;
  final Color glowB;
}

const _palettes = {
  // Warm amber and cool cyan on deep navy.
  AppColorTheme.classic: _Palette(
    accent: Color(0xFFFFB13D),
    onAccent: Color(0xFF1A1000),
    secondary: Color(0xFF4FD1FF),
    background: Color(0xFF070A16),
    backgroundTop: Color(0xFF0C1226),
    glowA: Color(0xFFFFB13D),
    glowB: Color(0xFF4FD1FF),
  ),
  // Cool: light blue on dark silver.
  AppColorTheme.frost: _Palette(
    accent: Color(0xFF8FD3FF),
    onAccent: Color(0xFF0B1A26),
    secondary: Color(0xFFC7E8FF),
    background: Color(0xFF111418),
    backgroundTop: Color(0xFF1A1F26),
    glowA: Color(0xFF8FD3FF),
    glowB: Color(0xFF7C8CFF),
  ),
  AppColorTheme.forest: _Palette(
    accent: Color(0xFF4CC38A),
    onAccent: Color(0xFF06210F),
    secondary: Color(0xFFB7F06B),
    background: Color(0xFF07120D),
    backgroundTop: Color(0xFF0E1F16),
    glowA: Color(0xFF4CC38A),
    glowB: Color(0xFF2FA9C9),
  ),
  AppColorTheme.plum: _Palette(
    accent: Color(0xFFC39BFF),
    onAccent: Color(0xFF1C0D35),
    secondary: Color(0xFFFF8AD8),
    background: Color(0xFF0D0916),
    backgroundTop: Color(0xFF181027),
    glowA: Color(0xFFC39BFF),
    glowB: Color(0xFFFF8AD8),
  ),
};

extension AppColorThemeX on AppColorTheme {
  Color get accent => _palettes[this]!.accent;
  Color get secondary => _palettes[this]!.secondary;
  Color get background => _palettes[this]!.background;
  Color get backgroundTop => _palettes[this]!.backgroundTop;
  Color get glowA => _palettes[this]!.glowA;
  Color get glowB => _palettes[this]!.glowB;

  /// A card color, for places that build their own cards.
  Color get surface => glass;
}

/// The translucent white that cards are made of ("glass" over the glow),
/// from the lowest, faintest level to the highest.
const glassLow = Color(0x0FFFFFFF);
const glass = Color(0x14FFFFFF);
const glassHigh = Color(0x1FFFFFFF);
const glassHighest = Color(0x2EFFFFFF);

/// The thin line around a card.
const glassBorder = Color(0x1AFFFFFF);

/// The ring around whatever the TV remote has selected.
const focusRing = Colors.white;

/// Radius of the big cards.
const cardRadius = 22.0;

ThemeData buildTheme([AppColorTheme theme = AppColorTheme.classic]) {
  final p = _palettes[theme]!;
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: Brightness.dark).copyWith(
    surface: p.backgroundTop,
    onSurface: const Color(0xFFF4F6FB),
    onSurfaceVariant: const Color(0xFFB4BBCC),
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.secondary,
    onSecondary: const Color(0xFF071018),
    primaryContainer: p.accent.withValues(alpha: 0.22),
    onPrimaryContainer: const Color(0xFFF4F6FB),
    // Cards and strips are translucent: the glow behind them shows through.
    surfaceContainerLowest: glassLow,
    surfaceContainerLow: glassLow,
    surfaceContainer: glass,
    surfaceContainerHigh: glassHigh,
    surfaceContainerHighest: glassHighest,
    secondaryContainer: glassHigh,
    onSecondaryContainer: const Color(0xFFF4F6FB),
    outline: glassBorder,
    outlineVariant: glassBorder,
    inverseSurface: const Color(0xFFF4F6FB),
    onInverseSurface: p.background,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  // With a TV remote the only way to know where you are is the focus, so
  // every button gets a thick white outline when it is selected.
  final focus = ButtonStyle(side: _focusSide, overlayColor: _focusOverlay);
  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    canvasColor: p.backgroundTop,
    visualDensity: VisualDensity.compact,
    focusColor: Colors.white.withValues(alpha: 0.12),
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ).merge(focus),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 16)).merge(focus),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: focus),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(46, 46), iconSize: 24).merge(focus),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        overlayColor: _focusOverlay,
        side: WidgetStatePropertyAll(BorderSide(color: glassBorder)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: glass,
      selectedColor: p.accent,
      side: const _ChipFocusSide(),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(color: p.onAccent),
      checkmarkColor: p.onAccent,
    ),
    cardTheme: CardThemeData(
      color: glass,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: const BorderSide(color: glassBorder),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF151A2E).withValues(alpha: 0.98),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: const Color(0xFF151A2E).withValues(alpha: 0.98),
      modalBackgroundColor: const Color(0xFF151A2E).withValues(alpha: 0.98),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF1B2140),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFFF4F6FB),
      contentTextStyle: TextStyle(color: p.background, fontSize: 16, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: glassBorder),
    listTileTheme: ListTileThemeData(iconColor: p.accent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onAccent : Colors.white70,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : glassHigh,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.focused) ? Colors.white : glassBorder,
      ),
      trackOutlineWidth: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused) ? 3 : 1),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: glassHigh,
      thumbColor: Colors.white,
      overlayColor: Colors.white.withValues(alpha: 0.2),
      trackHeight: 8,
      valueIndicatorColor: p.accent,
      valueIndicatorTextStyle: TextStyle(color: p.onAccent, fontWeight: FontWeight.w800),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glass,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: glassBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: glassBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.accent, width: 2)),
    ),
  );
}

const _ring = BorderSide(color: focusRing, width: 3, strokeAlign: BorderSide.strokeAlignOutside);

final _focusSide = WidgetStateProperty.resolveWith<BorderSide?>(
  (states) => states.contains(WidgetState.focused) ? _ring : null,
);

final _focusOverlay = WidgetStateProperty.resolveWith<Color?>(
  (states) => states.contains(WidgetState.focused) ? Colors.white.withValues(alpha: 0.14) : null,
);

/// Chips get the same white outline when selected with the remote.
class _ChipFocusSide extends WidgetStateBorderSide {
  const _ChipFocusSide();

  @override
  BorderSide? resolve(Set<WidgetState> states) =>
      states.contains(WidgetState.focused) ? _ring : const BorderSide(color: glassBorder);
}

/// The screen behind every page: the dark background with two soft lights,
/// one in the accent color at the top left and one in the second color at
/// the bottom right. Painted once; it never animates.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.theme, required this.child});

  final AppColorTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackgroundPainter(theme),
        child: child,
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.theme);

  final AppColorTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final p = _palettes[theme]!;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.backgroundTop, p.background],
        ).createShader(rect),
    );
    void light(Offset center, double radius, Color color, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    final r = size.longestSide;
    light(Offset(size.width * 0.12, -size.height * 0.05), r * 0.55, p.glowA, 0.26);
    light(Offset(size.width * 0.92, size.height * 1.05), r * 0.55, p.glowB, 0.22);
    light(Offset(size.width * 0.70, size.height * 0.15), r * 0.30, const Color(0xFF9A6BFF), 0.07);
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.theme != theme;
}
