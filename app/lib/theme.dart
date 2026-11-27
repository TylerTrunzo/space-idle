import 'package:material_ui/material_ui.dart';

/// The Mission Control palette; the only place the app spells a color.
///
/// Color never carries state on its own: widgets pair it with an icon and
/// text (see the accessibility constraint in the stage 2 plan).
abstract final class Palette {
  /// App and map background.
  static const Color background = Color(0xFF0B1020);

  /// Panels, sheets, cards and bars.
  static const Color panel = Color(0xFF111A30);

  /// Hairlines and panel borders.
  static const Color border = Color(0xFF1F2D4D);

  /// Anything the player can tap.
  static const Color cyan = Color(0xFF5FE1FF);

  /// Warnings: storage nearly full, an input running low.
  static const Color amber = Color(0xFFFFB547);

  /// Deficits and failures.
  static const Color red = Color(0xFFFF6470);

  /// Surpluses and successes.
  static const Color green = Color(0xFF63E6A4);

  /// Body text.
  static const Color text = Color(0xFFCFE3FF);

  /// Secondary text and labels.
  static const Color muted = Color(0xFF8EA3C9);
}

/// Star-map colors: one per body type, plus the star.
///
/// A body's ownership is never told by its color alone: the map adds a
/// ring and an "Unclaimed" label (see the star map).
abstract final class BodyPalette {
  /// The system's star.
  static const Color star = Color(0xFFFFD27A);

  static const Color _rocky = Color(0xFFB08968);
  static const Color _asteroid = Color(0xFF8A7A6A);
  static const Color _iceMoon = Color(0xFF9FE8FF);
  static const Color _gasGiant = Color(0xFFC56CFF);
  static const Color _volcanic = Color(0xFFFF8A5B);
  static const Color _kuiper = Color(0xFFA9B8D0);

  /// The color of a body of type [typeId]; [Palette.muted] for a type the
  /// map has no color for.
  static Color forType(String typeId) => switch (typeId) {
    'rocky' => _rocky,
    'asteroid_belt' => _asteroid,
    'ice_moon' => _iceMoon,
    'gas_giant' => _gasGiant,
    'volcanic' => _volcanic,
    'kuiper' => _kuiper,
    _ => Palette.muted,
  };
}

/// The app's single dark theme, built from [Palette].
ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Palette.cyan,
    onPrimary: Palette.background,
    secondary: Palette.cyan,
    onSecondary: Palette.background,
    tertiary: Palette.green,
    onTertiary: Palette.background,
    error: Palette.red,
    onError: Palette.background,
    surface: Palette.panel,
    onSurface: Palette.text,
    onSurfaceVariant: Palette.muted,
    surfaceContainerLowest: Palette.background,
    surfaceContainerLow: Palette.panel,
    surfaceContainer: Palette.panel,
    surfaceContainerHigh: Palette.panel,
    surfaceContainerHighest: Palette.border,
    outline: Palette.border,
    outlineVariant: Palette.border,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.background,
    canvasColor: Palette.background,
    dividerColor: Palette.border,
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
  );
}
