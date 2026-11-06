import 'package:flutter/material.dart';

/// Color themes the user can pick in settings. All are dark so the guitar
/// neck and white text stay easy to see.
enum AppColorTheme { classic, frost, forest, plum }

class _Palette {
  const _Palette({
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.surface,
    this.containers,
  });

  final Color accent;
  final Color onAccent;
  final Color background;
  final Color surface;

  /// Card colors from lowest to highest. null = derived from the accent.
  final List<Color>? containers;
}

const _palettes = {
  // The original look: warm orange on deep navy.
  AppColorTheme.classic: _Palette(
    accent: Color(0xFFFF7A1A),
    onAccent: Colors.white,
    background: Color(0xFF0E1020),
    surface: Color(0xFF141726),
  ),
  // Cool: light blue on dark silver.
  AppColorTheme.frost: _Palette(
    accent: Color(0xFF8FD3FF),
    onAccent: Color(0xFF0B1A26),
    background: Color(0xFF16191D),
    surface: Color(0xFF1E2227),
    containers: [Color(0xFF1A1D22), Color(0xFF22262C), Color(0xFF292E35), Color(0xFF323841), Color(0xFF3C434D)],
  ),
  AppColorTheme.forest: _Palette(
    accent: Color(0xFF4CC38A),
    onAccent: Color(0xFF06210F),
    background: Color(0xFF0B1712),
    surface: Color(0xFF11211A),
  ),
  AppColorTheme.plum: _Palette(
    accent: Color(0xFFC39BFF),
    onAccent: Color(0xFF1C0D35),
    background: Color(0xFF110D1D),
    surface: Color(0xFF191429),
  ),
};

extension AppColorThemeX on AppColorTheme {
  Color get accent => _palettes[this]!.accent;
  Color get background => _palettes[this]!.background;
  Color get surface => _palettes[this]!.surface;
}

ThemeData buildTheme([AppColorTheme theme = AppColorTheme.classic]) {
  final p = _palettes[theme]!;
  var scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: Brightness.dark).copyWith(
    surface: p.surface,
    primary: p.accent,
    onPrimary: p.onAccent,
  );
  final c = p.containers;
  if (c != null) {
    scheme = scheme.copyWith(
      surfaceContainerLowest: c[0],
      surfaceContainerLow: c[1],
      surfaceContainer: c[2],
      surfaceContainerHigh: c[3],
      surfaceContainerHighest: c[4],
      secondaryContainer: c[4],
      onSecondaryContainer: Colors.white,
    );
  }
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  // With a TV remote the only way to know where you are is the focus, so
  // every button gets a thick white outline when it is selected.
  final focusRing = ButtonStyle(side: _focusSide, overlayColor: _focusOverlay);
  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    visualDensity: VisualDensity.comfortable,
    focusColor: Colors.white.withValues(alpha: 0.24),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ).merge(focusRing),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 18)).merge(focusRing),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: focusRing),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(52, 52), iconSize: 28).merge(focusRing),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(overlayColor: _focusOverlay)),
    chipTheme: base.chipTheme.copyWith(side: const _ChipFocusSide()),
  );
}

const _ring = BorderSide(color: Colors.white, width: 3, strokeAlign: BorderSide.strokeAlignOutside);

final _focusSide = WidgetStateProperty.resolveWith<BorderSide?>(
  (states) => states.contains(WidgetState.focused) ? _ring : null,
);

final _focusOverlay = WidgetStateProperty.resolveWith<Color?>(
  (states) => states.contains(WidgetState.focused) ? Colors.white.withValues(alpha: 0.22) : null,
);

/// Chips get the same white outline when selected with the remote.
class _ChipFocusSide extends WidgetStateBorderSide {
  const _ChipFocusSide();

  @override
  BorderSide? resolve(Set<WidgetState> states) =>
      states.contains(WidgetState.focused) ? _ring : const BorderSide(color: Colors.white24);
}
